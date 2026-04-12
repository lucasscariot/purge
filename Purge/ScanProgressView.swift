import SwiftUI

struct ScanProgressView: View {
    let phase: ScanPhase
    let photoCount: Int
    let duplicateCount: Int

    var body: some View {
        ZStack {
            PurgeColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    StatusDot(color: PurgeColor.primary, size: 8)
                        .opacity(pulseOpacity)
                    Text("PURGE")
                        .font(PurgeFont.mono(12, weight: .semibold))
                        .foregroundStyle(PurgeColor.text)
                    Spacer()
                    Text("SCANNING...")
                        .font(PurgeFont.mono(10))
                        .foregroundStyle(PurgeColor.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(PurgeColor.surface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PurgeColor.border).frame(height: 1)
                }

                Spacer()

                // Status block
                VStack(alignment: .leading, spacing: 24) {

                    // Phase label + big message
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTag(text: phaseTag, color: PurgeColor.warning)
                        Text(bigMessage)
                            .font(PurgeFont.headline(52))
                            .foregroundStyle(PurgeColor.text)
                            .tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)

                    // Progress bar
                    if case .analysing(let current, let total) = phase {
                        VStack(alignment: .leading, spacing: 0) {
                            progressBar(current: current, total: total)

                            HStack {
                                Text("PHOTOS_PROCESSED")
                                    .font(PurgeFont.mono(9, weight: .semibold))
                                    .foregroundStyle(PurgeColor.textMuted)
                                Spacer()
                                Text("\(current) / \(total)")
                                    .font(PurgeFont.mono(13, weight: .semibold))
                                    .foregroundStyle(PurgeColor.text)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(PurgeColor.surface)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(PurgeColor.border).frame(height: 1)
                            }

                            if duplicateCount > 0 {
                                HStack {
                                    Text("DUPLICATES_FOUND")
                                        .font(PurgeFont.mono(9, weight: .semibold))
                                        .foregroundStyle(PurgeColor.textMuted)
                                    Spacer()
                                    Text("\(duplicateCount)")
                                        .font(PurgeFont.mono(13, weight: .semibold))
                                        .foregroundStyle(PurgeColor.primary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(PurgeColor.surface)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(PurgeColor.border).frame(height: 1)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Footer note
                Text(footerText)
                    .font(PurgeFont.mono(10))
                    .foregroundStyle(PurgeColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Progress bar

    private func progressBar(current: Int, total: Int) -> some View {
        GeometryReader { geo in
            let fraction = total > 0 ? CGFloat(current) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(PurgeColor.surface)
                Rectangle()
                    .fill(PurgeColor.primary)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.25), value: current)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Computed strings

    private var phaseTag: String {
        switch phase {
        case .requestingPermission: return "AUTH_REQUEST"
        case .enumerating:          return "ENUMERATION"
        case .analysing:            return "VISION_ANALYSIS"
        case .clustering:           return "CLUSTERING"
        default:                    return "PROCESSING"
        }
    }

    private var bigMessage: String {
        switch phase {
        case .requestingPermission:
            return "REQUESTING ACCESS"
        case .enumerating:
            return "READING LIBRARY"
        case .analysing(let current, let total):
            let pct = total > 0 ? Int(Double(current) / Double(total) * 100) : 0
            return "\(pct)%\nCOMPLETE"
        case .clustering:
            return "GROUPING RESULTS"
        default:
            return "PROCESSING"
        }
    }

    private var footerText: String {
        switch phase {
        case .analysing:  return "ALL_PROCESSING_ON_DEVICE — NO_DATA_LEAVES_YOUR_PHONE"
        case .clustering: return "BUILDING_CLUSTERS — ALMOST_DONE"
        default:          return "YOUR_PHOTOS_NEVER_LEAVE_YOUR_DEVICE"
        }
    }

    // Simple pulse animation for the status dot
    @State private var pulseOpacity: Double = 1.0

    // The dot pulsing is handled by a simple repeating animation on appear
}

#Preview {
    ScanProgressView(
        phase: .analysing(current: 3420, total: 12847),
        photoCount: 12847,
        duplicateCount: 234
    )
}
