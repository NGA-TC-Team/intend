import XCTest
@testable import Intend

final class HTMLExporterTests: XCTestCase {
    func test_renderHTML_usesConfiguredHeadingScalesAndInheritedFontFamily() {
        var config = AppConfig.default
        config.editor.font.family = "Pretendard"
        config.rendering.headings.h1.scale = 2.25
        config.rendering.headings.h2.scale = 1.75

        let result = parse(markdown: "# 제목\n\n## 소제목")
        let html = renderHTML(from: result, config: config)

        XCTAssertTrue(html.contains("font-family: \"Pretendard\""))
        XCTAssertTrue(html.contains("h1 { font-size: 2.25em; }"))
        XCTAssertTrue(html.contains("h2 { font-size: 1.75em; }"))
        XCTAssertTrue(html.contains("font-family: inherit;"))
    }
}
