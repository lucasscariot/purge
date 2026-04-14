import SwiftUI
import Pow

struct SessionCompleteView: View {
    let keptCount: Int
    let trashedCount: Int
    let favouritedCount: Int
    let spaceSavedMB: Int
    var onDone: () -> Void
    var onReviewTrash: () -> Void = {}

    var body: some View {
        ZStack {
            PurgeColor.primary.ignoresSafeArea()

            VStack(spacing: 0) {

                // Header
                HStack {
                    StatusDot(color: .white, size: 8)
                    Text("PURGE")
                        .font(PurgeFont.mono(12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("SESSION_COMPLETE")
                        .font(PurgeFont.mono(9))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.08))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                }

                Spacer()

                // Headline
                VStack(alignment: .leading, spacing: 6) {
                    SectionTag(text: "CLEANUP_RESULT", color: .white.opacity(0.6))
                        .padding(.horizontal, 16)

                    Text("OBLITERATED.")
                        .font(PurgeFont.headline(68))
                        .foregroundStyle(.white)
                        .tracking(-2)
                        .padding(.horizontal, 16)
                }

                // Stats
                statsBlock
                    .padding(.top, 24)

                Spacer()

                // Actions
                actionButtons
                    .padding(.bottom, 50)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Stats block

    private var statsBlock: some View {
        VStack(spacing: 1) {
            statRow(label: "KEPT",         value: "\(keptCount)",       color: .white)
            statRow(label: "TRASHED",      value: "\(trashedCount)",    color: .white)
            statRow(label: "FAVOURITED",   value: "\(favouritedCount)", color: .white)
            statRow(label: "SPACE_SAVED",  value: spaceSavedLabel,      color: .white)
        }
    }

    private var spaceSavedLabel: String {
        spaceSavedMB >= 1000
            ? String(format: "%.1f GB", Double(spaceSavedMB) / 1000.0)
            : "\(spaceSavedMB) MB"
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(PurgeFont.mono(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(PurgeFont.mono(28, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
        .transition(.movingParts.pop)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 1) {
            Button(action: onReviewTrash) {
                Text("REVIEW_TRASH")
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white)
            }
            .buttonStyle(.plain)

            Button(action: onDone) {
                Text("DONE")
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    SessionCompleteView(
        keptCount: 12,
        trashedCount: 22,
        favouritedCount: 3,
        spaceSavedMB: 430,
        onDone: {}
    )
}
