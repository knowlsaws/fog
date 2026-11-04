#!/usr/bin/env python3
"""気象庁「潮位表掲載地点一覧表」と各地点の「分潮一覧表」を取得し data/tide/harmonics.json を作る。

L2 で実装・検証する。L0 時点では骨組み（URL と出力形式の定義）のみ。
  一覧: https://www.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/station{year}.php
  分潮: 一覧ページの各地点行にある「分潮一覧表」リンク先（気象庁所管地点のみ）
"""
import argparse
import json
import sys

STATION_LIST_URL = "https://www.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/station{year}.php"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--year", type=int, required=True)
    p.add_argument("--out", default="data/tide/harmonics.json")
    args = p.parse_args()
    # TODO(L2): requests + HTML パースで一覧→各地点の分潮表を取得し、下の形式で保存する
    out = {"year": args.year, "source": STATION_LIST_URL.format(year=args.year), "stations": []}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"wrote {args.out} (stations: {len(out['stations'])}) — TODO(L2)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
