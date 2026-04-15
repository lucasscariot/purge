import SwiftUI
import SwiftData
import Pow
import UIKit
@preconcurrency import Photos

struct ScrollViewContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    @State private var isAppeared = false
    @State private var contentHeight: CGFloat = 0
    @State private var funName: String = [
        "sunshine", "hero", "smart-ass", "rockstar", "legend",
        "champ", "superstar", "genius", "boss", "chief",
        "captain", "maestro", "hotshot", "maverick", "tiger",
        "wizard", "ninja", "guru", "star", "darling",
        "sweetie", "honey", "pumpkin", "buttercup", "cupcake",
        "muffin", "peanut", "bean", "nugget", "🥦",
        "firecracker", "sparky", "wildcat", "troublemaker", "rebel",
        "outlaw", "bandit", "rascal", "scamp", "sport",
        "pal", "mate", "amigo", "bossman", "bosslady",
        "detective", "sleuth", "purger", "cleaner", "magician",
        "goblin", "gremlin", "bat", "vampire", "sleepwalker",
        "phantom", "ghost", "owl", "zombie", "dreamer", "👾", "👽"
    ].randomElement() ?? "friend"

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

    @State private var generatedGreeting: String = ""
    @State private var currentTipIndex = 0

    private let loadingTips = [
        ("lock.shield.fill", "100% Private", "Your photos never leave your device. All scanning happens locally."),
        ("rectangle.on.rectangle.angled", "Finding Duplicates", "We group similar photos together so you can keep the best ones."),
        ("hand.draw.fill", "Pinch to Zoom", "You can pinch any photo stack to get a closer look before purging."),
        ("sparkles", "Smart Organization", "We scan for receipts, screenshots, and blurry shots too.")
    ]

    private var greeting: String {
        if !generatedGreeting.isEmpty { return generatedGreeting }
        return "Hello, \(funName)"
    }
    
    private func generateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        if hour >= 0 && hour < 5 || hour >= 23 {
            let nightGreetings = ["Insomnia", "Up late", "Night owl", "Still awake"]
            let prefix = nightGreetings.randomElement() ?? "Insomnia"
            generatedGreeting = "\(prefix), \(funName)?"
            return
        }
        
        let timeGreetings: [String]
        switch hour {
        case 5..<12:
            timeGreetings = ["Good morning", "Rise and shine", "Morning", "Bonjour", "Hey", "What's up", "Top of the morning"]
        case 12..<17:
            timeGreetings = ["Good afternoon", "Afternoon", "Hey", "What's up", "Howdy", "Hello", "Hola", "Bonjour"]
        default:
            timeGreetings = ["Good evening", "Evening", "Hey", "What's up", "Bonsoir", "Hello", "Aloha"]
        }
        
        let prefix = timeGreetings.randomElement() ?? "Hello"
        let punctuation = (prefix == "What's up") ? "?" : ""
        generatedGreeting = "\(prefix), \(funName)\(punctuation)"
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    PurgeColor.background
                        .ignoresSafeArea()
                    
                    DotGridBackground()
                        .ignoresSafeArea()
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            
                            VStack(spacing: 24) {
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
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: ScrollViewContentHeightKey.self, value: geo.size.height)
                                }
                            )
                        }
                    }
                    .onPreferenceChange(ScrollViewContentHeightKey.self) { height in
                        let roundedHeight = round(height)
                        if abs(contentHeight - roundedHeight) > 1.0 {
                            contentHeight = roundedHeight
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
                            onDismiss: { selectedDayGroup = nil },
                            onRemovePhotos: { identifiers in
                                scanEngine.trashItems(
                                    identifiers: Set(identifiers),
                                    context: modelContext,
                                    dismissCallback: { selectedDayGroup = nil }
                                )
                            }
                        )
                    }
                    
                    if selectedDayGroup == nil && !dayGroups.isEmpty && groupedPreviousDays.count > 1 {
                        HStack(alignment: .top) {
                            Spacer()
                            TimelineScrubber(
                                months: groupedPreviousDays.map { $0.id },
                                proxy: proxy
                            )
                            .frame(maxHeight: contentHeight > 0 ? min(max(0, contentHeight - topSafeArea - 24), screenHeight - topSafeArea - 120) : .infinity)
                            .padding(.trailing, 0)
                            .padding(.top, topSafeArea + 24)
                        }
                    }
                }
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
    
    private var topSafeArea: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
    }
    
    private var screenHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.bounds.height ?? UIScreen.main.bounds.height
    }
    
    // MARK: - Hero
    
    private var statsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PurgeColor.mustard)
            
            HStack(spacing: 4) {
                Text("Saved")
                    .foregroundStyle(PurgeColor.textMuted)
                Text(formatBytes(totalMemorySaved))
                    .foregroundStyle(PurgeColor.text)
            }
            .font(PurgeFont.ui(14, weight: .semibold))
            
            if totalPhotosRemoved > 0 {
                Circle()
                    .frame(width: 3, height: 3)
                    .foregroundStyle(PurgeColor.textMuted.opacity(0.5))
                
                Text("\(totalPhotosRemoved) removed")
                    .font(PurgeFont.ui(14, weight: .medium))
                    .foregroundStyle(PurgeColor.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if totalMemorySaved > 0 {
                statsPill
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : -15)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(PurgeFont.ui(16, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 15)
                
                Text("Your Library")
                    .font(PurgeFont.display(42, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 15)
                
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PurgeColor.mustard)
                    
                    HStack(spacing: 4) {
                        Text("\(formatted(dynamicPhotoCount))")
                            .foregroundStyle(PurgeColor.text)
                            .font(PurgeFont.ui(14, weight: .bold))
                        
                        Text("photos waiting")
                            .foregroundStyle(PurgeColor.textMuted)
                            .font(PurgeFont.ui(14, weight: .medium))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                .opacity(isAppeared ? 1 : 0)
                .offset(y: isAppeared ? 0 : 15)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if generatedGreeting.isEmpty {
                generateGreeting()
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                isAppeared = true
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
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
    
    private var groupedPreviousDays: [(id: String, date: Date, days: [DayGroup])] {
        let calendar = Calendar.current
        let today = Date()
        let todayMonth = calendar.component(.month, from: today)
        let todayDay = calendar.component(.day, from: today)
        
        let previous = dayGroups.filter { group in
            let month = calendar.component(.month, from: group.date)
            let day = calendar.component(.day, from: group.date)
            return !(month == todayMonth && day == todayDay)
        }.sorted { $0.date > $1.date }
        
        var groups: [String: [DayGroup]] = [:]
        var dates: [String: Date] = [:]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        for day in previous {
            let key = formatter.string(from: day.date)
            if groups[key] == nil {
                groups[key] = []
                dates[key] = day.date
            }
            groups[key]?.append(day)
        }
        
        return groups.map { (id: $0.key, date: dates[$0.key]!, days: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    private var previousDaysSection: some View {
        let grouped = groupedPreviousDays
        
        return Group {
            if !grouped.isEmpty {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(grouped, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(group.id.uppercased())
                                .font(PurgeFont.display(24, weight: .bold))
                                .foregroundStyle(PurgeColor.text)
                                .padding(.horizontal, 24)
                                .id("header_\(group.id)")
                            
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                ForEach(group.days) { day in
                                    photoStackItem(group: day)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
    }
    
    private func photoStackItem(group: DayGroup) -> some View {
        let stack = PinchablePhotoStack(photos: group.photos, seed: group.id.hashValue) {
            selectedDayGroup = group
        }
        .frame(width: 160, height: 160)
        
        return VStack(spacing: 2) {
            stack
            
            VStack(spacing: 4) {
                Text(formattedDate(group.date))
                    .font(PurgeFont.ui(15, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                
                if group.nearDuplicateCount > 0 {
                    Text("\(group.nearDuplicateCount) near-dups")
                        .font(PurgeFont.ui(11, weight: .bold))
                        .foregroundStyle(PurgeColor.rose)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PurgeColor.rose.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(minHeight: 48, alignment: .top)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
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
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(PurgeColor.textMuted.opacity(0.2), lineWidth: 8)
                    .frame(width: 64, height: 64)
                
                if let progress = scanProgress {
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(PurgeColor.mustard, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)
                } else {
                    ProgressView().tint(PurgeColor.mustard)
                        .scaleEffect(1.5)
                }
            }
            
            VStack(spacing: 8) {
                Text("Gathering your memories...")
                    .font(PurgeFont.ui(18, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                
                if let progress = scanProgress {
                    Text("\(Int(progress * 100))% complete")
                        .font(PurgeFont.ui(14, weight: .medium))
                        .foregroundStyle(PurgeColor.textMuted)
                }
            }
            
            let tip = loadingTips[currentTipIndex]
            VStack(spacing: 12) {
                Image(systemName: tip.0)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(PurgeColor.mustard)
                
                Text(tip.1)
                    .font(PurgeFont.ui(16, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                
                Text(tip.2)
                    .font(PurgeFont.ui(14, weight: .medium))
                    .foregroundStyle(PurgeColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            .padding(.top, 16)
            .id(currentTipIndex)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom).animation(.spring(response: 0.5, dampingFraction: 0.8))),
                removal: .opacity.combined(with: .move(edge: .top).animation(.spring(response: 0.5, dampingFraction: 0.8)))
            ))
            
            if let pps = currentPPS, pps > 0 {
                Text(String(format: "Dev Mode: %.1f photos/sec", pps))
                    .font(PurgeFont.mono(12))
                    .foregroundStyle(PurgeColor.primary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .onReceive(Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()) { _ in
            if scanProgress != nil {
                withAnimation {
                    currentTipIndex = (currentTipIndex + 1) % loadingTips.count
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(PurgeColor.textMuted.opacity(0.5))
            Text("Your library is empty")
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
