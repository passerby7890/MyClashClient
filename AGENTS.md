# 🍎 天河網絡 (Tianhe Network) — macOS 專區開發規範與執行藍圖 (AGENTS.md)

本文件為 **Antigravity (AGY)** 及所有協作工程師在開發與維護 `./客戶端開發_Mac/` 時的唯一基準架構指南。所有 macOS 端模組實作、重構與代碼審查均須嚴格遵守本規範。

---

## 1. 專案願景與最高物理隔離原則

本專案為 **天河網絡 (Tianhe Network)** macOS 專屬商業旗艦級代理客戶端（支援 Apple Silicon M1/M2/M3/M4 與 Intel x86_64 通用架構）。
- **目錄鎖定**：所有代碼修改、資源變更與產物生成 **100% 嚴格鎖定在 `./客戶端開發_Mac/` 目錄**。
- **純淨隔離**：嚴禁出現任何 Windows `.exe`、`.ps1`、`win32` 依賴，或 Android `.apk`、`JNI`、`VpnService` 代碼。

---

## 2. 五方專家團隊職責分工

```mermaid
graph TD
    subgraph UI 展現層 (@Frontend)
        Window[1200x780 黃金比例 Dark Aqua 視窗]
        Bento[Bento 8 大分頁多欄網格]
        Map[全球 249 國經緯度動態投影地圖]
        Crisp[Crisp 客服 WebView Macintosh UA 注入]
    end

    subgraph 業務邏輯層 (@Backend)
        AuthMgr[AuthManager Laravel 訂單分頁]
        SubEngine[SubscriptionEngine 10 分鐘智慧更新]
        DiffCheck[Non-Disruptive 核心差分比對]
    end

    subgraph 核心防護與代理層 (@Network & @Security)
        Sandbox[Release.entitlements 關閉 App Sandbox]
        MacProxy[MacosNativeProxy networksetup 系統代理]
        CoreDaemon[Mihomo Darwin 內核守護 9090 REST API]
        FailSafe[100% 防斷網清零閉環]
    end

    subgraph 自動化打包層 (@DevOps)
        BuildScript[build_slim_dmg.sh 瘦身與封裝腳本]
        CloudCI[GitHub Actions build_macos.yml 雲端打包]
        DistDMG[dist_mac/TianheNetwork_v3.0.8_macOS.dmg]
    end

    Window --> Bento
    Bento --> AuthMgr
    Bento --> SubEngine
    SubEngine --> DiffCheck
    DiffCheck --> CoreDaemon
    CoreDaemon --> MacProxy
    MacProxy --> FailSafe
    Sandbox --> CoreDaemon
    BuildScript --> DistDMG
    CloudCI --> DistDMG
```

### 2.1 【@Frontend 專家規範】
1. **視窗美學**：
   - macOS 原生 `MainFlutterWindow.swift` 設定 `self.appearance = NSAppearance(named: .darkAqua)`。
   - 視窗預設尺寸 `1200 x 780` 置中，最小尺寸 `1120 x 740`。
   - 沉浸式透明標題列 (`titlebarAppearsTransparent = true`, `styleMask.insert(.fullSizeContentView)`)。
2. **多語系與標頭**：
   - 支援 4 國語系（繁體中文、簡體中文、English、日本語）。
   - Crisp 客服與 HTTP 標頭統一攜帶：`天河網絡/3.0.8 (Macintosh; Mac OS X; Apple Silicon/Intel)`。

### 2.2 【@Security & @Network 專家規範】
1. **解除 App Sandbox**：
   - `macos/Runner/Release.entitlements` 與 `DebugProfile.entitlements` 必須將 `com.apple.security.app-sandbox` 設為 `<false/>`。
   - 開啟 `network.client` 與 `network.server` 權限。
2. **系統代理控制 (`macos_native_proxy.dart`)**：
   - 透過 `/usr/sbin/networksetup` 自動識別所有活躍網路服務（`Wi-Fi` / `Ethernet`）。
   - 啟用：HTTP (7890)、HTTPS (7890)、SOCKS5 (7890)，並設定本機迴路白名單。
   - 防斷網：手動斷線、App 退出與冷啟動預檢時，全面執行 `off` 重置。
3. **Mihomo Darwin 生命週期**：
   - 自動賦予執行權限：`chmod +x mihomo`。
   - 孤兒清理：啟動前執行 `killall -9 mihomo`。
   - 閱後即焚：動態產生單節點臨時 `config.yaml`，確認 9090 端口回傳 200 OK 後立即抹除。
   - 毫秒級熱切換：透過 `PUT http://127.0.0.1:9090/configs?force=true` 記憶體直推 + `DELETE /connections`。

### 2.3 【@Backend 專家規範】
1. **四段式背景智慧更新**：
   - 活躍期間每 10 分鐘（`±60 秒` 隨機抖動）自動靜默更新訂閱與流量。
   - 喚醒檢測（距離上次更新 > 15 分鐘立即刷新）。
   - 連線失敗與超時緊急自救（5 分鐘冷卻保護）。
2. **不中斷連線鐵律 (Non-Disruptive Diff Check)**：
   - 若當前連線節點底層連線參數（IP/Port/UUID/Password/Cipher/TLS）未變，僅更新 UI 與 L2 加密金庫，嚴禁切斷或重啟連線。

### 2.4 【@DevOps 專家規範】
1. **產物封裝規範**：
   - 產物統一輸出至 `./dist_mac/`。
   - 提供 `scripts/build_slim_dmg.sh` 本機編譯封裝。
   - 提供 `.github/workflows/build_macos.yml` 雲端自動編譯 Universal DMG。

---

## 3. 安全與品質審查驗收準則

1. **靜態分析**：執行 `flutter analyze` 必須達到 **0 Errors, 0 Warnings**。
2. **單元測試**：全量執行 `flutter test`，確保 100% 通過。
3. **零明文原則**：日誌與錯誤輸出不得含有任何明文節點密碼、UUID 或訂閱連結。
