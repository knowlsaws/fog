# 決定事項ログ

新しい決定は上に追加する。形式：日付 / 決定 / 理由 / 影響範囲。
Claude Code が設計判断で迷ったら、まずここに「提案」として書き、PR で問う。

## 2026-11-04 初期決定（要件・UI 確定時）

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| コードネーム「Fog」（潮目）。正式なアプリ名は開発者が後で決める | リポジトリ・ターゲット名に仮名が必要 | `project.yml` の表示名を変えるだけで済む構成にする |
| iOS 26.0 以上 | 釣行後レポートに Foundation Models（Apple Intelligence）を使う | 対象は iPhone 16 Pro のみなので制約なし |
| Swift 5 言語モード、strict concurrency は `minimal` | ループの速度優先。Swift 6 の並行性エラーで止まらないため | 後で上げてよい |
| Xcode プロジェクトは XcodeGen で生成 | Mac がなく `.xcodeproj` を手で保守できない。差分が読める | `project.yml` が正。`.xcodeproj` はコミットしない |
| 純粋ロジックは `Packages/Core`（Linux でテスト） | Claude Code は Linux 上で動くため、iOS ビルドなしで検証できる範囲を最大化する | 潮汐・天文・釣れ率・統計はここ |
| 署名は App Store Connect API キーによる自動署名（cloud signing） | Mac なしで証明書を扱うため。fastlane match はリポジトリ管理が増える | Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID` |
| 配布は TestFlight 内部テスト | 本人のみ利用。審査不要で実機に入る | App Store Connect にアプリレコードが必要 |
| 潮汐は気象庁「分潮一覧表」の60分潮を同梱して調和推算 | 全国・無期限・オフライン。海保の推算と同じ式 | 分潮のない地点は潮位表テキストで補う |
| 海況は Open-Meteo Marine API | 無料・キー不要・非商用可。気象庁波浪は有償配信 | CC BY 4.0 のクレジット表示 |
| ネット釣果情報は RSS 方式に縮小（COULD） | 公開 API がなく、スクレイピングは規約と安定性の面で不可 | 釣れ率には反映しない |
| 魚種判定モデルの学習は CI の macOS ランナーで行う | Create ML は Mac が必要 | `scripts/train_classifier/` と workflow を L6 で用意 |

## 提案（未決）

（なし）
