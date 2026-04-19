import SwiftUI
import Photos
import Vision
import SwiftData
import UIKit

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
//
// ──────────────────────────────────────────────────────────────────────────
// SPEC: Scan engine high-level behaviour (locked-in across iterations)
// ──────────────────────────────────────────────────────────────────────────
// 1. Scans are ALWAYS incremental + silent by default. The UI must remain
//    fully usable (scrolling, taps, day overlay) while a scan runs.
// 2. autoScanIfNeeded is called on app launch AND when re-entering the
//    foreground. It MUST be a true no-op when the library is unchanged
//    (see needsScan for the freshness contract).
// 3. While a scan is running:
//      • dayGroups stay populated (cached data + new days merged in).
//      • Per-day nearDuplicateSets carried over from the previous scan
//        keep the rose duplicate badges visible until fresh results land.
//      • photoCount is only updated upward / to a non-zero value.
//      • A slim background banner surfaces progress; full-screen takeover
//        is reserved for explicit user-initiated full rescans.
// 4. Scan throughput is intentionally throttled during background scans
//    (utility QoS + per-batch sleep) to preserve scrolling FPS. The user
//    can scroll the entire grid at 60/120 fps while the scan crunches.
// 5. UI-facing @Observable state changes are throttled (≈5 Hz) so that
//    @Observable subscribers don't get spammed mid-batch.
// ──────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ScanEngine {

    var phase: ScanPhase = .idle
    var dayGroups: [DayGroup] = []
    var photoCount: Int = 0

    /// True when the current scan is incremental and should NOT take over the UI.
    /// Views read this to decide whether to show a small status banner instead of a
    /// full-screen progress takeover, and to keep scrolling/interaction enabled.
    /// SPEC: this MUST be true for every auto-triggered scan, and only false
    /// for explicit user-initiated full rescans launched from the rescan button.
    var isBackgroundScan: Bool = false

    /// Convenience: the (current, total) tuple for the active scan, or nil when idle.
    /// Useful for inline banners that display "1 234 / 12 000".
    var liveProgress: (current: Int, total: Int)? {
        if case .analysing(let c, let t) = phase { return (c, t) }
        return nil
    }

    /// True while a scan is actively running (any phase besides idle/complete/error).
    var isScanning: Bool {
        switch phase {
        case .rescanning, .requestingPermission, .enumerating, .analysing, .clustering:
            return true
        default:
            return false
        }
    }

    // Dev Mode Stats
    var scanStartTime: Date?
    var currentPPS: Double = 0.0

    // MARK: - Background task (extends runtime when app is backgrounded)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PurgeScan") { [weak self] in
            // iOS is about to expire our background time — release the task.
            // Persisted feature data per-batch means the next launch resumes cleanly.
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

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
    
    private func updateMemorySaved(bytes: Int64, photoCount: Int, context: ModelContext) {
        Task {
            let container = context.container
            let persistence = PersistenceManager(modelContainer: container)
            try? await persistence.updateMemorySaved(bytes: bytes, photoCount: photoCount)
        }
    }

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
        let assetIds = assets.map { $0.localIdentifier }
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // Re-fetch assets inside the closure so they are captured as Sendable PHObject
                // (PHAsset is Sendable when fetched fresh from the library).
                let localIds = assetIds
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

    private func calculateBytesSaved(identifiers: Set<String>, context: ModelContext) -> Int64 {
        var totalBytes: Int64 = 0
        let idArray = Array(identifiers)
        let chunkSize = 500
        
        for i in stride(from: 0, to: idArray.count, by: chunkSize) {
            let chunk = Array(idArray[i..<min(i + chunkSize, idArray.count)])
            let predicate = #Predicate<AssetRecord> { chunk.contains($0.localIdentifier) }
            let desc = FetchDescriptor<AssetRecord>(predicate: predicate)
            if let records = try? context.fetch(desc) {
                for record in records {
                    totalBytes += Int64(record.fileSize)
                }
            }
        }
        return totalBytes
    }

    /// Phase 2: Update in-memory dayGroups and prune SwiftData after deletion.
    /// Call this AFTER the presenting view has dismissed to avoid navigation crashes.
    func cleanupAfterDeletion(identifiers: Set<String>, context: ModelContext) {
        print("[PURGE-TRASH] cleanupAfterDeletion START: \(identifiers.count) items, dayGroups before=\(dayGroups.count)")
        
        // Calculate bytes saved
        let bytesSaved = calculateBytesSaved(identifiers: identifiers, context: context)
        updateMemorySaved(bytes: bytesSaved, photoCount: identifiers.count, context: context)
        AnalyticsService.logPhotosRemoved(count: identifiers.count, bytesSaved: bytesSaved)
        
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
        
        let idArray = Array(identifiers)
        let chunkSize = 500
        
        for i in stride(from: 0, to: idArray.count, by: chunkSize) {
            let chunk = Array(idArray[i..<min(i + chunkSize, idArray.count)])
            let predicate = #Predicate<AssetRecord> { chunk.contains($0.localIdentifier) }
            let desc = FetchDescriptor<AssetRecord>(predicate: predicate)
            if let records = try? context.fetch(desc) {
                for record in records {
                    context.delete(record)
                    deletedAssetRecords += 1
                }
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

            let dayRecords = records.filter { $0.clusterType == "day" }

            let validGroups = dayRecords
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

    // MARK: - Start / Rescan / Auto

    /// User-initiated scan. Defaults to silent: the UI stays usable and just
    /// surfaces a small inline banner. Pass `silent: false` to force the
    /// full-screen takeover (used for the legacy first-scan flow).
    func startScan(context: ModelContext, silent: Bool = true) {
        guard !isScanning else { return }
        isBackgroundScan = silent
        Task { await performScan(context: context, incremental: true) }
    }

    /// User-initiated full rescan. Wipes everything and re-analyses from scratch.
    /// Always shown in the foreground takeover so the user knows the heavy work
    /// is intentional.
    func rescan(context: ModelContext) {
        guard !isScanning else { return }
        Task {
            isBackgroundScan = false
            dayGroups = []; photoCount = 0; phase = .rescanning
            await performScan(context: context, incremental: false)
        }
    }

    /// Called on app launch / foreground. Quietly runs an incremental scan if there
    /// is anything new to process, while leaving the UI fully usable. No-ops when
    /// a scan is already in flight or the library hasn't changed since the last scan.
    ///
    /// SPEC: this MUST exit without touching `phase` or `dayGroups` if `needsScan`
    /// returns false. The user opening the app on an unchanged library should see
    /// no banner, no spinner, and no flicker.
    func autoScanIfNeeded(context: ModelContext) {
        guard !isScanning else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .denied else { return }

        Task {
            guard await needsScan(context: context) else { return }
            isBackgroundScan = true
            await performScan(context: context, incremental: true)
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // SPEC: Auto-scan trigger semantics (locked-in requirements)
    // ──────────────────────────────────────────────────────────────────────
    // 1. autoScanIfNeeded MUST be a no-op when the library hasn't changed
    //    since the last successful scan. Opening the app on an unchanged
    //    library MUST NOT spin up Vision / SwiftData / PhotoKit work.
    // 2. The freshness check is based on the maximum creationDate of any
    //    AssetRecord we've seen — NOT on representativeDate (which is
    //    start-of-day for day clusters and would falsely trigger any time
    //    the user has at least one photo from today).
    // 3. When AssetRecord is empty but photos exist in PhotoKit, this is
    //    treated as a first-launch and a scan is triggered.
    // 4. When PhotoKit holds fewer images than AssetRecord (deletions made
    //    outside Purge), a scan is triggered so we can prune stale rows.
    // 5. PHFetchOptions.fetchLimit = 1 keeps this O(1) in practice.
    // ──────────────────────────────────────────────────────────────────────
    private func needsScan(context: ModelContext) async -> Bool {
        let assetRecords = (try? context.fetch(FetchDescriptor<AssetRecord>())) ?? []

        // First-ever launch: scan iff there's anything in the library to scan.
        if assetRecords.isEmpty {
            let any = PHAsset.fetchAssets(with: .image, options: nil)
            return any.count > 0
        }

        // Newest creationDate we've already persisted. Using the actual
        // creationDate (not start-of-day) keeps this stable across same-day
        // launches when nothing new has been shot.
        let lastSeenDate: Date = assetRecords
            .compactMap { $0.creationDate }
            .max() ?? .distantPast

        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "creationDate > %@",
            lastSeenDate as NSDate
        )
        opts.fetchLimit = 1
        let newer = PHAsset.fetchAssets(with: .image, options: opts)
        if newer.count > 0 { return true }

        // Detect deletions made outside Purge: if the live library is smaller
        // than our recorded asset table, we should re-scan so the dayGroups
        // reflect the new reality.
        let liveCount = PHAsset.fetchAssets(with: .image, options: nil).count
        if liveCount < assetRecords.count { return true }

        return false
    }

    // MARK: - Main Pipeline
    //
    // ──────────────────────────────────────────────────────────────────────
    // SPEC: UI behaviour during a background / incremental scan
    // ──────────────────────────────────────────────────────────────────────
    // The scan must not "blank out" what the user already sees:
    //   • Cached dayGroups loaded by loadExistingClusters MUST stay visible
    //     for the entire duration of the scan; no full wipe / re-set.
    //   • Per-day nearDuplicateSets from the previous scan MUST be carried
    //     over, so the rose-coloured "near-duplicates" pill and per-card
    //     badges keep showing (with last known counts) while we recompute.
    //   • New days (today / yesterday) that we discover before Vision runs
    //     are merged into the existing list — never overwriting older days.
    //   • photoCount is only updated to a non-zero value, so the hero
    //     header doesn't flash "0 photos waiting" mid-scan.
    //   • Phase updates to .analysing(current:total:) are throttled so we
    //     don't spam SwiftUI with re-renders while Vision crunches batches.
    // ──────────────────────────────────────────────────────────────────────
    private func performScan(context: ModelContext, incremental: Bool) async {
        beginBackgroundTask()
        defer {
            endBackgroundTask()
            isBackgroundScan = false
        }

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
        // Cached near-duplicate sets per day, keyed by start-of-day. Used to
        // keep the dup badges visible on cards while the scan is running.
        var cachedDupSetsByDay: [Date: [[String]]] = [:]

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
                    let sets = r.nearDuplicateSets
                    if !sets.isEmpty { cachedDupSetsByDay[dayStart] = sets }
                }
            }
        }

        // ── 3. Pass 1 — Fast metadata enumeration (oldest → newest) ───────
        await MainActor.run { phase = .enumerating }
        let allMetadata = await Task.detached(priority: .utility) {
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

        // SPEC: never overwrite a non-zero photoCount with 0; that would make
        // the header pill flash blank during the brief moment between
        // enumeration and clustering.
        let newPhotoCount = cappedAllMetadata.filter { !$0.isScreenshot }.count
        if newPhotoCount > 0 || photoCount == 0 {
            photoCount = newPhotoCount
        }
        if cappedAllMetadata.isEmpty { phase = .complete; return }

        let initialRaw = await Task.detached(priority: .utility) {
            ClusteringEngine.buildInitialDayGroups(from: cappedAllMetadata)
        }.value
        let metaMap = Dictionary(uniqueKeysWithValues: cappedAllMetadata.map { ($0.localIdentifier, $0) })

        // Build "fresh" day groups but inject the previously-known
        // nearDuplicateSets for each day so the duplicate badges stay
        // visible on the cards while Vision re-runs.
        let initialDayGroups: [DayGroup] = initialRaw.compactMap { raw in
            guard let base = buildDayGroupFromRawCluster(raw, metaMap: metaMap),
                  let repDate = raw.representativeDate
            else { return nil }
            let dayStart = cal.startOfDay(for: repDate)
            let cachedSets = cachedDupSetsByDay[dayStart] ?? []
            return DayGroup(
                id: base.id,
                date: base.date,
                location: base.location,
                representativeLat: base.representativeLat,
                representativeLng: base.representativeLng,
                photos: base.photos,
                nearDuplicateSets: cachedSets
            )
        }

        // SPEC: never wipe the visible dayGroups during an incremental scan.
        //   - First-ever scan (cached dayGroups empty): assign initialDayGroups
        //     so the user sees the photo grid immediately.
        //   - Subsequent scans: keep the cached entries for previously-known
        //     days (preserving location, IDs, and near-dup badges) and only
        //     merge in NEW days that weren't in the cached set.
        if !incremental || dayGroups.isEmpty {
            dayGroups = initialDayGroups
        } else {
            let cachedDayKeys = Set(dayGroups.map { cal.startOfDay(for: $0.date) })
            let newDays = initialDayGroups.filter {
                !cachedDayKeys.contains(cal.startOfDay(for: $0.date))
            }
            if !newDays.isEmpty {
                dayGroups = (dayGroups + newDays).sorted { $0.date > $1.date }
            }
        }

        // ── SPEC: incremental work selection ────────────────────────────────
        // A photo NEVER gets re-Vision'd if its feature vector is already
        // persisted in SwiftData. The previous logic only short-circuited
        // photos belonging to "fully past" days, which forced us to redo
        // Vision on the entire current day every time the user opened the
        // app or pressed rescan — observable as "32 photos to scan" on every
        // press. Now:
        //   • preloadedCandidates  = ALL photos (any day) that already have
        //                            a cached featureVectorData. These feed
        //                            straight into clustering with no work.
        //   • candidatesMeta       = temporal candidates that are MISSING a
        //                            feature vector. These are the only
        //                            photos that go through Vision.
        // Result: pressing rescan on an unchanged library = 0 Vision work.
        // ─────────────────────────────────────────────────────────────────
        let preloadedCandidates: [ScannedAssetInfo] = cappedAllMetadata.compactMap { meta in
            guard !meta.isScreenshot,
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

        // Temporal candidates considered across the WHOLE library so a new
        // photo taken today can still match against yesterday's neighbour.
        let candidateIDs = await Task.detached(priority: .utility) {
            ClusteringEngine.temporalCandidates(from: cappedAllMetadata)
        }.value

        let candidatesMeta = cappedAllMetadata.filter { meta in
            !meta.isScreenshot &&
            candidateIDs.contains(meta.localIdentifier) &&
            existingFeatureMap[meta.localIdentifier] == nil
        }
        let candidateTotal = candidatesMeta.count
        // alreadyScannedDays is no longer consulted for work selection —
        // feature-vector presence is the source of truth. Silencing the
        // unused-warning while keeping the variable available for future
        // diagnostics (e.g. logging "skipped N days").
        _ = alreadyScannedDays
        await MainActor.run { phase = .analysing(current: 0, total: candidateTotal) }

        let newCandidates = await processCandidates(
            candidatesMeta,
            totalCount: candidateTotal,
            allMetadata: cappedAllMetadata,
            baselineCandidates: preloadedCandidates,
            context: context,
            metadataByID: metaMap
        )

        let allScanned = preloadedCandidates + newCandidates

        await MainActor.run { phase = .clustering }
        let rawClusters = await Task.detached(priority: .utility) {
            ClusteringEngine.clusterByDay(allMetadata: cappedAllMetadata, scannedCandidates: allScanned)
        }.value

        let metadataLookup = Dictionary(uniqueKeysWithValues: cappedAllMetadata.map { ($0.localIdentifier, $0) })
        dayGroups = rawClusters
            .filter { $0.type == "day" }
            .compactMap { buildDayGroupFromRawCluster($0, metaMap: metadataLookup) }

        // Atomic finalization: replace clusters in a single transaction. Asset
        // features were already persisted incrementally per-batch above, so even
        // if the app is killed before this point the next launch resumes from
        // the saved features instead of restarting from scratch.
        finalizeSwiftData(
            allMetadata: allMetadata,
            rawClusters: rawClusters,
            incremental: incremental,
            context: context
        )

        await MainActor.run {
            phase = .complete
            NotificationService.checkAndScheduleNotifications(for: dayGroups)
            AnalyticsService.logScanCompleted(photoCount: photoCount, dayGroupCount: dayGroups.count)
        }

        // ── 8. Background geocoding ────────────────────────────────────────
        Task { await geocodeDayGroups() }
    }

    // MARK: - Candidate Processing (off-main-actor batches)
    //
    // ──────────────────────────────────────────────────────────────────────
    // SPEC: Scan throttling & UI smoothness (locked-in requirements)
    // ──────────────────────────────────────────────────────────────────────
    // 1. Vision batches run at .utility priority (NOT .userInitiated) so the
    //    main thread keeps headroom for SwiftUI rendering and gestures.
    // 2. Background scans add a per-batch breathing-room sleep so users can
    //    scroll the photo grid at full FPS while we crunch in the background.
    //    The delay below is tuned for ~150-300 photos/sec on modern iPhones,
    //    which is fast enough to feel "live" but light enough to keep
    //    SwiftUI / scroll views buttery. Foreground scans skip the delay.
    // 3. phase = .analysing(...) updates are throttled to ~5 Hz instead of
    //    once per batch — a 40-photo batch can finish in <100ms and would
    //    otherwise spam @Observable subscribers and trigger a re-render
    //    storm in the inline progress banner.
    // 4. PPS recomputation piggy-backs on the throttled phase update so the
    //    "scanning N photos/sec" pill doesn't twitch.
    // ──────────────────────────────────────────────────────────────────────

    /// Minimum interval between MainActor `phase = .analysing(...)` updates.
    /// 0.2s ≈ 5 UI ticks per second — enough to feel live without thrashing.
    private static let phaseUpdateInterval: TimeInterval = 0.2

    /// Per-batch sleep injected during background scans so the device stays
    /// cool and the UI keeps a high frame rate while the user interacts.
    /// Foreground (full rescan) scans skip this — the user explicitly asked
    /// for the heavy work and is staring at the progress UI.
    private static let backgroundScanBatchDelayNs: UInt64 = 60_000_000  // 60 ms

    private func processCandidates(
        _ candidates: [AssetMetadata],
        totalCount: Int,
        allMetadata: [AssetMetadata],
        baselineCandidates: [ScannedAssetInfo] = [],
        context: ModelContext? = nil,
        metadataByID: [String: AssetMetadata] = [:]
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
        var lastPhaseUpdate = Date(timeIntervalSince1970: 0)
        let runningInBackground = isBackgroundScan

        for (batchIdx, batch) in batches.enumerated() {
            let currentAssets = batchPHAssets[batchIdx]

            // ── Pre-fetch NEXT batch while processing CURRENT batch ──
            // This overlaps iCloud downloads (network) with Vision CPU work.
            if batchIdx + 1 < batchPHAssets.count {
                prefetchThumbnails(for: batchPHAssets[batchIdx + 1])
            }
            stopPrefetching(for: previousPrefetchAssets)
            previousPrefetchAssets = currentAssets

            // SPEC: utility priority — never block UI work on Vision batches.
            let batchResults: [ScannedAssetInfo] = await Task.detached(priority: .utility) {
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

            // ── Persist this batch immediately ──
            // If iOS suspends the app or kills it, the work we've done so far is
            // still safe in SwiftData and the next launch's autoScanIfNeeded will
            // skip it instead of redoing Vision on the same photos.
            if let context {
                upsertAssetRecords(batchResults, metadataByID: metadataByID, context: context)
            }

            let processed = min((batchIdx + 1) * batchSize, totalCount)

            // SPEC: throttle MainActor phase updates so SwiftUI doesn't redraw
            // the inline progress banner more than ~5 times/sec, regardless of
            // how fast Vision chews through batches.
            let now = Date()
            let isLastBatch = (batchIdx == batches.count - 1)
            if isLastBatch || now.timeIntervalSince(lastPhaseUpdate) >= Self.phaseUpdateInterval {
                lastPhaseUpdate = now
                await MainActor.run {
                    phase = .analysing(current: processed, total: totalCount)
                    if let start = scanStartTime {
                        let elapsed = Date().timeIntervalSince(start)
                        currentPPS = elapsed > 0 ? Double(processed) / elapsed : 0.0
                    }
                }
            }

            // We no longer call updateDayGroupsIncrementally() here.
            // Re-clustering 20,000 photos every 40 images causes an O(N^2) CPU spiral
            // that locks up the device and spikes RAM to 3GB+.
            // dayGroups stay populated with cached data (incl. near-dup badges)
            // throughout the scan; final clustering replaces them in one pass
            // when processing completes.

            // SPEC: yield + sleep give the main run loop room to render scroll
            // updates and gestures before we kick off the next Vision batch.
            await Task.yield()
            if runningInBackground {
                try? await Task.sleep(nanoseconds: Self.backgroundScanBatchDelayNs)
            }
        }

        stopPrefetching(for: previousPrefetchAssets)
        return results
    }

    // MARK: - Persist (incremental)

    /// Upserts `AssetRecord`s for a batch of freshly-analysed candidates, preserving
    /// previously-saved features for assets we didn't touch this batch.
    private func upsertAssetRecords(
        _ batch: [ScannedAssetInfo],
        metadataByID: [String: AssetMetadata],
        context: ModelContext
    ) {
        guard !batch.isEmpty else { return }
        let ids = batch.map(\.localIdentifier)
        let predicate = #Predicate<AssetRecord> { ids.contains($0.localIdentifier) }
        let descriptor = FetchDescriptor<AssetRecord>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.localIdentifier, $0) })

        for info in batch {
            let isNew = existingMap[info.localIdentifier] == nil
            let record = existingMap[info.localIdentifier] ?? AssetRecord(localIdentifier: info.localIdentifier)
            record.creationDate       = info.date
            record.fileSize           = info.fileSize
            record.isScreenshot       = info.isScreenshot
            record.isLocallyAvailable = true
            record.featureVectorData  = info.featureData
            if let lat = info.latitude  { record.latitude  = lat }
            if let lng = info.longitude { record.longitude = lng }
            if isNew { context.insert(record) }
        }

        _ = metadataByID
        try? context.save()
    }

    /// Final commit: replace cluster records and reconcile the asset table with the
    /// current PhotoKit library. Performed in a single transaction so a crash here
    /// can't leave the UI looking at half-deleted clusters.
    private func finalizeSwiftData(
        allMetadata: [AssetMetadata],
        rawClusters: [RawCluster],
        incremental: Bool,
        context: ModelContext
    ) {
        // Cluster assignment lookup so each asset points at its day cluster.
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

        // Wipe clusters (cheap, fully derivable) and any asset rows for photos
        // that no longer exist in the library.
        try? context.delete(model: ClusterRecord.self)

        let liveIDs = Set(allMetadata.map(\.localIdentifier))
        if let everything = try? context.fetch(FetchDescriptor<AssetRecord>()) {
            for record in everything where !liveIDs.contains(record.localIdentifier) {
                context.delete(record)
            }
        }

        // Upsert asset records for the full library so metadata stays in sync,
        // even for assets we didn't run Vision on this scan (already had features
        // OR were not candidates).
        let existing: [AssetRecord]
        if incremental {
            existing = (try? context.fetch(FetchDescriptor<AssetRecord>())) ?? []
        } else {
            // Full rescan: start clean. Any features computed in this run were
            // upserted per-batch above, so we don't actually drop work.
            try? context.delete(model: AssetRecord.self)
            existing = []
        }
        let existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.localIdentifier, $0) })

        for meta in allMetadata {
            let isNew = existingMap[meta.localIdentifier] == nil
            let record = existingMap[meta.localIdentifier] ?? AssetRecord(localIdentifier: meta.localIdentifier)
            record.creationDate       = meta.date
            record.fileSize           = meta.estimatedFileSize
            record.isScreenshot       = meta.isScreenshot
            record.isLocallyAvailable = true
            record.clusterID          = clusterAssignment[meta.localIdentifier]
            if let lat = meta.latitude  { record.latitude  = lat }
            if let lng = meta.longitude { record.longitude = lng }
            if isNew { context.insert(record) }
        }

        for record in clusterRecords { context.insert(record) }
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
                color: Color(hex: "EFECE8"),
                label: "PHOTO",
                date: meta.date.map { Self.shortDateFormatter.string(from: $0).uppercased() } ?? "",
                sizeMB: Int(meta.estimatedFileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            id: DayGroup.stableID(for: date),
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
                color: Color(hex: "EFECE8"),
                label: "PHOTO",
                date: meta.date.map { Self.shortDateFormatter.string(from: $0).uppercased() } ?? "",
                sizeMB: Int(meta.estimatedFileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            id: DayGroup.stableID(for: date),
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
                color: Color(hex: "EFECE8"),
                label: "PHOTO",
                date: asset.creationDate.map { Self.shortDateFormatter.string(from: $0).uppercased() } ?? "",
                sizeMB: Int(asset.fileSize / 1_000_000)
            )
        }
        guard !photos.isEmpty else { return nil }
        return DayGroup(
            id: DayGroup.stableID(for: date),
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

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f
    }()

    private func shortDate(_ date: Date) -> String {
        return Self.shortDateFormatter.string(from: date).uppercased()
    }
}
