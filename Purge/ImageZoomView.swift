import SwiftUI
import Photos

struct ImageZoomView: View {
    let localIdentifier: String
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    @State private var isAppearing = false
    
    // Gesture state for magnification effect
    @GestureState private var magnifyBy: CGFloat = 1.0
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                    .opacity(isAppearing ? 1 : 0)
                
                // Zoomable image container
                if isAppearing {
                    imageContent(in: geometry)
                        .scaleEffect(scale * magnifyBy)
                        .offset(offset)
                        .rotationEffect(rotation)
                        .gesture(magnificationGesture)
                        .gesture(rotationGesture)
                        .gesture(dragGesture)
                        .gesture(doubleTapGesture(in: geometry))
                }
                
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        closeButton
                            .padding(.trailing, 16)
                            .padding(.top, 16)
                    }
                    Spacer()
                }
                .opacity(isAppearing ? 1 : 0)
                
                if isAppearing && scale == 1.0 && offset == .zero && rotation == .zero {
                    VStack {
                        Spacer()
                        Text("imagezoomview_pinch_to_zoom_drag_to_pan_rotate_with_two_fingers")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isAppearing = true
                }
            }
            .onDisappear {
                isAppearing = false
            }
        }
    }
    
    @ViewBuilder
    private func imageContent(in geometry: GeometryProxy) -> some View {
        AsyncPhotoImage(
            localIdentifier: localIdentifier,
            placeholder: Color.gray.opacity(0.3),
            targetSize: CGSize(
                width: geometry.size.width * maxScale,
                height: geometry.size.height * maxScale
            )
        )
        .frame(
            width: geometry.size.width,
            height: geometry.size.height
        )
        .clipped()
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = lastScale * value
                scale = min(max(newScale, minScale), maxScale)
                lastScale = scale
                
                // Reset offset when zooming out to original size
                if scale <= minScale {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                rotation = lastRotation + angle - lastRotation
            }
            .onEnded { angle in
                lastRotation = rotation
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow drag when zoomed in
                if scale > minScale {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width - value.translation.width,
                        height: lastOffset.height + value.translation.height - value.translation.height
                    )
                }
            }
            .onEnded { value in
                if scale > minScale {
                    let newOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    
                    // Bounds checking for offset
                    let maxOffset = calculateMaxOffset()
                    offset = CGSize(
                        width: min(max(newOffset.width, -maxOffset.width), maxOffset.width),
                        height: min(max(newOffset.height, -maxOffset.height), maxOffset.height)
                    )
                    lastOffset = offset
                }
            }
    }
    
    private func doubleTapGesture(in geometry: GeometryProxy) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > minScale {
                        // Zoom out to original
                        scale = minScale
                        lastScale = minScale
                        offset = .zero
                        lastOffset = .zero
                        rotation = .zero
                        lastRotation = .zero
                    } else {
                        // Zoom in to 2x centered
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
            }
    }
    
    private func calculateMaxOffset() -> CGSize {
        // Allow panning beyond bounds based on zoom level
        let excessScale = scale - 1.0
        return CGSize(
            width: excessScale * 200,
            height: excessScale * 200
        )
    }
    
    private var closeButton: some View {
        Button {
            dismissWithAnimation()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAppearing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}