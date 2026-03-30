import AppKit

// MARK: - Window Controller (싱글톤)

final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = String(localized: "prefs.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        contentViewController = PreferencesTabController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Tab Controller

private final class PreferencesTabController: NSTabViewController {

    override func loadView() {
        super.loadView()
        tabStyle = .toolbar
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addTabItem(EditorPrefsViewController(),     label: String(localized: "prefs.tab.editor"),     image: "textformat")
        addTabItem(RenderingPrefsViewController(),  label: String(localized: "prefs.tab.rendering"),  image: "doc.richtext")
        addTabItem(ThemePrefsViewController(),      label: String(localized: "prefs.tab.theme"),      image: "paintbrush")
        addTabItem(BackgroundPrefsViewController(), label: String(localized: "prefs.tab.background"), image: "photo")
    }

    private func addTabItem(_ vc: NSViewController, label: String, image: String) {
        let item = NSTabViewItem(viewController: vc)
        item.label = label
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        addTabViewItem(item)
    }
}

// MARK: - Shared form helpers

/// 레이블 + 컨트롤 행을 만드는 헬퍼.
private func formRow(label: String, control: NSView) -> NSStackView {
    let lbl = NSTextField(labelWithString: label)
    lbl.font            = .systemFont(ofSize: 13)
    lbl.alignment       = .right
    lbl.widthAnchor.constraint(equalToConstant: 130).isActive = true

    let row = NSStackView(views: [lbl, control])
    row.orientation = .horizontal
    row.spacing     = 8
    row.alignment   = .centerY
    return row
}

private func sectionLabel(_ text: String) -> NSTextField {
    let lbl = NSTextField(labelWithString: text)
    lbl.font        = .boldSystemFont(ofSize: 11)
    lbl.textColor   = .secondaryLabelColor
    return lbl
}

// MARK: - Editor Preferences

private final class EditorPrefsViewController: NSViewController {

    private var draft = ConfigManager.shared.current

    /// 시스템 폰트를 나타내는 sentinel 값 (AppConfig.swift의 전역 상수 참조).
    static let systemFontSentinel = systemFontFamilySentinel

    private let fontFamilyPopup = NSPopUpButton()
    private let fontSizeStepper = NSStepper()
    private let fontSizeField   = NSTextField()
    private let tabSizeStepper  = NSStepper()
    private let tabSizeField    = NSTextField()

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 360)

        // Font family — NSPopUpButton with system font families
        buildFontFamilyPopup()
        fontFamilyPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        fontFamilyPopup.target = self
        fontFamilyPopup.action = #selector(fontFamilyChanged)

        // Font size
        fontSizeStepper.minValue  = 8;  fontSizeStepper.maxValue = 48
        fontSizeStepper.increment = 1;  fontSizeStepper.doubleValue = draft.editor.font.size
        fontSizeStepper.target    = self; fontSizeStepper.action = #selector(fontSizeChanged)
        fontSizeField.doubleValue = draft.editor.font.size
        fontSizeField.isEditable  = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let sizeRow = NSStackView(views: [fontSizeStepper, fontSizeField])
        sizeRow.spacing = 4

        // Tab size
        tabSizeStepper.minValue  = 2;  tabSizeStepper.maxValue = 8
        tabSizeStepper.increment = 2;  tabSizeStepper.integerValue = draft.editor.tabSize
        tabSizeStepper.target    = self; tabSizeStepper.action = #selector(tabSizeChanged)
        tabSizeField.integerValue = draft.editor.tabSize
        tabSizeField.isEditable   = false
        tabSizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let tabRow = NSStackView(views: [tabSizeStepper, tabSizeField])
        tabRow.spacing = 4

        // Apply button
        let applyBtn = NSButton(title: String(localized: "action.apply"), target: self, action: #selector(apply))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            sectionLabel(String(localized: "prefs.section.font")),
            formRow(label: String(localized: "prefs.label.fontFamily"), control: fontFamilyPopup),
            formRow(label: String(localized: "prefs.label.fontSize"),   control: sizeRow),
            sectionLabel(String(localized: "prefs.section.editing")),
            formRow(label: String(localized: "prefs.label.tabSize"),    control: tabRow),
            NSView(),  // spacer
            applyBtn,
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 12
        stack.edgeInsets  = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Font popup setup

    private func buildFontFamilyPopup() {
        fontFamilyPopup.removeAllItems()

        // 첫 번째 항목: 시스템 폰트 (SF Pro)
        let sysItem = NSMenuItem()
        sysItem.title            = String(localized: "prefs.font.system")
        sysItem.representedObject = Self.systemFontSentinel
        sysItem.attributedTitle  = NSAttributedString(
            string: String(localized: "prefs.font.system"),
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        fontFamilyPopup.menu?.addItem(sysItem)
        fontFamilyPopup.menu?.addItem(.separator())

        // 시스템에 설치된 모든 폰트 패밀리 (알파벳 정렬)
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        for family in families {
            let item = NSMenuItem()
            item.title             = family
            item.representedObject = family
            // 각 항목을 해당 폰트로 표시
            if let font = NSFont(name: family, size: 13) {
                item.attributedTitle = NSAttributedString(
                    string: family,
                    attributes: [.font: font]
                )
            }
            fontFamilyPopup.menu?.addItem(item)
        }

        // 현재 설정값에 맞는 항목 선택
        selectCurrentFont()
    }

    private func selectCurrentFont() {
        let current = draft.editor.font.family
        if current == Self.systemFontSentinel || current.isEmpty {
            fontFamilyPopup.selectItem(at: 0)
            return
        }
        // representedObject 기준으로 탐색
        for item in fontFamilyPopup.itemArray {
            if (item.representedObject as? String) == current {
                fontFamilyPopup.select(item)
                return
            }
        }
        // 목록에 없으면 첫 번째(시스템 폰트)로 fallback
        fontFamilyPopup.selectItem(at: 0)
    }

    // MARK: - Actions

    @objc private func fontFamilyChanged() {
        let selected = fontFamilyPopup.selectedItem?.representedObject as? String
            ?? Self.systemFontSentinel
        draft.editor.font.family = selected
    }

    @objc private func fontSizeChanged() {
        draft.editor.font.size = fontSizeStepper.doubleValue
        fontSizeField.doubleValue = fontSizeStepper.doubleValue
    }

    @objc private func tabSizeChanged() {
        draft.editor.tabSize = tabSizeStepper.integerValue
        tabSizeField.integerValue = tabSizeStepper.integerValue
    }

    @objc private func apply() {
        saveUserConfig(draft)
    }
}

// MARK: - Rendering Preferences

private final class RenderingPrefsViewController: NSViewController {

    private var draft = ConfigManager.shared.current

    private let lineHeightSlider = NSSlider()
    private let lineHeightField  = NSTextField()

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 360)

        lineHeightSlider.minValue    = 1.0; lineHeightSlider.maxValue = 3.0
        lineHeightSlider.doubleValue = draft.rendering.paragraph.lineHeight
        lineHeightSlider.target      = self; lineHeightSlider.action = #selector(lineHeightChanged)
        lineHeightSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        lineHeightField.doubleValue = draft.rendering.paragraph.lineHeight
        lineHeightField.isEditable  = false
        lineHeightField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let lhRow = NSStackView(views: [lineHeightSlider, lineHeightField])
        lhRow.spacing = 6

        let applyBtn = NSButton(title: String(localized: "action.apply"), target: self, action: #selector(apply))
        applyBtn.bezelStyle    = .rounded
        applyBtn.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            sectionLabel(String(localized: "prefs.section.paragraph")),
            formRow(label: String(localized: "prefs.label.lineHeight"), control: lhRow),
            NSView(),
            applyBtn,
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 12
        stack.edgeInsets  = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func lineHeightChanged() {
        let v = lineHeightSlider.doubleValue
        draft.rendering.paragraph.lineHeight = v
        lineHeightField.stringValue = String(format: "%.1f", v)
    }

    @objc private func apply() {
        saveUserConfig(draft)
    }
}

// MARK: - Theme Preferences

private final class ThemePrefsViewController: NSViewController {

    private var draft = ConfigManager.shared.current

    private let appearanceControl = NSSegmentedControl(
        labels: [
            String(localized: "prefs.appearance.system"),
            String(localized: "prefs.appearance.light"),
            String(localized: "prefs.appearance.dark"),
        ],
        trackingMode: .selectOne,
        target: nil, action: nil
    )
    private let accentColorWell  = NSColorWell(style: .minimal)
    private let resetAccentButton = NSButton(title: String(localized: "action.resetToDefault"), target: nil, action: nil)

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 360)

        // 현재 appearance 설정에 따라 세그먼트 선택
        switch draft.theme.appearance {
        case "light": appearanceControl.selectedSegment = 1
        case "dark":  appearanceControl.selectedSegment = 2
        default:      appearanceControl.selectedSegment = 0
        }
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged)

        // 강조색 컬러웰
        accentColorWell.color  = ThemeManager.shared.accentColor
        accentColorWell.target = self
        accentColorWell.action = #selector(accentColorChanged)
        accentColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        accentColorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        resetAccentButton.bezelStyle = .rounded
        resetAccentButton.target     = self
        resetAccentButton.action     = #selector(resetAccent)

        let accentRow = NSStackView(views: [accentColorWell, resetAccentButton])
        accentRow.spacing = 8

        let applyBtn = NSButton(title: String(localized: "action.apply"), target: self, action: #selector(apply))
        applyBtn.bezelStyle    = .rounded
        applyBtn.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            sectionLabel(String(localized: "prefs.section.appearance")),
            formRow(label: String(localized: "prefs.label.colorMode"),    control: appearanceControl),
            sectionLabel(String(localized: "prefs.section.accentColor")),
            formRow(label: String(localized: "prefs.label.accentColor"),  control: accentRow),
            NSView(),
            applyBtn,
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 12
        stack.edgeInsets  = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func appearanceChanged() {
        switch appearanceControl.selectedSegment {
        case 1:  draft.theme.appearance = "light"
        case 2:  draft.theme.appearance = "dark"
        default: draft.theme.appearance = "system"
        }
    }

    @objc private func accentColorChanged() {
        draft.theme.colors.accent = accentColorWell.color.hexString
    }

    @objc private func resetAccent() {
        draft.theme.colors.accent = nil
        accentColorWell.color     = NSColor.controlAccentColor
    }

    @objc private func apply() {
        saveUserConfig(draft)
        // 외관 변경: NSApp appearance override
        switch draft.theme.appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil  // 시스템 따라가기
        }
    }
}

// MARK: - Background Preferences

private final class BackgroundPrefsViewController: NSViewController {

    private let ud = UserDefaults.standard

    // Controls
    private let modeControl = NSSegmentedControl(
        labels: [
            String(localized: "prefs.bg.none"),
            String(localized: "prefs.bg.transparent"),
            String(localized: "prefs.bg.image"),
        ],
        trackingMode: .selectOne,
        target: nil, action: nil
    )
    private let alphaSlider     = NSSlider()
    private let alphaField      = NSTextField()
    private let imageButton     = NSButton(title: String(localized: "action.chooseImage"), target: nil, action: nil)
    private let imagePathField  = NSTextField()
    private let contentModeControl = NSSegmentedControl(
        labels: [
            String(localized: "prefs.bg.fill"),
            String(localized: "prefs.bg.tile"),
            String(localized: "prefs.bg.center"),
        ],
        trackingMode: .selectOne,
        target: nil, action: nil
    )
    private let overlaySlider   = NSSlider()
    private let overlayField    = NSTextField()
    private var selectedImageURL: URL?

    // Dynamic rows
    private var transparentRows: [NSView] = []
    private var imageRows:       [NSView] = []
    private var stack: NSStackView!

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        setupControls()
        buildStack()
        restoreValues()
        updateVisibility()
    }

    // MARK: - Setup

    private func setupControls() {
        modeControl.target = self; modeControl.action = #selector(modeChanged)

        alphaSlider.minValue = 0; alphaSlider.maxValue = 1; alphaSlider.numberOfTickMarks = 0
        alphaSlider.target = self; alphaSlider.action = #selector(alphaChanged)
        alphaField.isEditable = false
        alphaField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        imageButton.target = self; imageButton.action = #selector(chooseImage)
        imageButton.bezelStyle = .rounded

        imagePathField.isEditable  = false
        imagePathField.placeholderString = String(localized: "prefs.bg.noImageSelected")
        imagePathField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        contentModeControl.target = self; contentModeControl.action = #selector(contentModeChanged)

        overlaySlider.minValue = 0; overlaySlider.maxValue = 1
        overlaySlider.target = self; overlaySlider.action = #selector(overlayChanged)
        overlayField.isEditable = false
        overlayField.widthAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func buildStack() {
        let alphaRow   = makeSliderRow(label: String(localized: "prefs.label.alpha"),        slider: alphaSlider,   field: alphaField)
        let overlayRow = makeSliderRow(label: String(localized: "prefs.label.overlayAlpha"), slider: overlaySlider, field: overlayField)
        let imgRow     = formRow(label: String(localized: "prefs.label.image"), control: imageButton)
        let pathRow    = formRow(label: "", control: imagePathField)
        let cmRow      = formRow(label: String(localized: "prefs.label.scale"), control: contentModeControl)

        transparentRows = [alphaRow]
        imageRows       = [imgRow, pathRow, cmRow, overlayRow]

        stack = NSStackView(views: [
            sectionLabel(String(localized: "prefs.section.backgroundMode")),
            formRow(label: String(localized: "prefs.label.mode"), control: modeControl),
            alphaRow,
            imgRow, pathRow, cmRow, overlayRow,
            NSView(),
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 12
        stack.edgeInsets  = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeSliderRow(label: String, slider: NSSlider, field: NSTextField) -> NSStackView {
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let inner = NSStackView(views: [slider, field])
        inner.spacing = 6
        return formRow(label: label, control: inner)
    }

    // MARK: - Restore

    private func restoreValues() {
        let settings = BackgroundSettings.load()
        switch settings.mode {
        case .none:        modeControl.selectedSegment = 0
        case .transparent: modeControl.selectedSegment = 1
        case .image:       modeControl.selectedSegment = 2
        }
        alphaSlider.doubleValue   = Double(settings.alpha)
        alphaField.stringValue    = String(format: "%.0f%%", settings.alpha * 100)
        overlaySlider.doubleValue = Double(settings.overlayAlpha)
        overlayField.stringValue  = String(format: "%.0f%%", settings.overlayAlpha * 100)
        switch settings.contentMode {
        case .fill:   contentModeControl.selectedSegment = 0
        case .tile:   contentModeControl.selectedSegment = 1
        case .center: contentModeControl.selectedSegment = 2
        }
        if let url = settings.imageURL {
            selectedImageURL        = url
            imagePathField.stringValue = url.lastPathComponent
        }
    }

    // MARK: - Visibility

    private func updateVisibility() {
        let seg = modeControl.selectedSegment
        transparentRows.forEach { $0.isHidden = seg != 1 }
        imageRows.forEach       { $0.isHidden = seg != 2 }
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        updateVisibility()
        commitAndNotify()
    }

    @objc private func alphaChanged() {
        alphaField.stringValue = String(format: "%.0f%%", alphaSlider.doubleValue * 100)
        commitAndNotify()
    }

    @objc private func overlayChanged() {
        overlayField.stringValue = String(format: "%.0f%%", overlaySlider.doubleValue * 100)
        commitAndNotify()
    }

    @objc private func contentModeChanged() { commitAndNotify() }

    @objc private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.selectedImageURL           = url
            self.imagePathField.stringValue = url.lastPathComponent
            self.commitAndNotify()
        }
    }

    private func commitAndNotify() {
        let modeMap: [BackgroundSettings.Mode] = [.none, .transparent, .image]
        let cmMap: [BackgroundView.ImageContentMode] = [.fill, .tile, .center]

        let settings = BackgroundSettings(
            mode:         modeMap[modeControl.selectedSegment],
            alpha:        CGFloat(alphaSlider.doubleValue),
            imageURL:     selectedImageURL,
            contentMode:  cmMap[contentModeControl.selectedSegment],
            overlayAlpha: CGFloat(overlaySlider.doubleValue)
        )
        settings.save()
        NotificationCenter.default.post(name: .backgroundSettingsDidChange, object: nil)
    }
}
