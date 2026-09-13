#!/bin/bash
# Health check for the Strix Halo LLM box.
# Prints a one-line summary: service, health endpoint, VRAM in use, disk free.

set -e

# 1. Service active
svc=$(systemctl is-active minimax 2>/dev/null || echo "inactive")

# 2. Health endpoint (port from build guide Phase 4/5)
health=$(curl -s -m 3 localhost:8080/health 2>/dev/null || echo "")
if echo "$health" | grep -q "ok"; then
    hlth="ok"
else
    hlth="down"
fi

# 3. VRAM in use (build guide Phase 4 pattern)
vram_used=$(awk '{printf "%.1f", $1/1e9}' /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null || echo "0")

# 4. Disk free
disk_free=$(df -h / | awk 'NR==2 {print $4}')

echo "minimax=$svc health=$hlth vram=${vram_used}GB disk_free=$disk_free"
