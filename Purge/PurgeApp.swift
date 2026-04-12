import SwiftUI
import SwiftData
import UserNotifications

@main
struct PurgeApp: App {
    @State private var scanEngine = ScanEngine()
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Purge Test"
                content.body = "If you see this, notifications are working!"
                content.sound = .default
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(identifier: "testNotification", content: content, trigger: trigger)
                
                UNUserNotificationCenter.current().add(request)
            }
        }
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
        Group {
            switch scanEngine.phase {
            case .idle, .permissionDenied:
                OnboardingView()

            case .rescanning, .requestingPermission:
                HomeView(
                    dayGroups: scanEngine.dayGroups,
                    photoCount: scanEngine.photoCount,
                    scanProgress: 0.01,
                    currentPPS: scanEngine.currentPPS,
                    onRescan: {}
                )

            case .enumerating, .analysing, .clustering, .complete:
                HomeView(
                    dayGroups: scanEngine.dayGroups,
                    photoCount: scanEngine.photoCount,
                    scanProgress: scanProgress,
                    currentPPS: scanEngine.currentPPS,
                    onRescan: { scanEngine.rescan(context: modelContext) }
                )

            case .error(let message):
                errorView(message)
            }
        }
        .task {
            // Load any previously completed scan on launch
            if scanEngine.phase == .idle {
                scanEngine.loadExistingClusters(context: modelContext)
            }
        }
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
