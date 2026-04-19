// PURGE — Tactile Scrapbook Design System
// Fonts: AntonSC-Regular (wordmark only), IBPMono (code/mono labels)
// Display: System Serif (New York), UI: System Rounded (SF Pro Rounded)

import SwiftUI
import Photos
import UIKit

// MARK: - Color Palette

enum PurgeColor {
    // Base
    static let background = Color(hex: "FCFCFA")   // off-white paper, less yellow
    static let surface    = Color(hex: "FFFFFF")   // white card surface
    static let text       = Color(hex: "2D2B2A")   // charcoal (never pure black)
    static let textMuted  = Color(hex: "8C8A88")   // muted grey

    // Earthy pastel accents
    static let mustard    = Color(hex: "EBC464")   // warm yellow
    static let rose       = Color(hex: "E76F68")   // dusty rose / coral
    static let sage       = Color(hex: "A6BE88")   // sage green
    static let lavender   = Color(hex: "B4A5D7")   // lavender / periwinkle
    static let peach      = Color(hex: "E5B8AD")   // soft peach

    // Brand red (kept for destructive / CTA accents)
    static let red        = Color(hex: "E03010")

    // Legacy aliases
    static let primary     = Color(hex: "E03010")
    static let secondary   = Color(hex: "0038FF")
    static let warning     = mustard
    static let teal        = Color(hex: "00C896")
    static let surfaceHigh = Color(hex: "1E1E1E")
    static let border      = Color(hex: "2D2B2A").opacity(0.08)
}

// MARK: - Header pills (hero stats)

/// Shared chrome for hero “pill” chips: frosted fill, hairline border, soft shadow.
/// Use `FlowLayout` in the parent so pills wrap on narrow widths; keep labels
/// single-line via ``View/purgePillSingleLine()`` — text should never wrap inside
/// a pill.
struct PurgeHeaderPill<Content: View>: View {
    enum Variant {
        /// White hairline border, neutral shadow — storage / photo count.
        case neutral
        /// Rose-tinted border & shadow — near-duplicate family.
        case rose
    }

    let variant: Variant
    var verticalPadding: CGFloat = PurgeHeaderPillMetrics.verticalPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: PurgeHeaderPillMetrics.innerSpacing) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, PurgeHeaderPillMetrics.horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: PurgeHeaderPillMetrics.borderWidth)
        )
        .shadow(color: shadowColor, radius: PurgeHeaderPillMetrics.shadowRadius, x: 0, y: PurgeHeaderPillMetrics.shadowY)
    }

    private var borderColor: Color {
        switch variant {
        case .neutral: Color.white.opacity(0.3)
        case .rose: PurgeColor.rose.opacity(0.25)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .neutral: Color.black.opacity(0.05)
        case .rose: PurgeColor.rose.opacity(0.08)
        }
    }
}

private enum PurgeHeaderPillMetrics {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 9
    static let innerSpacing: CGFloat = 8
    static let borderWidth: CGFloat = 0.5
    static let shadowRadius: CGFloat = 10
    static let shadowY: CGFloat = 4
}

extension View {
    /// Single-line labels inside header pills (wrap the row with ``FlowLayout``, not words).
    func purgePillSingleLine() -> some View {
        lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

// MARK: - Scrapbook chip (tape-pinned hero stat)

/// Tape-pinned scrapbook card used for hero stats (near-duplicates, days, …).
/// Sits on the cream paper background with a gentle rotation, a hand-torn
/// washi-tape strip on the top edge, and a soft drop shadow so it reads as a
/// physical sticker rather than a flat UI chip.
struct ScrapbookStatChip: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var rotation: Double = 0
    var trailingPulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 16, alignment: .leading)

                Text(value)
                    .font(PurgeFont.display(26, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .tracking(-0.5)
            }

            HStack(spacing: 6) {
                Text(label)
                    .font(PurgeFont.mono(9, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if trailingPulse {
                    PurgePulseDot(color: tint, baseSize: 5)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 110, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PurgeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
        )
        .overlay(alignment: .topLeading) { WashiTape(tint: tint) }
        .shadow(color: tint.opacity(0.14), radius: 14, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .rotationEffect(.degrees(rotation))
    }
}

/// A short translucent strip mimicking masking tape, lightly rotated and offset
/// so it appears to "pin" the chip to the page.
private struct WashiTape: View {
    let tint: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(0.55))
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: 38, height: 12)
        .rotationEffect(.degrees(-10))
        .offset(x: 14, y: -6)
        .shadow(color: Color.black.opacity(0.08), radius: 1.5, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}

/// Slow, low-amplitude pulsing dot. Re-implemented here so any chip / pill
/// across the design system can use it without depending on HomeView.
struct PurgePulseDot: View {
    let color: Color
    var baseSize: CGFloat = 6
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: baseSize * 2.2, height: baseSize * 2.2)
                .scaleEffect(pulsing ? 1.15 : 0.55)
                .opacity(pulsing ? 0.0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: baseSize, height: baseSize)
        }
        .frame(width: baseSize * 2.2, height: baseSize * 2.2)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Scan progress rule

/// A hairline progress rule designed to fit the editorial header. When
/// `fraction` is set it draws a tinted fill from leading; when `nil` (we're
/// still enumerating and don't know the denominator yet) it animates an
/// indeterminate shimmer back and forth so the user knows work is happening.
struct ScanProgressRule: View {
    let fraction: Double?
    var tint: Color = PurgeColor.mustard
    var height: CGFloat = 3

    @State private var shimmerPhase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PurgeColor.text.opacity(0.07))
                    .frame(height: height)

                if let f = fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geo.size.width * CGFloat(min(max(f, 0), 1))), height: height)
                        .animation(.easeOut(duration: 0.25), value: f)
                } else {
                    // Indeterminate shimmer — a 28%-wide gradient slug that
                    // crosses the rule on a slow loop.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.0), tint.opacity(0.85), tint.opacity(0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.28, height: height)
                        .offset(x: geo.size.width * shimmerPhase)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                                shimmerPhase = 1.0
                            }
                        }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Editorial accent rule

/// Two-tone hairline rule used under the hero title to give the page a
/// magazine-spread feel. The tinted segment leads into a softer extension that
/// fades into the paper background.
struct EditorialRule: View {
    var tint: Color = PurgeColor.mustard
    var width: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(tint)
                .frame(width: width, height: 3)
            Capsule()
                .fill(PurgeColor.text.opacity(0.12))
                .frame(width: width * 0.6, height: 1.5)
                .padding(.leading, 6)
        }
    }
}

// MARK: - Typography

enum PurgeFont {
    /// Editorial serif — page titles, large numbers, card fronts
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func cursive(_ size: CGFloat) -> Font {
        .custom("Delius-Regular", size: size)
    }

    /// UI labels, buttons, metadata — SF Pro Rounded
    static func ui(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Legacy mono — kept for brand labels and scan output
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold: .custom("IBMPlexMono-SemiBold", size: size)
        case .medium:   .custom("IBMPlexMono-Medium",   size: size)
        default:        .custom("IBMPlexMono-Regular",  size: size)
        }
    }

    /// Wordmark only
    static func headline(_ size: CGFloat) -> Font {
        .custom("AntonSC-Regular", size: size)
    }
}

// MARK: - Shadows

extension View {
    func cardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 10)
            .shadow(color: .black.opacity(0.04), radius: 4,  x: 0, y: 2)
    }

    func stickerShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(0.04), radius: 2,  x: 0, y: 1)
    }
}

// MARK: - Color init (hex)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Card Button Style (spring press)

struct ScrapbookButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .rotationEffect(configuration.isPressed ? .degrees(0.5) : .degrees(0))
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 375
        let result = FlowResult(in: width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                points.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Legacy stubs (for ContentRootView compatibility)

struct SectionTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(PurgeFont.mono(9, weight: .semibold))
            .foregroundStyle(color)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Rectangle().strokeBorder(color, lineWidth: 1))
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

// MARK: - Spacing Constants

enum PurgeSpacing {
    /// Extra small spacing — tight element grouping
    static let xs: CGFloat = 4
    /// Small spacing — icon-to-text, compact lists
    static let small: CGFloat = 8
    /// Default spacing — between related elements
    static let medium: CGFloat = 16
    /// Large spacing — section separation
    static let large: CGFloat = 24
    /// Extra large spacing — major section breaks
    static let xl: CGFloat = 32
    /// Hero spacing — screen padding, full-width sections
    static let hero: CGFloat = 48
}

// MARK: - Animation Durations

enum PurgeAnimation {
    /// Quick feedback — button press, toggle
    static let quick: Double = 0.2
    /// Default — standard transitions
    static let standard: Double = 0.35
    /// Slow — large view transitions
    static let slow: Double = 0.5
    /// Gesture-driven — spring with medium damping
    static let gesture: Double = 0.4
    /// Spring press — button interactions
    static let springPress: Double = 0.3
}

// MARK: - Async Photo Image (shared component)

/// Unified async photo loader using ImageCache for memory management and concurrency control
@MainActor
struct AsyncPhotoImage: View {
    let localIdentifier: String
    let placeholder: Color
    var targetSize: CGSize = CGSize(width: 800, height: 800)
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(placeholder)
            }
        }
        .clipped()
        .task(id: localIdentifier) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard !localIdentifier.isEmpty else { return }

        guard let asset = PHAsset
            .fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            .firstObject
        else { return }

        let stream = AsyncStream<UIImage?> { continuation in
            continuation.onTermination = { _ in
                Task { @MainActor in
                    ImageCache.shared.cancelRequest(for: localIdentifier)
                }
            }
            ImageCache.shared.requestImage(for: asset, targetSize: targetSize, ignoreDegraded: false) { image in
                continuation.yield(image)
            }
        }

        for await img in stream {
            if let img = img {
                self.image = img
            }
            if Task.isCancelled { break }
        }
    }
}

// MARK: - Dot Grid Background

struct DotGridBackground: View {
    var dotSize: CGFloat = 3
    var dotSpacing: CGFloat = 28
    var dotColor: Color = Color(hex: "D5D3CF").opacity(0.8)
    
    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / dotSpacing) + 1
            let rows = Int(size.height / dotSpacing) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * dotSpacing
                    let y = CGFloat(row) * dotSpacing
                    context.fill(
                        Circle().path(in: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(dotColor)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func dotGridBackground() -> some View {
        background(DotGridBackground())
    }
}
