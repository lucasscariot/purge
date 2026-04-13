import SwiftUI
import SwiftData
import UserNotifications

@main
struct PurgeApp: App {
    @State private var scanEngine = ScanEngine()
    
    init() {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // Check if we already asked for permission before — only send "thank you" on first grant
        let hasRequestedPermission = UserDefaults.standard.bool(forKey: "notificationPermissionRequested")
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted && !hasRequestedPermission {
                // Only show "thank you" if this is the first time permission was granted
                let content = UNMutableNotificationContent()
                content.title = "Thanks for using Purge"
                content.body = "We'll notify you when it's time to manage your photos."
                content.sound = .default
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: "thankYouNotification", content: content, trigger: trigger)
                
                UNUserNotificationCenter.current().add(request)
            }
        }
        
        UserDefaults.standard.set(true, forKey: "notificationPermissionRequested")
    }

    var body: some Scene {

        WindowGroup {
            ContentRootView()
                .environment(scanEngine)
        }
        .modelContainer(for: [AssetRecord.self, ClusterRecord.self])
    }
}

// MARK: - Content Root

struct ContentRootView: View {
    @Environment(ScanEngine.self)    private var scanEngine
    @Environment(\.modelContext)     private var modelContext

    var body: some View {
        rootContent
            // Restore persisted scan results on app launch.
            // Runs once when the view appears; loadExistingClusters sets
            // phase = .complete and populates dayGroups if data exists.
            .task {
                scanEngine.loadExistingClusters(context: modelContext)
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        // Track dayGroups so ContentRootView recomputes when scanEngine.dayGroups
        // changes (e.g. after photos are deleted). Without this, phase stays .complete
        // and SwiftUI never re-evaluates the body.
        let _ = scanEngine.dayGroups

        switch scanEngine.phase {
        case .idle:
            if scanEngine.dayGroups.isEmpty {
                emptyHomeView
            } else {
                // Show existing scan results even in idle state
                HomeView(
                    photoCount: scanEngine.photoCount,
                    scanProgress: nil,
                    currentPPS: nil,
                    onRescan: { scanEngine.rescan(context: modelContext) }
                )
            }

        case .rescanning, .requestingPermission:
            HomeView(
                photoCount: scanEngine.photoCount,
                scanProgress: 0.01,
                currentPPS: scanEngine.currentPPS,
                onRescan: {}
            )

        case .enumerating, .analysing, .clustering, .complete:
            HomeView(
                photoCount: scanEngine.photoCount,
                scanProgress: scanProgress,
                currentPPS: scanEngine.currentPPS,
                onRescan: { scanEngine.rescan(context: modelContext) }
            )

        case .permissionDenied:
            permissionDeniedView

        case .error(let message):
            errorView(message)
        }
    }

    private var emptyHomeView: some View {
        HomeView(
            photoCount: 0,
            scanProgress: nil,
            currentPPS: nil,
            onRescan: { scanEngine.startScan(context: modelContext) }
        )
    }

    private var permissionDeniedView: some View {
        HomeView(
            photoCount: 0,
            scanProgress: nil,
            currentPPS: nil,
            onRescan: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }

    private var scanProgress: Double? {
        switch scanEngine.phase {
        case .rescanning:                          return 0.01
        case .enumerating:                          return 0.02
        case .analysing(let current, let total):    return total > 0 ? max(0.01, Double(current) / Double(total)) : 0.02
        case .clustering:                           return 0.98
        default:                                    return nil
        }
    }

    private func errorView(_ message: String) -> some View {
        ZStack {
            PurgeColor.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    StatusDot(color: PurgeColor.primary, size: 8)
                    Text("PURGE")
                        .font(PurgeFont.mono(12, weight: .semibold))
                        .foregroundStyle(PurgeColor.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(PurgeColor.surface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PurgeColor.border).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTag(text: "SYSTEM_ERROR", color: PurgeColor.primary)
                    Text("SOMETHING\nBROKE.")
                        .font(PurgeFont.headline(56))
                        .foregroundStyle(PurgeColor.text)
                        .tracking(-1)
                    Text(message)
                        .font(PurgeFont.mono(11))
                        .foregroundStyle(PurgeColor.textMuted)
                    Text("NOT_YOUR_PHOTOS_THOUGH — THOSE_ARE_STILL_A_MESS")
                        .font(PurgeFont.mono(10))
                        .foregroundStyle(PurgeColor.textMuted)
                }
                .padding(16)
            }
        }
    }
}
