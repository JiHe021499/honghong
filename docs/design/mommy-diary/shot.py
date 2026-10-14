from playwright.sync_api import sync_playwright
import pathlib
u=pathlib.Path('design.html').resolve().as_uri()
ids=open('ids.txt').read().split()
with sync_playwright() as pw:
  b=pw.chromium.launch()
  pg=b.new_page(viewport={'width':390,'height':844},device_scale_factor=2)
  for i,s in enumerate(ids,1):
    pg.goto(u+'?s='+s);pg.wait_for_timeout(400);pg.screenshot(path=f'screens-{i:02d}-{s}.png')
  ov=b.new_page(viewport={'width':3000,'height':1000})
  ov.goto(u);ov.wait_for_timeout(600);ov.screenshot(path='overview.png',full_page=True)
  b.close()
