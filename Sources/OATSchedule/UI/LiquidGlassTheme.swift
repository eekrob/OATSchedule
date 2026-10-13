import SwiftUI

/// Shared visual language for OATSchedule.
///
/// On iOS 26+ (when compiled with the matching SDK) this uses Apple's native
/// Liquid Glass APIs. Older SDKs / OS versions keep a close material-based
/// fallback so the project remains buildable and usable down to iOS 17.
enum OATTheme {
    static let blue = Color(red: 0.02, green: 0.43, blue: 0.95)
    static let deepBlue = Color(red: 0.03, green: 0.24, blue: 0.62)
    static let cyan = Color(red: 0.18, green: 0.77, blue: 1.00)
    static let red = Color(red: 0.86, green: 0.12, blue: 0.10)

    static let cardRadius: CGFloat = 22
    static let compactRadius: CGFloat = 16
}

struct OATAppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.045, blue: 0.085),
                        Color(red: 0.035, green: 0.075, blue: 0.13),
                        Color(red: 0.055, green: 0.055, blue: 0.085)
                    ]
                    : [
                        Color(red: 0.95, green: 0.98, blue: 1.00),
                        Color(red: 0.89, green: 0.95, blue: 1.00),
                        Color(red: 0.97, green: 0.98, blue: 1.00)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(OATTheme.blue.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 82)
                .offset(x: -170, y: -280)

            Circle()
                .fill(OATTheme.cyan.opacity(colorScheme == .dark ? 0.13 : 0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 78)
                .offset(x: 180, y: -90)

            Circle()
                .fill(OATTheme.red.opacity(colorScheme == .dark ? 0.08 : 0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 170, y: 350)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct OATGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if let tint {
                content
                    .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                content
                    .glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.20 : 0.65),
                            .white.opacity(colorScheme == .dark ? 0.05 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                radius: 22,
                x: 0,
                y: 12
            )
    }
}

private struct OATGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct OATNativeTabBehaviorModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
    func oatGlassSurface(
        radius: CGFloat = OATTheme.cardRadius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(OATGlassSurfaceModifier(radius: radius, tint: tint, interactive: interactive))
    }

    func oatGlassButton(prominent: Bool = false) -> some View {
        modifier(OATGlassButtonModifier(prominent: prominent))
    }

    func oatNativeTabBehavior() -> some View {
        modifier(OATNativeTabBehaviorModifier())
    }

    func oatClearScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

struct OATGlassStatusBanner: View {
    let title: String
    let systemImage: String
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .oatGlassSurface(radius: 18, tint: tint.opacity(0.08))
        .padding(.horizontal, 12)
    }
}
