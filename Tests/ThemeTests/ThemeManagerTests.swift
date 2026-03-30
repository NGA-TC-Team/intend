import XCTest
import AppKit
@testable import Intend

final class ThemeManagerTests: XCTestCase {

    // MARK: - resolvedBackground

    func testResolvedBackground_light_usesLightOverride() {
        var colors = ThemeColors.default
        colors.background      = "#FFFFFF"
        colors.lightBackground = "#F5F5F5"
        colors.darkBackground  = "#1A1A1A"

        XCTAssertEqual(colors.resolvedBackground(isDark: false), "#F5F5F5")
    }

    func testResolvedBackground_dark_usesDarkOverride() {
        var colors = ThemeColors.default
        colors.background     = "#FFFFFF"
        colors.darkBackground = "#1A1A1A"

        XCTAssertEqual(colors.resolvedBackground(isDark: true), "#1A1A1A")
    }

    func testResolvedBackground_fallsBackToCommon_whenNoPairSpecified() {
        var colors = ThemeColors.default
        colors.background = "#ABCDEF"

        XCTAssertEqual(colors.resolvedBackground(isDark: false), "#ABCDEF")
        XCTAssertEqual(colors.resolvedBackground(isDark: true),  "#ABCDEF")
    }

    func testResolvedBackground_nil_whenAllNil() {
        let colors = ThemeColors.default
        XCTAssertNil(colors.resolvedBackground(isDark: false))
        XCTAssertNil(colors.resolvedBackground(isDark: true))
    }

    // MARK: - resolvedForeground

    func testResolvedForeground_dark_usesDarkOverride() {
        var colors = ThemeColors.default
        colors.foreground     = "#333333"
        colors.darkForeground = "#DDDDDD"

        XCTAssertEqual(colors.resolvedForeground(isDark: true),  "#DDDDDD")
        XCTAssertEqual(colors.resolvedForeground(isDark: false), "#333333")
    }

    // MARK: - ThemeManager color resolution

    @MainActor
    func testThemeManager_semanticFallback_light() {
        let manager = ThemeManager.shared
        // hex 없을 때 시맨틱 색상 반환 확인 (nil이 아님)
        NSApp.appearance = NSAppearance(named: .aqua)
        XCTAssertNotNil(manager.backgroundColor)
        XCTAssertNotNil(manager.foregroundColor)
        NSApp.appearance = nil
    }

    @MainActor
    func testThemeManager_semanticFallback_dark() {
        let manager = ThemeManager.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        XCTAssertNotNil(manager.backgroundColor)
        XCTAssertNotNil(manager.foregroundColor)
        NSApp.appearance = nil
    }

    @MainActor
    func testThemeManager_isDark_light() {
        NSApp.appearance = NSAppearance(named: .aqua)
        XCTAssertFalse(ThemeManager.shared.isDark)
        NSApp.appearance = nil
    }

    @MainActor
    func testThemeManager_isDark_dark() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        XCTAssertTrue(ThemeManager.shared.isDark)
        NSApp.appearance = nil
    }

    // MARK: - syntaxTokenColor

    func testSyntaxTokenColor_hasReducedAlpha() {
        let color = ThemeManager.shared.syntaxTokenColor
        XCTAssertLessThan(color.alphaComponent, 1.0)
    }
}
