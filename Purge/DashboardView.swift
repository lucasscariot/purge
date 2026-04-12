import SwiftUI

struct DashboardView: View {
    let clusters: [PhotoCluster]
    let photoCount: Int
    let duplicateCount: Int
    let screenshotCount: Int
    let blurryCount: Int
    let scanProgress: Double?   // nil = idle, 0–1 = scanning
    let onRescan: () -> Void

    @State private var selectedCluster: PhotoCluster? = nil

    private var totalReclaimableBytes: Int64 {
        clusters.reduce(0) { $0 + Int64($1.totalMB) * 1_000_000 }
    }

    private var reclaimableLabel: String {
        let mb = Double(totalReclaimableBytes) / 1_000_000
        return mb >= 1000
            ? String(format: "%.1f GB", mb / 1000)
            : "\(Int(mb)) MB"
    }

    var body: some View {
        ZStack {
            PurgeColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    bigStatCards
                        .padding(.top, 2)
                    startPurgeButton
                        .padding(.top, 2)
                    clusterLog
                        .padding(.top, 2)
                    bottomActions
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(item: $selectedCluster) { cluster in
            ReviewSessionView(cluster: cluster)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(
                    color: scanProgress != nil ? PurgeColor.warning : PurgeColor.primary,
                    size: 8
                )
                Text(scanProgress != nil ? "SCANNING" : "PURGE")
                    .font(PurgeFont.mono(13, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                if let p = scanProgress {
                    Text("\(Int(p * 100))%")
                        .font(PurgeFont.mono(10, weight: .semibold))
                        .foregroundStyle(PurgeColor.warning)
                        .animation(.none, value: p)
                }
                Spacer()
                Text(photoCount > 0 ? "\(photoCount.formatted()) PHOTOS" : "")
                    .font(PurgeFont.mono(10))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(PurgeColor.surface)

            // Progress bar (scanning) or 1px divider (idle)
            if let p = scanProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(PurgeColor.border)
                        Rectangle()
                            .fill(PurgeColor.warning)
                            .frame(width: geo.size.width * p)
                            .animation(.linear(duration: 0.4), value: p)
                    }
                }
                .frame(height: 2)
            } else {
                Rectangle()
                    .fill(PurgeColor.border)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Big Stat Cards

    private var bigStatCards: some View {
        VStack(spacing: 1) {
            // Card 1 — duplicates
            statCard(
                tag: "DUPLICATE_SCAN",
                tagColor: PurgeColor.warning,
                bigNumber: "\(duplicateCount)",
                label: "NEAR-DUPLICATES",
                warning: duplicateCount > 100 ? "HIGH_DENSITY_DETECTED" : nil
            )

            // Card 2 — reclaimable
            statCard(
                tag: "STORAGE_ANALYSIS",
                tagColor: PurgeColor.teal,
                bigNumber: reclaimableLabel,
                label: "WASTED",
                warning: totalReclaimableBytes > 1_000_000_000 ? "CRITICAL_ACCUMULATION" : nil
            )
        }
    }

    private func statCard(
        tag: String,
        tagColor: Color,
        bigNumber: String,
        label: String,
        warning: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTag(text: tag, color: tagColor)

            VStack(alignment: .leading, spacing: 0) {
                Text(bigNumber)
                    .font(PurgeFont.headline(68))
                    .foregroundStyle(PurgeColor.text)
                    .tracking(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(label)
                    .font(PurgeFont.headline(32))
                    .foregroundStyle(PurgeColor.text)
                    .tracking(-1)
            }

            if let warning {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(PurgeColor.primary)
                        .frame(width: 2, height: 10)
                    Text(warning)
                        .font(PurgeFont.mono(9, weight: .semibold))
                        .foregroundStyle(PurgeColor.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PurgeColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
    }

    // MARK: - START PURGE Button

    private var startPurgeButton: some View {
        Button {
            if let first = clusters.first {
                selectedCluster = first
            }
        } label: {
            HStack(spacing: 0) {
                Text("⚡")
                    .font(PurgeFont.mono(18))
                    .foregroundStyle(PurgeColor.warning)
                    .frame(width: 48)

                Spacer()

                Text("START PURGE")
                    .font(PurgeFont.headline(40))
                    .foregroundStyle(PurgeColor.text)
                    .tracking(-1)

                Spacer()

                Text("⚡")
                    .font(PurgeFont.mono(18))
                    .foregroundStyle(PurgeColor.warning)
                    .frame(width: 48)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(PurgeColor.primary)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PurgeColor.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(clusters.isEmpty)
    }

    // MARK: - Cluster Log

    private var clusterLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                StatusDot(color: PurgeColor.primary, size: 6)
                Text("CLEANUP_QUEUE")
                    .font(PurgeFont.mono(10, weight: .semibold))
                    .foregroundStyle(PurgeColor.textMuted)
                Spacer()
                Text("\(clusters.count) GROUPS")
                    .font(PurgeFont.mono(9))
                    .foregroundStyle(PurgeColor.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PurgeColor.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PurgeColor.border).frame(height: 1)
            }

            if clusters.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(clusters.enumerated()), id: \.element.id) { idx, cluster in
                        Button {
                            selectedCluster = cluster
                        } label: {
                            clusterLogRow(cluster: cluster, index: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func clusterLogRow(cluster: PhotoCluster, index: Int) -> some View {
        HStack(spacing: 0) {
            // Type indicator bar
            Rectangle()
                .fill(typeColor(cluster.type))
                .frame(width: 3)

            HStack(spacing: 8) {
                // Type tag
                Text(typeCode(cluster.type))
                    .font(PurgeFont.mono(8, weight: .semibold))
                    .foregroundStyle(typeColor(cluster.type))
                    .frame(width: 32, alignment: .leading)

                // Cluster name
                Text(cluster.label.replacingOccurrences(of: " ", with: "_"))
                    .font(PurgeFont.mono(11, weight: .semibold))
                    .foregroundStyle(PurgeColor.text)
                    .lineLimit(1)

                // Dot leader
                Spacer()

                // Count + size
                HStack(spacing: 10) {
                    Text("\(cluster.photoCount)")
                        .font(PurgeFont.mono(11, weight: .semibold))
                        .foregroundStyle(PurgeColor.textMuted)
                        .frame(width: 36, alignment: .trailing)

                    Text(sizeBadge(cluster.totalMB))
                        .font(PurgeFont.mono(10, weight: .semibold))
                        .foregroundStyle(typeColor(cluster.type))
                        .frame(width: 52, alignment: .trailing)
                }

                Text(">")
                    .font(PurgeFont.mono(12))
                    .foregroundStyle(PurgeColor.textMuted)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(index.isMultiple(of: 2) ? PurgeColor.surface : PurgeColor.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PurgeColor.border).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTHING_LEFT_TO_PURGE")
                .font(PurgeFont.mono(12, weight: .semibold))
                .foregroundStyle(PurgeColor.text)
            Text("Your gallery is clean. For now.")
                .font(PurgeFont.mono(11))
                .foregroundStyle(PurgeColor.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PurgeColor.surface)
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 1) {
            actionButton("RESCAN", action: onRescan)
            actionButton("SETTINGS", action: {})
        }
        .overlay(Rectangle().strokeBorder(PurgeColor.border, lineWidth: 1))
    }

    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(PurgeFont.mono(11, weight: .semibold))
                .foregroundStyle(PurgeColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PurgeColor.surface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func typeColor(_ type: ClusterType) -> Color {
        switch type {
        case .duplicate:  return PurgeColor.primary
        case .screenshot: return PurgeColor.teal
        case .blurry:     return PurgeColor.textMuted
        case .trip:       return PurgeColor.secondary
        case .event:      return PurgeColor.warning
        }
    }

    private func typeCode(_ type: ClusterType) -> String {
        switch type {
        case .duplicate:  return "DUP"
        case .screenshot: return "SCR"
        case .blurry:     return "BLR"
        case .trip:       return "TRP"
        case .event:      return "EVT"
        }
    }

    private func sizeBadge(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1fGB", Double(mb) / 1000) : "\(mb)MB"
    }
}

#Preview {
    DashboardView(
        clusters: PhotoCluster.sampleClusters,
        photoCount: 12_847,
        duplicateCount: 847,
        screenshotCount: 234,
        blurryCount: 23,
        scanProgress: nil,
        onRescan: {}
    )
}

#Preview("Scanning") {
    DashboardView(
        clusters: PhotoCluster.sampleClusters,
        photoCount: 12_847,
        duplicateCount: 312,
        screenshotCount: 234,
        blurryCount: 0,
        scanProgress: 0.45,
        onRescan: {}
    )
}
