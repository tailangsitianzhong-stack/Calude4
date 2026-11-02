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
RAW = ["wood", "stone", "iron", "copper", "crystal", "sand", "cactus_fiber", "sandstone", "coal", "gold_ore",
       "sulfur", "obsidian", "ice", "clay", "pearl", "resin", "water_bucket", "lava_bucket", "hot_water"]

# 1種類の物を作るレシピ(手元・作業台・製炉など)。ロケット段階では工業用製炉を使う前提
RECIPE = {}
for r in DATA["recipes"]:
    if r["id"] in RAW:
        continue
    if r["id"] not in RECIPE or r["station"] == "industrial_furnace":
        RECIPE[r["id"]] = r

# 採取の目安(main.gd の KINDS と同じ値)。移動時間は資源の密度から見積もった平均
# 岩や鉱石は大きさがまちまち(小 0.5倍・普通・大 2倍・巨大 3.5倍)なので、平均の取れる量は約1.25倍
NODES = {
    #            取れる物                       体力  移動秒  地域
    "tree":      ({"wood": 3.5},                 4.5,  8.0, "grass"),
    "big_tree":  ({"wood": 8, "resin": 2},       10.0, 16.0, "forest"),
    "rock":      ({"stone": 3.7},                3.0, 12.0, "grass"),
    "iron":      ({"iron": 3.7, "stone": 1.2},   5.0, 20.0, "grass"),
    "copper":    ({"copper": 3.7, "stone": 1.2}, 5.0, 24.0, "grass"),
    "coal":      ({"coal": 3.7},                 4.0, 20.0, "forest"),
    "crystal":   ({"crystal": 1.2},              7.0, 32.0, "snow"),
    "sand":      ({"sand": 4},                   2.0, 12.0, "desert"),
    "cactus":    ({"cactus_fiber": 3},           2.0, 14.0, "desert"),
    "sandstone": ({"sandstone": 3.7},            3.0, 14.0, "desert"),
    "gold":      ({"gold_ore": 2.5, "stone": 1}, 7.0, 30.0, "desert"),
    "ice":       ({"ice": 3.7},                  3.0, 14.0, "snow"),
    "sulfur":    ({"sulfur": 3.7},               3.0, 22.0, "lava"),
    "obsidian":  ({"obsidian": 2.5},             8.0, 26.0, "lava"),
    "clay":      ({"clay": 3},                   2.0, 20.0, "grass"),
    "clam":      ({"pearl": 1},                  1.0, 30.0, "grass"),
    "water":     ({"water_bucket": 1},           0.0, 10.0, "grass"),
    "lava":      ({"lava_bucket": 1},            0.0, 15.0, "lava"),
    "spring":    ({"hot_water": 1},              0.0, 15.0, "lava"),
}
TIER = {"crystal": 2, "gold": 2, "obsidian": 3}
TRIP = 75.0   # 遠くの地域へ行って帰ってくる秒数(1つの段階で1回)
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
        for k, v in r.get("returns", {}).items():
            stock[k] += v * times
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
    trips = set()
    for kind, (drops, hp, travel, region) in NODES.items():
        main = next(iter(drops))
        while have[main] < raw[main]:
            p = max(power, TIER.get(kind, 1))
            if region != "grass" and region not in trips:
                trips.add(region)
                t += TRIP
            t += travel * rng.uniform(0.7, 1.3) + math.ceil(hp / p) * SWING + 1.0
            for k, v in drops.items():
                have[k] += v
    return t


GOALS = [
    ("1. 作業台・製炉・鉄の道具", {"workbench": 1, "furnace": 1, "iron_axe": 1, "iron_pickaxe": 1}, 1),
    ("2. 木の小屋(3x3・ドア・窓・家具)", {"wood_foundation": 9, "wood_wall": 9, "wood_door": 1, "window_wall": 2,
                                         "wood_roof": 9, "bed": 1, "table": 1, "chair": 1, "torch": 4}, 2),
    ("3. 工業用製炉と旋盤", {"industrial_furnace": 1, "lathe": 1}, 2),
    ("4. 冒険の装備(防寒・耐熱・潜水・鋼鉄の道具)", {"warm_coat": 1, "heat_suit": 1, "diving_mask": 1, "bucket": 1,
                                             "steel_pickaxe": 1}, 2),
    ("5. ロケットと発射台", {"rocket": 1, "launch_pad": 1}, 3),
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
