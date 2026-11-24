import SwiftUI

// Variant B ("Frosted Pill"): each combination is one capsule. Modifiers are
// merged into a single chip of glyphs in macOS order (⌃⌥⇧⌘); the main key is a
// white chip. On macOS 26+ the capsule uses Liquid Glass; earlier systems use
// a frosted material.

struct KeystrokeChip: Identifiable, Equatable {
    var id: String
    var text: String
    var sfSymbol: String?
    var isWord: Bool
}

struct KeystrokeDisplayGroup: Identifiable, Equatable {
    var id: String
    var modifierGlyphs: String
    var chips: [KeystrokeChip]
    var count: Int
    /// The Windows equivalent ("Windows 對照"), when it differs meaningfully.
    var windowsText: String?
    /// True when `modifierGlyphs` holds words ("Ctrl + Shift") rather than
    /// Mac glyphs, so the pill uses a smaller, unspaced font.
    var modifiersAreWords = false

    /// The Mac combination as one line, written the way macOS menus do:
    /// "⇧⌘4", "⌘Click".
    var macText: String {
        modifierGlyphs + chips.map(\.text).joined(separator: " ")
    }

    static let windowsModifierWords: Set<String> = ["Ctrl", "Alt", "Shift", "Fn", "⊞ Win"]

    /// The same combination with the Windows shortcut in the pill, for
    /// "Windows first". Nil when the two systems type it the same way (plain
    /// letters, digits), so those keep the normal pill.
    func windowsPrimary() -> KeystrokeDisplayGroup? {
        guard let windowsText else { return nil }
        let parts = windowsText.components(separatedBy: " + ")
        let modifiers = parts.filter { Self.windowsModifierWords.contains($0) }
        let keys = parts.filter { !Self.windowsModifierWords.contains($0) }
        var converted = self
        converted.modifierGlyphs = modifiers.joined(separator: " + ")
        converted.modifiersAreWords = true
        converted.chips = keys.enumerated().map { index, key in
            KeystrokeChip(id: "win-\(index)-\(key)", text: key, sfSymbol: nil, isWord: key.count > 2)
        }
        return converted
    }

    static func make(from group: KeystrokeGroup, index: Int) -> KeystrokeDisplayGroup {
        let ordered = KeyName.displayOrder(group.keys.map(\.name))
        var glyphs = ""
        var chips: [KeystrokeChip] = []
        for name in ordered {
            let display = KeyDisplayMap.display(for: name)
            if display.isModifier {
                glyphs += display.glyph ?? display.compactLabel
                continue
            }
            let text: String
            switch display.category {
            case .letter, .digit, .punctuation, .numpad, .function:
                text = display.label
            case .arrow:
                text = display.glyph ?? display.label
            case .mouse:
                text = display.compactLabel
            default:
                text = display.compactLabel
            }
            chips.append(KeystrokeChip(
                id: name,
                text: text,
                sfSymbol: display.sfSymbol,
                isWord: text.count > 2
            ))
        }
        let lastCount = group.keys.last?.pressedCount ?? 1
        return KeystrokeDisplayGroup(
            id: "\(index)-\(group.createdAt)",
            modifierGlyphs: glyphs,
            chips: chips,
            count: lastCount,
            windowsText: WindowsEquivalent.text(for: group.keys.map(\.name))
        )
    }
}

struct ClickRipple: Identifiable, Equatable {
    var id = UUID()
    /// Position in the overlay's own coordinates (top-left origin).
    var point: CGPoint
    var isSecondary: Bool
}

@MainActor
final class KeystrokeOverlayModel: ObservableObject {
    @Published var groups: [KeystrokeDisplayGroup] = []
    @Published var ripples: [ClickRipple] = []
    @Published var settings: KeystrokeSettings

    init(settings: KeystrokeSettings) {
        self.settings = settings
    }
}

struct KeystrokeHUDView: View {
    @ObservedObject var model: KeystrokeOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settings = model.settings
        let s = CGFloat(min(max(settings.scale, 0.5), 3))
        ZStack {
            ZStack(alignment: Self.frameAlignment(settings.position)) {
                Color.clear
                KeystrokeGlassContainer(glass: settings.glass, spacing: 8 * s) {
                    KeystrokeStackView(groups: model.groups, position: settings.position, scale: s, glass: settings.glass,
                                       showWindows: settings.windowsEquivalent, primary: settings.primaryPlatform)
                }
                .padding(CGFloat(settings.margin))
            }
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(model.ripples) { ripple in
                    ClickRippleView(ripple: ripple)
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.26, dampingFraction: 0.84),
                   value: model.groups)
        .allowsHitTesting(false)
    }

    static func frameAlignment(_ position: KeystrokePosition) -> Alignment {
        switch position {
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        }
    }

    static func stackAlignment(_ position: KeystrokePosition) -> HorizontalAlignment {
        switch position {
        case .bottomLeft, .topLeft: return .leading
        case .bottomCenter, .topCenter: return .center
        case .bottomRight, .topRight: return .trailing
        }
    }

    static func scaleAnchor(_ position: KeystrokePosition) -> UnitPoint {
        switch position {
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        }
    }
}

/// The column of combination pills; newest at the end, older ones faded.
struct KeystrokeStackView: View {
    let groups: [KeystrokeDisplayGroup]
    let position: KeystrokePosition
    let scale: CGFloat
    let glass: KeystrokeGlass
    var showWindows = false
    var primary: KeystrokePlatform = .mac
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pills pop in from their anchor and fade out, so a combination leaving
    /// never looks like it is shrinking into the next one. With Reduce Motion
    /// both directions are a plain fade.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.88, anchor: KeystrokeHUDView.scaleAnchor(position)).combined(with: .opacity),
            removal: .opacity
        )
    }

    var body: some View {
        VStack(alignment: KeystrokeHUDView.stackAlignment(position), spacing: 8 * scale) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let isOld = index < groups.count - 1
                KeystrokeComboView(group: group, scale: scale, glass: glass, showWindows: showWindows,
                                   alignment: KeystrokeHUDView.stackAlignment(position), primary: primary)
                    .opacity(isOld ? 0.55 : 1)
                    .scaleEffect(isOld ? 0.86 : 1, anchor: KeystrokeHUDView.scaleAnchor(position))
                    .transition(transition)
            }
        }
    }
}

/// The keystroke HUD as an image plus its on-screen frame (global AppKit
/// coordinates, points), for compositing into recorded frames.
struct KeystrokeRecordingFrame: @unchecked Sendable {
    let image: CGImage
    let frame: CGRect
}

/// A pill plus, when "Windows 對照" is on, the other system's shortcut under
/// it: Windows below a Mac pill, or Mac below a Windows pill.
struct KeystrokeComboView: View {
    let group: KeystrokeDisplayGroup
    let scale: CGFloat
    let glass: KeystrokeGlass
    let showWindows: Bool
    let alignment: HorizontalAlignment
    var primary: KeystrokePlatform = .mac

    var body: some View {
        let s = scale
        let windowsFirst = primary == .windows ? group.windowsPrimary() : nil
        VStack(alignment: alignment, spacing: 5 * s) {
            KeystrokePillView(group: windowsFirst ?? group, scale: s, glass: glass)
            if showWindows, windowsFirst != nil {
                HStack(spacing: 6 * s) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 12 * s, weight: .semibold))
                    Text(L10n.t("Mac", "Mac"))
                        .font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(group.macText)
                        .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 6 * s)
                .background(Capsule().fill(Color(white: 0.16).opacity(0.9)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .fixedSize()
            } else if showWindows, windowsFirst == nil, primary == .mac, let windows = group.windowsText {
                HStack(spacing: 6 * s) {
                    Image(systemName: "pc")
                        .font(.system(size: 12 * s, weight: .semibold))
                    Text(L10n.t("Windows ≈", "Windows 建議"))
                        .font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(windows)
                        .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 6 * s)
                .background(Capsule().fill(Color(red: 0.0, green: 0.36, blue: 0.75).opacity(0.88)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .fixedSize()
            }
        }
    }
}

struct KeystrokePillView: View {
    let group: KeystrokeDisplayGroup
    let scale: CGFloat
    let glass: KeystrokeGlass

    var body: some View {
        let s = scale
        HStack(spacing: 6 * s) {
            if !group.modifierGlyphs.isEmpty {
                Text(group.modifierGlyphs)
                    .font(.system(size: (group.modifiersAreWords ? 17 : 21) * s, weight: .semibold, design: .rounded))
                    .kerning((group.modifiersAreWords ? 0 : 2) * s)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14 * s)
                    .frame(minWidth: 46 * s, minHeight: 46 * s)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            ForEach(group.chips) { chip in
                HStack(spacing: 6 * s) {
                    if let symbol = chip.sfSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 17 * s, weight: .semibold))
                    }
                    Text(chip.text)
                        .font(.system(size: (chip.isWord ? 16 : 23) * s, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
                .padding(.horizontal, 15 * s)
                .frame(minWidth: 46 * s, minHeight: 46 * s)
                .background(Capsule().fill(Color.white))
            }
            if group.count > 1 {
                Text("×\(group.count)")
                    .font(.system(size: 14 * s, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.trailing, 6 * s)
                    .contentTransition(.numericText())
            }
        }
        .padding(7 * s)
        // Per Apple's guidance the glass effect is applied after the other
        // appearance modifiers; the background modifier adds its own shadow
        // only for the non-glass styles.
        .modifier(KeystrokePillBackground(glass: glass, scale: s))
        .fixedSize()
    }
}

/// Liquid Glass needs the macOS 26 SDK (Swift 6.2 toolchain) at build time
/// and macOS 26 at run time; otherwise the HUD falls back to a frosted
/// material. When "Reduce transparency" is on, the opaque style is used.
enum KeystrokeGlassSupport {
    static var isLiquidGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

struct KeystrokePillBackground: ViewModifier {
    let glass: KeystrokeGlass
    let scale: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || glass == .solid {
            Self.solid(content, scale: scale)
        } else if glass == .automatic && KeystrokeGlassSupport.isLiquidGlassAvailable {
            Self.liquidGlass(content)
        } else {
            Self.frosted(content, scale: scale)
        }
    }

    @ViewBuilder
    private static func liquidGlass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.28)), in: Capsule())
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func solid(_ content: Content, scale: CGFloat) -> some View {
        content
            .background(Capsule().fill(Color(white: 0.09).opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 14 * scale, y: 6 * scale)
    }

    private static func frosted(_ content: Content, scale: CGFloat) -> some View {
        content
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 14 * scale, y: 6 * scale)
    }
}

/// Groups the pills in a GlassEffectContainer when Liquid Glass is in use so
/// they render together and morph into one another as combinations change.
struct KeystrokeGlassContainer<Content: View>: View {
    let glass: KeystrokeGlass
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), glass == .automatic {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct ClickRippleView: View {
    let ripple: ClickRipple
    @State private var expanded = false

    var body: some View {
        let color = ripple.isSecondary ? Color(red: 1.0, green: 0.62, blue: 0.04) : Color.white
        Circle()
            .strokeBorder(color, lineWidth: 3)
            .background(Circle().fill(color.opacity(expanded ? 0 : 0.18)))
            .frame(width: 46, height: 46)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .scaleEffect(expanded ? 1.5 : 0.45)
            .opacity(expanded ? 0 : 1)
            .position(ripple.point)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) {
                    expanded = true
                }
            }
    }
}
