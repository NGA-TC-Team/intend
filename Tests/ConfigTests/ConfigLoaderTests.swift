import XCTest
@testable import Intend

final class ConfigLoaderTests: XCTestCase {

    // MARK: - Default config

    func test_defaultConfig_hasExpectedValues() {
        let config = AppConfig.default
        XCTAssertEqual(config.editor.font.size, 16)
        XCTAssertEqual(config.editor.tabSize, 4)
        XCTAssertEqual(config.rendering.headings.h1.scale, 2.0)
        XCTAssertEqual(config.rendering.headings.h6.color, "#888888")
        XCTAssertEqual(config.theme.appearance, "auto")
    }

    // MARK: - parseConfig

    func test_parseConfig_validJSON_returnsConfig() {
        let json: [String: Any] = makeMinimalJSON()
        let result = parseConfig(from: json)

        switch result {
        case .success(let config):
            XCTAssertEqual(config.editor.font.family, "Helvetica Neue")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func test_parseConfig_invalidJSON_returnsFailure() {
        let json: [String: Any] = ["editor": "not a dict"]
        let result = parseConfig(from: json)

        if case .success = result {
            XCTFail("Expected failure for invalid JSON")
        }
    }

    // MARK: - merge

    func test_merge_partialOverride_preservesBaseValues() {
        let base = AppConfig.default
        let override: [String: Any] = [
            "editor": ["tabSize": 2]
        ]
        let result = merge(base: base, override: override)

        switch result {
        case .success(let merged):
            XCTAssertEqual(merged.editor.tabSize, 2)
            // 오버라이드하지 않은 값은 기본값 유지
            XCTAssertEqual(merged.editor.font.size, 16)
            XCTAssertEqual(merged.rendering.headings.h1.scale, 2.0)
        case .failure(let error):
            XCTFail("Merge failed: \(error)")
        }
    }

    func test_merge_themeColorOverride_appliesCorrectly() {
        let base = AppConfig.default
        let override: [String: Any] = [
            "theme": [
                "colors": ["background": "#1E1E1E", "foreground": "#D4D4D4"]
            ]
        ]
        let result = merge(base: base, override: override)

        switch result {
        case .success(let merged):
            XCTAssertEqual(merged.theme.colors.background, "#1E1E1E")
            XCTAssertEqual(merged.theme.colors.foreground, "#D4D4D4")
            XCTAssertNil(merged.theme.colors.accent) // 건드리지 않은 필드
        case .failure(let error):
            XCTFail("Merge failed: \(error)")
        }
    }

    // MARK: - deepMerge (직접 검증)

    func test_headingStyle_levelMapping() {
        let config = AppConfig.default.rendering
        XCTAssertEqual(config.headingStyle(level: 1).scale, 2.0)
        XCTAssertEqual(config.headingStyle(level: 3).weight, "semibold")
        XCTAssertEqual(config.headingStyle(level: 7).scale, config.headings.h6.scale) // 범위 초과 → h6
    }

    // MARK: - Helpers

    private func makeMinimalJSON() -> [String: Any] {
        [
            "editor": [
                "font": ["family": "Helvetica Neue", "size": 16.0],
                "lineHeight": 1.6, "tabSize": 4,
                "wordWrap": true, "spellCheck": false,
                "focusMode": false, "typewriterMode": false
            ],
            "rendering": [
                "headings": [
                    "h1": ["scale": 2.0, "weight": "bold"],
                    "h2": ["scale": 1.6, "weight": "bold"],
                    "h3": ["scale": 1.3, "weight": "semibold"],
                    "h4": ["scale": 1.1, "weight": "semibold"],
                    "h5": ["scale": 1.0, "weight": "medium"],
                    "h6": ["scale": 1.0, "weight": "medium", "color": "#888888"]
                ],
                "paragraph": ["lineHeight": 1.6, "firstLineIndent": 0.0, "spacing": 1.0],
                "blockquote": ["italic": true],
                "codeBlock": ["font": "Menlo", "fontSize": 14.0, "syntaxTheme": "github-dark", "showLineNumbers": false],
                "inlineCode": ["font": "Menlo", "fontSize": 14.0],
                "link": ["underline": true],
                "list": ["bulletStyle": "disc", "indentWidth": 24.0],
                "horizontalRule": ["style": "line"],
                "table": [:]
            ],
            "theme": [
                "name": "default", "appearance": "auto",
                "colors": ["background": NSNull(), "foreground": NSNull(), "accent": NSNull(), "selection": NSNull()]
            ],
            "export": [
                "pdf": ["paperSize": "A4", "marginTop": 20.0, "marginBottom": 20.0,
                        "marginLeft": 25.0, "marginRight": 25.0, "includeTableOfContents": false],
                "html": ["embedCSS": true, "syntaxHighlighting": true]
            ],
            "keybindings": [
                "togglePreview": "Cmd+Shift+P",
                "focusMode": "Cmd+Shift+F",
                "exportPDF": "Cmd+Shift+E"
            ]
        ]
    }
}
