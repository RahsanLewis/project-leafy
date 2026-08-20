import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    static let storageKey = "leafy.appearance.mode"

    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Follow System"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

enum LeafyTheme {
    static let green = Color(red: 0.13, green: 0.43, blue: 0.29)
    static let greenPressed = Color(red: 0.10, green: 0.35, blue: 0.23)
    static let mint = adaptiveColor(
        light: UIColor(red: 0.91, green: 0.97, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.19, blue: 0.13, alpha: 1)
    )
    static let ink = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.15, blue: 0.11, alpha: 1),
        dark: UIColor(white: 0.96, alpha: 1)
    )
    static let canvas = adaptiveColor(
        light: .white,
        dark: UIColor(red: 0.035, green: 0.04, blue: 0.038, alpha: 1)
    )
    static let surface = adaptiveColor(
        light: UIColor(white: 0.96, alpha: 1),
        dark: UIColor(white: 0.10, alpha: 1)
    )
    static let elevatedSurface = adaptiveColor(
        light: .white,
        dark: UIColor(white: 0.14, alpha: 1)
    )
    static let track = adaptiveColor(
        light: UIColor(white: 0.91, alpha: 1),
        dark: UIColor(white: 0.18, alpha: 1)
    )
    static let hairline = Color.primary.opacity(0.09)
    static let warning = Color.orange
    static let danger = Color.red
    static let pageInset: CGFloat = 20
    static let rowMinHeight: CGFloat = 60
    static let minimumTouchTarget: CGFloat = 44

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
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
    static let xxLarge: CGFloat = 48
}

enum LeafyRadius {
    static let control: CGFloat = 14
    static let prominent: CGFloat = 20
}

enum LeafyMotion {
    static let press = Animation.easeOut(duration: 0.14)
    static let state = Animation.easeInOut(duration: 0.22)
    static let content = Animation.easeInOut(duration: 0.28)
    static let directManipulation = Animation.spring(duration: 0.36, bounce: 0.06)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(configuration.isPressed ? LeafyTheme.greenPressed : LeafyTheme.green, in: .rect(cornerRadius: LeafyRadius.control))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(LeafyMotion.press, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(LeafyTheme.green.opacity(configuration.isPressed ? 0.7 : 1))
            .background(LeafyTheme.surface, in: .rect(cornerRadius: LeafyRadius.control))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(LeafyMotion.press, value: configuration.isPressed)
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
        .background(selected ? LeafyTheme.mint : LeafyTheme.surface, in: .rect(cornerRadius: 16))
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

private struct LeafyDetachedBottomControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.small)
            .padding(.bottom, LeafySpacing.medium)
            .frame(maxWidth: .infinity)
            .background(LeafyTheme.canvas)
    }
}

private struct LeafySheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let dismissAccessibilityLabel: String
    let dismissIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(LeafyTypography.title2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: LeafySpacing.small)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(LeafyTypography.icon(15))
                            .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dismissAccessibilityLabel)
                    .accessibilityIdentifier(dismissIdentifier)
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LeafyTheme.pageInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .background(LeafyTheme.canvas)
        .presentationSizing(.fitted)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("\(dismissIdentifier)Sheet")
    }
}

struct LeafyInfoSheet<Content: View>: View {
    let title: String
    let dismissAccessibilityLabel: String
    let dismissIdentifier: String
    @ViewBuilder let content: Content

    init(
        title: String,
        dismissAccessibilityLabel: String? = nil,
        dismissIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.dismissAccessibilityLabel = dismissAccessibilityLabel ?? "Dismiss \(title.lowercased()) explanation"
        self.dismissIdentifier = dismissIdentifier
        self.content = content()
    }

    var body: some View {
        LeafySheetScaffold(
            title: title,
            dismissAccessibilityLabel: dismissAccessibilityLabel,
            dismissIdentifier: dismissIdentifier,
            content: { content }
        )
    }
}

struct LeafyConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String?
    let confirmTitle: String
    let isDestructive: Bool
    let confirmIdentifier: String
    let cancelTitle: String
    let sheetIdentifier: String
    let onConfirm: () -> Void

    init(
        title: String,
        message: String? = nil,
        confirmTitle: String,
        isDestructive: Bool = false,
        confirmIdentifier: String,
        cancelTitle: String = "Cancel",
        sheetIdentifier: String,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
        self.confirmIdentifier = confirmIdentifier
        self.cancelTitle = cancelTitle
        self.sheetIdentifier = sheetIdentifier
        self.onConfirm = onConfirm
    }

    var body: some View {
        LeafySheetScaffold(
            title: title,
            dismissAccessibilityLabel: "Cancel",
            dismissIdentifier: "\(sheetIdentifier)Close"
        ) {
            if let message {
                Text(message)
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                dismiss()
                onConfirm()
            } label: {
                Text(confirmTitle)
                    .font(LeafyTypography.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(isDestructive ? Color.red : Color.white)
                    .background(
                        isDestructive ? Color.red.opacity(0.09) : LeafyTheme.green,
                        in: .rect(cornerRadius: LeafyRadius.control)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(confirmIdentifier)

            Button(cancelTitle) { dismiss() }
                .font(LeafyTypography.button)
                .foregroundStyle(LeafyTheme.green)
                .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(sheetIdentifier)Cancel")
        }
        .accessibilityIdentifier(sheetIdentifier)
    }
}

extension View {
    func leafyBorderlessList() -> some View {
        modifier(LeafyBorderlessListModifier())
    }

    func leafyBorderlessRows(separators: Bool = true) -> some View {
        modifier(LeafyBorderlessRowsModifier(separators: separators))
    }

    func leafyDetachedBottomControl() -> some View {
        modifier(LeafyDetachedBottomControlModifier())
    }
}
