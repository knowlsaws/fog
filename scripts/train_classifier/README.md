# 魚種判定モデルの学習（L6）

Mac が無いので GitHub Actions の macOS ランナーで Create ML を動かす。

```
scripts/train_classifier/
  fetch_inat.py   iNaturalist の研究グレード・CC ライセンス写真を魚種ごとに集める（公開データ）
  train.swift     Create ML（MLImageClassifier）で学習し FishClassifier.mlmodel を書き出す
  evaluate.swift  テストセットで Top-1 / Top-3 を測る（受け入れ条件: Top-1 90%・Top-3 98%）
```

## データの置き方

```
data/fish/
  train/<標準和名>/*.jpg
  test/<標準和名>/*.jpg
```

- 公開データ: `python3 scripts/train_classifier/fetch_inat.py --out data/fish --per-species 200`（CI の `train-classifier` ワークフローが実行）
- 開発者の写真: iCloud Drive などに `<標準和名>/` ごとに置き、ワークフローの入力 `photos_url`（zip の URL）で渡す。**リポジトリには上げない**（`data/fish/` は .gitignore）
- 魚種のリストと学名は `docs/species.md`

## 実行

Actions → `train-classifier` → Run workflow。成功すると `App/Resources/Models/FishClassifier.mlmodel` と
`docs/classifier_report.md`（精度）をコミットする。精度が受け入れ条件に届かないときはコミットせず失敗する。

アプリはモデルが同梱されていなければ候補 3 種を低確信度で返す仮実装で動く（撮影は止まらない）。
