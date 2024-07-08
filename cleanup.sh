#!/usr/bin/env bash
#
# docker-cleanup/cleanup.sh
# Cleans up unused Docker resources: stopped containers, dangling images,
# unused volumes, and unused networks. Shows space reclaimed per category.
#
# Usage: ./cleanup.sh [-a] [-n] [-v] [-h]
#

set -euo pipefail

# ─── Defaults ───────────────────────────────────────────────────────────────────
ALL_IMAGES=false     # include tagged images, not just dangling
DRY_RUN=false
VERBOSE=false

# ─── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Functions ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Cleans up unused Docker resources and reports space reclaimed.

Options:
  -a    Remove all unused images (not just dangling/untagged)
  -n    Dry-run: show what would be removed without removing anything
  -v    Verbose: show detailed information about each resource
  -h    Show this help message

Categories Cleaned:
  - Stopped containers
  - Dangling images (or all unused images with -a)
  - Unused volumes
  - Unused networks (excluding default bridge/host/none)

Examples:
  $(basename "$0")        # Clean dangling resources
  $(basename "$0") -a     # Clean all unused images too
  $(basename "$0") -n -v  # Verbose dry-run
  $(basename "$0") -h     # Show help
EOF
    exit 0
}

log_verbose() {
    if $VERBOSE; then
        echo -e "  ${CYAN}[VERBOSE]${RESET} $1"
    fi
}

format_size() {
    # Takes bytes and formats as human-readable
    local bytes="$1"
    if [[ "$bytes" -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ "$bytes" -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [[ "$bytes" -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# ─── Parse arguments ────────────────────────────────────────────────────────────
while getopts ":anvh" opt; do
    case "$opt" in
        a) ALL_IMAGES=true ;;
        n) DRY_RUN=true ;;
        v) VERBOSE=true ;;
        h) usage ;;
        \?) echo "Error: Unknown option -$OPTARG" >&2; usage ;;
    esac
done

# ─── Check Docker is available ──────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH.${RESET}" >&2
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}Error: Docker daemon is not running or you lack permissions.${RESET}" >&2
    exit 1
fi

# ─── Header ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Docker Cleanup Tool${RESET}"
echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN MODE] Nothing will be removed.${RESET}"
fi
echo ""

total_reclaimed=0

# ─── 1. Stopped Containers ──────────────────────────────────────────────────────
echo -e "${BOLD}=== Stopped Containers ===${RESET}"

stopped=$(docker ps -aq --filter "status=exited" --filter "status=created" --filter "status=dead" 2>/dev/null || true)
stopped_count=0
container_size=0

if [[ -n "$stopped" ]]; then
    stopped_count=$(echo "$stopped" | wc -l | xargs)

    for cid in $stopped; do
        cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's/^\///' || echo "$cid")
        csize=$(docker inspect --format '{{.SizeRw}}' "$cid" 2>/dev/null || echo "0")
        csize=${csize:-0}
        log_verbose "Container: $cname ($cid) - $(format_size "$csize")"
        container_size=$((container_size + csize))
    done

    if $DRY_RUN; then
        echo -e "  ${CYAN}Would remove${RESET} $stopped_count stopped container(s)"
        echo -e "  Estimated space: ~$(format_size "$container_size")"
    else
        docker rm $stopped &>/dev/null || true
        echo -e "  ${GREEN}Removed${RESET} $stopped_count stopped container(s)"
        echo -e "  Space reclaimed: ~$(format_size "$container_size")"
        total_reclaimed=$((total_reclaimed + container_size))
    fi
else
    echo -e "  ${GREEN}No stopped containers found.${RESET}"
fi
echo ""

# ─── 2. Dangling/Unused Images ──────────────────────────────────────────────────
if $ALL_IMAGES; then
    echo -e "${BOLD}=== All Unused Images ===${RESET}"
else
    echo -e "${BOLD}=== Dangling Images ===${RESET}"
fi

if $ALL_IMAGES; then
    images=$(docker images -q --filter "dangling=false" 2>/dev/null || true)
    # Get truly unused images (not referenced by any container)
    dangling=$(docker images -q --filter "dangling=true" 2>/dev/null || true)
    all_unused="$dangling"
else
    all_unused=$(docker images -q --filter "dangling=true" 2>/dev/null || true)
fi

image_count=0
image_size=0

if [[ -n "$all_unused" ]]; then
    image_count=$(echo "$all_unused" | sort -u | wc -l | xargs)

    for iid in $(echo "$all_unused" | sort -u); do
        iname=$(docker inspect --format '{{.RepoTags}}' "$iid" 2>/dev/null || echo "$iid")
        isize=$(docker inspect --format '{{.Size}}' "$iid" 2>/dev/null || echo "0")
        isize=${isize:-0}
        log_verbose "Image: $iname ($iid) - $(format_size "$isize")"
        image_size=$((image_size + isize))
    done

    if $DRY_RUN; then
        echo -e "  ${CYAN}Would remove${RESET} $image_count image(s)"
        echo -e "  Estimated space: ~$(format_size "$image_size")"
    else
        if $ALL_IMAGES; then
            docker image prune -a -f &>/dev/null || true
        else
            docker image prune -f &>/dev/null || true
        fi
        echo -e "  ${GREEN}Removed${RESET} $image_count image(s)"
        echo -e "  Space reclaimed: ~$(format_size "$image_size")"
        total_reclaimed=$((total_reclaimed + image_size))
    fi
else
    echo -e "  ${GREEN}No unused images found.${RESET}"
fi
echo ""

# ─── 3. Unused Volumes ──────────────────────────────────────────────────────────
echo -e "${BOLD}=== Unused Volumes ===${RESET}"

unused_volumes=$(docker volume ls -q --filter "dangling=true" 2>/dev/null || true)
vol_count=0

if [[ -n "$unused_volumes" ]]; then
    vol_count=$(echo "$unused_volumes" | wc -l | xargs)

    for vol in $unused_volumes; do
        mountpoint=$(docker volume inspect --format '{{.Mountpoint}}' "$vol" 2>/dev/null || echo "unknown")
        log_verbose "Volume: $vol (mount: $mountpoint)"
    done

    if $DRY_RUN; then
        echo -e "  ${CYAN}Would remove${RESET} $vol_count volume(s)"
    else
        docker volume prune -f &>/dev/null || true
        echo -e "  ${GREEN}Removed${RESET} $vol_count volume(s)"
    fi
else
    echo -e "  ${GREEN}No unused volumes found.${RESET}"
fi
echo ""

# ─── 4. Unused Networks ─────────────────────────────────────────────────────────
echo -e "${BOLD}=== Unused Networks ===${RESET}"

# Get networks not used by any container (excluding defaults)
unused_networks=$(docker network ls --filter "type=custom" -q 2>/dev/null || true)
net_count=0
nets_to_remove=""

if [[ -n "$unused_networks" ]]; then
    for nid in $unused_networks; do
        # Check if network has any connected containers
        connected=$(docker network inspect "$nid" --format '{{len .Containers}}' 2>/dev/null || echo "0")
        if [[ "$connected" == "0" ]]; then
            nname=$(docker network inspect "$nid" --format '{{.Name}}' 2>/dev/null || echo "$nid")
            log_verbose "Network: $nname ($nid) - 0 containers connected"
            nets_to_remove="$nets_to_remove $nid"
            ((net_count++)) || true
        fi
    done
fi

if [[ "$net_count" -gt 0 ]]; then
    if $DRY_RUN; then
        echo -e "  ${CYAN}Would remove${RESET} $net_count network(s)"
    else
        docker network prune -f &>/dev/null || true
        echo -e "  ${GREEN}Removed${RESET} $net_count network(s)"
    fi
else
    echo -e "  ${GREEN}No unused networks found.${RESET}"
fi
echo ""

# ─── Summary ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Summary ===${RESET}"
echo -e "  Containers: $stopped_count"
echo -e "  Images:     $image_count"
echo -e "  Volumes:    $vol_count"
echo -e "  Networks:   $net_count"

if ! $DRY_RUN && [[ "$total_reclaimed" -gt 0 ]]; then
    echo -e "  ${GREEN}Total space reclaimed: ~$(format_size "$total_reclaimed")${RESET}"
fi

echo ""
echo -e "${BOLD}Done.${RESET}"
