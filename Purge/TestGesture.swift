import SwiftUI

struct TestGesture: View {
    @State private var isPressed = false
    var body: some View {
        Text("Test")
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
    }
}
