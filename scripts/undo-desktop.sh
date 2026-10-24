#!/bin/bash
set -uo pipefail

# ==============================================================================
# undo-desktop.sh - Desktop Environment Rollback Tool (Subvolume Rollback)
# ==============================================================================
# Usage: sudo ./scripts/undo-desktop.sh
# Description: Reverts system to "Before Desktop Environments" using
#              btrfs-assistant. Performs a SUBVOLUME rollback (not a file-diff
#              undo), the most complete way to return to the checkpoint state.
#              Self-contained so it can be deployed to /usr/local/bin and
#              survive installer removal.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TARGET_DESC="Before Desktop Environments"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo ./scripts/undo-desktop.sh)${NC}"
    exit 1
fi

# 2. Check Dependencies
if ! command -v snapper &>/dev/null; then
    echo -e "${RED}Error: Snapper is not installed.${NC}"
    exit 1
fi
if ! command -v btrfs-assistant &>/dev/null; then
    echo -e "${RED}Error: btrfs-assistant is not installed.${NC}"
    echo "Cannot perform subvolume rollback."
    exit 1
fi

echo -e "${YELLOW}>>> Initializing rollback to '${TARGET_DESC}'...${NC}"

# --- Helper: rollback a single subvolume ---
# Args: $1 = subvolume name (e.g. @ or @home), $2 = snapper config (e.g. root or home)
perform_rollback() {
    local subvol="$1"
    local snap_conf="$2"

    echo -e "Checking config '${YELLOW}${snap_conf}${NC}' for subvolume '${YELLOW}${subvol}${NC}'..."

    # 1. Get Snapper ID for the target description
    local snap_id
    snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep "$TARGET_DESC" | tail -n 1 | awk '{print $1}')

    if [ -z "$snap_id" ]; then
        echo -e "${RED}  [SKIP] Snapshot '${TARGET_DESC}' not found in config '${snap_conf}'.${NC}"
        return 1
    fi
    echo -e "  Found Snapshot ID: ${GREEN}${snap_id}${NC}"

    # 2. Map Snapper ID to btrfs-assistant index
    # btrfs-assistant -l columns: $1=index, $2=subvolume, $3=snapper id
    local ba_index
    ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')

    if [ -z "$ba_index" ]; then
        echo -e "${RED}  [FAIL] Could not map Snapper ID ${snap_id} to btrfs-assistant index.${NC}"
        echo -e "${RED}  Subvolume name may differ from '${subvol}'. Check with: btrfs-assistant -l${NC}"
        return 1
    fi

    # 3. Execute subvolume restore
    echo -e "  Executing subvolume rollback (Index: ${ba_index})..."
    if btrfs-assistant -r "$ba_index"; then
        echo -e "  ${GREEN}Success.${NC}"
        return 0
    else
        echo -e "  ${RED}Restore command failed.${NC}"
        return 1
    fi
}

# --- Main ---

# 3. Rollback Root (critical)
echo -e "${YELLOW}>>> Restoring Root Filesystem...${NC}"
if ! perform_rollback "@" "root"; then
    echo -e "${RED}CRITICAL FAILURE: Failed to restore root. Aborting to prevent partial state.${NC}"
    exit 1
fi

# 4. Rollback Home (optional)
if snapper list-configs | grep -q "^home "; then
    echo -e "${YELLOW}>>> Restoring Home Filesystem...${NC}"
    perform_rollback "@home" "home"
else
    echo -e "No 'home' snapper config found, skipping home restore."
fi

echo -e "${GREEN}System rollback successful. Rebooting...${NC}"
sleep 2
reboot
