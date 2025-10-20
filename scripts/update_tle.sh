#!/bin/bash
# TLE 數據自動更新腳本
# 位置：tle_data/scripts/update_tle.sh (相對於父目錄)
#
# IMPORTANT: Uses relative path from script location
# - Script location: tle_data/scripts/update_tle.sh
# - TLE root: tle_data/ (parent of scripts/)
# - This ensures portability regardless of parent directory name/location

# 獲取腳本所在目錄的父目錄（tle_data 根目錄）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLE_DIR="$(dirname "$SCRIPT_DIR")"  # 上一層就是 tle_data/

DATE=$(date +%Y%m%d)
LOG_FILE="$TLE_DIR/logs/tle_download_$(date +%Y%m).log"

# 確保 logs 目錄存在
mkdir -p "$TLE_DIR/logs"

echo "========================================" | tee -a "$LOG_FILE"
echo "TLE Update: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Starlink TLE 更新
echo "Updating Starlink TLE..." | tee -a "$LOG_FILE"
wget -q -O "$TLE_DIR/starlink/tle/starlink_$DATE.tle" \
  "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle" \
  && echo "✅ Starlink TLE updated: starlink_$DATE.tle" | tee -a "$LOG_FILE" \
  || echo "❌ Failed to download Starlink TLE" | tee -a "$LOG_FILE"

# OneWeb TLE 更新
echo "Updating OneWeb TLE..." | tee -a "$LOG_FILE"
wget -q -O "$TLE_DIR/oneweb/tle/oneweb_$DATE.tle" \
  "https://celestrak.org/NORAD/elements/gp.php?GROUP=oneweb&FORMAT=tle" \
  && echo "✅ OneWeb TLE updated: oneweb_$DATE.tle" | tee -a "$LOG_FILE" \
  || echo "❌ Failed to download OneWeb TLE" | tee -a "$LOG_FILE"

# 清理 30 天前的舊文件
echo "Cleaning old TLE files (>30 days)..." | tee -a "$LOG_FILE"
find "$TLE_DIR" -name "*.tle" -mtime +30 -delete
echo "✅ Cleanup complete" | tee -a "$LOG_FILE"

# 統計當前 TLE 文件數量
STARLINK_COUNT=$(ls "$TLE_DIR/starlink/tle"/*.tle 2>/dev/null | wc -l)
ONEWEB_COUNT=$(ls "$TLE_DIR/oneweb/tle"/*.tle 2>/dev/null | wc -l)

echo "Current TLE files:" | tee -a "$LOG_FILE"
echo "  Starlink: $STARLINK_COUNT" | tee -a "$LOG_FILE"
echo "  OneWeb: $ONEWEB_COUNT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
