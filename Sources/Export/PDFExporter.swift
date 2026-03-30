import AppKit
import WebKit

// MARK: - PDF 내보내기

/// WKWebView.createPDF를 이용해 HTML → PDF 파일 저장.
/// macOS 13+ API 사용.
enum PDFExporter {

    /// html을 url 경로에 PDF로 저장.
    /// completion은 메인 스레드에서 호출됨.
    @MainActor
    static func export(html: String, to url: URL, completion: @escaping (Error?) -> Void) {
        let session = _PDFExportSession(html: html, destination: url, completion: completion)
        session.start()
        _sessions.append(session)
    }

    @MainActor private static var _sessions: [_PDFExportSession] = []

    @MainActor
    fileprivate static func removeSession(_ session: _PDFExportSession) {
        _sessions.removeAll { $0 === session }
    }
}

// MARK: - Internal session

private final class _PDFExportSession: NSObject, WKNavigationDelegate {

    private let webView:     WKWebView
    private let html:        String
    private let destination: URL
    private let completion:  (Error?) -> Void

    init(html: String, destination: URL, completion: @escaping (Error?) -> Void) {
        self.html        = html
        self.destination = destination
        self.completion  = completion
        self.webView     = WKWebView(frame: NSRect(x: 0, y: -2000, width: 794, height: 1123))
        super.init()
    }

    func start() {
        webView.navigationDelegate = self
        NSApp.mainWindow?.contentView?.addSubview(webView)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config        = WKPDFConfiguration()
        config.rect       = CGRect(x: 0, y: 0, width: 794, height: 1123)

        webView.createPDF(configuration: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webView.removeFromSuperview()
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: self.destination, options: .atomic)
                        self.completion(nil)
                    } catch {
                        self.completion(error)
                    }
                case .failure(let error):
                    self.completion(error)
                }
                PDFExporter.removeSession(self)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.removeFromSuperview()
        completion(error)
        Task { @MainActor [weak self] in
            if let self { PDFExporter.removeSession(self) }
        }
    }
}

// MARK: - Error

enum ExportError: LocalizedError {
    case pdfWriteFailed

    var errorDescription: String? {
        switch self {
        case .pdfWriteFailed: return "PDF 파일 저장에 실패했습니다."
        }
    }
}
