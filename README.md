<p align="center"><img src="docs/icon.png" width="160" alt="TeachLens 圖示"></p>

<h1 align="center">TeachLens</h1>

<p align="center">給 Mac 線上教學講師的螢幕講解工具：按鍵顯示 · Windows 對照 · 聚光燈 · 放大鏡 · 畫筆標註 · 即時字幕 · 課程模式 · 錄影</p>

<p align="center"><b>Fork 開發：<a href="https://www.facebook.com/Journal.of.Digital.Narrative">數位敘事力期刊 Journal of Digital Narrative</a></b></p>

<p align="center">
  <a href="https://github.com/FW1201/TeachLens/releases/latest">⬇︎ 下載最新版</a> ·
  <a href="#安裝">安裝</a> ·
  <a href="#快速上手">快速上手</a> ·
  <a href="#功能說明">功能說明</a> ·
  <a href="#常見問題">常見問題</a> ·
  <a href="docs/DEVELOPMENT.md">開發者文件</a>
</p>

> English summary: TeachLens is a free, open-source macOS menu-bar toolkit for online teaching — keystroke display with Windows equivalents, spotlight, zoom, on-screen drawing, live captions with transcript export, course-mode presets and screen recording. Download the DMG from [Releases](https://github.com/FW1201/TeachLens/releases). Built on ZoomIt for Mac (MIT) and Keyviz (GPL-3.0); licensed GPL-3.0.

---

## 為什麼用 TeachLens

線上授課、錄製教學影片或示範操作時，學生常看不到你按了什麼、滑鼠在哪、你正在講哪一塊。TeachLens 常駐在選單列，一個快捷鍵就能：

- **讓學生看到你按的快捷鍵**：⌘⇧4、⌥←、⌘ 點擊……即時顯示在畫面上。
- **同步顯示 Windows 對照**：⌘C 下方顯示 Ctrl + C，用 Windows 的學生也跟得上。
- **把視線帶到重點**：聚光燈、游標光圈、搖動找游標、放大鏡、畫筆標註。
- **自動上字幕**：講話即時轉成字幕，課後匯出 .srt 逐字稿。
- **一鍵切換課程情境**：講解、程式示範、重點強調、休息。

<!-- 截圖：06-keystrokes-hud.png（主視覺） -->
<p align="center"><img src="docs/screenshots/06-keystrokes-hud.png" width="720" alt="按鍵顯示畫面（待補截圖）"></p>

---

## 系統需求

| 項目 | 需求 |
|---|---|
| macOS | 14 Sonoma 以上（macOS 26 以上會顯示 Liquid Glass 樣式） |
| 晶片 | Apple Silicon 與 Intel 皆可（Universal） |
| 權限 | 螢幕錄製、輸入監控；使用字幕時另需麥克風、語音辨識 |
| 費用 | 免費、開源（GPL-3.0），只在 GitHub 發佈，不上架 App Store |

---

## 安裝

### 1. 下載

到 **[Releases 頁面](https://github.com/FW1201/TeachLens/releases/latest)** 下載 `TeachLens-版本.dmg`。

### 2. 拖進「應用程式」

打開 DMG，把 **TeachLens** 拖到 **Applications（應用程式）**。

<!-- 截圖：01-dmg-window.png -->
<p align="center"><img src="docs/screenshots/01-dmg-window.png" width="560" alt="DMG 視窗（待補截圖）"></p>

### 3. 第一次開啟（略過 Gatekeeper）

TeachLens 是開源免費版本，沒有付費向 Apple 公證，第一次開啟會被系統擋下。任選一種方式：

- **方法 A（系統設定，不用打指令）**
  1. 先雙擊 TeachLens 一次，出現被擋的訊息就按「完成」。
  2. 打開 **系統設定 ▸ 隱私權與安全性**，捲到最下面的「安全性」區塊。
  3. 按「已阻擋 TeachLens…」旁的 **強制打開（Open Anyway）**，輸入密碼或用 Touch ID 確認，再按 **打開**。
- **方法 B（終端機一行指令）**：打開「終端機」，貼上：

  ```bash
  xattr -dr com.apple.quarantine "/Applications/TeachLens.app"
  ```

> macOS 15 Sequoia 以後，「右鍵 ▸ 打開」已無法略過這個限制，請用上面兩種方法。macOS 14 仍可用右鍵 ▸ 打開。

<!-- 截圖：02-gatekeeper-open.png -->
<p align="center"><img src="docs/screenshots/02-gatekeeper-open.png" width="420" alt="系統設定的強制打開按鈕（待補截圖）"></p>

> 若出現「已損毀，無法打開」，同樣用方法 B 解決；這是未公證 App 的系統提示，不是檔案真的壞掉。

### 4. 開啟權限

TeachLens 會在需要時請求權限，也可以從選單列 **TeachLens ▸ Check Permissions** 一次檢查：

| 權限 | 用途 | 位置（系統設定 ▸ 隱私權與安全性） |
|---|---|---|
| 螢幕錄製 | 放大鏡、截圖、錄影 | 螢幕與系統錄音 |
| 輸入監控 | 顯示按鍵與滑鼠點擊 | 輸入監控 |
| 麥克風 | 即時字幕、錄影收音 | 麥克風 |
| 語音辨識 | 即時字幕 | 語音辨識 |
| 相機（選用） | 錄影時的子母畫面 | 相機 |

**開啟「螢幕錄製」或「輸入監控」後，請結束並重新打開 TeachLens 才會生效。**

<!-- 截圖：03-permissions-dialog.png、04-input-monitoring.png -->
<p align="center">
  <img src="docs/screenshots/03-permissions-dialog.png" width="380" alt="權限對話框（待補截圖）">
  <img src="docs/screenshots/04-input-monitoring.png" width="380" alt="輸入監控設定（待補截圖）">
</p>

### 更新與移除

- **更新**：下載新版 DMG，覆蓋「應用程式」裡的 TeachLens 即可，設定會保留。
- **移除**：把 TeachLens 丟到垃圾桶；如要連設定一起清除，在終端機執行 `defaults delete io.github.fw1201.teachlens`。

---

## 快速上手

TeachLens 沒有 Dock 圖示，執行後在**畫面右上角選單列**出現金色放大鏡圖示，所有功能都在這裡。

<!-- 截圖：05-menu-bar.png -->
<p align="center"><img src="docs/screenshots/05-menu-bar.png" width="360" alt="選單列選單（待補截圖）"></p>

**五分鐘上課流程：**

1. 上課前：選單列 ▸ **課程模式 ▸ 講解**（開啟按鍵顯示、游標強調、字幕）。
2. 示範快捷鍵：直接按，學生會看到畫面下方的按鍵膠囊；需要時開啟 **Windows 對照**。
3. 要強調某一區：按 **⌃⇧0** 開聚光燈，或 **⌃1** 放大後用滑鼠畫重點。
4. 下課休息：**課程模式 ▸ 休息**（自動開啟倒數計時）。
5. 課後：**字幕選項 ▸ 匯出逐字稿（.srt）**。

### 快捷鍵總表

| 功能 | 預設快捷鍵 |
|---|---|
| 顯示／隱藏按鍵 | ⌃0 |
| 聚光燈 | ⌃⇧0 |
| 即時字幕 | ⌃⇧C |
| 多頁白板 | ⌃⇧W |
| 靜態放大（凍結畫面） | ⌃1 |
| 畫筆標註（不放大） | ⌃2 |
| 休息計時器 | ⌃3 |
| 即時放大 | ⌃4 |
| 錄製全螢幕／區域 | ⌃5／⌃⇧5 |
| 截圖到剪貼簿／存檔／文字辨識 | ⌃6／⌃⇧6／⌃⌥6 |
| DemoMirror 鏡像 | ⌃9 |
| 長截圖到剪貼簿／存檔 | ⌃8／⌃⇧8 |

所有快捷鍵都能在 **Settings（設定）** 修改；設定時若和其他功能衝突，會顯示橘色警告。

---

## 設定與測試

選單列 ▸ **設定…** 打開設定視窗。左側分成兩組：

- **教學**：總覽與測試、按鍵顯示、聚光燈、字幕、課程模式、白板
- **ZoomIt 工具**：一般、放大、即時放大、畫筆、文字、DemoType、休息計時、截圖、錄影、長截圖、DemoMirror

**介面語言**：設定 ▸ 一般 ▸ 語言，可選「跟隨系統／繁體中文／English」，切換後立即生效。

### 總覽與測試（上課前先看這頁）

- **這個版本**：顯示版本號、建置 commit，以及是開發版還是正式版；「複製診斷資訊」可直接貼到問題回報。
- **課前檢查**：逐項顯示螢幕錄製、輸入監控、麥克風、語音辨識、相機是否已允許，未允許的可按「修正…」。
- **逐項測試**：每個功能都有「立即測試」按鈕，不用記快捷鍵。按鍵顯示有示範動畫（⌘C → ⇧⌘4 → ⌘Z ×3），**不需要任何權限**就能確認畫面效果；字幕也有不需要麥克風的示範。
- **課程模式試用**：逐一套用四種模式，最後按「回到原本設定」還原。
- **快捷鍵接收測試**：按任一 TeachLens 快捷鍵，這裡會顯示收到的功能名稱；沒有出現代表快捷鍵沒有送到 TeachLens（可能被其他 App 佔用）。

<!-- 截圖：20-check-and-test.png -->
<p align="center"><img src="docs/screenshots/20-check-and-test.png" width="560" alt="總覽與測試（待補截圖）"></p>

## 功能說明

### 1. 按鍵顯示（Keystrokes）

把你按的快捷鍵與滑鼠動作顯示在畫面上，學生不用猜你按了什麼。

- 修飾鍵依 Mac 慣例合併成一格（⌃⌥⇧⌘），主鍵用白色圓角塊。
- 連按同一組會顯示「×3」。
- 滑鼠：⌘ 點擊、⌥ 拖曳、滾輪都會顯示；點擊位置出現漣漪（左鍵白色、右鍵橘色）。
- 預設只顯示「快捷鍵」（有修飾鍵的組合），打字內容不會露出；改成「每個鍵」前會先提醒，避免分享螢幕時露出私人內容。
- 背景三選一：**Liquid Glass**（macOS 26+）、霧面、實色（錄影或背景很花時最清楚）。

<!-- 截圖：06-keystrokes-hud.png、08-keystrokes-settings.png -->
<p align="center">
  <img src="docs/screenshots/06-keystrokes-hud.png" width="420" alt="按鍵膠囊（待補截圖）">
  <img src="docs/screenshots/08-keystrokes-settings.png" width="380" alt="Keystrokes 設定（待補截圖）">
</p>

**設定位置**：選單列 ▸ Keystroke Options，或 Settings ▸ Keystrokes（位置、大小、停留秒數、歷史筆數、快捷鍵）。

### 2. Windows 對照

開啟後，每組 Mac 快捷鍵下方會出現藍色的「Windows 建議」對應按鍵，方便同時教 Mac 與 Windows 的學生。這是建議對照，實際快捷鍵可能依軟體而異。對照規則依 Apple 官方說明〈[Mac 上的 Windows 鍵盤對應鍵](https://support.apple.com/zh-hk/guide/mac-help/cpmh0038/mac)〉。

| Mac | Windows |
|---|---|
| ⌘C／⌘V／⌘Z | Ctrl + C／Ctrl + V／Ctrl + Z |
| ⇧⌘Z | Ctrl + Y |
| ⌘Q | Alt + F4 |
| ⌘Tab | Alt + Tab |
| ⌥⌘Esc（強制結束） | Ctrl + Alt + Delete |
| ⇧⌘3／⇧⌘4 | Print Screen／Win + Shift + S |
| ⌘←／⌘→ | Home／End |
| ⌥←／⌥→ | Ctrl + ←／Ctrl + → |
| ⌃ 點擊 | 右鍵 |
| Delete／fn + Delete | Backspace／Delete |

**開啟方式**：選單列 ▸ Keystroke Options ▸ **Windows 對照**，或 Settings ▸ Keystrokes ▸ 開啟 Windows 對照。

<!-- 截圖：07-windows-equivalent.png -->
<p align="center"><img src="docs/screenshots/07-windows-equivalent.png" width="520" alt="Windows 對照（待補截圖）"></p>

### 3. 聚光燈與游標強調（Spotlight）

- **聚光燈（⌃⇧0）**：畫面變暗，只亮滑鼠周圍；形狀可選圓形或「寬條」（適合逐行讀文字）。
- **游標光圈**：滑鼠外圍一圈彩色光環（黃、青、粉、綠）。
- **搖動找游標**：左右快速搖動滑鼠，游標位置會出現放大光圈。

調整：選單列 ▸ Spotlight Options，或 Settings ▸ Spotlight（大小、暗度、顏色、快捷鍵）。

<!-- 截圖：09-spotlight.png、10-cursor-highlight.png -->
<p align="center">
  <img src="docs/screenshots/09-spotlight.png" width="400" alt="聚光燈（待補截圖）">
  <img src="docs/screenshots/10-cursor-highlight.png" width="400" alt="游標強調（待補截圖）">
</p>

### 4. 放大鏡與畫筆標註（Zoom & Draw）

| 操作 | 說明 |
|---|---|
| ⌃1 | 凍結畫面並放大；滾輪或 ⌥↑／⌥↓ 調整倍率 |
| ⌃4 | 即時放大（畫面持續更新） |
| ⌃2 | 不放大，直接在畫面上畫 |
| 左鍵拖曳 | 畫筆；按住 Shift 畫直線、Control 畫矩形、Control+Shift 畫箭頭、Tab 畫橢圓 |
| R／G／B／O／Y／P／W／K | 紅、綠、藍、橘、黃、粉、白、黑；加 Shift 變螢光筆 |
| T | 打字標註（⇧T 靠右）；↑／↓ 或滾輪調整字級 |
| ⌃W／⌃K | 白板／黑板 |
| ⌘Z／E | 復原／清除 |
| ⌘C／⌘S | 複製／儲存目前畫面 |
| Esc 或右鍵 | 離開 |

<!-- 截圖：11-static-zoom.png、12-live-zoom.png -->
<p align="center">
  <img src="docs/screenshots/11-static-zoom.png" width="400" alt="靜態放大與標註（待補截圖）">
  <img src="docs/screenshots/12-live-zoom.png" width="400" alt="即時放大（待補截圖）">
</p>

### 5. 即時字幕與逐字稿（Live Captions）

- 按 **⌃⇧C** 開始，畫面下方即時顯示你說的話（兩行）；停頓後自動斷句。
- 語言：中文（台灣）、中文（简体）、English、日本語、한국어；支援的語言會在 Mac 本機辨識，不上傳雲端。
- **匯出**：字幕選項 ▸ 匯出逐字稿（.srt／.vtt／.txt）。
- **錄影字幕**：錄影時開著字幕，錄完選 **匯出上一段錄影的字幕（.srt）**，時間軸會對齊影片開頭，可直接匯入剪輯軟體或 YouTube。

<!-- 截圖：13-captions.png、14-caption-export.png -->
<p align="center">
  <img src="docs/screenshots/13-captions.png" width="420" alt="即時字幕（待補截圖）">
  <img src="docs/screenshots/14-caption-export.png" width="360" alt="匯出逐字稿（待補截圖）">
</p>

### 6. 課程模式（Course Modes）

一鍵切換整組設定，切換時右上角會短暫顯示目前模式：

| 模式 | 按鍵顯示 | 聚光燈 | 游標光圈 | 字幕 | 其他 |
|---|---|---|---|---|---|
| 講解 | 快捷鍵 | — | ✓ | ✓ | |
| 程式示範 | 每個鍵＋歷史、放大 1.25 倍 | — | ✓ | — | |
| 重點強調 | — | ✓ | — | — | |
| 休息 | — | — | — | — | 開啟休息計時器 |

- **自訂模式**：調好設定後選 **將目前設定存成模式…**。
- **分享模式**：**匯出模式…** 產生 JSON 檔，其他老師用 **匯入模式…** 載入。
- 重開 TeachLens 會回到上次的模式（不會自動開麥克風或計時器）。

<!-- 截圖：15-course-modes.png -->
<p align="center"><img src="docs/screenshots/15-course-modes.png" width="520" alt="課程模式（待補截圖）"></p>

### 7. 多頁白板（Whiteboard）

按 **⌃⇧W** 打開獨立白板視窗，適合推導、畫圖解或課堂板書：

- 背景：白板、黑板、方格、橫線（每頁可不同）。
- 工具：畫筆（P）、螢光筆（H）、橡皮擦（E），7 種顏色、可調粗細。
- 換頁：← → 鍵或工具列的 ‹ ›；**頁面** 選單可新增、刪除、清除本頁、復原（⌘Z）。
- **插入螢幕截圖為新頁面**：把目前畫面拍下來放進白板再標註。
- **匯出**：全部頁面存成一個 PDF，或本頁存成 PNG。
- 白板內容自動保存，下次打開會接續上次的頁面。

<!-- 截圖：19-whiteboard.png -->
<p align="center"><img src="docs/screenshots/19-whiteboard.png" width="560" alt="多頁白板（待補截圖）"></p>

### 8. 休息計時器、截圖、錄影

- **⌃3 休息計時器**：全螢幕倒數，可設定時間、顏色、背景圖與提示音（Settings ▸ Break）。
- **⌃6 截圖**：拖曳範圍複製到剪貼簿；⌃⇧6 存檔；⌃⌥6 辨識文字（OCR）。
- **⌃8 長截圖**：選取範圍後捲動，自動拼接成一張長圖。
- **⌃5 錄影**：全螢幕或區域（⌃⇧5），可收系統聲音、麥克風、加相機子母畫面；結束後可剪輯、淡入淡出再存檔。按鍵顯示與畫筆標註都會錄進影片。

<!-- 截圖：16-break-timer.png、17-recording-editor.png -->
<p align="center">
  <img src="docs/screenshots/16-break-timer.png" width="400" alt="休息計時器（待補截圖）">
  <img src="docs/screenshots/17-recording-editor.png" width="400" alt="錄影剪輯（待補截圖）">
</p>

### 搭配視訊會議

在 Google Meet、Zoom、Teams 選擇**分享整個螢幕**（不是只分享單一視窗），學生才看得到按鍵顯示、聚光燈與字幕。

---

## 常見問題

**下載後被 Mac 擋下、無法打開或顯示「已損毀」？**
這是未經 Apple 公證的開源 App 的正常提示，檔案沒有壞。到 **系統設定 ▸ 隱私權與安全性**，按 TeachLens 旁的 **強制打開**；或在終端機執行 `xattr -dr com.apple.quarantine "/Applications/TeachLens.app"`。詳見 [安裝步驟 3](#3-第一次開啟略過-gatekeeper)。

**按鍵沒有顯示？**
確認「輸入監控」已開啟 TeachLens，並**重新開啟 App**。選單列 ▸ Check Permissions 可檢查狀態。預設只顯示快捷鍵，單純打字不會出現；要顯示全部，到 Keystroke Options 取消「Shortcuts Only」。

**按 ⌃1 一直跳出螢幕錄製設定？**
在系統設定開啟「螢幕錄製」後要重開 TeachLens。若仍失敗，在終端機執行 `tccutil reset ScreenCapture io.github.fw1201.teachlens` 後重新授權。

**字幕沒有反應？**
確認「麥克風」「語音辨識」都已允許；選單列 ▸ 字幕選項確認語言正確。

**快捷鍵和其他 App 衝突？**
到 Settings 對應分頁點快捷鍵按鈕重新錄製；按 Esc 取消。

**為什麼不上 App Store？**
App Store 版必須放進沙盒，會失去 DemoType 等功能，審核也較慢。TeachLens 選擇以開源方式在 GitHub 發佈，原始碼公開可檢查。

---

## 出處與授權

**Fork 開發：[數位敘事力期刊 Journal of Digital Narrative](https://www.facebook.com/Journal.of.Digital.Narrative)**

TeachLens 由兩個開源專案改作而成：

| 專案 | 作者 | 授權 | 用途 |
|---|---|---|---|
| [ZoomIt for Mac](https://github.com/microsoft/Zoomit-Mac) | Microsoft Corporation | MIT | App 主體：放大、畫筆、計時器、截圖、錄影（上游 commit `45e15ac`） |
| [Keyviz](https://github.com/mulaRahul/keyviz) | Rahul Mula | GPL-3.0 | 按鍵與滑鼠顯示（以 Swift 重寫；原始碼保留於 [`Legacy/keyviz/`](Legacy/keyviz/)） |

TeachLens 整體以 **GNU GPL-3.0** 授權（[LICENSE](LICENSE)），ZoomIt for Mac 的 MIT 授權全文見 [ThirdParty/ZoomIt-Mac-LICENSE.txt](ThirdParty/ZoomIt-Mac-LICENSE.txt)，完整說明見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。TeachLens 與 Microsoft、Sysinternals、Keyviz 專案無隸屬或背書關係。

<!-- 截圖：18-settings-about.png -->
<p align="center"><img src="docs/screenshots/18-settings-about.png" width="420" alt="設定視窗出處（待補截圖）"></p>

開發、建置與發佈流程請見 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)；截圖待補清單見 [docs/screenshots/README.md](docs/screenshots/README.md)。
