"""レシピの難易度シミュレーション。

data/items.json のレシピから、目標ごとに必要な原料(木材・石・鉱石・結晶)を逆算し、
採取にかかるおおよその時間を出す。必要素材を調整するときに使う。

使い方: python3 tools/balance_sim.py
"""
import json
import math
import random
from collections import Counter, defaultdict
from pathlib import Path

DATA = json.loads((Path(__file__).resolve().parent.parent / "data" / "items.json").read_text(encoding="utf-8"))
RAW = ["wood", "stone", "iron", "copper", "crystal"]

# 1種類の物を作るレシピ(手元・作業台・製炉など)。ロケット段階では工業用製炉を使う前提
RECIPE = {}
for r in DATA["recipes"]:
    if r["id"] in RAW:
        continue
    if r["id"] not in RECIPE or r["station"] == "industrial_furnace":
        RECIPE[r["id"]] = r

# 採取の目安(main.gd の KINDS と同じ値)。移動時間は資源の密度から見積もった平均
NODES = {
    #          取れる物                  体力  移動秒
    "tree":    ({"wood": 3.5},            4.5,  8.0),
    "rock":    ({"stone": 3},             3.0, 12.0),
    "iron":    ({"iron": 3, "stone": 1},  5.0, 22.0),
    "copper":  ({"copper": 3, "stone": 1},5.0, 26.0),
    "crystal": ({"crystal": 1},           7.0, 35.0),
}
SWING = 0.42


def expand(goal: dict) -> tuple[Counter, Counter, float]:
    """目標の品物を原料まで分解。(原料, 途中で作る物の数, 製炉にかかる秒) を返す"""
    raw = Counter()
    made = Counter()
    stock = Counter()  # 余った中間素材(まとめて作ったときの残り)
    smelt = [0.0]

    def need(item: str, n: int) -> None:
        if item in RAW:
            raw[item] += n
            return
        use = min(stock[item], n)
        stock[item] -= use
        n -= use
        if n <= 0:
            return
        r = RECIPE[item]
        times = math.ceil(n / r["count"])
        made[item] += times * r["count"]
        stock[item] += times * r["count"] - n
        if r["station"] in ("furnace", "industrial_furnace"):
            smelt[0] += times * r.get("time", 3.0) / DATA["stations"][r["station"]].get("speed", 1.0)
        for k, v in r["cost"].items():
            need(k, v * times)

    for item, n in goal.items():
        need(item, n)
    return raw, made, smelt[0]


def gather_seconds(raw: Counter, power: int, rng: random.Random) -> float:
    """原料を集めるのにかかる秒数(副産物の石も数える)"""
    t = 0.0
    have = Counter()
    order = ["crystal", "copper", "iron", "tree", "rock"]
    for kind in order:
        drops, hp, travel = NODES[kind]
        main = next(iter(drops))
        while have[main] < raw[main]:
            p = power if kind != "crystal" else 2  # 結晶は鉄のツルハシが必要
            t += travel * rng.uniform(0.7, 1.3) + math.ceil(hp / p) * SWING + 1.0
            for k, v in drops.items():
                have[k] += v
    return t


GOALS = [
    ("1. 作業台・製炉・鉄の道具", {"workbench": 1, "furnace": 1, "iron_axe": 1, "iron_pickaxe": 1}, 1),
    ("2. 木の小屋(3x3・ドア・窓・家具)", {"wood_foundation": 9, "wood_wall": 9, "wood_door": 1, "window_wall": 2,
                                         "wood_roof": 9, "bed": 1, "table": 1, "chair": 1, "torch": 4}, 2),
    ("3. 工業用製炉と旋盤", {"industrial_furnace": 1, "lathe": 1}, 2),
    ("4. ロケットと発射台", {"rocket": 1, "launch_pad": 1}, 2),
]


def main() -> None:
    rng = random.Random(1)
    total_min = 0.0
    for name, goal, power in GOALS:
        raw, made, smelt = expand(goal)
        runs = [gather_seconds(raw, power, rng) for _ in range(20)]
        gather = sum(runs) / len(runs)
        # 製炉は採取と並行して動くので、待ち時間は半分と見る
        minutes = (gather + smelt * 0.5) / 60.0
        total_min += minutes
        print(f"{name}")
        print("  原料: " + "、".join(f"{k} {raw[k]}" for k in RAW if raw[k]))
        print(f"  製炉: {smelt / 60:.1f}分   採取: {gather / 60:.1f}分   → 約 {minutes:.0f} 分(累計 {total_min:.0f} 分)")
    print()
    raw, made, _ = expand({"rocket": 1, "launch_pad": 1})
    print("ロケットまでに作る主な中間素材: " + "、".join(f"{k} {v}" for k, v in made.most_common(12)))


if __name__ == "__main__":
    main()
