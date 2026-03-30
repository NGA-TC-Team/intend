import Foundation

// MARK: - Notification

extension Notification.Name {
    static let configDidChange    = Notification.Name("com.intend.configDidChange")
    static let appearanceDidChange = Notification.Name("com.intend.appearanceDidChange")
}

// MARK: - ConfigManager

/// 설정의 단일 접근점. AppConfig를 로드·감시·배포.
/// 사이드 이펙트(파일 I/O, 알림)를 이 클래스에 격리.
final class ConfigManager: @unchecked Sendable {

    static let shared = ConfigManager()

    private(set) var current: AppConfig = .default
    private var watcher: ConfigWatcher?

    private init() {}

    // MARK: - Load

    func load() {
        switch loadConfig() {
        case .success(let config):
            current = config
            startWatching()
        case .failure(let error):
            // 로딩 실패 시 기본값 유지, 콘솔에 기록
            print("[ConfigManager] Load failed: \(error). Using defaults.")
        }
    }

    // MARK: - Watch

    private func startWatching() {
        let url = userConfigURL()
        watcher = ConfigWatcher()
        watcher?.watch(url: url) { [weak self] in
            self?.reload()
        }
    }

    private func reload() {
        switch loadConfig() {
        case .success(let config) where config != current:
            current = config
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .configDidChange,
                    object: config
                )
            }
        default:
            break
        }
    }
}
