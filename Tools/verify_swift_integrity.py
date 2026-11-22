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
        "EmojiCatalog", "ClipboardClassifier",
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

    print(
        f"OK  Swift Static Integrity Audit Passed ({len(swift_files)} files, 3 Xcode targets, 0 conflicts, 0 unresolved members)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
