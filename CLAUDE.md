# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Intend** — Typora-inspired macOS native markdown editor/viewer built with Swift. The core UX goal is seamless WYSIWYG editing: users never see raw markdown syntax; instead they edit rendered output in-place (inline rendering). Secondary goal: distraction-free writing mode, file tree sidebar, and export (PDF/HTML).

## Build & Run

```bash
# Open in Xcode
open Intend.xcodeproj

# Build from CLI
xcodebuild -project Intend.xcodeproj -scheme Intend -configuration Debug build

# Run tests
xcodebuild -project Intend.xcodeproj -scheme IntendTests -destination 'platform=macOS' test

# Run a single test class
xcodebuild -project Intend.xcodeproj -scheme IntendTests -destination 'platform=macOS' -only-testing:IntendTests/MarkdownParserTests test
```

**Runtime**: macOS 14+ (Sonoma). Swift 6.0 (언어 모드), Swift 6.2 컴파일러.
**의존성**: `swift-markdown` (Apple 공식, SPM). xcodegen으로 프로젝트 재생성: `xcodegen generate`
**주의**: Xcode 16 debug dylib 기능(`ENABLE_DEBUG_DYLIB: NO`)을 비활성화해야 `_main` 심볼 오류 없이 빌드됨.

## Architecture

### Document-Based App Pattern

`NSDocumentController` → `MarkdownDocument` (NSDocument subclass) → `EditorWindowController` → `EditorViewController`

Each open file is a separate `NSDocument`. File I/O, autosave, and undo grouping all go through NSDocument lifecycle methods (`read(from:ofType:)`, `write(to:ofType:)`).

### Core Layer Split (구현 완료 표시 포함)

```
Sources/
├── App/                    # ✅ AppDelegate, main.swift (entry point)
├── Config/                 # ✅ AppConfig (값 타입), ConfigLoader (순수함수), ConfigManager, ConfigWatcher
├── Document/               # ✅ MarkdownDocument (NSDocument 서브클래스)
├── Editor/                 # ✅ EditorWindowController, EditorViewController
│   ├── MarkdownTextView    # ✅ NSTextView 서브클래스 — config 기반 폰트/색상
│   ├── MarkdownTextStorage # ✅ NSTextStorage 서브클래스 — 증분 속성 적용
│   └── InputHandler        # ✅ 순수함수 키 입력 변환 — auto-pair, smart Enter/Tab/Backspace
├── Sidebar/                # ✅ 파일 트리 사이드바
│   ├── FileNode            # ✅ FileNode 값 타입 + buildFileTree 순수함수
│   ├── FileWatcher         # ✅ DispatchSource 디렉터리 감시 (루트 레벨, 500ms 디바운스)
│   └── SidebarViewController # ✅ NSOutlineView + 보안 범위 북마크 + 폴더 선택
├── Theme/                  # ✅ ThemeManager — hex 색상 변환, 시스템 색상 fallback
├── Parser/                 # ✅ RenderNode (값 타입 AST), MarkdownParser (swift-markdown 래퍼), IncrementalParser
├── Renderer/               # ✅ AttributeRenderer — ParseResult → [AttributePatch] (heading/bold/italic/code/link/blockquote)
├── Preview/                # ✅ PreviewViewController — WKWebView + 300ms 디바운스
├── Sidebar/                # ✅ 파일 트리 NSOutlineView
├── Export/                 # ✅ HTMLExporter (순수함수), PDFExporter (WKWebView.createPDF)
├── Preferences/            # 🔲 설정 창 (Phase 7)
├── TOC/                    # ✅ TOCEntry (extractTOCEntries 순수함수), TOCViewController (NSTableView + delegate)
├── Math/                   # 🔲 LatexRenderer, MermaidRenderer, FormulaAttachment (Phase 10)
├── Encryption/             # 🔲 MarkdownEncryptor, PasswordSheetController (Phase 15)
└── Editor/
    ├── BackgroundView      # 🔲 이미지/투명 배경 관리 (Phase 11)
    └── StatusBarView       # 🔲 글자 수 + 마지막 편집 시각 (Phase 13)

scripts/
├── build-and-run.sh        # ✅ Debug 빌드 후 즉시 실행 (Phase 8)
├── make-dmg.sh             # 🔲 Release 빌드 → DMG 패키징 (Phase 17)
└── ExportOptions.plist     # 🔲 xcodebuild exportArchive 설정 (Phase 17)

Resources/
└── default-config.json     # ✅ 앱 번들 기본 설정값 (전체 스키마)

Tests/
├── ConfigTests/            # ✅ ConfigLoaderTests (6개 통과)
└── ParserTests/            # ✅ MarkdownParserTests (22개 통과)
```

### WYSIWYG Editing Strategy (critical design decision)

**Do NOT use WKWebView for the editor itself** — too slow for keystroke-level editing.

Instead, use a custom `NSTextStorage` + `NSLayoutManager` pipeline:

1. `MarkdownTextStorage` receives text edits → runs incremental lexer on changed range → updates internal AST nodes
2. `AttributeRenderer` converts AST nodes → `NSAttributedString` attributes (font, color, paragraph style)
3. Syntax tokens (e.g., `**`, `#`) are rendered with `.foregroundColor = .clear` + zero-width glyph tricks to hide them from view while keeping them in the backing store
4. Heading font sizes, blockquote background, horizontal rules: applied as `NSParagraphStyle` and custom `NSTextAttachment`

Incremental parsing: only re-parse the paragraph/block containing the edit, not the whole document.

### Preview Mode

Split-pane or toggle preview uses `PreviewViewController` with a `WKWebView`. On each document change (debounced 300ms), the full AST is rendered to HTML and loaded via `webView.loadHTMLString(_:baseURL:)`. Syntax highlighting in code blocks uses highlight.js bundled in the app's Resources.

### Config & Theme 시스템

설정은 두 계층으로 관리:
1. `AppConfig` (값 타입 struct) — 전체 설정의 in-memory 표현
2. `ConfigManager.shared.current` — 앱 전역 단일 접근점

설정 변경 알림: `NotificationCenter.default.post(name: .configDidChange, object: newConfig)`
수신: `ViewController`들이 `configDidChange` 구독 후 `textView.applyConfig(config)` 호출

색상은 `ThemeManager.shared`를 통해서만 접근 (hex → NSColor 변환, nil → 시스템 색상):
```swift
ThemeManager.shared.foregroundColor   // NSColor
ThemeManager.shared.backgroundColor
ThemeManager.shared.syntaxTokenColor  // 마크다운 토큰 흐리게 처리용
```

`AppConfig.default` → 하드코딩 기본값 (번들 JSON 로딩 실패 시 fallback).

### Concurrency 규칙 (Swift 6 strict)

- `ThemeManager`: `@unchecked Sendable` — 항상 메인 스레드에서만 접근
- `ConfigManager`: `@unchecked Sendable` — 내부 lock 없이 메인 스레드 전제
- NSTextStorage 서브클래싱: `@MainActor` 붙이지 말 것 (AppKit 내부 호출과 충돌). 대신 내부에서 `ThemeManager.shared`에 접근 가능 (같은 스레드 보장).
- Parsing 백그라운드 작업: `DispatchQueue(label: "com.intend.parser", qos: .userInitiated)`

### State & Data Flow

- No MVVM/VIPER. Use AppKit's MVC directly.
- `NSDocument` owns the source-of-truth string. All edits go through `NSTextStorage` → document marks itself dirty.
- Sidebar folder path stored in `UserDefaults`. Bookmark-resolved for sandbox security scope.
- Preferences use `@AppStorage` equivalents via a typed `Preferences` namespace over `UserDefaults`.

### Concurrency

- Parsing happens on `DispatchQueue(label: "com.intend.parser", qos: .userInitiated)`.
- All AppKit/layout updates must hop back to `DispatchQueue.main`.
- Use `Task` + `MainActor` for async export operations.

### Phase 8 — 로컬 빌드 & 실행 스크립트

`scripts/build-and-run.sh` 단일 파일로 구현:

1. `xcodebuild -scheme Intend -configuration Debug build` 실행
2. 빌드 결과물(`.app`) 경로를 `BUILT_PRODUCTS_DIR`에서 추출
3. `open "$APP_PATH"` 로 즉시 실행
4. 빌드 실패 시 `xcodebuild` 로그를 `build.log`에 저장 후 오류 출력

스크립트는 리포지토리 루트의 `scripts/` 에 위치. `chmod +x` 처리 포함.

### Phase 9 — 헤딩 목차 패널 (TOC Panel)

**컴포넌트**: `TOCViewController` — `NSOutlineView` 기반 계층 목록
**위치**: 편집기 우측 패널 (NSSplitView의 trailing pane, 기본 너비 220pt)
**데이터 소스**: `IncrementalParser`가 파싱할 때마다 heading 노드만 추출 → `[TOCEntry]` 배열 (`level`, `title`, `characterOffset`)
**업데이트 트리거**: `NSTextStorage` edit 완료 후 debounce 150ms → `TOCViewController.reload(entries:)` 호출 (메인 스레드)
**클릭 동작**: 선택된 heading의 `characterOffset`으로 `textView.scrollRangeToVisible` + 커서 이동
**들여쓰기**: H1=0, H2=12pt, H3=24pt… `NSTableColumn` indent 대신 `NSTextField.frame.origin.x` 직접 조정
**토글**: 툴바 버튼으로 trailing pane show/hide; 상태는 `UserDefaults["tocPanelVisible"]`에 저장

```
Sources/
└── TOC/                    # 🔲 TOCEntry (값 타입), TOCViewController, TOCDataSource
```

### Phase 10 — LaTeX 수식 + Mermaid 다이어그램

**LaTeX**:
- 인라인 수식: `$...$` → `NSTextAttachment` + `CALayer` 렌더링 (cmark-gfm 또는 순수 Swift 렉서로 토큰 추출)
- 블록 수식: `$$...$$` → 전체 행을 `NSTextAttachment`로 대체, `MTMathUILabel` (iosMath SPM) 또는 WebKit 오프스크린 렌더 후 `NSImage`로 캐시
- 추천: **iosMath** SPM 패키지 — 네이티브 렌더, WebKit 불필요

**Mermaid**:
- 코드 펜스 ` ```mermaid ` 블록 감지 → 편집 중엔 원본 코드 표시, 블록 밖으로 커서 이동 시 `WKWebView` 오프스크린 렌더 후 `NSImage` 스냅샷으로 교체 (Typora 방식)
- Mermaid JS는 번들 내 `Resources/mermaid.min.js` 로컬 파일 사용 (CDN 금지 — 샌드박스)
- 렌더 캐시: 소스 문자열 해시 → `NSCache<NSString, NSImage>`

```
Sources/
└── Math/                   # 🔲 LatexRenderer, MermaidRenderer, FormulaAttachment
```

### Phase 11 — 편집기 배경 커스터마이징

**투명 배경**:
- `MarkdownTextView.drawsBackground = false` + `NSScrollView.drawsBackground = false`
- 윈도우 레벨에서 `NSWindow.isOpaque = false`, `backgroundColor = .clear`
- 투명도 슬라이더 (`alpha: 0.0~1.0`) → `UserDefaults["editorBackgroundAlpha"]`에 저장

**이미지 배경**:
- `NSImageView`를 `NSScrollView` 아래 레이어(`superview.subviews.insert(at: 0)`)로 삽입
- `contentMode`: `.scaleAspectFill` (기본), `.tile`, `.center` 선택 가능
- 이미지 경로는 보안 범위 북마크로 저장 (`UserDefaults["editorBackgroundBookmark"]`)
- 이미지 위에 반투명 overlay(`NSView` + `backgroundColor.withAlphaComponent`)로 가독성 확보
- 설정 UI: Phase 7 설정 창에 "배경" 탭 추가

```
Sources/
└── Editor/
    └── BackgroundView          # 🔲 NSView 서브클래스 — 이미지/투명 배경 관리 (Phase 11)
```

### Phase 12 — 라이트 / 다크 모드 지원

**원칙**: `NSColor.controlTextColor` 같은 시맨틱 색상을 최우선 사용. 직접 hex 지정 시 라이트/다크 쌍으로 관리.

**ThemeManager 확장**:
- `effectiveAppearance` 감지: `NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])`
- 모드별 색상 토큰 쌍: `AppConfig`에 `colors.light.*` / `colors.dark.*` 구조 추가
- 시스템 자동 전환 구독: `NSApplication`의 `effectiveAppearance` KVO 또는 `viewDidChangeEffectiveAppearance` override

**적용 범위**:
- `MarkdownTextStorage`: 외관 변경 시 전체 속성 재적용 (`invalidateAttributes(in: fullRange)`)
- `TOCViewController`: `NSColor` 시맨틱 색상 사용으로 자동 대응
- 배경 overlay 투명도: 다크 모드에서 자동으로 약간 높여 가독성 유지
- 설정 창 (`Phase 7`): 수동 override 옵션 (라이트 고정 / 다크 고정 / 시스템 따라가기)

**테스트**: `XCTestCase`에서 `NSAppearance(named: .darkAqua)` 강제 주입 후 색상 토큰 검증

### Phase 13 — 글자 수 및 마지막 편집 시각 표시

**표시 위치**: 편집기 하단 상태바 (`NSStatusBar` 스타일 `NSView`, 높이 24pt)

**글자 수**:
- 공백 포함: `textStorage.string.count`
- 공백 미포함: `textStorage.string.filter { !$0.isWhitespace }.count`
- 업데이트 트리거: `NSTextStorageDelegate.textStorageDidProcessEditing` → debounce 200ms
- 표시 형식: `"공백 포함 1,234자 · 공백 제외 1,012자"`

**마지막 편집 시각**:
- `MarkdownDocument`가 `write(to:ofType:)` 호출 시 `Date()` 기록 → `UserDefaults["lastEditedAt.<fileURL.hash>"]`
- 편집 중(미저장)엔 인메모리 `lastTypedAt: Date` 갱신 (타이핑마다 업데이트)
- 표시 형식: 오늘이면 `"오늘 14:32"`, 과거면 `"2026-03-28 09:15"`
- `DateFormatter` 인스턴스는 재사용 (`static let`)

```
Sources/
└── Editor/
    └── StatusBarView           # 🔲 글자 수 + 마지막 편집 시각 표시 (Phase 13)
```

### Phase 14 — .md 파일 연결 등록 (UTI / CFBundleDocumentTypes)

**목표**: Finder에서 `.md` 파일 우클릭 → 「다음에서 열기」에 Intend가 나타남. 앱 최초 실행 시 기본 앱으로 등록 가능.

**Info.plist 설정**:
```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>       <string>Markdown Document</string>
    <key>CFBundleTypeRole</key>       <string>Editor</string>
    <key>LSHandlerRank</key>          <string>Alternate</string>  <!-- Default는 시스템 기본 앱 탈취 — Alternate 권장 -->
    <key>CFBundleTypeExtensions</key>
    <array><string>md</string><string>markdown</string><string>mdown</string></array>
    <key>LSItemContentTypes</key>
    <array><string>net.daringfireball.markdown</string><string>public.plain-text</string></array>
  </dict>
</array>
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>       <string>net.daringfireball.markdown</string>
    <key>UTTypeDescription</key>      <string>Markdown Document</string>
    <key>UTTypeConformsTo</key>       <array><string>public.plain-text</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array><string>md</string><string>markdown</string><string>mdown</string></array>
    </dict>
  </dict>
</array>
```

**주의**:
- `LSHandlerRank: Alternate` — 기존 기본 앱을 빼앗지 않고 「다음에서 열기」에만 노출
- `UTImportedTypeDeclarations` 대신 `UTExportedTypeDeclarations` 사용 — 앱이 해당 타입의 소유자임을 선언
- `project.yml` (`xcodegen`)에서 `INFOPLIST_FILE` 경로 지정 후 수동 편집 또는 `infoPlist` 딕셔너리로 관리
- 등록 후 `lsregister -f /Applications/Intend.app` 으로 즉시 캐시 갱신 가능

### Phase 15 — 암호화 마크다운 (.mdxk)

**파일 형식**: `.mdxk` = AES-256-GCM 암호화 바이너리. 평문으로 열면 의미 없는 바이트.

**암호화 구현** (`CryptoKit` — 외부 의존성 없음):
```swift
// 레이아웃: [4B magic "MDXK"] [16B salt] [12B nonce] [N+16B ciphertext+tag]
let key = SymmetricKey(data: try PKCS5.PBKDF2(password: pwd, salt: salt, iterations: 200_000, keyLength: 32, variant: .sha2(.sha256)).calculate())
let sealed = try AES.GCM.seal(plaintextData, using: key)
```
- KDF: PBKDF2-SHA256, 200,000 iterations, 16B random salt (NIST 권장)
- 매직 바이트 `4D 44 58 4B`로 손상/포맷 오인 방지

**UX — 2갈래 저장 흐름**:
1. **새 파일 저장**: `NSSavePanel` 파일 포맷 팝업에서 `.mdxk` 선택 → 비밀번호 입력 시트(`NSSecureTextField` × 2 확인) → 암호화 저장
2. **기존 .md → .mdxk**: 메뉴 「파일 › 다른 이름으로 저장…」 → 포맷 `.mdxk` 선택 → 비밀번호 시트 → 저장

**열기 흐름**:
- `MarkdownDocument.read(from:ofType:)` 매직 바이트 감지 → 비밀번호 입력 시트
- 복호화 실패(잘못된 비밀번호)는 AES-GCM 인증 태그 불일치로 자동 감지 → 오류 알림
- 비밀번호는 메모리에만 보관, `NSSecureTextField` 입력 즉시 `Data`로 변환 후 문자열 해제

**macOS 파일 타입 등록** (`Info.plist`):
```xml
<!-- CFBundleDocumentTypes에 .mdxk 항목 추가 -->
<key>LSHandlerRank</key>          <string>Owner</string>  <!-- 기본 앱으로 등록 -->
<key>CFBundleTypeExtensions</key> <array><string>mdxk</string></array>
<key>LSItemContentTypes</key>     <array><string>com.intend.encrypted-markdown</string></array>
```
- `.mdxk` UTI `Owner` 등급 — Intend가 유일한 연결 앱으로 등록

```
Sources/
└── Encryption/             # ✅ MarkdownEncryptor (CryptoKit AES-GCM), PasswordSheetController (Phase 15)
```

### Phase 16 — 한글 입력 안정화 및 PDF 내보내기 한글 깨짐 수정

**한글 입력 이슈 원인 및 수정 포인트**:

macOS IME는 조합 중인 문자를 `markedText`로 관리. `NSTextStorage` 서브클래스가 `processEditing` 중 속성을 강제 교체하면 조합 상태가 깨져 스페이스/엔터 이후 다음 타이핑이 엉킴.

점검 및 수정 사항:
1. **`MarkdownTextStorage.processEditing()`**: `hasMarkedText()` 확인 후 마킹 범위 내 속성 변경 금지
   ```swift
   override func processEditing() {
       super.processEditing()
       guard let tv = layoutManagers.first?.textContainers.first?.textView,
             !tv.hasMarkedText() else { return }
       applyAttributes(in: editedRange)
   }
   ```
2. **`InputHandler` 키 처리**: `Enter` / `Space` 이후 `markedRange`가 비어있을 때만 블록 레벨 처리 트리거
3. **`NSTextView.insertText(_:replacementRange:)` override**: `markedText` 진행 중 자동완성 쌍 삽입 차단
4. **속성 적용 범위 클램핑**: `editedRange`가 문자열 길이를 넘는 엣지 케이스 → `NSRange` 교집합 연산 방어

**PDF 내보내기 한글 깨짐 수정**:

`WKWebView.createPDF` 시 한글 깨짐 주요 원인: HTML `<meta charset>` 누락 또는 한글 폰트 미지정.

수정 포인트 (`HTMLExporter`):
1. HTML 템플릿에 `<meta charset="UTF-8">` 명시
2. CSS에 한글 폰트 명시:
   ```css
   body { font-family: "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; }
   code { font-family: "D2Coding", "Nanum Gothic Coding", monospace; }
   ```
3. `PDFExporter`: `loadHTMLString` 완료 콜백에서 `createPDF(configuration:)` 호출, `PDFConfiguration.contentArea` 여백 지정
4. `NSPrintOperation` 대안 경로: `NSFont(name: "AppleSDGothicNeo-Regular", size: 14)` 명시 — 시스템 fallback이 `.notdef` 글리프 렌더하는 경우 방어

**테스트 기준**: 한글 포함 `.md` → PDF 내보내기 → 미리보기 앱에서 모든 한글 정상 표시 확인

### Phase 17 — DMG 패키징

`scripts/make-dmg.sh` 구현:

1. Release 빌드: `xcodebuild -scheme Intend -configuration Release archive -archivePath build/Intend.xcarchive`
2. Export: `xcodebuild -exportArchive -archivePath … -exportPath build/export -exportOptionsPlist scripts/ExportOptions.plist`
3. DMG 생성: `create-dmg` (Homebrew) 또는 `hdiutil` 직접 사용
   - 앱 아이콘 + Applications 폴더 심볼릭 링크 포함
   - 배경 이미지: `scripts/dmg-background.png` (1000×600)
4. 출력: `dist/Intend-<version>.dmg`

`scripts/ExportOptions.plist` — `method: development`, `teamID` 설정 필요 (실행 환경에 따라 수정).
코드사이닝 없이 배포 시: `codesign --remove-signature` + `xattr -cr` 가이드 주석 포함.

## Key Implementation Notes

- **Undo**: Coalesce typing edits via `NSUndoManager.groupsByEvent`. Block-level operations (heading change, list toggle) are discrete undo groups.
- **Line Endings**: Normalize to `\n` on read; preserve original on write.
- **Large Files**: Stream-parse files >1 MB; defer full attribute application until visible range (use `NSLayoutManagerDelegate.layoutManager(_:shouldGenerateGlyphs:...)` for lazy rendering).
- **Sandbox**: App is sandboxed. Use security-scoped bookmarks for sidebar folder access.
- **Accessibility**: Set `accessibilityRole`, `accessibilityLabel` on all custom views. VoiceOver must be able to read rendered content, not raw markdown.

## 현재 구현 상태 (Phase 진행 현황)

| Phase | 내용 | 상태 |
|-------|------|------|
| Phase 1 | 프로젝트 뼈대, Document, Editor, Config 시스템 | ✅ 완료 |
| Phase 2 | swift-markdown 파서 연동, AST 설계 | ✅ 완료 |
| Phase 3 | WYSIWYG 속성 렌더러 (heading/bold/italic/code/link/blockquote) | ✅ 완료 |
| Phase 4 | 편집 경험 (자동완성 쌍, Tab/Enter 동작) | ✅ 완료 |
| Phase 5 | 사이드바 파일 트리 | ✅ 완료 |
| Phase 6 | WKWebView 미리보기, PDF/HTML 내보내기 | ✅ 완료 |
| Phase 7 | 설정 GUI 창, 테마 시스템 확장 | ✅ 완료 |
| Phase 8 | 로컬 빌드 & 실행 쉘 스크립트 — Debug .app 빌드 후 바로 실행 | ✅ 완료 |
| Phase 9 | 헤딩 목차 패널 — 편집기 우측에 노션식 계층적 TOC 표시 | ✅ 완료 |
| Phase 10 | LaTeX 수식 블록 + Mermaid 다이어그램 파싱 및 렌더링 | ✅ 완료 |
| Phase 11 | 편집기 배경 커스터마이징 — 투명 배경 및 이미지 배경 설정 | ✅ 완료 |
| Phase 12 | 라이트 / 다크 모드 완전 지원 및 테마 자동 전환 | ✅ 완료 |
| Phase 13 | 글자 수 및 마지막 편집 시각 표시 — 상태바 통계 패널 | ✅ 완료 |
| Phase 14 | .md 파일 연결 등록 — Finder 「다음에서 열기」 목록 노출 | ✅ 완료 |
| Phase 15 | 암호화 마크다운 (.mdxk) — 비밀번호 잠금 저장 및 열기 | ✅ 완료 |
| Phase 16 | 한글 입력 안정화 및 PDF 내보내기 한글 깨짐 수정 | ✅ 완료 |
| Phase 17 | DMG 패키징 — 팀 배포용 디스크 이미지 빌드 파이프라인 | ✅ 완료 |

## Conventions

- One Swift file per type. No `+Extension` files unless the extension is >50 lines.
- `Parser/` has zero AppKit/Foundation UI imports — pure Swift only, fully unit-testable.
- All `UserDefaults` keys are string constants in `Preferences.Keys`.
- Localizable strings go in `Localizable.strings`; use `NSLocalizedString("key", comment: "")`.
