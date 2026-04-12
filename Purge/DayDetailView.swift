import SwiftUI
import Photos

// MARK: - Photo tile with group badge
private struct GroupPhotoTile: View {
    let localIdentifier: String
    let placeholder: Color
    let isSelected: Bool
    let groupColor: Color?
    let groupIndex: Int?

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Photo / placeholder
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(placeholder)
                }
            }
            .clipped()

            // Red overlay when selected
            if isSelected {
                PurgeColor.primary.opacity(0.45)
            }

            // Near-dup group badge — bottom-trailing, inside the tile
            if let color = groupColor, let idx = groupIndex {
                Text("\(idx + 1)")
                    .font(PurgeFont.mono(9, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(color)
                    .clipShape(Circle())
                    .padding(5)
            }

            // Selection check — top-trailing
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, PurgeColor.primary)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .task(id: localIdentifier) { await loadImage() }
    }

    private func loadImage() async {
        guard let asset = PHAsset
            .fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            .firstObject
        else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.isSynchronous = false

        let size = CGSize(width: 400, height: 400)

        let stream = AsyncStream<UIImage> { cont in
            nonisolated(unsafe) var requestID: PHImageRequestID = PHInvalidImageRequestID
            requestID = PHImageManager.default().requestImage(
                for: asset, targetSize: size,
                contentMode: .aspectFill, options: options
            ) { img, info in
                if let img { cont.yield(img) }
                let isDone = (info?[PHImageResultIsDegradedKey] as? Bool) == false
                if isDone { cont.finish() }
            }
            cont.onTermination = { _ in
                if requestID != PHInvalidImageRequestID {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
            }
        }
        for await img in stream { image = img }
    }
}

// MARK: - Scrapbook Note Shape
struct ScrapbookNoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.01, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.01))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.04))
        path.addLine(to: CGPoint(x: w * 0.99, y: h * 0.02))
        
        path.addLine(to: CGPoint(x: w * 0.97, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 1.0, y: h * 0.8))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.98))
        
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.99))
        path.addLine(to: CGPoint(x: w * 0.02, y: h * 0.96))
        
        path.addLine(to: CGPoint(x: w * 0.04, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.0, y: h * 0.3))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - DayDetailView
struct DayDetailView: View {
    let day: DayGroup

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var showComplete = false

    // Group colour palette — deterministic per index
    private static let groupColors: [Color] = [
        PurgeColor.warning,
        PurgeColor.teal,
        Color(hex: "FF6B00"),
        Color(hex: "CC00FF"),
        Color(hex: "00AAFF"),
    ]

    private var dupGroupMap: [String: (Int, Color)] {
        var map: [String: (Int, Color)] = [:]
        for (i, group) in day.nearDuplicateSets.enumerated() {
            let color = Self.groupColors[i % Self.groupColors.count]
            for id in group { map[id] = (i, color) }
        }
        return map
    }

    private var selectedMB: Int {
        day.photos
            .filter { selectedIDs.contains($0.localIdentifier ?? "") }
            .reduce(0) { $0 + $1.sizeMB }
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy"
        return f.string(from: day.date).uppercased()
    }

    private var locationDisplayString: String? {
        if !day.location.isEmpty {
            return day.location
        } else if let lat = day.representativeLat, let lng = day.representativeLng {
            let latStr = String(format: "%.1f°%@", abs(lat), lat >= 0 ? "N" : "S")
            let lngStr = String(format: "%.1f°%@", abs(lng), lng >= 0 ? "E" : "W")
            return "\(latStr), \(lngStr)"
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            DotGridBackground()

            ScrollView {
                VStack(spacing: 32) {
                    // Header and action card are now in the ScrollView
                    customHeader
                    
                    if !day.nearDuplicateSets.isEmpty {
                        quickActionBar
                    }
                    
                    ForEach(Array(day.nearDuplicateSets.enumerated()), id: \.offset) { i, group in
                        clusterSection(index: i, group: group)
                    }
                    
                    let singles = day.photos.filter { photo in
                        let id = photo.localIdentifier ?? ""
                        return dupGroupMap[id] == nil
                    }
                    
                    if !singles.isEmpty {
                        singlesSection(singles: singles)
                    }
                    
                    Color.clear.frame(height: 120) // clearance for footer
                }
            }
            .scrollIndicators(.hidden)
            
            // Footer floats over grid
            VStack {
                Spacer()
                footer
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(false)
        .animation(.easeInOut(duration: 0.25), value: showComplete)
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        HStack(alignment: .top) {
            // Date / location sticker
            VStack(alignment: .leading, spacing: 4) {
                if let loc = locationDisplayString {
                    Text(loc.uppercased())
                        .font(PurgeFont.mono(16, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .lineLimit(1)
                    Text(dateLabel)
                        .font(PurgeFont.mono(12, weight: .semibold))
                        .foregroundStyle(PurgeColor.textMuted)
                } else {
                    Text(dateLabel)
                        .font(PurgeFont.mono(16, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PurgeColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white, lineWidth: 3))
            .stickerShadow()
            .rotationEffect(.degrees(-2))

            Spacer()

            // Photo count pill
            HStack(spacing: 4) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(PurgeColor.text)
                Text("\(day.photoCount)")
                    .font(PurgeFont.mono(14, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PurgeColor.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2))
            .stickerShadow()
            .rotationEffect(.degrees(3))
        }
        .padding(.horizontal, 16)
    }


    // MARK: - Quick Action Bar
    
    private var quickActionBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 16) {
                // Text
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(day.nearDuplicateSets.count) NEAR-DUP GROUPS")
                        .font(PurgeFont.display(18, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                        .rotationEffect(.degrees(-1))
                    
                    Text("Tap a photo to select it for deletion, or use auto-select.")
                        .font(PurgeFont.mono(12))
                        .foregroundStyle(PurgeColor.text.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .rotationEffect(.degrees(0.5))
                }

                Spacer()

            // Auto-select button
                Button(action: markAllNearDupes) {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(PurgeColor.surface)
                        Text("AUTO")
                            .font(PurgeFont.mono(10, weight: .bold))
                            .foregroundStyle(PurgeColor.surface)
                    }
                    .frame(width: 56, height: 56)
                    .background(PurgeColor.text)
                    .clipShape(ScrapbookNoteShape())
                    .stickerShadow()
                    .rotationEffect(.degrees(3))
                }
                .buttonStyle(ScrapbookButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ScrapbookNoteShape()
                    .fill(PurgeColor.mustard)
                    .stickerShadow()
            )
            .rotationEffect(.degrees(-2))
            
            Rectangle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 45, height: 14)
                .rotationEffect(.degrees(-6))
                .offset(y: -6)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func markAllNearDupes() {
        var newSelection = selectedIDs
        for group in day.nearDuplicateSets {
            for id in group.dropFirst() { newSelection.insert(id) }
        }
        withAnimation(.easeInOut(duration: 0.2)) { selectedIDs = newSelection }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func clusterSection(index: Int, group: [String]) -> some View {
        let color = Self.groupColors[index % Self.groupColors.count]
        let clusterPhotos = day.photos.filter { group.contains($0.localIdentifier ?? "") }
        return VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text("GROUP \(index + 1)")
                    .font(PurgeFont.mono(11, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2))
                    .stickerShadow()
                    .rotationEffect(.degrees(-1))
                
                Text("— \(group.count) photos")
                    .font(PurgeFont.mono(12))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 16)
            
            StaggeredGrid(clusterPhotos, columns: 2, spacing: 16) { photo in
                let id = photo.localIdentifier ?? ""
                let isSelected = selectedIDs.contains(id)
                let placeholder = photo.color
                
                GroupPhotoTile(
                    localIdentifier: id,
                    placeholder: placeholder,
                    isSelected: isSelected,
                    groupColor: color,
                    groupIndex: index
                )
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white, lineWidth: 4))
                .stickerShadow()
                .rotationEffect(.degrees(Double(abs(id.hashValue) % 9) - 4.0))
                .onTapGesture {
                    toggleSelection(for: id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func singlesSection(singles: [DummyPhoto]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SINGLES")
                    .font(PurgeFont.mono(11, weight: .bold))
                    .foregroundStyle(PurgeColor.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(PurgeColor.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2))
                    .stickerShadow()
                    .rotationEffect(.degrees(1))
                
                Text("— \(singles.count) photos")
                    .font(PurgeFont.mono(12))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 16)
            
            FlowLayout(spacing: 16) {
                ForEach(singles) { photo in
                    let id = photo.localIdentifier ?? ""
                    let isSelected = selectedIDs.contains(id)
                    
                    GroupPhotoTile(
                        localIdentifier: id,
                        placeholder: photo.color,
                        isSelected: isSelected,
                        groupColor: nil,
                        groupIndex: nil
                    )
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 4))
                    .stickerShadow()
                    .rotationEffect(.degrees(Double(abs(id.hashValue) % 9) - 4.0))
                    .onTapGesture {
                        toggleSelection(for: id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func toggleSelection(for id: String) {
        guard !id.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            if selectedIDs.contains(id) { selectedIDs.remove(id) }
            else                         { selectedIDs.insert(id) }
        }
    }

    // MARK: - Footer
    
    private var footer: some View {
        HStack(spacing: 16) {
            if selectedIDs.isEmpty {
                Spacer()
                // Single skip button as a sticker
                Button { dismiss() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("SKIP DAY")
                            .font(PurgeFont.mono(14, weight: .bold))
                    }
                    .foregroundStyle(PurgeColor.textMuted)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(PurgeColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white, lineWidth: 3))
                    .stickerShadow()
                    .rotationEffect(.degrees(1))
                }
                .buttonStyle(ScrapbookButtonStyle())
                Spacer()
            } else {
                // Clear — left half
                Button {
                    withAnimation(.spring(duration: 0.25)) { selectedIDs = [] }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("CLEAR")
                            .font(PurgeFont.mono(14, weight: .bold))
                    }
                    .foregroundStyle(PurgeColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        ScrapbookNoteShape()
                            .fill(PurgeColor.surface)
                            .stickerShadow()
                    )
                    .rotationEffect(.degrees(-1))
                }
                .buttonStyle(ScrapbookButtonStyle())

                Spacer()

                // Trash — right half, solid red
                Button(action: confirmDeletion) {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("TRASH \(selectedIDs.count)")
                                .font(PurgeFont.mono(14, weight: .bold))
                        }
                        Text("\(selectedMB) MB freed")
                            .font(PurgeFont.mono(10))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        ScrapbookNoteShape()
                            .fill(PurgeColor.primary)
                            .stickerShadow()
                    )
                    .rotationEffect(.degrees(1))
                }
                .buttonStyle(ScrapbookButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func confirmDeletion() {
        let idsToDelete = Array(selectedIDs)
        PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        } completionHandler: { _, _ in }
        withAnimation { showComplete = true }
    }
}

// MARK: - Preview
#Preview {
    DayDetailView(day: DayGroup.sampleDays[0])
}
