<div align="center">

<img src="Assets/IntendLogo.png" alt="Intend Logo" width="120" />

# Intend

**A minimal, native macOS Markdown editor — with encrypted vaults for sensitive documents.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

</div>

---

## Why Intend?

Most people who write Markdown don't work in VS Code or a full IDE every day. Opening a `.md` file shouldn't require a developer setup. Intend is a **focused, distraction-free editor** that just opens and renders Markdown — fast, clean, and native to macOS.

On top of that, AI-assisted work and team collaboration increasingly produce documents that contain **confidential information** — internal specs, API keys, strategy notes, personal data. Intend lets you lock any document with a password, producing a `.mdxk` file that is indistinguishable from random bytes without the key. Share Markdown, keep secrets.

---

## Features

### Writing & Editing

- **WYSIWYG inline rendering** — headings, bold, italic, code, blockquotes, links, and horizontal rules render in-place as you type. Raw syntax tokens (`**`, `#`) are hidden, not deleted.
- **Auto-pair & smart editing** — automatic bracket/quote pairing, smart Enter inside lists and blockquotes, Tab/Shift-Tab for list indentation.
- **Incremental parser** — only the edited paragraph is re-parsed on each keystroke. Large files stay responsive.
- **LaTeX math** — inline `$...$` and block `$$...$$` expressions rendered natively.
- **Mermaid diagrams** — fenced ` ```mermaid ` blocks rendered as images when the cursor leaves the block.
- **Multi-tab editing** — open multiple files simultaneously with a clean tab bar.

### Navigation

- **File sidebar** — browse your entire folder tree without leaving the app. Auto-refreshes on file system changes.
- **Table of Contents panel** — live, hierarchical heading list (H1–H6) in the right pane. Click any entry to jump to that position.

### Privacy & Security

- **Encrypted Markdown (`.mdxk`)** — save any document in AES-256-GCM encrypted format.
  - Key derivation: PBKDF2-SHA256, 200 000 iterations, 16-byte random salt.
  - File layout: `[4B magic] [16B salt] [12B nonce] [ciphertext + 16B GCM tag]`.
  - Wrong password → authentication tag mismatch; no information about the plaintext is exposed.
- **Password entry UX** — real-time match/mismatch feedback with color-coded field borders (green / red) and inline validation messages. Confirm button stays disabled until passwords match.
- **Zero external dependencies for crypto** — uses Apple's `CryptoKit` exclusively. No third-party code touches your keys or plaintext.
- **`.mdxk` is the default app** — Intend registers as the system owner of the `.mdxk` file type. Double-click to open, enter password, done.

### Viewing & Export

- **Split preview** — live HTML preview rendered in a WKWebView, debounced at 300 ms.
- **HTML export** — one-click clean HTML file with embedded styles.
- **PDF export** — high-fidelity PDF via WKWebView's native print pipeline. Korean (CJK) fonts handled correctly.
- **Syntax highlighting** — code blocks highlighted via bundled highlight.js (no network calls).

### Appearance & Focus

- **Light / Dark mode** — full system appearance support with automatic switching. Semantic NSColor tokens throughout.
- **Custom editor background** — set a solid color, a custom image, or make the editor transparent with adjustable opacity.
- **Focus / distraction-free mode** — toggle with `⌘\` to hide all chrome.
- **Preferences window** — font family, font size, line height, theme colors, and background settings — all configurable without touching a config file.

### System Integration

- **macOS document model** — built on `NSDocument`. Full undo history, autosave, and version browsing work out of the box.
- **Finder integration** — `.md`, `.markdown`, `.mdown` files appear under "Open With › Intend" in Finder right-click menus.
- **Status bar** — live character count (with and without whitespace) and last-edited timestamp in the bottom bar.

---

## Requirements

|                  |                                   |
| ---------------- | --------------------------------- |
| **OS**           | macOS 14 Sonoma or later          |
| **Architecture** | Apple Silicon & Intel (Universal) |

---

## Installation

### Download (recommended)

Download the latest `.dmg` from the [Releases](../../releases) page, drag **Intend.app** to `/Applications`, and open it.

> **First launch on macOS 14+:** If Gatekeeper blocks the app, right-click → Open, or run:
>
> ```sh
> xattr -cr /Applications/Intend.app
> ```

### Build from source

```sh
# Clone
git clone https://github.com/your-username/intend.git
cd intend

# Open in Xcode (recommended)
open Intend.xcodeproj

# Or build from the command line
xcodebuild -project Intend.xcodeproj -scheme Intend -configuration Release build
```

**Dependencies** — fetched automatically via Swift Package Manager:

- [`swift-markdown`](https://github.com/apple/swift-markdown) (Apple) — CommonMark-compliant parser

---

## Encrypted Markdown (`.mdxk`)

Intend introduces the `.mdxk` format for password-protected Markdown documents.

```
┌─────────────────────────────────────────────────┐
│  4B  │  Magic bytes  "MDXK"                      │
│ 16B  │  Random salt  (PBKDF2 input)               │
│ 12B  │  AES-GCM nonce                             │
│  NB  │  Ciphertext + 16B authentication tag       │
└─────────────────────────────────────────────────┘
```

**Save as encrypted:**
`File → Save As…` → select `.mdxk` format → enter password twice → done.

**Open encrypted file:**
Double-click any `.mdxk` file → enter password → the document opens as normal Markdown.

**Security properties:**

- Confidentiality: AES-256-GCM (NIST SP 800-38D)
- Integrity: GCM authentication tag — any tampering is detected on open
- Key stretching: PBKDF2-SHA256 with 200 000 iterations makes brute-force infeasible
- The password never touches disk; it is zeroed from memory after key derivation

---

## Intend + Agentic AI

AI coding agents — **Claude Code**, **OpenClaw**, and similar agentic tools — generate and edit files directly on your filesystem. That includes documentation, runbooks, architecture notes, and prompt files that often contain sensitive context: system prompts with internal business logic, API keys embedded in examples, team-only strategy memos written in Markdown.

Intend closes the gap between AI-assisted writing and secure storage.

### The problem

When an AI agent writes a `.md` file to disk, that file sits in plaintext. Anyone with access to the directory — a teammate, a future AI session with broader scope, or a misconfigured sync tool — can read it in full.

### How `.mdxk` fits in

```
AI agent writes draft → save as .mdxk → encrypted at rest
                                              ↓
                              share file / commit to repo
                                              ↓
                         recipient opens in Intend → password prompt → plaintext
```

- **Commit encrypted documents to version control.** `.mdxk` files are safe to commit; without the password they reveal nothing.
- **Share confidential Markdown over insecure channels.** Email, Slack, shared drives — the ciphertext is meaningless without the key.
- **Scope AI context intentionally.** Give an agent only the `.md` files it needs; lock everything else as `.mdxk`. The agent cannot read what it cannot decrypt.

### Workflow example with Claude Code

```sh
# 1. Agent drafts a sensitive architecture doc
claude "document our internal auth flow" > auth-internal.md

# 2. Read heading structure from plaintext Markdown
intend auth-internal.md
# -> ["# Internal Auth Flow", "## Token Lifetime", ...]

# 3. Or inspect full plaintext explicitly
intend --all auth-internal.md

# 4. For encrypted documents, provide the password
intend -p "$INTEND_PASSWORD" secrets.mdxk
# -> ["# Incident Notes", "## Root Cause", ...]
```

> The CLI is available alongside the macOS app so that Markdown and encrypted `.mdxk` documents can be inspected from shell scripts, agent workflows, and terminal tooling without opening the GUI.

---

## CLI

The current CLI supports both plaintext Markdown (`.md`) and encrypted Intend documents (`.mdxk`).

### Basic usage

```sh
# Plaintext Markdown: return heading lines as JSON array
intend notes.md

# Encrypted Markdown: decrypt, then return heading lines as JSON array
intend -p mypassword secrets.mdxk

# Subcommand form is also supported
intend decrypt notes.md
```

### Output modes

```sh
# 1. Default: extract heading lines only
intend notes.md
# -> ["# Title", "## Section", "### Details"]

# 2. Full document output
intend --all notes.md
intend -p mypassword secrets.mdxk --all

# 3. Exact heading level sections as JSON array
intend --level 2 notes.md
intend -p mypassword --level 2 secrets.mdxk
# -> ["## Section A\n...", "## Section B\n..."]
```

### Notes

- Input files must be `.md` or `.mdxk`.
- `-p, --password` is required for `.mdxk` files.
- `-p, --password` must not be used with plaintext `.md` files.
- `--all` and `-l, --level` are mutually exclusive.
- `--level` currently supports exact ATX heading levels `1` through `5`.
- Default and `--level` output are JSON string arrays intended for scripting and agent workflows.

Run `intend --help` for details.

---

## Architecture

```
Sources/
├── App/           AppDelegate, main entry point
├── Config/        AppConfig (value type), ConfigManager, ConfigWatcher
├── Document/      MarkdownDocument (NSDocument subclass)
├── Editor/        EditorWindowController, EditorViewController
│   ├── MarkdownTextView     NSTextView subclass — font/color from config
│   ├── MarkdownTextStorage  NSTextStorage subclass — incremental attribute application
│   └── InputHandler         Pure-function key transform — auto-pair, smart Enter/Tab/Backspace
├── Parser/        RenderNode (value-type AST), MarkdownParser, IncrementalParser
├── Renderer/      AttributeRenderer — ParseResult → NSAttributedString attributes
├── Preview/       PreviewViewController — WKWebView + 300 ms debounce
├── Sidebar/       FileNode, FileWatcher, SidebarViewController (NSOutlineView)
├── TOC/           TOCEntry, TOCViewController (NSTableView)
├── Theme/         ThemeManager — hex→NSColor conversion, system color fallback
├── Export/        HTMLExporter (pure function), PDFExporter (WKWebView.createPDF)
├── Encryption/    MarkdownEncryptor (CryptoKit AES-GCM), PasswordSheetController
├── Math/          LatexRenderer, MermaidRenderer
└── Preferences/   PreferencesWindowController
```

**Key design decisions:**

- No MVVM/VIPER — plain AppKit MVC. `NSDocument` owns the source-of-truth string.
- Editor uses `NSTextStorage` + `NSLayoutManager`, not WKWebView — keystroke latency is sub-millisecond.
- `Parser/` has zero AppKit imports; it is fully unit-testable in isolation.
- Swift 6 strict concurrency throughout. All UI work is `@MainActor`; parsing runs on a dedicated `DispatchQueue`.

---

## Contributing

Bug reports and pull requests are welcome. For major changes, please open an issue first to discuss the proposed change.

```sh
# Run all tests
xcodebuild -project Intend.xcodeproj -scheme IntendTests \
  -destination 'platform=macOS' test
```

---

## License

MIT © 2025 — see [LICENSE](LICENSE) for details.
