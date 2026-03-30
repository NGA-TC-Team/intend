import Foundation

/// 파일 변경 감지 → 디바운스 500ms → 콜백.
final class ConfigWatcher: @unchecked Sendable {

    private var source: DispatchSourceFileSystemObject?
    private var debounceTimer: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.intend.configWatcher", qos: .utility)

    deinit { stop() }

    func watch(url: URL, onChange: @escaping () -> Void) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            self?.debounce(delay: 0.5, action: onChange)
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    // MARK: - Debounce (순수 타이머 교체)

    private func debounce(delay: TimeInterval, action: @escaping () -> Void) {
        debounceTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        debounceTimer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
