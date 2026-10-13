from playwright.sync_api import sync_playwright
import pathlib
u = pathlib.Path('design.html').resolve().as_uri()
screens = [
  ('home', 'home'),
  ('home-feed', 'home-feed'),
  ('feed-end', 'feed-end'),
  ('home-sleep', 'home-sleep'),
  ('sleep-end', 'sleep-end'),
  ('home-diaper', 'home-diaper'),
  ('diaper-edit', 'diaper-edit'),
  ('home-burp', 'home-burp'),
  ('burp-end', 'burp-end'),
  ('home-saved', 'home-saved'),
  ('rec', 'rec'),
  ('res', 'res'),
  ('fb', 'fb'),
  ('night', 'night'),
  ('ins', 'ins'),
]
with sync_playwright() as pw:
  b = pw.chromium.launch()
  pg = b.new_page(viewport={'width': 390, 'height': 844}, device_scale_factor=2)
  for i, (sid, name) in enumerate(screens, 1):
    pg.goto(u + '?s=' + sid)
    pg.wait_for_timeout(500)
    path = f'screens-{i:02d}-{name}.png'
    pg.screenshot(path=path)
    print('ok', path)
  # overview: wide gallery of care-record related + key screens
  ov = b.new_page(viewport={'width': 4200, 'height': 1100}, device_scale_factor=1)
  ov.goto(u)
  ov.add_style_tag(content='.wall{flex-wrap:nowrap}')
  ov.wait_for_timeout(600)
  ov.screenshot(path='overview.png', full_page=True)
  print('ok overview.png')
  # focused care-flow strip
  care = b.new_page(viewport={'width': 2800, 'height': 1100}, device_scale_factor=1)
  care.goto(u)
  care.add_style_tag(content='''
    .wall{flex-wrap:nowrap}
    .cell{display:none !important}
    #c-home,#c-home-feed,#c-feed-end,#c-home-diaper,#c-home-saved{display:flex !important}
  ''')
  care.wait_for_timeout(500)
  care.screenshot(path='overview-care-flow.png', full_page=True)
  print('ok overview-care-flow.png')
  b.close()
