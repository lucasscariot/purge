import SwiftUI
import UIKit
import Photos

struct PinchablePhotoCard: View {
    let localIdentifier: String
    let onTap: () -> Void
    var onZoomChanged: ((Bool) -> Void)? = nil
    
    @State private var isZooming = false
    @State private var zoomImage: UIImage?
    @State private var startingFrame: CGRect = .zero
    @State private var thumbnailGlobalFrame: CGRect = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var isAnimating = false
    @State private var backgroundOpacity: Double = 0.0
    
    @State private var firstCenterPoint: CGPoint = .zero
    @State private var lastCenterPoint: CGPoint = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        thumbnailView
            .frame(width: 180, height: 180)
            .clipped()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: FramePreferenceKey.self, value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { frame in
                self.thumbnailGlobalFrame = frame
            }
            .overlay(
                ZoomGestureOverlay(
                    onBegan: { location in
                        if !isZooming && !isAnimating {
                            startZoom(location: location)
                        }
                    },
                    onChanged: { scale, location in
                        if isZooming {
                            updateZoom(scale: scale, location: location)
                        }
                    },
                    onEnded: {
                        if isZooming {
                            dismissZoom()
                        }
                    },
                    onTap: {
                        if !isZooming {
                            onTap()
                        }
                    }
                )
            )
            .background(
                FullscreenWindowOverlay(isPresented: isZooming) {
                    if let image = zoomImage {
                        zoomedImageView(image: image)
                    } else {
                        Color.clear
                    }
                }
            )
    }
    
    private var thumbnailView: some View {
        PhotoLoaderView(localIdentifier: localIdentifier, targetSize: CGSize(width: 400, height: 400))
    }
    
    private func zoomedImageView(image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(backgroundOpacity)
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: startingFrame.width, height: startingFrame.height)
                .clipShape(RoundedRectangle(cornerRadius: 12 / currentScale))
                .clipped()
                .scaleEffect(currentScale)
                .position(x: lastCenterPoint.x, y: lastCenterPoint.y)
        }
        .ignoresSafeArea()
    }
    
    private func startZoom(location: CGPoint) {
        startingFrame = thumbnailGlobalFrame
        firstCenterPoint = location
        lastCenterPoint = CGPoint(x: startingFrame.midX, y: startingFrame.midY)
        currentScale = 1.0
        
        Task {
            zoomImage = await loadHighQualityImage()
            await MainActor.run {
                isZooming = true
                onZoomChanged?(true)
                withAnimation(.easeInOut(duration: 0.2)) {
                    backgroundOpacity = 0.5
                }
            }
        }
    }
    
    private func updateZoom(scale: CGFloat, location: CGPoint) {
        let newScale = min(max(scale, minScale), maxScale)
        currentScale = newScale
        
        let newCenterX = location.x - (firstCenterPoint.x - startingFrame.midX) * newScale
        let newCenterY = location.y - (firstCenterPoint.y - startingFrame.midY) * newScale
        
        lastCenterPoint = CGPoint(x: newCenterX, y: newCenterY)
    }
    
    private func dismissZoom() {
        guard !isAnimating else { return }
        isAnimating = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentScale = 1.0
            backgroundOpacity = 0.0
            lastCenterPoint = CGPoint(x: thumbnailGlobalFrame.midX, y: thumbnailGlobalFrame.midY)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isZooming = false
            onZoomChanged?(false)
            currentScale = 1.0
            startingFrame = .zero
            lastCenterPoint = .zero
            firstCenterPoint = .zero
            isAnimating = false
        }
    }
    
    private func loadHighQualityImage() async -> UIImage? {
        guard !localIdentifier.isEmpty else { return nil }
        
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        
        let cachingManager = PHCachingImageManager()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        let targetSize = CGSize(width: 1200, height: 1200)
        
        return await withCheckedContinuation { continuation in
            cachingManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { img, _ in
                continuation.resume(returning: img)
            }
        }
    }
}

private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct FullscreenWindowOverlay<Content: View>: UIViewControllerRepresentable {
    var isPresented: Bool
    @ViewBuilder var content: () -> Content

    class Coordinator {
        var hostingController: UIHostingController<Content>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            if context.coordinator.hostingController == nil {
                let hostingController = UIHostingController(rootView: content())
                hostingController.view.backgroundColor = .clear
                
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) {
                    
                    window.addSubview(hostingController.view)
                    hostingController.view.frame = window.bounds
                }
                
                context.coordinator.hostingController = hostingController
            } else {
                context.coordinator.hostingController?.rootView = content()
            }
        } else {
            context.coordinator.hostingController?.view.removeFromSuperview()
            context.coordinator.hostingController = nil
        }
    }
}

private struct ZoomGestureOverlay: UIViewRepresentable {
    var onBegan: ((CGPoint) -> Void)
    var onChanged: ((CGFloat, CGPoint) -> Void)
    var onEnded: (() -> Void)
    var onTap: (() -> Void)
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded, onTap: onTap)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: ((CGPoint) -> Void)
        var onChanged: ((CGFloat, CGPoint) -> Void)
        var onEnded: (() -> Void)
        var onTap: (() -> Void)
        
        init(onBegan: @escaping (CGPoint) -> Void, onChanged: @escaping (CGFloat, CGPoint) -> Void, onEnded: @escaping () -> Void, onTap: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onTap = onTap
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }
            
            let location = gesture.location(in: window)
            
            switch gesture.state {
            case .began:
                if gesture.numberOfTouches >= 2 {
                    onBegan(location)
                }
            case .changed:
                onChanged(gesture.scale, location)
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                onTap()
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

private struct PhotoLoaderView: View {
    let localIdentifier: String
    let targetSize: CGSize
    
    @State private var imageData: Data?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .overlay {
                        if isLoading {
                            ProgressView()
                        }
                    }
            }
        }
        .clipped()
        .task(id: localIdentifier) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard !localIdentifier.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return }
        
        let cachingManager = PHCachingImageManager()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        let image: UIImage? = await withCheckedContinuation { continuation in
            cachingManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { img, _ in
                continuation.resume(returning: img)
            }
        }
        
        if let image = image {
            imageData = image.jpegData(compressionQuality: 0.9)
        }
    }
}
