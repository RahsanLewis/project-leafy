import SwiftUI

struct BeyondSolidSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.027)
                .ignoresSafeArea()

            Text("Beyond Solid")
                .font(LeafyTypography.metric(32, extraBold: true))
                .foregroundStyle(.white)
                .tracking(-0.7)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.97))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beyond Solid")
        .accessibilityIdentifier("beyondSolidSplash")
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.65)) {
                isVisible = true
            }
        }
    }
}
