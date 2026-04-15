import SwiftUI
import Photos

struct DayDetailOverlay: View {
    let dayGroup: DayGroup
    let onDismiss: () -> Void
    var onRemovePhotos: (([String]) -> Void)?
    
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var isSelectionMode = false
    @State private var selectedPhotos: Set<String> = []
    @State private var isAnyPhotoZooming = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    // Group photos by their near-duplicate sets
    private var organizedGroups: [(isNearDuplicate: Bool, photos: [DummyPhoto])] {
        let nearDupIds = Set(dayGroup.nearDuplicateSets.flatMap { $0 })
        
        var result: [(Bool, [DummyPhoto])] = []
        for set in dayGroup.nearDuplicateSets {
            let photosInSet = dayGroup.photos.filter { set.contains($0.localIdentifier ?? "") }
            if !photosInSet.isEmpty {
                result.append((true, photosInSet))
            }
        }
        
        let regularPhotos = dayGroup.photos.filter { photo in
            guard let id = photo.localIdentifier else { return true }
            return !nearDupIds.contains(id)
        }
        
        if !regularPhotos.isEmpty {
            result.append((false, regularPhotos))
        }
        return result
    }
    
    private var hasNearDuplicates: Bool {
        dayGroup.nearDuplicateCount > 0
    }
    
    private func isNearDuplicate(_ photo: DummyPhoto) -> Bool {
        guard let id = photo.localIdentifier else { return false }
        return dayGroup.nearDuplicateSets.flatMap { $0 }.contains(id)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date).uppercased()
    }
    
    private var isAllSelected: Bool {
        let allIds = dayGroup.photos.compactMap { $0.localIdentifier }
        return !allIds.isEmpty && allIds.allSatisfy { selectedPhotos.contains($0) }
    }
    
    private func selectAll() {
        withAnimation {
            let allIds = dayGroup.photos.compactMap { $0.localIdentifier }
            if isAllSelected {
                selectedPhotos.subtract(allIds)
                if selectedPhotos.isEmpty {
                    isSelectionMode = false
                }
            } else {
                isSelectionMode = true
                selectedPhotos.formUnion(allIds)
            }
        }
    }
    
    private func isGroupSelected(_ group: [DummyPhoto]) -> Bool {
        let groupIds = group.compactMap { $0.localIdentifier }
        return !groupIds.isEmpty && groupIds.allSatisfy { selectedPhotos.contains($0) }
    }
    
    private func selectGroup(_ group: [DummyPhoto]) {
        withAnimation {
            let groupIds = group.compactMap { $0.localIdentifier }
            if isGroupSelected(group) {
                selectedPhotos.subtract(groupIds)
                if selectedPhotos.isEmpty {
                    isSelectionMode = false
                }
            } else {
                isSelectionMode = true
                selectedPhotos.formUnion(groupIds)
            }
        }
    }
    
    private func applyAISelection() {
        var toSelect: Set<String> = []
        for set in dayGroup.nearDuplicateSets {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: set, options: nil)
            var assetList: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in assetList.append(asset) }
            
            let sorted = assetList.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                return (a.creationDate ?? Date.distantPast) > (b.creationDate ?? Date.distantPast)
            }
            
            guard let best = sorted.first else { continue }
            let keepId = best.localIdentifier
            
            for id in set {
                if id == keepId { continue }
                if let asset = assetList.first(where: { $0.localIdentifier == id }), asset.isFavorite {
                    continue
                }
                toSelect.insert(id)
            }
        }
        
        withAnimation {
            isSelectionMode = true
            selectedPhotos.formUnion(toSelect)
        }
    }
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Text(formattedDate(dayGroup.date))
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 16) {
                                Button(action: selectAll) {
                                        Text(isAllSelected ? NSLocalizedString("daydetailoverlay_unselect_all", comment: "") : NSLocalizedString("daydetailoverlay_select_all", comment: ""))
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(isAllSelected ? .primary : .red)
                                }
                                
                                if hasNearDuplicates {
                                    Button(action: applyAISelection) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "wand.and.stars")
                                            Text("daydetailoverlay_ai_select")
                                        }
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                        .padding(.top, 80)
                        
                        LazyVStack(spacing: 24) {
                            ForEach(0..<organizedGroups.count, id: \.self) { index in
                                let group = organizedGroups[index]

                                VStack(spacing: 12) {
                                    if group.isNearDuplicate {
                                        HStack {
                                            Image(systemName: "rectangle.stack.fill")
                                                .foregroundStyle(.orange)
                                            Text("daydetailoverlay_similar_photos")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Button(action: { selectGroup(group.photos) }) {
                                                let selected = isGroupSelected(group.photos)
                                                    Text(selected ? NSLocalizedString("daydetailoverlay_unselect_group", comment: "") : NSLocalizedString("daydetailoverlay_select_group", comment: ""))
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(selected ? .primary : .red)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    } else if index > 0 && hasNearDuplicates {
                                        Divider()
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 8)
                                    }

                                    LazyVGrid(columns: columns, spacing: 8) {
                                        ForEach(group.photos) { photo in
                                            photoCard(photo: photo)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 120)
                    }
                }
                .scrollDisabled(isAnyPhotoZooming)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: 15)
                )

                VStack {
                    Spacer()
                    actionButtons
                        .padding(.bottom, 40)
                }
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismissWithAnimation()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
    }
    
    @ViewBuilder
    private func photoCard(photo: DummyPhoto) -> some View {
        let isSelected = selectedPhotos.contains(photo.localIdentifier ?? "")
        
        ZStack {
            PinchablePhotoCard(
                localIdentifier: photo.localIdentifier ?? "",
                onTap: {
                    if isSelectionMode {
                        toggleSelection(photo)
                    } else {
                        withAnimation {
                            isSelectionMode = true
                            toggleSelection(photo)
                        }
                    }
                },
                onZoomChanged: { isZooming in
                    isAnyPhotoZooming = isZooming
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.red : Color.clear, lineWidth: 3)
                .overlay {
                    if isSelected {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.red))
                    }
                }
        }
        .frame(width: 180, height: 180)
        .contentShape(Rectangle())
        .onTapGesture {
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    withAnimation {
                        isSelectionMode = true
                        toggleSelection(photo)
                    }
                }
        )
    }
    
    private func toggleSelection(_ photo: DummyPhoto) {
        guard let id = photo.localIdentifier else { return }
        if selectedPhotos.contains(id) {
            selectedPhotos.remove(id)
        } else {
            selectedPhotos.insert(id)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: removeSelectedPhotos) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text(selectedPhotos.isEmpty || !isSelectionMode ? NSLocalizedString("daydetailoverlay_remove", comment: "") : String(format: NSLocalizedString("daydetailoverlay_remove_count", comment: ""), selectedPhotos.count))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 150, height: 44)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotos.isEmpty || !isSelectionMode)
            .opacity((selectedPhotos.isEmpty || !isSelectionMode) ? 0.5 : 1.0)
            
            closeButton
        }
    }
    
    private func removeSelectedPhotos() {
        let idsToRemove = Array(selectedPhotos)
        onRemovePhotos?(idsToRemove)
        
        withAnimation {
            isSelectionMode = false
            selectedPhotos.removeAll()
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            dragOffset = 400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
    
    private var closeButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                Text("daydetailoverlay_close")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(width: 120, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}