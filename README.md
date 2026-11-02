# Planet Pioneer

Godot 4.5で作っている、宇宙・惑星開拓ゲームの試作です。最初は青空の惑星の草原から始まり、木や岩、鉱石を道具で掘って集めます(宇宙へ出ていく方法はこれから決めます)。

## 遊び方

- 左側をなぞる:移動(PC: WASD)/ 右側をドラッグ:視点(PC: マウス)
- 攻撃ボタン(押し続けると連続):木を切る・岩や鉱石を掘る(PC: F)
- 設置できる物を持つと攻撃ボタンが「設置」になり、視線の先に見本が出る(緑なら置ける)
- 斧かツルハシで設置物を狙うと、攻撃ボタンの左上に「回収」ボタン(PC: R)
- 設備に近づくと、その上に「〜を使う」ボタン(PC: G)
- 右上:持ち物(PC: E)・視点切替(PC: V) / 左上:設定(感度・タイトルに戻る、PC: Esc)

### 進め方

1. 素手のクラフトで作業台を作る(木材・石・鉄鉱石 各6)
2. 作業台で製炉(石20)を作り、鉄鉱石を鉄にする → 鉄の斧・鉄のツルハシ(結晶は鉄のツルハシでないと掘れない)
3. 板材・石レンガで土台・壁・ドア・窓・屋根を作って家を建てる(2m のマス目にそろう)
4. 工業用製炉(製炉のアップグレード)で鋼鉄・ロケット燃料、旋盤で歯車・ネジ・パイプなどの工業用品
5. 部品を組み立ててロケットを作り、発射台の上に置く

作業台のレシピは50種類。必要素材は `tools/balance_sim.py` で採取時間を見積もって決めた(目安: 拠点5分、小屋13分、工業設備24分、ロケット73分)。

## 構成

| ファイル | 内容 |
|---|---|
| `scripts/world.gd` | 地形(草原・丘・湖・山脈)、青空、太陽、草花 |
| `scripts/player.gd` | 一人称/三人称の開拓者、道具を振る動き |
| `scripts/harvestable.gd` | 木・岩・鉱脈(叩くと体力が減り、資源を落とす) |
| `data/items.json` | アイテム・レシピ・設備の定義(難易度の調整はここ) |
| `scripts/item_db.gd` | data/items.json の読み込み |
| `scripts/build_manager.gd` | 設置物の置き場所(マス目へのスナップ)と見た目・当たり判定 |
| `scripts/station.gd` | 設置した設備(製炉は時間をかけて作る) |
| `scripts/title_screen.gd` | タイトル画面 |
| `shaders/water.gdshader` | 湖の水面(深さで色が変わり、岸に泡) |
| `tools/balance_sim.py` | レシピの難易度シミュレーション |
| `scripts/inventory.gd` | 持ち物(アイテム欄6枠+かばん18枠、素材は100個で1枠) |
| `scripts/touch_controls.gd` | スマホ用のスティック、ボタン、アイテム欄、持ち物画面、照準 |
| `scripts/main.gd` | 資源の配置、持ち物、画面表示などゲーム全体 |
| `assets/models/` | Blenderで作ったモデル(.glb)。`assets/blender/pioneer.blend` はBlenderで開いて編集できます |
| `tools/blender/make_assets.py` | モデルを作るBlenderスクリプト |
| `tools/blender/preview.py` | キャラクターの確認用画像を書き出すスクリプト |
| `web/shell.html` | スマホのブラウザで遊ぶための読み込みページ |
| `tools/build_web.sh` | Web版を書き出して `build/artifact/` にまとめる |
| `tools/make_font.py` | 使っている文字だけを含む日本語フォントを作る |

## モデルを作り直す

```
blender --background --python tools/blender/make_assets.py -- assets/models
```

画面に出す日本語を増やしたら `tools/make_font.py` でフォントを作り直してください(作り直さないと新しい文字が表示されません)。

## PCで開く場合

Godot 4.5以降で `project.godot` を開けば、そのまま編集・実行できます。

## 確認用の開始位置(Web版)

URL の末尾に `#lake`(湖のそば)、`#house`(見本の小屋の前)、`#bench`(作業台を開いた状態)を付けると、その状態から始まる。
