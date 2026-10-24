#!/bin/bash

# ==============================================================================
# 05-niri.sh - Niri Desktop (Restored FZF & Robust AUR)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
UNDO_SCRIPT="$SCRIPT_DIR/undo-niri.sh"

check_root

# --- [HELPER FUNCTIONS] ---

# hide .desktop
hide_desktop_file() {

  local file="$1"

  if [[ -f "$file" ]] && ! grep -q "^NoDisplay=true$" "$file"; then

    echo "NoDisplay=true" >> "$file"

  fi

}


# Ensure whiptail
if ! command -v whiptail &>/dev/null; then
  log "Installing dependency: whiptail..."
  pacman -S --noconfirm libnewt >/dev/null 2>&1
fi

section "Phase 5" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================

create_checkpoint() {
  local marker="Before Niri Setup"
  if snapper -c root list | grep -q "$marker"; then
    log "Checkpoint '$marker' already exists."
  else
    log "Creating safety checkpoint..."
    snapper -c root create -d "$marker"
    snapper -c home list &>/dev/null && snapper -c home create -d "$marker"
    success "Checkpoint created."
  fi
}
create_checkpoint

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(detect_user)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

# ==============================================================================
# STEP 2: Core Components
# ==============================================================================
section "Step 1/9" "Core Components"
exe pacman -S --noconfirm --needed niri xdg-desktop-portal-gnome fuzzel kitty libnotify mako polkit-gnome

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
section "Step 2/9" "File Manager"
exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus

if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
  exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Nvidia/Input Fix
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
  GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
  HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
  ENV_VARS="env GTK_IM_MODULE=fcitx"
  [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ] && ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"

  if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
    exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
  fi
fi

# ==============================================================================
# STEP 4: Network Optimization
# ==============================================================================
section "Step 3/9" "Network Optimization"
exe pacman -S --noconfirm --needed flatpak gnome-software
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
  IS_CN_ENV=true
  info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
  select_flathub_mirror
else
  log "Using Global Sources."
fi

setup_temp_sudoers

# ==============================================================================
# STEP 5: Dependencies (RESTORED FZF)
# ==============================================================================
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# Ensure tools
command -v fzf &>/dev/null || pacman -S --noconfirm fzf >/dev/null 2>&1

if [ -f "$LIST_FILE" ]; then
  echo -e "\n   ${H_YELLOW}>>> Default installation in 60s. Press ANY KEY to customize...${NC}"
  SELECTED_RAW=""

  if read -t 60 -n 1 -s -r; then
    clear
    log "Loading package list..."
    fzf_select "$LIST_FILE" "Search Pkg > " "[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL"
    clear
  else
    log "Auto-confirming ALL packages."
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
  fi

  if [ -z "$SELECTED_RAW" ]; then
    warn "No packages selected."
  else
    parse_selection
    info_kv "Target" "$(( ${#REPO_APPS[@]} + ${#AUR_APPS[@]} )) packages scheduled."

    # 1. Batch Install Repo Packages
    if [ ${#REPO_APPS[@]} -gt 0 ]; then
      log "Phase 1: Batch Installing Repo Packages..."
      as_user paru -S --noconfirm --needed --skipreview --nocleanafter --keepsrc --noremovemake "${REPO_APPS[@]}" || true
      for pkg in "${REPO_APPS[@]}"; do
        pkg_installed "$pkg" && continue
        warn "Missing: $pkg. Retrying individually..."
        install_aur_retry "$pkg"; rc=$?
        [ $rc -eq 130 ] && continue
        [ $rc -eq 0 ] || critical_failure_handler "Failed to install '$pkg'."
      done
    fi

    # 2. Sequential AUR Install
    if [ ${#AUR_APPS[@]} -gt 0 ]; then
      log "Phase 2: Installing AUR Packages (Sequential)..."
      for pkg in "${AUR_APPS[@]}"; do
        pkg_installed "$pkg" && continue
        install_aur_retry "$pkg"; rc=$?
        [ $rc -eq 130 ] && continue
        [ $rc -eq 0 ] || critical_failure_handler "Failed to install '$pkg'."
      done
    fi

    # Waybar fallback
    if ! command -v waybar &>/dev/null; then
      warn "Waybar missing. Installing stock..."
      exe pacman -S --noconfirm --needed waybar
    fi
  fi
else
  warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

TEMP_DIR="$PARENT_DIR/niri-dotfiles"

if [ -d "$TEMP_DIR" ]; then
  # Filter Exclusions
  if [ "$TARGET_USER" != "mugzx" ]; then
    EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
    if [ -f "$EXCLUDE_FILE" ]; then
      log "Processing exclusions..."
      while IFS= read -r item; do
        item=$(echo "$item" | tr -d '\r' | xargs)
        [ -n "$item" ] && [[ ! "$item" =~ ^# ]] && rm -rf "$TEMP_DIR/.config/$item"
      done <"$EXCLUDE_FILE"
    fi
  fi

  # Backup & Apply
  log "Backing up & Applying..."
  as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config
  as_user cp -rf "$TEMP_DIR/." "$HOME_DIR/"

  # Post-Process
  if [ "$TARGET_USER" != "mugzx" ]; then
    as_user truncate -s 0 "$HOME_DIR/.config/niri/output.kdl" 2>/dev/null
    rm -f "$HOME_DIR/.config/gtk-3.0/bookmarks"
  fi

  # Fix Symlinks & Permissions
  GTK4="$HOME_DIR/.config/gtk-4.0"
  THEME="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"
  as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
  as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
  as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"

  if command -v flatpak &>/dev/null; then
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
  fi
  success "Dotfiles Applied."
else
  warn "Dotfiles missing in temp directory."
fi

log "Hiding useless .desktop files"
hide_desktop_file "/usr/share/applications/avahi-discover.desktop"
hide_desktop_file "/usr/share/applications/qv4l2.desktop"
hide_desktop_file "/usr/share/applications/qvidcap.desktop"
hide_desktop_file "/usr/share/applications/bssh.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.Fcitx5.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.fcitx5-migrator.desktop"
hide_desktop_file "/usr/share/applications/xgps.desktop"
hide_desktop_file "/usr/share/applications/xgpsspeed.desktop"
hide_desktop_file "/usr/share/applications/gvim.desktop"
hide_desktop_file "/usr/share/applications/kbd-layout-viewer5.desktop"
hide_desktop_file "/usr/share/applications/bvnc.desktop"
# ==============================================================================
# STEP 7: Wallpapers
# ==============================================================================
section "Step 6/9" "Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
  as_user mkdir -p "$HOME_DIR/Pictures/Wallpapers"
  as_user cp -rf "$TEMP_DIR/wallpapers/." "$HOME_DIR/Pictures/Wallpapers/"
  as_user rm -rf "$HOME_DIR/wallpapers"
  success "Installed."
fi
rm -rf "$TEMP_DIR"

# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
section "Step 7/9" "Hardware"
if pacman -Q ddcutil &>/dev/null; then
  gpasswd -a "$TARGET_USER" i2c
  lsmod | grep -q i2c_dev || echo "i2c-dev" >/etc/modules-load.d/i2c-dev.conf
fi
if pacman -Q swayosd &>/dev/null; then
  systemctl enable --now swayosd-libinput-backend.service >/dev/null 2>&1
fi
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup & Auto-Login
# ==============================================================================
section "Final" "Cleanup & Boot"
cleanup_temp_sudoers

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
  log "Auto-login skipped."
  as_user rm -f "$LINK" "$SVC_FILE"
else
  log "Configuring TTY Auto-login..."
  mkdir -p "/etc/systemd/system/getty@tty1.service.d"
  echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

  as_user mkdir -p "$(dirname "$LINK")"
  cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
[Install]
WantedBy=default.target
EOT
  as_user ln -sf "../niri-autostart.service" "$LINK"
  chown -R "$TARGET_USER" "$SVC_DIR"
  success "Enabled."
fi

trap - ERR
log "Module 05-niri completed."
