import SwiftUI

struct StatusIndicator: View {
    let status: ProjectStatus.Status
    var isTracking: Bool = false
    var isUnbooked: Bool = false

    var color: Color {
        if isUnbooked { return Color(red: 0.60, green: 0.60, blue: 0.60) }
        switch status {
        case .under: return Color(red: 0.55, green: 0.75, blue: 0.50)
        case .onTrack: return Color(red: 0.85, green: 0.78, blue: 0.45)
        case .over: return Color(red: 0.80, green: 0.45, blue: 0.40)
        }
    }

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isTracking ? (isPulsing ? 0.3 : 1.0) : 1.0)
            .animation(
                isTracking ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .transaction { t in t.animation = nil }
            .onAppear {
                if isTracking { isPulsing = true }
            }
            .onChange(of: isTracking) { _, newValue in
                isPulsing = newValue
            }
    }
}
