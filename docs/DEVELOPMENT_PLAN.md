# 開發計劃：TeachLens，Mac 線上教學講解工具

> 「TeachLens」是暫定名稱，可隨時替換。全文只在 `AppInfo.swift` 和 `Info.plist` 兩處集中定義。

## Context
- 線上教學講師在 Mac 上同時需要兩組功能：
  - **讓觀眾看到操作**：按鍵和滑鼠視覺化，來自 Keyviz。
  - **引導觀眾視線**：縮放、畫筆標註、計時器、錄影，來自 ZoomIt-Mac。
- 目前這兩個工具彼此分離，快捷鍵也可能衝突。Keyviz 的 overlay 和 ZoomIt 的縮放與錄影也沒有協調。
- 目標是做成**單一原生 Swift 選單列 App**：
  - 以 ZoomIt-Mac（MIT，Swift，macOS 14 以上）為主體。
  - 用 Swift 重寫 Keyviz（GPL-3.0）的按鍵視覺化。
  - 再加上教學專屬功能：聚光燈、課程模式、即時字幕、多頁白板。
- 使用者已選定這個方向：**原生 Swift 單一 App，改名，並註明開源出處**。

## 授權與出處（第一步就要完成）
- 整體授權採 **GPL-3.0**：重寫時參考了 Keyviz 的 GPL 程式碼。
- ZoomIt 的 MIT 程式碼可以併入 GPL 專案，但要保留其版權聲明。
- `LICENSE`：放 GPL-3.0 全文。
- `THIRD_PARTY_NOTICES.md`：
  - Keyviz © Rahul Mula（GPL-3.0），https://github.com/mulaRahul/keyviz
  - ZoomIt for Mac © Microsoft（MIT 全文），https://github.com/microsoft/Zoomit-Mac
- README 開頭加「致謝與出處」段落；App 的「關於」頁同步顯示。
- 移除 Microsoft 與 Sysinternals 的商標字樣、圖示和 bundle id，例如改成 `io.github.fw1201.teachlens`。

## 專案結構（新 repo 佈局，沿用 ZoomIt 的 SwiftPM）
```
Package.swift                 # 目標：TeachLens（app）、TeachLensCore（lib）、TeachLensSelfTest
Sources/TeachLens/            # ZoomIt 原始碼移入後改名
  App/       AppInfo.swift, AppDelegate, MenuBar, HotkeyCenter, Settings（分頁）
  Zoom/      靜態縮放、即時縮放（沿用 ZoomIt）
  Annotate/  畫筆、圖形、文字（沿用），新增 Whiteboard/
  Capture/   截圖、OCR、全景、錄影、剪輯（沿用）
  Timer/     休息計時器（沿用）
  Keystroke/ 新增：Keyviz 的 Swift 版
  Spotlight/ 新增：聚光燈、游標強調
  Captions/  新增：即時字幕、逐字稿
  Modes/     新增：課程模式預設集
  Permissions/ 新增：統一的權限檢查與引導
Resources/   多語系（zh-Hant 預設，另有 en、zh-Hans）、圖示、音效
Scripts/build-app.sh          # 沿用，改名
Legacy/keyviz/                # 原 Tauri 專案，只做參考，最後一期刪除
```
- 現有 repo 的 Tauri 程式碼搬到 `Legacy/keyviz/`，當作移植規格的對照來源。

## 分期開發

### M0：基礎建置（約 1 週）
- 匯入 ZoomIt-Mac 原始碼，保留 git 出處：用 subtree，或在 commit 訊息註明上游 commit hash。
- 全域改名。完成授權檔、README 和「關於」頁。
- 建立 GitHub Actions（`macos-14` runner）：
  - 執行 `swift build`
  - 執行 `swift run TeachLensSelfTest`
  - 執行 `build-app.sh release`，產生 `.dmg` artifact
- 驗收：App 能啟動，ZoomIt 原有功能全部可用，「關於」頁顯示兩個出處。

### M1：按鍵視覺化，移植 Keyviz（約 2–3 週）
對照來源都在 `Legacy/keyviz/`：
- **事件來源**：
  - 用 `CGEvent.tapCreate(.cgSessionEventTap, .listenOnly)` 監聽 keyDown、keyUp、flagsChanged、滑鼠和滾輪。
  - 邏輯參考 `src-tauri/crates/rdev/src/macos/listen.rs` 和 `src-tauri/src/app/event.rs`，包含忽略重複按鍵、側鍵對應和切換快捷鍵。
- **按鍵對照**：
  - 把 `src/lib/keymaps.ts` 轉成 Swift 的 `KeyMap`，只保留 macOS 分支。
  - 修飾鍵依 ⌃⌥⇧⌘ 排序；Fn、Globe 和 Caps Lock 另外處理。
- **狀態與歷史**：
  - 移植 `src/stores/key_event.ts`，包含組合鍵分組、歷史筆數、逾時淡出、過濾器（僅快捷鍵、自訂）、連按次數。
  - 改寫成 `@Observable KeystrokeStore`。
- **樣式**：
  - 移植 `src/stores/key_style.ts` 和 `src/types/style.ts`：顏色、大小、邊框、對齊位置、進出場動畫。
  - 用 SwiftUI 重做 5 種鍵帽：`components/keycaps/` 下的 minimal、laptop、lowprofile、pbt、press-count。
- **Overlay 視窗**：
  - `NSPanel` 設定：nonactivating、borderless、`ignoresMouseEvents`、`level = .screenSaver`、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`。
  - 支援多螢幕切換，參考 `app/commands.rs` 的 `set_main_window_monitor`。
- **滑鼠效果**：移植 `mouse-overlay.tsx` 和 `mouse-indicator.tsx`，包含點擊漣漪、按住高亮和滾輪指示。
- **設定匯入匯出**：沿用 Keyviz 的 JSON 欄位名稱。
- 驗收：
  - 與舊版 Keyviz 並排比對，常見組合鍵顯示一致，例如 ⌘⇧4、⌥←、⌃Space。
  - CPU 閒置低於 1%，連續打字低於 5%。

### M2：權限中心與快捷鍵整合（約 1 週）
- **權限中心**：
  - 統一檢查 Screen Recording、Input Monitoring（`CGPreflightListenEventAccess`）、Accessibility、Microphone、Speech、Camera。
  - 首次啟動顯示引導頁，每項權限都提供「開啟系統設定」深連結。
- **快捷鍵**：
  - 全部集中到 `HotkeyCenter`，並做衝突偵測。
  - 預設值：
    - 沿用 ZoomIt 的 ⌃1–⌃8。
    - 新增 ⌃9 切換按鍵顯示（取代 Keyviz 的 Shift+F10）。
    - 新增 ⌃0 聚光燈、⌃⇧W 白板、⌃⇧C 字幕。
- **與 ZoomIt 協調**：
  - 靜態縮放凍結畫面時，暫時隱藏按鍵 overlay，避免它被截進凍結畫面。
  - 即時縮放和錄影時，overlay 正常顯示並會被錄入。
  - 用 `SCContentFilter` 控制 overlay 是否被錄入，可在設定中切換。
- 驗收：全新帳號首次啟動，依引導完成授權後，所有功能都能用，且沒有快捷鍵衝突。

### M3：聚光燈與游標強調（約 1 週）
- 全螢幕 overlay 加上暗化遮罩，挖空游標周圍的圓形或矩形區域。半徑和暗度可調，用滾輪即時調整。
- 游標強調：
  - 放大游標光暈與顏色環。
  - 「搖動找游標」動畫。
  - 點擊時顯示左鍵、右鍵的不同色環（重用 M1 的滑鼠效果）。
- 可與畫筆共存：開啟聚光燈時仍可標註。
- 驗收：在 2 台不同 scale 的外接螢幕上位置準確，60 fps。

### M4：課程模式預設集（約 1 週）
- `CourseMode` 資料模型：記錄每項功能的開關與參數，存成 JSON，可匯入匯出。
- 內建 4 組模式：
  - **講解**：顯示按鍵和字幕，關閉聚光燈。
  - **程式示範**：按鍵加歷史紀錄，滑鼠效果，鍵帽放大。
  - **重點強調**：開啟聚光燈，隱藏按鍵。
  - **休息**：休息計時器加背景音樂，暫停其他 overlay。
- 選單列可一鍵切換；切換時在畫面角落短暫顯示目前模式名稱。
- 驗收：切換後所有子系統狀態正確，重開 App 後保留最後的模式。

### M5：即時字幕與逐字稿（約 2 週）
- `SFSpeechRecognizer` 搭配 `requiresOnDeviceRecognition`，預設 zh-TW，可選 en-US 等。音訊來源為麥克風。
- 字幕 overlay：
  - 位置、字級、底色、行數可調。
  - 句子停頓後淡出。
  - 處理語音辨識單次約 1 分鐘的上限，自動接續新的 request。
- 逐字稿：
  - 帶時間戳，可匯出 `.txt`、`.srt`、`.vtt`。
  - 錄影時同步產生 `.srt`，並寫入錄影檔旁。
- 驗收：連續 30 分鐘講話不中斷，`.srt` 與錄影時間誤差小於 0.5 秒。

### M6：多頁白板與頁面標記（約 2 週）
- 以 ZoomIt 的畫布與工具為基礎，擴充成多頁白板。
  - 頁面類型：白、黑、格線、橫線、透明（疊在桌面上）。
  - 用 ←、→ 換頁，用縮圖列跳頁。
- 每頁的筆跡獨立保存，可以重新開啟和編輯。
- 匯出：單頁 PNG，全部頁面合併成 PDF（PDFKit）。
- 可把目前畫面截圖插入成新頁，再進行標註。
- 驗收：50 頁白板操作不卡頓，匯出的 PDF 用預覽程式可正確開啟。

### M7：在地化、打包與發佈（約 1 週）
- 介面語言：zh-Hant（預設）、en、zh-Hans。可沿用 Keyviz 的 `src/locales/*` 譯詞。
- 用 Developer ID 簽章與 notarize，產出 `.dmg`。若沒有開發者帳號，就在 README 保留 `xattr -cr` 說明。
- 支援開機自動啟動（沿用 ZoomIt 的功能）；可選用 Sparkle 自動更新。
- 撰寫講師使用手冊（README 加上 GitHub Pages）：快捷鍵表，以及 Zoom、Meet、Teams 分享畫面的設定建議。
- 刪除 `Legacy/keyviz/`，只保留出處說明。

## 風險與對策
| 風險 | 對策 |
|---|---|
| 雲端容器是 Linux，無法編譯 Swift 和 AppKit | 所有建置與測試都在 GitHub Actions 的 `macos-14` 上執行，再用你的 Mac 手動驗收 |
| Event tap 需要權限，簽章變更後授權會失效 | 固定 bundle id 和簽章；權限中心提供重新授權的引導 |
| 語音辨識有時長上限 | 自動輪替 request，並在時間軸上銜接 |
| 授權混用 | 整體採 GPL-3.0，NOTICE 檔保留 MIT 聲明 |
| ZoomIt 上游更新 | 用 subtree 追蹤，定期合併 |

## 驗證方式
- **每個 PR**：GitHub Actions 在 `macos-14` 上跑 `swift build`、`swift run TeachLensSelfTest` 和 release 打包，全部通過才能合併。
- **SelfTest 擴充**，加入單元測試：
  - KeyMap 對照與修飾鍵排序
  - KeystrokeStore 的分組、逾時和過濾
  - CourseMode 的序列化
  - SRT 時間格式
  - 白板匯出 PDF 的頁數
- **手動驗收清單**（每期附在 PR 中）：
  - 全新使用者首次啟動的權限流程
  - 每個快捷鍵
  - 多螢幕操作
  - 用 ZoomIt 錄影 3 分鐘，確認按鍵、聚光燈、字幕都有被錄入
  - 在 Google Meet 分享畫面，觀眾端看得到效果

## 交付節奏
- 每一期一個分支加一個 draft PR，先合併到 `claude/inspiring-mendel-tu4csa`。
- 總時程約 11–13 週，可依優先順序調整。建議 M0→M2 先完成可用的 MVP。
