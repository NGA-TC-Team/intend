import Foundation

// MARK: - Model

/// 파일 트리 노드 (값 타입).
/// children == nil  → 파일
/// children != nil  → 디렉터리 (빈 배열 포함)
struct FileNode: Equatable {
    let url:      URL
    var children: [FileNode]?

    var name:        String { url.lastPathComponent }
    var isDirectory: Bool   { children != nil }
    var isMarkdown:  Bool   {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

// MARK: - Tree builder (순수 함수)

/// 디렉터리 URL → FileNode 트리.
/// 정렬: 디렉터리 우선, 이름 오름차순.
/// 파일은 .md / .markdown 만 포함.
func buildFileTree(at url: URL) -> [FileNode] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    let nodes: [FileNode] = contents.compactMap { child in
        let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDir {
            return FileNode(url: child, children: buildFileTree(at: child))
        }
        let ext = child.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return nil }
        return FileNode(url: child, children: nil)
    }

    return nodes.sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}
