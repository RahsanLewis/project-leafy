import SwiftUI

struct LeafySplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: LeafySpacing.medium) {
                Image("LeafyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                Text("Leafy")
                    .font(LeafyTypography.metric(36, extraBold: true))
                    .foregroundStyle(.black)
                    .tracking(-0.8)
            }
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.97))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leafy")
        .accessibilityIdentifier("leafySplash")
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.65)) {
                isVisible = true
            }
        }
    }
}
