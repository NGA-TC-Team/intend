import Foundation

/// 편집기 탭 하나를 표현하는 값 타입.
/// document가 소유권, editorVC가 뷰 상태를 담당.
struct TabItem {
    let id:       UUID
    let document: MarkdownDocument
    let editorVC: EditorViewController
    /// 더블클릭으로 사용자가 수정한 이름. nil이면 h1Title 또는 document.displayName 사용.
    var customDisplayName: String?
    /// 문서 첫 H1 헤딩에서 추출한 제목. customDisplayName이 없을 때 우선 사용.
    var h1Title: String?

    @MainActor var displayName: String {
        customDisplayName ?? h1Title ?? document.displayName
    }

    init(document: MarkdownDocument, editorVC: EditorViewController) {
        self.id       = UUID()
        self.document = document
        self.editorVC = editorVC
    }
}
