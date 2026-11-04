#!/usr/bin/env python3
"""国土数値情報（国土交通省）の漁港データ（C09）と港湾データ（C02）を取得し、
釣り場候補として使う港の一覧 JSON を書き出す。

出力: [{"name": "鹿部漁港", "lat": 42.03, "lon": 140.81, "kind": "fishing"|"harbor", "pref": "01"}, ...]
Claude Code の実行環境からは nlftp.mlit.go.jp に届かないので CI（port-data.yml）で実行する。
利用規約: 国土数値情報は「政府標準利用規約（第2.0版）」（CC BY 4.0 互換）。出典表示が必要。
"""
import argparse
import io
import json
import re
import sys
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

BASE = "https://nlftp.mlit.go.jp/ksj/gml"
DATASETS = [
    # (識別子, 種別, 一覧ページ, 既知の zip URL の候補)
    ("C09", "fishing", f"{BASE}/datalist/KsjTmplt-C09.html", [f"{BASE}/data/C09/C09-06/C09-06_GML.zip"]),
    ("C02", "harbor", f"{BASE}/datalist/KsjTmplt-C02.html", [f"{BASE}/data/C02/C02-14/C02-14_GML.zip", f"{BASE}/data/C02/C02-06/C02-06_GML.zip"]),
]
UA = "fog-port-data/1.0 (GitHub Actions; fishing app data pipeline)"


def get(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def find_zip_urls(dataset: str, page_url: str, fallbacks: list[str]) -> list[str]:
    urls: list[str] = []
    try:
        html = get(page_url).decode("utf-8", "ignore")
        for m in re.finditer(rf"({dataset}-\d+[A-Za-z0-9_-]*_GML\.zip)", html):
            name = m.group(1)
            folder = name.split("_")[0]
            u = f"{BASE}/data/{dataset}/{folder}/{name}"
            if u not in urls:
                urls.append(u)
        # 全国版（都道府県別ではないもの）を優先。候補が多いときは最後（最新）から
        urls.sort(key=lambda u: (len(u), u), reverse=True)
        print(f"{dataset}: page lists {len(urls)} zip(s): {urls[:5]}", file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f"{dataset}: page fetch failed: {e}", file=sys.stderr)
    for f in fallbacks:
        if f not in urls:
            urls.append(f)
    return urls


def local(tag: str) -> str:
    return tag.split("}", 1)[1] if "}" in tag else tag


def parse_gml(data: bytes, kind: str) -> list[dict]:
    """JPGIS 1.0 / 2.1 の GML を、要素名に依存せずに読む。
    「Point」を名前に含む要素（gml:Point / jps:GM_Point）の id → 座標を集め、
    点を参照（xlink:href="#id"）し、かつ名前に「港」を含む文字列を持つ要素を港とする。"""
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        text = data.decode("shift_jis", "ignore")
        text = re.sub(r'encoding="[^"]+"', 'encoding="utf-8"', text, count=1)
        root = ET.fromstring(text.encode("utf-8"))
    points: dict[str, tuple[float, float]] = {}
    for el in root.iter():
        if "Point" not in local(el.tag):
            continue
        pid = next((v for k, v in el.attrib.items() if local(k) == "id"), None)
        pos = None
        for c in el.iter():
            if local(c.tag) in ("pos", "coordinates", "coordinate", "position") and c.text and c.text.strip():
                pos = c.text.strip().replace(",", " ").split()
                break
        if pid and pos and len(pos) >= 2:
            try:
                a, b = float(pos[0]), float(pos[1])
            except ValueError:
                continue
            lat, lon = (a, b) if a < b else (b, a)  # 日本では緯度 < 経度
            points[pid] = (lat, lon)
    out: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for feature in root.iter():
        ref = None
        texts: list[str] = []
        pref = None
        for c in feature.iter():
            href = next((v for k, v in c.attrib.items() if local(k) == "href"), None)
            if href and href.startswith("#") and ref is None:
                ref = href[1:]
            if c.text and c.text.strip():
                t = c.text.strip()
                texts.append(t)
                if "dministrative" in local(c.tag) and re.fullmatch(r"\d{2,5}", t):
                    pref = t[:2]
        if not ref or ref not in points:
            continue
        name = next((t for t in texts if "港" in t and len(t) <= 20), None)
        if not name or (name, ref) in seen:
            continue
        # 入れ子の親要素（データセット全体など）で同じ組を拾わないよう、直下に点参照を持つ要素だけ
        if not any(next((v for k, v in c.attrib.items() if local(k) == "href"), "") == "#" + ref for c in feature.iter()):
            continue
        seen.add((name, ref))
        lat, lon = points[ref]
        out.append({"name": name, "lat": round(lat, 5), "lon": round(lon, 5), "kind": kind, "pref": pref})
    if len(out) < 100:
        # 構造が想定と違うときの診断：要素名の頻度と先頭部分を出す
        from collections import Counter
        hist = Counter(local(e.tag) for e in root.iter())
        print("DIAG tags:", hist.most_common(40), file=sys.stderr)
        print("DIAG points:", len(points), file=sys.stderr)
        head = data[:3000].decode("utf-8", "ignore")
        print("DIAG head:", head, file=sys.stderr)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--core-data", required=True)
    args = ap.parse_args()

    ports: list[dict] = []
    for dataset, kind, page, fallbacks in DATASETS:
        got = False
        for url in find_zip_urls(dataset, page, fallbacks):
            try:
                blob = get(url)
            except Exception as e:  # noqa: BLE001
                print(f"{dataset}: {url} failed: {e}", file=sys.stderr)
                continue
            try:
                zf = zipfile.ZipFile(io.BytesIO(blob))
            except zipfile.BadZipFile:
                print(f"{dataset}: {url} is not a zip", file=sys.stderr)
                continue
            names = [n for n in zf.namelist() if n.lower().endswith((".xml", ".gml")) and "META" not in n.upper()]
            print(f"{dataset}: {url} → {len(names)} GML file(s): {names[:5]}", file=sys.stderr)
            count_before = len(ports)
            for n in names:
                try:
                    ports += parse_gml(zf.read(n), kind)
                except Exception as e:  # noqa: BLE001
                    print(f"{dataset}: parse {n} failed: {e}", file=sys.stderr)
            print(f"{dataset}: parsed {len(ports) - count_before} ports", file=sys.stderr)
            if len(ports) > count_before:
                got = True
                break
        if not got:
            print(f"{dataset}: no data", file=sys.stderr)

    # 同名・近接の重複を除く（300 m 以内で同じ名前）
    dedup: list[dict] = []
    for p in sorted(ports, key=lambda p: (p["kind"] != "fishing", p["name"])):
        if any(q["name"] == p["name"] and abs(q["lat"] - p["lat"]) < 0.003 and abs(q["lon"] - p["lon"]) < 0.004 for q in dedup):
            continue
        dedup.append(p)
    dedup.sort(key=lambda p: (p["lat"], p["lon"]))
    print(f"total {len(dedup)} ports ({sum(1 for p in dedup if p['kind'] == 'fishing')} fishing)", file=sys.stderr)
    if len(dedup) < 500:
        print("too few ports; not writing", file=sys.stderr)
        return 1
    payload = json.dumps(dedup, ensure_ascii=False, separators=(",", ":"))
    for path in (args.out, args.core_data):
        with open(path, "w", encoding="utf-8") as f:
            f.write(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
