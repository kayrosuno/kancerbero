import SwiftUI

struct LiveDot: View {
    var isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isLive && !reduceMotion {
                Circle()
                    .stroke(Color.green.opacity(0.45), lineWidth: 1)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulsing ? 2.4 : 1)
                    .opacity(pulsing ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false),
                               value: pulsing)
            }
            Circle()
                .fill(isLive ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
        }
        .frame(width: 20, height: 20)
        .onAppear { pulsing = true }
        .accessibilityLabel(isLive ? "Live data" : "No recent data")
    }
}
