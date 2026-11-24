import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
private final class LinkButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// A tabbed preferences window modeled on the Windows ZoomIt options dialog,
/// exposing the Zoom, Draw, and Type settings that TeachLens supports. Each tab
/// carries the same kind of descriptive help text the Windows dialog shows.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let settingsStore: SettingsStore
    private let onHotKeyChange: () -> Void
    private let onSuspendHotkeys: () -> Void
    private let onResumeHotkeys: () -> Void
    private let onRequestMicrophone: () -> Void
    private let onRequestSpeechRecognition: () -> Void
    private let onRequestCamera: () -> Void
    private let onOpenTrimEditor: () -> Void
    private let userSelectedResourceAccess: UserSelectedResourceAccess
    private var settings: AppSettings
    private let keystrokeController: KeystrokeController?
    private let spotlightController: SpotlightController?
    private let teaching: TeachingControllers?

    private static let homepageURLString = "https://github.com/FW1201/TeachLens"
    private static let contentWidth: CGFloat = 540
    private static let panelHorizontalInset: CGFloat = 28
    private static let wrappedLabelWidth: CGFloat = contentWidth - panelHorizontalInset * 2

    private var window: NSWindow?
    /// The pane content switcher. Its own tab strip is hidden; selection is
    /// driven by the sidebar list (see `makeWindow`).
    private weak var settingsTabView: NSTabView?
    /// The source-list sidebar that selects the visible pane.
    private weak var sidebarTableView: NSTableView?
    private static let sidebarWidth: CGFloat = 190
    private static let sidebarRowHeight: CGFloat = 28
    /// Vertical room reserved in the sidebar for the product/copyright/link
    /// footer beneath the pane list.
    private static let sidebarFooterAllowance: CGFloat = 90

    // Type tab controls.
    private weak var fontSampleLabel: NSTextField?

    // General tab controls.
    private weak var launchAtLoginCheckbox: NSButton?

    // Record tab controls.
    private weak var recordMicrophonePopup: NSPopUpButton?
    private weak var noiseCancellationCheckbox: NSButton?

    // Snip tab controls.
    private weak var snipMicrophonePopup: NSPopUpButton?
    private weak var snipSaveDirectoryField: NSTextField?
    private weak var snipSaveDirectoryBrowseButton: NSButton?

    #if !TEACHLENS_APP_STORE
    // DemoType tab controls.
    private weak var demoTypeFileField: NSTextField?
    #endif

    // Webcam controls.
    private weak var webcamDevicePopup: NSPopUpButton?
    private weak var webcamPositionPopup: NSPopUpButton?
    private weak var webcamSizePopup: NSPopUpButton?
    private weak var webcamShapePopup: NSPopUpButton?

    // Break tab controls.
    private weak var breakDurationLabel: NSTextField?
    private weak var breakSoundFileField: NSTextField?
    private weak var breakBackgroundModePopup: NSPopUpButton?
    private weak var breakBackgroundFileField: NSTextField?
    private weak var breakBackgroundBrowseButton: NSButton?
    private weak var breakBackgroundStretchCheckbox: NSButton?

    // Hotkey recorders.
    private enum HotKeyTarget {
        case zoom
        case draw
        case live
        case breakTimer
        case snip
        case snipOcr
        case record
        #if !TEACHLENS_APP_STORE
        case demoType
        #endif
        case panorama
        case demoMirror
    }
    private weak var hotKeyButton: NSButton?
    private weak var drawHotKeyButton: NSButton?
    private weak var liveHotKeyButton: NSButton?
    private weak var breakHotKeyButton: NSButton?
    private weak var snipHotKeyButton: NSButton?
    private weak var snipOcrHotKeyButton: NSButton?
    private weak var recordHotKeyButton: NSButton?
    #if !TEACHLENS_APP_STORE
    private weak var demoTypeHotKeyButton: NSButton?
    #endif
    private weak var panoramaHotKeyButton: NSButton?
    private weak var demoMirrorHotKeyButton: NSButton?
    private weak var demoMirrorTrackWindowCheckbox: NSButton?
    private var hotKeyMonitor: Any?
    private var recordingTarget: HotKeyTarget?

    init(
        settingsStore: SettingsStore,
        onHotKeyChange: @escaping () -> Void,
        onSuspendHotkeys: @escaping () -> Void,
        onResumeHotkeys: @escaping () -> Void,
        onRequestMicrophone: @escaping () -> Void,
        onRequestSpeechRecognition: @escaping () -> Void,
        onRequestCamera: @escaping () -> Void,
        onOpenTrimEditor: @escaping () -> Void,
        userSelectedResourceAccess: UserSelectedResourceAccess,
        keystrokeController: KeystrokeController? = nil,
        spotlightController: SpotlightController? = nil,
        teaching: TeachingControllers? = nil
    ) {
        self.teaching = teaching
        self.keystrokeController = keystrokeController
        self.spotlightController = spotlightController
        self.settingsStore = settingsStore
        self.onHotKeyChange = onHotKeyChange
        self.onSuspendHotkeys = onSuspendHotkeys
        self.onResumeHotkeys = onResumeHotkeys
        self.onRequestMicrophone = onRequestMicrophone
        self.onRequestSpeechRecognition = onRequestSpeechRecognition
        self.onRequestCamera = onRequestCamera
        self.onOpenTrimEditor = onOpenTrimEditor
        self.userSelectedResourceAccess = userSelectedResourceAccess
        self.settings = settingsStore.load()
        super.init()
    }

    /// Builds the window without showing it. Building and measuring every pane
    /// takes a noticeable moment, so the app does it while idle after launch
    /// and the first "Settings…" opens instantly.
    func prepareWindow() {
        guard window == nil else { return }
        settings = settingsStore.load()
        window = makeWindow()
    }

    func show() {
        // Always reflect the latest persisted values when re-opening.
        settings = settingsStore.load()

        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }
        hotKeyButton?.title = zoomHotKeyDisplayString()
        drawHotKeyButton?.title = drawHotKeyDisplayString()
        liveHotKeyButton?.title = liveHotKeyDisplayString()
        breakHotKeyButton?.title = breakHotKeyDisplayString()
        snipHotKeyButton?.title = snipHotKeyDisplayString()
        snipOcrHotKeyButton?.title = snipOcrHotKeyDisplayString()
        recordHotKeyButton?.title = recordHotKeyDisplayString()
        #if !TEACHLENS_APP_STORE
        demoTypeHotKeyButton?.title = demoTypeHotKeyDisplayString()
        #endif
        panoramaHotKeyButton?.title = panoramaHotKeyDisplayString()
        demoMirrorHotKeyButton?.title = demoMirrorHotKeyDisplayString()
        launchAtLoginCheckbox?.state = settings.launchAtLogin ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Cancel any in-progress recording (which resumes the global hotkeys if
        // they were suspended for capture).
        finishRecording()
    }

    // MARK: - Window construction

    /// The Options dialog tabs, in order. Zoom and Live Zoom are separate tabs
    /// (matching Windows ZoomIt, whose Zoom tab holds static-zoom settings only).
    /// Pane IDs (stable, English) in sidebar order: TeachLens's teaching
    /// panes first, then the tools inherited from ZoomIt.
    static let teachingPaneIDs = ["Check", "Keystrokes", "Spotlight", "Captions", "Modes", "Whiteboard"]

    static var toolPaneIDs: [String] {
        var titles = ["General", "Zoom", "Live Zoom", "Draw", "Type"]
        #if !TEACHLENS_APP_STORE
        titles.append("DemoType")
        #endif
        titles.append(contentsOf: ["Break", "Snip", "Record", "Panorama", "DemoMirror"])
        return titles
    }

    static var settingsTabTitles: [String] { teachingPaneIDs + toolPaneIDs }

    /// The localized name shown for a pane ID.
    static func displayTitle(for id: String) -> String {
        switch id {
        case "Check": return L10n.t("Check & Test", "總覽與測試")
        case "Keystrokes": return L10n.t("Keystrokes", "按鍵顯示")
        case "Spotlight": return L10n.t("Spotlight", "聚光燈")
        case "Captions": return L10n.t("Captions", "字幕")
        case "Modes": return L10n.t("Course Modes", "課程模式")
        case "Whiteboard": return L10n.t("Whiteboard", "白板")
        case "General": return L10n.t("General", "一般")
        case "Zoom": return L10n.t("Zoom", "放大")
        case "Live Zoom": return L10n.t("Live Zoom", "即時放大")
        case "Draw": return L10n.t("Draw", "畫筆")
        case "Type": return L10n.t("Type", "文字")
        case "Break": return L10n.t("Break", "休息計時")
        case "Snip": return L10n.t("Snip", "截圖")
        case "Record": return L10n.t("Record", "錄影")
        case "Panorama": return L10n.t("Panorama", "長截圖")
        default: return id
        }
    }

    private enum SidebarRow {
        case header(String)
        case pane(String)
    }

    private static var sidebarRows: [SidebarRow] {
        [.header(L10n.t("Teaching", "教學"))] + teachingPaneIDs.map { .pane($0) }
            + [.header(L10n.t("ZoomIt Tools", "ZoomIt 工具"))] + toolPaneIDs.map { .pane($0) }
    }

    private func viewForTab(_ title: String) -> NSView {
        switch title {
        case "General": return makeGeneralTab()
        case "Keystrokes": return makeKeystrokesTab()
        case "Spotlight": return makeSpotlightTab()
        case "Check": return hostTeachingPane { CheckAndTestPane(controllers: $0) }
        case "Captions": return hostTeachingPane { CaptionSettingsPane(controller: $0.captions) }
        case "Modes": return hostTeachingPane { CourseModeSettingsPane(controller: $0.courseModes) }
        case "Whiteboard": return hostTeachingPane { WhiteboardSettingsPane(controller: $0.whiteboard) }
        case "Zoom": return makeZoomTab()
        case "Live Zoom": return makeLiveZoomTab()
        case "Draw": return makeDrawTab()
        case "Type": return makeTypeTab()
        #if !TEACHLENS_APP_STORE
        case "DemoType": return makeDemoTypeTab()
        #endif
        case "Break": return makeBreakTab()
        case "Snip": return makeSnipTab()
        case "Record": return makeRecordTab()
        case "Panorama": return makePanoramaTab()
        case "DemoMirror": return makeDemoMirrorTab()
        default: return NSView()
        }
    }

    private func hostTeachingPane<V: View>(_ make: (TeachingControllers) -> V) -> NSView {
        guard let teaching else { return NSView() }
        return NSHostingView(rootView: make(teaching).frame(width: Self.contentWidth, height: 460))
    }

    /// Rebuilds the window in the newly chosen language.
    func reloadForLanguageChange() {
        let wasVisible = window?.isVisible ?? false
        window?.orderOut(nil)
        window = nil
        if wasVisible { show() }
    }

    private func makeWindow() -> NSWindow {
        // Build each tab's content and measure the tallest one so every tab can
        // share a single height. Equal-height tabs keep the tab view a constant
        // size, which in turn keeps the footer anchored near the bottom no
        // matter which tab is selected.
        let tabs: [(String, NSView)] = Self.settingsTabTitles.map { title in
            (title, viewForTab(title))
        }

        var maxContentHeight: CGFloat = 0
        for (_, content) in tabs {
            content.translatesAutoresizingMaskIntoConstraints = false
            let widthConstraint = content.widthAnchor.constraint(equalToConstant: Self.contentWidth)
            widthConstraint.isActive = true
            content.layoutSubtreeIfNeeded()
            maxContentHeight = max(maxContentHeight, content.fittingSize.height)
            widthConstraint.isActive = false
        }

        // Add only a small cushion beyond the tallest tab; the tab contents
        // already carry their own bottom inset.
        let tabContentHeight = maxContentHeight + 4

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        // The native tab strip is a single row that can't wrap, and with 11
        // tabs it no longer fits the window's width. Hide it (keeping the
        // bezel border around the content) and drive selection from a custom
        // two-row button bar built below instead.
        tabView.tabViewType = .noTabsNoBorder
        for (label, content) in tabs {
            // The holder is frame-managed so NSTabView resizes it to fill the
            // content area; the content is pinned to the holder's top so every
            // tab shares the same top margin regardless of window position.
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = true
            holder.autoresizingMask = [.width, .height]
            holder.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: tabContentHeight)
            content.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: holder.topAnchor),
                content.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
            ])
            tabView.addTabViewItem(makeTabItem(label: label, view: holder))
        }

        // Fix the tab view's size so its content area is exactly
        // contentWidth × tabContentHeight on every tab. The chrome (tab strip and
        // borders) is measured from a probe frame.
        tabView.frame = NSRect(x: 0, y: 0, width: Self.contentWidth + 24, height: tabContentHeight + 60)
        tabView.layoutSubtreeIfNeeded()
        let measuredChromeWidth = tabView.frame.width - tabView.contentRect.width
        let measuredChromeHeight = tabView.frame.height - tabView.contentRect.height
        let chromeWidth = measuredChromeWidth > 0 ? measuredChromeWidth : 14
        let chromeHeight = measuredChromeHeight > 4 ? measuredChromeHeight : 34
        NSLayoutConstraint.activate([
            tabView.widthAnchor.constraint(equalToConstant: Self.contentWidth + chromeWidth),
            tabView.heightAnchor.constraint(equalToConstant: tabContentHeight + chromeHeight)
        ])
        settingsTabView = tabView

        let outer = NSStackView(views: [tabView])
        outer.orientation = .vertical
        outer.alignment = .centerX
        outer.spacing = 12
        outer.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        outer.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outer.topAnchor.constraint(equalTo: container.topAnchor),
            outer.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TeachLens"
        window.contentViewController = makeSplitViewController(content: container)
        window.isReleasedWhenClosed = false
        window.delegate = self
        Self.configureAlwaysOnTop(window)

        // Size the window to fit the tallest pane, leaving room for the sidebar
        // alongside it and keeping it tall enough that the sidebar's full pane
        // list and its footer fit without scrolling.
        container.layoutSubtreeIfNeeded()
        let fitting = container.fittingSize
        let sidebarNeededHeight = CGFloat(Self.sidebarRows.count) * Self.sidebarRowHeight
            + Self.sidebarFooterAllowance
        window.setContentSize(NSSize(
            width: max(fitting.width + Self.sidebarWidth, 480),
            height: max(fitting.height, sidebarNeededHeight, 360)
        ))
        return window
    }

    /// Presents the panes with a source-list sidebar, the same arrangement
    /// System Settings uses. A sidebar keeps all panes visible at once; the
    /// preferences toolbar this replaced pushed the last few into an overflow
    /// menu once there were too many to fit the window's width.
    private func makeSplitViewController(content: NSView) -> NSSplitViewController {
        let sidebarController = NSViewController()
        sidebarController.view = makeSidebarView()

        let contentController = NSViewController()
        contentController.view = content

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth

        let splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: contentController))
        return splitViewController
    }

    private func makeSidebarView() -> NSView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = Self.sidebarRowHeight
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true

        sidebarTableView = tableView
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        // The product/copyright/link block sits at the foot of the sidebar.
        let footer = makeFooter(maxWidth: Self.sidebarWidth - 16)
        let container = NSView()
        container.addSubview(scrollView)
        container.addSubview(footer)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    /// Configures the settings window to behave like the Windows Options dialog:
    /// it floats above other windows so it can never get lost behind them. If it
    /// did, TeachLens's hotkeys (suspended while the dialog is open) would stay
    /// suspended and the app would appear broken with no obvious way to recover.
    static func configureAlwaysOnTop(_ window: NSWindow) {
        window.level = .floating
        window.hidesOnDeactivate = false
    }

    private func makeTabItem(label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    /// Returns the SF Symbol shown beside each pane's name in the sidebar.
    static func paneSymbolName(for title: String) -> String {
        switch title {
        case "General": return "gearshape"
        case "Keystrokes": return "command"
        case "Spotlight": return "light.max"
        case "Check": return "checklist"
        case "Captions": return "captions.bubble"
        case "Modes": return "square.stack"
        case "Whiteboard": return "scribble"
        case "Zoom": return "plus.magnifyingglass"
        case "Live Zoom": return "magnifyingglass.circle"
        case "Draw": return "pencil.tip"
        case "Type": return "textformat"
        case "DemoType": return "keyboard"
        case "Break": return "timer"
        case "Snip": return "camera.viewfinder"
        case "Record": return "record.circle"
        case "Panorama": return "pano"
        case "DemoMirror": return "rectangle.on.rectangle"
        default: return "square"
        }
    }

    // MARK: - Sidebar list

    func numberOfRows(in tableView: NSTableView) -> Int {
        Self.sidebarRows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = Self.sidebarRows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .pane = Self.sidebarRows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rows = Self.sidebarRows
        guard rows.indices.contains(row) else { return nil }
        let title: String
        switch rows[row] {
        case .header(let text):
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            let cell = NSTableCellView()
            cell.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3)
            ])
            return cell
        case .pane(let id):
            title = id
        }

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: Self.paneSymbolName(for: title),
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        imageView.contentTintColor = .controlAccentColor
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: Self.displayTitle(for: title))
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        let cell = NSTableCellView()
        cell.addSubview(stack)
        cell.textField = label
        cell.imageView = imageView
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let sidebarTableView, let settingsTabView else { return }
        let row = sidebarTableView.selectedRow
        guard Self.sidebarRows.indices.contains(row), case .pane(let id) = Self.sidebarRows[row] else { return }
        settingsTabView.selectTabViewItem(withIdentifier: id)
    }

    /// Two short lines: version + commit, and the fork credit link.
    private func makeFooter(maxWidth: CGFloat) -> NSView {
        let title = makeLabel("\(AppInfo.productName) \(AppInfo.version) · \(AppInfo.commit)")
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail

        let forkLink = LinkButton(title: AppInfo.forkCredit, target: self, action: #selector(openForkPage(_:)))
        forkLink.isBordered = false
        forkLink.bezelStyle = .inline
        forkLink.attributedTitle = NSAttributedString(
            string: AppInfo.forkCredit,
            attributes: [.foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        forkLink.toolTip = AppInfo.forkURL

        let stack = NSStackView(views: [title, forkLink])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        return stack
    }

    /// Builds a borderless button styled as a web hyperlink to the TeachLens
    /// home page.
    private func makeLink(title: String) -> NSButton {
        let button = LinkButton(title: title, target: self, action: #selector(openHomepage(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        button.toolTip = SettingsWindowController.homepageURLString
        button.setAccessibilityRole(.link)
        return button
    }

    @objc private func openForkPage(_ sender: Any?) {
        guard let url = URL(string: AppInfo.forkURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openHomepage(_ sender: Any?) {
        guard let url = URL(string: SettingsWindowController.homepageURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func makeColumn(_ rows: [NSView], spacing: CGFloat = 14) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: Self.panelHorizontalInset, bottom: 12, right: Self.panelHorizontalInset)
        return stack
    }

    private func makeLabel(_ text: String, wraps: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        if wraps {
            field.lineBreakMode = .byWordWrapping
            field.maximumNumberOfLines = 0
            field.preferredMaxLayoutWidth = Self.wrappedLabelWidth
        }
        return field
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let field = makeLabel(text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return field
    }

    private func makeRow(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    /// Creates a checkbox styled like the Windows ZoomIt options dialog, where
    /// the caption sits to the left of the box (BS_LEFTTEXT). Grouping several
    /// of these in a `makeCheckboxColumn` lines their boxes up in a single
    /// right-hand column, matching the Windows layout.
    private func makeCheckbox(_ title: String, action: Selector, state: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.imagePosition = .imageRight
        button.state = state ? .on : .off
        return button
    }

    /// Stacks Windows-style checkboxes so their boxes align in a right-hand
    /// column, the way the TeachLens options dialog aligns them.
    private func makeCheckboxColumn(_ checkboxes: [NSView], spacing: CGFloat = 6) -> NSView {
        let stack = NSStackView(views: checkboxes)
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = spacing
        return stack
    }

    private func makeIndentedColumn(_ rows: [NSView], indent: CGFloat = 18, spacing: CGFloat = 6) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: indent, bottom: 0, right: 0)
        return stack
    }

    /// Lays out label/control rows in a grid so the leading labels form a
    /// right-aligned column and the controls line up in consistent columns.
    /// Rows may have differing numbers of cells; trailing cells are left empty.
    private func makeFormGrid(_ rows: [[NSView]], rowSpacing: CGFloat = 10, columnSpacing: CGFloat = 8) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = rowSpacing
        grid.columnSpacing = columnSpacing
        // Center controls vertically within each row so labels line up with
        // popups, steppers and checkboxes regardless of their heights.
        grid.rowAlignment = .none
        for r in 0..<grid.numberOfRows {
            for c in 0..<grid.numberOfColumns {
                grid.cell(atColumnIndex: c, rowIndex: r).yPlacement = .center
            }
        }
        if grid.numberOfColumns > 0 {
            // Right-align the leading label column so the controls in column 1
            // share a common left edge.
            grid.column(at: 0).xPlacement = .trailing
        }
        return grid
    }

    // MARK: - General tab

    private func makeGeneralTab() -> NSView {
        let help = makeLabel(
            L10n.t("TeachLens runs in the menu bar. Choose a pane on the left to set it up.", "TeachLens 常駐在選單列。從左側選擇要設定的功能。"),
            wraps: true
        )

        let launchCheck = NSButton(checkboxWithTitle: L10n.t("Launch TeachLens when I log in", "登入時自動啟動 TeachLens"), target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheck.state = settings.launchAtLogin ? .on : .off
        launchCheck.isEnabled = LaunchAtLogin.isAvailable
        if !LaunchAtLogin.isAvailable {
            launchCheck.toolTip = L10n.t("Launch at login requires running TeachLens from TeachLens.app.", "必須從 TeachLens.app 執行才能設定登入時啟動。")
        }
        launchAtLoginCheckbox = launchCheck

        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for language in AppLanguage.allCases {
            languagePopup.addItem(withTitle: language.title)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        let languageRow = makeRow([makeLabel(L10n.t("Language:", "語言：")), languagePopup])

        let aboutTitle = makeSectionLabel(L10n.t("About", "關於"))
        let about = makeLabel(
            "\(AppInfo.productName) \(AppInfo.version) (\(AppInfo.commit))\n\(AppInfo.copyright)\n\(AppInfo.attribution)",
            wraps: true
        )
        about.textColor = .secondaryLabelColor
        let link = makeLink(title: "github.com/FW1201/TeachLens")

        return makeColumn([help, launchCheck, languageRow, aboutTitle, about, link])
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: raw), language != L10n.language else { return }
        L10n.language = language
        NotificationCenter.default.post(name: L10n.didChangeNotification, object: nil)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let enable = sender.state == .on
        settings.launchAtLogin = enable
        persist()
        do {
            try LaunchAtLogin.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("Couldn’t update the login item", "無法更新登入項目")
            alert.informativeText = L10n.t("TeachLens saved your startup preference and will try again next launch. macOS reported: \(error.localizedDescription)", "已保存設定，下次啟動時會再試一次。系統訊息：\(error.localizedDescription)")
            alert.addButton(withTitle: L10n.t("OK", "好"))
            alert.runModal()
        }
    }

    // MARK: - Keystrokes tab (TeachLens)

    private func makeKeystrokesTab() -> NSView {
        guard let keystrokeController else { return NSView() }
        let store = settingsStore
        let pane = KeystrokeSettingsPane(
            model: keystrokeController.observableModel,
            controller: keystrokeController,
            loadAppSettings: { store.load() }
        )
        .frame(width: Self.contentWidth, height: 460)
        return NSHostingView(rootView: pane)
    }

    private func makeSpotlightTab() -> NSView {
        guard let spotlightController else { return NSView() }
        let store = settingsStore
        let pane = SpotlightSettingsPane(controller: spotlightController, loadAppSettings: { store.load() })
            .frame(width: Self.contentWidth, height: 460)
        return NSHostingView(rootView: pane)
    }

    // MARK: - Zoom tab

    private func makeZoomTab() -> NSView {
        let help = makeLabel(
            L10n.t("Zoom with the mouse wheel or Option+↑/↓; exit with Esc or a right-click.", "用滑鼠滾輪或 ⌥↑／⌥↓ 調整倍率；按 Esc 或右鍵離開。"),
            wraps: true
        )

        let hotKeyButton = NSButton(title: zoomHotKeyDisplayString(), target: self, action: #selector(toggleZoomHotKeyRecording(_:)))
        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.setButtonType(.momentaryPushIn)
        hotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.hotKeyButton = hotKeyButton
        let hotKeyRow = makeRow([makeLabel(L10n.t("Zoom Toggle:", "放大快捷鍵：")), hotKeyButton])

        let magHelp = makeLabel(L10n.t("Specify the initial level of magnification when zooming in:", "放大時的初始倍率："), wraps: true)

        let magPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        magPopup.translatesAutoresizingMaskIntoConstraints = false
        for level in AppSettings.zoomLevels {
            magPopup.addItem(withTitle: String(format: "%gx", level))
        }
        let selectedIndex = AppSettings.zoomLevels.firstIndex(where: {
            abs($0 - settings.defaultZoomFactor) < 0.001
        }) ?? AppSettings.zoomLevels.firstIndex(of: 2.0) ?? 0
        magPopup.selectItem(at: selectedIndex)
        magPopup.target = self
        magPopup.action = #selector(zoomLevelChanged(_:))
        let magRow = makeRow([makeLabel(L10n.t("Initial magnification:", "初始倍率：")), magPopup])

        let animateCheck = makeCheckbox(L10n.t("Animate zoom in and zoom out:", "放大與縮小時顯示動畫："), action: #selector(animateZoomChanged(_:)), state: settings.animateZoom)
        let smoothCheck = makeCheckbox(L10n.t("Smooth zoomed image:", "平滑放大後的影像："), action: #selector(smoothImageChanged(_:)), state: settings.smoothImage)

        return makeColumn([help, hotKeyRow, magHelp, magRow, makeCheckboxColumn([animateCheck, smoothCheck])])
    }

    // MARK: - Live Zoom tab

    /// Live zoom lives on its own tab so the Zoom tab holds only static-zoom
    /// settings, matching the Windows ZoomIt options dialog.
    private func makeLiveZoomTab() -> NSView {
        let liveHelp = makeLabel(
            L10n.t("Magnifies the live screen so motion stays visible while zoomed.", "放大即時畫面，放大時動態內容仍持續更新。"),
            wraps: true
        )

        let liveHotKeyButton = NSButton(title: liveHotKeyDisplayString(), target: self, action: #selector(toggleLiveHotKeyRecording(_:)))
        liveHotKeyButton.bezelStyle = .rounded
        liveHotKeyButton.setButtonType(.momentaryPushIn)
        liveHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.liveHotKeyButton = liveHotKeyButton
        let liveHotKeyRow = makeRow([makeLabel(L10n.t("LiveZoom Toggle:", "即時放大快捷鍵：")), liveHotKeyButton])

        return makeColumn([liveHelp, liveHotKeyRow])
    }

    @objc private func zoomLevelChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard AppSettings.zoomLevels.indices.contains(index) else { return }
        settings.defaultZoomFactor = AppSettings.zoomLevels[index]
        persist()
    }

    @objc private func animateZoomChanged(_ sender: NSButton) {
        settings.animateZoom = (sender.state == .on)
        persist()
    }

    @objc private func smoothImageChanged(_ sender: NSButton) {
        settings.smoothImage = (sender.state == .on)
        persist()
    }

    // MARK: - Hotkey recorder

    @objc private func toggleZoomHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .zoom, sender: sender)
    }

    @objc private func toggleDrawHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .draw, sender: sender)
    }

    @objc private func toggleLiveHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .live, sender: sender)
    }

    @objc private func toggleBreakHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .breakTimer, sender: sender)
    }

    @objc private func toggleSnipHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .snip, sender: sender)
    }

    @objc private func toggleSnipOcrHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .snipOcr, sender: sender)
    }

    @objc private func toggleRecordHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .record, sender: sender)
    }

    #if !TEACHLENS_APP_STORE
    @objc private func toggleDemoTypeHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .demoType, sender: sender)
    }
    #endif

    @objc private func togglePanoramaHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .panorama, sender: sender)
    }

    @objc private func toggleDemoMirrorHotKeyRecording(_ sender: NSButton) {
        beginRecording(target: .demoMirror, sender: sender)
    }

    private func beginRecording(target: HotKeyTarget, sender: NSButton) {
        if recordingTarget != nil {
            // A recording is already in progress; clicking any recorder stops it.
            finishRecording()
            return
        }
        recordingTarget = target
        // Suspend the global hotkeys only while actively capturing a shortcut so
        // the pressed keys are recorded instead of triggering their action. They
        // resume as soon as recording finishes, so shortcuts like the Zoom toggle
        // keep working while the Settings dialog is merely open (issue #22).
        onSuspendHotkeys()
        sender.title = L10n.t("Type shortcut… (Esc cancels)", "請按快捷鍵…（Esc 取消）")
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.captureHotKey(event)
        }
    }

    private func captureHotKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Escape cancels recording.
            finishRecording()
            return nil
        }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !modifiers.isEmpty else {
            // A global hotkey needs at least one modifier.
            NSSound.beep()
            return nil
        }

        let newCode = Int(event.keyCode)
        let newModifiers = modifiers.rawValue

        switch recordingTarget {
        case .zoom:
            // Reject a shortcut already assigned to another TeachLens hotkey.
            if conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.hotKeyCode = newCode
            settings.hotKeyModifiers = newModifiers
        case .draw:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.drawHotKeyCode = newCode
            settings.drawHotKeyModifiers = newModifiers
        case .live:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.liveHotKeyCode = newCode
            settings.liveHotKeyModifiers = newModifiers
        case .breakTimer:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnip(code: newCode, modifiers: newModifiers) ||
                conflictsWithRecord(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithPanorama(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.breakHotKeyCode = newCode
            settings.breakHotKeyModifiers = newModifiers
        case .snip:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.snipHotKeyCode = newCode
            settings.snipHotKeyModifiers = newModifiers
        case .snipOcr:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnip(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.snipOcrHotKeyCode = newCode
            settings.snipOcrHotKeyModifiers = newModifiers
        case .record:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.recordHotKeyCode = newCode
            settings.recordHotKeyModifiers = newModifiers
        #if !TEACHLENS_APP_STORE
        case .demoType:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnip(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnipOcr(code: newCode, modifiers: newModifiers) ||
                conflictsWithRecord(code: newCode, modifiers: newModifiers) ||
                conflictsWithPanorama(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.demoTypeHotKeyCode = newCode
            settings.demoTypeHotKeyModifiers = newModifiers
        #endif
        case .panorama:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoMirror(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.panoramaHotKeyCode = newCode
            settings.panoramaHotKeyModifiers = newModifiers
        case .demoMirror:
            if conflictsWithZoom(code: newCode, modifiers: newModifiers) ||
                conflictsWithDraw(code: newCode, modifiers: newModifiers) ||
                conflictsWithLive(code: newCode, modifiers: newModifiers) ||
                conflictsWithBreak(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnip(code: newCode, modifiers: newModifiers) ||
                conflictsWithSnipOcr(code: newCode, modifiers: newModifiers) ||
                conflictsWithRecord(code: newCode, modifiers: newModifiers) ||
                conflictsWithDemoType(code: newCode, modifiers: newModifiers) ||
                conflictsWithPanorama(code: newCode, modifiers: newModifiers) {
                NSSound.beep()
                return nil
            }
            settings.demoMirrorHotKeyCode = newCode
            settings.demoMirrorHotKeyModifiers = newModifiers
        case nil:
            return nil
        }
        persist()
        finishRecording()
        onHotKeyChange()
        return nil
    }

    private func conflictsWithZoom(code: Int, modifiers: UInt) -> Bool {
        code == settings.hotKeyCode && modifiers == settings.hotKeyModifiers
    }

    private func conflictsWithDraw(code: Int, modifiers: UInt) -> Bool {
        code == settings.drawHotKeyCode && modifiers == settings.drawHotKeyModifiers
    }

    private func conflictsWithLive(code: Int, modifiers: UInt) -> Bool {
        code == settings.liveHotKeyCode && modifiers == settings.liveHotKeyModifiers
    }

    private func conflictsWithBreak(code: Int, modifiers: UInt) -> Bool {
        code == settings.breakHotKeyCode && modifiers == settings.breakHotKeyModifiers
    }

    private func conflictsWithSnip(code: Int, modifiers: UInt) -> Bool {
        code == settings.snipHotKeyCode && modifiers == settings.snipHotKeyModifiers
    }

    private func conflictsWithSnipOcr(code: Int, modifiers: UInt) -> Bool {
        settings.snipOcrHotKeyCode != 0 &&
            code == settings.snipOcrHotKeyCode && modifiers == settings.snipOcrHotKeyModifiers
    }

    private func conflictsWithRecord(code: Int, modifiers: UInt) -> Bool {
        code == settings.recordHotKeyCode && modifiers == settings.recordHotKeyModifiers
    }

    private func conflictsWithDemoType(code: Int, modifiers: UInt) -> Bool {
        #if TEACHLENS_APP_STORE
        false
        #else
        settings.demoTypeHotKeyCode != 0 &&
            code == settings.demoTypeHotKeyCode && modifiers == settings.demoTypeHotKeyModifiers
        #endif
    }

    private func conflictsWithPanorama(code: Int, modifiers: UInt) -> Bool {
        code == settings.panoramaHotKeyCode && modifiers == settings.panoramaHotKeyModifiers
    }

    private func conflictsWithDemoMirror(code: Int, modifiers: UInt) -> Bool {
        code == settings.demoMirrorHotKeyCode && modifiers == settings.demoMirrorHotKeyModifiers
    }

    private func finishRecording() {
        // Resume the global hotkeys only if a capture was actually in progress,
        // keeping the suspend/resume balanced no matter how recording ends
        // (successful capture, Esc, toggling the button, or window close).
        let wasRecording = recordingTarget != nil
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
        }
        hotKeyMonitor = nil
        recordingTarget = nil
        if wasRecording {
            onResumeHotkeys()
        }
        hotKeyButton?.title = zoomHotKeyDisplayString()
        drawHotKeyButton?.title = drawHotKeyDisplayString()
        liveHotKeyButton?.title = liveHotKeyDisplayString()
        breakHotKeyButton?.title = breakHotKeyDisplayString()
        snipHotKeyButton?.title = snipHotKeyDisplayString()
        snipOcrHotKeyButton?.title = snipOcrHotKeyDisplayString()
        recordHotKeyButton?.title = recordHotKeyDisplayString()
        #if !TEACHLENS_APP_STORE
        demoTypeHotKeyButton?.title = demoTypeHotKeyDisplayString()
        #endif
        panoramaHotKeyButton?.title = panoramaHotKeyDisplayString()
        demoMirrorHotKeyButton?.title = demoMirrorHotKeyDisplayString()
    }

    private func zoomHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.hotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.hotKeyModifiers))
    }

    private func drawHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.drawHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.drawHotKeyModifiers))
    }

    private func liveHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.liveHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.liveHotKeyModifiers))
    }

    private func breakHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.breakHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.breakHotKeyModifiers))
    }

    private func snipHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.snipHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.snipHotKeyModifiers))
    }

    private func snipOcrHotKeyDisplayString() -> String {
        guard settings.snipOcrHotKeyCode != 0 else { return L10n.t("None", "無") }
        return Self.describe(keyCode: settings.snipOcrHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.snipOcrHotKeyModifiers))
    }

    private func recordHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.recordHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.recordHotKeyModifiers))
    }

    #if !TEACHLENS_APP_STORE
    private func demoTypeHotKeyDisplayString() -> String {
        guard settings.demoTypeHotKeyCode != 0 else { return L10n.t("None", "無") }
        return Self.describe(keyCode: settings.demoTypeHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.demoTypeHotKeyModifiers))
    }
    #endif

    private func panoramaHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.panoramaHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.panoramaHotKeyModifiers))
    }

    private func demoMirrorHotKeyDisplayString() -> String {
        Self.describe(keyCode: settings.demoMirrorHotKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: settings.demoMirrorHotKeyModifiers))
    }

    // MARK: - Draw tab

    private func makeDrawTab() -> NSView {
        let help = makeLabel(
            L10n.t("Left-click to draw, right-click to stop; ⌘Z undoes, E erases all.", "左鍵開始畫，右鍵結束；⌘Z 復原，E 全部清除。"),
            wraps: true
        )

        let penSection = makeSectionLabel(L10n.t("Pen Control", "筆的控制"))
        let penHelp = makeLabel(
            L10n.t("Pen width: mouse wheel, [ and ], or Shift+↑/↓.", "筆寬：滑鼠滾輪、[ ]，或 Shift+↑／↓。"),
            wraps: true
        )

        let colorsSection = makeSectionLabel(L10n.t("Colors", "顏色"))
        let colorsHelp = makeLabel(
            L10n.t("R G B O Y P W K: red, green, blue, orange, yellow, pink, white, black.", "R G B O Y P W K：紅、綠、藍、橘、黃、粉、白、黑。"),
            wraps: true
        )

        let highlightSection = makeSectionLabel(L10n.t("Highlight", "螢光筆"))
        let highlightHelp = makeLabel(
            L10n.t("Shift + a colour key draws with a highlighter.", "Shift＋顏色鍵改為螢光筆。"),
            wraps: true
        )

        let shapesSection = makeSectionLabel(L10n.t("Shapes", "圖形"))
        let shapesHelp = makeLabel(
            L10n.t("Drag with Shift: line · Control: rectangle · Tab: ellipse · Shift+Control: arrow.", "拖曳時按 Shift：直線 · Control：矩形 · Tab：橢圓 · Shift+Control：箭頭。"),
            wraps: true
        )

        let screenSection = makeSectionLabel(L10n.t("Screen", "畫面"))
        let screenHelp = makeLabel(
            L10n.t("Ctrl+W / Ctrl+K turns the screen into a white / black board.", "Ctrl+W／Ctrl+K 切換成白板／黑板。"),
            wraps: true
        )

        let drawHotKeyButton = NSButton(title: drawHotKeyDisplayString(), target: self, action: #selector(toggleDrawHotKeyRecording(_:)))
        drawHotKeyButton.bezelStyle = .rounded
        drawHotKeyButton.setButtonType(.momentaryPushIn)
        drawHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.drawHotKeyButton = drawHotKeyButton
        let drawHotKeyRow = makeRow([makeLabel(L10n.t("Draw w/out Zoom:", "不放大直接畫：")), drawHotKeyButton])

        return makeColumn([
            help,
            penSection,
            makeIndentedColumn([penHelp]),
            colorsSection,
            makeIndentedColumn([colorsHelp]),
            highlightSection,
            makeIndentedColumn([highlightHelp]),
            shapesSection,
            makeIndentedColumn([shapesHelp]),
            screenSection,
            makeIndentedColumn([screenHelp]),
            drawHotKeyRow
        ], spacing: 6)
    }

    // MARK: - Type tab

    private func makeTypeTab() -> NSView {
        let help = makeLabel(
            L10n.t("While drawing, press T to type (Shift+T: right-aligned); ↑/↓ change the size.", "畫筆模式下按 T 打字（Shift+T 靠右）；↑／↓ 調整字級。"),
            wraps: true
        )

        let sample = makeLabel("")
        fontSampleLabel = sample
        updateFontSample()

        let fontButton = NSButton(title: L10n.t("Select Font…", "選擇字體…"), target: self, action: #selector(selectFont(_:)))
        fontButton.bezelStyle = .rounded

        let fontRow = makeRow([makeLabel(L10n.t("Typing font:", "打字字體：")), fontButton])

        return makeColumn([help, fontRow, sample])
    }

    // MARK: - Break tab

    private func makeBreakTab() -> NSView {
        let help = makeLabel(
            L10n.t("Shows a full-screen countdown; arrow keys adjust the time, Esc exits.", "顯示全螢幕倒數；方向鍵調整時間，Esc 離開。"),
            wraps: true
        )

        let hotKeyButton = NSButton(title: breakHotKeyDisplayString(), target: self, action: #selector(toggleBreakHotKeyRecording(_:)))
        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.setButtonType(.momentaryPushIn)
        hotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        breakHotKeyButton = hotKeyButton

        let durationStepper = NSStepper()
        durationStepper.minValue = 1
        durationStepper.maxValue = 99
        durationStepper.integerValue = settings.breakDurationMinutes
        durationStepper.increment = 1
        durationStepper.target = self
        durationStepper.action = #selector(breakDurationChanged(_:))
        let durationLabel = makeLabel("")
        breakDurationLabel = durationLabel
        updateBreakDurationLabel()
        let durationControls = makeRow([durationStepper, durationLabel])

        let expiredCheck = makeCheckbox(L10n.t("Show Time Elapsed After Expiration:", "時間到後顯示已超過的時間："), action: #selector(breakShowExpiredChanged(_:)), state: settings.breakShowExpiredTime)

        let textColorPopup = makeColorPopup(selected: settings.breakTextColorRGB, action: #selector(breakTextColorChanged(_:)))
        let backgroundColorPopup = makeColorPopup(selected: settings.breakBackgroundColorRGB, action: #selector(breakBackgroundColorChanged(_:)))

        let positionPopup = makeIndexedPopup(
            titles: [L10n.t("Top-left", "左上"), L10n.t("Top", "上"), L10n.t("Top-right", "右上"), L10n.t("Left", "左"), L10n.t("Center", "中央"), L10n.t("Right", "右"), L10n.t("Bottom-left", "左下"), L10n.t("Bottom", "下"), L10n.t("Bottom-right", "右下")],
            selected: settings.breakTimerPosition,
            action: #selector(breakPositionChanged(_:))
        )
        positionPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let opacityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        opacityPopup.translatesAutoresizingMaskIntoConstraints = false
        for value in stride(from: 10, through: 100, by: 10) {
            opacityPopup.addItem(withTitle: "\(value)%")
            opacityPopup.lastItem?.representedObject = value
        }
        opacityPopup.selectItem(withTitle: "\(min(max(settings.breakOpacity, 10), 100))%")
        opacityPopup.target = self
        opacityPopup.action = #selector(breakOpacityChanged(_:))

        let soundCheck = makeCheckbox(L10n.t("Play Sound on Expiration:", "時間到時播放聲音："), action: #selector(breakPlaySoundChanged(_:)), state: settings.breakPlaySound)
        let soundField = makePathField(settings.breakSoundFile)
        breakSoundFileField = soundField
        let soundBrowse = NSButton(title: L10n.t("Browse…", "瀏覽…"), target: self, action: #selector(chooseBreakSoundFile(_:)))
        soundBrowse.bezelStyle = .rounded

        let backgroundModePopup = makeIndexedPopup(
            titles: [L10n.t("No image", "無圖片"), L10n.t("Faded desktop", "淡化桌面"), L10n.t("Image file", "圖片檔")],
            selected: settings.breakBackgroundMode,
            action: #selector(breakBackgroundModeChanged(_:))
        )
        breakBackgroundModePopup = backgroundModePopup
        backgroundModePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let backgroundField = makePathField(settings.breakBackgroundFile)
        breakBackgroundFileField = backgroundField
        let backgroundBrowse = NSButton(title: L10n.t("Browse…", "瀏覽…"), target: self, action: #selector(chooseBreakBackgroundFile(_:)))
        backgroundBrowse.bezelStyle = .rounded
        breakBackgroundBrowseButton = backgroundBrowse
        let stretchCheck = makeCheckbox(L10n.t("Scale to screen:", "縮放至螢幕大小："), action: #selector(breakBackgroundStretchChanged(_:)), state: settings.breakBackgroundStretch)
        breakBackgroundStretchCheckbox = stretchCheck

        // A single grid keeps every label/control pair in aligned columns:
        // column 0 = right-aligned labels, column 1 = primary control,
        // column 2 = secondary label, column 3 = secondary control.
        let grid = makeFormGrid([
            [makeLabel(L10n.t("Start Timer:", "開始計時：")), hotKeyButton, makeLabel(L10n.t("Duration:", "時間長度：")), durationControls],
            [makeLabel(L10n.t("Timer color:", "計時器顏色：")), textColorPopup, makeLabel(L10n.t("Background:", "背景：")), backgroundColorPopup],
            [makeLabel(L10n.t("Position:", "位置：")), positionPopup, makeLabel(L10n.t("Opacity:", "不透明度：")), opacityPopup],
            [makeLabel(L10n.t("Backdrop:", "背景樣式：")), backgroundModePopup, stretchCheck],
            [makeLabel(L10n.t("Image file:", "圖片檔：")), backgroundField, backgroundBrowse],
            [makeLabel(L10n.t("Sound:", "聲音：")), soundField, soundBrowse]
        ])

        updateBreakBackgroundControlsEnabled()
        return makeColumn([
            help,
            grid,
            makeCheckboxColumn([expiredCheck, soundCheck])
        ], spacing: 12)
    }

    private func updateBreakDurationLabel() {
        breakDurationLabel?.stringValue = L10n.t("\(settings.breakDurationMinutes) minutes", "\(settings.breakDurationMinutes) 分鐘")
    }

    private func makePathField(_ path: String) -> NSTextField {
        let field = NSTextField(labelWithString: path.isEmpty ? L10n.t("No file selected", "尚未選擇檔案") : path)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingMiddle
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return field
    }

    private func makeColorPopup(selected: UInt32, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        for option in Self.breakColorOptions {
            popup.addItem(withTitle: option.name)
            popup.lastItem?.representedObject = Int(option.rgb)
        }
        let selectedIndex = Self.breakColorOptions.firstIndex { $0.rgb == selected } ?? 0
        popup.selectItem(at: selectedIndex)
        popup.target = self
        popup.action = action
        return popup
    }

    private func updateBreakBackgroundControlsEnabled() {
        let usesImageFile = settings.breakBackgroundMode == 2
        breakBackgroundFileField?.isEnabled = usesImageFile
        breakBackgroundBrowseButton?.isEnabled = usesImageFile
        breakBackgroundStretchCheckbox?.isEnabled = usesImageFile
    }

    @objc private func breakDurationChanged(_ sender: NSStepper) {
        settings.breakDurationMinutes = min(max(sender.integerValue, 1), 99)
        updateBreakDurationLabel()
        persist()
    }

    @objc private func breakShowExpiredChanged(_ sender: NSButton) {
        settings.breakShowExpiredTime = sender.state == .on
        persist()
    }

    @objc private func breakTextColorChanged(_ sender: NSPopUpButton) {
        settings.breakTextColorRGB = UInt32((sender.selectedItem?.representedObject as? Int) ?? Int(settings.breakTextColorRGB))
        persist()
    }

    @objc private func breakBackgroundColorChanged(_ sender: NSPopUpButton) {
        settings.breakBackgroundColorRGB = UInt32((sender.selectedItem?.representedObject as? Int) ?? Int(settings.breakBackgroundColorRGB))
        persist()
    }

    @objc private func breakPositionChanged(_ sender: NSPopUpButton) {
        settings.breakTimerPosition = sender.indexOfSelectedItem
        persist()
    }

    @objc private func breakOpacityChanged(_ sender: NSPopUpButton) {
        settings.breakOpacity = (sender.selectedItem?.representedObject as? Int) ?? settings.breakOpacity
        persist()
    }

    @objc private func breakPlaySoundChanged(_ sender: NSButton) {
        settings.breakPlaySound = sender.state == .on
        persist()
    }

    @objc private func chooseBreakSoundFile(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.title = L10n.t("TeachLens: Specify Sound File", "TeachLens：選擇聲音檔")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard saveSelection(url, for: .breakSound) else { return }
        settings.breakSoundFile = url.path
        breakSoundFileField?.stringValue = url.path
        persist()
    }

    @objc private func breakBackgroundModeChanged(_ sender: NSPopUpButton) {
        settings.breakBackgroundMode = sender.indexOfSelectedItem
        updateBreakBackgroundControlsEnabled()
        persist()
    }

    @objc private func chooseBreakBackgroundFile(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.title = L10n.t("TeachLens: Specify Background File", "TeachLens：選擇背景圖片")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard saveSelection(url, for: .breakBackground) else { return }
        settings.breakBackgroundFile = url.path
        breakBackgroundFileField?.stringValue = url.path
        persist()
    }

    @objc private func breakBackgroundStretchChanged(_ sender: NSButton) {
        settings.breakBackgroundStretch = sender.state == .on
        persist()
    }

    private static let breakColorOptions: [(name: String, rgb: UInt32)] = [
        (L10n.t("Red", "紅"), 0xFF0000),
        (L10n.t("Green", "綠"), 0x00FF00),
        (L10n.t("Blue", "藍"), 0x0000FF),
        (L10n.t("Orange", "橘"), 0xFFA500),
        (L10n.t("Yellow", "黃"), 0xFFFF00),
        (L10n.t("Pink", "粉紅"), 0xFF69B4),
        (L10n.t("White", "白"), 0xFFFFFF),
        (L10n.t("Black", "黑"), 0x000000)
    ]

    // MARK: - Snip tab

    private func makeSnipTab() -> NSView {
        let help = makeLabel(
            L10n.t("Drag a region to copy it; hold Shift to save a PNG. The OCR shortcut copies the text instead.", "拖曳範圍即複製；加 Shift 存成 PNG。文字辨識快捷鍵會改為複製文字。"),
            wraps: true
        )

        let snipHotKeyButton = NSButton(title: snipHotKeyDisplayString(), target: self, action: #selector(toggleSnipHotKeyRecording(_:)))
        snipHotKeyButton.bezelStyle = .rounded
        snipHotKeyButton.setButtonType(.momentaryPushIn)
        snipHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.snipHotKeyButton = snipHotKeyButton
        let snipHotKeyRow = makeRow([makeLabel(L10n.t("Snip Toggle:", "截圖快捷鍵：")), snipHotKeyButton])

        let snipOcrHotKeyButton = NSButton(title: snipOcrHotKeyDisplayString(), target: self, action: #selector(toggleSnipOcrHotKeyRecording(_:)))
        snipOcrHotKeyButton.bezelStyle = .rounded
        snipOcrHotKeyButton.setButtonType(.momentaryPushIn)
        snipOcrHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.snipOcrHotKeyButton = snipOcrHotKeyButton
        let snipOcrHotKeyRow = makeRow([makeLabel(L10n.t("Text Toggle:", "文字辨識快捷鍵：")), snipOcrHotKeyButton])

        let dictationCheck = makeCheckbox(
            L10n.t("Enable dictation during clipboard snips:", "截圖到剪貼簿時可以口述："),
            action: #selector(snipDictationChanged(_:)),
            state: settings.snipDictationEnabled
        )
        let dictationMicrophonePopup = makeMicrophonePopup(enabled: settings.snipDictationEnabled)
        snipMicrophonePopup = dictationMicrophonePopup
        let dictationMicrophoneRow = makeIndentedColumn([
            makeRow([makeLabel(L10n.t("Dictation microphone:", "口述用麥克風：")), dictationMicrophonePopup])
        ])

        let copyOnSaveCheck = makeCheckbox(
            L10n.t("Also copy to clipboard when saving to a file:", "存檔時也複製到剪貼簿："),
            action: #selector(copySnipToClipboardOnSaveChanged(_:)),
            state: settings.copySnipToClipboardOnSave
        )

        let saveToDirectoryCheck = makeCheckbox(
            L10n.t("Save to a folder instead of asking each time:", "直接存到資料夾，不每次詢問："),
            action: #selector(saveSnipToDirectoryChanged(_:)),
            state: settings.saveSnipToDirectory
        )

        let directoryField = NSTextField(labelWithString: snipSaveDirectoryDisplayPath())
        directoryField.translatesAutoresizingMaskIntoConstraints = false
        directoryField.lineBreakMode = .byTruncatingMiddle
        directoryField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        snipSaveDirectoryField = directoryField
        let directoryBrowse = NSButton(title: L10n.t("Browse…", "瀏覽…"), target: self, action: #selector(chooseSnipSaveDirectory(_:)))
        directoryBrowse.bezelStyle = .rounded
        snipSaveDirectoryBrowseButton = directoryBrowse
        let directoryRow = makeIndentedColumn([makeRow([makeLabel(L10n.t("Folder:", "資料夾：")), directoryField, directoryBrowse])])

        updateSnipSaveDirectoryControlsEnabled()

        return makeColumn([
            help,
            snipHotKeyRow,
            snipOcrHotKeyRow,
            makeCheckboxColumn([dictationCheck]),
            dictationMicrophoneRow,
            makeCheckboxColumn([copyOnSaveCheck, saveToDirectoryCheck]),
            directoryRow
        ])
    }

    private func snipSaveDirectoryDisplayPath() -> String {
        if settings.snipSaveDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
            return ImageExporter.defaultSaveDirectory().path
        }
        return settings.snipSaveDirectory
    }

    private func updateSnipSaveDirectoryControlsEnabled() {
        snipSaveDirectoryField?.isEnabled = settings.saveSnipToDirectory
        snipSaveDirectoryBrowseButton?.isEnabled = settings.saveSnipToDirectory
    }

    @objc private func copySnipToClipboardOnSaveChanged(_ sender: NSButton) {
        settings.copySnipToClipboardOnSave = (sender.state == .on)
        persist()
    }

    @objc private func snipDictationChanged(_ sender: NSButton) {
        settings.snipDictationEnabled = (sender.state == .on)
        updateMicrophoneOptionControls()
        persist()
        if settings.snipDictationEnabled {
            onRequestSpeechRecognition()
        }
    }

    @objc private func saveSnipToDirectoryChanged(_ sender: NSButton) {
        settings.saveSnipToDirectory = (sender.state == .on)
        updateSnipSaveDirectoryControlsEnabled()
        persist()
    }

    @objc private func chooseSnipSaveDirectory(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.t("Choose", "選擇")
        panel.title = L10n.t("TeachLens: Choose Snip Folder", "TeachLens：選擇截圖資料夾")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard saveSelection(url, for: .snipDirectory) else { return }
        settings.snipSaveDirectory = url.path
        snipSaveDirectoryField?.stringValue = url.path
        persist()
    }

    // MARK: - Record tab

    private func makeRecordTab() -> NSView {
        let help = makeLabel(
            L10n.t("Records the screen to MP4; hold Shift to record a region. Press again to stop.", "錄製全螢幕為 MP4；加 Shift 錄製區域。再按一次停止。"),
            wraps: true
        )

        let recordHotKeyButton = NSButton(title: recordHotKeyDisplayString(), target: self, action: #selector(toggleRecordHotKeyRecording(_:)))
        recordHotKeyButton.bezelStyle = .rounded
        recordHotKeyButton.setButtonType(.momentaryPushIn)
        recordHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.recordHotKeyButton = recordHotKeyButton
        let recordHotKeyRow = makeRow([makeLabel(L10n.t("Record Toggle:", "錄影快捷鍵：")), recordHotKeyButton])

        let systemAudioCheck = makeCheckbox(L10n.t("Capture system audio:", "錄製系統聲音："), action: #selector(recordSystemAudioChanged(_:)), state: settings.recordSystemAudio)

        let micCheck = makeCheckbox(L10n.t("Capture audio input:", "錄製麥克風："), action: #selector(recordMicrophoneChanged(_:)), state: settings.recordMicrophone)

        let windNoiseCheck = makeCheckbox(L10n.t("Noise cancellation:", "降噪："), action: #selector(recordNoiseCancellationChanged(_:)), state: settings.recordNoiseCancellation)
        noiseCancellationCheckbox = windNoiseCheck

        let micPopup = makeMicrophonePopup(enabled: settings.recordMicrophone)
        recordMicrophonePopup = micPopup
        let micDeviceRow = makeRow([makeLabel(L10n.t("Microphone:", "麥克風：")), micPopup])
        let micOptions = makeIndentedColumn([windNoiseCheck, micDeviceRow])
        updateMicrophoneOptionControls()

        let trimButton = NSButton(title: L10n.t("Trim…", "剪輯…"), target: self, action: #selector(openTrimEditor(_:)))
        trimButton.bezelStyle = .rounded
        let trimRow = makeRow([makeLabel(L10n.t("Edit existing video:", "剪輯現有影片：")), trimButton])

        return makeColumn([help, recordHotKeyRow, makeCheckboxColumn([systemAudioCheck, micCheck]), micOptions] + makeWebcamRows() + [trimRow], spacing: 10)
    }

    // MARK: - Panorama tab

    private func makePanoramaTab() -> NSView {
        let help = makeLabel(
            L10n.t("Drag over scrollable content, scroll, then press again to stitch one long image.", "框選可捲動的內容並捲動，再按一次即拼接成長圖。"),
            wraps: true
        )

        let panoramaHotKeyButton = NSButton(title: panoramaHotKeyDisplayString(), target: self, action: #selector(togglePanoramaHotKeyRecording(_:)))
        panoramaHotKeyButton.bezelStyle = .rounded
        panoramaHotKeyButton.setButtonType(.momentaryPushIn)
        panoramaHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.panoramaHotKeyButton = panoramaHotKeyButton
        let panoramaHotKeyRow = makeRow([makeLabel(L10n.t("Panorama Toggle:", "長截圖快捷鍵：")), panoramaHotKeyButton])

        return makeColumn([help, panoramaHotKeyRow])
    }

    // MARK: - DemoMirror tab

    private func makeDemoMirrorTab() -> NSView {
        let help = makeLabel(
            L10n.t("Mirrors the screen, a region or a window onto a second display.", "把螢幕、區域或視窗鏡像到第二台顯示器。"),
            wraps: true
        )

        let shortcutHelp = makeLabel(
            L10n.t("Shortcut: whole screen · with Shift: region · with Option: window under the pointer.", "快捷鍵：整個螢幕 · 加 Shift：區域 · 加 Option：游標下的視窗。"),
            wraps: true
        )

        let demoMirrorHotKeyButton = NSButton(title: demoMirrorHotKeyDisplayString(), target: self, action: #selector(toggleDemoMirrorHotKeyRecording(_:)))
        demoMirrorHotKeyButton.bezelStyle = .rounded
        demoMirrorHotKeyButton.setButtonType(.momentaryPushIn)
        demoMirrorHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.demoMirrorHotKeyButton = demoMirrorHotKeyButton
        let demoMirrorHotKeyRow = makeRow([makeLabel(L10n.t("Mirror Toggle:", "鏡像快捷鍵：")), demoMirrorHotKeyButton])

        let trackWindowHelp = makeLabel(
            L10n.t("Track the window region so zoom and drawing appear in place.", "追蹤視窗區域，讓放大與畫筆顯示在原位置。"),
            wraps: true
        )
        let trackWindowCheck = makeCheckbox(L10n.t("Track window region:", "追蹤視窗區域："), action: #selector(demoMirrorTrackWindowChanged(_:)), state: settings.demoMirrorTrackWindowRegion)
        demoMirrorTrackWindowCheckbox = trackWindowCheck

        return makeColumn([help, shortcutHelp, demoMirrorHotKeyRow, trackWindowHelp, trackWindowCheck])
    }

    @objc private func demoMirrorTrackWindowChanged(_ sender: NSButton) {
        settings.demoMirrorTrackWindowRegion = (sender.state == .on)
        persist()
    }

    @objc private func recordSystemAudioChanged(_ sender: NSButton) {
        settings.recordSystemAudio = (sender.state == .on)
        persist()
    }

    @objc private func recordMicrophoneChanged(_ sender: NSButton) {
        settings.recordMicrophone = (sender.state == .on)
        updateMicrophoneOptionControls()
        persist()
        // Trigger the microphone permission prompt the first time it's enabled.
        if settings.recordMicrophone {
            onRequestMicrophone()
        }
    }

    @objc private func microphoneChanged(_ sender: NSPopUpButton) {
        settings.microphoneDeviceID = (sender.selectedItem?.representedObject as? String) ?? ""
        synchronizeMicrophonePopups()
        updateMicrophoneOptionControls()
        persist()
    }

    @objc private func recordNoiseCancellationChanged(_ sender: NSButton) {
        settings.recordNoiseCancellation = (sender.state == .on)
        persist()
    }

    private func updateMicrophoneOptionControls() {
        recordMicrophonePopup?.isEnabled = settings.recordMicrophone
        snipMicrophonePopup?.isEnabled = settings.snipDictationEnabled
        let supported = settings.recordMicrophone && AudioDevices.supportsWindNoiseRemoval(deviceID: settings.microphoneDeviceID)
        noiseCancellationCheckbox?.title = supported ? L10n.t("Noise cancellation:", "降噪：") : L10n.t("Noise cancellation (not supported by selected microphone):", "降噪（所選麥克風不支援）：")
        noiseCancellationCheckbox?.isEnabled = supported
        noiseCancellationCheckbox?.state = (settings.recordNoiseCancellation && supported) ? .on : .off
        noiseCancellationCheckbox?.toolTip = supported
            ? L10n.t("Uses AVFoundation wind noise removal for the selected microphone.", "對所選麥克風使用系統的風噪消除。")
            : L10n.t("Wind noise removal requires macOS 15 and a microphone that supports it.", "風噪消除需要 macOS 15 以上與支援的麥克風。")
    }

    private func makeMicrophonePopup(enabled: Bool) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        let microphones = AudioDevices.availableMicrophones()
        var selectedIndex = 0
        for (index, device) in microphones.enumerated() {
            popup.addItem(withTitle: device.name)
            popup.lastItem?.representedObject = device.id
            if device.id == settings.microphoneDeviceID {
                selectedIndex = index
            }
        }
        popup.selectItem(at: selectedIndex)
        popup.target = self
        popup.action = #selector(microphoneChanged(_:))
        popup.isEnabled = enabled
        popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return popup
    }

    private func synchronizeMicrophonePopups() {
        for popup in [recordMicrophonePopup, snipMicrophonePopup].compactMap({ $0 }) {
            if let item = popup.itemArray.first(where: {
                ($0.representedObject as? String) == settings.microphoneDeviceID
            }) {
                popup.select(item)
            } else {
                popup.selectItem(at: 0)
            }
        }
    }

    @objc private func openTrimEditor(_ sender: NSButton) {
        onOpenTrimEditor()
    }

    // MARK: - Webcam controls

    private func makeWebcamRows() -> [NSView] {
        let heading = makeLabel(L10n.t("Webcam overlay:", "相機子母畫面："))
        heading.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let enableCheck = makeCheckbox("", action: #selector(webcamEnabledChanged(_:)), state: settings.webcamEnabled)

        let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePopup.translatesAutoresizingMaskIntoConstraints = false
        var selectedDevice = 0
        for (index, camera) in VideoDevices.availableCameras().enumerated() {
            devicePopup.addItem(withTitle: camera.name)
            devicePopup.lastItem?.representedObject = camera.id
            if camera.id == settings.webcamDeviceID { selectedDevice = index }
        }
        devicePopup.selectItem(at: selectedDevice)
        devicePopup.target = self
        devicePopup.action = #selector(webcamDeviceChanged(_:))
        webcamDevicePopup = devicePopup

        let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        positionPopup.translatesAutoresizingMaskIntoConstraints = false
        for item in [
            (L10n.t("Top-left", "左上"), 0),
            (L10n.t("Top-right", "右上"), 1),
            (L10n.t("Center", "中央"), 4),
            (L10n.t("Bottom-left", "左下"), 2),
            (L10n.t("Bottom-right", "右下"), 3)
        ] {
            positionPopup.addItem(withTitle: item.0)
            positionPopup.lastItem?.representedObject = item.1
            if item.1 == settings.webcamPosition {
                positionPopup.select(positionPopup.lastItem)
            }
        }
        positionPopup.target = self
        positionPopup.action = #selector(webcamPositionChanged(_:))
        webcamPositionPopup = positionPopup

        let sizePopup = makeIndexedPopup(
            titles: [L10n.t("Small", "小"), L10n.t("Medium", "中"), L10n.t("Large", "大"), L10n.t("X-Large", "特大"), L10n.t("Full screen", "全螢幕")],
            selected: settings.webcamSize,
            action: #selector(webcamSizeChanged(_:))
        )
        webcamSizePopup = sizePopup

        let shapePopup = makeIndexedPopup(
            titles: [L10n.t("Rectangle", "矩形"), L10n.t("Rounded rectangle", "圓角矩形"), L10n.t("Rounded square", "圓角正方形"), L10n.t("Circle", "圓形")],
            selected: settings.webcamShape,
            action: #selector(webcamShapeChanged(_:))
        )
        webcamShapePopup = shapePopup

        devicePopup.widthAnchor.constraint(equalToConstant: 185).isActive = true
        positionPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        sizePopup.widthAnchor.constraint(equalToConstant: 115).isActive = true
        shapePopup.widthAnchor.constraint(equalToConstant: 165).isActive = true

        let webcamEnableRow = makeRow([heading, enableCheck])
        // A grid keeps the two placement/appearance columns aligned so the
        // Position and Shape labels (and their popups) line up vertically.
        let webcamGrid = makeFormGrid([
            [makeLabel(L10n.t("Camera:", "相機：")), devicePopup, makeLabel(L10n.t("Position:", "位置：")), positionPopup],
            [makeLabel(L10n.t("Size:", "大小：")), sizePopup, makeLabel(L10n.t("Shape:", "形狀：")), shapePopup]
        ])

        updateWebcamControlsEnabled()
        return [webcamEnableRow, webcamGrid]
    }

    /// Builds a popup whose item indices map directly to a settings integer.
    private func makeIndexedPopup(titles: [String], selected: Int, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        for title in titles {
            popup.addItem(withTitle: title)
        }
        popup.selectItem(at: min(max(selected, 0), titles.count - 1))
        popup.target = self
        popup.action = action
        return popup
    }

    private func updateWebcamControlsEnabled() {
        let enabled = settings.webcamEnabled
        webcamDevicePopup?.isEnabled = enabled
        webcamPositionPopup?.isEnabled = enabled
        webcamSizePopup?.isEnabled = enabled
        // Shape doesn't apply to full screen.
        webcamShapePopup?.isEnabled = enabled && settings.webcamSize != 4
    }

    @objc private func webcamEnabledChanged(_ sender: NSButton) {
        settings.webcamEnabled = (sender.state == .on)
        updateWebcamControlsEnabled()
        persist()
        if settings.webcamEnabled {
            onRequestCamera()
        }
    }

    @objc private func webcamDeviceChanged(_ sender: NSPopUpButton) {
        settings.webcamDeviceID = (sender.selectedItem?.representedObject as? String) ?? ""
        persist()
    }

    @objc private func webcamPositionChanged(_ sender: NSPopUpButton) {
        settings.webcamPosition = (sender.selectedItem?.representedObject as? Int) ?? 3
        persist()
    }

    @objc private func webcamSizeChanged(_ sender: NSPopUpButton) {
        settings.webcamSize = sender.indexOfSelectedItem
        updateWebcamControlsEnabled()
        persist()
    }

    @objc private func webcamShapeChanged(_ sender: NSPopUpButton) {
        settings.webcamShape = sender.indexOfSelectedItem
        persist()
    }

    private func currentTypingFont() -> NSFont {
        AnnotationController.typingFont(named: settings.typingFontName, size: settings.typingFontSize)
    }

    private func updateFontSample() {
        let font = Self.fontSamplePreviewFont(name: settings.typingFontName, size: settings.typingFontSize)
        // Render the sample in the actually-selected font so choosing a new font
        // is reflected immediately (it previously always used the system font).
        fontSampleLabel?.font = font
        fontSampleLabel?.stringValue = L10n.t("Sample — \(font.displayName ?? font.fontName) \(Int(settings.typingFontSize))pt", "範例 — \(font.displayName ?? font.fontName) \(Int(settings.typingFontSize))pt")
    }

    /// Font used for the Type tab's live "Sample" preview. Uses the selected
    /// typing font, clamped to a legible on-screen preview size.
    static func fontSamplePreviewFont(name: String, size: CGFloat) -> NSFont {
        let previewSize = min(max(size, 12), 36)
        return AnnotationController.typingFont(named: name, size: previewSize)
    }

    @objc private func selectFont(_ sender: NSButton) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(currentTypingFont(), isMultiple: false)
        guard let window else { return }
        window.makeFirstResponder(window)
        manager.orderFrontFontPanel(sender)
    }

    @objc func changeFont(_ sender: Any?) {
        let manager = sender as? NSFontManager ?? NSFontManager.shared
        let newFont = manager.convert(currentTypingFont())
        settings.typingFontName = newFont.fontName
        settings.typingFontSize = newFont.pointSize
        updateFontSample()
        persist()
    }

    #if !TEACHLENS_APP_STORE
    // MARK: - DemoType tab

    private func makeDemoTypeTab() -> NSView {
        let help = makeLabel(
            L10n.t("Types the snippets from a text file; separate snippets with [end].", "依序輸入文字檔中的片段；片段之間用 [end] 分隔。"),
            wraps: true
        )

        let controlsHelp = makeLabel(
            L10n.t("Keywords: [pause:n] · [paste]…[/paste] · [enter] [up] [down] [left] [right]. Esc stops.", "關鍵字：[pause:n] · [paste]…[/paste] · [enter] [up] [down] [left] [right]。Esc 停止。"),
            wraps: true
        )

        let demoTypeHotKeyButton = NSButton(title: demoTypeHotKeyDisplayString(), target: self, action: #selector(toggleDemoTypeHotKeyRecording(_:)))
        demoTypeHotKeyButton.bezelStyle = .rounded
        demoTypeHotKeyButton.setButtonType(.momentaryPushIn)
        demoTypeHotKeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.demoTypeHotKeyButton = demoTypeHotKeyButton
        let hotKeyRow = makeRow([makeLabel(L10n.t("DemoType toggle:", "DemoType 快捷鍵：")), demoTypeHotKeyButton])

        let fileField = makePathField(settings.demoTypeFile)
        demoTypeFileField = fileField
        let browseButton = NSButton(title: "...", target: self, action: #selector(chooseDemoTypeFile(_:)))
        browseButton.bezelStyle = .rounded
        let fileRow = makeRow([makeLabel(L10n.t("Input file:", "輸入檔案：")), fileField, browseButton])

        let speedSlider = NSSlider(value: Double(min(max(settings.demoTypeSpeed, 10), 100)), minValue: 10, maxValue: 100, target: self, action: #selector(demoTypeSpeedChanged(_:)))
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let speedRow = makeRow([makeLabel(L10n.t("DemoType typing speed:", "DemoType 打字速度：")), makeLabel(L10n.t("Slow", "慢")), speedSlider, makeLabel(L10n.t("Fast", "快"))])

        let userDrivenCheck = makeCheckbox(L10n.t("Drive input with typing:", "由我打字推進："), action: #selector(demoTypeUserDrivenChanged(_:)), state: settings.demoTypeUserDriven)

        return makeColumn([help, controlsHelp, hotKeyRow, fileRow, speedRow, userDrivenCheck], spacing: 8)
    }

    @objc private func chooseDemoTypeFile(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = L10n.t("TeachLens: Specify DemoType File", "TeachLens：選擇 DemoType 檔案")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.demoTypeFile = url.path
        demoTypeFileField?.stringValue = url.path
        persist()
    }

    @objc private func demoTypeSpeedChanged(_ sender: NSSlider) {
        settings.demoTypeSpeed = min(max(sender.integerValue, 10), 100)
        persist()
    }

    @objc private func demoTypeUserDrivenChanged(_ sender: NSButton) {
        settings.demoTypeUserDriven = sender.state == .on
        persist()
    }
    #endif

    // MARK: - Persistence

    private func persist() {
        settingsStore.save(settings)
    }

    private func saveSelection(_ url: URL, for resource: UserSelectedResource) -> Bool {
        do {
            try userSelectedResourceAccess.saveSelection(url, for: resource)
            return true
        } catch {
            if DistributionChannel.isAppStore {
                NSAlert(error: error).runModal()
                return false
            }
            return true
        }
    }

    // MARK: - Key formatting

    static func describe(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyName(forKeyCode: keyCode)
        return result
    }

    private static func keyName(forKeyCode code: Int) -> String {
        keyNames[code] ?? "Key \(code)"
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
