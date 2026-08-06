import UIKit
import XCTest
@testable import Leafy

final class TypographyTests: XCTestCase {
    func testPlusJakartaSansWeightsAreRegistered() {
        let fontNames = [
            "PlusJakartaSans-Regular",
            "PlusJakartaSans-Medium",
            "PlusJakartaSans-SemiBold",
            "PlusJakartaSans-Bold",
            "PlusJakartaSans-ExtraBold"
        ]

        for fontName in fontNames {
            XCTAssertNotNil(UIFont(name: fontName, size: 17), "Missing bundled font: \(fontName)")
        }
    }

    func testFontFilesAreDeclaredInInfoPlist() {
        let declaredFonts = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String]
        XCTAssertEqual(
            declaredFonts,
            [
                "PlusJakartaSans-Regular.ttf",
                "PlusJakartaSans-Medium.ttf",
                "PlusJakartaSans-SemiBold.ttf",
                "PlusJakartaSans-Bold.ttf",
                "PlusJakartaSans-ExtraBold.ttf"
            ]
        )
    }
}
