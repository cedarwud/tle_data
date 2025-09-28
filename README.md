# 衛星 TLE 數據自動收集系統

## 📂 目錄結構

```
/home/sat/orbit-engine/data/tle_data/
├── README.md
├── .gitignore                     # Git 忽略配置
├── scripts/                      # 自動化腳本
│   ├── daily_tle_download_enhanced.sh   # 每日下載腳本
│   └── tle_cron_scheduler.sh           # Cron 排程腳本
├── logs/                         # 執行日誌 (被 .gitignore 忽略)
│   ├── tle_download.log         # 下載日誌
│   └── tle_error.log            # 錯誤日誌
├── starlink/                     # Starlink 數據目錄
│   ├── tle/                     # TLE 格式檔案
│   │   └── starlink_YYYYMMDD.tle
│   └── json/                    # JSON 格式檔案
│       └── starlink_YYYYMMDD.json
└── oneweb/                      # OneWeb 數據目錄
    ├── tle/                     # TLE 格式檔案
    │   └── oneweb_YYYYMMDD.tle
    └── json/                    # JSON 格式檔案
        └── oneweb_YYYYMMDD.json
```

**數據格式說明**:
- **TLE**: 標準兩行軌道參數，用於 SGP4 軌道計算
- **JSON**: 結構化數據，包含完整軌道參數和元數據

## 🚀 自動化腳本系統

### 1. daily_tle_download_enhanced.sh - 核心下載引擎

**用途**: 智能下載 Starlink 和 OneWeb TLE 數據，支援更新檢查

```bash
# 執行下載 (智能更新檢查)
./scripts/daily_tle_download_enhanced.sh

# 強制重新下載所有檔案
./scripts/daily_tle_download_enhanced.sh --force

# 跳過更新檢查
./scripts/daily_tle_download_enhanced.sh --no-update-check

# 查看幫助
./scripts/daily_tle_download_enhanced.sh --help
```

**核心功能**：
- ✅ 自動下載 Starlink 和 OneWeb 的 TLE/JSON 數據
- ✅ 智能更新檢查 (比較檔案大小和修改時間)
- ✅ 基於實際數據 epoch 日期命名檔案
- ✅ 完整的檔案驗證和錯誤處理
- ✅ 詳細日誌記錄和狀態報告
- ✅ 原子性檔案操作 (臨時檔案 + 移動)

### 2. tle_cron_scheduler.sh - 排程管理系統

**用途**: 設置和管理 TLE 數據自動下載排程

```bash
# 安裝自動排程 (建議在 UTC 01:00 執行)
./scripts/tle_cron_scheduler.sh install

# 檢查排程狀態
./scripts/tle_cron_scheduler.sh status

# 手動測試下載
./scripts/tle_cron_scheduler.sh test

# 查看執行日誌
./scripts/tle_cron_scheduler.sh logs 50

# 移除排程
./scripts/tle_cron_scheduler.sh remove
```

**排程功能**：
- ⏰ 每日自動下載設定
- 📊 執行狀態監控
- 📝 完整的日誌管理
- 🔧 簡易的安裝/移除操作

## 📋 數據來源

### API 端點
- **Starlink TLE**: `https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle`
- **Starlink JSON**: `https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=json`
- **OneWeb TLE**: `https://celestrak.org/NORAD/elements/gp.php?GROUP=oneweb&FORMAT=tle`
- **OneWeb JSON**: `https://celestrak.org/NORAD/elements/gp.php?GROUP=oneweb&FORMAT=json`

### 檔案命名規則
- **格式**: `{constellation}_{YYYYMMDD}.{ext}`
- **範例**:
  - `starlink_20250924.tle`
  - `oneweb_20250924.json`
- **日期**: 基於 TLE 數據中的實際 epoch 日期，不是下載日期

## 🔄 典型工作流程

### 自動化設置（推薦）
```bash
# 1. 安裝自動排程
./scripts/tle_cron_scheduler.sh install

# 2. 驗證運行
./scripts/tle_cron_scheduler.sh test

# 3. 監控狀態
./scripts/tle_cron_scheduler.sh status
```

### 手動管理
```bash
# 1. 手動下載最新數據
./scripts/daily_tle_download_enhanced.sh

# 2. 強制更新所有數據
./scripts/daily_tle_download_enhanced.sh --force

# 3. 檢查下載狀態
./scripts/tle_cron_scheduler.sh logs 20
```

## 🎯 使用目的

此系統收集的 TLE 數據用於：

1. **軌道計算與預測** - SGP4 軌道傳播模型
2. **網路覆蓋分析** - 衛星可見性和覆蓋計算
3. **換手策略研究** - 最佳衛星切換時機分析
4. **雙星座對比** - Starlink vs OneWeb 性能評估
5. **學術研究** - 提供真實軌道數據支援

## 📊 數據品質檢查

### 檢查下載狀態
```bash
# 查看最新檔案
ls -lt starlink/tle/ | head -5
ls -lt oneweb/tle/ | head -5

# 檢查檔案大小
ls -lh starlink/tle/starlink_*.tle | tail -5
ls -lh oneweb/tle/oneweb_*.tle | tail -5

# 統計衛星數量
wc -l starlink/tle/starlink_$(date -u '+%Y%m%d').tle
wc -l oneweb/tle/oneweb_$(date -u '+%Y%m%d').tle
```

### TLE 格式驗證
```bash
# 檢查 TLE 格式
head -6 starlink/tle/starlink_$(date -u '+%Y%m%d').tle

# 驗證 JSON 格式
python3 -c "import json; print(len(json.load(open('starlink/json/starlink_$(date -u '+%Y%m%d').json'))))"

# 檢查數據完整性
find . -name "*.tle" -size -1000c  # 查找異常小的檔案
```

## 📈 監控與維護

### 檢查日誌
```bash
# 查看下載日誌
tail -f logs/tle_download.log

# 查看錯誤日誌
tail -f logs/tle_error.log

# 檢查最近的執行狀況
./scripts/tle_cron_scheduler.sh logs 50
```

### 存儲管理
- 數據會持續累積，建議定期檢查磁碟使用量
- 可手動刪除過舊的檔案以節省空間
- 日誌檔案位於 `logs/` 目錄

### 健康檢查
```bash
# 檢查數據完整性
ls -la */tle/*.tle | wc -l  # 應該有檔案

# 檢查最新數據日期
find . -name "*.tle" -printf '%T+ %p\n' | sort -r | head -5

# 檢查排程狀態
./scripts/tle_cron_scheduler.sh status
```

## 🔧 故障排除

### 網路連接問題
```bash
# 測試連接
curl -I https://celestrak.org

# 手動下載測試
curl "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle" -o test.tle
```

### 腳本權限問題
```bash
# 確保腳本有執行權限
chmod +x scripts/daily_tle_download_enhanced.sh
chmod +x scripts/tle_cron_scheduler.sh
```

### Cron 問題
```bash
# 檢查 cron 服務狀態
sudo systemctl status cron

# 查看 cron 日誌
sudo journalctl -u cron -f

# 檢查當前用戶的 crontab
crontab -l
```

## ⚙️ 配置選項

### 環境要求
- **OS**: Linux (Ubuntu/Debian 推薦)
- **網路**: 穩定的網際網路連接
- **磁碟**: 建議至少 5GB 可用空間
- **工具**: curl, python3, cron

### 自訂設定
可編輯腳本修改：
- 下載時間間隔
- 重試次數和超時設定
- 檔案命名格式
- 日誌輸出格式

### 安全和權限
- 所有腳本使用 `set -euo pipefail` 嚴格錯誤處理
- 支援原子性檔案操作（臨時檔案 + 移動）
- 完整的日誌記錄用於審計
- 智能更新檢查避免不必要的下載

---

**🎯 目標**: 提供穩定、自動化的衛星 TLE 數據收集系統，支援軌道計算和網路分析研究