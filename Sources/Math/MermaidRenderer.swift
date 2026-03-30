import AppKit
import WebKit

// MARK: - Mermaid → NSImage 렌더러 (mermaid.js, WKWebView)

/// 싱글톤. LatexRenderer와 동일한 WKWebView 재사용 패턴.
/// mermaid-render.html + mermaid.min.js 번들 파일이 없으면 placeholder 반환.
/// 렌더 캐시: 소스 문자열 해시 → NSCache<NSString, NSImage>
@MainActor
final class MermaidRenderer: NSObject {

    static let shared = MermaidRenderer()

    // MARK: - Private state

    private let cache = NSCache<NSString, NSImage>()
    private var webView: WKWebView?
    private var isReady    = false
    private var isBusy     = false
    private var queue: [(String, (NSImage?) -> Void)] = []
    private var currentSource     = ""
    private var currentCompletion: ((NSImage?) -> Void)?

    private override init() {
        super.init()
        setupWebView()
    }

    // MARK: - Public

    func render(source: String, completion: @escaping (NSImage?) -> Void) {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.append((source, completion))
        processQueue()
    }

    // MARK: - Setup

    private func setupWebView() {
        guard let htmlURL = Bundle.main.url(forResource: "mermaid-render", withExtension: "html") else {
            return
        }

        let config     = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(WeakMermaidHandler(target: self), name: "rendered")
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: -3000, width: 700, height: 500),
                           configuration: config)
        wv.navigationDelegate = self
        NSApp.mainWindow?.contentView?.addSubview(wv)
        wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        webView = wv
    }

    // MARK: - Queue

    private func processQueue() {
        guard !isBusy, isReady, !queue.isEmpty, let wv = webView else { return }
        let (source, completion) = queue.removeFirst()
        isBusy             = true
        currentSource      = source
        currentCompletion  = completion

        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "$\\{")  // JS 템플릿 리터럴 내 표현식 평가 방지
        let js = "renderDiagram(`\(escaped)`);"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Snapshot

    fileprivate func didReceiveRendered(sizeString: String) {
        guard let wv = webView else { finishCurrent(image: nil); return }

        let parts = sizeString.split(separator: ",").compactMap { Int($0) }
        let w     = parts.count > 0 ? CGFloat(parts[0]) : 0
        let h     = parts.count > 1 ? CGFloat(parts[1]) : 0

        guard w > 4, h > 4 else {
            finishCurrent(image: makePlaceholderImage(for: currentSource, kind: .mermaid))
            return
        }

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(x: 0, y: 0, width: w + 16, height: h + 16)
        wv.takeSnapshot(with: snapshotConfig) { [weak self] image, _ in
            self?.finishCurrent(image: image)
        }
    }

    private func finishCurrent(image: NSImage?) {
        if let img = image {
            cache.setObject(img, forKey: currentSource as NSString)
        }
        currentCompletion?(image)
        currentCompletion = nil
        isBusy = false
        processQueue()
    }
}

// MARK: - WKNavigationDelegate

extension MermaidRenderer: WKNavigationDelegate {
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

// MARK: - WKScriptMessageHandler

extension MermaidRenderer: WKScriptMessageHandler {
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

// MARK: - Weak proxy

private final class WeakMermaidHandler: NSObject, WKScriptMessageHandler {
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
