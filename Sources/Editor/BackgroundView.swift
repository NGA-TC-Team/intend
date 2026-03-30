import AppKit

// MARK: - BackgroundView

/// 편집기 배경을 담당하는 NSView 서브클래스.
/// scrollView 뒤에 삽입되어 이미지 또는 투명 배경을 표현.
final class BackgroundView: NSView {

    // MARK: - Content mode

    enum ImageContentMode: String {
        case fill   = "fill"
        case tile   = "tile"
        case center = "center"
    }

    // MARK: - Subviews

    private let imageView   = NSImageView()
    private let overlayView = NSView()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling  = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true

        addSubview(imageView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    /// 배경 없음 (기본 시스템 배경).
    func reset() {
        imageView.image    = nil
        imageView.isHidden = true
        overlayView.layer?.backgroundColor = nil
        layer?.backgroundColor = nil
    }

    /// 투명 배경. alpha: 0 = 완전 투명, 1 = 불투명 흰/검.
    func applyTransparent(alpha: CGFloat) {
        imageView.image    = nil
        imageView.isHidden = true
        overlayView.layer?.backgroundColor = nil
        // 배경 레이어를 투명 흰색으로 (dark mode → 검은색)
        let base: NSColor = NSApp.effectiveAppearance.name == .darkAqua
            ? NSColor(white: 0, alpha: alpha)
            : NSColor(white: 1, alpha: alpha)
        layer?.backgroundColor = base.cgColor
    }

    /// 이미지 배경.
    /// - overlayAlpha: 이미지 불투명도 (0 = 완전 투명 → 앱 배경색만 표시, 1 = 이미지 완전히 표시)
    func applyImage(_ image: NSImage,
                    contentMode: ImageContentMode,
                    overlayAlpha: CGFloat) {
        imageView.isHidden = false
        overlayView.layer?.backgroundColor = nil  // 어두운 베일 제거

        // 이미지 뒤에 깔리는 솔리드 앱 배경색.
        // 이미지가 반투명일 때 바탕화면 대신 이 색이 보임.
        let appBg = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.13, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)
        layer?.backgroundColor = appBg.cgColor

        // 이미지 불투명도: overlayAlpha 값이 바로 이미지 opacity
        imageView.alphaValue = max(0, min(1, overlayAlpha))

        switch contentMode {
        case .fill:
            imageView.imageScaling = .scaleAxesIndependently
        case .tile:
            // NSImageView 타일링
            imageView.imageScaling = .scaleAxesIndependently
            if let cgImg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer?.contents        = cgImg
                layer?.contentsGravity = .topLeft
                imageView.isHidden     = true  // layer로 직접 그림
            }
        case .center:
            imageView.imageScaling = .scaleNone
        }

        if contentMode != .tile {
            imageView.image = image
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let backgroundSettingsDidChange = Notification.Name("backgroundSettingsDidChange")
}

// MARK: - UserDefaults helpers

struct BackgroundSettings {

    enum Mode: String { case none, transparent, image }

    let mode:         Mode
    let alpha:        CGFloat       // 투명도 (transparent 모드)
    let imageURL:     URL?          // 보안 범위 해제된 URL
    let contentMode:  BackgroundView.ImageContentMode
    let overlayAlpha: CGFloat

    /// UserDefaults에서 현재 설정 로드.
    static func load() -> BackgroundSettings {
        let ud    = UserDefaults.standard
        let mode  = Mode(rawValue: ud.string(forKey: Preferences.Keys.editorBackgroundMode) ?? "") ?? .none
        // object(forKey:)로 nil 여부를 구분 — double(forKey:)는 미설정 시 0을 반환해
        // 사용자가 명시적으로 0을 설정한 경우와 구분할 수 없음.
        let alpha = CGFloat((ud.object(forKey: Preferences.Keys.editorBackgroundAlpha) as? Double ?? 0.85)
                        .clamped(to: 0...1))
        let cm    = BackgroundView.ImageContentMode(
            rawValue: ud.string(forKey: Preferences.Keys.editorImageContentMode) ?? "") ?? .fill
        let oa    = CGFloat((ud.object(forKey: Preferences.Keys.editorOverlayAlpha) as? Double ?? 0.3)
                        .clamped(to: 0...1))

        var imgURL: URL? = nil
        if mode == .image,
           let data = ud.data(forKey: Preferences.Keys.editorBackgroundBookmark) {
            var stale = false
            imgURL = try? URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
        }
        return BackgroundSettings(mode: mode, alpha: alpha, imageURL: imgURL,
                                  contentMode: cm, overlayAlpha: oa)
    }

    /// UserDefaults에 저장.
    func save() {
        let ud = UserDefaults.standard
        ud.set(mode.rawValue, forKey: Preferences.Keys.editorBackgroundMode)
        ud.set(Double(alpha),        forKey: Preferences.Keys.editorBackgroundAlpha)
        ud.set(contentMode.rawValue, forKey: Preferences.Keys.editorImageContentMode)
        ud.set(Double(overlayAlpha), forKey: Preferences.Keys.editorOverlayAlpha)

        if let url = imageURL,
           let data = try? url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            ud.set(data, forKey: Preferences.Keys.editorBackgroundBookmark)
        }
    }
}

// MARK: - Double helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
