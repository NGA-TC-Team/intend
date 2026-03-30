import AppKit
import WebKit

/// WKWebView 기반 마크다운 미리보기 패널.
/// update(markdown:) 호출 시 300ms 디바운스 후 HTML 렌더링.
final class PreviewViewController: NSViewController {

    // MARK: - Subviews

    private var webView: WKWebView!

    // MARK: - State

    private var debounceTask: Task<Void, Never>?
    private var currentMarkdown = ""

    // MARK: - Lifecycle

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView    = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")  // 투명 배경 → 테마 추종
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 패널이 접혀 있다가 처음 펼쳐질 때 loadView()가 지연 호출됨.
        // 그 사이 update(markdown:)가 들어온 경우 currentMarkdown이 채워져 있으므로
        // 즉시 렌더링해 빈 화면 방지.
        if currentMarkdown.isEmpty {
            loadBlankPage()
        } else {
            render()
        }
    }

    // MARK: - Public

    /// 마크다운 내용 업데이트 (300ms 디바운스).
    func update(markdown: String) {
        guard markdown != currentMarkdown else { return }
        currentMarkdown = markdown

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.render()
        }
    }

    // MARK: - Private

    private func render() {
        // loadView()가 아직 호출되지 않은 상태(패널 접힘)에서 호출될 수 있음.
        // webView IUO가 nil이면 크래시 → guard로 방어.
        guard let wv = webView else { return }
        let result = parse(markdown: currentMarkdown)
        let config = ConfigManager.shared.current
        let html   = renderHTML(from: result, config: config)
        wv.loadHTMLString(html, baseURL: nil)
    }

    private func loadBlankPage() {
        webView.loadHTMLString(
            "<html><body style='background:#fff;color-scheme:light dark'></body></html>",
            baseURL: nil
        )
    }
}
