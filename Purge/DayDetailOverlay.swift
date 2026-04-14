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
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    // Group photos by their near-duplicate sets
    private var organizedPhotos: [[DummyPhoto]] {
        let nearDupIds = Set(dayGroup.nearDuplicateSets.flatMap { $0 })
        
        // First, group near duplicates by their set
        var nearDuplicateGroups: [[DummyPhoto]] = []
        for set in dayGroup.nearDuplicateSets {
            let photosInSet = dayGroup.photos.filter { set.contains($0.localIdentifier ?? "") }
            if !photosInSet.isEmpty {
                nearDuplicateGroups.append(photosInSet)
            }
        }
        
        // Then get regular photos (not in any near-duplicate set)
        let regularPhotos = dayGroup.photos.filter { photo in
            guard let id = photo.localIdentifier else { return true }
            return !nearDupIds.contains(id)
        }
        
        // Combine: near duplicates first, then regular photos
        var result: [[DummyPhoto]] = []
        result.append(contentsOf: nearDuplicateGroups)
        if !regularPhotos.isEmpty {
            result.append(regularPhotos)
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
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(0..<organizedPhotos.count, id: \.self) { index in
                            let photoGroup = organizedPhotos[index]

                            // Add separator between near-duplicate groups
                            if index > 0 && hasNearDuplicates {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(photoGroup) { photo in
                                    photoCard(photo: photo)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 60)
                    .padding(.bottom, 120)
                }
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
        let isNearDup = isNearDuplicate(photo)
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
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.blue))
                    }
                }
            
            if isNearDup {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.orange.opacity(0.9)))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
                    Text("Remove\(selectedPhotos.isEmpty || !isSelectionMode ? "" : " (\(selectedPhotos.count))")")
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
                Text("Close")
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