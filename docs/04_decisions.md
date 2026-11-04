# 決定事項ログ

新しい決定は上に追加する。形式：日付 / 決定 / 理由 / 影響範囲。
Claude Code が設計判断で迷ったら、まずここに「提案」として書き、PR で問う。

## 2026-11-04 L0 feedback: TestFlight の署名を手動署名＋証明書の永続化に変更

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| TestFlight のアーカイブは自動署名（cloud signing）をやめ、`scripts/ci/asc_signing.py` が App Store Connect API で作った Apple Distribution 証明書と App Store 用プロファイルで手動署名する | 自動署名は毎回まっさらなランナーに新しい証明書を作り、8回目のビルドで Apple の証明書上限に当たって失敗した（PR #1 マージ後の build 8） | `-allowProvisioningUpdates` は使わない。Development 証明書・プロファイルは不要 |
| 証明書と秘密鍵は `scripts/ci/signing/distribution.p12.enc` に暗号化して CI がコミットし、以後再利用する。パスフレーズは `ASC_PRIVATE_KEY` の SHA-256 から導出 | Mac がなく .p12 を手で作れない。新しい Secret を増やさずに済む。公開リポジトリでも暗号化済みなら置ける | ワークフローに `contents: write` が必要（Workflow permissions は Read and write 済み） |
| プロファイルは実行のたびに API で削除→作成する | プロファイルには上限がなく、常に証明書と整合させられる | 名前は `Fog CI AppStore {bundle id}` |
| 上限に当たったときは `signing-admin` ワークフロー（list / revoke）で開発者が iPad から失効させる | developer.apple.com でも可能だが、ID の一覧と失効を同じ場所で済ませる | 失効は自動では行わない |

## 2026-11-04 L1 データモデルと永続化

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| Core の値型は型ごとに1ファイル（`Models/*.swift`）。9型すべて `Codable, Hashable, Sendable`、`Identifiable` | L1 の成果物定義どおり。JSON の往復テストと SwiftData との相互変換を型単位で追える | `Models.swift` は分割して削除 |
| JSON は `FogJSON`（ISO 8601 UTC ミリ秒、キーソート）に統一 | エクスポート／インポート（F-23）とフィクスチャ、SwiftData 内の埋め込み値で同じ表現を使う | 日付は `Date` の秒未満を ms に丸める |
| SwiftData のレコードは Core と別の型（`*Record`）にし、`uuid` 列で Core の `id` を持つ | `PersistentModel` の `id` と衝突させない。Core は Foundation だけに依存させる | 画面・サービスは `FogStore` を通して Core の値型で読み書きする |
| CloudKit 対応の制約を全レコードに適用：全属性に既定値、リレーションは optional、`.unique` なし | SwiftData の CloudKit 同期の要件 | 一意性は `FogStore` の upsert で保証する |
| 配列・入れ子（候補3種、写真ID一覧、軌跡、釣果時の環境）は JSON の `Data?` で埋め込む | CloudKit で配列属性を避ける。釣果時の環境は不変のスナップショットで、分析は Core 側で行うので行に分ける必要がない | 釣行中の定期スナップショットだけは時系列に引くため `EnvSnapshotRecord` として行にする |
| ストアは App Group コンテナ（`group.{prefix}.fog`）に置く。取れなければ Application Support | L14 のウィジェットから同じストアを読むため | シミュレータ（未署名）でも動く |
| CloudKit は Info.plist の `FogCloudKitContainerIdentifier`（`project.yml` の `iCloud.${BUNDLE_ID_PREFIX}.fog`）と iCloud サインイン状態が揃ったときだけ有効。失敗したらローカル → メモリ内へ落とす | 開発者がコンテナを作る前でもアプリは動く（L1 受け入れ条件）。起動を止めない | `UIBackgroundModes` に `remote-notification` を追加（CloudKit のプッシュ同期） |
| 分析は保存データから毎回導出する。計算結果を持つときは `AnalysisCache` 経由にし、`FogStore.revision` が進んだら全部捨てる | 削除が分析に即時反映される（§6） | L7・L8 は `AnalysisCache.value(_:store:compute:)` を使う |
| 初回起動時にダミー釣行（函館港・アイナメ 38cm）を1件シードする。消されても再シードしない | L1 受け入れ条件「再起動後も残る」を TestFlight で確認するため | L11（長押し削除）か L15（全データ削除）で開発者が消せる。シードのコードは L16 までに外す |
| 釣果・釣行は `tackle: TackleKind?`（種別）と `tackleID: UUID?`（登録タックル）の両方を持つ | タックル未登録でもウィジェットの「スピニング／ベイト」切替が成立する（F-14 の例外的入力は未入力でも記録が成立する原則） | 登録タックルは種別の補足情報 |
| 魚種は `Species.initialCatalog`（docs/species.md）を Core に持ち、起動時に `SpeciesRecord` へマージする | 判定モデル（L6）が同じリストを使う。釣果は標準和名の文字列で参照する | L6 でリストを更新するときは Core と docs/species.md を同時に直す |

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
