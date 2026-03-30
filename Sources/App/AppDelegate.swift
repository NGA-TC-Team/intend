import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigManager.shared.load()
        ThemeManager.shared.apply(ConfigManager.shared.current.theme)
        // 프로그래매틱 메뉴 바 설치
        NSApp.mainMenu = MenuBuilder.buildMainMenu()
        // 커스텀 탭 바를 사용하므로 macOS 자동 탭 비활성화.
        NSWindow.allowsAutomaticWindowTabbing = false
        offerDefaultAppRegistrationIfNeeded()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Preferences (Cmd+,)

    @IBAction func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }

    // MARK: - File type registration

    /// 최초 실행 시 .md 기본 앱 등록 여부를 사용자에게 제안.
    /// macOS 12+: NSWorkspace.setDefaultApplication(at:toOpen:completionHandler:)
    private func offerDefaultAppRegistrationIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Preferences.Keys.hasOfferedDefaultApp) else { return }
        ud.set(true, forKey: Preferences.Keys.hasOfferedDefaultApp)

        // 창이 완전히 뜬 뒤 알림 표시
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.promptDefaultAppRegistration()
        }
    }

    private func promptDefaultAppRegistration() {
        let alert = NSAlert()
        alert.messageText     = String(localized: "alert.defaultApp.message")
        alert.informativeText = String(localized: "alert.defaultApp.info")
        alert.addButton(withTitle: String(localized: "alert.defaultApp.setDefault"))
        alert.addButton(withTitle: String(localized: "action.later"))
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if #available(macOS 12.0, *) {
            guard let appURL = Bundle.main.bundleURL as URL? else { return }
            let contentType = UTType("net.daringfireball.markdown") ?? .plainText
            NSWorkspace.shared.setDefaultApplication(
                at: appURL,
                toOpen: contentType
            ) { error in
                if let error {
                    DispatchQueue.main.async {
                        NSApp.presentError(error)
                    }
                }
            }
        } else {
            // macOS 12 미만: lsregister로 캐시 갱신만 수행
            refreshLaunchServicesCache()
        }
    }

    /// Launch Services 캐시 강제 갱신.
    /// 설치 직후 Finder가 앱을 인식하지 못할 때 사용.
    private func refreshLaunchServicesCache() {
        guard let lsregister = [
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Support/lsregister",
        ].first(where: { FileManager.default.fileExists(atPath: $0) }),
              let bundlePath = Bundle.main.bundlePath as String?
        else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: lsregister)
        proc.arguments     = ["-f", bundlePath]
        try? proc.run()
    }

}
