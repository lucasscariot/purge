import SwiftUI

struct SwipeSessionView: View {
    let cluster: PhotoCluster
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var decisions: [(photo: DummyPhoto, decision: UserDecision)] = []
    @State private var showComplete = false

    private var keptCount:       Int { decisions.filter { $0.decision == .keep }.count }
    private var trashedCount:    Int { decisions.filter { $0.decision == .trash }.count }
    private var favouritedCount: Int { decisions.filter { $0.decision == .favourite }.count }
    private var spaceSavedMB:    Int { decisions.filter { $0.decision == .trash }.reduce(0) { $0 + $1.photo.sizeMB } }

    var body: some View {
        ZStack {
            PurgeColor.background.ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    keptCount: keptCount,
                    trashedCount: trashedCount,
                    favouritedCount: favouritedCount,
                    spaceSavedMB: spaceSavedMB,
                    onDone: { dismiss() }
                )
            } else {
                VStack(spacing: 0) {
                    header
                    progressBar
                    cardStack
                        .padding(.top, 24)
                    Spacer(minLength: 0)
                    actionButtons
                        .padding(.bottom, 44)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("< BACK")
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(cluster.label.replacingOccurrences(of: " ", with: "_"))
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                Text("\(cluster.photoCount) PHOTOS")
                    .font(PurgeFont.mono(9))
                    .foregroundStyle(PurgeColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(PurgeColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(PurgeColor.surface)
                Rectangle()
                    .fill(PurgeColor.primary)
                    .frame(width: geo.size.width * CGFloat(currentIndex) / CGFloat(max(cluster.photos.count, 1)))
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Card stack

    private var cardStack: some View {
        ZStack {
            if currentIndex + 2 < cluster.photos.count { stackPlaceholder(depth: 2) }
            if currentIndex + 1 < cluster.photos.count { stackPlaceholder(depth: 1) }
            if currentIndex < cluster.photos.count {
                SwipeCardView(
                    photo: cluster.photos[currentIndex],
                    cardIndex: currentIndex + 1,
                    total: cluster.photos.count,
                    onDecision: handleDecision
                )
                .id(currentIndex)
                .transition(.identity)
            }
        }
        .frame(height: 480)
    }

    private func stackPlaceholder(depth: Int) -> some View {
        Rectangle()
            .fill(depth == 1 ? PurgeColor.surface : PurgeColor.surfaceHigh)
            .frame(width: 320, height: 440)
            .overlay(Rectangle().strokeBorder(PurgeColor.border, lineWidth: 1))
            .offset(x: CGFloat(depth * 8), y: CGFloat(depth * -8))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 1) {
                sessionActionButton(label: "TRASH", color: PurgeColor.primary, textColor: .white) {
                    handleDecision(.trash)
                }
                sessionActionButton(label: "FAV", color: PurgeColor.warning, textColor: PurgeColor.background) {
                    handleDecision(.favourite)
                }
                sessionActionButton(label: "KEEP", color: PurgeColor.secondary, textColor: .white) {
                    handleDecision(.keep)
                }
            }
            .overlay(Rectangle().strokeBorder(PurgeColor.border, lineWidth: 1))

            Button {
                undoLast()
            } label: {
                Text("UNDO")
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(decisions.isEmpty ? PurgeColor.textMuted : PurgeColor.textMuted)
                    .underline(!decisions.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(decisions.isEmpty)
        }
        .padding(.horizontal, 20)
    }

    private func sessionActionButton(
        label: String,
        color: Color,
        textColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(PurgeFont.mono(12, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func handleDecision(_ decision: UserDecision) {
        guard currentIndex < cluster.photos.count else { return }
        let photo = cluster.photos[currentIndex]
        decisions.append((photo: photo, decision: decision))
        withAnimation(.easeIn(duration: 0.15)) {
            currentIndex += 1
        }
        if currentIndex >= cluster.photos.count {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showComplete = true
                }
                AnalyticsService.logSwipeSessionCompleted(kept: keptCount, trashed: trashedCount, favourited: favouritedCount)
            }
        }
    }

    private func undoLast() {
        guard !decisions.isEmpty else { return }
        decisions.removeLast()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentIndex = max(0, currentIndex - 1)
        }
    }
}

#Preview {
    SwipeSessionView(cluster: PhotoCluster.sampleClusters[0])
}
