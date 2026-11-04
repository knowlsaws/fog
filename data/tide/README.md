# 潮汐データ

- `harmonics.json` : 気象庁「分潮一覧表」から取得した全地点の分潮（`scripts/fetch_jma_harmonics.py`）。
  `.github/workflows/tide-data.yml` が年1回（1月）と手動実行で更新し、`Packages/Core/Sources/Core/Data/harmonics.json` にも同じ内容を書いてコミットする。
- 形式（Core の `TideCatalog` と同じキー）:
  `{"year": 2026, "source": "...", "stations": [{"id": "HK", "name": "函館", "coordinate": {"latitude": 41.78, "longitude": 140.72}, "meanSeaLevelCm": 123.4, "constituents": [{"name": "M2", "amplitudeCm": 87.3, "phaseLagDeg": 231.5}, ...], "lagLongitudeDeg": 140.725}]}`
- 遅角 κ は現地子午線基準（`lagLongitudeDeg` は分潮一覧表に書かれた経度）。推算は `Core/Tide/TideEngine`（V_G + 種別×経度 + u − κ）。
- 検証用に函館・東京の潮位表テキスト（`Packages/Core/Tests/CoreTests/Fixtures/jma_tide_*.txt`）も同じワークフローが取得する。
