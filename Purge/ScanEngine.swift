import SwiftUI
import Photos
import Vision
import SwiftData

// MARK: - Scan Phase

enum ScanPhase: Equatable {
    case idle
    case rescanning
    case requestingPermission
    case enumerating
    case analysing(current: Int, total: Int)
    case clustering
    case complete
    case permissionDenied
    case error(String)
}

    // MARK: - Scan Engine

@MainActor
@Observable
final class ScanEngine {

    var phase: ScanPhase = .idle
    var dayGroups: [DayGroup] = []
    var photoCount: Int = 0

    // Dev Mode Stats
    var scanStartTime: Date?
    var currentPPS: Double = 0.0

    // ── DEBUG FLAGS ──────────────────────────────────────────────────────────
    // Set to a non-nil value to cap the number of photos processed.
    private let DEBUG_PHOTO_CAP: Int? = nil

    // MARK: - PHCachingImageManager (pre-warm iCloud photos before Vision analysis)

    private let cacheManager = PHCachingImageManager()

    private func prefetchThumbnails(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        let targetSize = CGSize(width: 256, height: 256)
        cacheManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opts
        )
    }

    private func stopPrefetching(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let opts = PHImageRequestOptions()
        let targetSize = CGSize(width: 256, height: 256)
        cacheManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opts
        )
    }
    
    var totalNearDuplicateCount: Int { dayGroups.reduce(0) { $0 + $1.nearDuplicateCount } }
    var daysWithDuplicates: Int      { dayGroups.filter { $0.nearDuplicateCount > 0 }.count }

    // MARK: - Trash Service (Centralized Deletion API)

    /// Tracks identifiers currently being deleted. Views can observe this to show progress.
    /// Set to `nil` when no deletion is in progress.
    var pendingDeletion: Set<String>? {
        didSet {
            print("[PURGE-TRASH] pendingDeletion changed: \(oldValue?.count ?? 0) -> \(pendingDeletion?.count ?? 0)")
        }
    }

    /// Tracks the deletion count for UI progress indicators.
    var deletionCount: Int { pendingDeletion?.count ?? 0 }

    /// Tracks whether a deletion is currently in progress.
    var isDeleting: Bool { pendingDeletion != nil }

    /// Phase 1: Deletes assets from the Photos library. Returns true if the user confirmed.
    /// Does NOT mutate in-memory state — call `cleanupAfterDeletion` separately.
    func performLibraryDeletion(identifiers: Set<String>) async -> Bool {
        print("[PURGE-TRASH] performLibraryDeletion START: \(identifiers.count) items")
        guard !identifiers.isEmpty else {
            print("[PURGE-TRASH] performLibraryDeletion SKIP: empty identifiers")
            return false
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(identifiers), options: nil)
        print("[PURGE-TRASH] performLibraryDeletion: found \(fetchResult.count) assets in Photos library")
        guard fetchResult.count > 0 else { return false }

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }

        // Explicitly dispatch to a background queue to avoid blocking the main thread
        // and prevent potential deadlocks with the Photos library.
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // Re-fetch assets inside the closure so they are captured as Sendable PHObject
                // (PHAsset is Sendable when fetched fresh from the library).
                let localIds = assets.map { $0.localIdentifier }
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", localIds)
                let freshFetch = PHAsset.fetchAssets(with: fetchOptions)
                var freshAssets: [PHAsset] = []
                freshFetch.enumerateObjects { asset, _, _ in freshAssets.append(asset) }
                let nsAssets = NSArray(array: freshAssets)

                print("[PURGE-TRASH] performLibraryDeletion: executing PHPhotoLibrary.performChanges on background queue")
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(nsAssets)
                } completionHandler: { ok, error in
                    print("[PURGE-TRASH] performLibraryDeletion PHPhotoLibrary.performChanges completed: success=\(ok), error=\(error?.localizedDescription ?? "nil")")
                    cont.resume(returning: ok)
                }
            }
        }

        print("[PURGE-TRASH] performLibraryDeletion END: success=\(success)")
        return success
    }

    /// Phase 2: Update in-memory dayGroups and prune SwiftData after deletion.
    /// Call this AFTER the presenting view has dismissed to avoid navigation crashes.
    func cleanupAfterDeletion(identifiers: Set<String>, context: ModelContext) {
        print("[PURGE-TRASH] cleanupAfterDeletion START: \(identifiers.count) items, dayGroups before=\(dayGroups.count)")
        dayGroups = dayGroups.compactMap { day in
            let remaining = day.photos.filter { !identifiers.contains($0.localIdentifier ?? "") }
            guard !remaining.isEmpty else { return nil }
            let prunedSets = day.nearDuplicateSets
                .map { $0.filter { !identifiers.contains($0) } }
                .filter { !$0.isEmpty }
            return DayGroup(
                id: day.id,
                date: day.date,
                location: day.location,
                representativeLat: day.representativeLat,
                representativeLng: day.representativeLng,
                photos: remaining,
                nearDuplicateSets: prunedSets
            )
        }

        print("[PURGE-TRASH] cleanupAfterDeletion: dayGroups after=\(dayGroups.count)")
        pruneSwiftData(identifiers: identifiers, context: context)
        print("[PURGE-TRASH] cleanupAfterDeletion END")
    }

    /// Atomically trash items: sets pendingDeletion, performs library deletion,
    /// dismisses via callback, then cleans up in-memory state.
    /// Views should call this instead of the raw two-phase methods.
    /// - Parameters:
    ///   - identifiers: Set of photo localIdentifiers to trash
    ///   - context: SwiftData ModelContext for pruning
    ///   - dismissCallback: Closure to dismiss the presenting view (called before cleanup to avoid NavigationStack crash)
    func trashItems(
        identifiers: Set<String>,
        context: ModelContext,
        dismissCallback: @escaping () -> Void
    ) {
        print("[PURGE-TRASH] trashItems START: \(identifiers.count) items")
        guard !identifiers.isEmpty, pendingDeletion == nil else {
            print("[PURGE-TRASH] trashItems SKIP: identifiers=\(identifiers.isEmpty ? "empty" : "not empty"), pendingDeletion=\(pendingDeletion != nil ? "already set" : "nil")")
            return
        }
        pendingDeletion = identifiers
        print("[PURGE-TRASH] trashItems: pendingDeletion set to \(identifiers.count) items")

        Task {
            let success = await performLibraryDeletion(identifiers: identifiers)

            guard success else {
                print("[PURGE-TRASH] trashItems: performLibraryDeletion FAILED, clearing pendingDeletion")
                await MainActor.run {
                    pendingDeletion = nil
                }
                return
            }

            // Dismiss the presenting view FIRST, then mutate state.
            // All views now read dynamically from scanEngine.dayGroups via Environment,
            // so there's no risk of stale bindings even without a delay.
            print("[PURGE-TRASH] trashItems: calling dismissCallback()")
            await MainActor.run {
                dismissCallback()
            }
            print("[PURGE-TRASH] trashItems: dismissCallback() completed, calling cleanupAfterDeletion")

            await MainActor.run {
                print("[PURGE-TRASH] trashItems: in MainActor, calling cleanupAfterDeletion")
                cleanupAfterDeletion(identifiers: identifiers, context: context)
                pendingDeletion = nil
                print("[PURGE-TRASH] trashItems END: cleanupAfterDeletion done, pendingDeletion cleared")
            }
        }
    }

    /// Cancel any pending deletion (e.g., user backed out).
    /// Returns true if there was a pending deletion to cancel.
    @discardableResult
    func cancelDeletion() -> Bool {
        guard pendingDeletion != nil else { return false }
        pendingDeletion = nil
        return true
    }

    // MARK: - Prune SwiftData (internal helper)

    private func pruneSwiftData(identifiers: Set<String>, context: ModelContext) {
        print("[PURGE-TRASH] pruneSwiftData START: \(identifiers.count) identifiers")
        var deletedAssetRecords = 0
        var deletedClusters = 0
        var updatedClusters = 0
        
        if let records = try? context.fetch(FetchDescriptor<AssetRecord>()) {
            for record in records where identifiers.contains(record.localIdentifier) {
                context.delete(record)
                deletedAssetRecords += 1
            }
        }
        if let clusters = try? context.fetch(FetchDescriptor<ClusterRecord>()) {
            for cluster in clusters {
                let pruned = cluster.assetIdentifiers.filter { !identifiers.contains($0) }
                if pruned.isEmpty {
                    context.delete(cluster)
                    deletedClusters += 1
                } else if pruned.count != cluster.assetIdentifiers.count {
                    cluster.assetIdentifiers = pruned
                    cluster.assetCount = pruned.count
                    updatedClusters += 1
                }
            }
        }
        try? context.save()
        print("[PURGE-TRASH] pruneSwiftData: deletedAssetRecords=\(deletedAssetRecords), deletedClusters=\(deletedClusters), updatedClusters=\(updatedClusters)")
    }

    // MARK: - Load Existing Scan

    func loadExistingClusters(context: ModelContext) {
        do {
            var desc = FetchDescriptor<ClusterRecord>()
            desc.sortBy = [SortDescriptor(\.representativeDate, order: .reverse)]
            let records = try context.fetch(desc)

            guard !records.isEmpty else { return }

            let assetDesc = FetchDescriptor<AssetRecord>()
            let allAssets = try context.fetch(assetDesc)
            let assetMap  = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.localIdentifier, $0) })

            photoCount = allAssets.filter { !$0.isScreenshot }.count

            let validGroups = records
                .filter { $0.clusterType == "day" }
                .compactMap { buildDayGroup(from: $0, assetMap: assetMap) }
                .filter { !$0.photos.isEmpty }

            dayGroups = validGroups
            if !dayGroups.isEmpty {
                phase = .complete
                NotificationService.checkAndScheduleNotifications(for: dayGroups)
            }
        } catch {
            // Entity not found or schema mismatch — clear stale data and let the next scan rebuild cleanly.
            try? context.delete(model: ClusterRecord.self)
            try? context.delete(model: AssetRecord.self)
            try? context.save()
        }
    }

    // MARK: - Start (incremental) / Rescan (full wipe)

    func startScan(context: ModelContext) {
        guard phase == .idle || phase == .permissionDenied else { return }
        Task { await performScan(context: context, incremental: true) }
    }

    func rescan(context: ModelContext) {
        Task {
            dayGroups = []; photoCount = 0; phase = .rescanning
            await performScan(context: context, incremental: false)
        }
    }

    // MARK: - Main Pipeline

    private func performScan(context: ModelContext, incremental: Bool) async {
        // ── 1. Permission ──────────────────────────────────────────────────
        phase = .requestingPermission
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            phase = .permissionDenied; return
        }

        // ── 2. Load existing data (incremental only) ───────────────────────
        await MainActor.run {
            self.scanStartTime = Date()
            self.currentPPS = 0.0
        }
        
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Feature vectors stored for each asset (avoids re-running Vision)
        var existingFeatureMap: [String: Data] = [:]
        // Past days that are fully scanned — their photos won't change
        var alreadyScannedDays: Set<Date> = []

        if incremental {
            let assetRecords = (try? context.fetch(FetchDescriptor<AssetRecord>())) ?? []
            for r in assetRecords {
                if let d = r.featureVectorData { existingFeatureMap[r.localIdentifier] = d }
            }

            let clusterRecords = (try? context.fetch(FetchDescriptor<ClusterRecord>())) ?? []
            for r in clusterRecords where r.clusterType == "day" {
                if let date = r.representativeDate {
                    let dayStart = cal.startOfDay(for: date)
                    if dayStart < today { alreadyScannedDays.insert(dayStart) }
                }
            }
        }

        // ── 3. Pass 1 — Fast metadata enumeration (oldest → newest) ───────
        await MainActor.run { phase = .enumerating }
        let allMetadata = await Task.detached(priority: .userInitiated) {
            let opts = PHFetchOptions()
            // Oldest first — we process incrementally and past days are skipped
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: .image, options: opts)

            var metadata: [AssetMetadata] = []
            metadata.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                metadata.append(AssetMetadata(
                    localIdentifier: asset.localIdentifier,
                    date: asset.creationDate,
                    latitude:  asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude,
                    pixelWidth:  asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    estimatedFileSize: Self.estimateFileSize(asset)
                ))
            }
            return metadata
        }.value

        // ── DEBUG: cap photo count to DEBUG_PHOTO_CAP ──────────────────────────
        var cappedAllMetadata = allMetadata
        if let cap = DEBUG_PHOTO_CAP, cappedAllMetadata.count > cap {
            cappedAllMetadata = Array(cappedAllMetadata.prefix(cap))
        }

        photoCount = cappedAllMetadata.filter { !$0.isScreenshot }.count
        if cappedAllMetadata.isEmpty { phase = .complete; return }

        let initialRaw = await Task.detached(priority: .utility) {
            ClusteringEngine.buildInitialDayGroups(from: cappedAllMetadata)
        }.value
        let metaMap = Dictionary(uniqueKeysWithValues: cappedAllMetadata.map { ($0.localIdentifier, $0) })
        dayGroups = initialRaw.compactMap { buildDayGroupFromRawCluster($0, metaMap: metaMap) }

        let preloadedCandidates: [ScannedAssetInfo] = cappedAllMetadata.compactMap { meta in
            guard !meta.isScreenshot, let date = meta.date else { return nil }
            let dayStart = cal.startOfDay(for: date)
            guard alreadyScannedDays.contains(dayStart),
                  let featureData = existingFeatureMap[meta.localIdentifier]
            else { return nil }
            return ScannedAssetInfo(
                localIdentifier: meta.localIdentifier,
                date: meta.date,
                latitude: meta.latitude,
                longitude: meta.longitude,
                fileSize: meta.estimatedFileSize,
                isScreenshot: meta.isScreenshot,
                featureData: featureData,
                pixelWidth: meta.pixelWidth,
                pixelHeight: meta.pixelHeight
            )
        }

        let unscannedMetadata = cappedAllMetadata.filter { meta in
            guard !meta.isScreenshot, let date = meta.date else { return !meta.isScreenshot }
            let dayStart = cal.startOfDay(for: date)
            return !alreadyScannedDays.contains(dayStart)
        }

        let candidateIDs = await Task.detached(priority: .utility) {
            ClusteringEngine.temporalCandidates(from: unscannedMetadata)
        }.value

        let candidatesMeta = unscannedMetadata.filter { candidateIDs.contains($0.localIdentifier) }
        let candidateTotal = candidatesMeta.count
        await MainActor.run { phase = .analysing(current: 0, total: candidateTotal) }

        let newCandidates = await processCandidates(
            candidatesMeta,
            totalCount: candidateTotal,
            allMetadata: cappedAllMetadata,
            baselineCandidates: preloadedCandidates
        )

        let allScanned = preloadedCandidates + newCandidates

        await MainActor.run { phase = .clustering }
        let rawClusters = await Task.detached(priority: .utility) {
            ClusteringEngine.clusterByDay(allMetadata: cappedAllMetadata, scannedCandidates: allScanned)
        }.value

        try? context.delete(model: ClusterRecord.self)
        try? context.delete(model: AssetRecord.self)

        let newFeatureMap = Dictionary(
            uniqueKeysWithValues: newCandidates.compactMap { c -> (String, Data)? in
                guard let d = c.featureData else { return nil }
                return (c.localIdentifier, d)
            }
        )
        let mergedFeatureMap = existingFeatureMap.merging(newFeatureMap) { _, new in new }

        let metadataLookup = Dictionary(uniqueKeysWithValues: cappedAllMetadata.map { ($0.localIdentifier, $0) })
        dayGroups = rawClusters
            .filter { $0.type == "day" }
            .compactMap { buildDayGroupFromRawCluster($0, metaMap: metadataLookup) }

        // Persist to SwiftData (inserts only — no fetch+rebuild since we already built dayGroups).
        // Saves happen on the main actor where context lives. Inserts are staged and flushed
        // with a single save() call. This is fast since we removed the redundant fetch.
        saveToSwiftData(
            allMetadata: allMetadata,
            rawClusters: rawClusters,
            featureMap: mergedFeatureMap,
            context: context
        )

        await MainActor.run {
            phase = .complete
            NotificationService.checkAndScheduleNotifications(for: dayGroups)
        }

        // ── 8. Background geocoding ────────────────────────────────────────
        Task { await geocodeDayGroups() }
    }

    // MARK: - Candidate Processing (off-main-actor batches)

    private func processCandidates(
        _ candidates: [AssetMetadata],
        totalCount: Int,
        allMetadata: [AssetMetadata],
        baselineCandidates: [ScannedAssetInfo] = []
    ) async -> [ScannedAssetInfo] {
        guard !candidates.isEmpty else { return [] }

        #if targetEnvironment(simulator)
        let batchSize = 10
        #else
        let batchSize = 40
        #endif

        var results: [ScannedAssetInfo] = []
        results.reserveCapacity(candidates.count)

        let batches = stride(from: 0, to: candidates.count, by: batchSize).map { start in
            Array(candidates[start..<min(start + batchSize, candidates.count)])
        }

        // Pre-resolve ALL PHAssets for all batches upfront — PHAsset.fetchAssets is O(1) in-memory.
        let batchPHAssets: [[PHAsset]] = await Task.detached(priority: .utility) {
            batches.map { batch in
                let ids = batch.map(\.localIdentifier)
                let r = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var assets: [PHAsset] = []
                r.enumerateObjects { a, _, _ in assets.append(a) }
                return assets
            }
        }.value


        var previousPrefetchAssets: [PHAsset] = []

        for (batchIdx, batch) in batches.enumerated() {
            let currentAssets = batchPHAssets[batchIdx]

            // ── Pre-fetch NEXT batch while processing CURRENT batch ──
            // This overlaps iCloud downloads (network) with Vision CPU work.
            if batchIdx + 1 < batchPHAssets.count {
                prefetchThumbnails(for: batchPHAssets[batchIdx + 1])
            }
            stopPrefetching(for: previousPrefetchAssets)
            previousPrefetchAssets = currentAssets

            let batchResults: [ScannedAssetInfo] = await Task.detached(priority: .userInitiated) {
                var out: [ScannedAssetInfo] = []
                for asset in currentAssets {
                    guard let meta = batch.first(where: { $0.localIdentifier == asset.localIdentifier })
                    else { continue }

                    #if targetEnvironment(simulator)
                    let fpData = Data(repeating: 0, count: 128)
                    out.append(ScannedAssetInfo(
                        localIdentifier: asset.localIdentifier,
                        date: meta.date,
                        latitude: meta.latitude,
                        longitude: meta.longitude,
                        fileSize: meta.estimatedFileSize,
                        isScreenshot: meta.isScreenshot,
                        featureData: fpData,
                        pixelWidth: meta.pixelWidth,
                        pixelHeight: meta.pixelHeight
                    ))
                    #else
                    guard let thumb = await ScanEngine.asyncThumbnail(for: asset) else { continue }

                    let fpData: Data? = autoreleasepool {
                        guard let obs = try? VisionService.featurePrint(for: thumb) else { return nil }
                        return try? VisionService.serialize(obs)
                    }

                    out.append(ScannedAssetInfo(
                        localIdentifier: asset.localIdentifier,
                        date: meta.date,
                        latitude: meta.latitude,
                        longitude: meta.longitude,
                        fileSize: meta.estimatedFileSize,
                        isScreenshot: meta.isScreenshot,
                        featureData: fpData,
                        pixelWidth: meta.pixelWidth,
                        pixelHeight: meta.pixelHeight
                    ))
                    #endif
                }
                return out
            }.value

            results.append(contentsOf: batchResults)

            let processed = min((batchIdx + 1) * batchSize, totalCount)
            await MainActor.run {
                phase = .analysing(current: processed, total: totalCount)
                if let start = scanStartTime {
                    let elapsed = Date().timeIntervalSince(start)
                    currentPPS = elapsed > 0 ? Double(processed) / elapsed : 0.0
                }
            }

            // We no longer call updateDayGroupsIncrementally() here.
            // Re-clustering 20,000 photos every 40 images causes an O(N^2) CPU spiral
            // that locks up the device and spikes RAM to 3GB+.
            // The UI hides dayGroups during scanning anyway, so we just wait for Step 6.

            await Task.yield()
        }

        stopPrefetching(for: previousPrefetchAssets)
        return results
    }

    // MARK: - Persist

    private func saveToSwiftData(
        allMetadata: [AssetMetadata],
        rawClusters: [RawCluster],
        featureMap: [String: Data],
        context: ModelContext
    ) {
        let clusterAssignment: [String: String] = {
            var m: [String: String] = [:]
            for raw in rawClusters {
                let id = UUID().uuidString
                raw.assetIdentifiers.forEach { m[$0] = id }
            }
            return m
        }()

        let clusterRecords: [ClusterRecord] = rawClusters.map { raw in
            let id = UUID().uuidString
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
            if let lat = meta.latitude  { record.latitude  = lat }
            if let lng = meta.longitude { record.longitude = lng }
            return record
        }

        for record in clusterRecords { context.insert(record) }
        for record in assetRecords { context.insert(record) }
        try? context.save()
    }

    // MARK: - Geocoding (background, rate-limited)

    private func geocodeDayGroups() async {
        // TODO: Replace CLGeocoder (deprecated iOS 26) with MKLocalSearch reverse geocoding.
        // Requires propagating repLat/repLng coordinates through to DayGroup first.
    }

    // MARK: - Day Group Builders

    private func buildDayGroupFromRawCluster(_ raw: RawCluster, metaMap: [String: AssetMetadata]) -> DayGroup? {
        guard !raw.assetIdentifiers.isEmpty,
              let date = raw.representativeDate else { return nil }
        let photos: [DummyPhoto] = raw.assetIdentifiers.compactMap { id in
            guard let meta = metaMap[id] else { return nil }
            return DummyPhoto(
                localIdentifier: id,
                color: Color(hex: "1E1E1E"),
                label: "PHOTO",
                date: meta.date.map { shortDate($0) } ?? "",
                sizeMB: Int(meta.estimatedFileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            date: date,
            location: raw.label,
            representativeLat: raw.representativeLat,
            representativeLng: raw.representativeLng,
            photos: photos,
            nearDuplicateSets: raw.nearDuplicateSets
        )
    }

    private func buildDayGroupFromRecord(_ record: ClusterRecord, metaMap: [String: AssetMetadata]) -> DayGroup? {
        guard !record.assetIdentifiers.isEmpty,
              let date = record.representativeDate else { return nil }
        let photos: [DummyPhoto] = record.assetIdentifiers.compactMap { id in
            guard let meta = metaMap[id] else { return nil }
            return DummyPhoto(
                localIdentifier: id,
                color: Color(hex: "1E1E1E"),
                label: "PHOTO",
                date: meta.date.map { shortDate($0) } ?? "",
                sizeMB: Int(meta.estimatedFileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            date: date,
            location: record.label,
            representativeLat: record.representativeLat,
            representativeLng: record.representativeLng,
            photos: photos,
            nearDuplicateSets: record.nearDuplicateSets
        )
    }

    private func buildDayGroup(from record: ClusterRecord, assetMap: [String: AssetRecord]) -> DayGroup? {
        guard !record.assetIdentifiers.isEmpty,
              let date = record.representativeDate else { return nil }
        let photos: [DummyPhoto] = record.assetIdentifiers.compactMap { id in
            guard let asset = assetMap[id] else { return nil }
            return DummyPhoto(
                localIdentifier: id,
                color: Color(hex: "1E1E1E"),
                label: "PHOTO",
                date: asset.creationDate.map { shortDate($0) } ?? "",
                sizeMB: Int(asset.fileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            date: date,
            location: record.label,
            representativeLat: record.representativeLat,
            representativeLng: record.representativeLng,
            photos: photos,
            nearDuplicateSets: record.nearDuplicateSets
        )
    }

    // MARK: - Static Helpers

    nonisolated private static func asyncThumbnail(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            
            // To ensure the continuation is only called once, use a thread-safe flag
            let flag = SendableBox(false)
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 256, height: 256),
                contentMode: .aspectFill,
                options: options
            ) { img, info in
                if flag.tryConsume() {
                    continuation.resume(returning: img)
                }
            }
        }
    }
    
    // Simple helper class to safely mutate boolean state across closures
    private final class SendableBox: @unchecked Sendable {
        private nonisolated(unsafe) var _value: Bool
        private let lock = NSLock()
        
        nonisolated init(_ value: Bool) { self._value = value }
        
        nonisolated func tryConsume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if !_value {
                _value = true
                return true
            }
            return false
        }
    }

    nonisolated private static func estimateFileSize(_ asset: PHAsset) -> Int64 {
        // Fetching PHAssetResource is synchronously blocking and causes massive thermal throttling / UI freezes
        // when looping over 10,000+ images. We use a purely mathematical estimation based on resolution.
        // A standard iPhone HEIC photo is roughly width * height * 0.4 bytes.
        let bytes = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return Int64(Double(bytes) * 0.4)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: date).uppercased()
    }
}
