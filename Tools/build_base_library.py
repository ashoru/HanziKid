#!/usr/bin/env python3
"""
生成汉字识字 App 的内置离线字库。

数据源（全部开源，见 README / 设计文档 6.2）：

  raw/xinhua_word.json     pwxcoo/chinese-xinhua   拼音 / 部首 / 笔画数 / 释义
  raw/pinyin.txt           mozillazg/pinyin-data   多音字读音（带声调）
  raw/hanzi_graphics.txt   skishore/makemeahanzi   逐笔 SVG 路径 + 中线（笔顺动画）
  raw/jieba_dict.txt       fxsjy/jieba             词频（用于选常用字 + 组词）

产出：

  Resources/base_characters.json   字卡基础数据
  Resources/strokes.json           每字逐笔路径（1024 网格，y 需翻转）

用法：
  python3 Tools/build_base_library.py --limit 800
  python3 Tools/build_base_library.py --limit 800 --force   # 重新下载原始数据
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "Tools" / "raw"
OUT = ROOT / "HanziKid" / "Resources"

SOURCES = {
    "xinhua_word.json": "https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/data/word.json",
    "pinyin.txt": "https://raw.githubusercontent.com/mozillazg/pinyin-data/master/pinyin.txt",
    "hanzi_graphics.txt": "https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt",
    "jieba_dict.txt": "https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt",
}

CJK = re.compile(r"^[\u4e00-\u9fff]$")
# 组词时排除的词性：人名/地名/音译/英文/数量词
BAD_TAGS = {"nr", "ns", "nt", "nz", "nrt", "eng", "x", "m", "mq"}


def ensure_sources(force: bool = False) -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    for name, url in SOURCES.items():
        path = RAW / name
        if path.exists() and path.stat().st_size > 10_000 and not force:
            continue
        print(f"下载 {name} …", flush=True)
        tmp = path.with_suffix(path.suffix + ".part")
        with urllib.request.urlopen(url, timeout=180) as resp, open(tmp, "wb") as fh:
            fh.write(resp.read())
        tmp.replace(path)
        print(f"  → {path.stat().st_size / 1e6:.1f} MB")


def load_xinhua() -> dict[str, dict]:
    """word.json → {汉字: {pinyin, radical, strokes, explanation}}"""
    with open(RAW / "xinhua_word.json", encoding="utf-8") as fh:
        entries = json.load(fh)
    out = {}
    for e in entries:
        ch = e.get("word", "")
        if len(ch) == 1 and CJK.match(ch):
            out[ch] = e
    return out


def load_pinyin() -> dict[str, list[str]]:
    """pinyin.txt → {汉字: [shuǐ, ...]}（保留原始声调符号；ü 转 v 再转回）"""
    out: dict[str, list[str]] = {}
    line_re = re.compile(r"^U\+([0-9A-F]+):\s*([^#]+)#")
    with open(RAW / "pinyin.txt", encoding="utf-8") as fh:
        for line in fh:
            m = line_re.match(line)
            if not m:
                continue
            cp = int(m.group(1), 16)
            readings = [r.strip() for r in m.group(2).split(",") if r.strip()]
            readings = [r.replace("u:", "ü") for r in readings]
            if readings and 0x4E00 <= cp <= 0x9FFF:
                out[chr(cp)] = readings
    return out


def load_strokes() -> dict[str, dict]:
    """graphics.txt → {汉字: {"strokes": [...], "medians": [...]}}"""
    out = {}
    with open(RAW / "hanzi_graphics.txt", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                g = json.loads(line)
            except json.JSONDecodeError:
                continue
            ch = g.get("character", "")
            if len(ch) == 1 and CJK.match(ch) and g.get("strokes"):
                out[ch] = {"strokes": g["strokes"], "medians": g.get("medians", [])}
    return out


def load_words() -> tuple[dict[str, float], list[tuple[str, float, str]]]:
    """
    jieba dict.txt → (字频表, 词表)
    字频 = 该字参与的所有词频累加（长词降权），用来排"常用字"顺序。
    """
    char_freq: dict[str, float] = defaultdict(float)
    words: list[tuple[str, float, str]] = []
    with open(RAW / "jieba_dict.txt", encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2:
                continue
            word, freq = parts[0], parts[1]
            tag = parts[2] if len(parts) > 2 else ""
            try:
                f = float(freq)
            except ValueError:
                continue
            words.append((word, f, tag))
            if not all(CJK.match(c) for c in word):
                continue
            weight = f if len(word) <= 2 else f * 0.4
            for c in set(word):
                char_freq[c] += weight
    return char_freq, words



# 5 岁启蒙字表的组词与释义人工兜底：这批字是孩子最先学的，必须贴近生活
PRESCHOOL_CONTENT: dict[str, tuple[str, list[str]]] = {
    "一": ("数字 1，一个", ["一个", "一起", "第一", "一半"]),
    "二": ("数字 2，两个", ["二月", "二十", "第二", "二年级"]),
    "三": ("数字 3，三个", ["三月", "三天", "三个", "再三"]),
    "四": ("数字 4，四个", ["四月", "四季", "四个", "四方"]),
    "五": ("数字 5，五个", ["五月", "五个", "五指", "五彩"]),
    "六": ("数字 6，六个", ["六月", "六个", "六点", "六一"]),
    "七": ("数字 7，七个", ["七月", "七个", "七天", "七彩"]),
    "八": ("数字 8，八个", ["八月", "八个", "八点", "八方"]),
    "九": ("数字 9，九个", ["九月", "九个", "九点", "九天"]),
    "十": ("数字 10，十个", ["十月", "十个", "十分", "十足"]),
    "人": ("会说话、会走路的人", ["大人", "老人", "人们", "人家"]),
    "口": ("嘴；也指门口、洞口", ["开口", "口水", "门口", "出口"]),
    "手": ("用来拿东西的手", ["小手", "手指", "动手", "洗手"]),
    "足": ("脚", ["手足", "足球", "不足", "满足"]),
    "目": ("眼睛", ["目光", "目的", "目录", "耳目"]),
    "大": ("和小相反，个头多", ["大人", "大树", "大门", "长大"]),
    "小": ("和大相反，个头少", ["小孩", "小狗", "小学", "大小"]),
    "多": ("数量大，很多", ["很多", "多少", "许多", "多年"]),
    "少": ("数量小，不多", ["多少", "少数", "少年", "缺少"]),
    "上": ("位置在高处；向上", ["上面", "上学", "早上", "上下"]),
    "下": ("位置在低处；向下", ["下面", "下雨", "下车", "下来"]),
    "里": ("里面", ["里面", "这里", "家里", "心里"]),
    "外": ("外面", ["外面", "外国", "外公", "门外"]),
    "前": ("前面", ["前面", "以前", "向前", "门前"]),
    "后": ("后面", ["后面", "以后", "后来", "后退"]),
    "中": ("里面；正中间", ["中间", "中心", "中国", "空中"]),
    "日": ("太阳；一天", ["日子", "生日", "星期日", "日出"]),
    "月": ("月亮；月份", ["月亮", "月光", "一月", "月牙"]),
    "水": ("喝的水，河里的水", ["喝水", "水果", "水杯", "河水"]),
    "火": ("会发光发热的火", ["火车", "火苗", "大火", "生火"]),
    "山": ("高高的山", ["高山", "山上", "爬山", "山坡"]),
    "石": ("石头", ["石头", "石桥", "石子", "岩石"]),
    "土": ("泥土", ["泥土", "土地", "土豆", "沙土"]),
    "天": ("天空；一天", ["天空", "今天", "白天", "天气"]),
    "地": ("地面；土地", ["地上", "土地", "地方", "草地"]),
    "木": ("树木；木头", ["木头", "木马", "树木", "积木"]),
    "米": ("大米", ["大米", "米饭", "小米", "玉米"]),
    "花": ("开出来的花", ["花朵", "开花", "红花", "花园"]),
    "草": ("小草", ["小草", "草地", "花草", "青草"]),
    "树": ("树木", ["大树", "树叶", "树木", "树林"]),
    "弟": ("弟弟，比自己小的男孩", ["弟弟", "兄弟", "小弟", "表弟"]),
    "我": ("自己", ["我们", "我的", "我家", "自我"]),
    "你": ("对方，听话的人", ["你们", "你好", "你的", "你我"]),
    "他": ("别人，另外那个人", ["他们", "他人", "其他", "他的"]),
    "男": ("男的，男性", ["男人", "男孩", "男生", "男女"]),
    "女": ("女的，女性", ["女人", "女孩", "女生", "子女"]),
    "马": ("会跑的大动物", ["小马", "木马", "马路", "赛马"]),
    "鱼": ("水里的鱼", ["小鱼", "金鱼", "鱼儿", "钓鱼"]),
    "门": ("进出的门", ["大门", "开门", "门口", "关门"]),
    "车": ("会跑的车", ["汽车", "火车", "车子", "车站"]),
    "船": ("在水上走的船", ["小船", "大船", "轮船", "帆船"]),
    "风": ("风", ["大风", "风雨", "风筝", "台风"]),
    "云": ("天上的云", ["白云", "乌云", "云朵", "云彩"]),
    "来": ("过来，到这里", ["过来", "回来", "出来", "来到"]),
    "去": ("离开，到那里", ["出去", "回去", "去年", "上去"]),
    "开": ("打开；开始", ["打开", "开门", "开心", "开会"]),
    "关": ("关上；关心", ["关门", "关心", "关上", "开关"]),
    "走": ("用脚走路", ["走路", "走开", "行走", "快走"]),
    "看": ("用眼睛看", ["看见", "看书", "好看", "看到"]),
    "听": ("用耳朵听", ["听见", "听话", "听讲", "好听"]),
    "说": ("用嘴说话", ["说话", "说明", "听说", "小说"]),
    "读": ("读书，念出声音", ["读书", "朗读", "读音", "阅读"]),
    "写": ("用笔写字", ["写字", "书写", "写作", "大写"]),
    "爱": ("很喜欢", ["爱心", "可爱", "爱好", "热爱"]),
    "笑": ("笑，心里高兴", ["笑脸", "微笑", "笑话", "大笑"]),
    "好": ("好，不错", ["好人", "好看", "你好", "好处"]),
    "红": ("红色，像苹果的颜色", ["红色", "红花", "红旗", "火红"]),
    "黄": ("黄色，像香蕉的颜色", ["黄色", "黄豆", "黄牛", "金黄"]),
    "白": ("白色，像雪的颜色", ["白色", "白云", "白天", "明白"]),
    "黑": ("黑色，像夜里的颜色", ["黑色", "黑夜", "黑板", "乌黑"]),
    "长": ("长；也指长大", ["长大", "长短", "校长", "生长"]),
    "高": ("高，从下到上距离大", ["高山", "高兴", "长高", "高手"]),
}

# 高频虚词 / 代词 / 方位词：字典本义对幼儿毫无意义，人工兜底
CURATED_MEANING = {
    "我": "自己，说话的人", "你": "对方，听话的人", "他": "另外的那个人",
    "她": "女性，她", "它": "指东西或动物", "的": "表示所属，如「我的书」",
    "了": "表示已经完成", "是": "就是、对", "在": "存在，或在某个地方",
    "有": "拥有，存在", "不": "否定，不要", "和": "跟、与；也指不吵架",
    "就": "马上、立刻", "都": "全部", "也": "同样", "很": "非常",
    "这": "指近的东西", "那": "指远的东西", "上": "位置在高处",
    "下": "位置在低处", "中": "里面、正中间", "大": "和小相反，体积多",
    "小": "和大相反，体积少", "个": "量词，一个、两个", "着": "表示正在进行",
    "把": "用手握住；量词", "被": "表示承受动作", "给": "交给、送给",
    "走": "用脚向前移动", "写": "用笔在纸上留下字", "看": "用眼睛观察",
}


ENUM_MARKS = "⒈⒉⒊⒋⒌⒍⒎⒏⒐⒑①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷"
LATIN = re.compile(r"[a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü0-9]")


# 释义里出现这些词，说明抽到的是古义/引证，不能给孩子看
SUSPICIOUS = ("同本义", "又如", "另见", "本义", "--", "《", "〈", "〉",
              "古代", "古时", "旧时", "通菉", "通“", "籀", "假借", "方言")


def clean_meaning(ch: str, explanation: str, limit: int = 46) -> str:
    """把冗长的字典释义压成一句给孩子看的话。

    抽取顺序：「本义」段 → 正文第一条定义；两处都过 SUSPICIOUS 过滤，
    宁可空着，也不给孩子看古文原句。
    """
    if ch in PRESCHOOL_CONTENT:
        return PRESCHOOL_CONTENT[ch][0]
    if ch in CURATED_MEANING:
        return CURATED_MEANING[ch]
    if not explanation:
        return ""

    text = explanation.replace("\r", "")
    flat = re.sub(r"\s*\n\s*", "", text)

    def tidy(raw: str) -> str:
        t = raw.strip()
        t = re.sub(r"^[" + ENUM_MARKS + r"\s\.、]+", "", t)
        t = re.sub(r"[（(][^）)]*[）)]", "", t)
        # 开头是括号注释（"(象形。从乹…"）：有闭合就取括号后的内容，没闭合就整条丢掉
        if t[:1] in ("（", "("):
            if let := re.search(r"[）)]", t):
                t = t[let.end():].strip()
            else:
                return ""
        t = t.strip("，,、;； 　")
        head = re.split(r"[，,、；;：:。]", t)[0].strip()
        if len(head) < 2:
            return ""   # 「歌,咏也」「版,大版」这种：宁可空着
        t = head
        t = re.sub(r"\s+", "", t)
        if len(t) < 2 or len(t) > limit or LATIN.search(t):
            return ""
        if any(k in t for k in SUSPICIOUS):
            return ""
        if t == ch:
            return ""
        return t.strip("，,、;； 　")

    # 1) 「本义 XXX」：通常是孩子最好懂的一句
    match = re.search(r"本义[：:]?\s*([^\)）]+)", flat)
    if match:
        for segment in re.split(r"[。]", match.group(1)):
            if segment.strip() == ch:
                continue
            candidate = tidy(segment)
            if candidate:
                return candidate

    # 2) 正文里第一条像定义的话（剔除引证）
    lines = [ln.strip() for ln in text.split("\n") if ln.strip()]
    if lines and len(lines[0]) <= 2:
        lines = lines[1:]
    for line in lines:
        candidate = tidy(re.split(r"[。]", line)[0])
        if candidate:
            return candidate
    return ""


def pick_words(ch: str, index: dict[str, list[tuple[str, float]]], limit: int) -> list[str]:
    """挑最适合给孩子看的组词：优先该字打头的双字词，再按词频。"""
    cands = index.get(ch, [])
    head2 = [w for w, _ in cands if len(w) == 2 and w.startswith(ch)]
    head3 = [w for w, _ in cands if len(w) == 3 and w.startswith(ch)]
    other = [w for w, _ in cands if not w.startswith(ch)]
    tail = [w for w, f in cands if w.endswith(ch) and len(w) == 2]

    chosen: list[str] = []
    for pool in (head2, other, head3, tail):
        for w in pool:
            if w not in chosen and all(c in (ch, *w) for c in w):
                chosen.append(w)
            if len(chosen) >= limit:
                return chosen[:limit]
    return chosen[:limit]


# 5 岁启蒙默认字表：按认知顺序排，不按字频（先具体名词，再方位/数字/动作）
PRESCHOOL_ORDER = (
    "一二三四五六七八九十"
    "人口手足耳目"
    "大小多少上下里外前后中"
    "日月水火山石田土天地"
    "木禾竹米花草树"
    "爸妈爷奶哥姐弟妹"
    "我你他男女"
    "牛羊马鸟鱼虫猫狗"
    "门窗车船"
    "风雨云雪"
    "来去开关走看听说读写"
    "爱笑哭好"
    "红黄绿白黑"
    "长短高矮"
)


def build_decks(cards: list[dict]) -> list[dict]:
    present = {c["hanzi"] for c in cards}
    seen: set[str] = set()
    preschool = []
    for ch in PRESCHOOL_ORDER:
        if ch in present and ch not in seen:
            seen.add(ch)
            preschool.append(ch)
    # 四年级示例字表：取字库中频段（跳过启蒙字），代表"课本里的字"的难度
    rest = [c["hanzi"] for c in cards if c["hanzi"] not in seen]
    primary = rest[150:270] if len(rest) > 270 else rest[:120]
    return [
        {"name": f"启蒙 {len(preschool)} 字", "level": 1, "hanzi": preschool},
        {"name": "四年级·示例 120 字", "level": 2, "hanzi": primary},
    ]


def build(limit: int) -> None:
    print("读取数据源 …", flush=True)
    xinhua = load_xinhua()
    pinyins = load_pinyin()
    strokes = load_strokes()
    char_freq, words = load_words()

    # 组词索引：只收 2–4 字、非专名、字都在常用范围内的词
    word_index: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for word, freq, tag in words:
        if not (2 <= len(word) <= 4):
            continue
        if tag in BAD_TAGS:
            continue
        if not all(CJK.match(c) for c in word):
            continue
        for c in set(word):
            word_index[c].append((word, freq))
    for c in word_index:
        word_index[c].sort(key=lambda x: -x[1])

    # 候选字：三库齐全才入表
    candidates = [
        c for c in xinhua
        if c in strokes and c in char_freq and char_freq[c] > 0
    ]
    candidates.sort(key=lambda c: -char_freq[c])
    chosen = candidates[:limit]

    # 兜底：把数字/基础字强制带上（幼儿启蒙最先学到）
    for c in "一二三四五六七八九十人口手大小上下中天日月山水火木土":
        if c in xinhua and c in strokes and c not in chosen:
            chosen.append(c)

    cards = []
    stroke_data = {}
    for ch in chosen:
        e = xinhua[ch]
        readings = pinyins.get(ch) or ([e["pinyin"]] if e.get("pinyin") else [])
        readings = [r for r in readings if r]
        try:
            stroke_count = int(re.sub(r"\D", "", str(e.get("strokes", "0"))) or 0)
        except ValueError:
            stroke_count = 0
        if not stroke_count:
            stroke_count = len(strokes[ch]["strokes"])

        curated = PRESCHOOL_CONTENT.get(ch)
        cards.append({
            "hanzi": ch,
            "pinyin": readings[0] if readings else "",
            "pinyinAll": readings,
            "radical": e.get("radicals", "") or "",
            "strokeCount": stroke_count,
            "meaning": clean_meaning(ch, e.get("explanation", "")),
            "words": curated[1] if curated else pick_words(ch, word_index, 6),
            "frequency": round(char_freq[ch], 1),
        })
        stroke_data[ch] = {
            "strokes": strokes[ch]["strokes"],
            "medians": strokes[ch]["medians"],
        }

    OUT.mkdir(parents=True, exist_ok=True)
    digest = hashlib.md5(
        json.dumps(cards, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()[:12]
    with open(OUT / "base_characters.json", "w", encoding="utf-8") as fh:
        json.dump({"version": 2, "contentHash": digest, "count": len(cards), "characters": cards},
                  fh, ensure_ascii=False, indent=1)
    print(f"   内容指纹 {digest}")
    with open(OUT / "strokes.json", "w", encoding="utf-8") as fh:
        json.dump(stroke_data, fh, ensure_ascii=False, separators=(",", ":"))

    decks = build_decks(cards)
    with open(OUT / "decks.json", "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "decks": decks}, fh, ensure_ascii=False, indent=1)
    print(f"✅ 默认字表 {[(d['name'], len(d['hanzi'])) for d in decks]} → decks.json")

    missing_words = sum(1 for c in cards if not c["words"])
    print(f"✅ {len(cards)} 字 → {OUT/'base_characters.json'} "
          f"({(OUT/'base_characters.json').stat().st_size/1e6:.2f} MB)")
    print(f"✅ 笔顺 {len(stroke_data)} 字 → {OUT/'strokes.json'} "
          f"({(OUT/'strokes.json').stat().st_size/1e6:.2f} MB)")
    print(f"   无组词 {missing_words} 字，无拼音 {sum(1 for c in cards if not c['pinyin'])} 字")
    print("   样例：", json.dumps(cards[0], ensure_ascii=False)[:200])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=800)
    ap.add_argument("--force", action="store_true", help="重新下载原始数据")
    args = ap.parse_args()
    try:
        ensure_sources(args.force)
        build(args.limit)
    except Exception as exc:  # noqa: BLE001
        print(f"❌ {exc}", file=sys.stderr)
        raise
