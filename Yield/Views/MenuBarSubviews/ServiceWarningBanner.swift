import SwiftUI

struct ServiceWarningBanner: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(YieldColors.yellowAccent)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.serviceErrors) { error in
                    ServiceErrorRow(
                        error: error,
                        snapshot: viewModel.statusSnapshot,
                        compact: true
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(YieldColors.yellowFaint)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }
}
