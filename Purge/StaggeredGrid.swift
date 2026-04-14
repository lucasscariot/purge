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
        let gridItems = Array(repeating: GridItem(.fixed(itemSize.width), spacing: spacing), count: columns)

        LazyVGrid(columns: gridItems, spacing: spacing) {
            ForEach(data, id: \.id) { item in
                content(item)
                    .frame(width: itemSize.width, height: itemSize.height)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
