import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ScanEngine.self) private var scanEngine

    var body: some View {
        ZStack(alignment: .bottom) {
            PurgeColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topLabel
                    wordmark
                    featureStack
                    Color.clear.frame(height: 120)
                }
            }
            .scrollIndicators(.hidden)

            if scanEngine.phase == .permissionDenied {
                permissionDenied
            } else {
                scanCTA
            }
        }
    }

    // MARK: - Top label

    private var topLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(PurgeColor.red)
                .frame(width: 6, height: 6)
            Text("PURGE · BY SCARIOT")
                .font(PurgeFont.mono(10, weight: .semibold))
                .foregroundStyle(PurgeColor.textMuted)
                .tracking(1.5)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PURGE")
                .font(PurgeFont.headline(96))
                .foregroundStyle(PurgeColor.text)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Rectangle()
                .fill(PurgeColor.red)
                .frame(height: 3)
                .frame(maxWidth: .infinity)

            Text("Ruthless photo cleanup.")
                .font(PurgeFont.display(16, weight: .regular))
                .italic()
                .foregroundStyle(PurgeColor.textMuted)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Feature Stack (scrapbook cards)

    private var featureStack: some View {
        VStack(spacing: -12) {
            featureCard(
                number: "01",
                headline: "Near-Duplicate Detection",
                body: "Vision AI finds photos taken within seconds of each other — burst shots, bracket exposures, the whole mess.",
                color: PurgeColor.mustard,
                rotation: -2.0
            )
            .zIndex(3)

            featureCard(
                number: "02",
                headline: "Browse by Day",
                body: "Your library, day by day. See exactly how many photos you took and how many are near-duplicates.",
                color: PurgeColor.sage,
                rotation: 1.5
            )
            .zIndex(2)

            featureCard(
                number: "03",
                headline: "Stays On-Device",
                body: "No cloud upload. No account. Runs locally using Apple's Vision framework. Your photos never leave.",
                color: PurgeColor.rose,
                rotation: -1.0
            )
            .zIndex(1)
        }
        .padding(.horizontal, 24)
    }

    private func featureCard(
        number: String,
        headline: String,
        body: String,
        color: Color,
        rotation: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(number)
                    .font(PurgeFont.mono(10, weight: .semibold))
                    .foregroundStyle(PurgeColor.text.opacity(0.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(PurgeColor.text.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(headline)
                    .font(PurgeFont.ui(14, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
            }

            Text(body)
                .font(PurgeFont.ui(13, weight: .regular))
                .foregroundStyle(PurgeColor.text.opacity(0.6))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: 3)
        )
        .stickerShadow()
        .rotationEffect(.degrees(rotation))
    }

    // MARK: - Scan CTA

    private var scanCTA: some View {
        Button {
            scanEngine.startScan(context: modelContext)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PurgeColor.red)

                Text("Scan My Library")
                    .font(PurgeFont.ui(17, weight: .bold))
                    .foregroundStyle(PurgeColor.text)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(PurgeColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .cardShadow()
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Denied

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(PurgeColor.red)
                Text("Photo access required")
                    .font(PurgeFont.ui(14, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                Spacer()
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Open Settings")
                        .font(PurgeFont.ui(16, weight: .semibold))
                        .foregroundStyle(PurgeColor.text)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PurgeColor.textMuted)
                    Spacer()
                }
                .frame(height: 64)
                .background(PurgeColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .cardShadow()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

#Preview {
    OnboardingView()
        .environment(ScanEngine())
        .modelContainer(for: [AssetRecord.self, ClusterRecord.self], inMemory: true)
}
