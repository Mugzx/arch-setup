#!/bin/bash
set -uo pipefail

# ==============================================================================
# 01-base.sh - Base System Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-utils.sh"

check_root

log "Starting Phase 1: Base System Configuration..."

# ------------------------------------------------------------------------------
# 1. Set Global Default Editor
# ------------------------------------------------------------------------------
section "Step 1/6" "Global Default Editor"

TARGET_EDITOR="vim"

if command -v nvim &> /dev/null; then
    TARGET_EDITOR="nvim"
    log "Neovim detected."
elif command -v nano &> /dev/null; then
    TARGET_EDITOR="nano"
    log "Nano detected."
else
    log "Neovim or Nano not found. Installing Vim..."
    if ! command -v vim &> /dev/null; then
        exe pacman -S --noconfirm gvim
    fi
fi

log "Setting EDITOR=$TARGET_EDITOR in /etc/environment..."

if grep -q "^EDITOR=" /etc/environment; then
    exe sed -i "s/^EDITOR=.*/EDITOR=${TARGET_EDITOR}/" /etc/environment
else
    # exe handles simple commands, for redirection we wrap in bash -c or just run it
    # For simplicity in logging, we just run it and log success
    echo "EDITOR=${TARGET_EDITOR}" >> /etc/environment
fi
success "Global EDITOR set to: ${TARGET_EDITOR}"

# ------------------------------------------------------------------------------
# 2. Enable 32-bit (multilib) Repository
# ------------------------------------------------------------------------------
section "Step 2/6" "Multilib Repository"

if grep -q "^\[multilib\]" /etc/pacman.conf; then
    success "[multilib] is already enabled."
else
    log "Uncommenting [multilib]..."
    # Uncomment [multilib] and the following Include line
    exe_must sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    
    log "Refreshing database..."
    exe_must pacman -Syu
    success "[multilib] enabled."
fi

# ------------------------------------------------------------------------------
# 3. Install Base Fonts
# ------------------------------------------------------------------------------
section "Step 3/6" "Base Fonts"

log "Installing adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts noto-fonts-cjk, noto-fonts, emoji..."
exe_must pacman -S --noconfirm --needed adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts noto-fonts-cjk noto-fonts noto-fonts-emoji
success "Base fonts installed."

# ------------------------------------------------------------------------------
# 4. Configure archlinuxcn Repository
# ------------------------------------------------------------------------------
section "Step 4/6" "ArchLinuxCN Repository"

if grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
    success "archlinuxcn repository already exists."
else
    log "Adding archlinuxcn mirrors to pacman.conf..."
    cat <<EOT >> /etc/pacman.conf

[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch
EOT
    success "Mirrors added."
fi

log "Installing archlinuxcn-keyring..."
# Keyring installation often needs -Sy specifically, but -Syu is safe too
exe_must pacman -Syu --noconfirm archlinuxcn-keyring
success "ArchLinuxCN configured."

# ------------------------------------------------------------------------------
# 5. Install AUR Helpers
# ------------------------------------------------------------------------------
section "Step 5/6" "AUR Helpers"

log "Installing yay and paru..."
exe_must pacman -S --noconfirm --needed base-devel yay paru
# 关键断言：AUR helper 必须可用，后续所有 AUR 安装都依赖它
command -v paru >/dev/null 2>&1 || { error "paru not found after install. Aborting."; exit 1; }
success "Helpers installed."

log "Module 01 completed."
