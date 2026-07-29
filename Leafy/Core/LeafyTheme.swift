import SwiftUI

enum LeafyTheme {
    static let green = Color(red: 0.13, green: 0.43, blue: 0.29)
    static let mint = Color(red: 0.91, green: 0.97, blue: 0.92)
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.11)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(LeafyTheme.green.opacity(configuration.isPressed ? 0.75 : 1), in: .rect(cornerRadius: 16))
    }
}

struct ChoiceCard<Content: View>: View {
    let selected: Bool
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 14) {
            content
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? LeafyTheme.green : .secondary)
        }
        .padding(16)
        .background(selected ? LeafyTheme.mint : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? LeafyTheme.green : .clear, lineWidth: 1.5))
    }
}

