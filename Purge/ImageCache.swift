import Foundation
import Photos
import UIKit

@MainActor
final class ImageCache {

    static let shared = ImageCache()
    
    private let cachingImageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    
    private var requestIDs: [String: PHImageRequestID] = [:]

    private init() {
        imageCache.countLimit = 150
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.imageCache.removeAllObjects()
            }
        }
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping @Sendable (UIImage?) -> Void) {
        requestImage(for: asset, targetSize: targetSize, ignoreDegraded: false, completion: completion)
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, ignoreDegraded: Bool = false, completion: @escaping @Sendable (UIImage?) -> Void) {
        let localIdentifier = asset.localIdentifier
        let cacheKey = "\(localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        if let existingID = requestIDs.removeValue(forKey: localIdentifier) {
            cachingImageManager.cancelImageRequest(existingID)
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        
        let requestID = cachingImageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, info in
            guard let self = self else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let resultID = info?[PHImageResultRequestIDKey] as? PHImageRequestID ?? PHInvalidImageRequestID
            
            if !isDegraded || isCancelled {
                if self.requestIDs[localIdentifier] == resultID {
                    self.requestIDs.removeValue(forKey: localIdentifier)
                }
            }
            
            if ignoreDegraded && isDegraded {
                return
            }
            
            if let image = image, !isDegraded {
                self.imageCache.setObject(image, forKey: cacheKey)
            }
            
            completion(image)
        }
        
        if requestID != PHInvalidImageRequestID {
            requestIDs[localIdentifier] = requestID
        }
    }
    
    func cancelRequest(for asset: PHAsset) {
        cancelRequest(for: asset.localIdentifier)
    }
    
    func cancelRequest(for localIdentifier: String) {
        if let requestID = requestIDs.removeValue(forKey: localIdentifier) {
            cachingImageManager.cancelImageRequest(requestID)
        }
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
}
