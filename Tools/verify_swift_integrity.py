#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
灵犀输入法 (Lingxi IME) Swift 编译前全量静态完整性与 Target 符号校验器
在 Windows / CI 构建前自动检查：
1. 三大 Xcode Target (Lingxi / LingxiKeyboard / LingxiTests) 零顶层符号重名冲突；
2. 键盘扩展 (Keyboard/ & Shared/) 零 App Extension 违禁 API (UIApplication.shared) 调用；
3. 全仓 Swift 文件零未闭合括号与零 TODO/FIXME 残缺占位符；
4. 全仓状态对象与领域模型成员属性/方法调用 100% 匹配已声明符号。
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections import defaultdict


def _strip_comments_and_strings(src: str) -> str:
    """剔除 Swift 注释与普通字符串字面量，供括号配对校验使用。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if src[i] == "/" and i + 1 < n and src[i + 1] == "*":
                    depth += 1
                    i += 2
                elif src[i] == "*" and i + 1 < n and src[i + 1] == "/":
                    depth -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        out.append("\n")
                    i += 1
            continue
        if src[i : i + 3] == '"""':
            i += 3
            while i < n and src[i : i + 3] != '"""':
                if src[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 3
            out.append('""')
            continue
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                i += 1
            i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _check_balanced_delimiters(rel: str, text: str) -> str | None:
    cleaned = _strip_comments_and_strings(text)
    stack: list[tuple[str, int]] = []
    pairs = {"}": "{", ")": "(", "]": "["}
    for lineno, line in enumerate(cleaned.splitlines(), 1):
        for ch in line:
            if ch in "{([":
                stack.append((ch, lineno))
            elif ch in "})]":
                if not stack or stack[-1][0] != pairs[ch]:
                    top = stack[-1] if stack else None
                    return f"ERROR: Unmatched '{ch}' in {rel}:{lineno} (stack top: {top})"
                stack.pop()
    if stack:
        return f"ERROR: Unclosed delimiter(s) in {rel}: {stack[-3:]}"
    return None


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    swift_files = sorted(root.rglob("*.swift"))
    if not swift_files:
        print("ERROR: No Swift files found", file=sys.stderr)
        return 1

    # 1. Target 顶层类型重名扫描
    targets = {
        "Lingxi": ["App", "Shared"],
        "LingxiKeyboard": ["Keyboard", "Shared"],
        "LingxiTests": ["Tests", "Shared", "Keyboard/Engine"],
    }
    top_decl_re = re.compile(
        r"^(?:public\s+|internal\s+|final\s+)*(struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)",
        re.M,
    )

    for tname, dirs in targets.items():
        seen = defaultdict(list)
        for d in dirs:
            for p in sorted((root / d).rglob("*.swift")):
                rel = p.relative_to(root).as_posix()
                text = p.read_text(encoding="utf-8")
                for kind, name in top_decl_re.findall(text):
                    seen[name].append((kind, rel))
        dups = {k: v for k, v in seen.items() if len(v) > 1}
        if dups:
            print(f"ERROR: Target {tname} has duplicate top-level symbols: {dups}", file=sys.stderr)
            return 1

    # 2. App Extension 违禁 API 与 TODO/FIXME 扫描
    all_texts = []
    for p in swift_files:
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf-8")
        all_texts.append(text)
        if (rel.startswith("Shared/") or rel.startswith("Keyboard/")) and "UIApplication.shared" in text:
            print(f"ERROR: Extension-unsafe UIApplication.shared in {rel}", file=sys.stderr)
            return 1
        if re.search(r"\b(TODO|FIXME)\b", text):
            print(f"ERROR: Found TODO/FIXME placeholder in {rel}", file=sys.stderr)
            return 1
        # 防止脱敏占位符或合并冲突标记被误写进源码（编译期才会暴露，CI 提前拦截）
        if re.search(r"\[REDACTED[_A-Z]*\]", text):
            print(f"ERROR: Found redaction placeholder in {rel}", file=sys.stderr)
            return 1
        if re.search(r"^(<{7}|>{7}|={7})( |$)", text, re.M):
            print(f"ERROR: Found merge conflict marker in {rel}", file=sys.stderr)
            return 1
        delim_err = _check_balanced_delimiters(rel, text)
        if delim_err:
            print(delim_err, file=sys.stderr)
            return 1
        # iOS 16 最低系统版本兼容门禁（拦截 iOS 16.1+ / 16.4+ / 17+ 专属 API 与 SF Symbols 5 图标）
        for ios17_pat, ios17_name in (
            (r"@Observable\b", "@Observable (iOS 17+)"),
            (r"\bContentUnavailableView\b", "ContentUnavailableView (iOS 17+)"),
            (r"\.sensoryFeedback\s*\(", ".sensoryFeedback (iOS 17+)"),
            (r"\.fontDesign\s*\(", ".fontDesign (iOS 16.1+)"),
            (r"\.presentationBackground\s*\(", ".presentationBackground (iOS 16.4+)"),
            (r"\.presentationCornerRadius\s*\(", ".presentationCornerRadius (iOS 16.4+)"),
            (r"\.scrollBounceBehavior\s*\(", ".scrollBounceBehavior (iOS 16.4+)"),
            (r"\.fileExporter\s*\([^)]*contentTypes\s*:", ".fileExporter(contentTypes:) (iOS 17+)"),
            (r"\.photosPicker\s*\(", ".photosPicker modifier (iOS 17+)"),
            (r"\.contentMargins\s*\(", ".contentMargins (iOS 17+)"),
            (r"\.symbolEffect\s*\(", ".symbolEffect (iOS 17+)"),
            (r"\bUnevenRoundedRectangle\b", "UnevenRoundedRectangle (iOS 17+)"),
            (r"\bregisterForTraitChanges\b", "registerForTraitChanges (iOS 17+)"),
        ):
            if re.search(ios17_pat, text):
                print(f"ERROR: Found post-iOS-16.0 API {ios17_name} in {rel} (deployment target is iOS 16.0)", file=sys.stderr)
                return 1
        for sf5_sym in (
            "gauge.with.dots.needle.67percent",
            "book.pages",
            "network.badge.shield.half.filled",
            "photo.badge.plus",
            "photo.badge.checkmark",
        ):
            if f'"{sf5_sym}"' in text:
                print(f"ERROR: Found iOS 17+ SF Symbol 5 '{sf5_sym}' in {rel} (renders blank on iOS 16.0)", file=sys.stderr)
                return 1
        if "AppShortcutsProvider" in text and "struct " in text:
            if "@AppShortcutsBuilder" not in text or "shortcutTileColor" not in text:
                print(f"ERROR: AppShortcutsProvider in {rel} missing @AppShortcutsBuilder or shortcutTileColor (Xcode 16 requirement)", file=sys.stderr)
                return 1
        for raw_ln, raw_line in enumerate(text.splitlines(), 1):
            if '#"' in raw_line and r"\u{" in raw_line:
                print(f"ERROR: Invalid ICU regex escape \\u{{...}} inside raw Swift string in {rel}:{raw_ln} (use \\uXXXX)", file=sys.stderr)
                return 1
        code_only = _strip_comments_and_strings(text)
        if "NavigationStack(path:" in code_only and "NavigationLink {" in code_only:
            print(f"ERROR: Mixed NavigationStack(path:) with legacy NavigationLink {{ }} in {rel} (crashes on iOS 16-18)", file=sys.stderr)
            return 1
        if rel.endswith("AISettingsView.swift") and "LazyVGrid(" in code_only:
            print(f"ERROR: Found LazyVGrid inside List in {rel} (causes UICollectionViewListCell self-sizing crash)", file=sys.stderr)
            return 1
        for m in re.finditer(r"\.onChange\s*\(\s*of:[^\n]+\)\s*\{([^\n]*)", text):
            rest = m.group(1).strip()
            if " in" not in rest:
                next_line = text[m.end() : m.end() + 80].splitlines()[0] if m.end() < len(text) else ""
                if " in" not in next_line:
                    print(f"ERROR: Found iOS 17+ 0-arg .onChange in {rel}: {m.group(0)}", file=sys.stderr)
                    return 1
            elif re.search(r"[A-Za-z_][A-Za-z0-9_]*\s*,\s*[A-Za-z_][A-Za-z0-9_]*\s+in", rest):
                print(f"ERROR: Found iOS 17+ 2-arg .onChange in {rel}: {m.group(0)}", file=sys.stderr)
                return 1

    # 3. 领域模型与状态对象成员访问完整性校验
    combined = "\n".join(all_texts)
    declared = set(
        re.findall(
            r"\b(?:var|let|func|case|struct|class|enum|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
            combined,
        )
    )
    system_members = {
        "shared", "rawValue", "allCases", "init", "self", "count", "isEmpty", "first", "last",
        "map", "filter", "sorted", "contains", "prefix", "suffix", "joined", "values", "keys",
        "firstIndex", "removeAll", "insert", "append", "enumerated", "indices", "compactMap", "reduce",
        "max", "min",
        "id", "frame", "bounds", "isHidden", "alpha", "layer", "backgroundColor", "textColor",
        "tintColor", "font", "text", "toggle", "withAlphaComponent", "cgColor", "topAnchor",
        "leadingAnchor", "trailingAnchor", "bottomAnchor", "heightAnchor", "widthAnchor",
        "centerXAnchor", "centerYAnchor", "constraint", "translatesAutoresizingMaskIntoConstraints",
        "removeFromSuperview", "addSubview", "setNeedsLayout", "layoutIfNeeded", "subviews",
        "arrangedSubviews", "addArrangedSubview", "removeArrangedSubview", "isUserInteractionEnabled",
        "trimmingCharacters", "components", "lowercased", "uppercased", "replacingOccurrences",
        "hasPrefix", "hasSuffix", "split", "dropFirst", "dropLast", "removeValue",
    }
    our_roots = [
        "appState", "settings", "theme", "aiConfig", "cloudConfig", "relayConfig", "habitProfile",
        "profile", "healthReport", "health", "outcome", "summary", "domainAnalysis", "domainAffinity",
        "lexicon", "pasteMonitor", "toolbarView", "candidateBar", "engine", "feedback", "Design",
        "Palette", "Spacing", "Radius", "Typography", "SwiftUIFont", "ClipboardStore",
        "CustomWordStore", "QuickPhraseStore", "RecentEmojiStore", "TypingStatsStore",
        "CloudBackendClient", "CloudCredentialStore", "TypingHabitTracker", "ClipboardRelayService",
        "LANSyncService", "CommunityLexiconService", "ComplianceService",
        "EngineHealthAndSustainabilityService", "BigBangTokenizer", "SyncCrypto", "SyncEngine",
        "SyncInfra", "LWWMergeEngine", "LamportClock", "LingxiBackup", "AppGroup",
        "EmojiCatalog", "ClipboardClassifier", "ConcealedPasteboard", "SecureSnippetVault",
        "AIWorkbenchSessionStore", "AIWorkbenchThreadsStore", "AIUsageLedgerStore", "AIRecentHistoryStore",
        "AIPrivacyShield", "AITextDiffEngine", "AICostEstimator", "ClipboardRelayCrypto",
        "PersonalContextCard", "AIBrainExportBundle", "VModeToolEngine", "InlineAICommandDetector",
        "SideloadConfigBridge", "AIClient", "ScreenshotOCRService",
        "KeyboardSwipeCommand", "OfflineTextLinter",
        "ChineseScriptConverter", "ContextualReranker", "CustomKeyboardLayoutPack", "PairedBracketHelper",
        "PromptVariableEngine", "VoiceTranscriptCleaner", "MarkdownBlockParser",
        "CommunicationGuardEngine", "SmartInfoParser",
        "LinkPrivacyCleaner", "DraftRecoveryStore", "PersonalFillCardStore",
        "SocialScriptBank", "SelectionTextTransform",
        "AICognitiveMemoryDB", "AIAutopilotController", "AIAutopilotMode",
        "ObsidianMemoryVaultEngine", "VaultNoteFolder",
    ]

    for p in swift_files:
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf-8")
        for r in our_roots:
            for m in re.finditer(rf"\b{r}\.([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?", text):
                for member in (m.group(1), m.group(2)):
                    if member and member not in declared and member not in system_members:
                        print(f"ERROR: Unresolved member '{member}' in {rel} ({m.group(0)})", file=sys.stderr)
                        return 1

    # 4b. Keyboard cold-start, pasteboard prompt & SwiftUI List/Form LazyVGrid crash regressions
    for p in swift_files:
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf-8")
        if rel.startswith("Keyboard/"):
            for i, line in enumerate(text.splitlines(), 1):
                if re.match(r"^\s*private\s+(var|let)\s+\w+\s*=\s*(LingxiSettings|ThemeCustomization)\.load\(", line):
                    print(f"ERROR: Sync disk load in Keyboard stored property initializer at {rel}:{i}", file=sys.stderr)
                    return 1
        if rel == "Keyboard/KeyboardViewController.swift":
            m_vl = re.search(r"override func viewWillLayoutSubviews\(\)\s*\{([^}]*)\}", text, re.S)
            if m_vl and "updatePreferredHeight(" in m_vl.group(1):
                print("ERROR: updatePreferredHeight() must not be called inside viewWillLayoutSubviews()", file=sys.stderr)
                return 1
            m_va = re.search(r"override func viewWillAppear\(_ animated: Bool\)\s*\{(.*?)\n    \}", text, re.S)
            if m_va and ("tryImportBridgeTokenFromPasteboardIfPresent" in m_va.group(1) or "checkPasteboardScreenshotOnAppearIfNeeded" in m_va.group(1)):
                print("ERROR: Synchronous pasteboard read must not run inside viewWillAppear()", file=sys.stderr)
                return 1
        if rel.startswith("App/Views/") and "LazyVGrid(" in text:
            # Verify no LazyVGrid is placed directly inside a Form/List Section
            lines = text.splitlines()
            for idx, line in enumerate(lines):
                if "LazyVGrid(" in line:
                    ctx_window = "\n".join(lines[max(0, idx - 12):idx])
                    if re.search(r"\bSection(\s*\(|\s*\{)", ctx_window) and "ScrollView" not in ctx_window:
                        print(f"ERROR: LazyVGrid inside List/Form Section in {rel}:{idx+1} (iOS 18 crash hazard)", file=sys.stderr)
                        return 1

    print(
        f"OK  Swift Static Integrity Audit Passed ({len(swift_files)} files, 3 Xcode targets, 0 conflicts, 0 unresolved members)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
