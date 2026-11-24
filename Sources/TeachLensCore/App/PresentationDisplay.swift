import AppKit

/// "分享中的螢幕": which display students see. Keystrokes and captions stay on
/// that display instead of following the pointer to the teacher's other
/// screen. Zero (the default) follows the pointer.
enum PresentationDisplay {
    static let key = "presentationDisplayID"
    static let didChange = Notification.Name("TeachLensPresentationDisplayDidChange")

    static var selectedID: CGDirectDisplayID {
        get { CGDirectDisplayID(UserDefaults.standard.integer(forKey: key)) }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The chosen display when it is connected, otherwise nil.
    @MainActor static var fixedScreen: NSScreen? {
        let id = selectedID
        guard id != 0 else { return nil }
        return NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// Where overlays belong right now: the chosen display, else the screen
    /// under the pointer.
    @MainActor static func screen() -> NSScreen? {
        if let fixed = fixedScreen { return fixed }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }
}
