import AppKit

/// After a file is written, says where it went and offers to show it.
@MainActor
enum ExportFeedback {
    static func saved(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.t("Saved", "已儲存")
        alert.informativeText = url.path
        alert.addButton(withTitle: L10n.t("Show in Finder", "在 Finder 中顯示"))
        alert.addButton(withTitle: L10n.t("Done", "完成"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func failed(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.t("Couldn’t save the file", "無法儲存檔案")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
