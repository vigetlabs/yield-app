import SwiftUI

struct StatusIndicator: View {
    let status: ProjectStatus.Status
    var isTracking: Bool = false
    var isUnbooked: Bool = false

    var color: Color {
        if isUnbooked { return YieldStatusColors.unbooked }
        switch status {
        case .under: return YieldStatusColors.under
        case .onTrack: return YieldStatusColors.onTrack
        case .over: return YieldStatusColors.over
        }
    }

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isTracking ? (isPulsing ? 0.3 : 1.0) : 1.0)
            .onAppear {
                guard isTracking else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: isTracking) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPulsing = false
                    }
                }
            }
    }
}
