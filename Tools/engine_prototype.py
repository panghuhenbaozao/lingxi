#!/usr/bin/env python3
"""
灵犀输入法引擎 v4 参考实现 (Python 原型) + 全量回归测试（含 WowType regress.tsv 评测）。

验证能力:
  1. 雾凇拼音 + WowType 词频融合 (Tatoeba/热词/去脏词) + 10万 sys_bigrams + 9.3万五笔86
  2. 精确全拼保护 (protect_exact_input) + 整词压制单字拼凑 + 歧义音节拆分 (xian -> 先/西安)
  3. 儿化音 (wanr -> 玩儿, zher -> 这儿, yidianr -> 一点儿, haowanr -> 好玩儿)
  4. 全拼混简拼 (kyi -> 可以, wanqky -> 完全可以, yongzwen -> 用中文, zhchi -> 支持, weish -> 为啥)
  5. 光标上文语境消歧 (我+知道/要/会, 你好+吗/了, 吃饭+了/吗)
  6. 英文精准排位 (github/wechat/iphone/deepseek -> #1; like/danger -> #6)
  7. 4 路拼写容错 (换位/多键删除/邻键替换/漏元音)
  8. 7 种双拼方案 (自然码/小鹤/微软/搜狗/智能ABC/紫光/拼音加加) + 五笔86与 z 临时拼音反查
  9. T9 九宫格数字拼音分词与解码

用法: python Tools/engine_prototype.py
"""
from __future__ import annotations

import math
import sqlite3
import sys
import time
from dataclasses import dataclass
from pathlib import Path

# Windows 终端默认 GBK 编码，打印含生僻字的候选词会触发 UnicodeEncodeError；
# 统一强制 UTF-8 输出，保证脚本在 Windows / macOS / Linux 行为一致。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "Keyboard" / "Resources" / "pinyin.sqlite"
REGRESS_TSV = ROOT / "Tools" / "data" / "wowtype" / "regress.tsv"

MAX_SYLLABLE_LEN = 6
MAX_PHRASE_LEN = 8
MAX_SEGMENTATIONS = 6
INVALID_LP = -40.0
WORD_BOUNDARY_PENALTY = 3.2
CONTEXT_BIGRAM_WEIGHT = 0.65
MERGED_PAIR_SCORE = 1.5
PARTIAL_COMPLETION_PENALTY = 1.2
SYLLABLE_ALIASES = {"lue": "lve", "nue": "nve"}

QWERTY_POS: dict[str, tuple[float, float]] = {
    **{ch: (float(i), 0.0) for i, ch in enumerate("qwertyuiop")},
    **{ch: (0.5 + float(i), 1.0) for i, ch in enumerate("asdfghjkl")},
    **{ch: (1.5 + float(i), 2.0) for i, ch in enumerate("zxcvbnm")},
}
CONSONANT_SYLLABLES = {"n", "m", "ng", "hm", "hng"}

COST_COMPLETE = 1.0
COST_PARTIAL_END = 1.3
COST_PARTIAL_MID = 1.8
COST_INVALID = 5.0

T9_MAP = str.maketrans("abcdefghijklmnopqrstuvwxyz", "22233344455566677778889999")
ADJACENT_KEYS = {
    "q": "wa", "w": "qes", "e": "wrd", "r": "etf", "t": "ryg", "y": "tuh", "u": "yij", "i": "uok", "o": "ipl", "p": "ol",
    "a": "qwsz", "s": "awedxz", "d": "serfcx", "f": "drtgvc", "g": "ftyhbv", "h": "gyujnb", "j": "huikmn", "k": "jiolm", "l": "kop",
    "z": "asx", "x": "zsdc", "c": "xdfv", "v": "cfgb", "b": "vghn", "n": "bhjm", "m": "njk",
}

# 小鹤双拼表（供 regress.tsv 中 sp=xiaohe 验证）
XIAOHE_FINALS = {
    "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
    "iu": "q", "ei": "w", "uan": "r", "ue": "t", "ve": "t", "un": "y", "uo": "o", "ie": "p",
    "ong": "s", "iong": "s", "ing": "k", "uai": "k", "ai": "d", "en": "f", "eng": "g", "iang": "l", "uang": "l",
    "ang": "h", "ian": "m", "an": "j", "ou": "z", "ia": "x", "ua": "x", "iao": "n", "ao": "c", "ui": "v", "in": "b",
}
XIAOHE_ZERO = {
    "aa": "a", "ai": "ai", "an": "an", "ah": "ang", "ao": "ao", "ad": "ai", "aj": "an", "ac": "ao",
    "ee": "e", "ei": "ei", "en": "en", "eg": "eng", "er": "er", "ew": "ei", "ef": "en",
    "oo": "o", "ou": "ou", "oz": "ou",
}


@dataclass(frozen=True)
class Token:
    text: str
    raw: str
    kind: str          # complete | partial | invalid
    end: int
    locked_syllable: str | None = None


class Segmenter:
    def __init__(self, syllables: set[str]):
        self.syllables = syllables | set(SYLLABLE_ALIASES)
        self.prefixes = {s[:i] for s in self.syllables for i in range(1, len(s) + 1)}

        self.t9_to_syllables: dict[str, list[str]] = {}
        self.t9_prefixes: set[str] = set()
        self.syl_to_t9: dict[str, str] = {}
        for s in sorted(self.syllables):
            if s in CONSONANT_SYLLABLES:
                continue
            code = s.translate(T9_MAP)
            self.syl_to_t9[s] = code
            self.t9_to_syllables.setdefault(code, []).append(s)
            for i in range(1, len(code) + 1):
                self.t9_prefixes.add(code[:i])

        self.xiaohe_pairs: dict[str, list[str]] = {}
        for k, v in XIAOHE_ZERO.items():
            self.xiaohe_pairs.setdefault(k, []).append(v)
        for syl in sorted(syllables):
            if syl in CONSONANT_SYLLABLES or syl in {"a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "er", "o", "ou"}:
                continue
            if syl.startswith("zh"):
                ini, fin = "v", syl[2:]
            elif syl.startswith("ch"):
                ini, fin = "i", syl[2:]
            elif syl.startswith("sh"):
                ini, fin = "u", syl[2:]
            else:
                ini, fin = syl[0], syl[1:]
            fc = XIAOHE_FINALS.get(fin)
            if fc:
                lst = self.xiaohe_pairs.setdefault(ini + fc, [])
                if syl not in lst:
                    lst.append(syl)

    def _classify(self, t: str, at_end: bool) -> tuple[float, str] | None:
        if t in self.syllables and t not in CONSONANT_SYLLABLES:
            return COST_COMPLETE, "complete"
        if t in self.prefixes:
            return (COST_PARTIAL_END if at_end else COST_PARTIAL_MID), "partial"
        return None

    def segmentations(self, raw: str, scheme: str = "quanpin") -> list[list[Token]]:
        if scheme == "xiaohe":
            return self._segment_xiaohe(raw.lower())
        results: list[list[Token]] = [[]]
        offset = 0
        for chunk in raw.lower().split("'"):
            if chunk:
                alts = self._segment_chunk(chunk, offset)
                results = [r + a for r in results for a in alts][:MAX_SEGMENTATIONS]
            offset += len(chunk) + 1
        return results if results[0] else []

    def _segment_xiaohe(self, raw: str) -> list[list[Token]]:
        paths: list[list[Token]] = [[]]
        i = 0
        n = len(raw)
        while i + 1 < n:
            pair = raw[i:i + 2]
            matches = self.xiaohe_pairs.get(pair)
            if matches:
                paths = [p + [Token(s, pair, "complete", i + 2)] for p in paths for s in matches][:MAX_SEGMENTATIONS]
            else:
                paths = [p + [Token(pair, pair, "invalid", i + 2)] for p in paths]
            i += 2
        if i < n:
            ch = raw[i]
            ini = {"v": "zh", "i": "ch", "u": "sh"}.get(ch, ch)
            paths = [p + [Token(ini, ch, "partial", n)] for p in paths]
        return paths

    def _segment_chunk(self, s: str, base: int) -> list[list[Token]]:
        n = len(s)
        INF = float("inf")
        cost = [INF] * (n + 1)
        preds: list[list[tuple[int, str]]] = [[] for _ in range(n + 1)]
        cost[0] = 0.0
        for i in range(n):
            if cost[i] == INF:
                continue
            for j in range(i + 1, min(n, i + MAX_SYLLABLE_LEN) + 1):
                cls = self._classify(s[i:j], j == n)
                if cls is None:
                    continue
                c = cost[i] + cls[0]
                if c < cost[j] - 1e-9:
                    cost[j], preds[j] = c, [(i, cls[1])]
                elif abs(c - cost[j]) <= 1e-9:
                    preds[j].append((i, cls[1]))
            c = cost[i] + COST_INVALID
            if c < cost[i + 1] - 1e-9:
                cost[i + 1], preds[i + 1] = c, [(i, "invalid")]

        out: list[list[Token]] = []

        def walk(j: int, tail: list[Token]) -> None:
            if len(out) >= MAX_SEGMENTATIONS:
                return
            if j == 0:
                out.append(list(reversed(tail)))
                return
            for i, kind in sorted(preds[j]):
                t = s[i:j]
                walk(i, tail + [Token(SYLLABLE_ALIASES.get(t, t), t, kind, base + j)])

        walk(n, [])

        # 单音节歧义补充切分：如 xian -> [xian] 外额外补充 [xi, an]，让「西安」无需手动加隔音符也能进 Top-5
        if len(out) < MAX_SEGMENTATIONS and len(out) >= 1 and len(out[0]) == 1 and out[0][0].kind == "complete" and n >= 3:
            for k in range(1, n):
                left, right = s[:k], s[k:]
                if (left in self.syllables and left not in CONSONANT_SYLLABLES and
                        right in self.syllables and right not in CONSONANT_SYLLABLES):
                    alt = [
                        Token(SYLLABLE_ALIASES.get(left, left), left, "complete", base + k),
                        Token(SYLLABLE_ALIASES.get(right, right), right, "complete", base + n),
                    ]
                    if alt not in out:
                        out.append(alt)
                        if len(out) >= MAX_SEGMENTATIONS:
                            break

        # 含 zh/ch/sh 的简拼补充纯单字母切分：如 gzh -> [g, zh] 外补充 [g, z, h] 让「公众号」进候选
        if (len(out) < MAX_SEGMENTATIONS and 2 <= n <= MAX_PHRASE_LEN
                and any(dg in s for dg in ("zh", "ch", "sh"))
                and not (out and all(t.kind == "complete" for t in out[0]))
                and all(ch in self.prefixes for ch in s)):
            single_init = [Token(ch, ch, "partial", base + idx + 1) for idx, ch in enumerate(s)]
            if single_init not in out:
                out.append(single_init)
        return out

    def t9_segmentations(self, digits: str, locked_prefixes: list[str] | None = None) -> list[list[Token]]:
        locked = locked_prefixes or []
        base_tokens: list[Token] = []
        pos = 0
        for syl in locked:
            code = syl.translate(T9_MAP)
            if digits[pos:pos + len(code)] != code:
                break
            pos += len(code)
            base_tokens.append(Token(code, code, "complete", pos, locked_syllable=syl))

        rem = digits[pos:]
        if not rem:
            return [base_tokens] if base_tokens else []

        n = len(rem)
        paths: list[list[tuple[float, list[Token]]]] = [[] for _ in range(n + 1)]
        paths[0] = [(0.0, [])]

        for i in range(n):
            if not paths[i]:
                continue
            for j in range(i + 1, min(n, i + MAX_SYLLABLE_LEN) + 1):
                sub = rem[i:j]
                if sub in self.t9_to_syllables:
                    step_c, kind = 1.0, "complete"
                elif sub in self.t9_prefixes:
                    step_c, kind = (1.35 if j == n else 1.85), "partial"
                else:
                    continue
                tok = Token(sub, sub, kind, pos + j)
                for prev_c, prev_toks in paths[i]:
                    paths[j].append((prev_c + step_c, prev_toks + [tok]))
            if paths[j := i + 1] == []:
                tok = Token(rem[i:j], rem[i:j], "invalid", pos + j)
                for prev_c, prev_toks in paths[i]:
                    paths[j].append((prev_c + 5.0, prev_toks + [tok]))

            for target in range(i + 1, min(n, i + MAX_SYLLABLE_LEN) + 1):
                if len(paths[target]) > 6:
                    paths[target].sort(key=lambda x: (x[0], len(x[1])))
                    paths[target] = paths[target][:4]

        paths[n].sort(key=lambda x: (x[0], len(x[1])))
        return [base_tokens + p for (_, p) in paths[n][:MAX_SEGMENTATIONS]]


@dataclass
class Candidate:
    word: str
    lp: float
    consumed: int
    exact: bool
    source: str = "dict"
    hint: str = ""


class Engine:
    def __init__(self, db_path: Path):
        self.con = sqlite3.connect(f"file:{db_path}?immutable=1", uri=True)
        syllables = {py for (py,) in self.con.execute("SELECT DISTINCT py FROM dict WHERE py NOT LIKE '%''%'")}
        self.segmenter = Segmenter(syllables)
        global MAX_PHRASE_LEN
        MAX_PHRASE_LEN = int(self.con.execute("SELECT value FROM meta WHERE key = 'max_len'").fetchone()[0])
        self.cache: dict[tuple, list[tuple[str, float, bool]]] = {}
        self.bigram_cache: dict[str, dict[str, float]] = {}

    def bigrams_for(self, prev_word: str) -> dict[str, float]:
        if not prev_word:
            return {}
        hit = self.bigram_cache.get(prev_word)
        if hit is None:
            hit = {n: b for (n, b) in self.con.execute("SELECT next, bonus FROM sys_bigrams WHERE prev = ?", (prev_word,))}
            self.bigram_cache[prev_word] = hit
        return hit

    def context_bonus_map(self, context: str | None) -> dict[str, float]:
        if not context:
            return {}
        tail = "".join(ch for ch in context[-8:] if "\u4e00" <= ch <= "\u9fff")
        if not tail:
            return {}
        merged: dict[str, float] = {}
        for L in range(min(4, len(tail)), 0, -1):
            sub = tail[-L:]
            for next_w, b in self.bigrams_for(sub).items():
                # 越长的匹配上文权重略高
                weighted = b * (1.0 + 0.15 * (L - 1))
                if weighted > merged.get(next_w, 0.0):
                    merged[next_w] = weighted
        return merged

    def merged_pair_bonus(self, context: str | None, word: str) -> float:
        """WowType MERGED_PAIR_SCORE：上文末尾 1~2 字与候选连起来本身是常用词（如 我+要=我要, 不+会=不会）时保底奖励。"""
        if not context or not word or len(word) > 3:
            return 0.0
        tail = "".join(ch for ch in context[-2:] if "\u4e00" <= ch <= "\u9fff")
        if not tail:
            return 0.0
        for L in range(min(2, len(tail)), 0, -1):
            combined = tail[-L:] + word
            row = self.con.execute("SELECT lp FROM glide_dict WHERE word = ? ORDER BY lp DESC LIMIT 1", (combined,)).fetchone()
            if row and row[0] > -13.0:
                return MERGED_PAIR_SCORE
        return 0.0

    def exact_english(self, raw: str) -> str | None:
        lower = raw.lower()
        if not lower.isascii() or not lower.isalpha():
            return None
        row = self.con.execute("SELECT word FROM en_dict WHERE lower = ?", (lower,)).fetchone()
        return row[0] if row else None

    @staticmethod
    def _match_26(token: Token, syllable: str, allow_prefix: bool) -> tuple[bool, bool]:
        if token.kind == "invalid":
            return False, False
        if syllable == token.text:
            return True, True
        if (token.kind == "partial" or allow_prefix) and syllable.startswith(token.text):
            return True, token.kind == "partial"
        return False, False

    def _match_t9(self, token: Token, syllable: str, allow_prefix: bool) -> tuple[bool, bool]:
        if token.kind == "invalid":
            return False, False
        if token.locked_syllable:
            return (syllable == token.locked_syllable), (syllable == token.locked_syllable)
        syl_t9 = self.segmenter.syl_to_t9.get(syllable) or syllable.translate(T9_MAP)
        if syl_t9 == token.text:
            return True, True
        if (token.kind == "partial" or allow_prefix) and syl_t9.startswith(token.text):
            return True, token.kind == "partial"
        return False, False

    def lookup(self, tokens: list[Token], i: int, j: int, open_end: bool, is_t9: bool = False) -> list[Candidate]:
        span = tokens[i:j]
        if any(t.kind == "invalid" for t in span):
            return []
        key = (is_t9, tuple((t.text, t.kind, t.locked_syllable) for t in span), open_end)
        cached = self.cache.get(key)
        if cached is None:
            if is_t9:
                abbr = "".join((t.locked_syllable.translate(T9_MAP)[0] if t.locked_syllable else t.text[0]) for t in span)
                sql = "SELECT word, py, lp FROM dict WHERE t9_abbr = ? ORDER BY lp DESC LIMIT 2500"
            else:
                abbr = "".join(t.text[0] for t in span)
                sql = "SELECT word, py, lp FROM dict WHERE abbr = ? ORDER BY lp DESC LIMIT 2500"

            exact, extended = [], []
            for word, py, lp in self.con.execute(sql, (abbr,)):
                sy = py.split("'")
                if len(sy) != len(span):
                    continue
                all_exact, ok = True, True
                comp_penalty = 0.0
                for k, (t, s) in enumerate(zip(span, sy)):
                    m, e = (self._match_t9 if is_t9 else self._match_26)(t, s, open_end and k == len(span) - 1)
                    if not m:
                        ok = False
                        break
                    all_exact &= e
                    # WowType 补全长度惩罚：多字母残缺音节（如 weish 中的 sh）按缺失字母数扣分，让「为啥」(-1.2) 胜过「卫生」(-3.6)
                    if not is_t9 and t.kind == "partial" and len(t.text) >= 2 and len(s) > len(t.text):
                        comp_penalty += PARTIAL_COMPLETION_PENALTY * (len(s) - len(t.text))
                if ok:
                    adj_lp = lp - comp_penalty
                    (exact if all_exact else extended).append((word, adj_lp, all_exact))
            exact.sort(key=lambda x: -x[1])
            extended.sort(key=lambda x: -x[1])
            cached = exact + extended
            self.cache[key] = cached
        end = span[-1].end
        return [Candidate(w, lp, end, e) for (w, lp, e) in cached]

    def sentences_nbest(
        self,
        tokens: list[Token],
        is_t9: bool = False,
        context_map: dict[str, float] | None = None,
        max_alts: int = 2,
    ) -> list[Candidate]:
        n = len(tokens)
        BEAM = 3
        SPAN_TOP_K = 4
        ctx = context_map or {}
        allow_tail_ext = tokens[-1].kind == "partial"
        states: list[list[tuple[float, tuple[str, ...]]]] = [[] for _ in range(n + 1)]
        states[0] = [(0.0, ())]

        for j in range(1, n + 1):
            candidates_at_j: list[tuple[float, tuple[str, ...]]] = []
            for i in range(max(0, j - MAX_PHRASE_LEN), j):
                if not states[i]:
                    continue
                # 仅当末尾音节未打完（partial）时允许开放前缀补全，避免 zhongdi 被「重点」压过「种地」
                cands = self.lookup(tokens, i, j, open_end=(j == n and allow_tail_ext), is_t9=is_t9)
                if cands:
                    span_choices = [(c.word, c.lp - WORD_BOUNDARY_PENALTY) for c in cands[:SPAN_TOP_K]]
                elif j - i == 1 and tokens[i].kind == "invalid":
                    span_choices = [(tokens[i].raw, INVALID_LP)]
                else:
                    continue

                for prev_score, prev_words in states[i]:
                    prev_w = prev_words[-1] if prev_words else ""
                    bg = self.bigrams_for(prev_w)
                    for word, base_sc in span_choices:
                        ctx_b = (ctx.get(word, 0.0) * CONTEXT_BIGRAM_WEIGHT) if i == 0 else 0.0
                        sc = prev_score + base_sc + bg.get(word, 0.0) + ctx_b
                        candidates_at_j.append((sc, prev_words + (word,)))

            candidates_at_j.sort(key=lambda x: -x[0])
            kept: list[tuple[float, tuple[str, ...]]] = []
            seen_last: set[str] = set()
            for item in candidates_at_j:
                last_w = item[1][-1]
                if last_w not in seen_last:
                    seen_last.add(last_w)
                    kept.append(item)
                    if len(kept) >= BEAM:
                        break
            states[j] = kept

        return [Candidate("".join(words), sc, tokens[-1].end, False) for (sc, words) in states[n][:max_alts]]

    def _run_segs(
        self,
        segs: list[list[Token]],
        is_t9: bool = False,
        context_map: dict[str, float] | None = None,
        limit: int = 30,
    ) -> tuple[list[Token], list[Candidate]]:
        if not segs:
            return [], []
        ctx = context_map or {}
        sentences: list[Candidate] = []
        exact_full: list[Candidate] = []
        extended_full: list[Candidate] = []
        best_seg, best_score = segs[0], -math.inf

        for tokens in segs:
            n = len(tokens)
            full = self.lookup(tokens, 0, n, open_end=True, is_t9=is_t9) if n <= MAX_PHRASE_LEN else []
            sents = self.sentences_nbest(tokens, is_t9=is_t9, context_map=ctx) if n > 1 else []
            sentences.extend(sents)
            for c in full:
                bonus = ctx.get(c.word, 0.0) * CONTEXT_BIGRAM_WEIGHT
                adjusted = Candidate(c.word, c.lp + bonus, c.consumed, c.exact) if bonus > 0 else c
                (exact_full if c.exact else extended_full).append(adjusted)
            full_top = max((c.lp + ctx.get(c.word, 0.0) * CONTEXT_BIGRAM_WEIGHT for c in full if c.exact), default=-math.inf)
            sent_top = sents[0].lp if sents else -math.inf
            score = max(full_top - WORD_BOUNDARY_PENALTY, sent_top)
            if score > best_score:
                best_seg, best_score = tokens, score

        sentences.sort(key=lambda c: -c.lp)
        exact_full.sort(key=lambda c: -c.lp)
        extended_full.sort(key=lambda c: -c.lp)

        out: list[Candidate] = []
        seen: set[str] = set()

        def add(c: Candidate) -> None:
            if c.word not in seen:
                seen.add(c.word)
                out.append(c)

        unique_sents: list[Candidate] = []
        seen_s = set()
        for s in sentences:
            if s.word not in seen_s:
                seen_s.add(s.word)
                unique_sents.append(s)
        kept_sentences: list[Candidate] = []
        if unique_sents:
            kept_sentences.append(unique_sents[0])
            if len(unique_sents) > 1 and unique_sents[1].lp >= unique_sents[0].lp - 1.5:
                kept_sentences.append(unique_sents[1])

        # WowType protect_exact_input：整输入正好是一个实在的精确词时，保护它排在第 1 位（不被单字拼凑或补全抢走）
        all_complete = all(t.kind == "complete" for t in best_seg)
        protect_exact = bool(exact_full) and (all_complete or len(best_seg) == 1) and exact_full[0].lp > -17.0
        if protect_exact:
            for c in exact_full:
                add(c)
            for c in kept_sentences:
                add(c)
        else:
            if kept_sentences and (not exact_full or kept_sentences[0].lp > exact_full[0].lp - WORD_BOUNDARY_PENALTY + 1e-9):
                add(kept_sentences[0])
            for c in exact_full:
                add(c)
            for c in kept_sentences:
                add(c)

        # 单音节歧义词保护（如 xian -> 先/现/显/西安）：把双音节高权重精确词放入 Top-4
        if len(best_seg) == 1 and len(segs) > 1:
            multi_exact = [c for c in exact_full if len(c.word) >= 2 and c.lp > -13.5]
            if multi_exact and multi_exact[0].word not in {c.word for c in out[:4]}:
                out = [c for c in out if c.word != multi_exact[0].word]
                out.insert(min(3, len(out)), multi_exact[0])

        for c in extended_full:
            add(c)

        n = len(best_seg)
        for k in range(min(n - 1, MAX_PHRASE_LEN), 0, -1):
            for c in self.lookup(best_seg, 0, k, open_end=False, is_t9=is_t9):
                add(c)
        return best_seg, out[:limit]

    def candidates(
        self,
        raw: str,
        scheme: str = "quanpin",
        context: str | None = None,
        limit: int = 30,
    ) -> tuple[list[Token], list[Candidate], str | None]:
        lower = raw.lower()
        ctx_map = self.context_bonus_map(context)
        segs = self.segmenter.segmentations(lower, scheme=scheme)
        best_seg, out = self._run_segs(segs, is_t9=False, context_map=ctx_map, limit=limit)

        has_invalid = any(t.kind == "invalid" for t in best_seg)
        all_initials = bool(best_seg) and all(len(t.raw) == 1 for t in best_seg)
        all_complete = bool(best_seg) and all(t.kind == "complete" for t in best_seg)
        has_awkward_partial = (len(best_seg) >= 2 and not all_initials and any(t.kind == "partial" for t in best_seg))
        corrected_hint = None

        # 1. 儿化音（wanr -> wan'er 玩儿, zher -> zhe'er 这儿, yidianr -> 一点儿, haowanr -> 好玩儿）
        if scheme == "quanpin" and len(lower) >= 3 and lower.endswith("r") and not all_complete and "'" not in lower:
            er_segs = self.segmenter.segmentations(lower[:-1] + "'er", scheme="quanpin")
            valid_er = [s for s in er_segs if all(t.kind == "complete" for t in s)]
            if valid_er:
                _, er_out = self._run_segs(valid_er, is_t9=False, context_map=ctx_map, limit=8)
                er_hits = [Candidate(c.word, c.lp, len(lower), True) for c in er_out if c.word.endswith("儿")]
                if er_hits:
                    er_words = {c.word for c in er_hits}
                    out = er_hits + [c for c in out if c.word not in er_words]

        # 2. 英文原词精确排位：非合法全拼（github/wechat/iphone/deepseek）直接排第 1，跳过无谓纠错
        exact_en = self.exact_english(lower) if scheme == "quanpin" else None
        if exact_en and not all_complete and not (all_initials and out and out[0].exact and out[0].lp > -11.5):
            en_cand = Candidate(exact_en, 5.0, len(raw), True, source="en")
            out = [en_cand] + [c for c in out if c.word != exact_en]
            return best_seg, out[:limit], None

        # 3. 4 路智能容错（仅全拼；额外支持换位/鼻音前后鼻容错与合法全拼邻键高频词如 tianqu -> 天气）
        if scheme == "quanpin" and "'" not in lower and 3 <= len(lower) <= 18 and not lower.startswith("v"):
            chars = list(lower)
            variants = []
            if has_invalid or has_awkward_partial:
                for idx in range(len(chars) - 1):
                    if chars[idx] != chars[idx + 1]:
                        sw = chars[:]
                        sw[idx], sw[idx + 1] = sw[idx + 1], sw[idx]
                        variants.append("".join(sw))
                if len(chars) >= 4:
                    for idx in range(len(chars)):
                        variants.append("".join(chars[:idx] + chars[idx + 1:]))
                suspect_positions = set()
                for t in best_seg:
                    if t.kind == "invalid" or (t.kind == "partial" and len(t.raw) == 1):
                        p = t.end - 1
                        suspect_positions.update({max(0, p - 1), p, min(len(chars) - 1, p + 1)})
                for pos in suspect_positions:
                    for rep in ADJACENT_KEYS.get(chars[pos], ""):
                        sub = chars[:]
                        sub[pos] = rep
                        variants.append("".join(sub))

                best_fix_cands: list[Candidate] = []
                best_fix_score = -math.inf
                best_fix_seg: list[Token] = []

                def eval_variants(var_list):
                    nonlocal best_fix_cands, best_fix_score, best_fix_seg
                    for v in dict.fromkeys(var_list):
                        v_segs = self.segmenter.segmentations(v)
                        valid_segs = [s for s in v_segs if all(t.kind == "complete" for t in s)]
                        if not valid_segs:
                            continue
                        v_seg, v_out = self._run_segs(valid_segs, is_t9=False, context_map=ctx_map, limit=6)
                        if v_out and len(v_out[0].word) >= 2 and v_out[0].lp > best_fix_score:
                            best_fix_score = v_out[0].lp
                            best_fix_cands = v_out
                            best_fix_seg = v_seg

                eval_variants(variants)
                if not best_fix_cands and len(chars) >= 4:
                    vowel_vars = []
                    for pos in (suspect_positions or {1, 2, len(chars) - 2}):
                        for ins_pos in (pos, pos + 1):
                            if 0 < ins_pos < len(chars):
                                for vch in "aeiou":
                                    vowel_vars.append("".join(chars[:ins_pos] + [vch] + chars[ins_pos:]))
                    eval_variants(vowel_vars)

                raw_top_lp = out[0].lp if out else -math.inf
                # 若输入仅含合法混简拼（无 invalid），需命中高频词 (> -11.5) 才覆盖，避免「拥吻」覆盖「用中文」
                allow_promote = bool(best_fix_cands) and (
                    has_invalid or (best_fix_score > -11.5 and best_fix_score - 3.8 > raw_top_lp)
                )
                if allow_promote:
                    corrected_hint = "'".join(t.text for t in best_fix_seg)
                    promoted = [Candidate(c.word, c.lp, len(raw), False) for c in best_fix_cands[:3]]
                    promoted_words = {c.word for c in promoted}
                    out = promoted + [c for c in out if c.word not in promoted_words]
            elif all_complete and len(best_seg) >= 2 and (not out or not out[0].exact or out[0].lp < -11.5):
                # 合法全拼但本身无精确整词或极低频（如 meiyuo、shengme、penyou、tianqu）
                raw_is_exact = bool(out and out[0].exact)
                raw_top = out[0].lp if out else -20.0
                # 3a. 换位（meiyuo->meiyou）+ WowType fuzzy_fallback（前后鼻音 an/ang, en/eng, in/ing 与平翘舌 zh/z, ch/c, sh/s 兜底，如 shengme->什么, penyou->朋友, yingai->应该, zidao->知道）
                strong_vars: list[str] = []
                for idx in range(len(chars) - 1):
                    if chars[idx] != chars[idx + 1]:
                        sw = chars[:]
                        sw[idx], sw[idx + 1] = sw[idx + 1], sw[idx]
                        strong_vars.append("".join(sw))
                for idx in range(len(chars) - 1):
                    if chars[idx] in "aei" and chars[idx + 1] == "n":
                        if idx + 2 < len(chars) and chars[idx + 2] == "g":
                            strong_vars.append("".join(chars[:idx + 2] + chars[idx + 3:]))
                        else:
                            strong_vars.append("".join(chars[:idx + 2] + ["g"] + chars[idx + 2:]))
                syl_texts = [t.text for t in best_seg]
                for s_idx, st in enumerate(syl_texts):
                    alts = []
                    for dg, sg in (("zh", "z"), ("ch", "c"), ("sh", "s")):
                        if st.startswith(dg):
                            alts.append(sg + st[2:])
                        elif st.startswith(sg) and not st.startswith(dg):
                            alts.append(dg + st[1:])
                    for fin_a, fin_b in (("ang", "an"), ("eng", "en"), ("ing", "in")):
                        if st.endswith(fin_a):
                            alts.append(st[:-3] + fin_b)
                        elif st.endswith(fin_b):
                            alts.append(st[:-2] + fin_a)
                    for alt in alts:
                        rep_syls = syl_texts[:]
                        rep_syls[s_idx] = alt
                        strong_vars.append("".join(rep_syls))
                best_strong: tuple[Candidate, list[Token]] | None = None
                for v in dict.fromkeys(strong_vars):
                    v_segs = [s for s in self.segmenter.segmentations(v) if all(t.kind == "complete" for t in s)]
                    if not v_segs:
                        continue
                    v_seg, v_out = self._run_segs(v_segs, is_t9=False, context_map=ctx_map, limit=2)
                    if v_out and v_out[0].exact and len(v_out[0].word) >= 2 and v_out[0].lp > -11.0:
                        if (not raw_is_exact) or (v_out[0].lp > raw_top + 3.5):
                            if best_strong is None or v_out[0].lp > best_strong[0].lp:
                                best_strong = (Candidate(v_out[0].word, v_out[0].lp, len(raw), False), v_seg)
                if best_strong is not None:
                    cand, v_seg = best_strong
                    corrected_hint = "'".join(t.text for t in v_seg)
                    out = [cand] + [c for c in out if c.word != cand.word]
                elif len(best_seg) == 2:
                    # 3b. 末位邻键高频词放第 2 位（tianqu -> [天区, 天气]，不抢 #1 精确词）
                    best_adj: Candidate | None = None
                    for pos in (len(chars) - 1, len(chars) - 2):
                        for rep in ADJACENT_KEYS.get(chars[pos], ""):
                            sub = chars[:]
                            sub[pos] = rep
                            v_segs = [s for s in self.segmenter.segmentations("".join(sub)) if all(t.kind == "complete" for t in s)]
                            if not v_segs:
                                continue
                            _, v_out = self._run_segs(v_segs, is_t9=False, context_map=ctx_map, limit=2)
                            if v_out and v_out[0].exact and len(v_out[0].word) >= 2 and v_out[0].lp > raw_top + 2.5:
                                if best_adj is None or v_out[0].lp > best_adj.lp:
                                    best_adj = Candidate(v_out[0].word, v_out[0].lp, len(raw), False)
                    if best_adj and best_adj.word not in {c.word for c in out[:2]}:
                        out.insert(min(1, len(out)), best_adj)

        # 4. 合法全拼同时又是英文词（like / danger）排第 6 位（前 5 位留给中文）
        if exact_en and all_complete:
            en_cand = Candidate(exact_en, -20.0, len(raw), False, source="en")
            out = [c for c in out if c.word != exact_en]
            out.insert(min(5, len(out)), en_cand)

        return best_seg, out[:limit], corrected_hint

    def wubi_candidates(self, code: str, limit: int = 24) -> list[Candidate]:
        lower = code.lower()
        if not lower or len(lower) > 4 or any(ch not in "abcdefghijklmnopqrstuvwxy" for ch in lower):
            return []
        exact = [
            Candidate(w, 0.0, len(lower), True, source="wubi", hint="")
            for (w,) in self.con.execute(
                "SELECT word FROM wubi WHERE code = ? ORDER BY weight DESC, ord ASC LIMIT ?",
                (lower, limit),
            )
        ]
        seen = {c.word for c in exact}
        out = list(exact)
        if len(lower) < 4 and len(out) < limit:
            upper = lower[:-1] + chr(ord(lower[-1]) + 1)
            for w, full_code in self.con.execute(
                "SELECT word, code FROM wubi WHERE code > ? AND code < ? ORDER BY weight DESC, ord ASC LIMIT ?",
                (lower, upper, limit * 2),
            ):
                if w not in seen:
                    seen.add(w)
                    out.append(Candidate(w, -1.0, len(lower), False, source="wubi", hint=full_code[len(lower):]))
                    if len(out) >= limit:
                        break
        return out

    def wubi_reverse_hint(self, word: str) -> str:
        codes = [r[0] for r in self.con.execute("SELECT code FROM wubi WHERE word = ? ORDER BY length(code) ASC, ord ASC LIMIT 6", (word,))]
        if not codes:
            return ""
        return codes[0] if codes[0] == codes[-1] else f"{codes[0]}/{codes[-1]}"

    def u_candidates(self, body: str, limit: int = 24) -> list[Candidate]:
        """U 模式：部件拆字反查（ushuishuishui->淼 miao, ufangfangtu->堃 kun）+ 五笔画反查（uhspn->木 mu）。"""
        lower = body.lower().replace("'", "")
        if not lower or not lower.isalpha():
            return []
        out: list[Candidate] = []
        seen: set[str] = set()
        upper = lower[:-1] + chr(ord(lower[-1]) + 1)

        # 1. 拆字精确 + 前缀匹配
        for w, py, _wt in self.con.execute(
            "SELECT word, py, weight FROM chaizi WHERE code = ? ORDER BY weight DESC LIMIT ?",
            (lower, limit),
        ):
            if w not in seen:
                seen.add(w)
                out.append(Candidate(w, 0.0, len(lower) + 1, True, source="u_chaizi", hint=py))

        # 2. 五笔画精确匹配（h横 s竖 p撇 n/d捺点 z折）
        stroke_q = lower.replace("d", "n")
        if set(stroke_q) <= set("hspnz"):
            for w, py, _wt in self.con.execute(
                "SELECT word, py, weight FROM strokes WHERE code = ? ORDER BY weight DESC LIMIT ?",
                (stroke_q, limit),
            ):
                if w not in seen:
                    seen.add(w)
                    out.append(Candidate(w, -0.2, len(lower) + 1, True, source="u_stroke", hint=py))

        # 3. 拆字前缀补全
        if len(out) < limit:
            for w, py, _code in self.con.execute(
                "SELECT word, py, code FROM chaizi WHERE code > ? AND code < ? ORDER BY length(code) ASC, weight DESC LIMIT ?",
                (lower, upper, limit * 2),
            ):
                if w not in seen:
                    seen.add(w)
                    out.append(Candidate(w, -1.0, len(lower) + 1, False, source="u_chaizi", hint=py))
                    if len(out) >= limit:
                        break

        # 4. 五笔画前缀补全
        if set(stroke_q) <= set("hspnz") and len(out) < limit:
            s_upper = stroke_q[:-1] + chr(ord(stroke_q[-1]) + 1)
            for w, py, _code in self.con.execute(
                "SELECT word, py, code FROM strokes WHERE code > ? AND code < ? ORDER BY length(code) ASC, weight DESC LIMIT ?",
                (stroke_q, s_upper, limit * 2),
            ):
                if w not in seen:
                    seen.add(w)
                    out.append(Candidate(w, -1.5, len(lower) + 1, False, source="u_stroke", hint=py))
                    if len(out) >= limit:
                        break
        return out[:limit]

    @staticmethod
    def _resample_polyline(pts: list[tuple[float, float]], n: int = 24) -> tuple[list[tuple[float, float]], float]:
        if not pts:
            return [(0.0, 0.0)] * n, 0.0
        clean = [pts[0]]
        for p in pts[1:]:
            if math.hypot(p[0] - clean[-1][0], p[1] - clean[-1][1]) > 1e-4:
                clean.append(p)
        if len(clean) == 1:
            return [clean[0]] * n, 0.0
        cum = [0.0]
        for i in range(1, len(clean)):
            cum.append(cum[-1] + math.hypot(clean[i][0] - clean[i - 1][0], clean[i][1] - clean[i - 1][1]))
        total = cum[-1]
        if total < 1e-4:
            return [clean[0]] * n, 0.0
        out = []
        seg_idx = 0
        for k in range(n):
            target = (total * k) / (n - 1)
            while seg_idx + 1 < len(cum) - 1 and cum[seg_idx + 1] < target:
                seg_idx += 1
            seg_len = max(1e-6, cum[seg_idx + 1] - cum[seg_idx])
            t = (target - cum[seg_idx]) / seg_len
            x = clean[seg_idx][0] + t * (clean[seg_idx + 1][0] - clean[seg_idx][0])
            y = clean[seg_idx][1] + t * (clean[seg_idx + 1][1] - clean[seg_idx][1])
            out.append((x, y))
        return out, total

    @classmethod
    def _word_key_polyline(cls, letters: str) -> list[tuple[float, float]]:
        dedup = []
        for ch in letters.lower():
            if ch in QWERTY_POS and (not dedup or dedup[-1] != ch):
                dedup.append(ch)
        return [QWERTY_POS[c] for c in dedup]

    def glide_candidates(self, points: list[tuple[float, float]], english: bool = False, limit: int = 10) -> list[Candidate]:
        """26 键滑行输入解码器（Shark2 / Gboard 几何轨迹重采样 + 语言模型联合打分）。"""
        if len(points) < 2:
            return []
        N = 24
        user_pts, user_len = self._resample_polyline(points, N)
        p_start, p_end = points[0], points[-1]

        start_keys = [
            k for k, pos in sorted(QWERTY_POS.items(), key=lambda kv: math.hypot(kv[1][0] - p_start[0], kv[1][1] - p_start[1]))
            if math.hypot(pos[0] - p_start[0], pos[1] - p_start[1]) <= 1.45
        ][:4]
        end_keys = [
            k for k, pos in sorted(QWERTY_POS.items(), key=lambda kv: math.hypot(kv[1][0] - p_end[0], kv[1][1] - p_end[1]))
            if math.hypot(pos[0] - p_end[0], pos[1] - p_end[1]) <= 1.45
        ][:4]
        if not start_keys or not end_keys:
            return []

        scored: list[tuple[float, str, str]] = []
        seen_words: set[str] = set()

        if english:
            q_marks = ",".join("?" for _ in start_keys)
            end_set = set(end_keys)
            rows = self.con.execute(
                f"SELECT lower, word, rank FROM en_dict WHERE substr(lower, 1, 1) IN ({q_marks}) ORDER BY rank DESC LIMIT 800",
                start_keys,
            ).fetchall()
            raw_pool = [(lower, lower, word, math.log(max(10, rank)) - 15.0) for lower, word, rank in rows if len(lower) >= 2 and lower[-1] in end_set]
        else:
            s_marks = ",".join("?" for _ in start_keys)
            e_marks = ",".join("?" for _ in end_keys)
            rows = self.con.execute(
                f"SELECT py_flat, py, word, lp FROM glide_dict WHERE first_c IN ({s_marks}) AND last_c IN ({e_marks}) ORDER BY lp DESC LIMIT 550",
                start_keys + end_keys,
            ).fetchall()
            raw_pool = rows

        for py_flat, py, word, lp in raw_pool:
            if word in seen_words:
                continue
            key_poly = self._word_key_polyline(py_flat)
            if len(key_poly) < 2:
                continue
            # 快速走廊过滤：每个转折键必须离轨迹足够近
            if any(min(math.hypot(kp[0] - up[0], kp[1] - up[1]) for up in user_pts) > 1.45 for kp in key_poly):
                continue
            tmpl_pts, tmpl_len = self._resample_polyline(key_poly, N)
            spatial = sum(math.hypot(u[0] - t[0], u[1] - t[1]) for u, t in zip(user_pts, tmpl_pts)) / N
            s_dist = math.hypot(p_start[0] - key_poly[0][0], p_start[1] - key_poly[0][1])
            e_dist = math.hypot(p_end[0] - key_poly[-1][0], p_end[1] - key_poly[-1][1])
            len_pen = abs(user_len - tmpl_len) / max(1.5, tmpl_len) * 0.45
            geo_cost = spatial * 4.2 + (s_dist + e_dist) * 1.5 + len_pen
            score = lp * 0.50 - geo_cost
            seen_words.add(word)
            scored.append((score, word, py))

        scored.sort(key=lambda x: -x[0])
        return [Candidate(w, sc, len(py), True, source="glide", hint=py) for sc, w, py in scored[:limit]]

    def t9_candidates(self, digits: str, locked: list[str] | None = None, limit: int = 30) -> tuple[list[Token], list[Candidate], list[str]]:
        segs = self.segmenter.t9_segmentations(digits, locked_prefixes=locked)
        best_seg, out = self._run_segs(segs, is_t9=True, limit=limit)
        left_syllables: list[str] = []
        pos = sum(len(s) for s in (locked or []))
        if pos < len(digits):
            rem = digits[pos:]
            for l in range(min(6, len(rem)), 0, -1):
                for syl in self.segmenter.t9_to_syllables.get(rem[:l], []):
                    if syl not in left_syllables:
                        left_syllables.append(syl)
        return best_seg, out, left_syllables


def run_wowtype_regress(eng: Engine) -> tuple[int, int]:
    if not REGRESS_TSV.exists():
        return 0, 0
    passed = 0
    total = 0
    print("\n=== WowType 官方 regress.tsv 回归集 ===")
    for line in REGRESS_TSV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        raw = parts[0]
        expects = parts[1].split("|")
        ctx = parts[2] if len(parts) > 2 else ""
        attr = parts[3] if len(parts) > 3 else ""

        scheme = "quanpin"
        top_n = 1
        exact_at = None
        before_single = False
        for tok in attr.split():
            if tok.startswith("top="):
                top_n = int(tok.split("=")[1])
            elif tok.startswith("at="):
                exact_at = int(tok.split("=")[1])
            elif tok == "before-single":
                before_single = True
            elif tok.startswith("sp="):
                scheme = tok.split("=")[1]

        eng.cache.clear()
        _, cands, _ = eng.candidates(raw, scheme=scheme, context=ctx or None, limit=20)
        words = [c.word for c in cands]

        if exact_at is not None:
            ok = len(words) >= exact_at and words[exact_at - 1] in expects
        elif before_single:
            first_single = next((i for i, w in enumerate(words) if len(w) == 1), len(words))
            ok = any(w in words[:first_single] for w in expects)
        else:
            ok = any(w in words[:top_n] for w in expects)

        total += 1
        passed += int(ok)
        if not ok:
            print(f"MISS {raw:18} ctx={ctx:4} attr={attr:13} expect={expects} got={words[:6]}")
    print(f"WowType regress.tsv: {passed}/{total} 通过")
    return passed, total


def main() -> int:
    if not DB.exists():
        print("请先运行 python Tools/build_dict.py", file=sys.stderr)
        return 1
    eng = Engine(DB)

    cases_26 = {
        "nihao": "你好",
        "woaini": "我爱你",
        "zhongguo": "中国",
        "xianzai": "现在",
        "xi'an": "西安",
        "nh": "你好",
        "zhhrmghg": "中华人民共和国",
        "jintiantianqizhenhao": "今天天气真好",
        "shurufa": "输入法",
        "fangan": "方案",
        "nihaoma": "你好吗",
        "lve": "略",
        "weixin": "微信",
        "zhifubao": "支付宝",
        "dagongren": "打工人",
        "womenyiqiqu": "我们一起去",
        "zhon": "中",
        "shekong": "社恐",
        "tangping": "躺平",
        "juejuezi": "绝绝子",
        "rengongzhineng": "人工智能",
        # 错拼容错测试
        "nihoa": "你好",
        "niihao": "你好",
        "zhkngguo": "中国",
        "zhngguo": "中国",
        "shurfa": "输入法",
        "weixni": "微信",
        "jintain": "今天",
        "zhognguo": "中国",
        "buhap": "不好",
        "woquchifan": "我去吃饭",
        "xiabanhouchihuoguo": "下班后吃火锅",
        "bangwokanyixia": "帮我看一下",
        "mingtianwanshang": "明天晚上",
        "zhegefangfa": "这个方法",
        # WowType 特色：精确保护、全拼混简拼、儿化音、中英直出
        "zhongdi": "种地",
        "beiji": "北极",
        "ka": "卡",
        "wanr": "玩儿",
        "zher": "这儿",
        "yidianr": "一点儿",
        "haowanr": "好玩儿",
        "kyi": "可以",
        "wanqky": "完全可以",
        "yongzwen": "用中文",
        "zhchi": "支持",
        "weish": "为啥",
        "zaijianl": "再见了",
        "github": "GitHub",
        "wechat": "WeChat",
        "deepseek": "DeepSeek",
        "heishenhua": "黑神话",
        "yingai": "应该",
        "zidao": "知道",
    }

    cases_t9 = {
        "64426": "你好",
        "962464": "我爱你",
        "94664486": "中国",
        "54684268426749436426": "今天天气真好",
        "7487832": "输入法",
        "326426": "方案",
        "934946": "微信",
    }

    failed = 0
    print("=== 26键全拼 + 纠错 + 混简拼 + 儿化 + 英文直出测试 ===")
    for raw, expect in cases_26.items():
        t0 = time.perf_counter()
        eng.cache.clear()
        tokens, cands, hint = eng.candidates(raw)
        dt = (time.perf_counter() - t0) * 1000
        top = [c.word for c in cands[:5]]
        ok = (expect == top[0]) if raw in {"zhongdi", "beiji", "ka", "github", "wechat", "deepseek", "wanr", "zher", "heishenhua"} else (expect in top[:3])
        failed += not ok
        hint_s = f" (纠错:{hint})" if hint else ""
        print(f"{'OK ' if ok else 'BAD'} {raw:22} {dt:5.1f}ms -> {' '.join(top)}{hint_s}")

    print("\n=== T9 九宫格测试 ===")
    for digits, expect in cases_t9.items():
        t0 = time.perf_counter()
        eng.cache.clear()
        tokens, cands, syls = eng.t9_candidates(digits)
        dt = (time.perf_counter() - t0) * 1000
        top = [c.word for c in cands[:5]]
        ok = expect in top[:3]
        failed += not ok
        print(f"{'OK ' if ok else 'BAD'} {digits:20} {dt:5.1f}ms -> {' '.join(top)}  [音节:{'/'.join(syls[:4])}]")

    print("\n=== 五笔 86 与 z 临时拼音反查测试 ===")
    wb_wq = eng.wubi_candidates("wq", limit=5)
    wb_ok1 = bool(wb_wq) and wb_wq[0].word == "你"
    wb_rev = eng.wubi_reverse_hint("工")
    wb_ok2 = wb_rev == "a/aaaa"
    failed += (not wb_ok1) + (not wb_ok2)
    print(f"{'OK ' if wb_ok1 else 'BAD'} wubi wq -> {[(c.word, c.hint) for c in wb_wq]}")
    print(f"{'OK ' if wb_ok2 else 'BAD'} wubi reverse '工' -> {wb_rev}")

    print("\n=== U 模式：部件拆字 (radical_pinyin) + 五笔画 (stroke) 反查测试 ===")
    u_cases = {
        "shuishuishui": "淼",
        "niuniuniu": "犇",
        "jinjinjin": "鑫",
        "huohuohuo": "焱",
        "fangfangtu": "堃",
        "tututu": "垚",
        "shishishi": "磊",
        "mamama": "骉",
        "longlonglong": "龘",
        "riyue": "明",
        "nvzi": "好",
        "koukoukou": "品",
        "mumumu": "森",
        "hspn": "木",
    }
    for u_code, u_exp in u_cases.items():
        u_hits = eng.u_candidates(u_code, limit=5)
        u_top = [c.word for c in u_hits[:3]]
        u_ok = u_exp in u_top
        failed += not u_ok
        print(f"{'OK ' if u_ok else 'BAD'} u+{u_code:14} -> {[(c.word, c.hint) for c in u_hits[:3]]}")

    print("\n=== 26 键滑行输入 (Glide Typing) 轨迹解码测试 ===")
    def synth_swipe(letters: str, jitter: float = 0.08) -> list[tuple[float, float]]:
        poly = Engine._word_key_polyline(letters)
        pts: list[tuple[float, float]] = []
        for i in range(len(poly) - 1):
            ax, ay = poly[i]
            bx, by = poly[i + 1]
            steps = 6
            for s in range(steps):
                t = s / steps
                jx = jitter * math.sin((i * 7 + s) * 1.3)
                jy = jitter * math.cos((i * 5 + s) * 1.7)
                pts.append((ax + (bx - ax) * t + jx, ay + (by - ay) * t + jy))
        pts.append(poly[-1])
        return pts

    glide_zh_cases = {
        "nihao": "你好",
        "zhongguo": "中国",
        "woaini": "我爱你",
        "weixin": "微信",
        "xianzai": "现在",
        "jintian": "今天",
        "shurufa": "输入法",
        "kaixin": "开心",
        "xiexie": "谢谢",
        "pengyou": "朋友",
    }
    for py_seq, g_exp in glide_zh_cases.items():
        t0 = time.perf_counter()
        g_cands = eng.glide_candidates(synth_swipe(py_seq), english=False, limit=5)
        dt = (time.perf_counter() - t0) * 1000
        g_top = [c.word for c in g_cands[:3]]
        g_ok = g_exp in g_top
        failed += not g_ok
        print(f"{'OK ' if g_ok else 'BAD'} glide-zh {py_seq:12} {dt:4.1f}ms -> {g_top}")

    glide_en_cases = {
        "hello": "hello",
        "github": "GitHub",
        "iphone": "iPhone",
        "python": "Python",
        "wechat": "WeChat",
    }
    for en_seq, g_exp in glide_en_cases.items():
        t0 = time.perf_counter()
        g_cands = eng.glide_candidates(synth_swipe(en_seq), english=True, limit=5)
        dt = (time.perf_counter() - t0) * 1000
        g_top = [c.word for c in g_cands[:3]]
        g_ok = g_exp in g_top
        failed += not g_ok
        print(f"{'OK ' if g_ok else 'BAD'} glide-en {en_seq:12} {dt:4.1f}ms -> {g_top}")

    reg_pass, reg_total = run_wowtype_regress(eng)
    en_hits = [r[0] for r in eng.con.execute("SELECT word FROM en_dict WHERE lower LIKE 'iph%' ORDER BY rank DESC LIMIT 5")]
    print(f"\n英文联想 iph -> {en_hits}")
    total = len(cases_26) + len(cases_t9) + 2 + len(u_cases) + len(glide_zh_cases) + len(glide_en_cases)
    print(f"\n核心套件: {total - failed}/{total} 通过 | WowType regress.tsv: {reg_pass}/{reg_total} 通过")
    return 1 if (failed or reg_pass != reg_total) else 0


if __name__ == "__main__":
    sys.exit(main())
