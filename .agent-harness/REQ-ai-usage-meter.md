# REQ: AI残量メーター（Claude Code／Codex の使用枠でキャラが走る）

対象リポ: menu-bar-pet（Swift 6 / SwiftPM / macOS 14+ / AppKit+SwiftUI）
起票: 2026-09-16 ／ 本人決定: 「RunCatの、ChatGPTやClaudeのトークン量が即見れる版」を **既存アプリの1機能** として作る。

## 0. ユーザーストーリー

- 個人開発者（第一顧客＝本人。Claude Code と Codex CLI を毎日・複数プロファイルで使う）として、
- **上限に当たる前に「そろそろ危ない」と作業中に気づきたい**。`/usage` を打ちに行く・設定画面を開く手間を無くしたい。
- メニューバーのキャラの走る速さと表情（汗・炎）で、Claude／Codex の **5時間枠・週枠のうち最も詰まっている枠** の使用率が分かり、クリックすると数値とリセット時刻が見える。

成功指標（本人ゲート）: 1週間使って `/usage` を打つ回数が減る・上限到達の不意打ちがゼロ。

## 0-1. UX 5階層（実装判断を導くために先に書く）

| 層 | 決めたこと | それで変わった実装 |
|---|---|---|
| 戦略 | 目的は「上限に当たる前に気づく」。週枠の方が不意打ちになりやすい | **駆動値＝有効な全プロバイダ・全枠の used% の最大値**（5時間枠だけにしない） |
| 要件 | 資格情報（キーチェーン・Cookie）に一切触れない。設定の手間を最小にする | Claude＝公式 statusLine の JSON を受ける／**Codex＝設定不要**（sessions の JSONL を読む。Stop フックは採らない） |
| 要件 | 非エンジニアでも連携できる | Claude 連携は **popover の1ボタン＋確認ダイアログ**。シェルや jq・python を要求しない → statusLine コマンドは **アプリ自身の `--statusline` モード** |
| 構造 | 「キャラを動かす指標」はキャラの反応源＝最重要設定なので上に。連携設定は初回だけ使うので下に | popover の並び: 見出し → 指標切替 → キャラ → AI残量（プロバイダ別）→ 連携 → 負荷テスト → システム |
| 骨格 | データ無しは「エラー」ではなく初回状態 | 無データ時はキャラが休息（0%）＋「Claude Codeで1回応答が返ると表示されます」の案内文 |
| 表層 | しきい値の意味は既存キャラ状態に委ねる（75%汗・90%炎） | AI モードは **`Sensitivity.standard` のしきい値 [20,50,75,90]** を使う（CPU の「敏感」固定はそのまま） |

→ 5階層を通した結果、当初案から **6箇所** の実装判断が変わった（駆動値の定義／Codex 設定不要化／`--statusline` をバイナリで／popover 配置／無データ状態の扱い／AI モードのしきい値）。

## 1. データソース（Core・純関数・テスト対象）

新規ディレクトリ `Sources/MenuBarPetCore/AIUsage/`。Foundation のみ。

### 1-1. モデル
- `AIUsageProvider: String, Codable, CaseIterable` = `.claudeCode`（表示「Claude Code」）／`.codex`（表示「Codex」）
- `AIUsageWindow`: `label: String`（"5時間"/"7日" など）、`usedPercentage: Double`、`resetsAt: Date?`
- `AIUsageSnapshot`: `provider`、`profileName: String`（設定ホームの basename。例 ".claude-work" ".codex-personal"）、`windows: [AIUsageWindow]`、`observedAt: Date`、`note: String?`（例: "クレジット切れ（workspace_member_credits_depleted）"）、`sourcePath: String`、`extras: [String: String]`（表示用。model／context% など任意）

### 1-2. `ClaudeStatusLineParser.parse(_ data: Data, observedAt: Date, profileName: String, sourcePath: String) -> AIUsageSnapshot?`
- 入力は Claude Code statusLine が stdin に渡す JSON そのもの（**公式スキーマ**: https://code.claude.com/docs/en/statusline を WebFetch で確認してから実装。`rate_limits.five_hour / seven_day{used_percentage, resets_at(epoch秒)}`。`spend_limit` があれば3つ目の枠として扱う）
- `rate_limits` が無い／空なら `nil`（Pro/Max 以外・初回応答前）。枠は個別に欠落しうる
- 任意で `model.display_name`、`context_window.used_percentage`、`cost.total_cost_usd` を `extras` に入れる（無ければ入れない）

### 1-3. `CodexSessionParser.parseLatest(text: String, observedAtFallback: Date, profileName:, sourcePath:) -> AIUsageSnapshot?`
- 入力は `~/.codex*/sessions/YYYY/MM/DD/rollout-*.jsonl` の **末尾テキスト**（呼び出し側が末尾 512KB を渡す。先頭行は途中で切れているので破棄）
- 行を末尾から走査し `"type":"event_msg"` かつ `payload.type == "token_count"` を探す
  - `payload.rate_limits.primary / secondary` が非 null → 枠にする。`window_minutes` から label（`< 1440` → "N時間"、それ以外 → "N日"。300→"5時間"、10080→"7日"）。`resets_at` は epoch 秒。`used_percent` は 0〜100
  - 最新の token_count の枠が両方 null で `rate_limit_reached_type` が非 null → **さらに古い行の枠を採用**しつつ `note` に理由を入れる（例: `workspace_member_credits_depleted` → 「クレジット切れ（workspace_member_credits_depleted）」）。古い行にも枠が無ければ枠空＋note のスナップショット
  - `observedAt` は行の `timestamp`（ISO8601・小数秒あり）。無ければ fallback
  - `payload.info.total_token_usage.total_tokens` があれば `extras["total_tokens"]`
- 実データ（2026-09-15・このMac）:
```
{"timestamp":"2026-09-15T13:28:48.436Z","ordinal":16,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":18548,"cached_input_tokens":12032,"cache_write_input_tokens":0,"output_tokens":155,"reasoning_output_tokens":0,"total_tokens":18703},"last_token_usage":{"input_tokens":18548,"cached_input_tokens":12032,"cache_write_input_tokens":0,"output_tokens":155,"reasoning_output_tokens":0,"total_tokens":18703},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1789492314},"secondary":{"used_percent":88.0,"window_minutes":10080,"resets_at":1789805930},"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,"spend_control_reached":null,"plan_type":"team","rate_limit_reached_type":null}}}
```
- 残高切れの実データ（2026-09-16）:
```
{"timestamp":"2026-09-16T03:49:29.337Z","ordinal":10,"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,"spend_control_reached":null,"plan_type":null,"rate_limit_reached_type":"workspace_member_credits_depleted"}}}
```

### 1-4. `AIUsageAggregator`（純関数）
- `effectiveUsedPercentage(_ window: AIUsageWindow, now: Date) -> Double`: `resetsAt <= now` なら **0**（枠が切り替わった）、それ以外は 0〜100 にクランプ
- `driveValue(snapshots: [AIUsageSnapshot], enabled: Set<AIUsageProvider>, now: Date) -> Double?`: 有効プロバイダの全枠の effective% の **最大値**。枠が1つも無ければ `nil`
- `bindingWindow(...)-> (AIUsageSnapshot, AIUsageWindow)?`: 最大値を出した枠（popover 見出しの「AI残量 88%（Codex 7日枠）」用）
- 表示フォーマッタ: `formatResetsAt(Date?, now:) -> String`（同日なら "14:30 リセット"、翌日以降なら "9/20 14:30 リセット"、過ぎていれば "リセット済み"、nil なら ""）、`formatCountdown` は不要

### 1-5. `AppSettings` 拡張（後方互換・既存の decodeIfPresent パターンで既定値）
- `metricSource: MetricSource`（`.cpu` 既定／`.aiUsage`）
- `aiUsageProviders: Set<AIUsageProvider>`（既定＝両方）

### 1-6. `ClaudeStatusLineInstaller`（純関数・Data/辞書 → Data）
- `install(settingsData: Data?, command: String) -> Data`: `statusLine` が無ければ `{"type":"command","command": command}` を追加。既に **別の** command があれば **`command --then '<元のcommand>'`** に連結して元の表示を維持（元 command は `--then` 引数として保存＝settings.json を見れば復元できる）。既に当アプリの command なら無変更（冪等）。他のキーは保持
- `uninstall(settingsData: Data, ourBinaryPath: String) -> Data`: 当アプリの statusLine なら、`--then` があれば元 command に戻し、無ければ `statusLine` を削除
- `isInstalled(settingsData: Data?, ourBinaryPath: String) -> Bool`
- 当アプリの command 文字列: `"<binaryPath>" --statusline`（binaryPath は `Bundle.main.executableURL` の実パス。空白があるのでクォート）

### 1-7. パス規約（固定・バンドルIDに依存させない）
- 使用量 JSON の置き場: `~/Library/Application Support/MenuBarPet/AIUsage/claude-<profile>.json`。環境変数 `MENUBARPET_USAGE_DIR` があれば優先（テスト用）
- Claude 設定ホームの探索: `~/.claude` と `~/.claude-*`（ディレクトリで `settings.json` を含むもの）。profile = basename。**`~/.claude.json` は除外**
- Codex ホームの探索: `~/.codex` と `~/.codex-*`（`sessions/` を含むディレクトリ）。profile = basename
- 探索の絞り込みは純関数 `discoverConfigDirectories(in homeDirectory: URL, using: FileManager)` として Core に置き、一時ディレクトリでテストする

## 2. アプリ側（Infrastructure／Presentation）

### 2-1. `--statusline` モード（`MenuBarPetMain`・NSApplication を起動しない・`--self-test` と同列）
- stdin を全部読む → `MENUBARPET_USAGE_DIR`（既定 1-7）に `claude-<profile>.json` を **アトミックに**書く（profile = `basename(${CLAUDE_CONFIG_DIR:-~/.claude})`）。JSON でなくても素通し保存はしない（パース失敗は stderr に1行・exit 0）
- `--then "<cmd>"` があれば `/bin/sh -c "<cmd>"` に **同じ JSON を stdin で渡し**、その stdout をそのまま出力（元の statusLine 表示を維持）。無ければ Core の `formatStatusLine(snapshot)` の1行（例: `Claude 5時間 23% · 7日 41%`。`rate_limits` 無しなら空文字）を出力
- 常に exit 0（statusLine を壊さない）。1秒以内に終わること

### 2-2. `--ai-usage-dump` モード（検証用・GUI 不要）
- 探索したプロファイルとスナップショットを人間可読で標準出力（provider／profile／各枠 %／resets／observedAt／note／sourcePath）。無ければ「(none)」。**Fable が実データで受け入れ確認に使う**

### 2-3. `AIUsageRepository`（@MainActor・ObservableObject）
- `snapshots: [AIUsageSnapshot]`、`lastRefreshedAt`、`refresh()`。Claude は 1-7 の JSON を読む。Codex は各ホームの `sessions/` から **日付ディレクトリ降順で最新2日分**の `rollout-*.jsonl` を mtime 降順に見て、新しい方から最大3ファイルの末尾 512KB を `CodexSessionParser` に渡し、`observedAt` 最新のスナップショットをプロファイルごとに1つ採用。`(path, mtime, size)` が変わらないファイルは再パースしない
- 更新間隔: AI モード中または popover 表示中は **15秒**ごと。それ以外は止める（常駐負荷を増やさない）

### 2-4. `PetViewModel` の変更
- `metricSource` を持ち、`sample()` で `.cpu` なら従来どおり `cpuSampler.readUsage()`、`.aiUsage` なら `AIUsageAggregator.driveValue(...)`（nil → **0**）を状態機械へ流す。AI モードのしきい値は `Sensitivity.standard`（CPU は現行の `.sensitive` 固定のまま）
- `debugOverrideUsage`（負荷テスト）は両モードで有効
- `cpuUsage` プロパティ名はそのまま「駆動値」として使ってよい（StatusItemController／PetMotion 無改造で済ませる。docコメントで意味を明記）。`accessibilitySummary` はモードに応じて「CPU 23パーセント」／「AI残量 88パーセント」
- 切替・プロバイダ有効化は `AppSettings` に保存

### 2-5. popover（`PopoverView`）
- 見出し行: 状態名＋「CPU 23%」または「AI残量 88%（Codex 7日）」
- **指標切替**: `Picker("動かす指標")` segmented「CPU／AI残量」＝キャラPickerの上
- **AI残量セクション**（見出し「AI残量」）: スナップショットごとにブロック。1行目「Claude Code（.claude-work）」、続く行は既存 `systemRow` 流用で「5時間 ｜ 23%・14:30 リセット」「7日 ｜ 41%・9/20 09:00 リセット」。`note` があれば caption で赤系 secondary。末尾に「更新 12:49」。プロバイダのオン/オフは Toggle（両方オフは不可＝最後の1つは無効化できない）
  - 無データ: 「まだデータがありません。Claude Code で1回応答が返ると表示されます／Codex はセッションログから自動で読み取ります」
- **連携セクション**: Claude 設定ホームごとに「.claude-work ｜ 設定済み／未設定」＋ボタン「連携する…」「解除」。押すと `NSAlert`（何を変更するか＝`settings.json` の statusLine を本アプリに向ける／元の設定は `settings.json.menubarpet-backup-<yyyyMMdd-HHmmss>` に保存／既存の statusLine は引き継いで表示を維持）→ OK で実行 → `statusMessage` で結果。Codex は「設定不要（セッションログを読み取り）」と1行
- 既存の負荷テスト・システム・終了はそのまま下へ

## 3. やらないこと
- キーチェーン／Cookie／`api.anthropic.com/api/oauth/usage`／`chatgpt.com` へのアクセス、ネットワーク通信全般
- Codex の Stop フック・`codex app-server` RPC（将来の別REQ）
- 新しいキャラ状態（「疲れて座る」）・描画の変更・RUBRIC 類の編集
- **このMacの `~/.claude*/settings.json` を開発中に書き換えること**（連携は本人がアプリから実行する。テストは一時ディレクトリだけ）
- `git commit` / `git push`（**本人のみ。絶対に実行しない**）／既存の未コミット変更を戻すこと

## 4. 受け入れ条件
1. `./scripts/test.sh` 全パス（`Tests/MenuBarPetCoreTests/main.swift` の件数ガードを更新。素の `swift test` は偽の緑＝禁止）。新規テスト（最低）:
   - statusLine JSON: 2枠パース／`rate_limits` 無し→nil／片枠欠落／extras
   - Codex JSONL: 上の実データ2行＋ダミー数行で「最新の残高切れ行を飛ばして直前の枠を採用＋note」／label 300→"5時間"・10080→"7日"／timestamp パース／末尾の切れた行を無視
   - Aggregator: `resetsAt` 経過→0／複数スナップショットの最大／無効プロバイダ除外／空→nil／bindingWindow
   - Installer: 無→追加／他 command→`--then` 連結／冪等／uninstall で復元・削除／他キー保持
   - AppSettings: 旧 JSON（新キー無し）→ 既定値
   - 探索: 一時ホームに `.claude`（settings.json あり）・`.claude-work`・`.claude.json`（ファイル）・`.codex-work/sessions` を作って正しく拾う
   - `formatStatusLine`／`formatResetsAt` の境界
2. `./scripts/build-app.sh` 成功
3. 描画無影響の証明: `swift run -c release --disable-sandbox MenuBarPet --filmstrip .agent-harness/filmstrip-output/aiusage-r1` を出力し、**同名ファイルが `shiba-r2/` と全てバイト一致**（`cmp` の結果を報告）
4. CLI スモーク（実行して出力を報告）:
   - `printf '<statusLine fixture JSON>' | MENUBARPET_USAGE_DIR=$(mktemp -d) .build/release/MenuBarPet --statusline` → ファイル生成＋1行出力
   - `.build/release/MenuBarPet --ai-usage-dump` → このMacの `.codex-work`／`.codex-personal` のスナップショットが出る（Claude はまだ連携前なので (none) で正しい）
5. 報告: 変更ファイル一覧／test.sh 実出力末尾／cmp 結果／スモーク出力／REQ の各項目の対応1行／未対応・迷った点

---

## 追記 2026-09-16（本人指示）: F5 メニューバー数値表示（Claude／Codex × 短い枠／長い枠を常時見せる）

本人の言葉: 「Claude CodeとCodexどっちも見たい。週制限と5時間ごとの制限もどっちも見たい」＝キャラの速さ（最大値1つ）だけでは足りず、**4つの数字がクリックなしで見えること**が要件。

### 仕様
- `NSStatusItem` を可変長にし、キャラ画像の**右**に 2 行の小さな文字（`NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)`・`labelColor`・2行が 22pt に収まる行間）を `attributedTitle` で出す。`imagePosition = .imageLeading`。**キャラ画像の描画・サイズは一切変えない**（filmstrip 一致で証明）
- 1 行＝1 プロバイダ。形式は `Claude 23 41` / `Codex  17 88`（名前を 6 桁で左寄せ・数字は短い枠→長い枠の順・%記号なし・実効値＝`resets_at` 経過は 0）。枠が 1 つしか無ければ片方 `--`、データ無しは `Claude  --  --`（連携していないことに気づける）。上限到達（5時間以内の `rate_limit_reached_type`）が有効なプロバイダは `Codex  上限` にする
- プロバイダに複数プロファイルがあるときは、**実効%の最大が最も大きいプロファイル**の枠を出す（駆動値と同じ「いちばん詰まっている方」）。ツールチップに全プロファイル・全枠・リセット時刻を列挙する
- 表示条件: `metricSource == .aiUsage` かつ新設定 `showsMenuBarReadout`（既定 **true**）。CPU モードでは出さない（長さは 44 に戻す）。popover の「AI残量」セクションに Toggle「メニューバーに数値を表示」を置く。`AppSettings` に後方互換で追加
- 更新: `AIUsageRepository` の更新（15秒）と設定変更のたびに描き直す。`accessibilitySummary` にも同じ 4 数字を含める
- 文字列の組み立ては Core の純関数 `MenuBarReadout.rows(snapshots:enabled:now:) -> [String]`（＋ tooltip 用 `MenuBarReadout.tooltip(...)`）に置いてテスト（枠 2 つ／1 つ／無し／上限／複数プロファイルの選択／CPU モードで空）

### 受け入れ
1. `./scripts/test.sh` 全パス（件数ガード更新）／`./scripts/build-app.sh` 成功・警告 0
2. filmstrip `aiusage-r4` が `shiba-r2` と 210 枚バイト一致
3. `--ai-usage-dump` の末尾に `menubar:` として 2 行の実出力（実データで `Codex` 行が出ること・`Claude  --  --`）
4. GUI 起動 5 秒クラッシュ無し
