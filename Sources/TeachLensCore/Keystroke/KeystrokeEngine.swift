import Foundation

// Swift port of Keyviz's key event store (Legacy/keyviz/src/stores/key_event.ts,
// © Rahul Mula, GPL-3.0). The grouping, history, filter, drag and scroll rules
// follow the original so that TeachLens shows the same combinations Keyviz did.
//
// This file intentionally depends on Foundation only, so the state machine can
// be exercised by the self-test without a window server.

/// A key (or mouse action treated as a key) inside a displayed group.
struct KeystrokeKey: Equatable, Sendable {
    var name: String
    var pressedCount: Int
    /// The last press or release of this key.
    var lastPressedAt: TimeInterval
    /// When the current (or most recent) press began.
    var pressStartedAt: TimeInterval

    init(name: String, at time: TimeInterval) {
        self.name = name
        self.pressedCount = 1
        self.lastPressedAt = time
        self.pressStartedAt = time
    }
}

/// One visual combination, e.g. ⌘ + ⇧ + 4.
struct KeystrokeGroup: Equatable, Sendable {
    var keys: [KeystrokeKey]
    var createdAt: TimeInterval
}

/// Which presses start a visible group. Mirrors Keyviz's filter setting.
enum KeystrokeFilter: String, Codable, CaseIterable, Sendable {
    /// Show everything that is typed.
    case none
    /// Show only combinations that start with a modifier (shortcuts).
    case modifiers
    /// Show only combinations that start with one of `allowedKeys`.
    case custom
}

struct KeystrokeEngineConfig: Equatable, Sendable {
    var filter: KeystrokeFilter = .modifiers
    var allowedKeys: [String] = [KeyName.controlLeft, KeyName.metaLeft, KeyName.alt]
    var showHistory: Bool = false
    var maxHistory: Int = 5
    var showMouseEvents: Bool = true
    /// Seconds a released key stays on screen.
    var lingerDuration: TimeInterval = 3
    /// Points the pointer must travel with a button held before it counts as a drag.
    var dragThreshold: Double = 50
    /// A modifier pressed on its own (⌘ before ⌘C, or a ⌘-click) is only shown
    /// once it has been held this long, so quick taps don't flash a lone ⌘.
    var soloModifierDelay: TimeInterval = 0.35
    /// How long a modifier that was held on its own stays after release.
    var soloModifierLinger: TimeInterval = 1.0
    /// Keys the teacher added as custom shortcuts; they start a visible
    /// combination whatever the filter says.
    var extraKeys: Set<String> = []
}

struct KeystrokeEngine: Sendable {
    static let scrollLinger: TimeInterval = 0.3

    var config: KeystrokeEngineConfig

    private(set) var pressedKeys: [String] = []
    private(set) var groups: [KeystrokeGroup] = []

    // Mouse state
    private(set) var pressedMouseButton: String?
    private var mouseX: Double = 0
    private var mouseY: Double = 0
    private var dragStart: (x: Double, y: Double)?
    private(set) var dragging = false
    private var wheel = 0
    private var lastScrollAt: TimeInterval?

    init(config: KeystrokeEngineConfig = KeystrokeEngineConfig()) {
        self.config = config
    }

    mutating func reset() {
        pressedKeys = []
        groups = []
        pressedMouseButton = nil
        dragStart = nil
        dragging = false
        wheel = 0
        lastScrollAt = nil
    }

    /// Clears what is shown but keeps tracking what is physically held.
    mutating func clearGroups() {
        groups = []
    }

    // MARK: Keyboard

    mutating func keyDown(_ name: String, at now: TimeInterval) {
        // A repeat of a key that is already down is ignored (Keyviz did the
        // same in the native listener).
        if pressedKeys.contains(name) { return }

        var pressed = pressedKeys
        pressed.append(name)

        // 1. filter
        if config.filter != .none && ignore(pressed) {
            pressedKeys = pressed
            return
        }

        let last = groups.count - 1
        let key = KeystrokeKey(name: name, at: now)

        // 2. pressed again
        if last >= 0, groups[last].keys.contains(where: { $0.name == name }) {
            if config.showHistory && groups[last].keys.count > 1 {
                // History mode: repeat the still-held part of the combination as a new group.
                let groupKeys = groups[last].keys
                    .filter { pressed.contains($0.name) }
                    .map { KeystrokeKey(name: $0.name, at: now) }
                groups.append(KeystrokeGroup(keys: groupKeys, createdAt: now))
            } else {
                // Replace mode, or history mode with a single key: bump the count.
                var groupKeys: [KeystrokeKey] = []
                for gKey in groups[last].keys {
                    if gKey.name == name {
                        var bumped = gKey
                        bumped.pressedCount += 1
                        bumped.lastPressedAt = now
                        bumped.pressStartedAt = now
                        groupKeys.append(bumped)
                    } else if pressed.contains(gKey.name) {
                        groupKeys.append(gKey)
                    }
                }
                groups[last].keys = groupKeys
            }
        }
        // 3. add to group
        else {
            let createdAt = config.showHistory ? now : 0
            if pressed.count == 1 || last < 0 {
                if config.showHistory {
                    groups.append(KeystrokeGroup(keys: [key], createdAt: createdAt))
                } else {
                    groups = [KeystrokeGroup(keys: [key], createdAt: createdAt)]
                }
            } else if config.showHistory && groups[last].keys.contains(where: { !pressed.contains($0.name) }) {
                // History mode, partial combination: start a new group with what is still held.
                var groupKeys = groups[last].keys.filter { pressed.contains($0.name) }
                groupKeys.append(key)
                groups.append(KeystrokeGroup(keys: groupKeys, createdAt: createdAt))
            } else {
                // Keys released since (Z in "hold ⌘, Z, then X") are no longer
                // part of the combination.
                groups[last].keys.removeAll { !pressed.contains($0.name) }
                groups[last].keys.append(key)
            }
        }

        if config.showHistory && groups.count > max(1, config.maxHistory) {
            groups = Array(groups.suffix(max(1, config.maxHistory)))
        }
        pressedKeys = pressed
    }

    mutating func keyUp(_ name: String, at now: TimeInterval) {
        pressedKeys.removeAll { $0 == name }
        let last = groups.count - 1
        if last >= 0, let index = groups[last].keys.firstIndex(where: { $0.name == name }) {
            groups[last].keys[index].lastPressedAt = now
        }
    }

    func isPressed(_ name: String) -> Bool {
        pressedKeys.contains(name)
    }

    private func ignore(_ pressed: [String]) -> Bool {
        guard let first = pressed.first else { return true }
        if config.extraKeys.contains(CustomShortcut.normalized(first)) { return false }
        switch config.filter {
        case .none:
            return false
        case .modifiers:
            return !KeyName.modifiers.contains(first)
        case .custom:
            return !config.allowedKeys.contains(first)
        }
    }

    // MARK: Mouse

    mutating func mouseMoved(x: Double, y: Double, at now: TimeInterval) {
        mouseX = x
        mouseY = y
        guard let start = dragStart, !dragging else { return }
        let distance = hypot(x - start.x, y - start.y)
        guard distance > config.dragThreshold else { return }

        dragging = true
        let buttonName = pressedMouseButton
        let last = groups.count - 1
        let hasOtherGroupKeys = last >= 0 && groups[last].keys.contains { $0.name != buttonName }
        let dragAllowed = config.filter != .custom || config.allowedKeys.contains(KeyName.drag)
        guard config.showMouseEvents, hasOtherGroupKeys || dragAllowed else { return }

        // Replace the held button with a drag.
        if let buttonName {
            pressedKeys.removeAll { $0 == buttonName }
            if last >= 0 {
                groups[last].keys.removeAll { $0.name == buttonName }
            }
        }
        keyDown(KeyName.drag, at: now)
    }

    mutating func mouseDown(_ button: String, x: Double, y: Double, at now: TimeInterval) {
        mouseX = x
        mouseY = y
        dragStart = (x, y)
        dragging = false
        if config.showMouseEvents {
            keyDown(button, at: now)
        }
        pressedMouseButton = button
    }

    mutating func mouseUp(_ button: String, at now: TimeInterval) {
        if config.showMouseEvents {
            if dragging && pressedKeys.contains(KeyName.drag) {
                keyUp(KeyName.drag, at: now)
            } else {
                keyUp(button, at: now)
            }
        }
        pressedMouseButton = nil
        dragStart = nil
        dragging = false
    }

    /// `deltaY` > 0 scrolls up.
    mutating func scroll(deltaY: Double, at now: TimeInterval) {
        guard config.showMouseEvents else { return }
        let direction = deltaY > 0 ? 1 : (deltaY < 0 ? -1 : 0)
        guard direction != 0 else { return }

        let rawKey = direction > 0 ? KeyName.scrollUp : KeyName.scrollDown
        let previousKey = wheel > 0 ? KeyName.scrollUp : KeyName.scrollDown
        if wheel != 0 && wheel != direction && pressedKeys.contains(previousKey) {
            keyUp(previousKey, at: now)
        }
        wheel = direction
        lastScrollAt = now
        if !pressedKeys.contains(rawKey) {
            keyDown(rawKey, at: now)
        }
    }

    // MARK: Display timing

    /// The groups to draw at `now`. A group of modifiers only (nothing pressed
    /// with them yet) waits for `soloModifierDelay` before it appears and
    /// leaves after `soloModifierLinger`, so typing ⌘C never flashes "⌘" first
    /// and a quick ⌘ tap shows nothing at all. Holding ⌥ to explain it still
    /// shows it.
    ///
    /// With the shortcuts filter, modifiers alone never show: the HUD appears
    /// only once a full combination (modifier plus another key) is pressed.
    func visibleGroups(at now: TimeInterval) -> [KeystrokeGroup] {
        groups.filter { group in
            guard !group.keys.isEmpty,
                  group.keys.allSatisfy({ KeyName.modifiers.contains($0.name) }) else { return true }
            if config.filter == .modifiers { return false }
            let held = group.keys.filter { pressedKeys.contains($0.name) }
            if let firstHeld = held.map(\.pressStartedAt).min() {
                return now - firstHeld >= config.soloModifierDelay
            }
            let longestHold = group.keys.map { $0.lastPressedAt - $0.pressStartedAt }.max() ?? 0
            let released = group.keys.map(\.lastPressedAt).max() ?? 0
            return longestHold >= config.soloModifierDelay && now - released < config.soloModifierLinger
        }
    }

    // MARK: Time

    /// Expires released keys and scroll gestures. Returns true when `groups`
    /// changed and the view should refresh.
    @discardableResult
    mutating func tick(at now: TimeInterval) -> Bool {
        let before = groups

        if let lastScrollAt, now - lastScrollAt > Self.scrollLinger {
            if pressedKeys.contains(KeyName.scrollUp) { keyUp(KeyName.scrollUp, at: now) }
            if pressedKeys.contains(KeyName.scrollDown) { keyUp(KeyName.scrollDown, at: now) }
            wheel = 0
            self.lastScrollAt = nil
        }

        // A combination leaves as a whole: it stays while any of its keys is
        // held and for `lingerDuration` after the last one is released, so
        // holding ⌘ after ⌘Z doesn't shrink the pill to a lone "⌘".
        groups = groups.filter { group in
            group.keys.contains { pressedKeys.contains($0.name) }
                || now - (group.keys.map(\.lastPressedAt).max() ?? 0) < config.lingerDuration
        }
        return groups != before
    }
}
