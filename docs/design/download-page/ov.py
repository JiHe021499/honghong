from PIL import Image,ImageDraw,ImageFont
f=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',40)
m=['ios','android','wechat','beta-ios'];L=['移动端 · iOS','移动端 · 安卓','微信内打开','内测版 · 移动端']
W=2*1440+120; ims=[Image.open(f'screens-mobile-{x}.png').resize((585,1266)) for x in m]
d=[Image.open(f'screens-desktop-{x}.png') for x in ['release','beta']]
H=80+1266+60+80+900+60
o=Image.new('RGB',(W,H),'#EFE7DE');g=ImageDraw.Draw(o)
for i,im in enumerate(ims):
  x=40+i*(585+148); g.text((x,20),L[i],font=f,fill='#3D3A45'); o.paste(im,(x,80))
for i,im in enumerate(d):
  x=40+i*(1440+40); y=80+1266+60; g.text((x,y),['桌面端 · 正式版（二维码为主视觉）','桌面端 · 内测版'][i],font=f,fill='#3D3A45'); o.paste(im,(x,y+60))
o.save('overview.png')
