import Vision
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Vision analysis helpers
// All members are nonisolated — called from background Tasks, not the main actor.

enum VisionService {

    // MARK: Feature Prints

    // Reusable request to avoid spinning up the ML model configuration for every single photo
    nonisolated(unsafe) private static let featurePrintRequest: VNGenerateImageFeaturePrintRequest = {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        return request
    }()

    nonisolated static func featurePrint(for image: UIImage) throws -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([featurePrintRequest])
        return featurePrintRequest.results?.first as? VNFeaturePrintObservation
    }

    nonisolated static func distance(
        _ a: VNFeaturePrintObservation,
        _ b: VNFeaturePrintObservation
    ) -> Float {
        var d: Float = 0
        try? a.computeDistance(&d, to: b)
        return d
    }

    nonisolated static func serialize(_ obs: VNFeaturePrintObservation) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    nonisolated static func deserialize(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self,
            from: data
        )
    }

    // MARK: Blur Detection

    /// Sharpness score via high-frequency energy (CIEdges average).
    /// Higher = sharper. Values below `blurThreshold` are considered blurry.
    nonisolated static func sharpnessScore(for image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }

        var ciImage = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))

        ciImage = ciImage.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 0.0
        ])

        let edges = ciImage.applyingFilter("CIEdges", parameters: [
            "inputIntensity": 5.0
        ])

        guard let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: edges,
            kCIInputExtentKey: CIVector(cgRect: edges.extent)
        ]), let output = avgFilter.outputImage else { return 0 }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        var pixel = [UInt8](repeating: 0, count: 4)
        ctx.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return Float(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3.0
    }

    nonisolated static var blurThreshold: Float { 15.0 }

    nonisolated static func isBlurry(image: UIImage) -> Bool {
        sharpnessScore(for: image) < blurThreshold
    }
}
