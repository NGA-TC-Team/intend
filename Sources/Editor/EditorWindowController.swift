import AppKit
import UniformTypeIdentifiers

// MARK: - Tab Container

/// 탭 바 + 현재 활성 EditorViewController를 담는 컨테이너 VC.
/// NSSplitViewItem의 viewController로 사용.
final class TabContainerViewController: NSViewController {

    let tabBarView = TabBarView()
    private var activeEditorVC: EditorViewController?

    override func loadView() {
        view = NSView()
        view.addSubview(tabBarView)
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: TabBarView.height),
        ])
    }

    func switchTo(_ editorVC: EditorViewController) {
        if activeEditorVC === editorVC { return }
        activeEditorVC?.view.removeFromSuperview()
        activeEditorVC = editorVC

        editorVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorVC.view)
        NSLayoutConstraint.activate([
            editorVC.view.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            editorVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - EditorWindowController

final class EditorWindowController: NSWindowController {

    // MARK: - Permanent child VCs (shared across all tabs)

    private let sidebarVC     = SidebarViewController()
    private let previewVC     = PreviewViewController()
    private let tocVC         = TOCViewController()
    private let tabContainerVC = TabContainerViewController()

    // MARK: - Split items

    private var previewSplitItem: NSSplitViewItem?
    private var tocSplitItem:     NSSplitViewItem?
    private var sidebarSplitItem: NSSplitViewItem?

    // MARK: - Tab state

    private var tabs:           [TabItem] = []
    private var activeTabIndex: Int = 0

    private var activeTab: TabItem? {
        guard !tabs.isEmpty, tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }

    // MARK: - Focus Mode

    private var isFocusModeActive        = false
    private var preFocusSidebarCollapsed = false
    private var preFocusTOCCollapsed     = false

    // MARK: - Init

    init() {
        let window = Self.makeWindow()
        super.init(window: window)

        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical   = true
        // "V3" suffix: 탭 시스템 도입으로 autosave 레이아웃 초기화
        splitVC.splitView.autosaveName = "EditorSplitViewV3"
        splitVC.splitView.dividerStyle = .thin

        // sidebarWithViewController 대신 일반 viewController 사용:
        // sidebarWithViewController는 자동으로 safe-area inset + 라운드 컨테이너를 추가해
        // 탭 바 상단과 정렬이 깨지는 원인이 됨.
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness           = 160
        sidebarItem.maximumThickness           = 340
        sidebarItem.preferredThicknessFraction = 0.20
        splitVC.addSplitViewItem(sidebarItem)
        sidebarSplitItem = sidebarItem

        let editorItem = NSSplitViewItem(viewController: tabContainerVC)
        editorItem.minimumThickness = 360
        splitVC.addSplitViewItem(editorItem)

        let preview = NSSplitViewItem(viewController: previewVC)
        preview.minimumThickness = 280
        preview.isCollapsed      = true
        splitVC.addSplitViewItem(preview)
        previewSplitItem = preview

        let tocVisible = UserDefaults.standard.object(forKey: Preferences.Keys.tocPanelVisible) as? Bool ?? true
        let toc = NSSplitViewItem(viewController: tocVC)
        toc.minimumThickness = 160
        toc.maximumThickness = 320
        toc.isCollapsed      = !tocVisible
        splitVC.addSplitViewItem(toc)
        tocSplitItem = toc

        contentViewController = splitVC
        sidebarVC.delegate    = self
        tocVC.delegate        = self

        // 탭 바 이벤트 연결
        tabContainerVC.tabBarView.onSelectTab = { [weak self] idx in self?.switchTab(to: idx) }
        tabContainerVC.tabBarView.onCloseTab  = { [weak self] idx in self?.closeTab(at: idx) }
        tabContainerVC.tabBarView.onRenameTab = { [weak self] idx, name in
            guard let self, self.tabs.indices.contains(idx) else { return }
            self.tabs[idx].customDisplayName = name
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func windowDidLoad() {
        super.windowDidLoad()
        DispatchQueue.main.async { [weak self] in
            guard let self, let tocSplitItem else { return }
            let visible = UserDefaults.standard.object(forKey: Preferences.Keys.tocPanelVisible) as? Bool ?? true
            tocSplitItem.isCollapsed = !visible
        }
        setupToolbar()
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate               = self
        toolbar.displayMode            = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    // MARK: - Tab Management (public)

    /// 새 문서를 탭으로 추가. 추가 직후 활성화.
    func addTab(document: MarkdownDocument, activate: Bool = true) {
        let editorVC = EditorViewController()
        setupCallbacks(for: editorVC)

        // Finder 드래그앤드롭: 드롭된 .md 파일을 새 탭으로 열기
        editorVC.onFileDropped = { [weak self] url in
            self?.openDroppedFile(url)
        }

        let tab = TabItem(document: document, editorVC: editorVC)
        tabs.append(tab)

        editorVC.load(document: document)

        // 최근 파일 목록 갱신
        sidebarVC.refresh()

        // 초기 TOC 채우기
        let entries = extractTOCEntries(from: parse(markdown: document.source))
        tocVC.reload(entries: entries)

        if activate {
            switchTab(to: tabs.count - 1)
        }
        reloadTabBar()
    }

    /// 활성 탭 닫기. 마지막 탭이면 창 닫기.
    @IBAction func closeActiveTab(_ sender: Any?) {
        closeTab(at: activeTabIndex)
    }

    /// 다음 탭으로 전환 (Ctrl+Tab).
    @IBAction func selectNextEditorTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        switchTab(to: (activeTabIndex + 1) % tabs.count)
    }

    /// 이전 탭으로 전환 (Ctrl+Shift+Tab).
    @IBAction func selectPreviousEditorTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        switchTab(to: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }

    /// 암호화 파일 열기 시: 비밀번호 시트 표시 후 addTab.
    func requestDecryption(for document: MarkdownDocument) {
        guard let window else { return }
        PasswordSheetController.promptForDecrypt(relativeTo: window) { [weak self, weak document] password in
            guard let self, let document else { return }
            guard let password else { document.close(); return }
            do {
                try document.decrypt(with: password)
                self.addTab(document: document)
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window) { _ in
                    self.requestDecryption(for: document)
                }
            }
        }
    }

    /// 암호화 문서 최초 열기 시 창 표시 후 비밀번호 시트.
    /// (MarkdownDocument.makeWindowControllers에서 신규 WC 생성 경로에만 사용)
    func showWindowAndRequestDecryption(document: MarkdownDocument) {
        showWindow(nil)
        requestDecryption(for: document)
    }

    // MARK: - Tab Management (private)

    private func switchTab(to index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        let tab = tabs[index]

        tabContainerVC.switchTo(tab.editorVC)
        window?.title = tab.displayName
        previewVC.update(markdown: tab.document.source)

        // TOC 갱신
        let entries = extractTOCEntries(from: parse(markdown: tab.document.source))
        tocVC.reload(entries: entries)

        reloadTabBar()
        window?.makeFirstResponder(tab.editorVC.focusableView)
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }

        if tabs.count == 1 {
            // 마지막 탭: 창 닫기
            window?.performClose(nil)
            return
        }

        let tab = tabs.remove(at: index)
        // NSDocument에서 이 WC 연결 해제 후 문서 닫기
        tab.document.removeWindowController(self)
        if tab.document.windowControllers.isEmpty {
            tab.document.close()
        }

        // 활성 인덱스 조정
        let newIndex = min(index, tabs.count - 1)
        switchTab(to: newIndex)
        reloadTabBar()
    }

    private func setupCallbacks(for editorVC: EditorViewController) {
        editorVC.onTextChange = { [weak self, weak editorVC] markdown in
            guard let self, let editorVC, self.activeTab?.editorVC === editorVC else { return }
            self.previewVC.update(markdown: markdown)
        }
        editorVC.onTOCEntriesChange = { [weak self, weak editorVC] entries in
            guard let self, let editorVC else { return }
            // 활성 탭에만 TOC 갱신 + H1 제목 동기화
            guard let idx = self.tabs.firstIndex(where: { $0.editorVC === editorVC }) else { return }
            if self.activeTab?.editorVC === editorVC {
                self.tocVC.reload(entries: entries)
            }
            // H1이 있고 사용자 지정 이름이 없으면 탭 제목으로 사용
            if self.tabs[idx].customDisplayName == nil {
                let h1Title = entries.first(where: { $0.level == 1 })?.title
                if self.tabs[idx].h1Title != h1Title {
                    self.tabs[idx].h1Title = h1Title
                    self.reloadTabBar()
                    if self.activeTabIndex == idx {
                        self.window?.title = self.tabs[idx].displayName
                    }
                }
            }
        }
    }

    private func reloadTabBar() {
        tabContainerVC.tabBarView.reload(tabs: tabs, activeIndex: activeTabIndex)
    }

    // MARK: - Toggle actions

    @IBAction func toggleSidebar(_ sender: Any?) {
        sidebarSplitItem?.animator().isCollapsed.toggle()
    }

    @IBAction func togglePreview(_ sender: Any?) {
        previewSplitItem?.animator().isCollapsed.toggle()
    }

    @IBAction func toggleTOC(_ sender: Any?) {
        guard let tocSplitItem else { return }
        tocSplitItem.animator().isCollapsed.toggle()
        UserDefaults.standard.set(!tocSplitItem.isCollapsed, forKey: Preferences.Keys.tocPanelVisible)
    }

    @IBAction func toggleFocusMode(_ sender: Any?) {
        guard let sidebarSplitItem, let tocSplitItem else { return }

        if isFocusModeActive {
            sidebarSplitItem.animator().isCollapsed = preFocusSidebarCollapsed
            tocSplitItem.animator().isCollapsed     = preFocusTOCCollapsed
            UserDefaults.standard.set(!preFocusTOCCollapsed, forKey: Preferences.Keys.tocPanelVisible)
            isFocusModeActive = false
        } else {
            preFocusSidebarCollapsed = sidebarSplitItem.isCollapsed
            preFocusTOCCollapsed     = tocSplitItem.isCollapsed
            sidebarSplitItem.animator().isCollapsed = true
            tocSplitItem.animator().isCollapsed     = true
            isFocusModeActive = true
        }

        window?.toolbar?.items
            .first(where: { $0.itemIdentifier.rawValue == "focusMode" })?
            .image = focusModeIcon()
    }

    private func focusModeIcon() -> NSImage {
        let name = isFocusModeActive
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
        return NSImage(systemSymbolName: name, accessibilityDescription: "포커스 모드") ?? NSImage()
    }

    // MARK: - Lock (암호화 저장)

    @IBAction func lockWithPassword(_ sender: Any?) {
        guard let doc = activeTab?.document else { return }

        // 저장 패널에 비밀번호 입력 필드를 accessoryView로 삽입
        let pw1 = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        pw1.placeholderString = String(localized: "editor.lock.placeholder.password")
        pw1.bezelStyle = .roundedBezel

        let pw2 = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        pw2.placeholderString = String(localized: "editor.lock.placeholder.confirm")
        pw2.bezelStyle = .roundedBezel

        let stack = NSStackView(views: [pw1, pw2])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 72))
        accessory.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
        ])

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType("com.intend.encrypted-markdown") ?? .data]
        let baseName = doc.displayName
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: ".markdown", with: "")
        panel.nameFieldStringValue = baseName + ".mdxk"
        panel.message = String(localized: "editor.lock.panel.message")
        panel.accessoryView = accessory

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let p1 = pw1.stringValue
            let p2 = pw2.stringValue
            guard !p1.isEmpty else {
                self?.presentEncryptError(String(localized: "editor.lock.error.empty"))
                return
            }
            guard p1 == p2 else {
                self?.presentEncryptError(String(localized: "editor.lock.error.mismatch"))
                return
            }
            do {
                try doc.saveAsEncrypted(password: p1, to: url)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private func presentEncryptError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle  = .warning
        alert.addButton(withTitle: String(localized: "action.confirm"))
        if let window {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    // MARK: - Export actions

    @IBAction func exportHTML(_ sender: Any?) {
        guard let doc = activeTab?.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.html]
        panel.nameFieldStringValue = doc.displayName + ".html"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let result = parse(markdown: doc.source)
            let html   = renderHTML(from: result, config: ConfigManager.shared.current)
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    @IBAction func exportPDF(_ sender: Any?) {
        guard let doc = activeTab?.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.pdf]
        panel.nameFieldStringValue = doc.displayName + ".pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let result = parse(markdown: doc.source)
            let html   = renderHTML(from: result, config: ConfigManager.shared.current)
            PDFExporter.export(html: html, to: url) { error in
                if let error { NSApp.presentError(error) }
            }
        }
    }

    // MARK: - Private

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            // fullSizeContentView 제거: 콘텐츠 영역이 타이틀바/툴바 아래에서 시작하도록
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title       = "Intend"
        window.minSize     = NSSize(width: 560, height: 400)
        // macOS State Restoration 비활성화: pkill 후 재실행 시 이전 윈도우 크기가
        // 복원돼 contentRect 지정값을 덮어쓰는 현상 방지.
        // 사용자가 크기를 바꾼 뒤의 재실행 크기는 setFrameAutosaveName이 별도로 관리.
        window.isRestorable = false
        window.center()
        window.setFrameAutosaveName("EditorWindowV3")
        return window
    }
}

// MARK: - NSToolbarDelegate

extension EditorWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("focusMode")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("focusMode")]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier.rawValue == "focusMode" else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label   = "포커스 모드"
        item.toolTip = "포커스 모드 (⌘\\)"
        item.image   = focusModeIcon()
        item.action  = #selector(toggleFocusMode(_:))
        item.target  = self
        return item
    }
}

// MARK: - SidebarViewControllerDelegate

extension EditorWindowController: SidebarViewControllerDelegate {
    func sidebar(_ vc: SidebarViewController, didSelectFile url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}

// MARK: - Drag and Drop (Finder → New Tab)

extension EditorWindowController {
    /// Finder에서 드롭된 .md 파일을 새 탭으로 열기.
    func openDroppedFile(_ url: URL) {
        let normalizedURL = url.standardizedFileURL

        if let existingIndex = tabs.firstIndex(where: {
            $0.document.fileURL?.standardizedFileURL == normalizedURL
        }) {
            switchTab(to: existingIndex)
            return
        }

        if let existingDocument = NSDocumentController.shared.documents
            .compactMap({ $0 as? MarkdownDocument })
            .first(where: { $0.fileURL?.standardizedFileURL == normalizedURL }) {
            attachDroppedDocument(existingDocument)
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: normalizedURL, display: false) { [weak self] document, _, error in
            guard let self else { return }
            if let error {
                NSApp.presentError(error)
                return
            }
            guard let document = document as? MarkdownDocument else { return }
            self.attachDroppedDocument(document)
        }
    }

    private func attachDroppedDocument(_ document: MarkdownDocument) {
        if let existingIndex = tabs.firstIndex(where: { $0.document === document }) {
            switchTab(to: existingIndex)
            return
        }

        if !document.windowControllers.contains(where: { $0 === self }) {
            document.addWindowController(self)
        }
        addTab(document: document)
    }
}

// MARK: - TOCViewControllerDelegate

extension EditorWindowController: TOCViewControllerDelegate {
    func toc(_ vc: TOCViewController, didSelectEntry entry: TOCEntry) {
        activeTab?.editorVC.scrollToHeading(offset: entry.characterOffset)
    }
}
