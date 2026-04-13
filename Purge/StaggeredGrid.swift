import SwiftUI

struct StaggeredGrid<Content: View, T: Identifiable>: View where T: Hashable {
    var data: [T]
    var columns: Int
    var spacing: CGFloat
    var itemSize: CGSize
    var content: (T) -> Content

    init(_ data: [T], columns: Int = 2, spacing: CGFloat = 16, itemSize: CGSize = CGSize(width: 160, height: 160), @ViewBuilder content: @escaping (T) -> Content) {
        self.data = data
        self.columns = columns
        self.spacing = spacing
        self.itemSize = itemSize
        self.content = content
    }

    var body: some View {
        let rowCount = (data.count + columns - 1) / columns
        let totalHeight = CGFloat(rowCount) * itemSize.height + CGFloat(max(0, rowCount - 1)) * spacing
        let totalWidth = CGFloat(columns) * itemSize.width + CGFloat(max(0, columns - 1)) * spacing

        ZStack(alignment: .topLeading) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                let col = index % columns
                let row = index / columns
                
                let x = CGFloat(col) * (itemSize.width + spacing)
                let y = CGFloat(row) * (itemSize.height + spacing)
                
                content(item)
                    .frame(width: itemSize.width, height: itemSize.height)
                    .position(x: x + itemSize.width / 2, y: y + itemSize.height / 2)
            }
        }
        .frame(width: totalWidth, height: totalHeight)
    }
}
