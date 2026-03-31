#!/bin/bash
# =============================================================================
# 增強版每日 TLE 數據自動下載腳本 - 支援智能更新檢查
# 新功能：
# 1. 檔案存在時仍檢查是否有更新版本
# 2. 比較檔案修改時間和大小
# 3. 強制更新模式
# 4. 備份舊檔案
# =============================================================================

set -euo pipefail

# 配置參數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLE_DATA_DIR="$(dirname "$SCRIPT_DIR")"  # 當前目錄(/home/sat/orbit-engine/data/tle_data)

# 日誌配置
LOG_DIR="$TLE_DATA_DIR/logs"
LOG_FILE="$LOG_DIR/tle_download.log"

# 創建必要目錄
mkdir -p "$LOG_DIR"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 命令行參數
FORCE_UPDATE=false
CHECK_UPDATES=true

# 解析命令行參數
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --no-update-check)
            CHECK_UPDATES=false
            shift
            ;;
        --help)
            echo "用法: $0 [選項]"
            echo "選項:"
            echo "  --force           強制重新下載所有檔案"
            echo "  --no-update-check 不檢查更新，直接跳過已存在檔案"
            echo "  --help           顯示此幫助訊息"
            exit 0
            ;;
        *)
            echo "未知選項: $1"
            exit 1
            ;;
    esac
done

# 日誌函數 - 同時輸出到終端和日誌文件
log_info() { 
    local msg="${BLUE}[INFO]${NC} $@"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $@" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() { 
    local msg="${YELLOW}[WARN]${NC} $@"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $@" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() { 
    local msg="${RED}[ERROR]${NC} $@"
    echo -e "$msg" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $@" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() { 
    local msg="${GREEN}[SUCCESS]${NC} $@"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $@" >> "$LOG_FILE" 2>/dev/null || true
}

log_update() { 
    local msg="${CYAN}[UPDATE]${NC} $@"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPDATE] $@" >> "$LOG_FILE" 2>/dev/null || true
}

# 獲取當前 UTC 日期
get_current_date() {
    date -u '+%Y%m%d'
}

# 檢查檔案是否存在且有效
file_exists_and_valid() {
    local filepath="$1"
    if [[ -f "$filepath" && -s "$filepath" ]]; then
        return 0
    else
        return 1
    fi
}


# 檢查是否需要更新檔案
need_update() {
    local local_file="$1"
    local url="$2"
    local description="$3"
    
    if $FORCE_UPDATE; then
        return 0
    fi
    
    if ! file_exists_and_valid "$local_file"; then
        return 0
    fi
    
    if ! $CHECK_UPDATES; then
        return 1
    fi
    
    local temp_header_file=$(mktemp)
    if curl -s -I --connect-timeout 30 --max-time 60 "$url" > "$temp_header_file"; then
        
        # 獲取遠端檔案信息
        local remote_last_modified=$(grep -i "Last-Modified:" "$temp_header_file" | cut -d' ' -f2- | tr -d '\r')
        local remote_content_length=$(grep -i "Content-Length:" "$temp_header_file" | cut -d' ' -f2 | tr -d '\r')
        
        # 獲取本地檔案信息
        local local_size=$(stat -c%s "$local_file" 2>/dev/null || echo "0")
        local local_mtime=$(stat -c%Y "$local_file" 2>/dev/null || echo "0")
        
        rm -f "$temp_header_file"
        
        # 檢查大小是否不同 (只有在獲得有效遠端大小時才比較)
        if [[ -n "$remote_content_length" && "$remote_content_length" -gt 0 && "$remote_content_length" != "$local_size" ]]; then
            return 0
        fi
        
        # 檢查修改時間 (如果可用)
        if [[ -n "$remote_last_modified" ]]; then
            local remote_timestamp
            # 嘗試解析時間戳 (這可能因服務器而異)
            if command -v gdate >/dev/null 2>&1; then  # macOS
                remote_timestamp=$(gdate -d "$remote_last_modified" +%s 2>/dev/null || echo "0")
            else  # Linux
                remote_timestamp=$(date -d "$remote_last_modified" +%s 2>/dev/null || echo "0")
            fi
            
            if [[ "$remote_timestamp" -gt "$local_mtime" && "$remote_timestamp" != "0" ]]; then
                return 0
            fi
        fi
        
        return 1
    else
        rm -f "$temp_header_file"
        return 0
    fi
}

# 下載檔案
download_file() {
    local url="$1"
    local output_path="$2"
    local description="$3"
    
    # 確保輸出目錄存在
    mkdir -p "$(dirname "$output_path")"
    
    # 使用臨時檔案下載
    local temp_file="${output_path}.tmp"
    
    if curl -L --fail --connect-timeout 30 --max-time 300 --retry 3 \
            -o "$temp_file" "$url"; then

        # 檢查 Celestrak 的「資料未更新」回應（HTTP 200 但內容是純文字錯誤訊息）
        if grep -q "GP data has not updated" "$temp_file" 2>/dev/null; then
            local celestrak_msg
            celestrak_msg=$(cat "$temp_file" | tr '\n' ' ')
            log_warn "Celestrak 資料尚未更新（將視為已是最新）: $celestrak_msg"
            rm -f "$temp_file"
            return 2  # 特殊返回碼：資料未更新，非真正的錯誤
        fi

        # 檢查檔案大小
        local file_size=$(stat -c%s "$temp_file")
        if [[ $file_size -lt 100 ]]; then
            rm -f "$temp_file"
            return 1
        fi

        # 原子性移動檔案
        mv "$temp_file" "$output_path"

        # 設置檔案時間戳為當前時間
        touch "$output_path"

        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# 從 TLE 數據提取實際日期
extract_tle_date() {
    local tle_file="$1"

    # 檢查檔案是否存在
    if [[ ! -f "$tle_file" ]]; then
        echo ""
        return 1
    fi

    # 提取第一顆衛星的 epoch
    local first_line1=$(sed -n '2p' "$tle_file" 2>/dev/null)
    if [[ -z "$first_line1" ]]; then
        echo ""
        return 1
    fi

    # 提取年份和天數
    local epoch_year=$(echo "$first_line1" | cut -c19-20)
    local epoch_day_decimal=$(echo "$first_line1" | cut -c21-32)
    local epoch_day=$(echo "$epoch_day_decimal" | cut -d'.' -f1)

    # 轉換為完整年份
    local full_year
    if [[ $epoch_year -lt 57 ]]; then  # 假設 57 以下是 20xx 年
        full_year="20$epoch_year"
    else
        full_year="19$epoch_year"
    fi

    # 轉換天數為日期
    local epoch_date
    if command -v python3 >/dev/null 2>&1; then
        epoch_date=$(python3 -c "
from datetime import datetime, timedelta
import sys
try:
    year = int('$full_year')
    day = int('$epoch_day')
    date = datetime(year, 1, 1) + timedelta(days=day-1)
    print(date.strftime('%Y%m%d'))
except:
    sys.exit(1)
" 2>/dev/null)
    else
        # 備用方法：使用 date 命令
        epoch_date=$(date -d "$full_year-01-01 +$((epoch_day-1)) days" '+%Y%m%d' 2>/dev/null)
    fi

    echo "$epoch_date"
    return 0
}

# 驗證 TLE 數據
validate_tle_data() {
    local tle_file="$1"
    local expected_date="$2"
    local constellation="$3"

    # 檢查檔案格式
    local line_count=$(wc -l < "$tle_file")
    if [[ $line_count -lt 6 ]]; then
        return 1
    fi

    # 檢查是否為 TLE 格式
    local first_line1=$(sed -n '2p' "$tle_file")
    local first_line2=$(sed -n '3p' "$tle_file")

    if [[ ! "$first_line1" =~ ^1\  ]] || [[ ! "$first_line2" =~ ^2\  ]]; then
        return 1
    fi

    # 提取 epoch date 進行詳細分析
    local epoch_year=$(echo "$first_line1" | cut -c19-20)
    local epoch_day=$(echo "$first_line1" | cut -c21-32)

    # 提取實際數據日期
    local actual_date=$(extract_tle_date "$tle_file")
    if [[ -n "$actual_date" ]]; then
        # 將實際日期存儲到全局變量中，供後續使用
        export TLE_ACTUAL_DATE="$actual_date"
    fi

    return 0
}

# 驗證 JSON 數據
validate_json_data() {
    local json_file="$1"
    local expected_date="$2"
    local constellation="$3"
    
    # 檢查 JSON 格式
    if ! python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
        return 1
    fi
    
    # 檢查數組長度
    local array_length=$(python3 -c "
import json
with open('$json_file', 'r') as f:
    data = json.load(f)
    print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null)
    
    if [[ $array_length -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

# 檢查是否需要更新已存在的檔案
need_update_existing() {
    local existing_file="$1"
    local url="$2"
    local description="$3"

    if $FORCE_UPDATE; then
        return 0
    fi

    if ! file_exists_and_valid "$existing_file"; then
        return 0  # 檔案不存在或無效，需要下載
    fi

    if ! $CHECK_UPDATES; then
        return 1  # 不檢查更新
    fi

    # 使用原有的更新檢查邏輯
    need_update "$existing_file" "$url" "$description"
    return $?
}

# 主下載函數
download_constellation_data() {
    local constellation="$1"
    local date_str="$2"

    local tle_url="https://celestrak.org/NORAD/elements/gp.php?GROUP=$constellation&FORMAT=tle"
    local temp_tle_file="$TLE_DATA_DIR/$constellation/tle/temp_${constellation}.tle"

    local success_count=0
    local total_count=2
    local updated_count=0

    # 追蹤下載和更新的檔案
    declare -a downloaded_files=()
    declare -a updated_files=()

    # ── 處理 TLE 檔案 ──────────────────────────────────────────────────────
    local tle_download_rc=0
    download_file "$tle_url" "$temp_tle_file" "$constellation TLE" || tle_download_rc=$?

    if [[ $tle_download_rc -eq 2 ]]; then
        # Celestrak 資料未更新，兩個檔案都視為已是最新
        success_count=$((success_count + 2))
    elif [[ $tle_download_rc -eq 0 ]]; then
        if validate_tle_data "$temp_tle_file" "$date_str" "$constellation"; then
            local actual_date="$TLE_ACTUAL_DATE"
            [[ -z "$actual_date" ]] && actual_date="$date_str"

            local final_tle_file="$TLE_DATA_DIR/$constellation/tle/${constellation}_${actual_date}.tle"
            local final_json_file="$TLE_DATA_DIR/$constellation/json/${constellation}_${actual_date}.json"

            # 檢查是否需要更新 TLE
            local should_update=true
            local is_new_file=true
            if [[ -f "$final_tle_file" ]]; then
                is_new_file=false
                if ! need_update_existing "$final_tle_file" "$tle_url" "$constellation TLE"; then
                    should_update=false
                fi
            fi

            if $should_update; then
                mv "$temp_tle_file" "$final_tle_file"
                updated_count=$((updated_count + 1))

                local file_info="$constellation TLE: ${constellation}_${actual_date}.tle"
                if $is_new_file; then
                    downloaded_files+=("$file_info")
                    log_success "已下載: $file_info"
                else
                    updated_files+=("$file_info")
                    log_update "已更新: $file_info"
                fi

                # ── 從 TLE 本地轉換 JSON（不再向 Celestrak 發第二次請求）────
                local is_new_json=$( [[ -f "$final_json_file" ]] && echo false || echo true )
                if python3 "$SCRIPT_DIR/tle_to_json.py" "$final_tle_file" "$final_json_file" 2>/dev/null; then
                    updated_count=$((updated_count + 1))
                    local json_info="$constellation JSON: ${constellation}_${actual_date}.json (本地轉換)"
                    if [[ "$is_new_json" == "true" ]]; then
                        downloaded_files+=("$json_info")
                        log_success "已產生: $json_info"
                    else
                        updated_files+=("$json_info")
                        log_update "已更新: $json_info"
                    fi
                    success_count=$((success_count + 1))
                else
                    log_error "$constellation JSON 轉換失敗"
                fi
            else
                rm -f "$temp_tle_file"
                # TLE 不需要更新，JSON 也不用重新產生
                success_count=$((success_count + 1))
            fi

            success_count=$((success_count + 1))
        else
            rm -f "$temp_tle_file"
        fi
    fi
    
    # 將下載和更新的檔案信息保存到全局變量
    if [[ ${#downloaded_files[@]} -gt 0 ]] 2>/dev/null; then
        eval "${constellation}_downloaded_files=(\"\${downloaded_files[@]}\")"
    fi
    if [[ ${#updated_files[@]} -gt 0 ]] 2>/dev/null; then
        eval "${constellation}_updated_files=(\"\${updated_files[@]}\")"
    fi
    
    return $((total_count - success_count))
}

# 生成簡化報告
generate_summary() {
    local starlink_result="$1"
    local oneweb_result="$2"
    
    echo
    echo "===== TLE 數據下載完成 ====="
    
    # 統計檔案狀態並顯示具體檔案
    if [[ $starlink_result -eq 0 ]]; then
        echo -e "${GREEN}✅ Starlink: 已下載/更新${NC}"
        
        # 顯示下載的檔案
        if [[ -n "${starlink_downloaded_files[*]:-}" ]]; then
            echo -e "${CYAN}  📥 新下載檔案:${NC}"
            for file in "${starlink_downloaded_files[@]}"; do
                echo -e "    • $file"
            done
        fi
        
        # 顯示更新的檔案
        if [[ -n "${starlink_updated_files[*]}" ]]; then
            echo -e "${YELLOW}  🔄 更新檔案:${NC}"
            for file in "${starlink_updated_files[@]}"; do
                echo -e "    • $file"
            done
        fi
        
        # 如果沒有任何檔案被處理，顯示跳過信息
        if [[ -z "${starlink_downloaded_files[*]:-}" && -z "${starlink_updated_files[*]:-}" ]]; then
            echo -e "${BLUE}  ⏭️  所有檔案已是最新，跳過下載${NC}"
        fi
    else
        echo -e "${RED}❌ Starlink: 失敗${NC}"
    fi
    
    if [[ $oneweb_result -eq 0 ]]; then
        echo -e "${GREEN}✅ OneWeb: 已下載/更新${NC}"
        
        # 顯示下載的檔案
        if [[ -n "${oneweb_downloaded_files[*]:-}" ]]; then
            echo -e "${CYAN}  📥 新下載檔案:${NC}"
            for file in "${oneweb_downloaded_files[@]}"; do
                echo -e "    • $file"
            done
        fi
        
        # 顯示更新的檔案
        if [[ -n "${oneweb_updated_files[*]}" ]]; then
            echo -e "${YELLOW}  🔄 更新檔案:${NC}"
            for file in "${oneweb_updated_files[@]}"; do
                echo -e "    • $file"
            done
        fi
        
        # 如果沒有任何檔案被處理，顯示跳過信息
        if [[ -z "${oneweb_downloaded_files[*]:-}" && -z "${oneweb_updated_files[*]:-}" ]]; then
            echo -e "${BLUE}  ⏭️  所有檔案已是最新，跳過下載${NC}"
        fi
    else
        echo -e "${RED}❌ OneWeb: 失敗${NC}"
    fi
    
    echo "============================="
}

# 主程序
main() {
    # 記錄開始時間
    local start_time=$(date +%s)
    local start_timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    local date_str
    date_str=$(get_current_date)
    
    # 初始化全局數組變量
    declare -ga starlink_downloaded_files=()
    declare -ga starlink_updated_files=()
    declare -ga oneweb_downloaded_files=()
    declare -ga oneweb_updated_files=()
    
    echo
    echo "🚀 TLE 數據下載工具"
    echo "⏰ 開始時間: $start_timestamp"
    
    # 記錄執行開始
    log_info "========== TLE 數據下載開始 =========="
    log_info "執行時間: $start_timestamp"
    log_info "工作目錄: $TLE_DATA_DIR"
    
    if $FORCE_UPDATE; then
        echo -e "${YELLOW}⚡ 強制更新模式已啟用${NC}"
    fi
    
    if ! $CHECK_UPDATES; then
        echo -e "${BLUE}⏭️ 跳過已存在檔案模式已啟用${NC}"
    fi
    
    echo
    

    
    # 檢查網路連接
    echo "🌐 檢查網路連接..."
    if ! curl -s --connect-timeout 10 "https://celestrak.org" > /dev/null; then
        log_error "無法連接到 CelesTrak，請檢查網路連接"
        exit 1
    fi
    
    # 確保目錄存在
    mkdir -p "$TLE_DATA_DIR"/{starlink,oneweb}/{tle,json}
    
    # 下載數據（用 || 捕捉非零返回碼，避免 set -e 在單一失敗時中止整個腳本）
    local starlink_result=0
    echo "📡 開始下載 Starlink 數據... ($(date '+%H:%M:%S'))"
    download_constellation_data "starlink" "$date_str" || starlink_result=$?

    local oneweb_result=0
    echo "🛰️ 開始下載 OneWeb 數據... ($(date '+%H:%M:%S'))"
    download_constellation_data "oneweb" "$date_str" || oneweb_result=$?
    

    # 生成簡化報告
    generate_summary "$starlink_result" "$oneweb_result"

    # 總結
    local total_failures=$((starlink_result + oneweb_result))
    local end_timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    if [[ $total_failures -eq 0 ]]; then
        log_info "========== TLE 數據下載完成 =========="
        log_info "結束時間: $end_timestamp"
        log_info "執行結果: 成功"
        exit 0
    else
        log_error "========== TLE 數據下載失敗 =========="
        log_error "結束時間: $end_timestamp"
        log_error "執行結果: 部分數據處理失敗"
        exit 1
    fi
}

# 執行主程序
main "$@"