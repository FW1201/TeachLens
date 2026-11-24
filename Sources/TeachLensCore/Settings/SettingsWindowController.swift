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
    private let keystrokeController: KeystrokeController?
    private let spotlightController: SpotlightController?
    private let teaching: TeachingControllers?

    private static let contentWidth: CGFloat = 540
    private static let panelHorizontalInset: CGFloat = 28
    private static let wrappedLabelWidth: CGFloat = contentWidth - panelHorizontalInset * 2

    private var window: NSWindow?
    /// Settings for the tool panes (General, Zoom, Draw, … DemoMirror).
    private lazy var toolModel = ToolSettingsModel(
        store: settingsStore,
        access: userSelectedResourceAccess,
        onHotKeyChange: onHotKeyChange,
        onSuspendHotkeys: onSuspendHotkeys,
        onResumeHotkeys: onResumeHotkeys,
        requestMicrophone: onRequestMicrophone,
        requestSpeechRecognition: onRequestSpeechRecognition,
        requestCamera: onRequestCamera,
        openTrimEditor: onOpenTrimEditor
    )
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
        super.init()
    }

    /// Builds the window without showing it. Building and measuring every pane
    /// takes a noticeable moment, so the app does it while idle after launch
    /// and the first "Settings…" opens instantly.
    func prepareWindow() {
        guard window == nil else { return }
        window = makeWindow()
        toolModel.window = window
    }

    func show() {

        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }
        toolModel.reload()
        toolModel.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Selects a pane by id: its group in the sidebar, then the pane within.
    func select(pane id: String) {
        let groupID = Self.group(containing: id) ?? id
        guard let row = Self.sidebarRows.firstIndex(where: {
            if case .pane(let paneID) = $0 { return paneID == groupID }
            return false
        }) else { return }
        sidebarTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        settingsTabView?.selectTabViewItem(withIdentifier: groupID)
        if let switcher = groupSwitchers[groupID], let index = switcher.members.firstIndex(of: id) {
            switcher.control.selectedSegment = index
            switcher.tabs.selectTabViewItem(withIdentifier: id)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Cancel any in-progress recording (which resumes the global hotkeys if
        // they were suspended for capture).
        toolModel.finishRecording()
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

    /// The sidebar shows eight groups instead of seventeen panes; a group with
    /// several panes switches between them with a segmented control on top.
    static var paneGroups: [(id: String, members: [String])] {
        var advanced = ["General"]
        #if !TEACHLENS_APP_STORE
        advanced.append("DemoType")
        #endif
        advanced.append("DemoMirror")
        return [
            ("Check", ["Check"]),
            ("Modes", ["Modes"]),
            ("KeysCursor", ["Keystrokes", "Spotlight"]),
            ("Captions", ["Captions"]),
            ("BoardTimer", ["Whiteboard", "Break"]),
            ("ZoomDraw", ["Zoom", "Live Zoom", "Draw", "Type"]),
            ("Capture", ["Snip", "Record", "Panorama"]),
            ("Advanced", advanced),
        ]
    }

    static let teachingGroupIDs: Set<String> = ["Check", "Modes", "KeysCursor", "Captions", "BoardTimer"]

    static func group(containing pane: String) -> String? {
        paneGroups.first { $0.members.contains(pane) }?.id
    }

    /// Segmented switchers of multi-pane groups, by group id.
    private var groupSwitchers: [String: (control: NSSegmentedControl, tabs: NSTabView, members: [String])] = [:]

    /// The localized name shown for a pane ID.
    static func displayTitle(for id: String) -> String {
        switch id {
        case "Check": return L10n.t("Check & Test", "總覽與測試")
        case "KeysCursor": return L10n.t("Keystrokes & Pointer", "按鍵與游標")
        case "BoardTimer": return L10n.t("Whiteboard & Timer", "白板與計時")
        case "ZoomDraw": return L10n.t("Zoom & Annotate", "放大與標註")
        case "Capture": return L10n.t("Capture", "擷取")
        case "Advanced": return L10n.t("Advanced", "進階")
        case "DemoType": return L10n.t("Auto Typing", "自動打字")
        case "DemoMirror": return L10n.t("Mirror Window", "鏡像視窗")
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
        let groups = paneGroups.map(\.id)
        let teaching: [SidebarRow] = groups.filter { teachingGroupIDs.contains($0) }.map { .pane($0) }
        let tools: [SidebarRow] = groups.filter { !teachingGroupIDs.contains($0) }.map { .pane($0) }
        return [.header(L10n.t("Teaching", "教學"))] + teaching + [.header(L10n.t("Tools", "工具"))] + tools
    }

    /// One sidebar entry's content: the pane itself, or a segmented switcher
    /// over the group's panes sized to the tallest of them.
    private func makeGroupView(id: String, members: [String]) -> NSView {
        let views = members.map { viewForTab($0) }
        if views.count == 1 { return views[0] }
        var tallest: CGFloat = 0
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            let width = view.widthAnchor.constraint(equalToConstant: Self.contentWidth)
            width.isActive = true
            view.layoutSubtreeIfNeeded()
            tallest = max(tallest, view.fittingSize.height)
            width.isActive = false
        }
        let tabs = NSTabView()
        tabs.tabViewType = .noTabsNoBorder
        tabs.translatesAutoresizingMaskIntoConstraints = false
        for (member, view) in zip(members, views) {
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = true
            holder.autoresizingMask = [.width, .height]
            holder.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: tallest)
            holder.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: holder.topAnchor),
                view.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
            ])
            tabs.addTabViewItem(makeTabItem(label: member, view: holder))
        }
        NSLayoutConstraint.activate([
            tabs.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            tabs.heightAnchor.constraint(equalToConstant: tallest + 4)
        ])

        let control = NSSegmentedControl(labels: members.map { Self.displayTitle(for: $0) },
                                         trackingMode: .selectOne, target: self,
                                         action: #selector(subPaneChanged(_:)))
        for (index, member) in members.enumerated() {
            control.setImage(NSImage(systemSymbolName: Self.paneSymbolName(for: member), accessibilityDescription: nil),
                             forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        control.selectedSegment = 0
        control.identifier = NSUserInterfaceItemIdentifier(id)
        groupSwitchers[id] = (control, tabs, members)

        let stack = NSStackView(views: [control, tabs])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        return stack
    }

    @objc private func subPaneChanged(_ sender: NSSegmentedControl) {
        guard let id = sender.identifier?.rawValue, let switcher = groupSwitchers[id],
              switcher.members.indices.contains(sender.selectedSegment) else { return }
        switcher.tabs.selectTabViewItem(withIdentifier: switcher.members[sender.selectedSegment])
    }

    private func viewForTab(_ title: String) -> NSView {
        switch title {
        case "General": return hostToolPane(GeneralToolPane(model: toolModel))
        case "Keystrokes": return makeKeystrokesTab()
        case "Spotlight": return makeSpotlightTab()
        case "Check": return hostTeachingPane { CheckAndTestPane(controllers: $0) }
        case "Captions": return hostTeachingPane { CaptionSettingsPane(controller: $0.captions) }
        case "Modes": return hostTeachingPane { CourseModeSettingsPane(controller: $0.courseModes) }
        case "Whiteboard": return hostTeachingPane { WhiteboardSettingsPane(controller: $0.whiteboard) }
        case "Zoom": return hostToolPane(ZoomToolPane(model: toolModel))
        case "Live Zoom": return hostToolPane(LiveZoomToolPane(model: toolModel))
        case "Draw": return hostToolPane(DrawToolPane(model: toolModel))
        case "Type": return hostToolPane(TypeToolPane(model: toolModel))
        #if !TEACHLENS_APP_STORE
        case "DemoType": return hostToolPane(DemoTypeToolPane(model: toolModel))
        #endif
        case "Break": return hostToolPane(BreakToolPane(model: toolModel))
        case "Snip": return hostToolPane(SnipToolPane(model: toolModel))
        case "Record": return hostToolPane(RecordToolPane(model: toolModel))
        case "Panorama": return hostToolPane(PanoramaToolPane(model: toolModel))
        case "DemoMirror": return hostToolPane(DemoMirrorToolPane(model: toolModel))
        default: return NSView()
        }
    }

    private func hostToolPane<V: View>(_ pane: V) -> NSView {
        NSHostingView(rootView: pane)
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
        groupSwitchers = [:]
        let tabs: [(String, NSView)] = Self.paneGroups.map { group in
            (group.id, makeGroupView(id: group.id, members: group.members))
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
        case "KeysCursor": return "command"
        case "BoardTimer": return "scribble"
        case "ZoomDraw": return "plus.magnifyingglass"
        case "Capture": return "camera.viewfinder"
        case "Advanced": return "gearshape.2"
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

    @objc private func openForkPage(_ sender: Any?) {
        guard let url = URL(string: AppInfo.forkURL) else { return }
        NSWorkspace.shared.open(url)
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

    /// Font used for the Type pane's live "Sample" preview. Uses the selected
    /// typing font, clamped to a legible on-screen preview size.
    static func fontSamplePreviewFont(name: String, size: CGFloat) -> NSFont {
        let previewSize = min(max(size, 12), 36)
        return AnnotationController.typingFont(named: name, size: previewSize)
    }
}
