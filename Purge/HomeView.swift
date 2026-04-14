import SwiftUI
import SwiftData
import Pow
import UIKit
@preconcurrency import Photos

struct HomeView: View {
    let photoCount: Int
    let scanProgress: Double?
    let currentPPS: Double?
    var onRescan: () -> Void
    var onStartReview: (() -> Void)? = nil

    @Environment(ScanEngine.self) private var scanEngine
    @Environment(\.modelContext) private var modelContext
    @Query private var memorySavedRecords: [MemorySaved]

    @State private var selectedDayGroup: DayGroup?

    private var totalMemorySaved: Int64 {
        memorySavedRecords.first?.totalBytesSaved ?? 0
    }

    private var totalPhotosRemoved: Int {
        memorySavedRecords.first?.totalPhotosRemoved ?? 0
    }

    private var dayGroups: [DayGroup] {
        scanEngine.dayGroups
    }

    private var dynamicPhotoCount: Int {
        scanEngine.photoCount
    }

    
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PurgeColor.background
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        DotGridBackground()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .offset(y: -topSafeArea)
                        
                        VStack(spacing: 48) {
                            Color.clear.frame(height: topSafeArea)
                            
                            heroSection
                                .padding(.top, 16)
                            
                            if scanProgress != nil {
                                scanningState
                            } else if dayGroups.isEmpty {
                                emptyState
                            } else {
                                photoStacksSection
                                    .padding(.top, 16)
                            }
                            
                            Color.clear.frame(height: 120)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        rescanButton
                    }
                    .padding(24)
                }
                
                if let group = selectedDayGroup {
                    DayDetailOverlay(
                        dayGroup: group,
                        onDismiss: { selectedDayGroup = nil }
                    )
                }
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private var topSafeArea: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved \(formatBytes(totalMemorySaved))")
                    .font(PurgeFont.cursive(22))
                    .foregroundStyle(PurgeColor.mustard)
                if totalPhotosRemoved > 0 {
                    Text("\(totalPhotosRemoved) photos removed")
                        .font(PurgeFont.cursive(16))
                        .foregroundStyle(PurgeColor.mustard.opacity(0.7))
                }
            }

            Text("Your Scrapbook")
                .font(PurgeFont.display(42, weight: .bold))
                .foregroundStyle(PurgeColor.text)
                .transition(.movingParts.boing)

            Text("\(formatted(dynamicPhotoCount)) photos waiting to be organized")
                .font(PurgeFont.ui(16, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Stats Section
    
    @State private var statsKey: UUID = UUID()
    
    private var statsSection: some View {
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                statCard(title: "Days", value: "\(dayGroups.count)")
                    .changeEffect(.shine, value: statsKey)
                statCard(title: "Photos", value: "\(dayGroups.reduce(0) { $0 + $1.photoCount })")
                    .changeEffect(.shine, value: statsKey)
            }
        }
        .padding(.horizontal, 24)
        .onChange(of: dayGroups.count) { _, _ in
            statsKey = UUID()
        }
    }
    
// MARK: - Photo Stacks Section
    
    private var photoStacksSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            onThisDaySection
            previousDaysSection
        }
    }
    
    private var onThisDaySection: some View {
        let calendar = Calendar.current
        let today = Date()
        let todayMonth = calendar.component(.month, from: today)
        let todayDay = calendar.component(.day, from: today)
        
        let onThisDayGroups = dayGroups.filter { group in
            let month = calendar.component(.month, from: group.date)
            let day = calendar.component(.day, from: group.date)
            return month == todayMonth && day == todayDay && calendar.component(.year, from: group.date) != calendar.component(.year, from: today)
        }.sorted { $0.date > $1.date }
        
        return Group {
            if !onThisDayGroups.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("On this day")
                        .font(PurgeFont.display(24, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(onThisDayGroups) { day in
                                photoStackItem(group: day)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
    }
    
    private var previousDaysSection: some View {
        let calendar = Calendar.current
        let today = Date()
        let todayMonth = calendar.component(.month, from: today)
        let todayDay = calendar.component(.day, from: today)
        
        let previousDays = dayGroups.filter { group in
            let month = calendar.component(.month, from: group.date)
            let day = calendar.component(.day, from: group.date)
            return !(month == todayMonth && day == todayDay)
        }.sorted { $0.date > $1.date }
        
        return Group {
            if !previousDays.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Previous Days")
                        .font(PurgeFont.display(24, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .padding(.horizontal, 24)
                    
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(previousDays) { day in
                            photoStackItem(group: day)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
    
    private func photoStackItem(group: DayGroup) -> some View {
        let stack = PinchablePhotoStack(photos: group.photos, seed: group.id.hashValue) {
            selectedDayGroup = group
        }
        .frame(width: 160, height: 160)
        
        return VStack(spacing: 6) {
            stack
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            Text(formattedDate(group.date))
                .font(PurgeFont.cursive(14))
                .fontWeight(.medium)
                .foregroundStyle(PurgeColor.textMuted)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
    
    // MARK: - Stat Card
    
    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(PurgeFont.display(32, weight: .bold))
                .foregroundStyle(PurgeColor.text)
            Text(title)
                .font(PurgeFont.ui(14, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(PurgeColor.mustard.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Rescan Button
    
    @State private var isRescanPressed = false
    
    private var rescanButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRescan()
        }) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .background(PurgeColor.text)
                .clipShape(Circle())
                .shadow(color: PurgeColor.text.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScrapbookButtonStyle())
        .scaleEffect(isRescanPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRescanPressed)
        .disabled(scanProgress != nil)
        .opacity(scanProgress != nil ? 0.5 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRescanPressed)
        .onChange(of: scanProgress) { _, newValue in
            if newValue != nil && !isRescanPressed {
                isRescanPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isRescanPressed = false
                }
            }
        }
    }
    
    // MARK: - Placeholders
    
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().tint(PurgeColor.mustard)
                .scaleEffect(1.5)
            Text("Gathering your memories...")
                .font(PurgeFont.ui(16, weight: .bold))
                .foregroundStyle(PurgeColor.textMuted)
            
            if let pps = currentPPS, pps > 0 {
                Text(String(format: "Dev Mode: %.1f photos/sec", pps))
                    .font(PurgeFont.mono(12))
                    .foregroundStyle(PurgeColor.primary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(PurgeColor.textMuted.opacity(0.5))
            Text("Your scrapbook is empty")
                .font(PurgeFont.display(24, weight: .bold))
                .foregroundStyle(PurgeColor.text)
            Text("Tap the rescan button to find photos.")
                .font(PurgeFont.ui(16, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    private func formatted(_ n: Int) -> String {
        n >= 1000 ? "\(n / 1000),\(String(format: "%03d", n % 1000))" : "\(n)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview {
    HomeView(
        photoCount: 4821,
        scanProgress: nil,
        currentPPS: nil,
        onRescan: {}
    )
}