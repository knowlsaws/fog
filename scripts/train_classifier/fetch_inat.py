#!/usr/bin/env python3
"""iNaturalist から魚種ごとの写真（研究グレード・CC ライセンス）を集める。標準ライブラリのみ。

  python3 scripts/train_classifier/fetch_inat.py --out data/fish --per-species 200 --test-ratio 0.2

docs/species.md の学名で検索し、data/fish/train/<標準和名>/ と test/<標準和名>/ に保存する。
ライセンスは CC0 / CC-BY / CC-BY-NC のみ（本人利用のアプリなので非商用で問題ない）。出典は credits.json に残す。
"""
import argparse
import json
import os
import random
import sys
import time
import urllib.parse
import urllib.request

# 標準和名: 学名（docs/species.md）
SPECIES = {
    "アイナメ": "Hexagrammos otakii",
    "クロソイ": "Sebastes schlegelii",
    "マゾイ": "Sebastes vulpes",
    "シマゾイ": "Sebastes trivittatus",
    "エゾメバル": "Sebastes taczanowskii",
    "ムラソイ": "Sebastes pachycephalus",
    "カジカ": "Myoxocephalus polyacanthocephalus",
    "ホッケ": "Pleurogrammus azonus",
    "クジメ": "Hexagrammos agrammus",
    "マコガレイ": "Pseudopleuronectes yokohamae",
    "クロガシラガレイ": "Pseudopleuronectes schrenki",
    "ウグイ": "Pseudaspius hakonensis",
    "ヒラメ": "Paralichthys olivaceus",
    "ブリ": "Seriola quinqueradiata",
    "サクラマス": "Oncorhynchus masou",
}
LICENSES = "cc0,cc-by,cc-by-nc"
API = "https://api.inaturalist.org/v1"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "fog-classifier/1.0 (personal fishing app)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def taxon_id(name):
    data = json.loads(get(f"{API}/taxa?q={urllib.parse.quote(name)}&rank=species&per_page=1"))
    results = data.get("results", [])
    return results[0]["id"] if results else None


def photos_for(tid, limit):
    out = []
    page = 1
    while len(out) < limit and page <= 10:
        url = (f"{API}/observations?taxon_id={tid}&quality_grade=research&photo_license={LICENSES}"
               f"&photos=true&per_page=100&page={page}&order_by=votes")
        data = json.loads(get(url))
        results = data.get("results", [])
        if not results:
            break
        for obs in results:
            for p in obs.get("photos", [])[:1]:
                url_m = p.get("url", "").replace("square", "medium")
                if url_m:
                    out.append({"url": url_m, "license": p.get("license_code"), "attribution": p.get("attribution"), "observation": obs.get("id")})
        page += 1
        time.sleep(1)
    return out[:limit]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/fish")
    ap.add_argument("--per-species", type=int, default=200)
    ap.add_argument("--test-ratio", type=float, default=0.2)
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    random.seed(42)
    credits = {}
    for jp, sci in SPECIES.items():
        if args.only and jp not in args.only:
            continue
        tid = taxon_id(sci)
        if not tid:
            print(f"::warning::{jp} ({sci}) が iNaturalist に見つかりません", file=sys.stderr)
            continue
        photos = photos_for(tid, args.per_species)
        random.shuffle(photos)
        n_test = int(len(photos) * args.test_ratio)
        print(f"{jp}: {len(photos)} photos (test {n_test})", file=sys.stderr)
        for i, p in enumerate(photos):
            split = "test" if i < n_test else "train"
            d = os.path.join(args.out, split, jp)
            os.makedirs(d, exist_ok=True)
            path = os.path.join(d, f"inat_{p['observation']}_{i}.jpg")
            if os.path.exists(path):
                continue
            try:
                with open(path, "wb") as f:
                    f.write(get(p["url"]))
            except Exception as e:  # noqa: BLE001
                print(f"  skip {p['url']}: {e}", file=sys.stderr)
            credits[path] = {"license": p["license"], "attribution": p["attribution"]}
            time.sleep(0.2)
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "credits.json"), "w", encoding="utf-8") as f:
        json.dump(credits, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
