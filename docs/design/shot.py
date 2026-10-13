from playwright.sync_api import sync_playwright
import pathlib
u=pathlib.Path('design.html').resolve().as_uri()
with sync_playwright() as pw:
  b=pw.chromium.launch();pg=b.new_page(viewport={'width':390,'height':844},device_scale_factor=2)
  for i,s in enumerate(['home','rec','res','fb','log','night','ins'],1):
    pg.goto(u+'?s='+s);pg.wait_for_timeout(400);pg.screenshot(path=f'screens-{i}-{s}.png')
  pg=b.new_page(viewport={'width':3200,'height':1000},device_scale_factor=1);pg.goto(u)
  pg.add_style_tag(content='.wall{flex-wrap:nowrap}');pg.wait_for_timeout(400);pg.screenshot(path='overview.png',full_page=True)
  b.close()
