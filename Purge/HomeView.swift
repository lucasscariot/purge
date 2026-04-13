import SwiftUI
@preconcurrency import Photos

// MARK: - HomeView

struct HomeView: View {
    let photoCount: Int
    let scanProgress: Double?
    let currentPPS: Double?
    var onRescan: () -> Void

    @Environment(ScanEngine.self) private var scanEngine
    @State private var selectedDay: DayGroup?

    private var dayGroups: [DayGroup] {
        scanEngine.dayGroups
    }

    private var dynamicPhotoCount: Int {
        scanEngine.photoCount
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DotGridBackground()
                
                ScrollView {
                    VStack(spacing: 48) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: topSafeArea)
                            scrollingHeader
                        }
                        .padding(.top, -32)
                        
                        heroSection
                            .padding(.top, 16)
                        
                        onThisDaySection
                            .padding(.top, -16)
                        
                        if scanProgress != nil {
                            scanningState
                        } else if dayGroups.isEmpty {
                            emptyState
                        } else {
                            let columns = [
                                GridItem(.flexible(), spacing: 24),
                                GridItem(.flexible(), spacing: 24)
                            ]
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(dayGroups.sorted(by: { $0.date > $1.date })) { day in
                                    DaySection(day: day, selectedDay: $selectedDay)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Color.clear.frame(height: 120)
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
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedDay) { day in
                DayDetailView(dayId: day.id)
            }
        }
    }
    
    // MARK: - Scrolling Header
    
    private var scrollingHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                
                if let progress = scanProgress {
                    Text("Scanning \(Int(max(1, progress * 100)))%")
                        .font(PurgeFont.ui(13, weight: .bold))
                        .foregroundStyle(PurgeColor.textMuted)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
            
            if let progress = scanProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        PurgeColor.text.opacity(0.05)
                        PurgeColor.mustard
                            .frame(width: geo.size.width * max(0.01, progress))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: progress)
                    }
                }
                .frame(height: 3)
                .transition(.opacity)
            }
        }
    }
    
    private var topSafeArea: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
    }
    
    // MARK: - On This Day
    
    @ViewBuilder
    private var onThisDaySection: some View {
        let currentMonth = Calendar.current.component(.month, from: Date())
        let currentDay = Calendar.current.component(.day, from: Date())
        let currentYear = Calendar.current.component(.year, from: Date())
        
        let pastDays = dayGroups.filter { group in
            let month = Calendar.current.component(.month, from: group.date)
            let day = Calendar.current.component(.day, from: group.date)
            let year = Calendar.current.component(.year, from: group.date)
            return month == currentMonth && day == currentDay && year < currentYear
        }
        
        if !pastDays.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("On This Day")
                    .font(PurgeFont.display(24, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                    .padding(.horizontal, 24)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(pastDays.sorted(by: { Calendar.current.component(.year, from: $0.date) > Calendar.current.component(.year, from: $1.date) }), id: \.id) { group in
                            let year = Calendar.current.component(.year, from: group.date)
                            
                            Button(action: {
                                selectedDay = group
                            }) {
                                VStack(alignment: .center, spacing: 12) {
                                    PhotoPileView(photos: group.photos, seed: group.id.hashValue)
                                        .stickerShadow()
                                        .rotationEffect(.degrees(Double((year * 7) % 11) - 5.0))
                                    
                                    Text(String(year))
                                        .font(PurgeFont.mono(14, weight: .bold))
                                        .foregroundStyle(PurgeColor.text)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Scrapbook")
                .font(PurgeFont.display(42, weight: .bold))
                .foregroundStyle(PurgeColor.text)
            
            Text("\(formatted(dynamicPhotoCount)) photos waiting to be organized")
                .font(PurgeFont.ui(16, weight: .medium))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Rescan Button
    
    private var rescanButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        .disabled(scanProgress != nil)
        .opacity(scanProgress != nil ? 0.5 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: scanProgress != nil)
    }
    
    // MARK: - Placeholders
    
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().tint(PurgeColor.mustard)
                .scaleEffect(1.5)
            Text("Gathering your memories…")
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
}

// MARK: - Day Section

struct DaySection: View {
    let day: DayGroup
    @Binding var selectedDay: DayGroup?
    @State private var isPressed = false
    
    private var locationDisplayString: String? {
        if !day.location.isEmpty { return day.location }
        if let lat = day.representativeLat, let lng = day.representativeLng {
            return String(format: "%.1f°%@, %.1f°%@", abs(lat), lat >= 0 ? "N" : "S", abs(lng), lng >= 0 ? "E" : "W")
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PinchablePhotoStack(photos: day.photos, seed: day.id.hashValue) {
                selectedDay = day
            }
            .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(day.date))
                    .font(PurgeFont.display(16, weight: .bold))
                    .foregroundStyle(PurgeColor.text)

                if let locationText = locationDisplayString {
                    Text(locationText)
                        .font(PurgeFont.mono(10))
                        .foregroundStyle(PurgeColor.textMuted)
                }
            }
            .padding(.horizontal, 4)
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = pressing
            }
        })
        .scaleEffect(isPressed ? 0.96 : 1.0)
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}

// MARK: - Photo Pile View

struct PhotoPileView: View {
    let photos: [DummyPhoto]
    let seed: Int
    
    private struct PilePattern {
        let offsets: [CGPoint]
        let rotations: [Double]
    }
    
    private let patterns: [PilePattern] = [
        PilePattern(offsets: [CGPoint(x: -8, y: -4), CGPoint(x: 8, y: 4)], rotations: [-4, 3]),
        PilePattern(offsets: [CGPoint(x: -6, y: -6), CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 6)], rotations: [-5, 0, 4]),
        PilePattern(offsets: [CGPoint(x: -8, y: -4), CGPoint(x: -4, y: 4), CGPoint(x: 4, y: -4), CGPoint(x: 8, y: 4)], rotations: [-6, -2, 2, 5])
    ]
    
    var body: some View {
        ZStack {
            let patternIndex = abs(seed) % patterns.count
            let pattern = patterns[patternIndex]
            let displayPhotos = Array(photos.prefix(pattern.offsets.count + 1))
            
            ForEach(0..<displayPhotos.count, id: \.self) { i in
                let index = displayPhotos.count - 1 - i
                PilePhotoView(photo: displayPhotos[index])
                    .rotationEffect(.degrees(index < pattern.rotations.count ? pattern.rotations[index] : 0))
                    .offset(x: index < pattern.offsets.count ? pattern.offsets[index].x : 0, 
                            y: index < pattern.offsets.count ? pattern.offsets[index].y : 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 140, height: 140)
    }
}

struct PilePhotoView: View {
    let photo: DummyPhoto
    @State private var loadedImage: UIImage?
    @State private var asset: PHAsset?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(photo.color)
            
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
        )
        .shadow(color: PurgeColor.text.opacity(0.1), radius: 2, x: 0, y: 1)
        .task(id: photo.localIdentifier) {
            guard let localId = photo.localIdentifier else { return }
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
            self.asset = fetchResult.firstObject
            if let asset = self.asset {
                ImageCache.shared.requestImage(for: asset, targetSize: CGSize(width: 256, height: 256)) { image in
                    self.loadedImage = image
                }
            }
        }
        .onDisappear {
            if let asset = asset {
                ImageCache.shared.cancelRequest(for: asset)
            }
        }
    }
}

private final class SendableBox: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()
    
    init(_ value: Bool) { self._value = value }
    
    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !_value {
            _value = true
            return true
        }
        return false
    }
}

// MARK: - Dot Grid Background

struct DotGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            let dotSize: CGFloat = 2.5
            let dotColor = Color(hex: "E5E3E0")
            
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PurgeColor.background))
            
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    y += spacing
                }
                x += spacing
            }
        }
        .ignoresSafeArea()
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
