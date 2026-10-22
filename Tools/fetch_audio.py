#!/usr/bin/env python3
"""
用百度翻译的 TTS 接口预生成发音，打包进 App（离线播放，不依赖系统 TTS）。

为什么用百度：系统 TTS 读单个汉字只有 0.5 秒左右，听起来又短又急；
百度这个接口读单字约 1.2–1.3 秒，尾音自然，还能整词发音、能调语速。

产出：
  HanziKid/Resources/audio/chars/<汉字>.mp3    单字（语速 spd=2，慢一点）
  HanziKid/Resources/audio/words/<词语>.mp3    组词（语速 spd=3，正常）

用法：
  python3 Tools/fetch_audio.py                # 全部（已存在则跳过）
  python3 Tools/fetch_audio.py --only-chars   # 只抓单字
  python3 Tools/fetch_audio.py --limit 20     # 试抓 20 个
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "HanziKid" / "Resources" / "audio"
CACHE = ROOT / "Tools" / "raw" / "tts_cache"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
ENDPOINT = "https://fanyi.baidu.com/gettts?lan=zh&text={text}&spd={spd}&source=web"


def load_library() -> list[dict]:
    return json.loads((ROOT / "HanziKid" / "Resources" / "base_characters.json").read_text(encoding="utf-8"))["characters"]


def load_decks() -> list[dict]:
    return json.loads((ROOT / "HanziKid" / "Resources" / "decks.json").read_text(encoding="utf-8"))["decks"]


def fetch_audio(text: str, spd: int, attempts: int = 3) -> bytes | None:
    url = ENDPOINT.format(text=urllib.parse.quote(text), spd=spd)
    for attempt in range(attempts):
        request = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://fanyi.baidu.com/"})
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                data = response.read()
                content_type = response.headers.get_content_type()
        except Exception:
            time.sleep(0.8 * (attempt + 1))
            continue
        if len(data) > 1500 and (content_type == "audio/mpeg"
                                 or data[:1] == b"\xff"
                                 or data[:3] == b"ID3"):
            return data
        time.sleep(0.6 * (attempt + 1))
    return None


def download(kind: str, text: str, spd: int) -> tuple[str, str]:
    folder = AUDIO / kind
    target = folder / f"{text}.mp3"
    if target.exists() and target.stat().st_size > 1500:
        return text, "skip"
    cached = CACHE / kind / f"{text}.mp3"
    if cached.exists() and cached.stat().st_size > 1500:
        folder.mkdir(parents=True, exist_ok=True)
        target.write_bytes(cached.read_bytes())
        return text, "cache"
    data = fetch_audio(text, spd)
    if not data:
        return text, "fail"
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(data)
    folder.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return text, "ok"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only-chars", action="store_true")
    parser.add_argument("--only-words", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    library = load_library()
    decks = load_decks()

    char_items: list[str] = [item["hanzi"] for item in library]
    deck_chars: list[str] = []
    for deck in decks:
        for ch in deck["hanzi"]:
            if ch not in deck_chars:
                deck_chars.append(ch)
    by_hanzi = {item["hanzi"]: item for item in library}
    word_items: list[str] = []
    for ch in deck_chars:
        for word in by_hanzi.get(ch, {}).get("words", [])[:6]:
            if word not in word_items:
                word_items.append(word)

    tasks: list[tuple[str, str, int]] = []
    if not args.only_words:
        tasks += [("chars", ch, 2) for ch in char_items]
    if not args.only_chars:
        tasks += [("words", word, 3) for word in word_items]
    if args.limit:
        tasks = tasks[: args.limit]

    print(f"待抓取 {len(tasks)} 条（单字 {len(char_items)}，组词 {len(word_items)}）", flush=True)
    stats: dict[str, int] = {}
    failures: list[str] = []
    started = time.time()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(download, kind, text, spd): (kind, text) for kind, text, spd in tasks}
        for index, future in enumerate(as_completed(futures), 1):
            text, status = future.result()
            stats[status] = stats.get(status, 0) + 1
            if status == "fail":
                failures.append(text)
            if index % 500 == 0:
                print(f"  {index}/{len(tasks)}  {stats}  {time.time()-started:.0f}s", flush=True)

    total = sum(f.stat().st_size for f in AUDIO.rglob("*.mp3"))
    count = len(list(AUDIO.rglob("*.mp3")))
    print(f"\n完成：{stats}")
    print(f"音频 {count} 个，共 {total/1e6:.1f} MB")
    if failures:
        print(f"失败 {len(failures)} 条（运行时回退系统 TTS）：{''.join(failures[:40])}")


if __name__ == "__main__":
    sys.exit(main())
