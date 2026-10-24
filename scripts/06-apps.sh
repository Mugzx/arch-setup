#!/bin/bash

# ==============================================================================
# 06-apps.sh - Common Applications (FZF Menu + Split Repo/AUR + Retry Logic)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib-utils.sh"

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User & Helper
# ------------------------------------------------------------------------------
section "Phase 6" "Common Applications"

log "Identifying target user..."
DETECTED_USER=$(detect_user)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    read -p "   Please enter the target username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. List Selection & User Prompt
# ------------------------------------------------------------------------------
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-common-applist.txt"
else
    LIST_FILENAME="niri-common-applist.txt"
fi
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

FAILED_PACKAGES=()

if [ ! -f "$LIST_FILE" ]; then
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    warn "App list is empty. Skipping."
    trap - INT
    exit 0
fi

echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC}"
echo -e "   ${H_YELLOW}>>> Do you want to install common applications?${NC}"
echo -e "   ${H_CYAN}    [ENTER] = Select packages${NC}"
echo -e "   ${H_CYAN}    [N]     = Skip installation${NC}"
echo -e "   ${H_YELLOW}    [Timeout 60s] = Auto-install ALL default packages (No FZF)${NC}"
echo ""

read -t 60 -p "   Please select [Y/n]: " choice
READ_STATUS=$?

SELECTED_RAW=""

# Case 1: Timeout (Auto Install ALL)
if [ $READ_STATUS -ne 0 ]; then
    echo "" 
    warn "Timeout reached (60s). Auto-installing ALL applications from list..."
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')

# Case 2: User Input
else
    choice=${choice:-Y}
    if [[ "$choice" =~ ^[nN]$ ]]; then
        warn "User skipped application installation."
        trap - INT
        exit 0
    else
        clear
        echo -e "\n  Loading application list..."

        fzf_select "$LIST_FILE" "Search App > " "[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL"

        clear
        
        if [ -z "$SELECTED_RAW" ]; then
            log "Skipping application installation (User cancelled selection)."
            trap - INT
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection & Strip Prefixes
# ------------------------------------------------------------------------------
log "Processing selection..."
parse_selection

info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"

# ------------------------------------------------------------------------------
# [SETUP] GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
if [ ${#REPO_APPS[@]} -gt 0 ] || [ ${#AUR_APPS[@]} -gt 0 ]; then
    log "Configuring temporary NOPASSWD for installation..."
    setup_temp_sudoers
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Repo Apps (BATCH MODE) ---
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    section "Step 1/3" "Official Repository Packages (Batch)"

    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
        info_kv "Installing" "${#REPO_QUEUE[@]} packages via Pacman/Paru"

        if as_user paru -S --noconfirm --needed --skipreview --nocleanafter --keepsrc --noremovemake "${REPO_QUEUE[@]}"; then
            success "Repo batch installation completed."
        else
            error "Batch installation failed. Some repo packages might be missing."
        fi

        for pkg in "${REPO_QUEUE[@]}"; do
            pkg_installed "$pkg" && continue
            warn "Missing: $pkg. Retrying individually..."
            install_aur_retry "$pkg" || FAILED_PACKAGES+=("repo:$pkg")
        done
    else
        log "All Repo packages are already installed."
    fi
fi

# --- B. Install AUR Apps (INDIVIDUAL MODE + RETRY) ---
if [ ${#AUR_APPS[@]} -gt 0 ]; then
    section "Step 2/3" "AUR Packages (Sequential + Retry)"

    for app in "${AUR_APPS[@]}"; do
        pkg_installed "$app" && { log "Skipping '$app' (Already installed)."; continue; }

        log "Installing AUR: $app ..."
        install_aur_retry "$app" || FAILED_PACKAGES+=("aur:$app")
    done
fi

# --- C. Install Flatpak Apps (INDIVIDUAL MODE) ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 3/3" "Flatpak Packages (Individual)"
    
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        log "Installing Flatpak: $app ..."
        if ! exe flatpak install -y flathub "$app"; then
            error "Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            success "Installed $app"
        fi
    done
fi

# ------------------------------------------------------------------------------
# [FIX] CLEANUP GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
cleanup_temp_sudoers

# ------------------------------------------------------------------------------
# 4. Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"

    if [ ! -d "$DOCS_DIR" ]; then as_user mkdir -p "$DOCS_DIR"; fi

    echo -e "\n========================================================" >> "$REPORT_FILE"
    echo -e " Installation Failure Report - $(date)" >> "$REPORT_FILE"
    echo -e "========================================================" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"

    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"

    echo ""
    warn "Some applications failed to install."
    warn "A report has been saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed successfully."
fi

# Reset Trap
trap - INT

log "Module 06-apps completed."
