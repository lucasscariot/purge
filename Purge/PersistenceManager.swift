import Foundation
import SwiftData

// Assuming Models are in a module or file accessible to this target
// If they are in a different module, we'd need to import that module.
// They seem to be in the same module, so we just use them.

@ModelActor
actor PersistenceManager {
    func persist(
        allMetadata: [AssetMetadata],
        rawClusters: [RawCluster],
        featureMap: [String: Data]
    ) throws {
        var clusterAssignment: [String: String] = [:]

        let clusterRecords: [ClusterRecord] = rawClusters.map { raw in
            let id = UUID().uuidString
            raw.assetIdentifiers.forEach { clusterAssignment[$0] = id }
            return ClusterRecord(
                id: id,
                clusterType: raw.type,
                label: raw.label,
                sublabel: raw.sublabel,
                assetIdentifiers: raw.assetIdentifiers,
                nearDuplicateSets: raw.nearDuplicateSets,
                totalBytes: raw.totalBytes,
                representativeDate: raw.representativeDate,
                representativeLat: raw.representativeLat,
                representativeLng: raw.representativeLng
            )
        }

        let assetRecords: [AssetRecord] = allMetadata.map { meta in
            let record = AssetRecord(localIdentifier: meta.localIdentifier)
            record.creationDate        = meta.date
            record.fileSize            = meta.estimatedFileSize
            record.isScreenshot        = meta.isScreenshot
            record.isLocallyAvailable  = true
            record.clusterID           = clusterAssignment[meta.localIdentifier]
            record.featureVectorData   = featureMap[meta.localIdentifier]
            record.latitude            = meta.latitude ?? 0
            record.longitude           = meta.longitude ?? 0
            return record
        }

        for record in clusterRecords { modelContext.insert(record) }
        for record in assetRecords { modelContext.insert(record) }
        try modelContext.save()
    }
}
