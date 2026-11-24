import AppKit
import CoreGraphics

/// A keyboard or mouse event reduced to plain values, so it can leave the
/// event-tap callback without carrying the CGEvent.
struct KeystrokeInput: Sendable {
    enum Kind: Sendable {
        case keyDown(name: String)
        case keyUp(name: String)
        case mouseDown(button: String)
        case mouseUp(button: String)
        case mouseDragged
        case scroll(deltaY: Double)
    }

    var kind: Kind
    /// Pointer position in global CoreGraphics coordinates (top-left origin of
    /// the primary display, in points).
    var x: Double
    var y: Double
}

/// Input Monitoring permission, which a listen-only event tap needs.
enum InputMonitoringPermission {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards macOS only reports.
    @discardableResult
    static func request() -> Bool { CGRequestListenEventAccess() }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Listen-only CGEventTap on the main run loop. It never modifies or
/// swallows events.
@MainActor
final class KeystrokeTap {
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onInput: (KeystrokeInput) -> Void

    init(onInput: @escaping (KeystrokeInput) -> Void) {
        self.onInput = onInput
    }

    var isRunning: Bool { machPort != nil }

    /// Returns false when macOS refuses the tap (Input Monitoring not granted).
    @discardableResult
    func start() -> Bool {
        if machPort != nil { return true }

        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let values = KeystrokeTapRawValues(type: type, event: event)
                if let refcon {
                    let address = UInt(bitPattern: refcon)
                    MainActor.assumeIsolated {
                        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                        let tap = Unmanaged<KeystrokeTap>.fromOpaque(pointer).takeUnretainedValue()
                        tap.handle(values)
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
    }

    private func handle(_ raw: KeystrokeTapRawValues) {
        guard let type = CGEventType(rawValue: raw.typeRaw) else { return }
        let kind: KeystrokeInput.Kind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return
        case .keyDown:
            guard !raw.autorepeat, let name = KeyCodeMap.name(for: raw.keyCode) else { return }
            kind = .keyDown(name: name)
        case .keyUp:
            guard let name = KeyCodeMap.name(for: raw.keyCode) else { return }
            kind = .keyUp(name: name)
        case .flagsChanged:
            guard let name = KeyCodeMap.name(for: raw.keyCode) else { return }
            if name == KeyName.capsLock {
                // Caps Lock toggles state; show it as a quick tap.
                onInput(KeystrokeInput(kind: .keyDown(name: name), x: raw.x, y: raw.y))
                kind = .keyUp(name: name)
            } else if let down = KeyCodeMap.isModifierDown(keyCode: raw.keyCode, flags: raw.flags) {
                kind = down ? .keyDown(name: name) : .keyUp(name: name)
            } else {
                return
            }
        case .leftMouseDown: kind = .mouseDown(button: KeyName.mouseLeft)
        case .leftMouseUp: kind = .mouseUp(button: KeyName.mouseLeft)
        case .rightMouseDown: kind = .mouseDown(button: KeyName.mouseRight)
        case .rightMouseUp: kind = .mouseUp(button: KeyName.mouseRight)
        case .otherMouseDown: kind = .mouseDown(button: Self.otherButtonName(raw.buttonNumber))
        case .otherMouseUp: kind = .mouseUp(button: Self.otherButtonName(raw.buttonNumber))
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: kind = .mouseDragged
        case .scrollWheel:
            let delta = raw.scrollLines != 0 ? raw.scrollLines : raw.scrollPoints
            guard delta != 0 else { return }
            kind = .scroll(deltaY: delta)
        default:
            return
        }
        onInput(KeystrokeInput(kind: kind, x: raw.x, y: raw.y))
    }

    static func otherButtonName(_ number: Int) -> String {
        switch number {
        case 2: return KeyName.mouseMiddle
        case 3: return KeyName.mouseBack
        case 4: return KeyName.mouseForward
        default: return KeyName.mouseMiddle
        }
    }
}

/// The fields the callback needs, copied out of the CGEvent.
struct KeystrokeTapRawValues: Sendable {
    var typeRaw: UInt32
    var keyCode: Int
    var flags: UInt64
    var autorepeat: Bool
    var buttonNumber: Int
    var scrollLines: Double
    var scrollPoints: Double
    var x: Double
    var y: Double

    init(type: CGEventType, event: CGEvent) {
        typeRaw = type.rawValue
        keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        flags = event.flags.rawValue
        autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        scrollLines = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        scrollPoints = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let location = event.location
        x = Double(location.x)
        y = Double(location.y)
    }
}
