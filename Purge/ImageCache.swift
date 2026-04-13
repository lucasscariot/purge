import Foundation
import Photos
import UIKit

@MainActor
final class ImageCache {

    static let shared = ImageCache()
    
    private let cachingImageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    
    // Track active requests by localIdentifier to ensure uniqueness and memory safety
    private var requestIDs: [String: PHImageRequestID] = [:]
    
    // Limit concurrent requests to the Photos daemon (assetsd) to prevent XPC interruptions
    // and connection drops during rapid scrolling or zooming.
    private let semaphore = DispatchSemaphore(value: 15)

    private init() {
        imageCache.countLimit = 150
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping @Sendable (UIImage?) -> Void) {
        let localIdentifier = asset.localIdentifier
        let cacheKey = "\(localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        
        // Check memory cache first to avoid unnecessary Photos framework calls
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        // Cancel any existing request for this same asset to avoid redundant work and daemon overload
        if let existingID = requestIDs.removeValue(forKey: localIdentifier) {
            cachingImageManager.cancelImageRequest(existingID)
            semaphore.signal()
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        
        // Wait for an available slot before hitting the daemon
        semaphore.wait()
        
        let requestID = cachingImageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, info in
            guard let self = self else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let resultID = info?[PHImageResultRequestIDKey] as? PHImageRequestID ?? PHInvalidImageRequestID
            
            // If we got the final image or the request was cancelled, free up the slot
            if !isDegraded || isCancelled {
                if self.requestIDs[localIdentifier] == resultID {
                    self.requestIDs.removeValue(forKey: localIdentifier)
                    self.semaphore.signal()
                }
            }
            
            if let image = image, !isDegraded {
                self.imageCache.setObject(image, forKey: cacheKey)
            }
            
            completion(image)
        }
        
        // Store the request ID
        if requestID != PHInvalidImageRequestID {
            requestIDs[localIdentifier] = requestID
        } else {
            // If the request failed to start, release the semaphore slot
            semaphore.signal()
        }
    }
    
    func cancelRequest(for asset: PHAsset) {
        cancelRequest(for: asset.localIdentifier)
    }
    
    func cancelRequest(for localIdentifier: String) {
        if let requestID = requestIDs.removeValue(forKey: localIdentifier) {
            cachingImageManager.cancelImageRequest(requestID)
            semaphore.signal()
        }
    }
    
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
}
