import FirebaseAnalytics

enum AnalyticsService {

    static func logAppOpen() {
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
    }

    static func logPhotosRemoved(count: Int, bytesSaved: Int64) {
        Analytics.logEvent("photos_removed", parameters: [
            "count": count,
            "bytes_saved": bytesSaved
        ])
    }

    static func logSpaceSaved(totalBytes: Int64) {
        Analytics.logEvent("space_saved_milestone", parameters: [
            "total_bytes": totalBytes
        ])
    }

    static func logDayOpened(photoCount: Int, date: String) {
        Analytics.logEvent("day_opened", parameters: [
            "photo_count": photoCount,
            "date": date
        ])
    }

    static func logScanCompleted(photoCount: Int, dayGroupCount: Int) {
        Analytics.logEvent("scan_completed", parameters: [
            "photo_count": photoCount,
            "day_group_count": dayGroupCount
        ])
    }

    static func logSwipeSessionCompleted(kept: Int, trashed: Int, favourited: Int) {
        Analytics.logEvent("swipe_session_completed", parameters: [
            "kept": kept,
            "trashed": trashed,
            "favourited": favourited
        ])
    }

    static func logPushNotificationOpened(identifier: String) {
        Analytics.logEvent("push_notification_opened", parameters: [
            "notification_id": identifier
        ])
    }
}
