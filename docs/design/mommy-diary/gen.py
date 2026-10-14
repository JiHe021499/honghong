I='../../../app/assets/icons/3.0x/'
def ic(n,s=24): return f'<img class="hi" src="{I}{n}.png" style="width:{s}px;height:{s}px">'
K='#5A3E36'
def sv(p,s=22): return f'<svg class="hi" width="{s}" height="{s}" viewBox="0 0 24 24" fill="none" stroke="{K}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{p}</svg>'
KEY=lambda s=20: sv('<rect x="2.5" y="6" width="19" height="12.5" rx="3.2" fill="#FFF8F0"/><path d="M6 10h.1M9.5 10h.1M13 10h.1M16.5 10h.1M7 14.5h10"/>',s)
EDIT=lambda s=16: sv('<path d="M4 20l1-4.2L15.6 5.2a2 2 0 0 1 2.9 0l.4.4a2 2 0 0 1 0 2.9L8.3 19.1z" fill="#FFE7DB"/><path d="M13.8 7l3.3 3.3"/>',s)
TRASH=lambda s=18: sv('<path d="M4.5 7h15M9.5 7V4.6h5V7"/><path d="M6.4 7.2l1 12.3h9.2l1-12.3" fill="#FFE7DB"/><path d="M10.3 11v5M13.7 11v5"/>',s)
BOOK=lambda s=28: sv('<path d="M5 4.5h11.5a2.5 2.5 0 0 1 2.5 2.5v12.5H7.5A2.5 2.5 0 0 1 5 17z" fill="#FFE7DB"/><path d="M5 17a2.5 2.5 0 0 1 2.5-2.5H19M9 8.5h6M9 11.2h4"/><path d="M15.5 2.8l.6 1.3 1.3.2-1 .9.3 1.3-1.2-.7-1.2.7.3-1.3-1-.9 1.3-.2z" fill="#FF9874" stroke-width="1"/>',s)
CAT={'feed':('喂奶','care_feed','#FFE7DB'),'sleep':('睡眠','care_sleep','#E3EEF8'),'diaper':('尿布','care_diaper','#E6F4EA'),'mood':('情绪','cause_hold_me','#FFF0C9'),'other':('其他','tip','#F3EAE1')}
SB='<div class="notch"></div><div class="sb"><span>9:41</span><span>▂▄▆ ▮</span></div>'
cells=[]
def cell(id,title,inner,night=False):
  cells.append((id,f'<div class="cell" id="c-{id}"><b>{len(cells)+1} · {title}</b><div class="phone{" night" if night else ""}">{SB}{inner}</div></div>'))
TAB=f'<div class="tab"><div class="on"><i>{ic("tab_home")}</i>首页</div><div><i>{ic("tab_insights")}</i>规律</div><div><i>{ic("tab_family")}</i>家庭</div><div><i>{ic("tab_me")}</i>我的</div></div>'
# 1 existing home + entry card
HOME=f'''<div class="body">
<div class="hd"><div class="baby"><div class="av">{ic("avatar_baby",30)}</div><div><b>小米粒</b><small>出生第 23 天</small></div></div><div class="ic">{ic("night_mode",24)}</div></div>
<div class="status">{ic("care_feed",18)} 上次喂奶 <em>2小时40分</em>前 · {ic("care_sleep",18)} 已睡 <em>20分钟</em></div>
<div class="cryw"><button class="cry">宝宝在哭<span>点一下，帮你听听</span></button>
<div class="tg"><div class="sw"></div>自动监听哭声 · 已开启</div></div>
<div class="qg"><div class="q"><i>{ic("care_feed")}</i>喂奶</div><div class="q"><i>{ic("care_sleep")}</i>睡觉</div><div class="q"><i>{ic("care_diaper")}</i>换尿布</div><div class="q"><i>{ic("care_burp")}</i>拍嗝</div></div>
<div class="md-entry" onclick="go('{{T}}')"><div class="md-ico">{BOOK()}</div><div><b>妈咪日记<span class="md-new">新</span></b><small>{{S}}</small></div><span class="md-go">{ic("chevron_right",18)}</span></div>
<div class="sec">今天的记录<a>喂奶 / 睡觉 / 拍嗝：开始后计时</a></div>
<div class="tl">
<div class="tli"><div class="d" style="background:#E3EEF8">{ic("care_sleep")}</div>午睡 · 42 分钟<small>16:20</small></div>
<div class="tli"><div class="d" style="background:#FFE7DB">{ic("care_feed")}</div>母乳 · 左侧 15 分钟<small>15:00</small></div>
<div class="tli"><div class="d" style="background:#E6F4EA">{ic("care_diaper")}</div>换尿布 · 小便<small>14:45</small></div>
</div></div>{TAB}'''
cell('home','首页 · 新增「妈咪日记」入口（其余不变）',HOME.replace('{T}','first').replace('{S}','说一句话，帮你把今天记下来'))
cell('home-sum','首页 · 21:00 后入口显示今日小结',HOME.replace('{T}','summary').replace('{S}','今日小结已生成 · 点开看看').replace('md-entry"','md-entry" style="background:linear-gradient(135deg,#E3EEF8,#F2F7FC);border-color:rgba(143,184,222,.5)"'))
def HD(t='妈咪日记',back='home'):
  return f'<div class="hd"><div class="ic" onclick="go(\'{back}\')">{ic("chevron_left",22)}</div><b class="md-hdt">{t}</b><div style="width:38px"></div></div>'
def tli(c,txt,t,extra='',go_='edit'):
  n,i,bg=CAT[c]
  return f'<div class="tli" onclick="go(\'{go_}\')"><div class="d" style="background:{bg}">{ic(i)}</div><div class="md-tx">{n} · {txt}{extra}</div><small>{t}</small></div>'
QK='<span class="md-tag md-q">快捷记录</span>'
def diary(state,recs=True,night=False):
  if state=='idle':
    mic=f'<div class="md-micw"><button class="md-mic" onclick="go(\'rec\')">{ic("voice",52)}<b>按住说话</b><span>比如“上午喂了两次奶，拉了一次”</span></button></div><div class="md-alt" onclick="go(\'text\')">{KEY()}不方便出声？打字记录</div>'
  elif state=='rec':
    w=''.join(f'<i style="height:{h}px;animation-delay:{d}s"></i>' for h,d in [(18,0),(34,.1),(52,.2),(30,.3),(58,.15),(40,.25),(22,.05),(48,.35),(28,.2),(16,.1)])
    mic=f'<div class="md-micw"><div class="md-bub"><div class="wave">{w}</div><div class="md-tm">0:04</div><div class="md-live">“今天吃奶 6 次，下午哭得厉害…”</div></div><div class="md-up">↑ 上滑取消</div><button class="md-mic md-on" onclick="go(\'proc\')">{ic("voice",48)}<b>松开 结束</b></button></div>'
  elif state=='cancel':
    mic=f'<div class="md-micw"><div class="md-cz">{ic("close",32)}<b>松手取消</b><span>这句话不会被记录</span></div><button class="md-mic md-gray" onclick="go(\'diary\')">{ic("voice",48)}<b>松开 取消</b></button></div>'
  else:
    mic=f'<div class="md-micw"><div class="md-bub"><div class="md-live" style="color:var(--ink);font-size:15px">“今天吃奶6次，下午哭得厉害，中午睡了一个多小时，上午拉了一次黄色软便”</div><div class="md-dots"><i></i><i></i><i></i></div><div class="md-tm md-s">正在帮你整理成卡片…</div></div><button class="md-mic md-gray">{ic("voice",48)}<b>整理中</b></button></div>'
  lst=(f'<div class="sec">今天的日记<a onclick="go(\'tl\')">查看全部 ›</a></div><div class="tl">'+tli('mood','下午哭得<mark>厉害</mark>','下午')+tli('feed','母乳 · 左侧 15 分钟','15:00',QK)+'</div>') if recs else f'<div class="sec">今天的日记</div><div class="md-empty" onclick="go(\'rec\')">{ic("soothed",40)}<div><b>今天还没有日记</b>按住上面的按钮，说一句宝宝的情况</div></div>'
  return f'<div class="body">{HD()}<p class="md-sub">小米粒 · 出生第 23 天</p>{mic}{lst}</div>'
FIRST=diary('idle',False)+f'''<div class="dim"></div><div class="sheet"><div class="grab"></div>
<div class="sheet-hero"><div class="icon">{BOOK(30)}</div><div><h3>欢迎使用妈咪日记</h3><p>已沿用宝宝资料：小米粒 · 出生第 23 天</p></div></div>
<div class="lab">还差一项：宝宝性别（可跳过）</div><div class="seg"><div class="on" onclick="seg(this)">男宝宝</div><div onclick="seg(this)">女宝宝</div></div>
<div class="btn row" style="padding:0;margin-top:22px"><button class="btn ghost" onclick="go('diary-empty')">以后再说</button><button class="btn pri" onclick="go('diary-empty')">开始记录</button></div>
<p class="disc">妈咪日记仅用于记录宝宝日常情况，不提供医疗诊断或建议。如宝宝出现发热、持续哭闹、精神差等异常情况，请及时咨询专业医生。</p></div>'''
cell('first','首次进入 · 沿用已有宝宝资料，只补性别',FIRST)
cell('diary-empty','妈咪日记 · 当天空状态',diary('idle',False))
cell('diary','妈咪日记 · 按住说话（空闲）',diary('idle'))
cell('rec','录音中（波形 + 计时 + 实时转写）',diary('rec'))
cell('cancel','上滑取消',diary('cancel'))
cell('proc','AI 整理中（显示原文）',diary('proc'))
cell('err','语音识别失败 · 兜底',diary('idle')+f'''<div class="dim"></div><div class="sheet"><div class="grab"></div><div class="center">{ic("signal_error",52)}<h3 style="font-size:20px;margin-top:8px">没听清，再试一次？</h3><p class="hint" style="font-size:14px">周围有点吵，或者说得太快了。宝宝睡着时，也可以直接打字。</p></div>
<button class="btn pri" style="margin-top:18px" onclick="go('text')">改用文字输入</button><button class="btn ghost" style="margin-top:10px" onclick="go('rec')">再说一次</button>
<p class="hint">录音少于 1 秒提示“说长一点试试”；断网时已识别的文字保留为草稿</p></div>''')
cell('text','文字输入',f'''<div class="body">{HD('打字记录','diary')}<div class="md-ta">中午睡了一个多小时，上午拉了一次黄色软便<span class="md-cur"></span></div>
<div class="chips" style="margin-top:12px"><span>喂了…</span><span>睡了…</span><span>换了尿布</span><span>哭闹</span></div>
<button class="btn pri" style="margin-top:18px" onclick="go('confirm')">整理成卡片</button><p class="hint">和语音走同一个整理流程</p></div><div class="md-kb">{"".join(f"<i>{c}</i>" for c in "手机键盘区域")}</div>''')
def cc(c,main,sub,t,y=True,low=False,op=False,to='confirm-edit'):
  n,i,bg=CAT[c]
  ed=f'''<div class="md-edit"><div class="lab">分类</div><div class="chips">{"".join(f'<span class="{"on" if k==c else ""}" onclick="chip(this)">{CAT[k][0]}</span>' for k in CAT)}</div>
<div class="md-g2"><div><div class="lab">次数</div><div class="md-inp md-ok">6 次</div></div><div><div class="lab">时间</div><div class="md-inp md-ok">今天 · 当日汇总</div></div></div>
<div class="lab">备注</div><div class="md-inp"><span class="md-ph">比如：亲喂为主</span></div><div class="md-fold" onclick="go('confirm')">完成，收起 ⌃</div></div>''' if op else ''
  return f'''<div class="md-cc{' md-off' if not y else ''}{' md-open' if op else ''}"><div class="md-ch"><div class="md-ck{' md-y' if y else ''}" onclick="this.classList.toggle('md-y');this.closest('.md-cc').classList.toggle('md-off')">{'✓' if y else ''}</div>
<div class="md-d" style="background:{bg}">{ic(i,24)}</div><div class="md-cm" onclick="go('{to}')"><b>{n} · {main}</b><small>{sub}</small>{'<em class="md-low">请核对</em>' if low else ''}</div><span class="md-t">{t}</span>{'' if op else EDIT()}</div>{ed}</div>'''
RAW='<div class="md-raw"><small>你说的是</small>“今天吃奶6次，下午哭得厉害，中午睡了一个多小时，上午拉了一次黄色软便”<a onclick="go(\'text\')">改原文</a></div>'
def conf(cards,btn='保存 4 条',off=False,extra=''):
  b=f'<button class="btn ghost" style="color:#B3A99F;background:#EDE5DC;border:0">{btn}</button>' if off else f'<button class="btn pri" onclick="go(\'saved\')">{btn}</button>'
  return f'<div class="body">{HD("帮你整理好了","diary")}{RAW}{extra}{cards}<p class="hint">点卡片可就地修改 · 取消勾选的不会保存</p></div><div class="md-foot">{b}</div>'
C1=lambda o=False:cc('feed','6 次','今天汇总 · 未提到方式和奶量','当日',op=o)
REST=cc('mood','哭闹 · <mark>厉害</mark>','原话“哭得厉害”','下午')+cc('sleep','1 小时多','原话“一个多小时”','中午',low=True)+cc('diaper','便便 · 黄色软便','1 次','上午')
cell('confirm','AI 拆分确认 · 默认全选',conf(C1()+REST))
cell('confirm-edit','确认页 · 就地展开编辑',conf(C1(True)+REST))
cell('confirm-none','确认页 · 全部取消（保存置灰）',conf(''.join(cc(c,m,s,t,y=False) for c,m,s,t in [('feed','6 次','今天汇总','当日'),('mood','哭闹 · <mark>厉害</mark>','原话“哭得厉害”','下午'),('sleep','1 小时多','原话“一个多小时”','中午'),('diaper','便便 · 黄色软便','1 次','上午')]),'请至少勾选一条',True))
cell('confirm-fail','AI 整理失败 · 原文存为“其他”',conf(cc('other','原话已保留','可点开改分类和内容','刚刚'),'保存 1 条',extra=f'<div class="md-warn">{ic("signal_error",22)}<span>这次没能自动整理，原话先存成一条“其他”，不会丢。</span></div>'))
cell('risk','确认页 · 风险词通用提示',conf(cc('other','体温 38.6℃','原话“有点发烧 38.6”','刚刚')+cc('mood','精神不太好','原话“蔫蔫的”','刚刚'),'保存 2 条',extra=f'<div class="md-warn md-blue">{ic("tip",22)}<span>如有担心，请及时就医。</span></div>'))
TL=tli('mood','下午哭得<mark>厉害</mark>','下午')+tli('feed','母乳 · 左侧 15 分钟','15:00',QK,'tl')+tli('sleep','午睡 1 小时 10 分','13:20')+tli('diaper','便便 · 黄色软便','11:05')+tli('feed','今天共 6 次','当日','<span class="md-tag">汇总</span>')
SUMM=f'<div class="md-sum" onclick="go(\'summary\')">{ic("night_mode",30)}<div><small>今日小结 · 21:00</small><b>今天小米粒吃了 6 次奶，午睡一个多小时，下午有点闹，你辛苦啦。</b></div></div>'
HN='<p class="hint">“下午”按 15:00 排序 · 首页快捷记录会一并显示（只读跳转）· 汇总不与单次重复计数</p>'
def tl(summary=SUMM,body=TL,toast='',hint=True,n=5):
  days=''.join(f'<div class="{"on" if d=="今天" else ""}">{w}<b>{d}</b></div>' for w,d in [('六','10'),('日','11'),('一','12'),('二','13'),('三','今天')])
  return f'''{toast}<div class="body">{HD("今天的日记","diary")}<div class="md-days">{days}</div>{summary}<div class="sec">10 月 14 日 · {n} 条<a>按时间排序</a></div><div class="tl">{body}</div>{HN if hint else ''}</div>'''
cell('saved','保存成功 · 进入时间线',tl('',toast=f'<div class="toast"><i>{ic("check_done",24)}</i><div>已保存 4 条<small>在日记里可以随时修改</small></div></div>'))
cell('tl','当日时间线（顶部今日小结）',tl())
cell('edit','时间线 · 编辑（沿用补记 sheet）',tl()+f'''<div class="dim"></div><div class="sheet"><div class="grab"></div><div class="sheet-hero"><div class="icon">{ic("cause_hold_me",30)}</div><div><h3>情绪</h3><p>来自：“下午哭得厉害”</p></div></div>
<div class="lab">情绪</div><div class="chips"><span class="on" onclick="chip(this)">哭闹</span><span onclick="chip(this)">哄不好</span><span onclick="chip(this)">开心</span><span onclick="chip(this)">自定义</span></div>
<div class="lab">程度</div><div class="seg"><div onclick="seg(this)">一点</div><div onclick="seg(this)">明显</div><div class="on" onclick="seg(this)">厉害</div></div>
<div class="lab">时段</div><div class="seg"><div onclick="seg(this)">上午</div><div class="on" onclick="seg(this)">下午</div><div onclick="seg(this)">晚上</div><div onclick="seg(this)">夜里</div></div>
<div class="btn row" style="padding:0;margin-top:22px"><button class="btn ghost md-red" onclick="go('del')">删除</button><button class="btn pri" onclick="go('tl')">保存修改</button></div></div>''')
cell('del','删除二次确认',tl()+f'''<div class="dim"></div><div class="md-dlg"><h3>删除这条日记？</h3><p>情绪 · 下午哭得厉害<br>已生成的今日小结不会自动改写</p><div class="md-row2"><button class="btn ghost" onclick="go('tl')">再想想</button><button class="btn pri md-redb" onclick="go('tl')">删除</button></div></div>''')
cell('tl-empty','时间线 · 空状态',tl('',f'<div class="md-empty md-col" onclick="go(\'diary\')">{ic("soothed",52)}<b>这天还没有日记</b>回到上一页按住说话，说一句就能记</div>',hint=False,n=0))
def summ(night):
  return f'''<div class="body">{HD("今日小结","tl")}<div class="md-moon">{ic("night_mode",84)}</div><div class="md-sdate">10 月 14 日 · 星期三 · 21:00</div>
<div class="md-sbig">今天小米粒吃了 6 次奶，午睡一个多小时，下午有点闹。你辛苦啦，早点休息。</div>
<div class="md-facts"><div>{ic("care_feed",28)}<b>6 次</b><small>喂奶</small></div><div>{ic("care_sleep",28)}<b>1 小时多</b><small>午睡</small></div><div>{ic("care_diaper",28)}<b>1 次</b><small>便便</small></div><div>{ic("cause_hold_me",28)}<b>下午</b><small>哭闹</small></div></div>
<p class="hint">只根据今天保存的 5 条记录生成</p><button class="btn ghost" style="margin-top:16px" onclick="go('tl')">看今天的日记</button>
<p class="disc">妈咪日记仅用于记录宝宝日常情况，不提供医疗诊断或建议。如宝宝出现发热、持续哭闹、精神差等异常情况，请及时咨询专业医生。</p></div>'''
cell('summary','晚间今日小结',summ(False))
cell('summary-night','今日小结 · 夜间模式（沿用暗红夜间配色）',summ(True),night=True)
cell('summary-empty','今日小结 · 当天无记录',f'''<div class="body">{HD("今日小结","tl")}<div class="md-moon">{ic("soothed",84)}</div><div class="md-sdate">10 月 14 日 · 21:00</div><div class="md-sbig">今天没有日记也没关系，照顾好宝宝和自己就是最重要的事。</div><button class="btn pri" onclick="go('diary')">补记一句</button></div>''')
css=open('base.css').read()+open('md.css').read()
html=f'''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>哄哄 · 妈咪日记（新功能）设计稿</title><style>{css}</style></head><body>
<h1 class="t">哄哄 · 妈咪日记（新增功能）</h1><p class="ts">基于设计稿 v1.1 · 入口在首页快捷按钮下方 · 首页其余内容与底部标签不变 · 点击可跳转 · 数据均为示例</p>
<div class="wall">{"".join(h for _,h in cells)}</div>
<script>
const p=new URLSearchParams(location.search).get('s');
function go(s){{if(!document.body.classList.contains('single')){{const el=document.getElementById('c-'+s);if(el)el.scrollIntoView({{behavior:'smooth',inline:'center',block:'center'}});return}}
document.querySelectorAll('.cell').forEach(c=>c.classList.toggle('show',c.id=='c-'+s));history.replaceState(0,'','?s='+s)}}
function seg(e){{e.parentNode.querySelectorAll('div').forEach(d=>d.classList.remove('on'));e.classList.add('on')}}
function chip(e){{e.parentNode.querySelectorAll('span').forEach(s=>s.classList.remove('on'));e.classList.add('on')}}
if(p){{document.body.classList.add('single');go(p)}}
</script></body></html>'''
open('design.html','w').write(html)
open('ids.txt','w').write('\n'.join(i for i,_ in cells))
