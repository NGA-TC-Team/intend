import AppKit

/// 앱 메뉴 바 전체를 코드로 구성.
/// applicationDidFinishLaunching 에서 한 번 호출.
@MainActor
enum MenuBuilder {

    static func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem())
        main.addItem(viewMenuItem())
        main.addItem(windowMenuItem())
        return main
    }

    // MARK: - Intend 앱 메뉴

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let sub  = NSMenu(title: "Intend")

        sub.addItem(withTitle: String(localized: "menu.app.about"),
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")

        sub.addItem(.separator())

        let prefs = NSMenuItem(title: String(localized: "menu.app.preferences"),
                               action: #selector(AppDelegate.showPreferences(_:)),
                               keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = .command
        sub.addItem(prefs)

        sub.addItem(.separator())

        sub.addItem(withTitle: String(localized: "menu.app.hide"),
                    action: #selector(NSApplication.hide(_:)),
                    keyEquivalent: "h")

        let hideOthers = NSMenuItem(title: String(localized: "menu.app.hideOthers"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        sub.addItem(hideOthers)

        sub.addItem(withTitle: String(localized: "menu.app.showAll"),
                    action: #selector(NSApplication.unhideAllApplications(_:)),
                    keyEquivalent: "")

        sub.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "menu.app.quit"),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        sub.addItem(quit)

        item.submenu = sub
        return item
    }

    // MARK: - File 메뉴

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "menu.file"), action: nil, keyEquivalent: "")
        let sub  = NSMenu(title: String(localized: "menu.file"))

        // 새 문서
        let new = NSMenuItem(title: String(localized: "menu.file.new"),
                             action: #selector(NSDocumentController.newDocument(_:)),
                             keyEquivalent: "n")
        new.keyEquivalentModifierMask = .command
        sub.addItem(new)

        // 열기
        let open = NSMenuItem(title: String(localized: "menu.file.open"),
                              action: #selector(NSDocumentController.openDocument(_:)),
                              keyEquivalent: "o")
        open.keyEquivalentModifierMask = .command
        sub.addItem(open)

        sub.addItem(.separator())

        // 닫기 (활성 탭 닫기)
        let close = NSMenuItem(title: String(localized: "menu.file.close"),
                               action: #selector(EditorWindowController.closeActiveTab(_:)),
                               keyEquivalent: "w")
        close.keyEquivalentModifierMask = .command
        sub.addItem(close)

        // 저장
        let save = NSMenuItem(title: String(localized: "menu.file.save"),
                              action: #selector(NSDocument.save(_:)),
                              keyEquivalent: "s")
        save.keyEquivalentModifierMask = .command
        sub.addItem(save)

        // 다른 이름으로 저장
        let saveAs = NSMenuItem(title: String(localized: "menu.file.saveAs"),
                                action: #selector(NSDocument.saveAs(_:)),
                                keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(saveAs)

        sub.addItem(.separator())

        // 내보내기
        let exportHTML = NSMenuItem(title: String(localized: "menu.file.exportHTML"),
                                    action: #selector(EditorWindowController.exportHTML(_:)),
                                    keyEquivalent: "")
        sub.addItem(exportHTML)

        let exportPDF = NSMenuItem(title: String(localized: "menu.file.exportPDF"),
                                   action: #selector(EditorWindowController.exportPDF(_:)),
                                   keyEquivalent: "")
        sub.addItem(exportPDF)

        sub.addItem(.separator())

        // 암호화 저장
        let lock = NSMenuItem(title: String(localized: "menu.file.lock"),
                              action: #selector(EditorWindowController.lockWithPassword(_:)),
                              keyEquivalent: "")
        sub.addItem(lock)

        item.submenu = sub
        return item
    }

    // MARK: - Edit 메뉴

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "menu.edit"), action: nil, keyEquivalent: "")
        let sub  = NSMenu(title: String(localized: "menu.edit"))

        sub.addItem(withTitle: String(localized: "menu.edit.undo"),      action: #selector(UndoManager.undo),       keyEquivalent: "z")
        let redo = NSMenuItem(title: String(localized: "menu.edit.redo"),
                              action: #selector(UndoManager.redo),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(redo)
        sub.addItem(.separator())
        sub.addItem(withTitle: String(localized: "menu.edit.cut"),       action: #selector(NSText.cut(_:)),         keyEquivalent: "x")
        sub.addItem(withTitle: String(localized: "menu.edit.copy"),      action: #selector(NSText.copy(_:)),        keyEquivalent: "c")
        sub.addItem(withTitle: String(localized: "menu.edit.paste"),     action: #selector(NSText.paste(_:)),       keyEquivalent: "v")
        sub.addItem(withTitle: String(localized: "menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)),   keyEquivalent: "a")
        sub.addItem(.separator())

        // 찾기
        let find = NSMenuItem(title: String(localized: "menu.edit.find"),
                              action: #selector(EditorViewController.performFindAction(_:)),
                              keyEquivalent: "f")
        find.keyEquivalentModifierMask = .command
        sub.addItem(find)

        // 찾기/바꾸기
        let findReplace = NSMenuItem(title: String(localized: "menu.edit.findReplace"),
                                     action: #selector(EditorViewController.performFindReplaceAction(_:)),
                                     keyEquivalent: "f")
        findReplace.keyEquivalentModifierMask = [.command, .option]
        sub.addItem(findReplace)

        // 다음/이전 찾기
        let findNext = NSMenuItem(title: String(localized: "menu.edit.findNext"),
                                  action: #selector(EditorViewController.findNext(_:)),
                                  keyEquivalent: "g")
        findNext.keyEquivalentModifierMask = .command
        sub.addItem(findNext)

        let findPrev = NSMenuItem(title: String(localized: "menu.edit.findPrev"),
                                  action: #selector(EditorViewController.findPrevious(_:)),
                                  keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(findPrev)

        item.submenu = sub
        return item
    }

    // MARK: - View 메뉴

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "menu.view"), action: nil, keyEquivalent: "")
        let sub  = NSMenu(title: String(localized: "menu.view"))

        let focus = NSMenuItem(title: String(localized: "menu.view.focusMode"),
                               action: #selector(EditorWindowController.toggleFocusMode(_:)),
                               keyEquivalent: "\\")
        focus.keyEquivalentModifierMask = .command
        sub.addItem(focus)

        sub.addItem(.separator())

        let preview = NSMenuItem(title: String(localized: "menu.view.preview"),
                                 action: #selector(EditorWindowController.togglePreview(_:)),
                                 keyEquivalent: "p")
        preview.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(preview)

        let toc = NSMenuItem(title: String(localized: "menu.view.toc"),
                             action: #selector(EditorWindowController.toggleTOC(_:)),
                             keyEquivalent: "t")
        toc.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(toc)

        let sidebar = NSMenuItem(title: String(localized: "menu.view.sidebar"),
                                 action: #selector(EditorWindowController.toggleSidebar(_:)),
                                 keyEquivalent: "")
        sub.addItem(sidebar)

        item.submenu = sub
        return item
    }

    // MARK: - Window 메뉴

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "menu.window"), action: nil, keyEquivalent: "")
        let sub  = NSMenu(title: String(localized: "menu.window"))

        sub.addItem(withTitle: String(localized: "menu.window.minimize"),
                    action: #selector(NSWindow.miniaturize(_:)),
                    keyEquivalent: "m")

        sub.addItem(withTitle: String(localized: "menu.window.zoom"),
                    action: #selector(NSWindow.zoom(_:)),
                    keyEquivalent: "")

        sub.addItem(.separator())

        // 탭 전환 (Ctrl+Tab / Ctrl+Shift+Tab)
        let nextTab = NSMenuItem(title: String(localized: "menu.window.nextTab"),
                                 action: #selector(EditorWindowController.selectNextEditorTab(_:)),
                                 keyEquivalent: "\t")
        nextTab.keyEquivalentModifierMask = .control
        sub.addItem(nextTab)

        let prevTab = NSMenuItem(title: String(localized: "menu.window.prevTab"),
                                 action: #selector(EditorWindowController.selectPreviousEditorTab(_:)),
                                 keyEquivalent: "\t")
        prevTab.keyEquivalentModifierMask = [.control, .shift]
        sub.addItem(prevTab)

        sub.addItem(.separator())

        sub.addItem(withTitle: String(localized: "menu.window.bringAll"),
                    action: #selector(NSApplication.arrangeInFront(_:)),
                    keyEquivalent: "")

        NSApp.windowsMenu = sub
        item.submenu = sub
        return item
    }
}
