#!/bin/bash
set -uo pipefail

# ==============================================================================
# 06-kde.sh - KDE Plasma Setup (FZF Menu + Robust Installation)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
export UNDO_SCRIPT="$SCRIPT_DIR/undo-desktop.sh"

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

section "Phase 6" "KDE Plasma Environment"

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Identifying user..."
DETECTED_USER=$(detect_user)
TARGET_USER="${DETECTED_USER:-${ARCH_SETUP_USER:-}}"
if [ -z "$TARGET_USER" ]; then
    read -t 30 -p "Target user: " TARGET_USER || { error "No target user. Set ARCH_SETUP_USER env var."; exit 1; }
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. Install KDE Plasma Base
# ------------------------------------------------------------------------------
section "Step 1/5" "Plasma Core"

log "Installing KDE Plasma Meta & Apps..."
KDE_PKGS="plasma-meta konsole dolphin kate qt6-multimedia-ffmpeg pipewire-jack sddm"
exe pacman -S --noconfirm --needed $KDE_PKGS
success "KDE Plasma installed."

# ------------------------------------------------------------------------------
# 2. Software Store & Network (Smart Mirror Selection)
# ------------------------------------------------------------------------------
section "Step 2/5" "Software Store & Network"

log "Configuring Discover & Flatpak..."

exe pacman -S --noconfirm --needed flatpak flatpak-kcm
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Network Detection Logic ---
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Timezone)"
elif [ "$CN_MIRROR" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Manual Env)"
elif [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    warn "DEBUG MODE: Forcing China Environment"
fi

# --- Mirror Configuration ---
if [ "$IS_CN_ENV" = true ]; then
    log "Enabling China Optimizations..."
    select_flathub_mirror
    success "Optimizations Enabled."
else
    log "Using Global Official Sources."
fi

# NOPASSWD for yay
setup_temp_sudoers

# ------------------------------------------------------------------------------
# 3. Install Dependencies (FZF Selection + Retry Logic)
# ------------------------------------------------------------------------------
section "Step 3/5" "KDE Dependencies"

LIST_FILE="$PARENT_DIR/kde-applist.txt"


if [ -f "$LIST_FILE" ]; then
    echo ""
    echo -e "   Selected List: ${BOLD}$LIST_FILE${NC}"
    echo -e "   ${H_YELLOW}>>> Default installation will start in 60 seconds.${NC}"
    echo -e "   ${H_RED}${BOLD}>>> WARNING: AUR packages may fail due to unstable network connection!${NC}"
    echo -e "   ${H_CYAN}>>> Press ANY KEY to customize selection...${NC}"

    SELECTED_RAW=""
    if read -t 60 -n 1 -s -r; then
        clear
        echo -e "\n  Loading package list..."
        fzf_select "$LIST_FILE" "Search Pkg > " "[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL"
        clear
    else
        log "Timeout reached (60s). Auto-confirming ALL packages."
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
    fi

    if [ -z "$SELECTED_RAW" ]; then
        warn "No packages selected."
    else
        parse_selection
        info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}"

        # --- A. Install Repo Apps (BATCH MODE) ---
        if [ ${#REPO_APPS[@]} -gt 0 ]; then
            log "Phase 1: Batch Installing Repository Packages..."
            REPO_QUEUE=()
            for pkg in "${REPO_APPS[@]}"; do
                pkg_installed "$pkg" || REPO_QUEUE+=("$pkg")
            done

            if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
                as_user paru -S --noconfirm --needed --skipreview --nocleanafter --keepsrc --noremovemake "${REPO_QUEUE[@]}" || true
                log "Verifying batch installation..."
                for pkg in "${REPO_QUEUE[@]}"; do
                    pkg_installed "$pkg" && continue
                    warn "Verification failed for '$pkg'. Retrying individually..."
                    install_aur_retry "$pkg"; rc=$?
                    [ $rc -eq 130 ] && continue
                    [ $rc -eq 0 ] || critical_failure_handler "$pkg (Repo)"
                done
                success "Batch phase verified."
            else
                log "All selected repo packages are already installed."
            fi
        fi

        # --- B. Install AUR Apps (SEQUENTIAL + RETRY) ---
        if [ ${#AUR_APPS[@]} -gt 0 ]; then
            log "Phase 2: Installing AUR Packages (Sequential)..."
            log "Hint: Use Ctrl+C to skip a specific package download step."
            for pkg in "${AUR_APPS[@]}"; do
                pkg_installed "$pkg" && continue
                install_aur_retry "$pkg"; rc=$?
                [ $rc -eq 130 ] && continue
                [ $rc -eq 0 ] || critical_failure_handler "$pkg (AUR)"
            done
        fi
    fi
else
    warn "kde-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 4. Dotfiles Deployment
# ------------------------------------------------------------------------------
section "Step 4/5" "KDE Config Deployment"

DOTFILES_SOURCE="$PARENT_DIR/kde-dotfiles"

if [ -d "$DOTFILES_SOURCE" ]; then
    log "Deploying KDE configurations..."

    # 1. Backup Existing .config
    BACKUP_NAME="config_backup_kde_$(date +%s).tar.gz"
    if [ -d "$HOME_DIR/.config" ]; then
        log "Backing up ~/.config to $BACKUP_NAME..."
        exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    fi

    # 2. Explicitly Copy .config and .local

    # --- Process .config ---
    if [ -d "$DOTFILES_SOURCE/.config" ]; then
        log "Merging .config..."
        if [ ! -d "$HOME_DIR/.config" ]; then mkdir -p "$HOME_DIR/.config"; fi

        exe cp -rf "$DOTFILES_SOURCE/.config/"* "$HOME_DIR/.config/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.config/." "$HOME_DIR/.config/" 2>/dev/null || true

        log "Fixing permissions for .config..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.config"
    fi

    # --- Process .local ---
    if [ -d "$DOTFILES_SOURCE/.local" ]; then
        log "Merging .local..."
        if [ ! -d "$HOME_DIR/.local" ]; then mkdir -p "$HOME_DIR/.local"; fi

        exe cp -rf "$DOTFILES_SOURCE/.local/"* "$HOME_DIR/.local/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.local/." "$HOME_DIR/.local/" 2>/dev/null || true

        log "Fixing permissions for .local..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.local"
    fi
    
    success "KDE Dotfiles applied and permissions fixed."
else
    warn "Folder 'kde-dotfiles' not found in repo. Skipping config."
fi

# ------------------------------------------------------------------------------
# 4.5 Deploy Resource Files (README)
# ------------------------------------------------------------------------------
log "Deploying desktop resources..."

SOURCE_README="$PARENT_DIR/kde-dotfiles/KDE-README.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"

if [ ! -d "$DESKTOP_DIR" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$DESKTOP_DIR"
fi

if [ -f "$SOURCE_README" ]; then
    log "Copying KDE-README.txt..."
    exe cp "$SOURCE_README" "$DESKTOP_DIR/"
    exe chown "$TARGET_USER" "$DESKTOP_DIR/KDE-README.txt"
    success "Readme deployed."
else
    warn "kde-dotfiles/KDE-README.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Enable SDDM (FIXED THEME)
# ------------------------------------------------------------------------------
section "Step 5/5" "Enable Display Manager"

log "Configuring SDDM Theme to Breeze..."
exe mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=breeze
EOF
log "Theme set to 'breeze'."

log "Enabling SDDM..."
exe systemctl enable sddm
success "SDDM enabled. Will start on reboot."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Cleanup" "Restoring State"
cleanup_temp_sudoers
success "Done."

trap - ERR
log "Module 06-kde completed."
