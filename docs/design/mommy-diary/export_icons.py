"""把设计稿里内联的 3 个新图标（本子/键盘/编辑）导出到 app/assets/icons。
与现有手绘图标保持一致：48dp 基准、透明底、外圈奶油色描边（深色底可见）。
用法：python3 docs/design/mommy-diary/export_icons.py（需 cairosvg）"""
import os, cairosvg
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
D = os.path.join(ROOT, "app/assets/icons/")
INK, CREAM = "#5A3E36", "#FFF8F0"  # 描边色与设计稿一致
ICONS = {
    "diary": ['<path d="M5 4.5h11.5a2.5 2.5 0 0 1 2.5 2.5v12.5H7.5A2.5 2.5 0 0 1 5 17z" fill="#FFE7DB"/>',
              '<path d="M5 17a2.5 2.5 0 0 1 2.5-2.5H19M9 8.5h6M9 11.2h4"/>'],
    "keyboard": ['<rect x="2.5" y="6" width="19" height="12.5" rx="3.2" fill="#FFF8F0"/>',
                 '<path d="M6 10h.1M9.5 10h.1M13 10h.1M16.5 10h.1M7 14.5h10"/>'],
    "edit": ['<path d="M4 20l1-4.2L15.6 5.2a2 2 0 0 1 2.9 0l.4.4a2 2 0 0 1 0 2.9L8.3 19.1z" fill="#FFE7DB"/>',
             '<path d="M13.8 7l3.3 3.3"/>'],
}
def svg(parts):
    body = "".join(parts)
    g = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
    halo = body.replace('fill="#FFE7DB"', f'fill="{CREAM}"').replace('fill="#FFF8F0"', f'fill="{CREAM}"')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="-1 -1 26 26">'
            f'<g {g} stroke="{CREAM}" stroke-width="3.6">{halo}</g>'
            f'<g {g} stroke="{INK}" stroke-width="1.9">{body}</g></svg>')
for n, parts in ICONS.items():
    s = svg(parts)
    open(D + f"svg/{n}.svg", "w").write(s)
    for sub, px in (("", 48), ("2.0x/", 96), ("3.0x/", 144)):
        cairosvg.svg2png(bytestring=s.encode(), write_to=D + sub + n + ".png", output_width=px, output_height=px)
    print("exported", n)
