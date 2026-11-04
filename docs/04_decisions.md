# 決定事項ログ

新しい決定は上に追加する。形式：日付 / 決定 / 理由 / 影響範囲。
Claude Code が設計判断で迷ったら、まずここに「提案」として書き、PR で問う。

## 2026-11-04 実機フィードバック 1（ホーム・釣り場）

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| ホームの釣れ率の円は常に画面中央に置き、魚種別の数字は右側に重ねる | 魚種別の数字が無いときに円が左にずれていた | `HomeView.scoreArea` を ZStack に |
| 先の推移と潮位曲線は 1 枚のグラフに統合し、左軸に 0〜100 を出す。潮位は下の帯（4〜40）に写して満干の時刻を点に付ける | 2 段で小さく、何のグラフか分かりにくかった | 高さを 32% → 40%。UI 設計 §3 を更新 |
| チップは「アイコン・値・意味」の 3 段。値は次の出来事の時刻（満潮 23:50、朝マズメ 5:44）か今の数値（4 m/s、9°）。残り時間（11:03）は出さない | 「マズメまで 11:03」が時刻と紛らわしかった | `HomeViewModel.Chip` に `value/label` |
| 釣り場地図は表示範囲の漁港・港を MapKit（`MKLocalSearch`「漁港」「港」）で探してグレーの点に出し、カードの「登録」で自分の釣り場にする。拡大すると各点がホームと同じ釣れ率の円になる | 釣行前は登録釣り場が無く地図が空だった。よく行く漁港を先に登録したい | 検索は Apple Maps への問い合わせ（地図タイルと同じ経路）。完全ローカル原則の例外として L13 の全国検索と同じ扱い。候補はストアに保存せず、登録したものだけ `Spot` にする |

## 2026-11-04 L16 実機総合検証（開発者）への引き渡し

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| L1〜L15 は CI 緑を確認して Claude Code がマージした（開発者の指示）。実機確認は `docs/06_device_verification.md` にまとめ、ループごとではなく一括で行う | 開発者が Mac を持たず、TestFlight での確認は丸一日の釣行を含むため、ループごとに待つと止まる | 状態表は `review` のまま。確認できた項目から `done` にする。問題は `feedback` Issue |
| 初回起動のダミー釣行（函館港・アイナメ）のシードを外す。すでに入っている端末では起動時に 1 回だけそのダミーを削除する | L1 の確認用だった（決定ログ参照）。実データと混ざると分析が歪む | 魚種カタログのマージは残す（`SampleSeeder` → `CatalogSeeder`） |
| 魚種判定モデル（`FishClassifier.mlmodelc`）は未同梱で出荷する。候補なしのとき撮影は魚種空欄で成立する | 学習用写真が開発者の手元にしかない。完全ローカル原則で写真はリポジトリに置かない | `scripts/train_classifier/README.md` の手順で CI（macOS）で学習し、生成物を `App/Resources/Models/` に置くと有効になる |
| `testflight` ワークフローは `concurrency` で直列化する | エクスポート時に Xcode が App Store Connect の最新ビルド番号 +1 を自動採番する（`manageAppVersionAndBuildNumber`）。main への push が続くと同じ番号で 2 本上がり、後の方が Redundant Binary Upload で失敗した（run 20, 26） | 後の run は前の run の完了を待ってから走る。失敗した run は Re-run すれば次の番号で上がる |

## 2026-11-04 L14 ウィジェット・ロック画面・通知

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| ウィジェットはアプリが App Group に書き出す `WidgetSnapshot`（15 分刻みの釣れ率・潮位・イベント・記録中フラグ・タックル）からタイムラインを組む。拡張側では計算しない | 拡張のメモリ・実行時間の制限内で確実に 15 分更新する。予報範囲（48 時間以上）の間はアプリを開かなくても正しい | ホームの推移を計算するたびに `WidgetSync.publish` で書き出す。釣行の開始・終了・タックル切替は部分更新 |
| アプリと拡張で共有するコードは `App/Shared/`（両ターゲットのソースに含める）。`FogShared` が App Group の UserDefaults とスナップショットの置き場 | フレームワーク化せずに Intent と共有ストアを両方でコンパイルする最小構成 | 共有キー：`fog.currentTackle`（タックル）、`fog.pendingHookLost`（針ロストの待ち行列） |
| タックルの現在値は App Group の UserDefaults に移す | ウィジェットの「タックル切替」をアプリを開かずに成立させる（F-14） | `CaptureService.currentTackle` は `FogShared` を読む |
| ウィジェットの「針ロスト」は時刻だけを待ち行列に入れ、アプリが次に前面に来たときに釣行・位置を補って `HookEvent` にする | 拡張から SwiftData/CloudKit ストアを書かない（同期と競合を避ける）。位置は釣行の軌跡から補える | 釣行中でなければ捨てる（針ロストは釣行の中でだけ意味がある） |
| ウィジェットの「撮影」とロック画面は URL スキーム `fog://capture` で開く。カメラコントロールは `CameraCaptureIntent` でアプリを起動する（LockedCameraCapture 拡張は作らない） | 撮影画面は 1 つ（§5）。拡張を分けると ARKit・LiDAR の撮影体験を二重に持つことになる | ロック中は端末のロック解除を挟む |
| ピーク通知は `PeakNotificationPlanner`（Core）で判定：登録釣り場・今日・80 以上・ピーク開始の 1 時間前。予約済みで未発火なら差し替え、発火後は同日 2 回目を出さない | 「1 日 1 回」を守りつつ、予報更新で時刻が動いたときは追従する | 通知 ID は `peak.<日付>` |
| 記録更新の通知は `CaptureService.persist` でアプリが前面でないときだけ出す | 撮影直後はシートで見せる（§8） | 標準カメラ写真の取り込み（釣行終了時）で主に鳴る |

## 2026-11-04 L15 設定・データ管理

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 設定は 6 項目の入口を 1 画面に収め、各項目は子ページで完結させる | 「全画面は縦スクロールなし」の原則を設定にも適用する | 子ページはいずれも項目数が少なく 1 画面に収まる |
| エクスポートは Core の `ExportBundle`（JSON、`FogJSON` 形式）と `CSVExport`（釣果・釣行・スナップショットの 3 表）で生成し、App 側の `DataManager` がファイル化・共有する | 書式は Linux でテストできる。復元は同じ JSON を読む | 復元は同じ ID を上書き、無いものは追加（重複しない） |
| 写真付き ZIP は `NSFileCoordinator(.forUploading)` でフォルダを zip 化する | 追加ライブラリなし。写真はフォトライブラリから書き出して `photos/` に入れる | 写真が多いと時間がかかるので進捗を出す |
| 通知のオンオフは `NotificationSettings`（UserDefaults、既定オン）で種類ごとに持ち、送信側で確認する | 設定画面と送信側で同じ判定を使う | L14 の記録更新・ピーク通知も同じ仕組みを使う |
| 全データ削除後に `Species.initialCatalog` を再マージし、サンプル釣行は再シードしない | 図鑑と判定の候補が空にならないようにする。削除は分析に即時反映 | 設定のキャッシュ・修正履歴・タックル選択も消す |
| RSS の登録（F-27）は情報源ページに置き場所だけ用意し、実装は L17 | COULD 要件。設計上の位置を確定するため | 情報源ページには Open-Meteo（CC BY 4.0）と Apple Weather の帰属、気象庁潮位表の出典を出す |

## 2026-11-04 L4〜L13（記録が抜けていた分をまとめて追記）

### L4 釣行セッション自動検出

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 検出は Core の `SessionDetector`（状態機械：idle → candidate → active → cooldown）で行い、位置の取得と通知だけを App 側（`SessionDetectionService`）に置く | しきい値の挙動を Linux の GPX フィクスチャで再現テストできる | 感度 3 段階は `DetectionSettings.forSensitivity`。初期値は L16 の実測で確定 |
| 待機中は Visits＋大幅変更の監視、記録中だけ 100 m（釣行中）／25 m（移動中）の位置更新 | 10 時間で 20% 以下の電池消費（§7） | 立ち位置の軌跡は 2 分・20 m の低頻度 |
| 立ち位置は 30 m メッシュの `Point` に丸める。経度刻みは行（緯度）ごとに固定 | 釣果・針ロストをポイント単位で集計する（ヒートマップ・根掛かりマップ） | `Mesh.key/center` |
| 釣り場名は MapKit の逆ジオコーディングで漁港・岸壁名を候補にし、取れなければ「釣り場」 | 自動登録でも名前が付く。変なときだけ釣り場詳細で変える（§7） | `ShoreOracle` |
| ランガン（終了から一定時間・距離内の再開）は同じ釣行にまとめる | 1 日の釣行が複数に割れると分析がぶれる | `runAndGunMaxGap/MaxDistanceM` |

### L5 撮影と LiDAR サイズ推定

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| サイズは ARKit の `smoothedSceneDepth` と Vision の前景マスク（`VNGenerateForegroundInstanceMaskRequest`）から、魚の両端を内部パラメータで逆投影して求める（Core の `LengthEstimator`） | 追加ハードなしで ±1〜2 cm。誤差モデルを持ち推定幅を記録に残す | 計測枠は 0.3〜0.9 m で緑、外れると状態表示だけ変える（§5） |
| 連続撮影は `CatchMerger`（3 分以内・同魚種・近いサイズ）で 1 尾にまとめる | 撮り直しが尾数を増やさない（原則 1） | まとめた釣果は写真 ID を複数持つ |
| 写真はフォトライブラリに保存し、アプリはサムネイル JPEG だけ持つ | 完全ローカル。iCloud 写真は本人の iCloud | エクスポートの ZIP はライブラリから書き出す |
| 記録中の釣行が無ければ撮影位置で手動の釣行を始める | 撮影は釣行の証拠。自動検出が遅れても記録が成立する | `isAutoDetected = false` |

### L6 魚種判定

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 判定は Core ML 画像分類器（`FishClassifier.mlmodelc`）＋ `SpeciesCorrectionTable` の再ランク。モデルが無ければ候補なしで記録が成立する | 学習用写真は開発者の手元にしかない。写真はリポジトリに置かない（`data/fish/` は gitignore） | 学習は `train-classifier.yml`（macOS、Create ML）で行い、生成物を `App/Resources/Models/` に置く |
| 低確信度のときだけ結果シートに候補 3 種を出し、1 タップで確定。修正は `confusions/confirmed` に記録して次回の並びに反映 | 原則 1（撮影以外は自動）と F-24 | 設定 > 判定 に修正件数を出す |

### L7 釣れ率エンジン（Core）

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 釣れ率は 50 を基準にしたルール加点（光 ±18、潮 ±12/±4、風 +4〜−20、波 +3〜−20、水温 +6〜−8、気圧 +4〜−3、月 +2）を 0〜100 に丸める | 釣果が無くても初日から動く。内訳が説明できる | `ScoreBreakdown` をホームの内訳に出す |
| 自分のデータは `PersonalModel`（条件バケットごとの log 比、±20、重み hours/(hours+40)）で上乗せ。1 時間以上のデータがあるときだけ使う | 釣れた条件を自動で学ぶ（原則 2）。少量データで暴れない | 削除が即時反映されるよう `AnalysisCache` 経由 |
| 推移は 15 分刻み。1 日分を 50 ms 以内（分潮の事前展開、日ごとの太陽計算のキャッシュ） | ホームとウィジェットで毎回計算する | `ScoreTimeline` / `ScoreEvents` |

### L8 統計・相関・レポート

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 分析（釣り場・魚種・時間帯×月・リグ・比較・記録判定）は Core の `Analytics` で保存データから毎回導出する | 記録と同時に更新（原則 2）。Linux でテストできる | 画面は `AnalysisCache` で結果を持つ |
| 釣行後レポートは Core の `ReportFacts/ReportTemplate` で事実と定型文を作り、App 側で Foundation Models（`LanguageModelSession`、10 秒でタイムアウト）に文章化させる。使えなければ定型文 | Apple Intelligence が無効・圏外でもレポートは付く | 通知の本文は要約 1 行 |
| 記録判定は推定幅を考慮（新記録の下限が既存最大の上限を超えたときだけ自己記録） | LiDAR 推定の誤差で「記録更新」が乱発しない | `Analytics.judge` |

### L9〜L13 画面

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| ホーム（L9）は 30 秒ごと・ストア変更時・釣り場切替で全部再計算する。釣り場は 記録中 → 選択中 → 現在地に最も近い登録釣り場 → 直近の釣行 の順で決める | ユーザー操作なしで今の釣り場の釣れ率が出る | 推移は今日 0 時から予報の範囲（最低 48 時間） |
| 撮影画面（L10）はロック画面・ウィジェット・カメラコントロール・ショートカットから URL スキーム `fog://` と App Intent で開く。タブ切替は `Router` 経由 | 撮影画面は 1 つだけ（§5） | `fog://capture` / `fog://home` / `fog://tackle` / `fog://hooklost` |
| ログ（L11）は上半分に釣行カード、下半分に分析カードの横スクロールで 1 画面に収める。編集操作は長押し削除だけ | §4 の実装メモ。エクスポートは設定側 | 削除は分析に即時反映 |
| 図鑑（L12）の 1 エントリは魚種名で識別する（`GuideEntry: Identifiable`、id = 魚種名） | 釣った魚種だけが並ぶので魚種名が一意 | 魚種の修正はシートから `CaptureService.setSpecies` |
| 釣り場（L13）はモノトーンの MapKit 地図に、釣行数で大きさが変わる点を置く。検索は `MKLocalSearch`（全国）。詳細のヒートマップはポイント単位の釣果数、根掛かりマップは針ロスト数 | §7 | 地図の見え方は実機確認 |

## 2026-11-04 L3 環境データ取得

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| スナップショットの組み立て・予報キャッシュ・1 時間ゲート・海上格子探索・Open-Meteo の応答解読は Core に置き、WeatherKit / URLSession / CMAltimeter / CMPedometer の薄いアダプタだけを App に置く | 「機内モードでも組み立てられる」「1 時間に 1 回を超えて叩かない」「陸扱いを回避する」を Linux の `swift test` で検証するため | iOS 側のテストターゲットは作らない |
| 活動量は HealthKit ではなく CoreMotion の CMPedometer で取る | 同じ歩数・距離が取れ、HealthKit の権限・Capability が不要 | 要件 §2「CoreMotion、HealthKit」のうち HealthKit は使わない |
| 外部 API への位置は 0.01°（約 1 km）に丸めて送る | 要件 §6「取得クエリに必要な精度に丸めて送る」 | キャッシュのキーも同じ丸め |
| Open-Meteo の陸扱いは中心→8 方位 × 2.5/5/10 km の 25 候補を近い順に探索し、最初に値が返った格子点を釣り場ごとに記憶する | 漁港内・湾奥の座標は null が返る | 2 回目以降は記憶した格子点に直接問い合わせる |
| 予報キャッシュは App Group のディレクトリに JSON で保存し、48 時間より古い値は捨てる | 圏外でも §2 の項目を補間で埋める。ウィジェット（L14）からも読める | `environment-cache.json` |
| 通信復帰後の実況差し替えは、釣行終了時に WeatherKit の過去時間別値を取り直し、`isForecast` のスナップショット・釣果環境の気象項目だけを置き換える | F-06。潮・月・天文は端末計算なので差し替え不要 | `EnvironmentService.backfill` |

## 2026-11-04 L2 天文計算と潮汐エンジン

| 決定 | 理由 | 影響 |
| --- | --- | --- |
| 太陽は NOAA の太陽位置アルゴリズム（日の出入 ±1 分）、月は Meeus 第47章の主要項（黄経 ±0.01°程度） | Foundation だけで実装でき、要件の精度（1分）を満たす | `Core/Astro/` |
| 月齢は国立天文台と同じ定義（直前の朔からの経過日数）。朔は太陽と月の黄経差 0° を二分法で求める | 平均朔望月からの概算では最大 ±0.5 日ずれ、要件の 0.1 を満たせない | `MoonCalculator.age(at:)` |
| 潮汐の分潮は Schureman 表記（T, s, h, p, N, p' の係数＋位相）で基本分潮を定義し、複合分潮は結合（V は和、f は積、u は和）で表す | 60 分潮を個別に表にするより誤りが少なく、検証もしやすい | `Core/Tide/Constituents.swift` |
| 気象庁の遅角 κ は「現地子午線基準」（分潮一覧表の注記）。天文引数はグリニッジ（UT）で評価し、分潮の種別 m × 地点経度 L を加えて現地の平衡潮引数にする | JST 基準とみなすと函館で RMS 6 cm、時差換算（ω·L/15）でも 3 cm だったが、m·L で函館 RMS 0.7 cm・東京 1.6 cm（最大 2〜5 cm）まで一致した | `TideStation.lagLongitudeDeg`（分潮一覧表の経度） |
| ノード因子 f, u は IHO の近似多項式（N の 1〜3 倍角） | Schureman の厳密式と cm 以下の差 | 18.6 年周期を毎回計算する |
| 分潮データは CI（`tide-data` ワークフロー）で気象庁から取得してコミットする。Claude Code の環境からは気象庁に届かない | データの再現性と年1回の更新を自動化する | `data/tide/harmonics.json` と Core 同梱コピー |
| 函館・東京の潮位表テキストをテストフィクスチャとして同じワークフローで取得し、推算値との差を CI で常に検証する | L2 受け入れ条件（数 cm・数分）を人手でなく CI が確認する | `TideEngineTests.testBundledHarmonicsAgainstJMATables` |

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
