# Intend — Initial Specification

> Typora-inspired macOS WYSIWYG 마크다운 편집기. Swift + AppKit 네이티브.

---

## 1. 목표 & 성공 기준

| 항목 | 기준 |
|------|------|
| 편집 방식 | 커서가 있는 블록만 raw 마크다운 노출, 나머지는 렌더링된 상태 |
| 반응성 | 타이핑 지연 < 16ms (60fps 유지) |
| 파일 크기 | 1MB 마크다운 파일 정상 동작 |
| 내보내기 | PDF, HTML 지원 |
| 접근성 | VoiceOver로 렌더링 텍스트 읽기 가능 |

---

## 2. 구현 로드맵 (Phase별)

### Phase 1 — 뼈대 (1~2주)
- [ ] Xcode 프로젝트 생성 (Document-Based App 템플릿)
- [ ] `MarkdownDocument` (NSDocument 서브클래스) — read/write
- [ ] `EditorWindowController` + `EditorViewController`
- [ ] 기본 `NSTextView` 로 텍스트 편집 확인
- [ ] 빌드/테스트 파이프라인 구성

### Phase 2 — 파서 (2~3주)
- [ ] Lexer (토큰 스트림 생성)
- [ ] Parser (토큰 → AST)
- [ ] 단위 테스트: CommonMark spec 케이스 100개 이상
- [ ] 증분(incremental) 파싱 기반 설계

### Phase 3 — WYSIWYG 렌더러 (3~4주)
- [ ] `MarkdownTextStorage` (NSTextStorage 서브클래스)
- [ ] `AttributeRenderer` — 인라인 스타일 (bold/italic/code/link)
- [ ] `BlockRenderer` — 단락 스타일 (heading 크기, blockquote, list indent)
- [ ] 마크다운 토큰 숨기기 (** → 투명 처리)
- [ ] 커서 블록 "포커스 해제 시 렌더링" 동작

### Phase 4 — 편집 경험 (2주)
- [ ] 자동 완성 쌍 (`**|**`, `[|]()`, `` ` `` )
- [ ] Tab → 들여쓰기 / 목록 레벨 변경
- [ ] Enter → 목록 항목 자동 생성
- [ ] Undo 그룹 전략

### Phase 5 — 사이드바 & 파일 관리 (1~2주)
- [ ] `NSOutlineView` 기반 파일 트리
- [ ] 샌드박스 security-scoped bookmark
- [ ] 파일 감시 (`DispatchSource.makeFileSystemObjectSource`)

### Phase 6 — 미리보기 & 내보내기 (1~2주)
- [ ] WKWebView 분할 미리보기
- [ ] HTML 내보내기
- [ ] PDF 내보내기 (`NSPrintOperation`)

### Phase 7 — 개인화 & 설정 (2~3주)
- [ ] `config.json` 스키마 정의 및 기본값 번들링
- [ ] `ConfigLoader` — JSON 파일 파싱 → `AppConfig` 값 타입으로 변환
- [ ] `ConfigWatcher` — 파일 변경 감시 → 핫 리로드
- [ ] 렌더링 설정 반영: 폰트/색상/간격 전부 config 기반
- [ ] 설정 창 (GUI) — config.json 과 양방향 동기화
- [ ] 테마 시스템 (config의 `theme` 섹션 기반)

---

## 3. 핵심 구현 상세

### 3-1. WYSIWYG 렌더링 파이프라인

```
키 입력
  └─▶ NSTextStorage.processEditing()
        └─▶ 증분 Lexer (변경 range의 단락만)
              └─▶ 증분 Parser (영향받는 블록만)
                    └─▶ AttributeRenderer
                          └─▶ NSLayoutManager가 글리프 재계산
                                └─▶ 화면 렌더링
```

**토큰 숨기기 전략:**

옵션 A — 투명 색상 (구현 쉬움, 접근성 문제):
```swift
// ** 토큰에 적용
attrs[.foregroundColor] = NSColor.clear
attrs[.font] = NSFont.systemFont(ofSize: 0.01) // 공간 최소화
```

옵션 B — NSTextAttachment 대체 (권장):
```swift
// ** 토큰을 너비=0 attachment로 교체
// 단점: 복사 시 raw 마크다운 복원 로직 필요
```

옵션 C — NSLayoutManager glyph 조작 (가장 완성도 높음, 가장 어려움):
```swift
// layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)
// 토큰 range의 글리프를 .null 로 대체
```

**권장: Phase 3는 옵션 A로 빠르게 구현 후, Phase 7에서 옵션 C로 마이그레이션.**

### 3-2. NSTextStorage 서브클래싱 필수 규칙

> NSTextStorage를 잘못 서브클래싱하면 앱이 무한루프/크래시됨. 반드시 숙지.

```swift
class MarkdownTextStorage: NSTextStorage {
    // 1. 반드시 이 두 프로퍼티를 오버라이드
    override var string: String { _backingStore.string }
    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        return _backingStore.attributes(at: location, effectiveRange: range)
    }

    // 2. 편집 메서드는 반드시 beginEditing/endEditing으로 감쌈
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        _backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        _backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // 3. 실제 파싱/렌더링은 여기서
    override func processEditing() {
        // super 호출 전에 attribute 적용
        applyMarkdownAttributes(in: editedRange)
        super.processEditing()
    }

    private var _backingStore = NSMutableAttributedString()
}
```

### 3-3. 설정 시스템 아키텍처

#### 설정 파일 위치 (우선순위 순)

```
1. ~/Library/Application Support/Intend/config.json  ← 사용자 설정 (최우선)
2. <앱 번들>/Resources/default-config.json           ← 앱 내장 기본값
```

사용자 파일이 없으면 기본값만 사용. 사용자 파일은 일부 키만 존재해도 됨 (deep merge).

#### config.json 전체 스키마

```json
{
  "version": "1",
  "editor": {
    "font": { "family": "Helvetica Neue", "size": 16 },
    "lineHeight": 1.6,
    "tabSize": 4,
    "wordWrap": true,
    "spellCheck": false,
    "focusMode": false,
    "typewriterMode": false
  },
  "rendering": {
    "headings": {
      "h1": { "scale": 2.0, "weight": "bold",     "color": null },
      "h2": { "scale": 1.6, "weight": "bold",     "color": null },
      "h3": { "scale": 1.3, "weight": "semibold", "color": null },
      "h4": { "scale": 1.1, "weight": "semibold", "color": null },
      "h5": { "scale": 1.0, "weight": "medium",   "color": null },
      "h6": { "scale": 1.0, "weight": "medium",   "color": "#888888" }
    },
    "paragraph": { "spacing": 1.0, "firstLineIndent": 0 },
    "blockquote": { "borderColor": null, "backgroundColor": null, "italic": true },
    "codeBlock": {
      "font": "Menlo", "fontSize": 14,
      "syntaxTheme": "github-dark",
      "showLineNumbers": false,
      "backgroundColor": null
    },
    "inlineCode": { "font": "Menlo", "fontSize": 14, "backgroundColor": null },
    "link": { "color": null, "underline": true },
    "list": { "bulletStyle": "disc", "indentWidth": 24 },
    "horizontalRule": { "style": "line", "color": null },
    "table": { "borderColor": null, "headerBackground": null }
  },
  "theme": {
    "name": "default",
    "appearance": "auto",
    "colors": {
      "background": null, "foreground": null,
      "accent": null,     "selection": null
    }
  },
  "export": {
    "pdf": {
      "paperSize": "A4",
      "margin": { "top": 20, "bottom": 20, "left": 25, "right": 25 },
      "includeTableOfContents": false
    },
    "html": { "embedCSS": true, "syntaxHighlighting": true }
  },
  "keybindings": {
    "togglePreview": "Cmd+Shift+P",
    "focusMode":     "Cmd+Shift+F",
    "exportPDF":     "Cmd+Shift+E"
  }
}
```

`color` 필드가 `null`이면 시스템 accent/label color 사용 (다크모드 자동 대응).

#### ConfigLoader 구현 (함수형)

```swift
// AppConfig — 완전한 값 타입. 모든 필드 non-optional (기본값 병합 후)
struct AppConfig: Equatable {
    var editor: EditorConfig
    var rendering: RenderingConfig
    var theme: ThemeConfig
    var export: ExportConfig
    var keybindings: KeybindingsConfig
}

// 순수 함수들의 파이프라인으로 로딩
func loadConfig() -> Result<AppConfig, ConfigError> {
    loadDefaultConfig()                        // Bundle에서 JSON 읽기
        .flatMap(parseConfig)                  // JSON → AppConfig
        .flatMap { defaults in
            loadUserConfig()                   // 사용자 파일 읽기 (없으면 .success(nil))
                .flatMap { userJSON in
                    merge(base: defaults, override: userJSON)  // deep merge
                }
        }
}

// 각 단계는 순수 함수 — 외부 상태 없음, 테스트 가능
func merge(base: AppConfig, override: [String: Any]?) -> Result<AppConfig, ConfigError>
func parseConfig(from json: [String: Any]) -> Result<AppConfig, ConfigError>
```

#### ConfigWatcher — 핫 리로드

```swift
// 파일 변경 감지 → 디바운스 500ms → 재로딩
final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?

    func watch(url: URL, onChange: @escaping (AppConfig) -> Void) {
        let fd = open(url.path, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source?.setEventHandler { [weak self] in
            self?.debounce(500) {
                loadConfig().map(onChange)
            }
        }
        source?.resume()
    }
}
```

변경 시 `NotificationCenter.post(.configDidChange, object: newConfig)` → 각 컴포넌트가 독립적으로 반영.

### 3-4. 증분(Incremental) 파싱 전략

마크다운은 문맥 의존적이라 증분 파싱이 까다로움. 현실적 타협:

```
블록 레벨 증분:
  - 편집된 위치의 블록 경계(빈 줄)를 앞뒤로 탐색
  - 해당 블록만 재파싱
  - 블록 간 영향(예: 중첩 목록)은 상위 블록까지 확장

인라인 레벨 증분:
  - 해당 블록 안에서만 인라인 토큰 재계산
```

```swift
func dirtyBlockRange(around editedRange: NSRange, in string: String) -> NSRange {
    // 편집 위치 앞의 첫 번째 \n\n 탐색
    // 편집 위치 뒤의 첫 번째 \n\n 탐색
    // 그 사이 range 반환
}
```

---

## 4. 주의점 & 함정 (반드시 읽기)

### ⚠️ 주의 1: NSTextStorage 편집 중 재진입 금지

`processEditing()` 안에서 `replaceCharacters(in:with:)`를 절대 호출하지 말 것.
속성(attribute)만 변경해야 함. 텍스트 자체를 바꾸려면 `DispatchQueue.main.async`로 지연.

```swift
// ❌ 무한루프 발생
override func processEditing() {
    replaceCharacters(in: someRange, with: "fixed") // CRASH
    super.processEditing()
}

// ✅ 지연 처리
override func processEditing() {
    let rangeToFix = someRange
    DispatchQueue.main.async {
        self.replaceCharacters(in: rangeToFix, with: "fixed")
    }
    super.processEditing()
}
```

### ⚠️ 주의 2: NSRange vs Swift String.Index 혼용

AppKit은 UTF-16 기반 NSRange 사용. Swift String은 UTF-8/Unicode scalar 기반.
한글, 이모지 포함 시 인덱스 불일치 → 크래시.

```swift
// ❌ 위험
let swiftRange = string.index(string.startIndex, offsetBy: nsRange.location)

// ✅ 안전
let swiftRange = Range(nsRange, in: string)!
// 또는
(string as NSString).substring(with: nsRange)
```

파서 내부는 **전부 String.Index** 사용. AppKit 경계에서만 NSRange 변환.

### ⚠️ 주의 3: 마크다운 복사/붙여넣기 이중성

WYSIWYG 편집기에서 복사 시:
- `Cmd+C` → 렌더링된 텍스트 (사용자가 보는 것)
- 붙여넣기 대상이 다른 앱이면 raw 마크다운이어야 함

`NSPasteboard`에 두 가지 타입 모두 등록:
```swift
pasteboard.setString(renderedText, forType: .string)
pasteboard.setString(rawMarkdown, forType: .init("net.daringfireball.markdown"))
```

### ⚠️ 주의 4: NSTextView의 자동 기능들이 마크다운을 망침

NSTextView의 기본 설정이 마크다운 편집을 방해함:

```swift
textView.isAutomaticQuoteSubstitutionEnabled = false  // "smart quotes" 비활성화
textView.isAutomaticDashSubstitutionEnabled = false   // -- → — 변환 비활성화
textView.isAutomaticSpellingCorrectionEnabled = false // 자동 교정 비활성화
textView.isAutomaticLinkDetectionEnabled = false      // 링크 자동 감지 비활성화
textView.isAutomaticTextCompletionEnabled = false
```

### ⚠️ 주의 5: 샌드박스 파일 접근

앱 샌드박스 활성화 시 사용자가 선택한 폴더 외부 접근 불가.
파일 트리(사이드바)는 `NSOpenPanel`로 폴더 선택 → security-scoped bookmark 저장:

```swift
// 저장
let bookmark = try url.bookmarkData(options: .withSecurityScope, ...)
UserDefaults.standard.set(bookmark, forKey: "sidebarFolder")

// 복원
var isStale = false
let url = try URL(resolvingBookmarkData: bookmark,
                  options: .withSecurityScope,
                  bookmarkDataIsStale: &isStale)
url.startAccessingSecurityScopedResource() // 잊지 말 것
defer { url.stopAccessingSecurityScopedResource() }
```

### ⚠️ 주의 6: Undo 스택 오염

NSTextStorage 속성 변경도 Undo 스택에 기록됨.
마크다운 렌더링 속성 적용은 Undo 불가 작업으로 처리:

```swift
textView.undoManager?.disableUndoRegistration()
applyMarkdownAttributes(...)
textView.undoManager?.enableUndoRegistration()
```

### ⚠️ 주의 7: 커서 블록 "언렌더링" 구현 복잡도

Typora의 핵심 UX — 커서가 들어간 블록은 raw 마크다운 표시, 나가면 렌더링.
구현 난이도가 가장 높음:

```
NSTextView.delegate.textViewDidChangeSelection()
  → 이전 커서 블록: 토큰 다시 숨기기 (속성 재적용)
  → 현재 커서 블록: 토큰 표시 (foregroundColor = 원래 색)
```

성능 주의: selection 변경 시마다 두 블록의 레이아웃 재계산 발생.
해당 범위만 `invalidateLayout`으로 제한할 것.

### ⚠️ 주의 8: 마크다운 파서를 직접 만들지 말 것 (초기에는)

CommonMark spec은 600+ 엣지 케이스 존재. 초기 Phase에서는 검증된 파서 사용 권장:
- **swift-markdown** (Apple 공식, Swift Package): CommonMark 100% 준수
- **cmark** (C 라이브러리, Swift wrapper): 고성능

직접 파서는 Phase 2에서 swift-markdown으로 시작 → 성능 병목 확인 후 직접 구현 결정.

```swift
// Package.swift
.package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0")
```

---

## 5. 기술 선택 근거

| 결정 | 선택 | 이유 | 포기한 대안 |
|------|------|------|------------|
| 편집기 엔진 | NSTextStorage + NSLayoutManager | 60fps 타이핑 가능, AppKit 완전 통합 | WKWebView (지연 큼), CEF (번들 크기 150MB+) |
| 파서 | swift-markdown (초기) | Apple 공식, CommonMark 준수 | 직접 구현 (시간 비용), cmark (C FFI 필요) |
| UI 프레임워크 | AppKit (SwiftUI 부분 혼용) | NSTextView 직접 제어 필수 | 순수 SwiftUI (NSTextView 커스터마이징 불가) |
| 미리보기 | WKWebView | HTML/CSS 렌더링, highlight.js 활용 | AppKit 직접 렌더링 (코드 블록 하이라이팅 구현 비용) |
| 설정 형식 | JSON (직접 편집 가능) | 개발자 친화적, 버전관리 가능, 핫 리로드 용이 | UserDefaults만 (GUI 전용, 이식성 없음), TOML/YAML (추가 파서 필요) |
| 의존성 | 최소화 | 장기 유지보수, App Store 심사 | 과도한 외부 라이브러리 |

---

## 6. SwiftUI vs AppKit 혼용 가이드

```swift
// 편집기 뷰 — 반드시 AppKit (NSViewRepresentable 래핑)
struct EditorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        // NSTextView 생성 및 커스터마이징
    }
}

// 설정창, 툴바 아이콘 — SwiftUI 사용 가능
struct PreferencesView: View { ... }

// 사이드바 — AppKit NSOutlineView 권장 (대용량 파일 트리 성능)
```

---

## 7. 프로젝트 초기 설정 체크리스트

```
Xcode 설정:
  ☐ Template: macOS → App (Document Based Application 체크)
  ☐ Minimum Deployment: macOS 14.0
  ☐ App Sandbox: YES
  ☐ User Selected File: Read/Write
  ☐ Document Types 추가: .md, .markdown (public.plain-text UTType)
  ☐ Exported UTI: net.daringfireball.markdown

Info.plist:
  ☐ CFBundleDocumentTypes (md, markdown)
  ☐ NSSupportsAutomaticTermination: YES
  ☐ NSSupportsSuddenTermination: YES

Signing:
  ☐ 개발 중: Development signing (로컬 실행)
  ☐ 배포: Distribution + Notarization (Gatekeeper 통과 필수)
```

---

## 8. 성능 예산

| 작업 | 목표 |
|------|------|
| 키 입력 → 화면 갱신 | < 16ms |
| 증분 파싱 (단락) | < 5ms |
| 전체 문서 속성 적용 (1MB) | < 500ms (백그라운드) |
| 미리보기 HTML 생성 | < 100ms (debounce 300ms) |
| PDF 내보내기 (100페이지) | < 5s (비동기 허용) |

---

## 9. 함수형 스타일 가이드

이 프로젝트의 Swift 코드는 함수형 스타일을 우선한다. AppKit 바인딩 레이어(클래스 필수 구간)를 제외한 모든 로직에 적용.

### 핵심 원칙

| 원칙 | 적용 방식 |
|------|----------|
| 불변성 우선 | `let` 기본, `var`는 불가피할 때만 |
| 값 타입 우선 | `struct` / `enum` 우선, `class`는 AppKit 서브클래싱·참조 공유 필요시만 |
| 순수 함수 | Parser, Renderer, ConfigLoader — 외부 상태 없음, 같은 입력 → 같은 출력 |
| 사이드 이펙트 격리 | I/O, UI 업데이트는 가장 바깥 레이어(App/ViewController)에서만 |
| 명시적 에러 | `throws` 대신 `Result<T, E>` — 에러 타입이 시그니처에 드러남 |

### 변환 파이프라인 패턴

```swift
// 함수 합성으로 파이프라인 표현
// String → Tokens → AST → AttributedString
func render(markdown: String, config: RenderingConfig) -> NSAttributedString {
    markdown
        |> tokenize                          // String → [Token]
        |> parse                             // [Token] → Document
        |> { applyConfig($0, config) }       // config 주입
        |> renderToAttributedString          // Document → NSAttributedString
}

// |> 연산자 정의 (Swift 기본 미제공)
infix operator |>: AdditionPrecedence
func |> <A, B>(value: A, f: (A) -> B) -> B { f(value) }
```

### 에러 처리 — Result 체이닝

```swift
// ❌ throws 중첩 — 에러 타입 불명확
func load() throws -> AppConfig {
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data)
    return try parse(json)
}

// ✅ Result 체이닝 — 각 단계의 실패 타입 명시
func load() -> Result<AppConfig, ConfigError> {
    readFile(at: url)               // Result<Data, ConfigError>
        .flatMap(parseJSON)         // Result<[String:Any], ConfigError>
        .flatMap(parseConfig)       // Result<AppConfig, ConfigError>
}
```

### 값 타입으로 상태 표현

```swift
// ❌ 클래스 + 뮤테이션
class EditorState {
    var cursorBlock: BlockNode?
    var selection: NSRange = .init()
    func moveCursor(to range: NSRange) { selection = range; ... }
}

// ✅ 구조체 + 새 값 반환
struct EditorState: Equatable {
    let cursorBlock: BlockNode?
    let selection: NSRange

    func withCursor(at range: NSRange, in doc: Document) -> EditorState {
        EditorState(cursorBlock: doc.block(containing: range), selection: range)
    }
}
// 상태 변경 = 새 EditorState 생성 → ViewController가 diff 적용
```

### 컬렉션 변환

```swift
// ❌ 명령형 루프
var results: [NSAttributedString] = []
for node in nodes {
    if node.isVisible { results.append(render(node)) }
}

// ✅ 함수형
let results = nodes
    .filter(\.isVisible)
    .map(render)
```

### AppKit 경계 처리

AppKit 클래스 서브클래싱(NSTextStorage, NSDocument 등)이 필요한 구간은 클래스 사용 불가피. 이 경우:
- 클래스 내부 로직은 순수 함수로 추출 후 호출
- 클래스는 "얇은 어댑터(thin adapter)" 역할만 수행

```swift
class MarkdownTextStorage: NSTextStorage {
    // 클래스 자체는 AppKit 계약 이행만
    override func processEditing() {
        // 실제 로직은 순수 함수에 위임
        let attrs = computeAttributes(string: string,
                                      editedRange: editedRange,
                                      config: config)
        applyAttributes(attrs)  // 유일한 사이드 이펙트
        super.processEditing()
    }
}

// 순수 함수 — XCTest에서 직접 테스트 가능
func computeAttributes(string: String,
                        editedRange: NSRange,
                        config: RenderingConfig) -> [(NSRange, Attributes)] { ... }
```

---

## 10. 참고 자료

- [CommonMark Spec](https://spec.commonmark.org/) — 파서 구현 기준
- [Apple: Text System Overview](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextArchitecture/TextArchitecture.html) — NSTextStorage/NSLayoutManager 이해 필수
- [Apple swift-markdown](https://github.com/apple/swift-markdown) — 공식 파서
- NSTextStorage 서브클래싱: WWDC 2018 Session 221 "TextKit Best Practices"
