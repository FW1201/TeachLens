import AppKit
import SwiftUI

/// The shared look of TeachLens's floating controls (Graphical Mode, the
/// whiteboard toolbars): 30 × 28 icon buttons on a Liquid Glass surface on
/// macOS 26, a regular material before that, and an opaque surface when
/// "Reduce transparency" is on.
enum TeachLensChrome {
    static let iconWidth: CGFloat = 30
    static let iconHeight: CGFloat = 28
    static let iconCorner: CGFloat = 8

    static var liquidGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    @MainActor static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Scales the chrome icon buttons (the floating toolbar's Small / Medium /
/// Large setting). 1 is the standard 30 × 28 button.
private struct ChromeIconScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var chromeIconScale: CGFloat {
        get { self[ChromeIconScaleKey.self] }
        set { self[ChromeIconScaleKey.self] = newValue }
    }
}

/// An icon button: hover and pressed feedback, plus a tinted fill when the
/// tool it controls is on.
struct ChromeIconButtonStyle: ButtonStyle {
    var isOn = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        ChromeIconBody(label: configuration.label, isPressed: configuration.isPressed, isOn: isOn, tint: tint)
    }
}

private struct ChromeIconBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isOn: Bool
    let tint: Color
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.chromeIconScale) private var scale

    var body: some View {
        let corner = TeachLensChrome.iconCorner * scale
        label
            .font(.system(size: 14 * scale, weight: .medium))
            .foregroundStyle(isOn ? tint : Color.primary)
            .frame(width: TeachLensChrome.iconWidth * scale, height: TeachLensChrome.iconHeight * scale)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(isOn ? tint.opacity(0.22) : Color.primary.opacity(hovering && isEnabled ? 0.09 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: corner))
            .scaleEffect(isPressed ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isOn)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// An icon menu that looks like the icon buttons next to it.
    func chromeIconMenu() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(ChromeIconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// The floating surface behind a row or column of icon buttons.
    func chromeSurface<S: Shape>(_ shape: S) -> some View {
        modifier(ChromeSurface(shape: shape))
    }
}

private struct ChromeSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        } else if TeachLensChrome.liquidGlassAvailable {
            glass(content)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
        #else
        content.background(.regularMaterial, in: shape)
        #endif
    }
}

/// Fades and lifts an item in shortly after its container appears, `index`
/// steps after the first, so a column of icons arrives in order instead of
/// all at once. With Reduce Motion the item is simply there.
struct StaggeredAppearance: ViewModifier {
    let index: Int
    var step: Double = 0.018
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85).delay(Double(index) * step)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppearance(index: index)) }
}

/// A thin vertical or horizontal rule between groups of icon buttons.
struct ChromeDivider: View {
    var vertical = true

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: vertical ? 1 : 22, height: vertical ? 18 : 1)
            .padding(vertical ? .horizontal : .vertical, 3)
    }
}
