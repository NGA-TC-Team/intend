import AppKit

/// 활성 테마에 맞는 NSColor를 제공하는 단일 접근점.
/// 항상 메인 스레드에서 접근하므로 @unchecked Sendable.
final class ThemeManager: @unchecked Sendable {

    static let shared = ThemeManager()
    private init() {}

    private var config: ThemeConfig = .default

    func apply(_ config: ThemeConfig) {
        self.config = config
    }

    // MARK: - Appearance

    /// 현재 앱 외관이 다크 모드인지.
    var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Colors (appearance-aware, lazy resolved)

    var backgroundColor: NSColor {
        resolve(config.colors.resolvedBackground(isDark: isDark)) ?? .textBackgroundColor
    }

    var foregroundColor: NSColor {
        resolve(config.colors.resolvedForeground(isDark: isDark)) ?? .labelColor
    }

    var accentColor: NSColor {
        resolve(config.colors.accent) ?? .controlAccentColor
    }

    var selectionColor: NSColor {
        resolve(config.colors.selection) ?? .selectedTextBackgroundColor
    }

    /// 마크다운 토큰(#, **, * 등)을 흐리게 표시할 색상
    var syntaxTokenColor: NSColor {
        foregroundColor.withAlphaComponent(0.3)
    }

    // MARK: - Private

    private func resolve(_ hex: String?) -> NSColor? {
        hex.flatMap(NSColor.init(hex:))
    }
}

// NSColor.init(hex:) 는 AttributeRenderer.swift 에 정의 (중복 방지)
