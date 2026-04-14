import SwiftUI
import UIKit

struct TimelineScrubber: View {
    let months: [String]
    let proxy: ScrollViewProxy
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var currentIndex: Int = 0
    @State private var lastHapticIndex: Int = -1
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let thumbRadius: CGFloat = 10
            let usableHeight = max(1, trackHeight - 2 * thumbRadius)
            
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 60, height: trackHeight)
                
                ZStack(alignment: .center) {
                    Capsule()
                        .fill(PurgeColor.text.opacity(0.08))
                        .frame(width: 4, height: trackHeight)
                    
                    ZStack {
                        Circle()
                            .fill(PurgeColor.rose)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        
                        if isDragging && !months.isEmpty {
                            Text(months[currentIndex].uppercased())
                                .font(PurgeFont.ui(14, weight: .bold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(PurgeColor.text)
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                                .offset(x: -60)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .scaleEffect(isDragging ? 1.4 : 1.0)
                    .offset(y: min(max(dragOffset, thumbRadius), trackHeight - thumbRadius) - trackHeight / 2)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isDragging)
                }
                .frame(width: 14)
                .padding(.trailing, 8)
            }
            .frame(width: 60, height: trackHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        
                        let percent = max(0, min((value.location.y - thumbRadius) / usableHeight, 1.0))
                        
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = thumbRadius + percent * usableHeight
                        }
                        
                        if !months.isEmpty {
                            let index = min(max(Int(percent * CGFloat(months.count)), 0), months.count - 1)
                            
                            if index != currentIndex {
                                currentIndex = index
                                
                                if index != lastHapticIndex {
                                    hapticGenerator.selectionChanged()
                                    lastHapticIndex = index
                                }
                                
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    proxy.scrollTo(months[index], anchor: .center)
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        
                        if !months.isEmpty {
                            let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                dragOffset = thumbRadius + snapPercentage * usableHeight
                            }
                        }
                    }
            )
            .onAppear {
                if !months.isEmpty {
                    let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                    dragOffset = thumbRadius + snapPercentage * usableHeight
                }
            }
            .onChange(of: months.count) { _, _ in
                if !months.isEmpty {
                    currentIndex = 0
                    dragOffset = thumbRadius
                }
            }
            .onChange(of: trackHeight) { _, newHeight in
                if !months.isEmpty {
                    let newUsableHeight = max(1, newHeight - 2 * thumbRadius)
                    let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                    dragOffset = thumbRadius + snapPercentage * newUsableHeight
                }
            }
        }
        .frame(width: 60)
    }
}
