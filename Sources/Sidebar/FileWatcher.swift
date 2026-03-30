import Foundation

/// DispatchSource 기반 단일 디렉터리 감시자.
/// 루트 디렉터리의 직접 변경(파일 추가/삭제/이름 변경)을 감지.
/// 하위 디렉터리 변경은 감지하지 않음 (Phase 5 범위).
final class FileWatcher {

    private var source:   DispatchSourceFileSystemObject?
    private var fd:       Int32 = -1
    private var debounce: DispatchWorkItem?
    private let queue     = DispatchQueue(label: "com.intend.filewatcher", qos: .utility)

    /// onChange는 MainActor에서 호출됨 (Task { @MainActor in } 경유).
    func watch(url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.debounce?.cancel()
            let work = DispatchWorkItem {
                Task { @MainActor in onChange() }
            }
            self?.debounce = work
            self?.queue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        src.resume()
        source = src
    }

    func stop() {
        debounce?.cancel()
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
