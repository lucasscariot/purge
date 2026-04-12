import Foundation
import CoreLocation
import Vision

// MARK: - Intermediate types

public struct AssetMetadata {
    let localIdentifier: String
    let date: Date?
    let latitude: Double?
    let longitude: Double?
    let pixelWidth: Int
    let pixelHeight: Int
    let isScreenshot: Bool
    let estimatedFileSize: Int64
}

public struct RawCluster {
    var type: String
    var label: String
    var sublabel: String
    var assetIdentifiers: [String]
    var nearDuplicateSets: [[String]]
    var totalBytes: Int64
    var representativeDate: Date?
    var representativeLat: Double?
    var representativeLng: Double?

    nonisolated init(
        type: String, label: String, sublabel: String,
        assetIdentifiers: [String], nearDuplicateSets: [[String]] = [],
        totalBytes: Int64, representativeDate: Date? = nil,
        representativeLat: Double? = nil, representativeLng: Double? = nil
    ) {
        self.type               = type
        self.label              = label
        self.sublabel           = sublabel
        self.assetIdentifiers   = assetIdentifiers
        self.nearDuplicateSets  = nearDuplicateSets
        self.totalBytes         = totalBytes
        self.representativeDate = representativeDate
        self.representativeLat  = representativeLat
        self.representativeLng  = representativeLng
    }
}

public struct ScannedAssetInfo {
    let localIdentifier: String
    let date: Date?
    let latitude: Double?
    let longitude: Double?
    let fileSize: Int64
    let isScreenshot: Bool
    let featureData: Data?        // nil for non-candidates
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - Clustering Engine

enum ClusteringEngine {

    // MARK: - Temporal Candidate Detection

    /// Returns identifiers of all photos that have at least one other photo
    /// taken within `windowMinutes` — the only ones worth running Vision on.
    nonisolated static func temporalCandidates(
        from metadata: [AssetMetadata],
        windowMinutes: Double = 5
    ) -> Set<String> {
        let nonScreenshots = metadata
            .filter { !$0.isScreenshot }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        guard !nonScreenshots.isEmpty else { return [] }

        var candidates = Set<String>()
        let window = windowMinutes * 60

        let dates: [Double] = nonScreenshots.map { ($0.date ?? .distantPast).timeIntervalSince1970 }

        var lo = 0
        for hi in 0..<nonScreenshots.count {
            let hiDate = dates[hi]
            while lo < hi {
                let loDate = dates[lo]
                if hiDate - loDate > window { 
                    lo += 1 
                } else { 
                    break 
                }
            }
            if hi > lo {
                candidates.insert(nonScreenshots[hi].localIdentifier)
                for i in lo..<hi {
                    candidates.insert(nonScreenshots[i].localIdentifier)
                }
            }
        }
        return candidates
    }

    // MARK: - Cluster Entry Point

    nonisolated static func cluster(
        allMetadata: [AssetMetadata],
        scannedCandidates: [ScannedAssetInfo]
    ) -> [RawCluster] {
        // Build lookup for vision-analysed assets
        let candidateMap = Dictionary(
            uniqueKeysWithValues: scannedCandidates.map { ($0.localIdentifier, $0) }
        )

        // Merge: all assets get metadata, candidates additionally get featureData
        let allAssets: [ScannedAssetInfo] = allMetadata.map { meta in
            if let c = candidateMap[meta.localIdentifier] { return c }
            return ScannedAssetInfo(
                localIdentifier: meta.localIdentifier,
                date: meta.date,
                latitude: meta.latitude,
                longitude: meta.longitude,
                fileSize: meta.estimatedFileSize,
                isScreenshot: meta.isScreenshot,
                featureData: nil,
                pixelWidth: meta.pixelWidth,
                pixelHeight: meta.pixelHeight
            )
        }

        let nonScreenshots = allAssets.filter { !$0.isScreenshot }
        let screenshots    = allAssets.filter { $0.isScreenshot }

        var clusters: [RawCluster] = []
        var clusteredIDs = Set<String>()

        // 1. Near-duplicate groups (candidates only)
        let dupeGroups = nearDuplicateGroups(candidates: scannedCandidates.filter { !$0.isScreenshot })
        for group in dupeGroups {
            let total = group.reduce(0) { $0 + $1.fileSize }
            let repDate = group.compactMap(\.date).max()
            let repLat = group.compactMap(\.latitude).first
            let repLng = group.compactMap(\.longitude).first
            group.forEach { clusteredIDs.insert($0.localIdentifier) }
            clusters.append(RawCluster(
                type: "duplicate",
                label: duplicateLabel(group: group),
                sublabel: "\(group.count) NEAR-DUPLICATES · \(bytesLabel(total))_WASTED",
                assetIdentifiers: group.map(\.localIdentifier),
                totalBytes: total,
                representativeDate: repDate,
                representativeLat: repLat,
                representativeLng: repLng
            ))
        }

        // 2. Screenshot clusters
        if !screenshots.isEmpty {
            let total = screenshots.reduce(0) { $0 + $1.fileSize }
            let repDate = screenshots.compactMap(\.date).max()
            screenshots.forEach { clusteredIDs.insert($0.localIdentifier) }
            clusters.append(RawCluster(
                type: "screenshot",
                label: "SCREENSHOTS",
                sublabel: "\(screenshots.count) SCREENSHOTS · \(bytesLabel(total))",
                assetIdentifiers: screenshots.map(\.localIdentifier),
                totalBytes: total,
                representativeDate: repDate,
                representativeLat: nil,
                representativeLng: nil
            ))
        }

        // 3. Time-based event clusters (non-duplicate, non-screenshot photos)
        let unclustered = nonScreenshots.filter { !clusteredIDs.contains($0.localIdentifier) }
        let eventGroups = timeBasedGroups(assets: unclustered, gapHours: 4.0, minSize: 5)
        for group in eventGroups {
            let total = group.reduce(0) { $0 + $1.fileSize }
            let dates = group.compactMap(\.date).sorted()
            let repDate = dates.last
            let repLat = representativeCoordinate(in: group, keyPath: \.latitude)
            let repLng = representativeCoordinate(in: group, keyPath: \.longitude)
            group.forEach { clusteredIDs.insert($0.localIdentifier) }
            clusters.append(RawCluster(
                type: "event",
                label: eventLabel(dates: dates),
                sublabel: "\(group.count) PHOTOS · \(dateRangeLabel(dates)) · \(bytesLabel(total))",
                assetIdentifiers: group.map(\.localIdentifier),
                totalBytes: total,
                representativeDate: repDate,
                representativeLat: repLat,
                representativeLng: repLng
            ))
        }

        // Sort: most recent first, break ties by size
        return clusters.sorted {
            let dateA = $0.representativeDate ?? .distantPast
            let dateB = $1.representativeDate ?? .distantPast
            if abs(dateA.timeIntervalSince(dateB)) > 86400 {   // > 1 day apart → sort by date
                return dateA > dateB
            }
            return $0.totalBytes > $1.totalBytes                // same day → bigger first
        }
    }

    // MARK: - Near-Duplicate Detection

    nonisolated static func nearDuplicateGroups(
        candidates: [ScannedAssetInfo]
    ) -> [[ScannedAssetInfo]] {
        let withFeatures = candidates
            .filter { $0.featureData != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        guard !withFeatures.isEmpty else { return [] }

        // ── Pre-deserialize ALL feature vectors ONCE before the nested loops ──
        // Calling VisionService.deserialize() inside nested loops causes O(N²)
        // NSKeyedUnarchiver overhead. Deserializing upfront is O(N) with a single
        // bridging cost, then the comparison loops are pure Float math.
        var deserialized: [(ScannedAssetInfo, VNFeaturePrintObservation)] = []
        deserialized.reserveCapacity(withFeatures.count)
        for candidate in withFeatures {
            if let fp = candidate.featureData.flatMap({ VisionService.deserialize($0) }) {
                deserialized.append((candidate, fp))
            }
        }

        var groups: [[ScannedAssetInfo]] = []
        var visited = Set<String>()

        for i in 0..<deserialized.count {
            let (a, fpA) = deserialized[i]
            guard !visited.contains(a.localIdentifier) else { continue }

            var group: [ScannedAssetInfo] = [a]
            let windowEnd = (a.date ?? .distantPast).addingTimeInterval(5 * 60)

            for j in (i + 1)..<deserialized.count {
                let (b, fpB) = deserialized[j]
                guard !visited.contains(b.localIdentifier) else { continue }
                guard let dateB = b.date, dateB <= windowEnd else { break }
                if VisionService.distance(fpA, fpB) < 0.5 { group.append(b) }
            }

            if group.count >= 2 {
                group.forEach { visited.insert($0.localIdentifier) }
                groups.append(group)
            }
        }
        return groups
    }

    // MARK: - Time-Based Event Clusters

    nonisolated private static func timeBasedGroups(
        assets: [ScannedAssetInfo],
        gapHours: Double,
        minSize: Int
    ) -> [[ScannedAssetInfo]] {
        let sorted = assets.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard !sorted.isEmpty else { return [] }

        var groups: [[ScannedAssetInfo]] = []
        var current = [sorted[0]]

        for i in 1..<sorted.count {
            let gap = (sorted[i].date ?? .distantPast)
                .timeIntervalSince(sorted[i - 1].date ?? .distantPast)
            if gap > gapHours * 3600 {
                if current.count >= minSize { groups.append(current) }
                current = [sorted[i]]
            } else {
                current.append(sorted[i])
            }
        }
        if current.count >= minSize { groups.append(current) }
        return groups
    }

    // MARK: - Label Helpers

    nonisolated static func duplicateLabel(group: [ScannedAssetInfo]) -> String {
        guard let date = group.compactMap(\.date).max() else { return "NEAR-DUPLICATES" }
        return shortDate(date)
    }

    nonisolated private static func eventLabel(dates: [Date]) -> String {
        guard let first = dates.first else { return "UNTITLED_EVENT" }
        let cal = Calendar.current
        if let last = dates.last, !cal.isDate(first, inSameDayAs: last) {
            // Multi-day: "NOV 2024"
            let f = DateFormatter(); f.dateFormat = "MMM yyyy"
            return f.string(from: first).uppercased()
        }
        // Single day: "SAT 12 NOV"
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: first).uppercased()
    }

    nonisolated private static func dateRangeLabel(_ dates: [Date]) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        let f = DateFormatter(); f.dateFormat = "d MMM"
        let cal = Calendar.current
        if cal.isDate(first, inSameDayAs: last) {
            return f.string(from: first).uppercased()
        }
        return "\(f.string(from: first).uppercased()) – \(f.string(from: last).uppercased())"
    }

    nonisolated private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: date).uppercased()
    }

    nonisolated static func bytesLabel(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return mb >= 1000
            ? String(format: "%.1f GB", mb / 1000)
            : "\(Int(mb)) MB"
    }

    /// Returns the median latitude or longitude for a group of assets.
    nonisolated private static func representativeCoordinate(
        in assets: [ScannedAssetInfo],
        keyPath: KeyPath<ScannedAssetInfo, Double?>
    ) -> Double? {
        let values = assets.compactMap { $0[keyPath: keyPath] }.sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    // MARK: - Day-Based Clustering (primary flow)

    /// Groups non-screenshot photos by calendar day, detects near-duplicates within each day.
    nonisolated static func clusterByDay(
        allMetadata: [AssetMetadata],
        scannedCandidates: [ScannedAssetInfo]
    ) -> [RawCluster] {
        let cal = Calendar.current
        let nonScreenshots = allMetadata.filter { !$0.isScreenshot }
        let candidateMap = Dictionary(uniqueKeysWithValues: scannedCandidates.map { ($0.localIdentifier, $0) })

        // Group metadata by start-of-day
        var byDay: [Date: [AssetMetadata]] = [:]
        for meta in nonScreenshots {
            guard let date = meta.date else { continue }
            byDay[cal.startOfDay(for: date), default: []].append(meta)
        }

        var clusters: [RawCluster] = []
        for (dayStart, dayPhotos) in byDay {
            let dayCandidates = dayPhotos.compactMap { candidateMap[$0.localIdentifier] }
            let dupeSets = nearDuplicateGroups(
                candidates: dayCandidates.filter { $0.featureData != nil }
            )
            let dupeCount = dupeSets.reduce(0) { $0 + $1.count }

            let total = dayPhotos.reduce(0) { $0 + $1.estimatedFileSize }
            let lats = dayPhotos.compactMap(\.latitude).sorted()
            let lngs = dayPhotos.compactMap(\.longitude).sorted()
            let repLat = lats.isEmpty ? nil : lats[lats.count / 2]
            let repLng = lngs.isEmpty ? nil : lngs[lngs.count / 2]

            var parts = ["\(dayPhotos.count) PHOTOS"]
            if dupeCount > 0 { parts.append("\(dupeCount) NEAR-DUPES") }
            parts.append(bytesLabel(total))

            clusters.append(RawCluster(
                type: "day",
                label: dayLabel(dayStart),
                sublabel: parts.joined(separator: " · "),
                assetIdentifiers: dayPhotos.map(\.localIdentifier),
                nearDuplicateSets: dupeSets.map { $0.map(\.localIdentifier) },
                totalBytes: total,
                representativeDate: dayStart,
                representativeLat: repLat,
                representativeLng: repLng
            ))
        }

        return clusters.sorted {
            ($0.representativeDate ?? .distantPast) > ($1.representativeDate ?? .distantPast)
        }
    }

    /// Builds initial day groups from metadata only (no Vision — shown immediately after enumeration).
    nonisolated static func buildInitialDayGroups(from metadata: [AssetMetadata]) -> [RawCluster] {
        let cal = Calendar.current
        let nonScreenshots = metadata.filter { !$0.isScreenshot }

        var byDay: [Date: [AssetMetadata]] = [:]
        for meta in nonScreenshots {
            guard let date = meta.date else { continue }
            byDay[cal.startOfDay(for: date), default: []].append(meta)
        }

        return byDay.map { (dayStart, photos) in
            let total = photos.reduce(0) { $0 + $1.estimatedFileSize }
            let lats = photos.compactMap(\.latitude).sorted()
            let lngs = photos.compactMap(\.longitude).sorted()
            return RawCluster(
                type: "day",
                label: dayLabel(dayStart),
                sublabel: "\(photos.count) PHOTOS · \(bytesLabel(total))",
                assetIdentifiers: photos.map(\.localIdentifier),
                totalBytes: total,
                representativeDate: dayStart,
                representativeLat: lats.isEmpty ? nil : lats[lats.count / 2],
                representativeLng: lngs.isEmpty ? nil : lngs[lngs.count / 2]
            )
        }
        .sorted { ($0.representativeDate ?? .distantPast) > ($1.representativeDate ?? .distantPast) }
    }

    nonisolated private static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: date).uppercased()
    }
}
