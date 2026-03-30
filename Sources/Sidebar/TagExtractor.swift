import Foundation

// MARK: - TagExtractor

/// 마크다운 파일의 YAML front-matter에서 tags 필드를 추출하는 순수 함수 모음.
///
/// 지원 형식:
/// ```
/// ---
/// tags: [태그1, 태그2]
/// ---
/// ```
/// 또는
/// ```
/// ---
/// tags:
///   - 태그1
///   - 태그2
/// ---
/// ```
enum TagExtractor {

    /// 파일을 읽어 태그 배열을 반환. front-matter가 없으면 빈 배열.
    /// - Note: 파일 I/O 포함 — 백그라운드 스레드에서 호출할 것.
    static func extract(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(markdown: text)
    }

    /// 마크다운 텍스트에서 태그를 파싱. (테스트 가능한 순수 함수)
    static func parse(markdown text: String) -> [String] {
        // front-matter: 첫 줄이 "---"로 시작해야 함
        guard text.hasPrefix("---") else { return [] }

        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }

        // closing "---" 탐색 (1번 인덱스부터)
        var endIndex: Int? = nil
        for i in 1 ..< lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return [] }

        let frontMatter = lines[1 ..< end]
        return parseTags(from: Array(frontMatter))
    }

    // MARK: - Private

    private static func parseTags(from lines: [String]) -> [String] {
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // "tags:" 키 탐색
            if trimmed.lowercased().hasPrefix("tags:") {
                let afterColon = String(trimmed.dropFirst("tags:".count))
                    .trimmingCharacters(in: .whitespaces)

                if afterColon.isEmpty {
                    // 다음 줄부터 "  - tag" 형식
                    var tags: [String] = []
                    var j = i + 1
                    while j < lines.count {
                        let item = lines[j].trimmingCharacters(in: .whitespaces)
                        if item.hasPrefix("-") {
                            let tag = String(item.dropFirst()).trimmingCharacters(in: .whitespaces)
                            if !tag.isEmpty { tags.append(tag) }
                            j += 1
                        } else if item.isEmpty {
                            j += 1  // 빈 줄 스킵
                        } else {
                            break   // 다음 키
                        }
                    }
                    return tags
                } else {
                    // 인라인 배열: [tag1, tag2] 또는 tag1, tag2
                    return parseInlineList(afterColon)
                }
            }
            i += 1
        }
        return []
    }

    private static func parseInlineList(_ raw: String) -> [String] {
        // "[태그1, 태그2]" or "태그1, 태그2"
        var s = raw
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        return s.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }
}
