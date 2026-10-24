#!/bin/bash
set -uo pipefail

# ==============================================================================
# 05-snapshot-desktop.sh - 桌面安装前快照
# 在安装桌面环境前创建统一检查点，供 undo-desktop.sh 回滚使用。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-utils.sh"

check_root

section "Phase 5" "System Snapshot"

create_checkpoint() {
    local MARKER="Before Desktop Environments"

    # 0. 检查 snapper 是否可用
    if ! command -v snapper &>/dev/null; then
        warn "Snapper tool not found. Skipping snapshot creation."
        return
    fi

    # 1. Root 分区快照
    if snapper -c root get-config &>/dev/null; then
        if snapper -c root list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [root]."
        else
            log "Creating safety checkpoint on [root]..."
            if snapper -c root create --description "$MARKER"; then
                success "Root snapshot created."
            else
                error "Failed to create root snapshot. Aborting."
                exit 1
            fi
        fi
    else
        warn "Snapper 'root' config not configured. Skipping root snapshot."
    fi

    # 2. Home 分区快照（如存在 home 配置）
    if snapper -c home get-config &>/dev/null; then
        if snapper -c home list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [home]."
        else
            log "Creating safety checkpoint on [home]..."
            if snapper -c home create --description "$MARKER"; then
                success "Home snapshot created."
            else
                error "Failed to create home snapshot. Aborting."
                exit 1
            fi
        fi
    fi
}

create_checkpoint
log "Module 05-snapshot-desktop completed."
