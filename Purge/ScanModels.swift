import Foundation
import SwiftData

// MARK: - SwiftData Models

@Model
final class AssetRecord {
    @Attribute(.unique) var localIdentifier: String
    var creationDate: Date?
    var latitude: Double
    var longitude: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var isScreenshot: Bool
    var fileSize: Int64
    var isLocallyAvailable: Bool

    // Vision results
    @Attribute(.externalStorage) var featureVectorData: Data?
    var blurScore: Float        // -1 = not computed, higher = sharper
    var isBlurry: Bool

    // Cluster assignment
    var clusterID: String?

    init(localIdentifier: String) {
        self.localIdentifier   = localIdentifier
        self.latitude          = 0
        self.longitude         = 0
        self.pixelWidth        = 0
        self.pixelHeight       = 0
        self.isScreenshot      = false
        self.fileSize          = 0
        self.isLocallyAvailable = false
        self.blurScore         = -1
        self.isBlurry          = false
    }
}

@Model
final class ClusterRecord {
    @Attribute(.unique) var id: String
    var clusterType: String
    var label: String
    var sublabel: String
    var assetCount: Int
    var totalBytes: Int64
    var isReviewed: Bool
    var assetIdentifiers: [String]
    var nearDuplicateSetsData: Data?    // JSON-encoded [[String]]
    var representativeDate: Date?
    var representativeLat: Double?
    var representativeLng: Double?

    /// Decoded near-duplicate groups (not stored — derived from nearDuplicateSetsData)
    var nearDuplicateSets: [[String]] {
        guard let data = nearDuplicateSetsData,
              let sets = try? JSONDecoder().decode([[String]].self, from: data)
        else { return [] }
        return sets
    }

    init(
        id: String = UUID().uuidString,
        clusterType: String,
        label: String,
        sublabel: String,
        assetIdentifiers: [String] = [],
        nearDuplicateSets: [[String]] = [],
        totalBytes: Int64 = 0,
        representativeDate: Date? = nil,
        representativeLat: Double? = nil,
        representativeLng: Double? = nil
    ) {
        self.id                    = id
        self.clusterType           = clusterType
        self.label                 = label
        self.sublabel              = sublabel
        self.assetIdentifiers      = assetIdentifiers
        self.assetCount            = assetIdentifiers.count
        self.totalBytes            = totalBytes
        self.isReviewed            = false
        self.nearDuplicateSetsData = try? JSONEncoder().encode(nearDuplicateSets)
        self.representativeDate    = representativeDate
        self.representativeLat     = representativeLat
        self.representativeLng     = representativeLng
    }
}
