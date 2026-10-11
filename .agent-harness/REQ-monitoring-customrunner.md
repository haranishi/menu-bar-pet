# REQ: 自作ランナー（複数コマ）＋システムモニタリング表示

対象リポ: menu-bar-pet（Swift 6 / SwiftPM / macOS 14+ / AppKit）
起票: 2026-08-29 ／ 本人決定: RunCat同型の「自作ランナー」を実装する（**方針転換**。削除した「1枚→細切り自動アニメ」とは別物＝ユーザーが複数コマを用意して回す方式。枚数が多いほど滑らか）。あわせてRunCat同様のシステム情報表示を追加。

## F1: 自作ランナー（カスタムキャラ）

- `PetCharacter` に `.custom`（displayName「自作ランナー」）を追加。**コマ画像が保存済みのときだけ**選択肢に出す
  （→ ハムスターと2択になり既存のキャラPickerが表示される）
- 取り込み: popoverに「自作ランナーを登録…」ボタン → NSOpenPanel で **PNG を複数選択**（2〜24枚・
  `allowsMultipleSelection`）。**ファイル名の昇順＝コマ順**。メッセージに「透過PNG推奨・権利を持つ画像のみ・
  このMac内だけで処理」と明記。1枚だけ選ばれたら「2枚以上必要」とstatusMessageで案内
- 保存: 新規 `CustomRunnerStore`（Application Supportのコンテナへコピー・全消し削除メソッド付き）。
  popoverに「自作ランナーを削除」ボタン（登録済みのときだけ表示。削除時に選択中なら hamsterWheel へ戻す）
- 描画: **素のコマ切替**（RunCat方式・変形やオーバーレイは一切掛けない）。18pt高にaspect fitで@2x描画。
  コマ index は Core の純関数 `frameIndex(phase:frameCount:)` で決定（phase×count の床・[0,count) を保証）
- 速度: 既存クロック（`cycleDuration(cpu:)`＝1周期で全コマを1巡）。**resting はコマ0で静止**（S7: アイドルは静か）。
  reduceMotion もコマ0固定
- fps: 既存の「1周期最低12コマ保証」ロジックのままでよいが、**コマ数が12超なら1周期あたり全コマ表示できるfps**
  （上限30）まで引き上げる: `fps = clamp(max(12, frameCount) / cycleDuration, 状態別下限, 30)`

## F2: システムモニタリング表示（popover内・表示のみ）

- popoverの負荷テストモードの下に「システム」区画を追加し、1秒更新で表示:
  - **メモリ**: 使用率%（`host_statistics64` のメモリ圧縮・アクティブ等から算出）
  - **ストレージ**: 起動ボリュームの空き容量（`volumeAvailableCapacityForImportantUsageKey`）
  - **バッテリー**: 残量%と電源接続（IOPowerSources）。バッテリー非搭載Macでは行ごと非表示
  - **ネットワーク**: 上下の転送レート（`getifaddrs` の累積バイトを1秒差分でB/s換算・単位自動: KB/s・MB/s）
- サンプリングは **popoverが開いている間だけ**動かす（常駐負荷を増やさない）。閉じたら停止
- 数値フォーマットは Core に純関数で置く（`formatBytesPerSecond` 等）→ テスト対象
- キャラの反応への接続（メモリで荷物を背負う等）は**今回やらない**（表示のみ）

## やらないこと

- 課金・キャラのロック（次REQで別途）／カスタムランナーへのオーバーレイ・変形／GIF・APNG対応（PNG連番のみ）
- メニューバーへの数値併記／ネットワーク以外のキャラ連動
- `git commit` / `git push`（**本人のみ。絶対に実行しない**）／RUBRIC類の編集

## 受け入れ条件

1. `./scripts/test.sh` 全パス（素の `swift test` は偽の緑＝禁止）。新規テスト:
   - `frameIndex(phase:frameCount:)` が全位相で [0, count)・単調・phase 1.0 で 0 に戻る
   - コマ数依存fpsが全域で「1周期に全コマ or 下限」かつ上限30以下
   - `CustomRunnerStore` の保存→読込→削除ラウンドトリップ（一時ディレクトリで）
   - バイト表示フォーマッタの境界（999B/s・1.0KB/s・1.0MB/s）
2. `./scripts/build-app.sh` 成功（sandbox衝突時は swift 呼び出しのみ `--disable-sandbox`・スクリプト変更禁止）
3. filmstrip を `.agent-harness/filmstrip-output/customrunner-r1/` に出力し、
   **strip-hamsterWheel-\*.png 全10枚が hamster-r4/ とバイト一致**（ハムスター無影響の証明）。
   カスタムランナーは合成ダミーコマ（コード生成の単色矩形3枚等）で1本 strip を出す
4. 報告: 変更ファイル一覧／test.sh実出力末尾／cmp結果／F1・F2の対応各1行
