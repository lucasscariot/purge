import UIKit
import SwiftUI
import Photos

// MARK: - Overlay View (pure UIView, no UICollectionView)

final class PhotoStackOverlayView: UIView {

    var onDismiss: (() -> Void)?
    var onRestoreGridCards: (() -> Void)?

    private let dimView = UIView()
    private var cardViews: [UIView] = []

    // Precomputed per-card configs
    private var stackCenters:    [CGPoint]          = []
    private var stackTransforms: [CGAffineTransform] = []
    private var spreadCenters:   [CGPoint]          = []
    private var spreadTransforms:[CGAffineTransform] = []

    // Mirrors PhotoStackView patterns so the overlay starts in the exact same visual state
    private let patternOffsets: [[CGPoint]] = [
        [CGPoint(x: -8, y: -4), CGPoint(x:  8, y:  4)],
        [CGPoint(x: -6, y: -6), CGPoint(x:  0, y:  0), CGPoint(x:  6, y:  6)],
        [CGPoint(x: -8, y: -4), CGPoint(x: -4, y:  4), CGPoint(x:  4, y: -4), CGPoint(x:  8, y:  4)],
    ]
    private let patternRotations: [[CGFloat]] = [
        [-4, 3],
        [-5, 0, 4],
        [-6, -2, 2, 5],
    ]
    private let stackScales: [CGFloat] = [1.0, 0.96, 0.92, 0.88, 0.84, 0.80]

    // Alpha at progress=0 for each card — grid-visible cards start at 1, extras at 0
    private var stackAlphas: [CGFloat] = []

    // Spread target — screen-relative positions so cards spread across the full screen
    // regardless of where the source tile sits (expressed as fractions for 393×852 baseline)
    private let spreadFractions: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.28),  // top-centre
        CGPoint(x: 0.20, y: 0.45),  // left
        CGPoint(x: 0.80, y: 0.45),  // right
        CGPoint(x: 0.25, y: 0.65),  // lower-left
        CGPoint(x: 0.75, y: 0.65),  // lower-right
        CGPoint(x: 0.50, y: 0.80),  // bottom-centre
    ]
    private let spreadScale: CGFloat = 1.25  // cards grow 25 % at full spread

    private let cardSize = CGSize(width: 120, height: 120)

    init(photos: [DummyPhoto], sourceFrame: CGRect, windowBounds: CGRect, seed: Int,
         onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)

        let src      = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let count    = min(photos.count, 6)

        // Use the same seed-based pattern as PhotoStackView for grid-visible cards
        let pidx       = abs(seed) % patternOffsets.count
        let gridOff    = patternOffsets[pidx]
        let gridRot    = patternRotations[pidx]
        let gridCount  = min(count, gridOff.count + 1)  // cards actually shown in the grid

        for i in 0..<count {
            let offset: CGPoint
            let rotDeg: CGFloat
            if i < gridOff.count {
                // Card matches grid exactly
                offset = gridOff[i]
                rotDeg = i < gridRot.count ? gridRot[i] : 0
            } else if i < gridCount {
                // Last grid card — no offset (same as buildStack's fallback)
                offset = .zero
                rotDeg = 0
            } else {
                // Extra cards beyond grid: hidden, stacked at centre
                offset = .zero
                rotDeg = gridRot.isEmpty ? 0 : gridRot[i % gridRot.count] * 0.3
            }

            let rot     = rotDeg * .pi / 180
            let scale   = stackScales[min(i, stackScales.count - 1)]
            let isExtra = i >= gridCount

            stackCenters.append(CGPoint(x: src.x + offset.x, y: src.y + offset.y))
            stackTransforms.append(
                CGAffineTransform(rotationAngle: rot).scaledBy(x: scale, y: scale)
            )
            stackAlphas.append(isExtra ? 0 : 1)

            let sf = spreadFractions[i]
            spreadCenters.append(CGPoint(x: windowBounds.width  * sf.x,
                                         y: windowBounds.height * sf.y))
            spreadTransforms.append(
                CGAffineTransform(rotationAngle: rot)
                    .scaledBy(x: spreadScale, y: spreadScale)
            )
        }

        setupDim()
        setupCards(photos: photos, count: count)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func setupDim() {
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.frame = bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(dimView)
    }

    private func setupCards(photos: [DummyPhoto], count: Int) {
        // Back cards added first so the front card sits on top
        for i in stride(from: count - 1, through: 0, by: -1) {
            let card = makeCard(photo: photos[i])
            card.center    = stackCenters[i]
            card.transform = stackTransforms[i]
            card.alpha     = stackAlphas[i]
            addSubview(card)
            cardViews.insert(card, at: 0)  // keep cardViews[0] = front
        }
    }

    private func makeCard(photo: DummyPhoto) -> UIView {
        let container = UIView(frame: CGRect(origin: .zero, size: cardSize))
        container.layer.cornerRadius  = 10
        container.layer.cornerCurve   = .continuous
        container.layer.borderColor   = UIColor.white.cgColor
        container.layer.borderWidth   = 2.5
        container.layer.masksToBounds = false

        let iv = UIImageView(frame: container.bounds)
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.contentMode  = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.layer.cornerCurve  = .continuous
        iv.backgroundColor    = UIColor(photo.color)
        container.addSubview(iv)

        if let localId = photo.localIdentifier {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
            if let asset = result.firstObject {
                ImageCache.shared.requestImage(
                    for: asset, targetSize: CGSize(width: 320, height: 320)
                ) { [weak iv] img in
                    DispatchQueue.main.async { iv?.image = img }
                }
            }
        }
        return container
    }

    // MARK: Progress (called on every gesture .changed)

    func updateProgress(_ t: CGFloat) {
        updateProgressWithRotation(t, rotation: 0)
    }

    func updateProgressWithRotation(_ t: CGFloat, rotation: CGFloat) {
        for (i, card) in cardViews.enumerated() {
            card.center    = lerp(stackCenters[i],    spreadCenters[i],    t)
            let baseTransform = lerpAffine(stackTransforms[i], spreadTransforms[i], t)
            let rotationTransform = CGAffineTransform(rotationAngle: rotation)
            card.transform = rotationTransform.concatenating(baseTransform)
            card.alpha     = stackAlphas[i] + (1 - stackAlphas[i]) * t
        }
        dimView.alpha = t * 0.45
    }

    // MARK: Spring back and remove

    func springClose(releaseVelocity: CGFloat = 0, finalRotation: CGFloat = 0) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // UIView.animate with .beginFromCurrentState reads the presentation layer for
        // every property — including dimView.alpha and layer.shadowOpacity — so there
        // is no single-frame snap regardless of what updateProgress set on the model.
        UIView.animate(
            withDuration: 0.52,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            for (i, card) in self.cardViews.enumerated() {
                card.center    = self.stackCenters[i]
                let rotationTransform = CGAffineTransform(rotationAngle: -finalRotation)
                card.transform = rotationTransform.concatenating(self.stackTransforms[i])
                card.alpha     = self.stackAlphas[i]
            }
            self.dimView.alpha = 0
        } completion: { _ in
            self.onRestoreGridCards?()
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    // MARK: Interpolation helpers

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }
    // Component-wise affine lerp — valid for our small angles (≤ 6°)
    private func lerpAffine(_ a: CGAffineTransform, _ b: CGAffineTransform,
                             _ t: CGFloat) -> CGAffineTransform {
        CGAffineTransform(
            a:  lerp(a.a,  b.a,  t),  b:  lerp(a.b,  b.b,  t),
            c:  lerp(a.c,  b.c,  t),  d:  lerp(a.d,  b.d,  t),
            tx: lerp(a.tx, b.tx, t),  ty: lerp(a.ty, b.ty, t)
        )
    }
}

// MARK: - PhotoStackView (collapsed pile in the grid)

final class PhotoStackView: UIView {
    var onTap: (() -> Void)?

    private var photos:     [DummyPhoto] = []
    private var seed:       Int = 0
    private var imageViews: [UIImageView] = []
    private weak var activeOverlay: PhotoStackOverlayView?
    
    // Track cumulative rotation across pinch + rotation gestures
    private var currentRotation: CGFloat = 0

    // Patterns mirror PhotoPileView exactly
    private let patternOffsets: [[CGPoint]] = [
        [CGPoint(x: -8, y: -4), CGPoint(x:  8, y:  4)],
        [CGPoint(x: -6, y: -6), CGPoint(x:  0, y:  0), CGPoint(x:  6, y:  6)],
        [CGPoint(x: -8, y: -4), CGPoint(x: -4, y:  4), CGPoint(x:  4, y: -4), CGPoint(x:  8, y:  4)],
    ]
    private let patternRotations: [[CGFloat]] = [
        [-4, 3],
        [-5, 0, 4],
        [-6, -2, 2, 5],
    ]

    init(photos: [DummyPhoto], seed: Int) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 160, height: 160)))
        self.photos = photos
        self.seed   = seed
        buildStack()
        addGestures()
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(photos: [DummyPhoto]) {
        guard photos.map(\.id) != self.photos.map(\.id) else { return }
        self.photos = photos
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        buildStack()
    }

    private func buildStack() {
        let pidx      = abs(seed) % patternOffsets.count
        let offsets   = patternOffsets[pidx]
        let rotations = patternRotations[pidx]
        let count     = min(photos.count, offsets.count + 1)

        for i in (0..<count).reversed() {
            let iv  = makeImageView(for: photos[i])
            let rot = i < rotations.count ? rotations[i] : 0
            let off = i < offsets.count   ? offsets[i]   : .zero
            iv.transform = CGAffineTransform(rotationAngle: rot * .pi / 180)
            iv.center    = CGPoint(x: bounds.midX + off.x, y: bounds.midY + off.y)
            addSubview(iv)
            imageViews.append(iv)
        }
    }

    private func makeImageView(for photo: DummyPhoto) -> UIImageView {
        let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        iv.contentMode     = .scaleAspectFill
        iv.clipsToBounds   = true   // masksToBounds stays true — image clips to corners
        iv.backgroundColor = UIColor(photo.color)
        iv.layer.cornerRadius = 8
        iv.layer.cornerCurve  = .continuous
        iv.layer.borderColor  = UIColor.white.cgColor
        iv.layer.borderWidth  = 2

        if let localId = photo.localIdentifier {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
            if let asset = result.firstObject {
                ImageCache.shared.requestImage(
                    for: asset, targetSize: CGSize(width: 256, height: 256)
                ) { [weak iv] img in
                    DispatchQueue.main.async { iv?.image = img }
                }
            }
        }
        return iv
    }

    // MARK: Gestures

    private func addGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        addGestureRecognizer(rotation)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() { onTap?() }

    @objc private func handleRotation(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began:
            currentRotation = 0
        case .changed:
            currentRotation += g.rotation
            g.rotation = 0
            activeOverlay?.updateProgressWithRotation(currentPinchProgress, rotation: currentRotation)
        case .ended, .cancelled, .failed:
            break
        default:
            break
        }
    }
    
    private var currentPinchProgress: CGFloat = 0

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard activeOverlay == nil, let window else { return }
            let sourceFrame = convert(bounds, to: window)
            currentRotation = 0
            currentPinchProgress = 0

            // Hide grid cards — overlay will show identical cards on top
            imageViews.forEach { $0.alpha = 0 }

            let overlay = PhotoStackOverlayView(
                photos: Array(photos.prefix(6)),
                sourceFrame: sourceFrame,
                windowBounds: window.bounds,
                seed: seed
            ) { [weak self] in
                self?.activeOverlay = nil
            }
            // Called after spring ends, while overlay still covers the grid —
            // grid cards restore to alpha=1 invisibly, then overlay fades out over them.
            overlay.onRestoreGridCards = { [weak self] in
                self?.imageViews.forEach { $0.alpha = 1 }
            }
            overlay.frame = window.bounds
            window.addSubview(overlay)
            activeOverlay = overlay

        case .changed:
            let progress = max(0, min(1, (g.scale - 1.0) / 1.2))
            currentPinchProgress = progress
            activeOverlay?.updateProgressWithRotation(progress, rotation: currentRotation)

        case .ended, .cancelled, .failed:
            activeOverlay?.springClose(releaseVelocity: g.velocity, finalRotation: currentRotation)

        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PhotoStackView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - SwiftUI Bridge

struct PinchablePhotoStack: UIViewRepresentable {
    let photos: [DummyPhoto]
    let seed:   Int
    var onTap:  () -> Void

    func makeUIView(context: Context) -> PhotoStackView {
        let v = PhotoStackView(photos: photos, seed: seed)
        v.onTap = onTap
        return v
    }

    func updateUIView(_ view: PhotoStackView, context: Context) {
        view.update(photos: photos)
        view.onTap = onTap
    }
}
