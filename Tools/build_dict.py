#!/usr/bin/env python3
"""
构建灵犀输入法现代只读词库 (SQLite) 与拼音音节表 (Swift 源码)。

数据源（优先级从高到低）:
  1. Tools/data/rime_ice/8105.dict.yaml   雾凇拼音 8105 常用单字表
  2. Tools/data/rime_ice/base.dict.yaml   雾凇拼音现代基础词库
  3. Tools/data/rime_ice/ext.dict.yaml    雾凇拼音扩展词库（精选现代热词）
  4. Tools/data/rime_ice/others.dict.yaml 雾凇拼音杂项补充
  5. Tools/data/extra_words.txt           额外自定义网络热词 / 互联网产品名
  6. Tools/data/rime_ice/en.dict.yaml     英文联想词库 (melt_eng)

输出:
  Keyboard/Resources/pinyin.sqlite
  Keyboard/Engine/PinyinSyllables.swift

用法:
  python Tools/build_dict.py
"""
from __future__ import annotations

import math
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

# 同 engine_prototype.py：强制 UTF-8 输出，避免 Windows GBK 终端打印中文时报 UnicodeEncodeError。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "Tools" / "data"
RIME_ICE = DATA / "rime_ice"
WOWTYPE_DATA = DATA / "wowtype"
RIME_WUBI = DATA / "rime_wubi"
RIME_U = DATA / "rime_u"
EXTRA_WORDS = DATA / "extra_words.txt"
OUT_DB = ROOT / "Keyboard" / "Resources" / "pinyin.sqlite"
OUT_SWIFT = ROOT / "Keyboard" / "Engine" / "PinyinSyllables.swift"

MAX_PHRASE_LEN = 8
BASE_MIN_WEIGHT = 200
HAN_RE = re.compile(r"^[\u4e00-\u9fff]{2,8}$")
T9_TABLE = str.maketrans("abcdefghijklmnopqrstuvwxyz", "22233344455566677778889999")
WUBI_CHARS = set("abcdefghijklmnopqrstuvwxy")


def fail(msg: str) -> None:
    print(f"[build_dict] 错误: {msg}", file=sys.stderr)
    sys.exit(1)


def iter_rime_yaml(path: Path):
    if not path.exists():
        fail(f"找不到词库文件: {path}")
    in_body = False
    for line in path.open(encoding="utf-8"):
        line = line.rstrip("\r\n")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        word = parts[0].strip()
        py_raw = parts[1].strip()
        weight = int(parts[2].strip()) if len(parts) >= 3 and parts[2].strip().isdigit() else 1
        yield word, py_raw, weight


def load_rime_chinese() -> dict[tuple[str, str], float]:
    entries: dict[tuple[str, str], float] = defaultdict(float)

    # 1. 8105 标准常用单字表
    for word, py_raw, wt in iter_rime_yaml(RIME_ICE / "8105.dict.yaml"):
        sy = [s for s in py_raw.split(" ") if s]
        if len(sy) != 1 or not sy[0].isalpha():
            continue
        key = (word, sy[0])
        entries[key] = max(entries[key], float(max(wt, 1)))

    # 2. 雾凇现代基础词库（按词频截取高频核心词；地理行政与交通地标后缀词豁免门槛，防止中小城市/区县缺失）
    geo_suffixes = ("省", "市", "区", "县", "镇", "乡", "州", "盟", "旗", "站", "港", "湾", "湖", "山", "岛", "大学", "机场", "广场")
    for word, py_raw, wt in iter_rime_yaml(RIME_ICE / "base.dict.yaml"):
        sy = [s for s in py_raw.split(" ") if s]
        if not (2 <= len(sy) <= MAX_PHRASE_LEN):
            continue
        is_geo_like = word.endswith(geo_suffixes)
        if wt < BASE_MIN_WEIGHT and not is_geo_like:
            continue
        if any(not s.isalpha() for s in sy):
            continue
        key = (word, "'".join(sy))
        entries[key] = max(entries[key], float(max(wt, 220 if is_geo_like else wt)))

    # 3. 扩展词库中完整收录全部 3 字现代词汇（避免字母序截断导致 P-Z 现代词缺失，如「前后端」）
    for word, py_raw, wt in iter_rime_yaml(RIME_ICE / "ext.dict.yaml"):
        sy = [s for s in py_raw.split(" ") if s]
        if len(sy) != 3 or any(not s.isalpha() for s in sy):
            continue
        key = (word, "'".join(sy))
        if key not in entries:
            entries[key] = float(max(wt, 100))

    # 4. 杂项补充
    others_path = RIME_ICE / "others.dict.yaml"
    if others_path.exists():
        for word, py_raw, wt in iter_rime_yaml(others_path):
            sy = [s for s in py_raw.split(" ") if s]
            if 1 <= len(sy) <= MAX_PHRASE_LEN and all(s.isalpha() for s in sy):
                key = (word, "'".join(sy))
                if key not in entries:
                    entries[key] = float(max(wt, 300))

    return entries


def load_extra(valid_syllables: set[str]) -> dict[tuple[str, str], float]:
    if not EXTRA_WORDS.exists():
        return {}
    try:
        from pypinyin import Style, lazy_pinyin
    except ImportError:
        fail("需要 pypinyin: pip install pypinyin")

    entries: dict[tuple[str, str], float] = {}
    for line in EXTRA_WORDS.open(encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        word = cols[0].strip()
        base_freq = float(cols[1]) if len(cols) > 1 and cols[1].strip() else 3000.0
        # 映射到雾凇权重尺度（约 30x）
        scaled_freq = base_freq * 40.0
        if not HAN_RE.match(word):
            continue
        syllables = [s.replace("ü", "v") for s in lazy_pinyin(word, style=Style.NORMAL, v_to_u=False)]
        if len(syllables) == len(word) and all(s in valid_syllables for s in syllables):
            entries[(word, "'".join(syllables))] = scaled_freq
    return entries


def apply_wowtype_curations(merged: dict[tuple[str, str], float]) -> None:
    """融入 WowType 精选清洗：去脏词(blocklist)、Tatoeba 口语词频融合、热词与 rime-ice 词频修正。"""
    # 1. 去脏词 (blocklist.tsv)
    blocklist_path = WOWTYPE_DATA / "blocklist.tsv"
    if blocklist_path.exists():
        blocked = set()
        for line in blocklist_path.open(encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 2:
                blocked.add(parts[1].strip())
        if blocked:
            for k in [k for k in merged if k[0] in blocked]:
                del merged[k]

    # 2. Tatoeba 口语词频融合（按词总频次融合，权重 0.3，封顶 5 倍防小语料偏移）
    tatoeba_path = WOWTYPE_DATA / "tatoeba-freq.tsv"
    if tatoeba_path.exists():
        counts: dict[str, float] = {}
        for line in tatoeba_path.open(encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 2 and parts[1].strip().isdigit():
                counts[parts[0].strip()] = float(int(parts[1].strip()))
        by_word: dict[str, list[tuple[str, str]]] = defaultdict(list)
        for key in merged:
            by_word[key[0]].append(key)
        shared_lex = 0.0
        shared_ext = 0.0
        for w, keys in by_word.items():
            if w in counts and len(w) >= 2:
                tot = sum(merged[k] for k in keys)
                if tot >= 500.0:
                    shared_lex += tot
                    shared_ext += counts[w]
        if shared_ext > 0:
            scale = shared_lex / shared_ext
            w_ratio = 0.30
            max_factor = 5.0
            floor_wt = 500.0
            for w, keys in by_word.items():
                cnt = counts.get(w)
                if cnt is None or len(w) < 2:
                    continue
                tot = sum(merged[k] for k in keys)
                if tot <= 0:
                    continue
                factor = (tot * (1.0 - w_ratio) + cnt * scale * w_ratio) / tot
                factor = min(factor, max_factor * max(tot, floor_wt) / tot)
                if factor != 1.0:
                    for k in keys:
                        merged[k] = merged[k] * factor

    # 3. WowType 热词 (hotwords.tsv) 与雾凇词频修正 (rime-ice-freq.tsv)：只提不降
    for fname, default_wt in [("hotwords.tsv", 30000.0), ("rime-ice-freq.tsv", 30000.0)]:
        path = WOWTYPE_DATA / fname
        if not path.exists():
            continue
        for line in path.open(encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            py_parts = [s.strip().lower().replace("ü", "v") for s in parts[0].strip().split() if s.strip()]
            word = parts[1].strip()
            if not word or not py_parts or len(py_parts) > MAX_PHRASE_LEN or any(not s.isalpha() for s in py_parts):
                continue
            wt = float(int(parts[2].strip())) if len(parts) >= 3 and parts[2].strip().isdigit() else default_wt
            key = (word, "'".join(py_parts))
            merged[key] = max(merged.get(key, 0.0), wt)

    # 4. 全国完整省/市/区/县 + 口语简称 + 交通/商圈/高校地标权威词表 (china_geo.tsv)
    china_geo_path = DATA / "china_geo.tsv"
    if china_geo_path.exists():
        for line in china_geo_path.open(encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            word = parts[0].strip()
            py_parts = [s.strip().lower().replace("ü", "v") for s in parts[1].strip().split("'") if s.strip()]
            if not word or not py_parts or len(py_parts) > MAX_PHRASE_LEN or any(not s.isalpha() for s in py_parts):
                continue
            wt = float(int(parts[2].strip())) if len(parts) >= 3 and parts[2].strip().isdigit() else 120000.0
            key = (word, "'".join(py_parts))
            merged[key] = max(merged.get(key, 0.0), wt)


def load_wubi86() -> list[tuple[str, str, int, int]]:
    """按 WowType wubi2tsv.py 规则解析 Rime 五笔 86 码表（过滤 z 码、0 权重生僻扩展字与私用区）。"""
    path = RIME_WUBI / "wubi86.dict.yaml"
    if not path.exists():
        print("[build_dict] 提示: 未找到 wubi86.dict.yaml，跳过五笔表", file=sys.stderr)
        return []
    entries: dict[tuple[str, str], tuple[int, int]] = {}
    in_body = False
    for lineno, line in enumerate(path.open(encoding="utf-8"), 1):
        line = line.rstrip("\r\n")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 2 or len(fields) > 4:
            continue
        word, code = fields[0], fields[1]
        if not word or not code or code.startswith("z"):
            continue
        if len(code) > 4 or not set(code) <= WUBI_CHARS:
            continue
        if any(0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000 for ch in word):
            continue
        if len(fields) == 2 or not fields[2].strip():
            weight = 1
        else:
            try:
                weight = int(fields[2].strip())
            except ValueError:
                continue
            if weight <= 0:
                continue
        key = (code, word)
        if key not in entries or weight > entries[key][0]:
            entries[key] = (weight, lineno)

    rows = sorted(entries.items(), key=lambda kv: (kv[0][0], -kv[1][0], kv[1][1]))
    return [(code, word, wt, idx) for idx, ((code, word), (wt, _)) in enumerate(rows)]


def build_char_readings(merged: dict[tuple[str, str], float]) -> tuple[dict[str, str], dict[str, int]]:
    """为单字建立最常用拼音读音与权重映射（供 U 模式拆字/笔画反查显示读音并排序）。"""
    best_py: dict[str, tuple[str, float]] = {}
    for (word, py), wt in merged.items():
        if len(word) == 1 and "'" not in py:
            prev = best_py.get(word)
            if prev is None or wt > prev[1]:
                best_py[word] = (py, wt)
    readings = {w: py for w, (py, _) in best_py.items()}
    weights = {w: max(1, int(wt)) for w, (_, wt) in best_py.items()}
    return readings, weights


def load_chaizi(char_readings: dict[str, str], char_weights: dict[str, int]) -> list[tuple[str, str, str, int]]:
    """解析 Rime radical_pinyin 部件拆字表（如 ushuishuishui -> 淼 miao, ufangfangtu -> 堃 kun）。"""
    path = RIME_U / "radical_pinyin.dict.yaml"
    if not path.exists():
        print("[build_dict] 提示: 未找到 radical_pinyin.dict.yaml，跳过拆字表", file=sys.stderr)
        return []
    try:
        from pypinyin import Style, lazy_pinyin
    except ImportError:
        lazy_pinyin = None

    entries: dict[tuple[str, str], int] = {}
    in_body = False
    for line in path.open(encoding="utf-8"):
        line = line.rstrip("\r\n")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        word = parts[0].strip()
        if len(word) != 1:
            continue
        cp = ord(word)
        # 仅保留常用 BMP 汉字，剔除私用区和罕见兼容区
        if not (0x4E00 <= cp <= 0x9FFF):
            continue
        code = parts[1].strip().lower().replace("'", "").replace(" ", "")
        if not code or not code.isalpha() or len(code) > 24:
            continue
        wt = int(parts[2].strip()) if len(parts) >= 3 and parts[2].strip().isdigit() else 1
        # 融合单字常用度权重，常用字排在更前面
        eff_wt = max(wt, min(50000, char_weights.get(word, 0) // 100))
        key = (code, word)
        if eff_wt > entries.get(key, -1):
            entries[key] = eff_wt

    out: list[tuple[str, str, str, int]] = []
    py_cache = dict(char_readings)
    for (code, word), wt in entries.items():
        py = py_cache.get(word)
        if py is None:
            if lazy_pinyin is not None:
                p = lazy_pinyin(word, style=Style.NORMAL, v_to_u=False)
                py = p[0].replace("ü", "v") if p and p[0].isalpha() else ""
            else:
                py = ""
            py_cache[word] = py
        out.append((code, word, py, wt))
    out.sort(key=lambda r: (r[0], -r[3]))
    return out


def load_strokes(char_readings: dict[str, str], char_weights: dict[str, int], known_chaizi_chars: set[str]) -> list[tuple[str, str, str, int]]:
    """解析 Rime stroke 五笔画反查表（h横 s竖 p撇 n捺 z折），聚焦 BMP 常用汉字与生僻常见字。"""
    path = RIME_U / "stroke.dict.yaml"
    if not path.exists():
        print("[build_dict] 提示: 未找到 stroke.dict.yaml，跳过笔画表", file=sys.stderr)
        return []
    try:
        from pypinyin import Style, lazy_pinyin
    except ImportError:
        lazy_pinyin = None

    stroke_chars = set("hspnz")
    allowed_words = set(char_readings.keys()) | known_chaizi_chars
    seen: set[tuple[str, str]] = set()
    py_cache = dict(char_readings)
    out: list[tuple[str, str, str, int]] = []
    in_body = False
    for line in path.open(encoding="utf-8"):
        line = line.rstrip("\r\n")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        word, code = parts[0].strip(), parts[1].strip().lower()
        if len(word) != 1 or word not in allowed_words:
            continue
        if not code or len(code) > 36 or not (set(code) <= stroke_chars):
            continue
        key = (code, word)
        if key in seen:
            continue
        seen.add(key)
        py = py_cache.get(word)
        if py is None:
            if lazy_pinyin is not None:
                p = lazy_pinyin(word, style=Style.NORMAL, v_to_u=False)
                py = p[0].replace("ü", "v") if p and p[0].isalpha() else ""
            else:
                py = ""
            py_cache[word] = py
        wt = max(1, char_weights.get(word, 1))
        out.append((code, word, py, wt))
    out.sort(key=lambda r: (r[0], -r[3]))
    return out


def build_glide_lexicon(rows: list[tuple[str, str, str, str, float]], limit: int = 28000) -> list[tuple[str, str, str, str, str, float]]:
    """提取高频 1~4 字词构建滑行输入专用几何索引表（按首尾字母分桶，单次查表 < 0.5ms）。"""
    eligible = []
    for word, py, _abbr, _t9, lp in rows:
        if 1 <= len(word) <= 4:
            py_flat = py.replace("'", "")
            if 2 <= len(py_flat) <= 18 and py_flat.isalpha():
                eligible.append((py_flat[0], py_flat[-1], py_flat, py, word, lp))
    eligible.sort(key=lambda r: -r[5])
    # 每个 (py_flat, word) 去重后保留 Top limit
    dedup = []
    seen: set[tuple[str, str]] = set()
    for item in eligible:
        k = (item[2], item[4])
        if k not in seen:
            seen.add(k)
            dedup.append(item)
            if len(dedup) >= limit:
                break
    dedup.sort(key=lambda r: (r[0], r[1], -r[5]))
    return dedup


def load_english_words() -> list[tuple[str, str, int]]:
    rows_map: dict[str, tuple[str, int]] = {}
    canonical_tech = {
        "iphone": ("iPhone", 900), "ipad": ("iPad", 860), "macos": ("macOS", 860),
        "ios": ("iOS", 860), "wechat": ("WeChat", 900), "github": ("GitHub", 900),
        "deepseek": ("DeepSeek", 900), "chatgpt": ("ChatGPT", 900), "openai": ("OpenAI", 880),
        "gemini": ("Gemini", 880), "claude": ("Claude", 860), "python": ("Python", 880),
        "swift": ("Swift", 850), "swiftui": ("SwiftUI", 850), "xcode": ("Xcode", 850),
        "rust": ("Rust", 840), "linux": ("Linux", 860), "docker": ("Docker", 840),
        "typescript": ("TypeScript", 840), "javascript": ("JavaScript", 840),
        "vscode": ("VSCode", 840), "sqlite": ("SQLite", 840), "json": ("JSON", 840),
        "api": ("API", 840), "url": ("URL", 820), "pdf": ("PDF", 820), "ai": ("AI", 880),
        "llm": ("LLM", 820), "ok": ("OK", 820), "vip": ("VIP", 820), "app": ("App", 850),
        "hello": ("hello", 850), "google": ("Google", 860), "apple": ("Apple", 860),
    }
    hot_words = {
        "the": 1000, "and": 950, "you": 920, "that": 900, "for": 890, "with": 880,
        "this": 870, "have": 860, "from": 850, "what": 840, "hello": 830, "good": 820,
        "thanks": 810, "thank": 800, "please": 790, "sorry": 780, "okay": 770, "ok": 760,
        "email": 670, "password": 660, "meeting": 650, "project": 640, "update": 630,
        "design": 620, "happy": 610, "birthday": 600, "morning": 590, "night": 580,
        "today": 570, "tomorrow": 560, "like": 700, "danger": 620,
    }

    for fname in ["en.dict.yaml", "en_ext.dict.yaml"]:
        path = RIME_ICE / fname
        if not path.exists():
            continue
        in_body = False
        for line in path.open(encoding="utf-8"):
            line = line.rstrip("\r\n")
            if not in_body:
                if line == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            word = parts[0].strip()
            if not word or not word.isascii() or len(word) > 24:
                continue
            lower = word.lower()
            if not lower.isalpha():
                continue
            wt = int(parts[2].strip()) if len(parts) >= 3 and parts[2].strip().isdigit() else 0
            rank = max(hot_words.get(lower, max(10, 200 - len(lower) * 8)), wt)
            prev = rows_map.get(lower)
            if prev is None or rank > prev[1]:
                rows_map[lower] = (word, rank)

    for lower, (word, rank) in canonical_tech.items():
        prev_rank = rows_map.get(lower, (word, 0))[1]
        rows_map[lower] = (word, max(rank, prev_rank))

    return [(lower, word, rank) for lower, (word, rank) in rows_map.items()]


def mine_sys_bigrams(word_weights: dict[str, float], limit: int = 100000) -> list[tuple[str, str, float]]:
    """从雾凇词库与高频组合词切分中挖掘真实二元搭配（供 Beam Search 消歧、光标上文消歧与首日下一词预测）。"""
    unigram_wt: dict[str, float] = {}
    phrases: list[tuple[str, float]] = []
    for (word, _py), wt in word_weights.items():
        if len(word) <= 4:
            unigram_wt[word] = max(unigram_wt.get(word, 0.0), wt)
        if 3 <= len(word) <= 8 or (len(word) == 2 and wt >= 4000.0):
            phrases.append((word, wt))

    bigrams: dict[tuple[str, str], float] = defaultdict(float)
    for word, wt in phrases:
        n = len(word)
        best_pair: tuple[str, str] | None = None
        best_sc = -1.0
        for k in range(1, n):
            l, r = word[:k], word[k:]
            wl = unigram_wt.get(l, 0.0)
            wr = unigram_wt.get(r, 0.0)
            if wl >= 200.0 and wr >= 200.0:
                sc = math.log(wl) + math.log(wr)
                if sc > best_sc:
                    best_sc = sc
                    best_pair = (l, r)
        if best_pair is not None:
            bigrams[best_pair] += wt

    # 全局 Top limit + 高频上文词（如 我/我们/你好/吃饭/不）各自保留前 128 个自然搭配，避免常见主语漏掉高频动词（如 我们->会）
    kept: dict[tuple[str, str], float] = dict(sorted(bigrams.items(), key=lambda kv: -kv[1])[:limit])
    by_prev: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for (p, n_w), wt in bigrams.items():
        if wt >= 300.0 and unigram_wt.get(p, 0.0) >= 20000.0:
            by_prev[p].append((n_w, wt))
    for p, lst in by_prev.items():
        lst.sort(key=lambda x: -x[1])
        cap = 128 if unigram_wt.get(p, 0.0) >= 100000.0 else 64
        for n_w, wt in lst[:cap]:
            if (p, n_w) not in kept:
                kept[(p, n_w)] = wt

    ranked = sorted(kept.items(), key=lambda kv: -kv[1])
    return [(prev_w, next_w, round(min(3.2, 0.40 * math.log10(1.0 + wt)), 4)) for (prev_w, next_w), wt in ranked]


def build() -> None:
    merged = load_rime_chinese()
    apply_wowtype_curations(merged)
    syllables = {s for (_, py) in merged for s in py.split("'")}
    extra = load_extra(syllables)
    for key, freq in extra.items():
        merged[key] = max(merged.get(key, 0.0), freq)

    bigram_rows = mine_sys_bigrams(merged, limit=150000)
    wubi_rows = load_wubi86()
    char_readings, char_weights = build_char_readings(merged)
    chaizi_rows = load_chaizi(char_readings, char_weights)
    stroke_rows = load_strokes(char_readings, char_weights, {r[1] for r in chaizi_rows})

    total = sum(merged.values())
    OUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUT_DB.exists():
        OUT_DB.unlink()

    con = sqlite3.connect(OUT_DB)
    con.executescript(
        """
        PRAGMA page_size = 8192;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE dict (
            word    TEXT NOT NULL,
            py      TEXT NOT NULL,
            abbr    TEXT NOT NULL,
            t9_abbr TEXT NOT NULL,
            lp      REAL NOT NULL
        );
        CREATE TABLE en_dict (
            lower TEXT PRIMARY KEY,
            word  TEXT NOT NULL,
            rank  INTEGER NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE sys_bigrams (
            prev  TEXT NOT NULL,
            next  TEXT NOT NULL,
            bonus REAL NOT NULL,
            PRIMARY KEY (prev, next)
        ) WITHOUT ROWID;
        CREATE TABLE wubi (
            code   TEXT NOT NULL,
            word   TEXT NOT NULL,
            weight INTEGER NOT NULL,
            ord    INTEGER NOT NULL
        );
        CREATE TABLE chaizi (
            code   TEXT NOT NULL,
            word   TEXT NOT NULL,
            py     TEXT NOT NULL,
            weight INTEGER NOT NULL
        );
        CREATE TABLE strokes (
            code   TEXT NOT NULL,
            word   TEXT NOT NULL,
            py     TEXT NOT NULL,
            weight INTEGER NOT NULL
        );
        CREATE TABLE glide_dict (
            first_c TEXT NOT NULL,
            last_c  TEXT NOT NULL,
            py_flat TEXT NOT NULL,
            py      TEXT NOT NULL,
            word    TEXT NOT NULL,
            lp      REAL NOT NULL
        );
        """
    )

    rows = []
    max_len = 1
    for (word, py), freq in merged.items():
        sy = py.split("'")
        max_len = max(max_len, len(sy))
        abbr = "".join(s[0] for s in sy)
        t9_abbr = abbr.translate(T9_TABLE)
        rows.append((word, py, abbr, t9_abbr, math.log(freq / total)))

    glide_rows = build_glide_lexicon(rows, limit=20000)

    rows.sort(key=lambda r: (r[2], -r[4]))
    con.executemany("INSERT INTO dict (word, py, abbr, t9_abbr, lp) VALUES (?,?,?,?,?)", rows)

    en_rows = load_english_words()
    con.executemany("INSERT INTO en_dict (lower, word, rank) VALUES (?,?,?)", en_rows)
    con.executemany("INSERT INTO sys_bigrams (prev, next, bonus) VALUES (?,?,?)", bigram_rows)
    if wubi_rows:
        con.executemany("INSERT INTO wubi (code, word, weight, ord) VALUES (?,?,?,?)", wubi_rows)
    if chaizi_rows:
        con.executemany("INSERT INTO chaizi (code, word, py, weight) VALUES (?,?,?,?)", chaizi_rows)
    if stroke_rows:
        con.executemany("INSERT INTO strokes (code, word, py, weight) VALUES (?,?,?,?)", stroke_rows)
    if glide_rows:
        con.executemany("INSERT INTO glide_dict (first_c, last_c, py_flat, py, word, lp) VALUES (?,?,?,?,?,?)", glide_rows)

    con.executescript(
        """
        CREATE INDEX idx_dict_abbr    ON dict (abbr, lp DESC);
        CREATE INDEX idx_dict_t9      ON dict (t9_abbr, lp DESC);
        CREATE INDEX idx_wubi_code    ON wubi (code, weight DESC, ord ASC);
        CREATE INDEX idx_wubi_word    ON wubi (word, length(code) ASC, ord ASC);
        CREATE INDEX idx_chaizi_code  ON chaizi (code, weight DESC);
        CREATE INDEX idx_strokes_code ON strokes (code, weight DESC);
        CREATE INDEX idx_glide_ends   ON glide_dict (first_c, last_c, lp DESC);
        CREATE INDEX idx_glide_word   ON glide_dict (word, lp DESC);
        ANALYZE;
        """
    )
    con.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [
            ("version", "5"),
            ("entries", str(len(rows))),
            ("en_entries", str(len(en_rows))),
            ("bigrams", str(len(bigram_rows))),
            ("wubi_entries", str(len(wubi_rows))),
            ("chaizi_entries", str(len(chaizi_rows))),
            ("stroke_entries", str(len(stroke_rows))),
            ("glide_entries", str(len(glide_rows))),
            ("max_len", str(max_len)),
            ("source", "rime-ice + WowType + rime-wubi86 + rime-radical-pinyin + rime-stroke"),
        ],
    )
    con.commit()
    con.execute("VACUUM")
    con.close()

    all_syllables = sorted(syllables)
    lines = [
        "// 此文件由 Tools/build_dict.py 自动生成，请勿手动修改。",
        "// 音节集合与 pinyin.sqlite 词库严格一致。",
        "",
        "enum PinyinSyllables {",
        "    static let all: [String] = [",
    ]
    for i in range(0, len(all_syllables), 10):
        chunk = ", ".join(f'"{s}"' for s in all_syllables[i:i + 10])
        lines.append(f"        {chunk},")
    lines += ["    ]", "}", ""]
    OUT_SWIFT.parent.mkdir(parents=True, exist_ok=True)
    OUT_SWIFT.write_text("\n".join(lines), encoding="utf-8")

    size_mb = OUT_DB.stat().st_size / (1024 * 1024)
    print(f"[build_dict] 完成 v5: {len(rows)} 中文, {len(en_rows)} 英文, {len(bigram_rows)} 二元搭配, {len(wubi_rows)} 五笔86, {len(chaizi_rows)} 拆字, {len(stroke_rows)} 笔画, {len(glide_rows)} 滑行词库, {len(all_syllables)} 音节, 词库 {size_mb:.2f} MB")


if __name__ == "__main__":
    build()
