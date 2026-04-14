import SwiftUI
import Photos

struct DayDetailOverlay: View {
    let dayGroup: DayGroup
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(dayGroup.photos) { photo in
                            AsyncPhotoImage(
                                localIdentifier: photo.localIdentifier ?? "",
                                placeholder: Color.gray.opacity(0.3),
                                targetSize: CGSize(width: 200, height: 200)
                            )
                            .frame(width: 180, height: 180)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 60)
                    .padding(.bottom, 120)
                }
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: 15)
                )
                
                VStack {
                    Spacer()
                    closeButton
                        .padding(.bottom, 40)
                }
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismissWithAnimation()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            dragOffset = 400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
    
    private var closeButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                Text("Close")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(width: 120, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}