import Foundation

let path = "Purge/HomeView.swift"
var content = try String(contentsOfFile: path)

// 1. Replace navBar in ZStack
content = content.replacingOccurrences(of: """
                .scrollIndicators(.hidden)
                
                navBar
                
                VStack {
""", with: """
                .scrollIndicators(.hidden)
                
                VStack {
""")

// 2. Replace ScrollView content
content = content.replacingOccurrences(of: """
                ScrollView {
                    VStack(spacing: 48) {
                        Color.clear.frame(height: 60)
                        
                        heroSection
""", with: """
                ScrollView {
                    VStack(spacing: 48) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: topSafeArea)
                            scrollingHeader
                        }
                        
                        heroSection
""")

// 3. Replace navBar definition with scrollingHeader
content = content.replacingOccurrences(of: """
    // MARK: - Nav Bar
    
    private var navBar: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topSafeArea)
            
            HStack {
""", with: """
    // MARK: - Scrolling Header
    
    private var scrollingHeader: some View {
        VStack(spacing: 0) {
            HStack {
""")

content = content.replacingOccurrences(of: """
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
        .background(
            PurgeColor.background.opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
    }
""", with: """
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
""")

// 4. Remove topSafeArea padding from heroSection
content = content.replacingOccurrences(of: """
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topSafeArea)
    }
""", with: """
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
""")

try content.write(toFile: path, atomically: true, encoding: .utf8)
