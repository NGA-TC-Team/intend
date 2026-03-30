import Foundation

/// 앱 전역 UserDefaults 키 네임스페이스.
enum Preferences {
    enum Keys {
        static let sidebarFolderBookmark   = "sidebarFolderBookmark"
        static let tocPanelVisible         = "tocPanelVisible"
        static let editorBackgroundMode    = "editorBackgroundMode"       // "none"|"transparent"|"image"
        static let editorBackgroundAlpha   = "editorBackgroundAlpha"      // Double 0.0–1.0
        static let editorBackgroundBookmark = "editorBackgroundBookmark"  // Data (security-scoped)
        static let editorImageContentMode  = "editorImageContentMode"     // "fill"|"tile"|"center"
        static let editorOverlayAlpha        = "editorOverlayAlpha"         // Double 0.0–1.0
        static let lastEditedAtPrefix        = "lastEditedAt."              // + fileURL.hash
        static let hasOfferedDefaultApp      = "hasOfferedDefaultApp"
        static let focusModeActive           = "focusModeActive"
    }
}
