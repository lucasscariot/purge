import SwiftUI

struct StaggeredGrid<Content: View, T: Identifiable>: View where T: Hashable {
    var data: [T]
    var columns: Int
    var spacing: CGFloat
    var content: (T) -> Content
    
    init(_ data: [T], columns: Int = 2, spacing: CGFloat = 16, @ViewBuilder content: @escaping (T) -> Content) {
        self.data = data
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { col in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(data.enumerated()).filter { $0.offset % columns == col }.map { $0.element }) { item in
                        content(item)
                    }
                }
            }
        }
    }
}
