import SwiftUI
import SwiftData
import Pow
import UIKit
import Combine
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
    @State private var funName: String = ""

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

    private var loadingTips: [(String, String, String)] {
        [
            ("lock.shield.fill", NSLocalizedString("homeview_tip_private_title", comment: ""), NSLocalizedString("homeview_tip_private_desc", comment: "")),
            ("rectangle.on.rectangle.angled", NSLocalizedString("homeview_tip_duplicates_title", comment: ""), NSLocalizedString("homeview_tip_duplicates_desc", comment: "")),
            ("hand.draw.fill", NSLocalizedString("homeview_tip_zoom_title", comment: ""), NSLocalizedString("homeview_tip_zoom_desc", comment: "")),
            ("sparkles", NSLocalizedString("homeview_tip_smart_title", comment: ""), NSLocalizedString("homeview_tip_smart_desc", comment: ""))
        ]
    }

    private var greeting: String {
        if !generatedGreeting.isEmpty { return generatedGreeting }
        return String(format: NSLocalizedString("homeview_greeting_format", comment: ""), "Hello", funName.isEmpty ? "friend" : funName)
    }
    
    private func generateGreeting() {
        if funName.isEmpty {
            let namesStr = NSLocalizedString("homeview_fun_names", comment: "")
            let names = namesStr.components(separatedBy: ",")
            funName = names.randomElement()?.trimmingCharacters(in: .whitespaces) ?? "friend"
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let format = NSLocalizedString("homeview_greeting_format", comment: "")
        
        if hour >= 0 && hour < 5 || hour >= 23 {
            let nightGreetingsStr = NSLocalizedString("homeview_greetings_night", comment: "")
            let nightGreetings = nightGreetingsStr.components(separatedBy: ",")
            let prefix = nightGreetings.randomElement()?.trimmingCharacters(in: .whitespaces) ?? "Insomnia"
            
            // For night greetings, the original code added a question mark.
            let formatNight = NSLocalizedString("homeview_greeting_format_question", comment: "")
            generatedGreeting = String(format: formatNight, prefix, funName)
            return
        }
        
        let timeGreetingsStr: String
        switch hour {
        case 5..<12:
            timeGreetingsStr = NSLocalizedString("homeview_greetings_morning", comment: "")
        case 12..<17:
            timeGreetingsStr = NSLocalizedString("homeview_greetings_afternoon", comment: "")
        default:
            timeGreetingsStr = NSLocalizedString("homeview_greetings_evening", comment: "")
        }
        
        let timeGreetings = timeGreetingsStr.components(separatedBy: ",")
        let prefix = timeGreetings.randomElement()?.trimmingCharacters(in: .whitespaces) ?? "Hello"
        
        let punctuation = (prefix == "What's up") ? "?" : ""
        if punctuation == "?" {
            let formatQuestion = NSLocalizedString("homeview_greeting_format_question", comment: "")
            generatedGreeting = String(format: formatQuestion, prefix, funName)
        } else {
            generatedGreeting = String(format: format, prefix, funName)
        }
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

                                if scanEngine.isBackgroundScan {
                                    backgroundScanBanner
                                        .padding(.horizontal, 24)
                                        .padding(.top, 8)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                heroSection
                                    .padding(.top, 16)
                                
                                if scanProgress != nil {
                                    scanningState
                                } else if dayGroups.isEmpty {
                                    if scanEngine.isScanning {
                                        preparingState
                                    } else {
                                        emptyState
                                    }
                                } else {
                                    photoStacksSection
                                        .padding(.top, 16)
                                }
                                
                                Color.clear.frame(height: 120)
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scanEngine.isBackgroundScan)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: ScrollViewContentHeightKey.self, value: geo.size.height)
                                }
                            )
                        }
                    }
                    .scrollDisabled(scanProgress != nil && !scanEngine.isBackgroundScan)
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
        return windowScene?.windows.first?.bounds.height ?? windowScene?.screen.bounds.height ?? 852
    }
    
    // MARK: - Background scan banner

    /// Editorial scrapbook banner shown at the top of HomeView while a silent
    /// incremental scan is running. Mirrors the language of the hero block:
    /// a paper card with a mustard washi-tape strip, a mono uppercase status
    /// label, a serif progress fraction, a percentage on the right, and a
    /// hairline mustard rule that fills as Vision crunches batches.
    /// SPEC: this banner MUST stay non-blocking — the user can scroll the
    /// grid, open day overlays, etc. while it's visible.
    private var backgroundScanBanner: some View {
        let progress = scanEngine.liveProgress
        let fraction: Double? = {
            guard let p = progress, p.total > 0 else { return nil }
            return Double(p.current) / Double(p.total)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PurgePulseDot(color: PurgeColor.mustard, baseSize: 5)
                    .frame(width: 12, height: 12)

                Text("homeview_background_scan_title")
                    .font(PurgeFont.mono(10, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)

                if let f = fraction {
                    Text("\(Int((f * 100).rounded()))%")
                        .font(PurgeFont.mono(10, weight: .semibold))
                        .foregroundStyle(PurgeColor.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                if let p = progress, p.total > 0 {
                    Text(formatted(p.current))
                        .font(PurgeFont.display(22, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("/ \(formatted(p.total))")
                        .font(PurgeFont.mono(11, weight: .medium))
                        .foregroundStyle(PurgeColor.textMuted)
                        .lineLimit(1)
                } else {
                    Text("homeview_background_scan_subtitle")
                        .font(PurgeFont.mono(11, weight: .medium))
                        .foregroundStyle(PurgeColor.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            ScanProgressRule(fraction: fraction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PurgeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PurgeColor.mustard.opacity(0.22), lineWidth: 0.6)
        )
        .overlay(alignment: .topLeading) {
            // Reuse the same washi tape look as the scrapbook chips, but
            // anchored further in so it visually "pins" a wider banner.
            Rectangle()
                .fill(PurgeColor.mustard.opacity(0.55))
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 12)
                .rotationEffect(.degrees(-8))
                .offset(x: 22, y: -6)
                .shadow(color: Color.black.opacity(0.08), radius: 1.5, x: 0, y: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: PurgeColor.mustard.opacity(0.14), radius: 14, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Hero
    
    private var statsPill: some View {
        PurgeHeaderPill(variant: .neutral, verticalPadding: 10) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PurgeColor.mustard)

            HStack(spacing: 4) {
                Text("homeview_saved")
                    .font(PurgeFont.ui(14, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                    .purgePillSingleLine()
                Text(formatBytes(totalMemorySaved))
                    .font(PurgeFont.ui(14, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                    .purgePillSingleLine()
            }

            if totalPhotosRemoved > 0 {
                Circle()
                    .frame(width: 3, height: 3)
                    .foregroundStyle(PurgeColor.textMuted.opacity(0.5))

                Text(String(format: NSLocalizedString("homeview_photos_removed", comment: ""), totalPhotosRemoved))
                    .font(PurgeFont.ui(14, weight: .medium))
                    .foregroundStyle(PurgeColor.textMuted)
                    .purgePillSingleLine()
            }
        }
    }
    
    // NOTE: The previous frosted `photoCountPill` / `nearDuplicatesCountPill` /
    // `nearDuplicatesDaysPill` were replaced by the editorial hero block
    // (`heroNumberBlock` + `heroScrapbookChips`). Keeping `PurgeHeaderPill` as
    // a shared component for any future header pill needs (it is still used
    // by `statsPill`).

    // ── Hero (editorial / scrapbook) ────────────────────────────────────
    // SPEC: this is a paid-production hero. Hierarchy is:
    //   1. statsPill (only when something has been saved) — small frosted chip
    //      anchored top-left, acts as a "seal" on the page
    //   2. handwritten greeting (Delius cursive) — personal, scrapbook tone
    //   3. "Your Library" — bold serif page title
    //   4. mustard editorial rule — visual anchor / magazine spread cue
    //   5. hero number — gigantic serif photo count, the page's focal point
    //   6. scrapbook stat chips (rose / peach) — tape-pinned, lightly rotated
    // Animations are staggered by ~60ms per row to feel curated, not robotic.
    // ────────────────────────────────────────────────────────────────────

    private var heroGreeting: some View {
        // SPEC: greeting uses the app's soft rounded UI face (SF Pro Rounded)
        // — the cursive scrapbook font felt off-brand against the editorial
        // serif title. Uppercase + tracking gives it an editorial small-caps
        // feel that complements the "// APR 2026" issue tag.
        Text(greeting)
            .font(PurgeFont.ui(13, weight: .semibold))
            .foregroundStyle(PurgeColor.textMuted)
            .textCase(.uppercase)
            .tracking(1.6)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var heroTitleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("homeview_your_library")
                .font(PurgeFont.display(46, weight: .bold))
                .foregroundStyle(PurgeColor.text)
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            Text(issueTag)
                .font(PurgeFont.mono(10, weight: .semibold))
                .foregroundStyle(PurgeColor.textMuted)
                .tracking(1.5)
                .padding(.bottom, 6)
        }
    }

    /// "// APR 2026" style issue tag — adds a magazine-spread feel to the title.
    private var issueTag: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return "// " + f.string(from: Date()).uppercased()
    }

    /// Magazine-grade focal number: the photo count rendered as a 76pt serif,
    /// flanked by a mustard accent rule + mono caption. Replaces the previous
    /// `photoCountPill` — same data, much higher impact.
    private var heroNumberBlock: some View {
        let countLabel: String = dynamicPhotoCount > 0 ? formatted(dynamicPhotoCount) : "—"
        return HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text(countLabel)
                .font(PurgeFont.display(60, weight: .bold))
                .foregroundStyle(PurgeColor.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .tracking(-1.5)
                .changeEffect(.shine, value: dynamicPhotoCount)

            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(PurgeColor.mustard)
                    .frame(width: 28, height: 3)
                Text("homeview_photos_waiting")
                    .font(PurgeFont.mono(10, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: dynamicPhotoCount)
    }

    /// Two scrapbook chips that wrap on narrow widths (FlowLayout). Each chip
    /// is a tape-pinned card with a light rotation — kept distinct from the
    /// frosted material pills used elsewhere so they read as "stickers".
    private var heroScrapbookChips: some View {
        FlowLayout(spacing: 14) {
            if scanEngine.totalNearDuplicateCount > 0 {
                ScrapbookStatChip(
                    value: formatted(scanEngine.totalNearDuplicateCount),
                    label: NSLocalizedString("homeview_near_duplicates_label", comment: ""),
                    icon: "rectangle.on.rectangle.angled.fill",
                    tint: PurgeColor.rose,
                    rotation: -1.8,
                    trailingPulse: scanEngine.isScanning
                )

                if scanEngine.daysWithDuplicates > 0 {
                    ScrapbookStatChip(
                        value: formatted(scanEngine.daysWithDuplicates),
                        label: NSLocalizedString("homeview_days_label", comment: ""),
                        icon: "calendar",
                        tint: PurgeColor.peach,
                        rotation: 1.6
                    )
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if totalMemorySaved > 0 {
                statsPill
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : -15)
            }

            VStack(alignment: .leading, spacing: 10) {
                heroGreeting
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 15)

                heroTitleRow
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 15)

                EditorialRule()
                    .padding(.top, 2)
                    .opacity(isAppeared ? 1 : 0)
                    .scaleEffect(x: isAppeared ? 1 : 0.4, anchor: .leading)

                heroNumberBlock
                    .padding(.top, 8)
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 15)

                heroScrapbookChips
                    .padding(.top, 14)
                    .padding(.horizontal, -2) // let chip shadows breathe past the safe zone
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scanEngine.totalNearDuplicateCount)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scanEngine.daysWithDuplicates)
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
                    Text("homeview_on_this_day")
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
                    Text(String(format: NSLocalizedString("homeview_near_dups", comment: ""), group.nearDuplicateCount))
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
        .disabled(scanProgress != nil || scanEngine.isScanning)
        .opacity((scanProgress != nil || scanEngine.isScanning) ? 0.5 : 1.0)
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
                Text("homeview_gathering_your_memories")
                    .font(PurgeFont.ui(18, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                
                if let progress = scanProgress {
                    Text(String(format: NSLocalizedString("homeview_percent_complete", comment: ""), Int(progress * 100)))
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
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(PurgeColor.mustard)
                    Text(String(format: NSLocalizedString("homeview_scanning_speed", comment: ""), Int(pps)))
                        .font(PurgeFont.ui(14, weight: .bold))
                        .foregroundStyle(PurgeColor.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PurgeColor.textMuted.opacity(0.1))
                .clipShape(Capsule())
                .padding(.top, 16)
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
            Text("homeview_your_library_is_empty")
                .font(PurgeFont.display(24, weight: .bold))
                .foregroundStyle(PurgeColor.text)
            Text("homeview_tap_the_rescan_button_to_find_photos")
                .font(PurgeFont.ui(16, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    /// Lightweight stand-in shown while the very first scan is enumerating the
    /// library. The banner at the top surfaces progress; this just lets the user
    /// know the photos are on their way without locking the screen.
    private var preparingState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(PurgeColor.mustard)
                .symbolEffect(.pulse, options: .repeating)
            Text("homeview_preparing_title")
                .font(PurgeFont.display(24, weight: .bold))
                .foregroundStyle(PurgeColor.text)
            Text("homeview_preparing_subtitle")
                .font(PurgeFont.ui(16, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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

// MARK: - ScanningPulse
//
// SPEC: Small reusable badge dot that pulses while a background scan is
// running. Used inside the duplicates pill to indicate that the count is
// being refreshed in realtime. Designed to be lightweight (no Combine, no
// timers) so it doesn't add render cost during the scan it represents.
private struct ScanningPulse: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.15 : 0.6)
                .opacity(pulse ? 0.0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
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
