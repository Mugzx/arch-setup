#!/bin/bash
set -uo pipefail

# ==============================================================================
# lib-utils.sh - The "TUI" Visual Engine (v4.0)
# ==============================================================================

# --- 1. 颜色与样式定义 (ANSI) ---
# 注意：这里定义的是字面量字符串，需要 echo -e 来解析
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'

# 常用高亮色
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'
export H_MAGENTA='\033[1;95m'

# 背景色 (用于标题栏)
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'

# 符号定义
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"

# 日志文件
export TEMP_LOG_FILE="/tmp/log-arch-setup.txt"
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# --- 2. 基础工具 ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}

write_log() {
    # Strip ANSI colors for log file
    local clean_msg
    clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# --- 3. 视觉组件 (TUI Style) ---

# 绘制分割线
hr() {
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

# 绘制大标题 (Section)
section() {
    local title="$1"
    local subtitle="$2"
    echo ""
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}${H_WHITE}$title${NC}"
    echo -e "${H_PURPLE}│${NC} ${H_CYAN}$subtitle${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
    write_log "SECTION" "$title - $subtitle"
}

# 绘制键值对信息
info_kv() {
    local key="$1"
    local val="$2"
    local extra="${3:-}"
    printf "   ${H_BLUE}●${NC} %-15s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
    write_log "INFO" "$key=$val"
}

# 普通日志
log() {
    echo -e "   $ARROW $1"
    write_log "LOG" "$1"
}

# 成功日志
success() {
    echo -e "   $TICK ${H_GREEN}$1${NC}"
    write_log "SUCCESS" "$1"
}

# 警告日志 (突出显示)
warn() {
    echo -e "   $WARN ${H_YELLOW}${BOLD}WARNING:${NC} ${H_YELLOW}$1${NC}"
    write_log "WARN" "$1"
}

# 错误日志 (非常突出)
error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  ERROR: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

# --- 4. 核心：命令执行器 (Command Exec) ---
exe() {
    local full_command="$*"
    
    # Visual: 显示正在运行的命令
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    
    write_log "EXEC" "$full_command"
    
    # Run the command
    "$@" 
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit Code: $status"
        return $status
    fi
}

# 静默执行
exe_silent() {
    "$@" > /dev/null 2>&1
}

# 必须成功的命令执行器（关键步骤失败即中止，避免静默失败）
exe_must() {
    exe "$@" || { error "Critical step failed: $*"; exit 1; }
}

# --- 5. 可复用逻辑块 ---

# 动态选择 Flathub 镜像源 (修复版：使用 echo -e 处理颜色变量)
select_flathub_mirror() {
    # 1. 索引数组保证顺序
    local names=(
        "SJTU (Shanghai Jiao Tong)"
        "USTC (Univ of Sci & Tech of China)"
    )
    
    local urls=(
        "https://mirror.sjtu.edu.cn/flathub"
        "https://mirrors.ustc.edu.cn/flathub"
    )

    # 2. 动态计算菜单宽度 (基于无颜色的纯文本)
    local max_len=0
    local title_text="Select Flathub Mirror (60s Timeout)"
    
    max_len=${#title_text}

    for name in "${names[@]}"; do
        # 预估显示长度："[x] Name - Recommended"
        local item_len=$((${#name} + 4 + 14)) 
        if (( item_len > max_len )); then
            max_len=$item_len
        fi
    done

    # 菜单总宽度
    local menu_width=$((max_len + 4))

    # --- 3. 渲染菜单 (使用 echo -e 确保颜色变量被解析) ---
    echo ""
    
    # 生成横线
    local line_str=""
    printf -v line_str "%*s" "$menu_width" ""
    line_str=${line_str// /─}

    # 打印顶部边框
    echo -e "${H_PURPLE}╭${line_str}╮${NC}"

    # 打印标题 (计算居中填充)
    local title_padding_len=$(( (menu_width - ${#title_text}) / 2 ))
    local right_padding_len=$((menu_width - ${#title_text} - title_padding_len))
    
    # 生成填充空格
    local t_pad_l=""; printf -v t_pad_l "%*s" "$title_padding_len" ""
    local t_pad_r=""; printf -v t_pad_r "%*s" "$right_padding_len" ""
    
    echo -e "${H_PURPLE}│${NC}${t_pad_l}${BOLD}${title_text}${NC}${t_pad_r}${H_PURPLE}│${NC}"

    # 打印中间分隔线
    echo -e "${H_PURPLE}├${line_str}┤${NC}"

    # 打印选项
    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local display_idx=$((i+1))
        
        # 1. 构造用于显示的带颜色字符串
        local color_str=""
        # 2. 构造用于计算长度的无颜色字符串
        local raw_str=""

        if [ "$i" -eq 0 ]; then
            raw_str=" [$display_idx] $name - Recommended"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name} - ${H_GREEN}Recommended${NC}"
        else
            raw_str=" [$display_idx] $name"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name}"
        fi

        # 计算右侧填充空格
        local padding=$((menu_width - ${#raw_str}))
        local pad_str=""; 
        if [ "$padding" -gt 0 ]; then
            printf -v pad_str "%*s" "$padding" ""
        fi
        
        # 打印：边框 + 内容 + 填充 + 边框
        echo -e "${H_PURPLE}│${NC}${color_str}${pad_str}${H_PURPLE}│${NC}"
    done

    # 打印底部边框
    echo -e "${H_PURPLE}╰${line_str}╯${NC}"
    echo ""

    # --- 4. 用户交互 ---
    local choice
    # 提示符
    read -t 60 -p "$(echo -e "   ${H_YELLOW}Enter choice [1-${#names[@]}]: ${NC}")" choice
    if [ $? -ne 0 ]; then echo ""; fi
    choice=${choice:-1}
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
        log "Invalid choice or timeout. Defaulting to SJTU..."
        choice=1
    fi

    local index=$((choice-1))
    local selected_name="${names[$index]}"
    local selected_url="${urls[$index]}"

    log "Setting Flathub mirror to: ${H_GREEN}$selected_name${NC}"
    
    # 执行修改 (仅修改 flathub，不涉及 github)
    if exe flatpak remote-modify flathub --url="$selected_url"; then
        success "Mirror updated."
    else
        error "Failed to update mirror."
    fi
}

# --- 6. 共享安装逻辑 (Shared Install Helpers) ---

# 检测 UID 1000 的用户名
detect_user() {
    awk -F: '$3 == 1000 {print $1}' /etc/passwd
}

# 判断包是否已安装
pkg_installed() {
    pacman -Q "$1" &>/dev/null
}

# 以 TARGET_USER 身份执行命令
as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}

# 临时 NOPASSWD sudoers（安装期间免密；结束或失败时须调用 cleanup_temp_sudoers）
SUDO_TEMP_FILE="/etc/sudoers.d/99_installer_temp"
setup_temp_sudoers() {
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
}
cleanup_temp_sudoers() {
    rm -f "$SUDO_TEMP_FILE"
}

# 从列表文件 FZF 多选，结果写入全局 SELECTED_RAW
fzf_select() {
    local list_file="$1" prompt="$2" header="$3"
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$list_file" | \
        sed -E 's/[[:space:]]+#/\t#/' | \
        fzf --multi \
            --layout=reverse --border --margin=1,2 \
            --prompt="$prompt" --pointer=">>" --marker="* " \
            --delimiter=$'\t' --with-nth=1 \
            --bind 'load:select-all' --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
            --info=inline --header="$header" \
            --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
            --preview-window=right:45%:wrap:border-left \
            --color=dark --color=fg+:white,bg+:black \
            --color=hl:blue,hl+:blue:bold --color=header:yellow:bold \
            --color=info:magenta --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
            --color=spinner:yellow)
}

# 解析 SELECTED_RAW 到 REPO_APPS / AUR_APPS / FLATPAK_APPS
parse_selection() {
    REPO_APPS=(); AUR_APPS=(); FLATPAK_APPS=()
    local line raw
    while IFS= read -r line; do
        raw=$(echo "$line" | cut -f1 -d$'\t' | xargs)
        [[ -z "$raw" ]] && continue
        case "$raw" in
            flatpak:*) FLATPAK_APPS+=("${raw#flatpak:}") ;;
            AUR:*)     AUR_APPS+=("${raw#AUR:}") ;;
            *)         REPO_APPS+=("$raw") ;;
        esac
    done <<< "$SELECTED_RAW"
}

# AUR 包逐包安装（带重试）；返回 0=成功 / 130=用户跳过 / 1=失败
install_aur_retry() {
    local pkg="$1" max_retries="${2:-2}" attempt
    for ((attempt=0; attempt<=max_retries; attempt++)); do
        [ $attempt -gt 0 ] && { warn "Retry $attempt/$max_retries for '$pkg' in 3s..."; sleep 3; }
        as_user paru -S --noconfirm --needed --skipreview --nocleanafter --keepsrc --noremovemake "$pkg"
        local rc=$?
        [ $rc -eq 130 ] && { warn "Skipped '$pkg' by user (Ctrl+C)."; return 130; }
        if pkg_installed "$pkg"; then success "Installed $pkg"; return 0; fi
        warn "Attempt $((attempt+1)) failed for $pkg"
    done
    return 1
}

# 关键失败处理：提示回滚快照（依赖全局 UNDO_SCRIPT）
critical_failure_handler() {
    local reason="$1"
    trap - ERR
    echo ""
    echo -e "\033[0;31m###############################################################\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                    #\033[0m"
    echo -e "\033[0;31m#   Reason: $reason\033[0m"
    echo -e "\033[0;31m#   1. Restore snapshot   2. Fix manually and re-run          #\033[0m"
    echo -e "\033[0;31m###############################################################\033[0m"
    echo ""
    while true; do
        if ! read -p "Execute System Recovery (Restore Snapshot)? [y/n]: " -r choice; then
            # read 失败（EOF/非交互环境），默认中止而非死循环
            warn "No input received. Aborting installation (no rollback)."
            cleanup_temp_sudoers
            exit 1
        fi
        case "$choice" in
            [yY]*)
                cleanup_temp_sudoers
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script..."
                    bash "$UNDO_SCRIPT"
                else
                    error "Recovery script missing!"
                fi
                exit 1 ;;
            [nN]*)
                cleanup_temp_sudoers
                error "Installation aborted."
                exit 1 ;;
            *) echo "Invalid input. Please enter 'y' or 'n'." ;;
        esac
    done
}
