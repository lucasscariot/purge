import SwiftUI
import Photos
import UIKit

struct NetworkPhotoImage: View {

    let localIdentifier: String
    let placeholder: Color

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(placeholder)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .tint(Color.white.opacity(0.4))
                                .scaleEffect(0.7)
                        }
                    }
            }
        }
        .clipped()
        .task(id: localIdentifier) {
            guard let asset = PHAsset
                .fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
                .firstObject
            else { return }

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true     // pull from iCloud when needed
            options.deliveryMode = .opportunistic     // degraded first, then full quality
            options.isSynchronous = false

            // 600pt → crisp on 3× displays without loading the full original
            let size = CGSize(width: 600, height: 600)

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

            for await img in stream {
                isLoading = false
                image = img
            }
        }
    }
}

// MARK: - Review Session

struct ReviewSessionView: View {
    let cluster: PhotoCluster
    @Environment(\.dismiss) private var dismiss

    @State private var markedForDeletion: Set<String> = []
    @State private var showComplete = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var markedPhotos: [DummyPhoto] {
        cluster.photos.filter { photo in
            guard let id = photo.localIdentifier else { return false }
            return markedForDeletion.contains(id)
        }
    }
    private var selectedCount: Int { markedPhotos.count }
    private var selectedMB:    Int { markedPhotos.reduce(0) { $0 + $1.sizeMB } }

    var body: some View {
        ZStack {
            PurgeColor.background.ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    keptCount: cluster.photoCount - selectedCount,
                    trashedCount: selectedCount,
                    favouritedCount: 0,
                    spaceSavedMB: selectedMB,
                    onDone: { dismiss() }
                )
            } else {
                VStack(spacing: 0) {
                    header
                    instructionBar
                    photoGrid
                    footer
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Text("< BACK")
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(cluster.label.replacingOccurrences(of: " ", with: "_"))
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                Text("\(cluster.photoCount) PHOTOS")
                    .font(PurgeFont.mono(9))
                    .foregroundStyle(PurgeColor.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(PurgeColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
    }

    // MARK: - Instruction bar

    private var instructionBar: some View {
        HStack(spacing: 8) {
            StatusDot(color: PurgeColor.primary, size: 6)
            Text("TAP TO MARK FOR DELETION")
                .font(PurgeFont.mono(9, weight: .semibold))
                .foregroundStyle(PurgeColor.textMuted)
            Spacer()
            if selectedCount > 0 {
                Text("\(selectedCount)_SELECTED · \(selectedMBLabel)")
                    .font(PurgeFont.mono(9, weight: .semibold))
                    .foregroundStyle(PurgeColor.primary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PurgeColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: selectedCount)
    }

    // MARK: - Grid

    private var photoGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cluster.photos) { photo in
                    photoCell(photo: photo)
                }
            }
        }
    }

    private func photoCell(photo: DummyPhoto) -> some View {
        let isMarked = photo.localIdentifier.map { markedForDeletion.contains($0) } ?? false

        return ZStack(alignment: .topTrailing) {
            // Photo
            ZStack(alignment: .bottomLeading) {
                if let id = photo.localIdentifier {
                    NetworkPhotoImage(localIdentifier: id, placeholder: photo.color)
                } else {
                    Rectangle().fill(photo.color)
                }

                // Date label
                Text(photo.date)
                    .font(PurgeFont.mono(8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5))
                    .padding(4)
            }

            // Delete overlay
            if isMarked {
                Color.black.opacity(0.45)
                    .allowsHitTesting(false)
            }

            // ✕ badge (top-right)
            ZStack {
                Circle()
                    .fill(isMarked ? PurgeColor.primary : Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))

                if isMarked {
                    Text("✕")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(6)

            // Border
            Rectangle()
                .strokeBorder(
                    isMarked ? PurgeColor.primary : PurgeColor.border,
                    lineWidth: isMarked ? 2 : 1
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            guard let id = photo.localIdentifier else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                if markedForDeletion.contains(id) {
                    markedForDeletion.remove(id)
                } else {
                    markedForDeletion.insert(id)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showComplete = true
                }
            } label: {
                HStack(spacing: 0) {
                    Text("⚡")
                        .font(PurgeFont.mono(18))
                        .foregroundStyle(selectedCount > 0 ? PurgeColor.warning : PurgeColor.textMuted)
                        .frame(width: 48)

                    Spacer()

                    if selectedCount > 0 {
                        Text("TRASH \(selectedCount) PHOTOS")
                            .font(PurgeFont.headline(32))
                            .foregroundStyle(PurgeColor.text)
                            .tracking(-1)
                    } else {
                        Text("SKIP GROUP")
                            .font(PurgeFont.mono(13, weight: .semibold))
                            .foregroundStyle(PurgeColor.textMuted)
                    }

                    Spacer()

                    Text(selectedCount > 0 ? "⚡" : "")
                        .font(PurgeFont.mono(18))
                        .foregroundStyle(PurgeColor.warning)
                        .frame(width: 48)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(selectedCount > 0 ? PurgeColor.primary : PurgeColor.surface)
                .animation(.easeInOut(duration: 0.15), value: selectedCount > 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 34)
        .background(PurgeColor.surface)
    }

    // MARK: - Helpers

    private var selectedMBLabel: String {
        selectedMB >= 1000
            ? String(format: "%.1fGB", Double(selectedMB) / 1000)
            : "\(selectedMB)MB"
    }
}
