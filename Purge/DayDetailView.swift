import SwiftUI
import UIKit
import Photos

// MARK: - Natural Pinchable Tile

private struct NaturalPinchableTile: View {
    let localIdentifier: String
    let placeholder: Color
    let isSelected: Bool
    let groupColor: Color?
    let groupIndex: Int?
    let cornerRadius: CGFloat
    let rotation: Double
    let onTap: () -> Void
    var onZoomChange: ((Bool) -> Void)? = nil

    @State private var currentScale: CGFloat = 1.0
    @State private var isPinching: Bool = false

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    onZoomChange?(true)
                }
                currentScale = max(1.0, value)
            }
            .onEnded { _ in
                isPinching = false
                onZoomChange?(false)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    currentScale = 1.0
                }
            }
    }

    var body: some View {
        AsyncPhotoImage(localIdentifier: localIdentifier, placeholder: placeholder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, PurgeColor.primary)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let color = groupColor, let idx = groupIndex {
                    Text("\(idx + 1)")
                        .font(PurgeFont.mono(9, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 20, height: 20)
                        .background(color)
                        .clipShape(Circle())
                        .padding(5)
                }
            }
            .overlay {
                if isSelected {
                    PurgeColor.primary.opacity(0.45)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .stickerShadow()
            .rotationEffect(.degrees(rotation))
            .scaleEffect(currentScale, anchor: .center)
            .zIndex(isPinching ? 100 : 0)
            .gesture(pinchGesture)
            .onTapGesture { onTap() }
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
    let dayId: UUID

    @Environment(\.dismiss)   private var dismiss
    @Environment(ScanEngine.self) private var scanEngine
    @Environment(\.modelContext) private var modelContext

    @State private var selectedIDs: Set<String> = []
    @State private var zoomingTileID: String? = nil
    private var isDeleting: Bool { scanEngine.isDeleting }

    private var day: DayGroup? {
        scanEngine.dayGroups.first { $0.id == dayId }
    }

    private static let groupColors: [Color] = [
        PurgeColor.warning,
        PurgeColor.teal,
        Color(hex: "FF6B00"),
        Color(hex: "CC00FF"),
        Color(hex: "00AAFF"),
    ]

    private var dupGroupMap: [String: (Int, Color)] {
        guard let day else { return [:] }
        var map: [String: (Int, Color)] = [:]
        for (i, group) in day.nearDuplicateSets.enumerated() {
            let color = Self.groupColors[i % Self.groupColors.count]
            for id in group { map[id] = (i, color) }
        }
        return map
    }

    private var selectedMB: Int {
        (day?.photos ?? [])
            .filter { selectedIDs.contains($0.localIdentifier ?? "") }
            .reduce(0) { $0 + $1.sizeMB }
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy"
        guard let date = day?.date else { return "" }
        return f.string(from: date).uppercased()
    }

    private var locationDisplayString: String? {
        guard let day else { return nil }
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
        if let day {
            ZStack(alignment: .top) {
                DotGridBackground(scanProgress: nil)

                ScrollView {
                    VStack(spacing: 32) {
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

                        Color.clear.frame(height: 120)
                    }
                }
                .scrollIndicators(.hidden)

                VStack {
                    Spacer()
                    footer
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden(false)
        } else {
            ZStack { Color.black }
        }
    }

    // MARK: - Quick Action Bar

    private var quickActionBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(day?.nearDuplicateSets.count ?? 0) NEAR-DUP GROUPS")
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
        guard let day else { return }
        var newSelection = selectedIDs
        for group in day.nearDuplicateSets {
            for id in group.dropFirst() { newSelection.insert(id) }
        }
        withAnimation(.easeInOut(duration: 0.2)) { selectedIDs = newSelection }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func clusterSection(index: Int, group: [String]) -> some View {
        let color = Self.groupColors[index % Self.groupColors.count]
        let clusterPhotos = (day?.photos ?? []).filter { (photo: DummyPhoto) in
            group.contains(photo.localIdentifier ?? "")
        }
        return VStack(alignment: .center, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Group \(index + 1)")
                        .font(PurgeFont.display(20, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                    
                    Text("\(group.count) similar photos")
                        .font(PurgeFont.ui(14, weight: .medium))
                        .foregroundStyle(PurgeColor.textMuted)
                }
                Spacer()
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PurgeColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white, lineWidth: 3))
            .stickerShadow()
            .rotationEffect(.degrees(Double(index % 2 == 0 ? -1 : 1)))
            .padding(.horizontal, 16)

            StaggeredGrid(clusterPhotos, columns: 2, spacing: 16, itemSize: CGSize(width: 160, height: 200)) { photo in
                let id = photo.localIdentifier ?? ""
                let isSelected = selectedIDs.contains(id)
                let placeholder = photo.color

                NaturalPinchableTile(
                    localIdentifier: id,
                    placeholder: placeholder,
                    isSelected: isSelected,
                    groupColor: color,
                    groupIndex: index,
                    cornerRadius: 12,
                    rotation: Double(abs(id.hashValue) % 9) - 4.0,
                    onTap: { toggleSelection(for: id) },
                    onZoomChange: { isZooming in
                        if isZooming { zoomingTileID = id }
                        else if zoomingTileID == id { zoomingTileID = nil }
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .zIndex(group.contains(zoomingTileID ?? "") ? 100 : 0)
    }

    private func singlesSection(singles: [DummyPhoto]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Singles")
                        .font(PurgeFont.display(20, weight: .bold))
                        .foregroundStyle(PurgeColor.text)
                    
                    Text("\(singles.count) unique photos")
                        .font(PurgeFont.ui(14, weight: .medium))
                        .foregroundStyle(PurgeColor.textMuted)
                }
                Spacer()
                
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PurgeColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white, lineWidth: 3))
            .stickerShadow()
            .rotationEffect(.degrees(1))
            .padding(.horizontal, 16)

            FlowLayout(spacing: 16) {
                ForEach(singles) { photo in
                    let id = photo.localIdentifier ?? ""
                    let isSelected = selectedIDs.contains(id)

                    NaturalPinchableTile(
                        localIdentifier: id,
                        placeholder: photo.color,
                        isSelected: isSelected,
                        groupColor: nil,
                        groupIndex: nil,
                        cornerRadius: 8,
                        rotation: Double(abs(id.hashValue) % 9) - 4.0,
                        onTap: { toggleSelection(for: id) },
                        onZoomChange: { isZooming in
                            if isZooming { zoomingTileID = id }
                            else if zoomingTileID == id { zoomingTileID = nil }
                        }
                    )
                    .frame(width: 120, height: 120)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .zIndex(singles.contains(where: { $0.localIdentifier == zoomingTileID }) ? 100 : 0)
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

                Button(action: confirmDeletion) {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(isDeleting ? "DELETING…" : "TRASH \(selectedIDs.count)")
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
                            .fill(isDeleting ? PurgeColor.primary.opacity(0.6) : PurgeColor.primary)
                            .stickerShadow()
                    )
                    .rotationEffect(.degrees(1))
                }
                .buttonStyle(ScrapbookButtonStyle())
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func confirmDeletion() {
        guard !scanEngine.isDeleting, !selectedIDs.isEmpty else { return }
        scanEngine.trashItems(
            identifiers: selectedIDs,
            context: modelContext,
            dismissCallback: { dismiss() }
        )
    }
}

// MARK: - Preview
#Preview {
    DayDetailView(dayId: DayGroup.sampleDays[0].id)
}
