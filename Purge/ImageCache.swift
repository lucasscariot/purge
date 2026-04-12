import Foundation
import Photos
import UIKit

final class ImageCache {

    static let shared = ImageCache()
    
    private let cachingImageManager = PHCachingImageManager()
    
    private var requestIDs: [PHAsset: PHImageRequestID] = [:]
    private let lock = NSLock()

    private init() {
        cachingImageManager.allowsCachingHighQualityImages = false
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        
        lock.lock()
        let requestID = cachingImageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
            DispatchQueue.main.async {
                completion(image)
            }
        }
        requestIDs[asset] = requestID
        lock.unlock()
    }
    
    func cancelRequest(for asset: PHAsset) {
        lock.lock()
        if let requestID = requestIDs.removeValue(forKey: asset) {
            cachingImageManager.cancelImageRequest(requestID)
        }
        lock.unlock()
    }
    
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
}
