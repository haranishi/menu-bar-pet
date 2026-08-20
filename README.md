# MenuBarPet MVP

好きな画像をMacのメニューバーに置き、CPU負荷へ反応させるローカル検証版です。macOS 14以降、Apple標準フレームワークのみで動き、外部通信やアカウントはありません。

## すぐ試す

```bash
cd /Users/hara/Projects/menu-bar-pet
./scripts/build-app.sh
open dist/MenuBarPet.app
```

初回ビルド後はFinderで`dist/MenuBarPet.app`をダブルクリックしても起動できます。メニューバーのオレンジ色の猫をクリックし、「画像を選ぶ」からPNG・JPEG・HEICを登録してください。終了はポップオーバー右下の「終了」です。

ソースから直接起動する場合は`swift run MenuBarPet`、ロジック検証だけなら`swift run MenuBarPet --self-test`を使います。

## このMVPで確認できること

- Dockへ出ないメニューバー常駐と標準ペット
- CPUを1秒ごとに読み、休息・通常・疾走・汗・全力へ変える反応
- Core Animationによる低負荷な上下動と前傾
- 感度3段階、一時停止、Reduce Motionへの追従
- 権利を持つ画像1枚の選択、検証、縮小、ローカル保存
- 設定と画像の再起動後復元、標準ペットへの復帰

画像は`~/Library/Application Support/com.hara.MenuBarPet/`、設定はmacOSのUserDefaultsへ保存されます。CPU履歴、アプリ名、キー入力は保存しません。

## 現時点の範囲外

これは販売版ではなく企画のP1〜P2検証版です。自動背景除去・手動クロップ、ログイン時起動、StoreKit、複数ペット、署名・公証・App Sandbox付き配布は未実装です。登録画像は透明PNGを使うと最も自然に表示されます。

## 検証結果

- Swift 6.3.3 release build：成功
- `--self-test`：4テスト群合格
- 起動スモーク：23秒間クラッシュなし
- 参考値：安定時CPU 0.0%、常駐メモリ44,784KB

数値はApple Silicon実機での短時間`ps`計測です。製品判断にはInstrumentsによる長時間計測と、ノッチ・複数画面・スリープ復帰の手動試験が必要です。
