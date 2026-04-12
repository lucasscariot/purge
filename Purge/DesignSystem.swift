// PURGE — Tactile Scrapbook Design System
// Fonts: AntonSC-Regular (wordmark only), IBMPlexMono (code/mono labels)
// Display: System Serif (New York), UI: System Rounded (SF Pro Rounded)

import SwiftUI

// MARK: - Color Palette

enum PurgeColor {
    // Base
    static let background = Color(hex: "FAF8F5")   // cream paper
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

// MARK: - Typography

enum PurgeFont {
    /// Editorial serif — page titles, large numbers, card fronts
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
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
        let width = proposal.width ?? UIScreen.main.bounds.width
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
