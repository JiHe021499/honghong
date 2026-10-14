from playwright.sync_api import sync_playwright
import pathlib
R=pathlib.Path('index.html').resolve().as_uri(); B=pathlib.Path('beta/index.html').resolve().as_uri()
M=[('mobile-ios',R,'ios'),('mobile-android',R,'android'),('mobile-wechat',R,'wechat'),('mobile-beta-ios',B,'ios')]
with sync_playwright() as pw:
  b=pw.chromium.launch()
  pg=b.new_page(viewport={'width':390,'height':844},device_scale_factor=2)
  for n,u,ua in M: pg.goto(u+'?ua='+ua);pg.wait_for_timeout(400);pg.screenshot(path=f'screens-{n}.png')
  pg.goto(R+'?ua=ios');pg.wait_for_timeout(300);pg.screenshot(path='screens-mobile-ios-full.png',full_page=True)
  d=b.new_page(viewport={'width':1440,'height':900})
  for n,u in [('desktop-release',R),('desktop-beta',B)]: d.goto(u+'?ua=desktop');d.wait_for_timeout(400);d.screenshot(path=f'screens-{n}.png')
  b.close()
