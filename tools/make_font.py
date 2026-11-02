"""スクリプト内で使っている文字だけを含む日本語フォントを作る(Web版の容量を小さくするため)。

使い方: python3 tools/make_font.py path/to/NotoSansJP[wght].ttf
必要: pip install fonttools
"""
import glob, subprocess, sys, tempfile
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

src = sys.argv[1]
chars = set(chr(c) for c in range(0x20, 0x7F)) | set("0123456789:・→()!?、。ー〜")
for p in glob.glob('scripts/*.gd'):
    chars |= set(open(p, encoding='utf-8').read())
chars = ''.join(sorted(c for c in chars if c >= ' '))
with tempfile.TemporaryDirectory() as d:
    bold = f'{d}/bold.ttf'
    instancer.instantiateVariableFont(TTFont(src), {"wght": 700}).save(bold)
    open(f'{d}/chars.txt', 'w', encoding='utf-8').write(chars)
    subprocess.run(['pyftsubset', bold, f'--text-file={d}/chars.txt', '--output-file=fonts/ui_font.ttf'], check=True)
print('fonts/ui_font.ttf を更新しました')
