# 潮汐データ

- `harmonics.json` : 気象庁「分潮一覧表」から取得した全地点の60分潮（L2 で `scripts/fetch_jma_harmonics.py` が生成）。年1回更新。
- 形式: `{"year": 2026, "stations": [{"id": "HK", "name": "函館", "latitude": 41.78, "longitude": 140.72, "z0_cm": 123.4, "constituents": [{"name": "M2", "amplitude_cm": 87.3, "phase_deg": 231.5}, ...]}]}`
- ビルド時に `Packages/Core/Sources/Core/Data/` へコピーして同梱する。
