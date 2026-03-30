import AppKit
import WebKit

// MARK: - LaTeX → NSImage 렌더러 (KaTeX, WKWebView)

/// 싱글톤. 하나의 WKWebView를 재사용해 순차 렌더링.
/// katex-render.html + katex.min.js/css 번들 파일이 없으면 placeholder 반환.
@MainActor
final class LatexRenderer: NSObject {

    static let shared = LatexRenderer()

    // MARK: - Private state

    private let cache = NSCache<NSString, NSImage>()
    private var webView: WKWebView?
    private var isReady    = false
    private var isBusy     = false
    private var queue: [(String, Bool, (NSImage?) -> Void)] = []
    // 현재 처리 중인 요청
    private var currentContent: String = ""
    private var currentDisplayMode     = false
    private var currentCompletion: ((NSImage?) -> Void)?

    private override init() {
        super.init()
        setupWebView()
    }

    // MARK: - Public

    /// latex: LaTeX 소스, displayMode: 블록 수식 여부.
    func render(latex: String, displayMode: Bool, completion: @escaping (NSImage?) -> Void) {
        let key = (displayMode ? "B:" : "I:") + latex as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.append((latex, displayMode, completion))
        processQueue()
    }

    // MARK: - Setup

    private func setupWebView() {
        guard let htmlURL = Bundle.main.url(forResource: "katex-render", withExtension: "html") else {
            // 번들에 HTML 파일이 없으면 렌더러 비활성화
            return
        }

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(WeakScriptHandler(target: self), name: "rendered")
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: -2000, width: 600, height: 200),
                           configuration: config)
        wv.navigationDelegate = self
        NSApp.mainWindow?.contentView?.addSubview(wv)
        wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        webView = wv
    }

    // MARK: - Queue

    private func processQueue() {
        guard !isBusy, isReady, !queue.isEmpty, let wv = webView else { return }
        let (latex, displayMode, completion) = queue.removeFirst()
        isBusy                = true
        currentContent        = latex
        currentDisplayMode    = displayMode
        currentCompletion     = completion

        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "$\\{")  // JS 템플릿 리터럴 내 표현식 평가 방지
        let js = "renderMath(`\(escaped)`, \(displayMode ? "true" : "false"));"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Snapshot

    fileprivate func didReceiveRendered(sizeString: String) {
        guard let wv = webView else { finishCurrent(image: nil); return }

        let parts  = sizeString.split(separator: ",").compactMap { Int($0) }
        let w      = parts.count > 0 ? CGFloat(parts[0]) : 0
        let h      = parts.count > 1 ? CGFloat(parts[1]) : 0

        guard w > 0, h > 0 else {
            // 렌더링 실패 → placeholder
            let img = makePlaceholderImage(
                for: currentContent,
                kind: currentDisplayMode ? .blockLatex : .inlineLatex
            )
            finishCurrent(image: img)
            return
        }

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(x: 0, y: 0, width: w + 12, height: h + 4)
        wv.takeSnapshot(with: snapshotConfig) { [weak self] image, _ in
            self?.finishCurrent(image: image)
        }
    }

    private func finishCurrent(image: NSImage?) {
        if let img = image {
            let key = (currentDisplayMode ? "B:" : "I:") + currentContent as NSString
            cache.setObject(img, forKey: key)
        }
        currentCompletion?(image)
        currentCompletion = nil
        isBusy = false
        processQueue()
    }
}

// MARK: - WKNavigationDelegate

extension LatexRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isReady = true
            self.processQueue()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isBusy  = false
            self.isReady = false
        }
    }
}

// MARK: - WKScriptMessageHandler via weak proxy

extension LatexRenderer: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body as? String ?? "0,0"
        Task { @MainActor in
            self.didReceiveRendered(sizeString: body)
        }
    }
}

// MARK: - Weak proxy (retain cycle 방지)

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (AnyObject & WKScriptMessageHandler)?

    init(target: AnyObject & WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
