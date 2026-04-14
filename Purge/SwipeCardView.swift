import SwiftUI
import Photos

// MARK: -

struct SwipeCardView: View {
    let photo: DummyPhoto
    let cardIndex: Int
    let total: Int
    var onDecision: (UserDecision) -> Void

    @State private var offset: CGSize = .zero

    // MARK: - Drag state

    private var dragX: CGFloat { offset.width }
    private var dragY: CGFloat { offset.height }

    private var swipeDirection: UserDecision? {
        if dragX < -50 { return .trash }
        if dragX >  50 { return .keep }
        if dragY < -50 { return .favourite }
        return nil
    }

    private var stampOpacity: Double {
        let threshold: CGFloat = 30
        let full: CGFloat = 110
        let distance: CGFloat
        if      dragX < -threshold { distance = abs(dragX) - threshold }
        else if dragX >  threshold { distance = dragX - threshold }
        else if dragY < -threshold { distance = abs(dragY) - threshold }
        else                       { return 0 }
        return min(Double(distance) / Double(full - threshold), 1.0)
    }

    private var cardOverlayOpacity: Double { stampOpacity * 0.22 }
    private var rotation: Double           { Double(dragX / 16) }

    private var overlayColor: Color {
        switch swipeDirection {
        case .trash:     return PurgeColor.primary
        case .keep:      return PurgeColor.secondary
        case .favourite: return PurgeColor.warning
        case nil:        return .clear
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Photo content
            if let id = photo.localIdentifier {
                AsyncPhotoImage(localIdentifier: id, placeholder: photo.color)
            } else {
                Rectangle().fill(photo.color)
            }

            // Directional color wash
            overlayColor.opacity(cardOverlayOpacity)

            // Stamp
            stampLabel

            // Bottom bar
            VStack {
                Spacer()
                bottomBar
            }
        }
        .frame(width: 320, height: 440)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { val in offset = val.translation }
                .onEnded   { val in handleDragEnd(val) }
        )
    }

    // MARK: - Stamp

    @ViewBuilder
    private var stampLabel: some View {
        if let direction = swipeDirection, stampOpacity > 0 {
            let (text, color, angle): (String, Color, Double) = switch direction {
            case .trash:     ("TRASH", PurgeColor.primary,   -14.0)
            case .keep:      ("KEEP",  PurgeColor.secondary,  14.0)
            case .favourite: ("FAV",   PurgeColor.warning,     0.0)
            }

            Text(text)
                .font(PurgeFont.headline(48))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(color, lineWidth: 3))
                .rotationEffect(.degrees(angle))
                .opacity(stampOpacity)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.label)
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                Text(photo.date)
                    .font(PurgeFont.mono(9))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(cardIndex) / \(total)")
                    .font(PurgeFont.mono(9, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                Text("\(photo.sizeMB) MB")
                    .font(PurgeFont.mono(9))
                    .foregroundStyle(PurgeColor.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PurgeColor.background.opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
    }

    // MARK: - Gesture

    private func handleDragEnd(_ val: DragGesture.Value) {
        let threshold: CGFloat = 100
        if val.translation.width < -threshold {
            flyOff(to: CGSize(width: -700, height: val.translation.height * 0.5), decision: .trash)
        } else if val.translation.width > threshold {
            flyOff(to: CGSize(width: 700, height: val.translation.height * 0.5), decision: .keep)
        } else if val.translation.height < -threshold {
            flyOff(to: CGSize(width: val.translation.width * 0.5, height: -900), decision: .favourite)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) { offset = .zero }
        }
    }

    private func flyOff(to destination: CGSize, decision: UserDecision) {
        withAnimation(.easeIn(duration: 0.28)) { offset = destination }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            onDecision(decision)
        }
    }

    private func hapticStyle(for decision: UserDecision) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch decision {
        case .trash:     .heavy
        case .keep:      .medium
        case .favourite: .light
        }
    }
}

#Preview {
    SwipeCardView(
        photo: DummyPhoto(color: Color(hex: "4A7A9B"), label: "BEACH", date: "15 JUN", sizeMB: 22),
        cardIndex: 1,
        total: 5,
        onDecision: { _ in }
    )
    .padding()
    .background(PurgeColor.background)
}
