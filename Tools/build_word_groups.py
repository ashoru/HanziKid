#!/usr/bin/env python3
"""
重建「组词」数据：每个字 2 个常用词，多音字按读音分组，每个读音 2 个词。

数据源（都要是词典里查得到的词，不用人名/地名/生僻词）：

  raw/cedict.txt       CC-CEDICT（开源汉英词典，12.5 万条，带拼音 + 释义）
  raw/jieba_dict.txt   fxsjy/jieba 词频（用来只留"常用"的词）
  Resources/base_characters.json   现有字库（字、拼音、多音字读音）

筛选规则：
  1. 词长 2 个字（凑不够时允许 3 个字）
  2. 词里每个字都在内置字库里（3506 字）
  3. 词的拼音音节数 = 字数，且该字在这个词里的读音 = 该字的某个读音
  4. 排除专有名词：拼音首字母大写的都是人名/地名/朝代名（CC-CEDICT 的约定）
  5. 排除释义里的 "surname / variant / abbr. / archaic / Japanese / Korean …"
  6. 按 jieba 词频从高到低取，词频门槛分档（2000 → 800 → 300 → 100 → 0）

用法：
  python3 Tools/build_word_groups.py --report      # 只看统计，不写文件
  python3 Tools/build_word_groups.py               # 写回 base_characters.json
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "Tools" / "raw"
LIBRARY = ROOT / "HanziKid" / "Resources" / "base_characters.json"

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"

# 释义里出现这些就当"不是普通词"
BAD_DEFS = (
    "surname",
    "variant of",
    "old variant",
    "archaic",
    "abbr. for",
    "abbr. to",
    "used in",
    "japanese",
    "korean",
    "taiwan pr.",
    "also written",
    "see also",
    "erhua variant",
    "person's name",
)

# 不适合给孩子看的词
BLOCKED_WORDS = {
    "他妈的", "狗日", "妈的", "娘的", "婊子", "王八", "混蛋", "妓女", "娼妓", "强奸",
    "走狗", "鸦片", "赌博", "吸毒", "自杀", "妈的逼", "屌", "屎", "尿", "放屁",
    "该死", "滚蛋", "畜生", "贱人", "白痴", "智障", "神经病", "流氓", "色情",
    "狗屁", "屁话", "他妈", "妈的个", "日你", "操你", "傻逼", "傻B", "二逼",
    "狗贼", "尚书", "的确良", "王八蛋", "兔崽子",
}

# 人工校正：自动挑词在这些字上会挑到文言/歧义词，直接指定更合适的常用词
OVERRIDES: dict[str, list[dict]] = {
    "长": [{"pinyin": "zhǎng", "words": ["长大", "校长"]},
           {"pinyin": "cháng", "words": ["长短", "长度"]}],
    "行": [{"pinyin": "xíng", "words": ["行走", "行动"]},
           {"pinyin": "háng", "words": ["银行", "行业"]}],
    "都": [{"pinyin": "dōu", "words": ["都是", "全都"]},
           {"pinyin": "dū", "words": ["首都", "古都"]}],
    "觉": [{"pinyin": "jué", "words": ["觉得", "感觉"]},
           {"pinyin": "jiào", "words": ["睡觉", "午觉"]}],
    "书": [{"pinyin": "shū", "words": ["读书", "书本"]}],
    "狗": [{"pinyin": "gǒu", "words": ["小狗", "热狗"]}],
    "的": [{"pinyin": "de", "words": ["我的", "好的"]},
           {"pinyin": "dì", "words": ["目的", "有的放矢"]}],
    "子": [{"pinyin": "zi", "words": ["孩子", "儿子"]},
           {"pinyin": "zǐ", "words": ["电子", "子女"]}],
    "和": [{"pinyin": "hé", "words": ["和平", "和气"]},
           {"pinyin": "huò", "words": ["和面", "和药"]}],
    "地": [{"pinyin": "dì", "words": ["土地", "地方"]},
           {"pinyin": "de", "words": ["慢慢地", "高兴地"]}],
}

# 常见姓氏（兜底词首字是这些就当作人名，跳过）
SURNAMES = set(
    "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻"
    "柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳唐罗薛雷贺倪汤滕殷罗毕郝邬"
    "安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵湛汪祁毛禹狄米贝明臧计伏成"
    "戴谈宋茅庞熊纪舒屈项祝董梁杜阮蓝闵席季麻强贾路娄危江童颜郭梅盛林刁钟徐邱骆"
    "高夏蔡田樊胡凌霍虞万支柯昝管卢莫经房裘缪干解应宗丁宣贲邓郁单杭洪包诸左石崔"
    "吉钮龚程嵇邢滑裴陆荣翁荀羊惠甄曲家封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山"
    "谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘钭厉戎祖武符刘景詹束龙叶幸司韶郜黎蓟薄"
    "印宿白怀蒲邰从鄂索咸籍赖卓蔺屠蒙池乔阴胥苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦"
    "雍却璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎"
    "戈廖庾终暨居衡步都耿满弘匡国文寇广禄阙东欧殳沃利蔚越夔隆师巩厍聂晁勾敖融冷"
    "訾辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后荆红游竺权逯盖益桓公"
)

# 声调符号 → 无调
TONE_MAP = str.maketrans(
    "āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜüńňǹê",
    "aaaaeeeeiiiioooouuuuüüüüünnne",
)


TONE_NUM = {
    "ā": ("a", 1), "á": ("a", 2), "ǎ": ("a", 3), "à": ("a", 4),
    "ē": ("e", 1), "é": ("e", 2), "ě": ("e", 3), "è": ("e", 4),
    "ī": ("i", 1), "í": ("i", 2), "ǐ": ("i", 3), "ì": ("i", 4),
    "ō": ("o", 1), "ó": ("o", 2), "ǒ": ("o", 3), "ò": ("o", 4),
    "ū": ("u", 1), "ú": ("u", 2), "ǔ": ("u", 3), "ù": ("u", 4),
    "ǖ": ("ü", 1), "ǘ": ("ü", 2), "ǚ": ("ü", 3), "ǜ": ("ü", 4),
}


def numbered(syllable: str) -> str:
    """带调拼音 → CC-CEDICT 风格（cháng → chang2，de → de5）"""
    tone = 5
    letters = []
    for ch in syllable.strip().lower():
        if ch in TONE_NUM:
            base, value = TONE_NUM[ch]
            letters.append(base)
            tone = value
        else:
            letters.append(ch)
    text = "".join(letters).replace("ü", "u:").replace("v", "u:")
    return f"{text}{tone}"


def plain(syllable: str) -> str:
    """把带调拼音（cháng / chang2）统一成无调小写（chang）"""
    out = []
    for ch in syllable:
        if ch.isdigit():
            continue
        out.append(ch)
    text = "".join(out).translate(TONE_MAP).lower()
    return text.replace("u:", "ü").replace("v", "ü")


def ensure_cedict() -> Path:
    path = RAW / "cedict.txt"
    if path.exists() and path.stat().st_size > 1_000_000:
        return path
    RAW.mkdir(parents=True, exist_ok=True)
    print("下载 CC-CEDICT …", flush=True)
    with urllib.request.urlopen(CEDICT_URL, timeout=180) as resp:
        blob = resp.read()
    path.write_text(gzip.decompress(blob).decode("utf-8"), encoding="utf-8")
    print(f"  → {path.stat().st_size / 1e6:.1f} MB")
    return path


def load_freq() -> dict[str, float]:
    freq: dict[str, float] = {}
    with open(RAW / "jieba_dict.txt", encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    freq[parts[0]] = float(parts[1])
                except ValueError:
                    continue
    return freq


def load_cedict(path: Path) -> list[tuple[str, str, list[str], str]]:
    """→ [(简体, 原始拼音串, 音节列表, 释义)]"""
    pattern = re.compile(r"^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.*)/$")
    rows: list[tuple[str, str, list[str], str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        match = pattern.match(line)
        if not match:
            continue
        _traditional, simplified, pinyin, defs = match.groups()
        rows.append((simplified, pinyin, pinyin.split(), defs))
    return rows


def reading_matches(syllable: str, readings: list[str], allow_neutral: bool = True) -> bool:
    """词的读音和字库读音是否一致；单读音字允许轻声（fu5）通配（吩咐 → 咐 fù）"""
    if syllable in readings:
        return True
    if allow_neutral and syllable.endswith("5"):
        base = syllable[:-1]
        return any(r[:-1] == base for r in readings if r and r[-1].isdigit())
    return False


def is_proper_noun(syllables: list[str]) -> bool:
    """CC-CEDICT 里专有名词的拼音首字母是大写的（Zhang1 lan2 / Chang2jiang1）"""
    return any(syllable[:1].isupper() for syllable in syllables)


def is_plain_word(defs: str) -> bool:
    low = defs.lower()
    return not any(bad in low for bad in BAD_DEFS)


def build(cards: list[dict], cedict: list[tuple[str, str, list[str], str]],
          freq: dict[str, float], per_reading: int = 2) -> dict[str, list[dict]]:
    hanzi_set = {card["hanzi"] for card in cards}
    # 精确读音（cháng → chang2）与宽松读音（chang）两套索引
    exact = {card["hanzi"]: [numbered(r) for r in card["pinyinAll"]] for card in cards}
    loose = {card["hanzi"]: {plain(r) for r in card["pinyinAll"]} for card in cards}

    # 词 → [(字, 读音, 词频, 长度)]；同一个词只保留词频最高的那条
    best: dict[str, tuple[float, str, str]] = {}
    for simplified, _raw_pinyin, syllables, defs in cedict:
        length = len(simplified)
        if length not in (2, 3):
            continue
        if not all(ch in hanzi_set for ch in simplified):
            continue
        if len(syllables) != length:
            continue
        if is_proper_noun(syllables):
            continue
        if not is_plain_word(defs):
            continue
        if simplified in BLOCKED_WORDS:
            continue
        score = freq.get(simplified, 0)
        # 同一个词可能有多条（多音），只留词频最高的
        previous = best.get(simplified)
        if previous and previous[0] >= score:
            continue
        # 这个词里每个字的读音都要是字库里存在的读音
        ok = True
        for index, ch in enumerate(simplified):
            allow_neutral = len(exact.get(ch, [])) == 1
            if not reading_matches(syllables[index].lower(), exact.get(ch, []), allow_neutral):
                ok = False
                break
        if not ok:
            continue
        # 记录成：词 → (词频, 主字读音, 说明)；按字建立索引时再拆
        best[simplified] = (score, "", "")

    # 按字 + 读音分桶
    buckets: dict[tuple[str, str], list[tuple[float, str]]] = defaultdict(list)
    for simplified, _raw, syllables, _defs in cedict:
        if simplified not in best:
            continue
        score = best[simplified][0]
        for index, ch in enumerate(simplified):
            reading = syllables[index].lower()
            allow_neutral = len(exact.get(ch, [])) == 1
            for target in exact.get(ch, []):
                if reading_matches(reading, [target], allow_neutral):
                    ranked = score * (1.5 if len(simplified) == 2 else 1.0)
                    if simplified.startswith(ch):
                        ranked *= 1.3
                    buckets[(ch, target)].append((ranked, simplified))
                    break

    buckets_loose: dict[tuple[str, str], list[tuple[float, str]]] = defaultdict(list)
    for simplified, _raw, syllables, _defs in cedict:
        if simplified not in best:
            continue
        score = best[simplified][0]
        for index, ch in enumerate(simplified):
            reading = plain(syllables[index])
            if reading not in loose.get(ch, set()):
                continue
            ranked = score * (1.5 if len(simplified) == 2 else 1.0)
            if simplified.startswith(ch):
                ranked *= 1.3
            buckets_loose[(ch, reading)].append((ranked, simplified))

    # 单读音字的兜底词：jieba 常用词里挑，跳过人名（首字是常见姓氏）和含生僻字的
    jieba_only: dict[str, list[str]] = defaultdict(list)
    for word, score in freq.items():
        if len(word) != 2 or score < 100:
            continue
        if not all(ch in hanzi_set for ch in word):
            continue
        if any(ch not in hanzi_set for ch in word):
            continue
        if word[0] in SURNAMES and word[1:] != "":
            continue
        if word in BLOCKED_WORDS:
            continue
        for ch in word:
            if len(exact.get(ch, [])) == 1:
                jieba_only[ch].append(word)
    for ch in jieba_only:
        jieba_only[ch] = sorted(set(jieba_only[ch]), key=lambda w: -freq.get(w, 0))[:6]

    thresholds = (2000, 800, 300, 100, 0)
    result: dict[str, list[dict]] = {}
    scores: dict[str, dict[str, float]] = {}
    for card in cards:
        ch = card["hanzi"]
        groups: list[dict] = []
        used: set[str] = set()
        group_scores: dict[str, float] = {}
        for original in card["pinyinAll"]:
            reading = numbered(original)
            picked: list[str] = []
            total = 0.0
            for lengths in ((2,), (2, 3)):
                for threshold in thresholds:
                    for score, word in sorted(buckets.get((ch, reading), []), reverse=True):
                        if len(picked) >= per_reading:
                            break
                        if len(word) not in lengths:
                            continue
                        if score < threshold or word in used or word in picked:
                            continue
                        picked.append(word)
                        total += score
                    if len(picked) >= per_reading:
                        break
                if len(picked) >= per_reading:
                    break
            if not picked and len(card["pinyinAll"]) == 1:
                # 兜底：只给单读音字用 jieba 里的常用词（字典没收「您好」这种）
                picked = jieba_only.get(ch, [])[:per_reading]
                total = sum(freq.get(w, 0) for w in picked)
                used.update(picked)
            if not picked and len(card["pinyinAll"]) == 1:
                # 再兜底（只限单读音字）：字典标音和字库不一致时按去声调宽松匹配
                loose_reading = plain(original)
                for threshold in thresholds:
                    for score, word in sorted(buckets_loose.get((ch, loose_reading), []), reverse=True):
                        if len(picked) >= per_reading:
                            break
                        if score < threshold or word in used or word in picked:
                            continue
                        picked.append(word)
                        total += score
                    if len(picked) >= per_reading:
                        break
            raw_total = sum(freq.get(w, 0) for w in picked)
            weakest = min((freq.get(w, 0) for w in picked), default=0)
            # 第一个（主）读音宽松；其他读音要"整组够常用、每个词也不太冷"
            if len(picked) >= per_reading and (not groups or (raw_total >= 800 and weakest >= 150)):
                used.update(picked)
                groups.append({"pinyin": original, "words": picked})
                group_scores[original] = total
            elif picked and not groups:
                # 第一个读音凑不满也先留着，免得整字没词
                used.update(picked)
                groups.append({"pinyin": original, "words": picked})
                group_scores[original] = total
        if groups:
            # 词频总量最高的读音排第一（同时把字卡的默认拼音改成它）
            groups.sort(key=lambda g: -group_scores.get(g["pinyin"], 0))
            result[ch] = groups
            scores[ch] = group_scores
    return result, scores


def apply_primary(cards: list[dict], groups: dict[str, list[dict]]) -> int:
    """把字卡默认拼音改成最常用的那个读音，并把它排到 pinyinAll 第一位"""
    changed = 0
    for card in cards:
        group_list = groups.get(card["hanzi"])
        if not group_list:
            continue
        primary = group_list[0]["pinyin"]
        if card.get("pinyin") != primary:
            card["pinyin"] = primary
            changed += 1
        rest = [r for r in card.get("pinyinAll", []) if r != primary]
        card["pinyinAll"] = [primary] + rest
    return changed


def original_reading(card: dict, flat: str) -> str:
    """把无调读音还原成字库里带调的形式"""
    for reading in card["pinyinAll"]:
        if plain(reading) == flat:
            return reading
    return flat


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="只打印统计，不写文件")
    parser.add_argument("--per-reading", type=int, default=2)
    args = parser.parse_args()

    payload = json.loads(LIBRARY.read_text(encoding="utf-8"))
    cards = payload["characters"]
    cedict = load_cedict(ensure_cedict())
    freq = load_freq()
    groups, _scores = build(cards, cedict, freq, per_reading=args.per_reading)

    polyphonic = [c for c in cards if len(c["pinyinAll"]) > 1]
    missing_primary = [c["hanzi"] for c in cards if not groups.get(c["hanzi"])]
    short_primary = [c["hanzi"] for c in cards
                     if len(groups.get(c["hanzi"], [{}])[0].get("words", [])) < args.per_reading]
    poly_missing = [c["hanzi"] for c in polyphonic if len(groups.get(c["hanzi"], [])) < 2]

    print(f"字库 {len(cards)} 字 · 多音字 {len(polyphonic)} 个")
    print(f"完全没有组词的字：{len(missing_primary)}")
    print(f"主读音不足 {args.per_reading} 个词的字：{len(short_primary)}")
    print(f"多音字里只给到一个读音的：{len(poly_missing)}")
    words = [w for gs in groups.values() for g in gs for w in g["words"]]
    print(f"组词总数 {len(words)}（去重 {len(set(words))}），平均每字 {len(words) / max(1, len(groups)):.1f}")

    for ch in ("长", "行", "都", "张", "重", "的", "了", "还", "乐", "着", "觉", "数", "间"):
        print(f"  {ch}: " + " / ".join(f"{g['pinyin']}→{'、'.join(g['words'])}" for g in groups.get(ch, [])))
    print("  完全没有组词的字：", " ".join(missing_primary))
    print("  主读音不足的样例：", " ".join(short_primary[:60]))

    if args.report:
        return

    # 人工校正优先（同时用它修正默认读音）
    for ch, group_list in OVERRIDES.items():
        groups[ch] = group_list
    changed = apply_primary(cards, groups)
    print(f"修正默认读音 {changed} 个字")
    for card in cards:
        ch = card["hanzi"]
        card_groups = groups.get(ch, [])
        card["wordGroups"] = card_groups
        card["words"] = [w for g in card_groups for w in g["words"]]
    payload["contentHash"] = "words-v2"
    LIBRARY.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"已写入 {LIBRARY}（{LIBRARY.stat().st_size / 1e6:.2f} MB）")


if __name__ == "__main__":
    main()
