import SwiftUI

enum LeafyTheme {
    static let green = Color(red: 0.13, green: 0.43, blue: 0.29)
    static let mint = Color(red: 0.91, green: 0.97, blue: 0.92)
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.11)
    static let canvas = Color(.systemGroupedBackground)
    static let hairline = Color.primary.opacity(0.10)
    static let pageInset: CGFloat = 20
    static let rowMinHeight: CGFloat = 60
}

enum LeafyTypography {
    private static let regularName = "PlusJakartaSans-Regular"
    private static let mediumName = "PlusJakartaSans-Medium"
    private static let semiBoldName = "PlusJakartaSans-SemiBold"
    private static let boldName = "PlusJakartaSans-Bold"
    private static let extraBoldName = "PlusJakartaSans-ExtraBold"

    static let largeTitle = Font.custom(extraBoldName, size: 34, relativeTo: .largeTitle)
    static let title = Font.custom(boldName, size: 28, relativeTo: .title)
    static let title2 = Font.custom(boldName, size: 22, relativeTo: .title2)
    static let title3 = Font.custom(semiBoldName, size: 20, relativeTo: .title3)
    static let headline = Font.custom(semiBoldName, size: 17, relativeTo: .headline)
    static let body = Font.custom(regularName, size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom(mediumName, size: 17, relativeTo: .body)
    static let callout = Font.custom(regularName, size: 16, relativeTo: .callout)
    static let subheadline = Font.custom(regularName, size: 15, relativeTo: .subheadline)
    static let subheadlineSemibold = Font.custom(semiBoldName, size: 15, relativeTo: .subheadline)
    static let footnote = Font.custom(regularName, size: 13, relativeTo: .footnote)
    static let caption = Font.custom(regularName, size: 12, relativeTo: .caption)
    static let captionSemibold = Font.custom(semiBoldName, size: 12, relativeTo: .caption)
    static let caption2 = Font.custom(regularName, size: 11, relativeTo: .caption2)
    static let button = Font.custom(semiBoldName, size: 17, relativeTo: .headline)

    static func metric(_ size: CGFloat, extraBold: Bool = false, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(extraBold ? extraBoldName : boldName, size: size, relativeTo: style)
    }

    static func icon(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: size, weight: .regular)
    }
}

enum LeafySpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(LeafyTheme.green.opacity(configuration.isPressed ? 0.75 : 1), in: .rect(cornerRadius: 16))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(LeafyTheme.green.opacity(configuration.isPressed ? 0.7 : 1))
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LeafyTheme.green.opacity(0.35), lineWidth: 1.5))
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

private struct LeafyBorderlessListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, LeafyTheme.rowMinHeight)
            .scrollContentBackground(.hidden)
            .background(LeafyTheme.canvas)
            .tint(LeafyTheme.green)
    }
}

private struct LeafyBorderlessRowsModifier: ViewModifier {
    let separators: Bool

    func body(content: Content) -> some View {
        content
            .listRowInsets(.init(
                top: 0,
                leading: LeafyTheme.pageInset,
                bottom: 0,
                trailing: LeafyTheme.pageInset
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(separators ? .visible : .hidden)
            .listRowSeparatorTint(LeafyTheme.hairline)
    }
}

extension View {
    func leafyBorderlessList() -> some View {
        modifier(LeafyBorderlessListModifier())
    }

    func leafyBorderlessRows(separators: Bool = true) -> some View {
        modifier(LeafyBorderlessRowsModifier(separators: separators))
    }
}
