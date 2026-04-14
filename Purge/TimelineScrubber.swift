import SwiftUI
import UIKit

struct TimelineScrubber: View {
    let months: [String]
    let proxy: ScrollViewProxy
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var currentIndex: Int = 0
    
    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            
            ZStack(alignment: .center) {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 80, height: trackHeight)

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
                                .offset(x: -70)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .offset(y: max(0, min(dragOffset, trackHeight)) - trackHeight / 2)
                    .scaleEffect(isDragging ? 1.4 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isDragging)
                }
                .frame(width: 80, height: trackHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                let generator = UIImpactFeedbackGenerator(style: .soft)
                                generator.impactOccurred()
                            }
                            
                            let pos = max(0, min(value.location.y, trackHeight))
                            
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                                dragOffset = pos
                            }
                            
                            if !months.isEmpty {
                                let percent = pos / trackHeight
                                let index = min(max(Int(percent * CGFloat(months.count)), 0), months.count - 1)
                                
                                if index != currentIndex {
                                    currentIndex = index
                                    let generator = UISelectionFeedbackGenerator()
                                    generator.selectionChanged()
                                    
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        proxy.scrollTo(months[index], anchor: .center)
                                    }
                                }
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            
                            if !months.isEmpty {
                                let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    dragOffset = snapPercentage * trackHeight
                                }
                            }
                        }
                )
                .onAppear {
                    if !months.isEmpty {
                        let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                        dragOffset = snapPercentage * trackHeight
                    }
                }
                .onChange(of: months.count) { _, _ in
                    if !months.isEmpty {
                        currentIndex = 0
                        dragOffset = 0
                    }
                }
                .onChange(of: trackHeight) { _, newHeight in
                    if !months.isEmpty {
                        let snapPercentage = CGFloat(currentIndex) / CGFloat(months.count > 1 ? months.count - 1 : 1)
                        dragOffset = snapPercentage * newHeight
                    }
                }
            }
            .frame(width: 80)
        }
        .frame(width: 80)
    }
}
