# Fog — 釣りアプリ

iPhone 16 Pro 専用・本人利用のみ・完全ローカルの釣りアプリ。
「撮影以外は全自動」「釣果は自動分析」の2原則で、ループエンジニアリングにより実装する。

- 設計書: `docs/01_requirements.md`（機能要件）, `docs/02_ui_design.md`（UI設計、画像は `docs/ui/`）
- 進め方: `CLAUDE.md`（Claude Code 向けの指示）, `docs/03_loop_plan.md`（ループ計画と状態表）
- 決定事項: `docs/04_decisions.md` / 調査: `docs/research/data_sources.md`

## 構成

```
App/            iOS アプリ（SwiftUI, SwiftData, WidgetKit）— CI の macOS ランナーでのみビルド
Packages/Core   純粋ロジック（潮汐・天文・釣れ率・統計・モデル）— Linux で `swift test` できる
project.yml     XcodeGen 定義（.xcodeproj はコミットしない）
.github/        core-tests（Linux）/ ios-build（macOS）/ testflight（main → TestFlight）
scripts/        データ取得・CI 補助
data/tide/      気象庁の分潮データ（L2 で生成）
```

## 開発者（人間）の初期設定

`docs/05_setup_for_developer.md` を参照。
