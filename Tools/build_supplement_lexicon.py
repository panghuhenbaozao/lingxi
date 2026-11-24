#!/usr/bin/env python3
"""
构建灵犀输入法轻量全字库与现代热词补充包 (Keyboard/Resources/supplement_lexicon.tsv)。

目标：
  1. 在不膨胀 51MB 主词库二进制的前提下，补齐 Unicode 基本多文种平面 (U+4E00..U+9FFF) 全部剩余 ~13,000+ 生僻/人名/古籍/方言/港台单字（如 幵、龘、喆同辈生僻字、化学元素字、姓氏生僻字），实现 20,900+ 汉字 100% 可打。
  2. 补齐雾凇 ext.dict.yaml 中此前未收录的高权重四字成语/常用短语，以及 2024–2026 日常口语/网络高频表达。

格式：
  #S\t<pinyin>\t<单字紧凑串（按常用度降序）>
  #P\t<词条>\t<apostrophe分隔全拼>\t<lp对数概率>
"""
from __future__ import annotations

import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "Keyboard" / "Resources" / "pinyin.sqlite"
DATA_DIR = ROOT / "Tools" / "data"
OUT_PATH = ROOT / "Keyboard" / "Resources" / "supplement_lexicon.tsv"

# 精选高频日常口语、网络热词与现代 AI/科技词汇（确保打字自然顺手不缺词）
CURATED_MODERN_PHRASES: list[tuple[str, str, float]] = [
    ("啊对对对", "a'dui'dui'dui", -11.20),
    ("已读乱回", "yi'du'luan'hui", -11.40),
    ("已读不回", "yi'du'bu'hui", -11.10),
    ("尊嘟假嘟", "zun'du'jia'du", -11.60),
    ("草台班子", "cao'tai'ban'zi", -11.20),
    ("水灵灵", "shui'ling'ling", -11.50),
    ("去班味", "qu'ban'wei", -11.80),
    ("班味", "ban'wei", -11.60),
    ("松弛感", "song'chi'gan", -11.00),
    ("情绪价值", "qing'xu'jia'zhi", -10.90),
    ("配享太庙", "pei'xiang'tai'miao", -11.80),
    ("偷感", "tou'gan", -12.10),
    ("偷感很重", "tou'gan'hen'zhong", -12.00),
    ("硬控", "ying'kong", -11.80),
    ("哈基米", "ha'ji'mi", -11.80),
    ("脆皮大学生", "cui'pi'da'xue'sheng", -11.90),
    ("特种兵式", "te'zhong'bing'shi", -12.10),
    ("那咋了", "na'za'le", -11.50),
    ("包的", "bao'de", -11.80),
    ("丸辣", "wan'la", -12.20),
    ("主包", "zhu'bao", -12.10),
    ("显眼包", "xian'yan'bao", -11.00),
    ("搭子", "da'zi", -11.20),
    ("饭搭子", "fan'da'zi", -11.40),
    ("旅游搭子", "lv'you'da'zi", -11.70),
    ("大模型", "da'mo'xing", -10.80),
    ("智能体", "zhi'neng'ti", -11.00),
    ("提示词", "ti'shi'ci", -11.10),
    ("具身智能", "ju'shen'zhi'neng", -11.60),
    ("深度思考", "shen'du'si'kao", -11.20),
    ("流式输出", "liu'shi'shu'chu", -11.80),
    ("端到端", "duan'dao'duan", -11.20),
    ("零延迟", "ling'yan'chi", -11.50),
    ("丝滑", "si'hua", -11.10),
    ("泰裤辣", "tai'ku'la", -12.20),
    ("家人们", "jia'ren'men", -11.00),
    ("谁懂啊", "shei'dong'a", -11.30),
    ("谁懂啊", "shui'dong'a", -11.30),
    ("纯爱战士", "chun'ai'zhan'shi", -12.00),
    ("电子榨菜", "dian'zi'zha'cai", -11.80),
    ("嘴替", "zui'ti", -11.80),
    ("互联网嘴替", "hu'lian'wang'zui'ti", -11.90),
    ("赛博朋克", "sai'bo'peng'ke", -11.60),
    ("脑雾", "nao'wu", -12.20),
    ("内耗", "nei'hao", -10.90),
    ("精神内耗", "jing'shen'nei'hao", -11.10),
    ("反内卷", "fan'nei'juan", -11.70),
    ("性价比", "xing'jia'bi", -10.50),
    ("质价比", "zhi'jia'bi", -11.60),
    ("心价比", "xin'jia'bi", -12.10),
    ("回头聊", "hui'tou'liao", -11.20),
    ("辛苦啦", "xin'ku'la", -10.80),
    ("收到啦", "shou'dao'la", -10.90),
    ("好的呢", "hao'de'ne", -11.00),
    ("好滴", "hao'di", -11.10),
    ("没毛病", "mei'mao'bing", -10.90),
    ("安排上", "an'pai'shang", -11.20),
    ("搞定啦", "gao'ding'la", -11.30),
    ("冲冲冲", "chong'chong'chong", -11.30),
]


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    valid_syllables: set[str] = set()
    existing_single_pairs: set[tuple[str, str]] = set()
    existing_words: set[str] = set()

    for word, py in c.execute("SELECT word, py FROM dict"):
        existing_words.add(word)
        for s in py.split("'"):
            valid_syllables.add(s)
        if len(word) == 1 and "'" not in py:
            existing_single_pairs.add((word, py))

    # 1. 从 chaizi 表提取全部缺失的 BMP 单字及拼音与权重
    rare_by_py: dict[str, dict[str, int]] = defaultdict(dict)
    for word, py, wt in c.execute("SELECT word, py, weight FROM chaizi WHERE py != ''"):
        if len(word) != 1:
            continue
        cp = ord(word)
        if not (0x4E00 <= cp <= 0x9FFF):
            continue
        py_norm = py.strip().lower().replace("ü", "v")
        if py_norm not in valid_syllables:
            continue
        if (word, py_norm) in existing_single_pairs:
            continue
        prev = rare_by_py[py_norm].get(word, -1)
        if wt > prev:
            rare_by_py[py_norm][word] = wt

    # 若安装了 pypinyin，补齐 U+4E00..U+9FFF 中极少数未进拆字表的汉字及常见多音字读音
    try:
        from pypinyin import Style, pinyin as py_multi

        for cp in range(0x4E00, 0x9FA6):
            ch = chr(cp)
            readings = py_multi(ch, style=Style.NORMAL, heteronym=True, v_to_u=False)
            if not readings:
                continue
            for idx, r in enumerate(readings[0][:3]):
                py_norm = r.strip().lower().replace("ü", "v")
                if py_norm in valid_syllables and (ch, py_norm) not in existing_single_pairs:
                    if ch not in rare_by_py[py_norm]:
                        # 主读音权重略高于次读音
                        rare_by_py[py_norm][ch] = 2 if idx == 0 else 1
    except ImportError:
        pass

    # 2. 从 ext.dict.yaml 和 base.dict.yaml 精选此前未进主库的实用 2~4 字高频词/成语
    phrase_map: dict[tuple[str, str], float] = {}
    for w, py, lp in CURATED_MODERN_PHRASES:
        syls = py.split("'")
        if all(s in valid_syllables for s in syls):
            phrase_map[(w, py)] = lp

    # base.dict.yaml 中 120 <= wt < 200 的常用 2~4 字词（主库门槛为 200）
    base_path = DATA_DIR / "rime_ice" / "base.dict.yaml"
    if base_path.exists():
        in_body = False
        base_candidates: list[tuple[int, str, str]] = []
        for line in base_path.open(encoding="utf-8"):
            line = line.rstrip("\r\n")
            if not in_body:
                if line == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3 or not parts[2].strip().isdigit():
                continue
            w = parts[0].strip()
            wt = int(parts[2].strip())
            if not (130 <= wt < 200) or not (2 <= len(w) <= 4) or w in existing_words:
                continue
            sy = [s.replace("ü", "v") for s in parts[1].strip().split(" ") if s]
            if len(sy) == len(w) and all(s in valid_syllables for s in sy):
                base_candidates.append((wt, w, "'".join(sy)))
        base_candidates.sort(key=lambda x: -x[0])
        for wt, w, py in base_candidates[:2200]:
            lp = -13.6 + (wt - 130) * 0.012
            if (w, py) not in phrase_map:
                phrase_map[(w, py)] = round(lp, 3)

    # ext.dict.yaml 中高权重 4 字成语与现代短语（wt >= 260）
    ext_path = DATA_DIR / "rime_ice" / "ext.dict.yaml"
    if ext_path.exists():
        in_body = False
        ext_candidates: list[tuple[int, str, str]] = []
        for line in ext_path.open(encoding="utf-8"):
            line = line.rstrip("\r\n")
            if not in_body:
                if line == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3 or not parts[2].strip().isdigit():
                continue
            w = parts[0].strip()
            wt = int(parts[2].strip())
            if wt < 240 or len(w) != 4 or w in existing_words:
                continue
            sy = [s.replace("ü", "v") for s in parts[1].strip().split(" ") if s]
            if len(sy) == 4 and all(s in valid_syllables for s in sy):
                ext_candidates.append((wt, w, "'".join(sy)))
        ext_candidates.sort(key=lambda x: -x[0])
        for wt, w, py in ext_candidates[:2000]:
            lp = -13.4 + min(1.8, (wt - 240) / 1000.0)
            if (w, py) not in phrase_map:
                phrase_map[(w, py)] = round(lp, 3)

    lines: list[str] = [
        "# Lingxi Supplement Lexicon v1 (Full Unicode BMP CJK + Curated Phrases)",
    ]
    total_rare_pairs = 0
    unique_rare_chars: set[str] = set()
    for py in sorted(rare_by_py.keys()):
        items = sorted(rare_by_py[py].items(), key=lambda kv: (-kv[1], ord(kv[0])))
        chars_str = "".join(ch for ch, _ in items)
        if chars_str:
            lines.append(f"#S\t{py}\t{chars_str}")
            total_rare_pairs += len(items)
            unique_rare_chars.update(chars_str)

    sorted_phrases = sorted(phrase_map.items(), key=lambda kv: (-kv[1], kv[0][0]))
    for (w, py), lp in sorted_phrases:
        lines.append(f"#P\t{w}\t{py}\t{lp:.2f}")

    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    size_kb = OUT_PATH.stat().st_size / 1024.0
    print(
        f"[supplement_lexicon] 生成完成: 扩展单字读音 {total_rare_pairs} 条 (去重 {len(unique_rare_chars)} 字), "
        f"补充热词/成语 {len(sorted_phrases)} 条, 体积 {size_kb:.1f} KB -> {OUT_PATH}"
    )


if __name__ == "__main__":
    main()
