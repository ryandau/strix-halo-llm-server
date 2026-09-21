#!/bin/bash
# Health check for the Strix Halo LLM box.
# Prints a one-line summary: service, health endpoint, GPU watchdog, VRAM in use, disk free.

set -e

# 1. Service active
svc=$(systemctl is-active qwen38 2>/dev/null || echo "inactive")

# 2. Health endpoint. Note: this stays "ok" after a GPU device-lost; the watchdog timer covers that.
health=$(curl -s -m 3 localhost:8080/health 2>/dev/null || echo "")
if echo "$health" | grep -q "ok"; then
    hlth="ok"
else
    hlth="down"
fi

# 3. GPU watchdog timer (build guide Phase 5)
watch=$(systemctl is-active qwen38-watch.timer 2>/dev/null || echo "inactive")

# 4. VRAM in use
vram_used=$(awk '{printf "%.1f", $1/1e9}' /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1 || echo "0")

# 5. Disk free
disk_free=$(df -h / | awk 'NR==2 {print $4}')

echo "qwen38=$svc health=$hlth watchdog=$watch vram=${vram_used}GB disk_free=$disk_free"
