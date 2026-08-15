import Foundation
import SwiftUI

struct AIMealWaitEstimator {
    private static let textKey = "leafy.aiMeal.wait.text"
    private static let photoKey = "leafy.aiMeal.wait.photo"

    static func estimatedSeconds(hasPhoto: Bool, defaults: UserDefaults = .standard) -> Double {
        let key = hasPhoto ? photoKey : textKey
        let stored = defaults.double(forKey: key)
        return clamp(stored > 0 ? stored : (hasPhoto ? 20 : 12))
    }

    static func record(_ duration: TimeInterval, hasPhoto: Bool, defaults: UserDefaults = .standard) {
        guard duration.isFinite, duration > 0 else { return }
        let key = hasPhoto ? photoKey : textKey
        let previous = estimatedSeconds(hasPhoto: hasPhoto, defaults: defaults)
        defaults.set(clamp(previous * 0.7 + duration * 0.3), forKey: key)
    }

    private static func clamp(_ value: Double) -> Double {
        min(45, max(5, value))
    }
}

struct AIMealLoadingView: View {
    let startedAt: Date
    let estimatedSeconds: Double
    let onCancel: () -> Void

    var body: some View {
        LeafyAnalysisLoadingView(
            title: "Leafy is estimating your meal",
            facts: Self.facts,
            startedAt: startedAt,
            estimatedSeconds: estimatedSeconds,
            loadingAccessibilityIdentifier: "aiMealLoadingScreen",
            cancelAccessibilityIdentifier: "cancelMealAnalysisButton",
            onCancel: onCancel
        )
    }

    private static let facts = [
        "Protein and carbohydrates each provide about 4 calories per gram.",
        "Fat provides about 9 calories per gram, making portions especially useful to estimate.",
        "Cooking oils, dressings, and sauces can make a meaningful difference in a meal estimate.",
        "Describing portion sizes helps Leafy narrow the calorie range.",
        "Daily weight can shift from water, sodium, and digestion—not only body tissue.",
        "Fiber is found naturally in foods like beans, fruit, vegetables, and whole grains.",
        "Restaurant portions can vary, so Leafy keeps an uncertainty range around its estimate.",
        "Reviewing an AI estimate helps Leafy preserve what you actually ate rather than a guess.",
    ]
}

struct LeafyAnalysisLoadingView: View {
    let title: String
    let facts: [String]
    let startedAt: Date
    let estimatedSeconds: Double
    let loadingAccessibilityIdentifier: String
    let cancelAccessibilityIdentifier: String
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var factIndex = 0

    var body: some View {
        VStack(spacing: LeafySpacing.xLarge) {
            Spacer()
            ZStack {
                Circle().stroke(LeafyTheme.green.opacity(0.16), lineWidth: 10)
                ProgressView().controlSize(.large).tint(LeafyTheme.green)
            }
            .frame(width: 92, height: 92)

            VStack(spacing: LeafySpacing.small) {
                Text(title)
                    .font(LeafyTypography.title2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(loadingAccessibilityIdentifier)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(waitMessage(at: context.date))
                        .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(spacing: LeafySpacing.compact) {
                Text("DID YOU KNOW?")
                    .font(LeafyTypography.captionSemibold).foregroundStyle(LeafyTheme.green)
                Text(facts[factIndex])
                    .id(factIndex)
                    .font(LeafyTypography.body)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .frame(minHeight: 80, alignment: .top)
            }
            .padding(.horizontal, 34)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LeafyTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button("Cancel", role: .cancel, action: onCancel)
                .font(LeafyTypography.button)
                .foregroundStyle(LeafyTheme.green)
                .frame(minHeight: LeafyTheme.minimumTouchTarget)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier(cancelAccessibilityIdentifier)
        }
        .interactiveDismissDisabled()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    factIndex = (factIndex + 1) % facts.count
                }
            }
        }
    }

    private func waitMessage(at date: Date) -> String {
        let elapsed = date.timeIntervalSince(startedAt)
        if elapsed >= estimatedSeconds { return "Finishing up…" }
        return "Usually about \(Int(estimatedSeconds.rounded())) seconds"
    }
}
