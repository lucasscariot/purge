import SwiftUI
import SwiftData
import Pow
@preconcurrency import Photos

struct HomeView: View {
    let photoCount: Int
    let scanProgress: Double?
    let currentPPS: Double?
    var onRescan: () -> Void

    @Environment(ScanEngine.self) private var scanEngine
    @Environment(\.modelContext) private var modelContext
    @Query private var memorySavedRecords: [MemorySaved]

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

    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DotGridBackground(scanProgress: scanProgress, scrollOffset: scrollOffset)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 48) {
                        Color.clear.frame(height: topSafeArea)
                        
                        heroSection
                            .padding(.top, 16)
                        
                        if scanProgress != nil {
                            scanningState
                        } else if dayGroups.isEmpty {
                            emptyState
                        } else {
                            statsSection
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

// MARK: - Dot Grid Background

struct DotGridBackground: View {
    let scanProgress: Double?
    let scrollOffset: CGFloat
    
    @State private var phase: CGFloat = 0
    @State private var touchBounce: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            let baseDotSize: CGFloat = 3.5
            
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PurgeColor.background))
            
            let progress = scanProgress ?? 0
            let isScanning = progress > 0 && progress < 1
            let bounce = touchBounce * 8
            
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let waveOffset = sin((x + y) / 50 + phase) * 0.5 + 0.5
                    let colorIntensity = Color(hex: "E5E3E0")
                    
                    let dotSize: CGFloat
                    let dotColor: Color
                    
                    if isScanning {
                        let animatedWave = waveOffset * CGFloat(progress)
                        dotSize = baseDotSize + animatedWave * 4
                        
                        let saturation = animatedWave * 0.3
                        dotColor = Color(
                            red: 0.898 + saturation * 0.102,
                            green: 0.890 - saturation * 0.047,
                            blue: 0.878 - saturation * 0.125,
                            opacity: 0.6 + animatedWave * 0.4
                        )
                    } else {
                        let touchOffset = sin((x + y) / 30 + scrollOffset / 2) * 0.5 + 0.5
                        let bounceScale = touchBounce > 0 ? touchOffset * bounce : 0
                        dotSize = baseDotSize + CGFloat(waveOffset) * 0.8 + bounceScale
                        dotColor = touchBounce > 0 
                            ? Color(hex: "E5E3E0").opacity(0.5 + touchOffset * 0.5 + touchOffset * 0.3)
                            : colorIntensity.opacity(0.5 + waveOffset * 0.5)
                    }
                    
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    y += spacing
                }
                x += spacing
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onChange(of: scrollOffset) { oldValue, newValue in
            if abs(newValue - oldValue) > 1 {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    touchBounce = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        touchBounce = 0
                    }
                }
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