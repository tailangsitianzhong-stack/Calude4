# Planet Pioneer

Godot 4.5で作っている、宇宙・惑星開拓ゲームの試作です。最初は青空の惑星の草原から始まり、木や岩、鉱石を道具で掘って集めます(宇宙へ出ていく方法はこれから決めます)。

## 遊び方

- 左側をなぞる:移動(PCではWASDか矢印キー)
- 右側をドラッグ:視点を回す(PCではマウスでドラッグ)
- 攻撃ボタン(押し続けると連続で振る):PCではFキー
- ジャンプ:Space
- アイテム欄(下中央):1 斧 / 2 ツルハシ(PCでは数字キー)
- 視点ボタン(右上):一人称と三人称を切り替え(PCではVキー)

斧で木を切ると木材、ツルハシで岩を掘ると石、鉱脈を掘ると鉄鉱石・銅鉱石・結晶が手に入ります。

## 構成

| ファイル | 内容 |
|---|---|
| `scripts/world.gd` | 地形(草原・丘・湖・山脈)、青空、太陽、草花 |
| `scripts/player.gd` | 一人称/三人称の開拓者、道具を振る動き |
| `scripts/harvestable.gd` | 木・岩・鉱脈(叩くと体力が減り、資源を落とす) |
| `scripts/touch_controls.gd` | スマホ用のスティック、ボタン、アイテム欄、照準 |
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
