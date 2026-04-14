import SwiftUI
import SwiftData
import Photos

@Model
final class MemorySaved {
    var totalBytesSaved: Int64
    var totalPhotosRemoved: Int

    init(totalBytesSaved: Int64 = 0, totalPhotosRemoved: Int = 0) {
        self.totalBytesSaved = totalBytesSaved
        self.totalPhotosRemoved = totalPhotosRemoved
    }
}

// MARK: - Core Types

enum UserDecision {
    case keep, trash, favourite
}

enum ClusterType: String {
    case duplicate  = "NEAR-DUPLICATES"
    case screenshot = "SCREENSHOTS"
    case trip       = "TRIP"
    case event      = "EVENT"
    case blurry     = "BLURRY PHOTOS"
}

// MARK: - Data Models

struct DummyPhoto: Identifiable, Hashable {
    let id = UUID()
    let localIdentifier: String?
    let color: Color
    let label: String
    let date: String
    let sizeMB: Int

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DummyPhoto, rhs: DummyPhoto) -> Bool { lhs.id == rhs.id }

    // Backwards-compatible init (dummy/preview data)
    init(color: Color, label: String, date: String, sizeMB: Int) {
        self.localIdentifier = nil
        self.color = color
        self.label = label
        self.date  = date
        self.sizeMB = sizeMB
    }

    // Real-photo init
    init(localIdentifier: String, color: Color, label: String, date: String, sizeMB: Int) {
        self.localIdentifier = localIdentifier
        self.color = color
        self.label = label
        self.date  = date
        self.sizeMB = sizeMB
    }
}

struct PhotoCluster: Identifiable {
    let id: UUID
    let type: ClusterType
    var label: String          // mutable — updated after geocoding
    var sublabel: String
    var photos: [DummyPhoto]
    var representativeDate: Date?
    var representativeLat: Double?
    var representativeLng: Double?

    var totalMB: Int    { photos.reduce(0) { $0 + $1.sizeMB } }
    var photoCount: Int { photos.count }

    init(
        id: UUID = UUID(),
        type: ClusterType,
        label: String,
        sublabel: String,
        photos: [DummyPhoto],
        representativeDate: Date? = nil,
        representativeLat: Double? = nil,
        representativeLng: Double? = nil
    ) {
        self.id                 = id
        self.type               = type
        self.label              = label
        self.sublabel           = sublabel
        self.photos             = photos
        self.representativeDate = representativeDate
        self.representativeLat  = representativeLat
        self.representativeLng  = representativeLng
    }
}

// MARK: - Day Group (new primary model)

struct DayGroup: Identifiable {
    let id: UUID
    let date: Date               // calendar start-of-day
    var location: String         // geocoded city, filled in after scan
    var representativeLat: Double?
    var representativeLng: Double?
    var photos: [DummyPhoto]     // non-screenshot photos for this day
    var nearDuplicateSets: [[String]]  // each inner array = near-dup group localIdentifiers

    var photoCount: Int         { photos.count }
    var nearDuplicateCount: Int { nearDuplicateSets.reduce(0) { $0 + $1.count } }
    var totalMB: Int            { photos.reduce(0) { $0 + $1.sizeMB } }

    init(
        id: UUID = UUID(),
        date: Date,
        location: String = "",
        representativeLat: Double? = nil,
        representativeLng: Double? = nil,
        photos: [DummyPhoto],
        nearDuplicateSets: [[String]] = []
    ) {
        self.id                = id
        self.date              = date
        self.location          = location
        self.representativeLat = representativeLat
        self.representativeLng = representativeLng
        self.photos            = photos
        self.nearDuplicateSets = nearDuplicateSets
    }
}

extension DayGroup: Hashable {
    static func == (lhs: DayGroup, rhs: DayGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension DayGroup {
    static let sampleDays: [DayGroup] = {
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: -n, to: Date())!) }
        return [
            DayGroup(date: daysAgo(0), location: "PARIS",
                     photos: (0..<12).map { DummyPhoto(color: Color(hex: "4A7A9B"), label: "PHOTO", date: "12 MAR", sizeMB: 18 + $0 % 5) },
                     nearDuplicateSets: [["a","b","c"], ["d","e"]]),
            DayGroup(date: daysAgo(2), location: "PARIS",
                     photos: (0..<7).map { DummyPhoto(color: Color(hex: "7A9B4A"), label: "PHOTO", date: "10 MAR", sizeMB: 14 + $0 % 3) }),
            DayGroup(date: daysAgo(4), location: "LONDON",
                     photos: (0..<23).map { DummyPhoto(color: Color(hex: "9B4A7A"), label: "PHOTO", date: "8 MAR", sizeMB: 20 + $0 % 6) },
                     nearDuplicateSets: [["x","y"]]),
        ]
    }()
}

// MARK: - Dummy Data (kept for legacy views)

extension PhotoCluster {
    static let sampleClusters: [PhotoCluster] = [
        PhotoCluster(
            type: .duplicate,
            label: "NEAR-DUPLICATES",
            sublabel: "12 PHOTOS · 380 MB OF WASTE",
            photos: [
                DummyPhoto(color: Color(hex: "C8B8A2"), label: "SELFIE", date: "12 MAR", sizeMB: 28),
                DummyPhoto(color: Color(hex: "B8A892"), label: "SELFIE", date: "12 MAR", sizeMB: 31),
                DummyPhoto(color: Color(hex: "D4C4AE"), label: "SELFIE", date: "12 MAR", sizeMB: 29),
                DummyPhoto(color: Color(hex: "C0B09A"), label: "SELFIE", date: "12 MAR", sizeMB: 27),
                DummyPhoto(color: Color(hex: "CAB9A4"), label: "SELFIE", date: "12 MAR", sizeMB: 30),
                DummyPhoto(color: Color(hex: "C5B49E"), label: "SELFIE", date: "12 MAR", sizeMB: 32),
            ]
        ),
        PhotoCluster(
            type: .screenshot,
            label: "RECEIPTS",
            sublabel: "45 SCREENSHOTS · 120 MB",
            photos: [
                DummyPhoto(color: Color(hex: "E8E4DE"), label: "RECEIPT", date: "3 APR", sizeMB: 2),
                DummyPhoto(color: Color(hex: "F0ECE6"), label: "RECEIPT", date: "1 APR", sizeMB: 2),
                DummyPhoto(color: Color(hex: "ECEAE4"), label: "RECEIPT", date: "28 MAR", sizeMB: 3),
                DummyPhoto(color: Color(hex: "E4E0DA"), label: "RECEIPT", date: "22 MAR", sizeMB: 2),
            ]
        ),
        PhotoCluster(
            type: .blurry,
            label: "BLURRY PHOTOS",
            sublabel: "23 PHOTOS · 85 MB",
            photos: [
                DummyPhoto(color: Color(hex: "A89880"), label: "BLURRY", date: "5 APR", sizeMB: 4),
                DummyPhoto(color: Color(hex: "9C8C74"), label: "BLURRY", date: "4 APR", sizeMB: 3),
                DummyPhoto(color: Color(hex: "B0A088"), label: "BLURRY", date: "2 APR", sizeMB: 5),
            ]
        ),
        PhotoCluster(
            type: .trip,
            label: "BIARRITZ",
            sublabel: "JUNE 2025 · 47 PHOTOS · 1.2 GB",
            photos: [
                DummyPhoto(color: Color(hex: "4A7A9B"), label: "BEACH",  date: "15 JUN", sizeMB: 22),
                DummyPhoto(color: Color(hex: "5E8FAE"), label: "BEACH",  date: "15 JUN", sizeMB: 19),
                DummyPhoto(color: Color(hex: "3D6E8C"), label: "SURF",   date: "16 JUN", sizeMB: 25),
                DummyPhoto(color: Color(hex: "6B9BBE"), label: "SUNSET", date: "16 JUN", sizeMB: 18),
                DummyPhoto(color: Color(hex: "527E99"), label: "TOWN",   date: "17 JUN", sizeMB: 20),
            ]
        ),
    ]
}
