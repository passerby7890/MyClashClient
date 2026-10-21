# 🍎 天河網絡 (Tianhe Network) — macOS 桌面端專屬操作與維運筆記手冊 (v3.0.8)

> **所屬分區**：`./客戶端開發_Mac/`（100% 純 macOS 桌面端工程，與 Android、Windows 物理隔離）  
> **應用名稱與包名**：`Tianhe.app` (`com.tianhe.cloud.assistant.macos`)  
> **支援晶片架構**：Apple Silicon (`M1 / M2 / M3 / M4 arm64`) & Intel (`x86_64`)  
> **核心引擎**：`mihomo` (Mihomo Meta v1.19.32 `darwin`) + macOS 原生 `networksetup` 系統代理控制

---

## 📌 一、 MAC 專區目錄結構

```text
客戶端開發_Mac/
├── macos/                             # macOS Cocoa / Swift 原生層
│   └── Runner/
│       ├── MainFlutterWindow.swift    # 1200x780 黃金視窗、darkAqua 深色主題與透明標題列
│       ├── Configs/AppInfo.xcconfig   # PRODUCT_NAME = Tianhe & Bundle ID 設定
│       └── Release.entitlements       # 關閉 App Sandbox (允許啟動 mihomo 與修改系統代理)
├── lib/                               # 桌面端 Dart 業務邏輯與 1200x780 Bento 網格 UI
│   ├── core/                          # AES-256 解密、XOR 混淆、4 國語系、249 國經緯度投影引擎
│   ├── infrastructure/                # mihomo 守護、macos_native_proxy.dart (networksetup)、9090 動態密碼
│   ├── business/                      # AuthManager (Laravel 分頁) & 10 分鐘背景靜默更新引擎
│   └── presentation/                  # 8 大分頁 Bento 網格視圖 (與 Windows 端 100% 視覺一致)
├── tools/mihomo/                      # 隨包內核 (mihomo darwin) 與離線分流庫 (Country.mmdb, GeoIP.dat, geosite.dat)
├── scripts/
│   └── build_slim_dmg.sh              # macOS 瘦身打包與 DMG 封裝腳本
├── .github/workflows/
│   └── build_macos.yml                # GitHub Actions 雲端自動編譯 macOS DMG 工作流
└── dist_mac/                          # 唯一發布目錄 (Tianhe.app & TianheNetwork_v3.0.8_macOS.dmg)
```

---

## ⚡ 二、 macOS 端五大核心技術機制筆記

### 1. 為什麼 `Release.entitlements` 必須設為 `app-sandbox = false`？
* Apple 預設為 Flutter macOS 專案開啟沙盒（App Sandbox）。若未關閉沙盒，macOS 核心會直接攔截 `Process.start('mihomo')`（報 `Operation not permitted`），且無法呼叫 `/usr/sbin/networksetup` 設定系統代理。
* 我們透過獨立 `.dmg` 發佈（非上架 Mac App Store），因此將 `com.apple.security.app-sandbox` 設為 `false`，即可免除沙盒限制，實現一鍵無感開啟系統代理。

### 2. macOS 系統代理與「100% 防斷網」機制 (`macos_native_proxy.dart`)
* **連通時**：自動透過 `networksetup -listallnetworkservices` 識別當前連線網卡（如 `Wi-Fi`），自動將 Web Proxy (HTTP)、Secure Web Proxy (HTTPS) 與 SOCKS Proxy 指向 `127.0.0.1:7890`。
* **斷線 / 關閉視窗 / 冷啟動預檢時**：自動將所有網卡的 `webproxystate`、`securewebproxystate`、`socksfirewallproxystate` 設回 `off`，並執行 `killall -9 mihomo`，確保用戶關閉 `Tianhe.app` 後 Safari 與 Chrome 絕不斷網。

### 3. 毫秒級熱切換 (< 50ms) 與每 10 分鐘背景靜默更新
* **熱切換**：切換節點時絕不重啟 `mihomo` 進程，直接透過記憶體發送 `PUT http://127.0.0.1:9090/configs?force=true` (`{"payload": yaml}`) + `DELETE /connections` 斬斷舊長連線。
* **每 10 分鐘自動同步**：背景每 10 分鐘（`±60 秒` 隨機抖動）自動拉取最新節點與剩餘流量；具備 **Diff Check 差異比對**，若當前連線節點 IP/Port 未變則僅更新 UI 與 L2 加密金庫，絕不打斷進行中的連線。

### 4. L0 單節點閱後即焚與 9090 端口防窺探
* 臨時設定檔寫入 `~/Library/Application Support/TianheNetwork/core/config.yaml`，待 `GET http://127.0.0.1:9090/version` 返回 `200 OK` 確認載入記憶體後**立即覆寫刪除**，磁碟零明文殘留。

---

## 🚀 三、 如何編譯打包 `Tianhe.app` 與 `.dmg` 安裝包？

### 方法 A：在沒有 Mac 電腦的情況下（使用 GitHub Actions 雲端免費打包）
1. 將 `./客戶端開發_Mac/` 推送至你的 GitHub 私有儲存庫（Private Repository）。
2. 點擊 GitHub 頁面上方的 **`Actions`** ➔ 選擇 **`Build Tianhe macOS DMG`** ➔ 點擊 **`Run workflow`**。
3. 等待約 4～5 分鐘，雲端 `macos-latest` 主機就會自動完成：
   * 下載最新 `mihomo-darwin` 內核與離線 `Country.mmdb`
   * 執行 `flutter build macos --release --obfuscate --split-debug-info=build/macos_symbols`
   * 剔除 `kernel_blob.bin` 等除錯廢料並執行 Ad-hoc 簽名
   * 打包產出 **`TianheNetwork_v3.0.8_macOS.dmg`** 供你直接下載並上傳至下載站！

### 方法 B：在 Mac 電腦（MacBook / Mac mini）本機直接打包
打開 Mac 終端機（Terminal），進入 `客戶端開發_Mac` 目錄執行：
```bash
chmod +x ./scripts/build_slim_dmg.sh
./scripts/build_slim_dmg.sh
```
編譯完成後，即可在 `./dist_mac/` 目錄下取得：
* `dist_mac/Tianhe.app`
* `dist_mac/TianheNetwork_v3.0.8_macOS.dmg`

---

## 🛠️ 四、 客服必備筆記：Mac 客戶安裝常見問題秒解 (FAQ)

### Q1：Mac 用戶下載 `.dmg` 拖入「應用程式 (Applications)」後，雙擊打開跳出「無法打開 Tianhe，因為無法驗證開發者」或「Tianhe 已損毀，無法打開」怎麼辦？
* **原因**：這是因為沒有購買每年 $99 美金的 Apple Developer ID 憑證進行公證（Notarization），macOS Gatekeeper 會對網路下載的 `.dmg` 加上隔離屬性（`com.apple.quarantine`）。
* **秒解步驟（可放進官網文檔中心或交給客服回覆客人）**：
  1. 打開 Mac 上的 **「終端機 (Terminal)」**（按 `Command + 空白鍵` 搜尋 `Terminal`）。
  2. 複製貼上以下這行指令並按 Enter（會提示輸入 Mac 開機密碼，輸入時不會顯示字元，輸完直接按 Enter 即可）：
     ```bash
     sudo xattr -rd com.apple.quarantine /Applications/Tianhe.app
     ```
  3. 執行完畢後，再次雙擊 `Tianhe` 即可永久正常開啟！

### Q2：如何在遠端動態配置更新 Mac 版下載連結？
* 打開 `tools/aes_crypto_tool.html`，在 JSON 配置中新增或更新 `"dmg_url"`（或 `"mac_url"`）：
  ```json
  {
    "hosts": ["https://api-primary.your-domain.com"],
    "latest_version": "3.0.8",
    "min_version": "3.0.0",
    "apk_url": "https://dl.your-domain.com/tianhe-v3.0.8-arm64-v8a.apk",
    "exe_url": "https://dl.your-domain.com/TianheNetwork_v3.0.8_Portable.zip",
    "dmg_url": "https://dl.your-domain.com/TianheNetwork_v3.0.8_macOS.dmg"
  }
  ```
* 點擊加密後，將 Base64 密文同步更新至 Cloudflare DNS (`thjsqaes32.spsr86.cv` TXT 記錄) 與阿里雲 OSS (`web-config.json`) 即可。
