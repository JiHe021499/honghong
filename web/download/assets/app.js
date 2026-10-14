(function(){
  var KIND = document.body.getAttribute('data-kind'); // release | beta
  var CFG = window.HH_CONFIG||{}, C = CFG[KIND]||{};
  // ---- 平台识别（?ua=ios|android|wechat|desktop 可覆盖，用于预览） ----
  var q = (location.search.match(/[?&]ua=([a-z]+)/)||[])[1];
  var ua = navigator.userAgent||'';
  var isWx = /MicroMessenger/i.test(ua), isIOS = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints>1),
      isAnd = /Android/i.test(ua);
  var p = q || (isWx ? 'wechat' : isIOS ? 'ios' : isAnd ? 'android' : (/Mobi/i.test(ua) ? 'android' : 'desktop'));
  var wxOS = q==='wechat' ? 'ios' : (isIOS?'ios':'android');
  var b = document.body;
  b.classList.add(p==='desktop'?'is-desktop':'is-mobile');
  if(p==='wechat') b.classList.add('is-wechat');
  function $(s){return document.querySelectorAll(s)}
  function set(k,v){ $('[data-f="'+k+'"]').forEach(function(e){e.textContent=v}) }
  function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;')}

  // ---- 二维码（本地生成，不依赖版本数据） ----
  $('[data-qr]').forEach(function(el){
    var qr = qrcode(0,'M'); qr.addData(C.pageUrl||location.href); qr.make();
    var n = qr.getModuleCount(), cell = +el.getAttribute('data-qr')/(n+8), s='';
    for(var r=0;r<n;r++)for(var c=0;c<n;c++) if(qr.isDark(r,c)) s+='M'+(c+4)+' '+(r+4)+'h1v1h-1z';
    var px = cell*(n+8);
    el.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="'+px+'" height="'+px+'" viewBox="0 0 '+(n+8)+' '+(n+8)+'" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path d="'+s+'" fill="#3D3A45"/></svg>';
  });

  // ---- version.json → 页面数据 ----
  function fmtDate(iso){
    var d = new Date(iso); if(isNaN(d)) return '';
    // 统一按北京时间显示
    var t = new Date(d.getTime() + 8*3600e3), z = function(x){return (x<10?'0':'')+x};
    var day = t.getUTCFullYear()+'-'+z(t.getUTCMonth()+1)+'-'+z(t.getUTCDate());
    return KIND==='beta' ? day+' '+z(t.getUTCHours())+':'+z(t.getUTCMinutes()) : day;
  }
  function fmtSize(n){ n=+n; return n>0 ? (n/1048576).toFixed(1)+' MB' : '' }
  function notesOf(cl){
    return String(cl||'').split('\n').map(function(l){return l.replace(/^\s*[-*•]\s*/,'').trim()})
      .filter(Boolean).slice(0,8);
  }
  function pick(json){
    var e = json && json.channels && json.channels[C.channel];
    if(!e && json && json.channel===C.channel) e = json; // 旧格式只有顶层字段
    if(!e || !e.apkUrl || !e.versionName) return null;
    return { version:e.versionName, build:String(e.versionCode||''), date:fmtDate(e.publishedAt),
             size:fmtSize(e.size), apkUrl:e.apkUrl, notes:notesOf(e.changelog) };
  }
  function load(i, done){
    var src = (CFG.sources||[])[i]; if(!src) return done(null);
    var x = new XMLHttpRequest();
    x.open('GET', src + (src.indexOf('?')<0?'?':'&') + 't=' + Math.floor(Date.now()/60000), true); // 1 分钟内复用缓存
    x.timeout = 6000;
    x.onload = function(){
      var d=null; try{ if(x.status===200) d = JSON.parse(x.responseText) }catch(e){}
      d ? done(d) : load(i+1, done);
    };
    x.onerror = x.ontimeout = function(){ load(i+1, done) };
    x.send();
  }

  var ICON_A='<svg viewBox="0 0 24 24" fill="#fff"><path d="M17.5 9.5l1.6-2.8a.4.4 0 00-.7-.4l-1.6 2.8A9.6 9.6 0 0012 8a9.6 9.6 0 00-4.8 1.1L5.6 6.3a.4.4 0 00-.7.4l1.6 2.8A8.5 8.5 0 002 16.5h20a8.5 8.5 0 00-4.5-7zM7.5 14a1 1 0 110-2 1 1 0 010 2zm9 0a1 1 0 110-2 1 1 0 010 2z"/></svg>';
  var ICON_I='<svg viewBox="0 0 24 24" fill="#fff"><path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9s-2-.9-3.4-.9A5 5 0 003.5 9.3c-1.8 3.1-.5 7.7 1.3 10.2.8 1.2 1.8 2.6 3.1 2.5 1.2-.1 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.6-1-2.2-4.2zM14 5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>';
  var SOON = '即将上线';

  function render(D, failed){ // D 为 null 表示该渠道还没有发版（或数据拉取失败）
    var ok = !!D, tf = C.testflightUrl;
    var none = failed ? '暂时获取不到版本信息，请稍后刷新' : KIND==='beta' ? '暂无内测版本' : '正式版即将发布';
    set('version', ok ? 'v'+D.version : none);
    if(!ok) $('.ver,.vline').forEach(function(e){ e.textContent = none });
    if(!ok) $('.card h3 [data-f="version"]').forEach(function(e){ var t=e.previousSibling; if(t&&t.nodeType===3) t.textContent=t.textContent.replace(/\s*·\s*$/,''); e.textContent='' });
    set('build', ok ? D.build : '');
    set('date', ok ? D.date : '');
    set('size', ok && D.size ? D.size : '');
    set('minOS', C.minOS + (tf ? ' / iOS 15+' : ' · iOS 版即将上线'));
    $('[data-f="notes"]').forEach(function(ul){
      var ns = ok && D.notes.length ? D.notes : [ok ? '本次没有填写更新说明' : (KIND==='beta'?'下一次 dev 构建发布后会显示在这里':'正式版发布后，更新说明会显示在这里')];
      ul.innerHTML = ns.map(function(n){return '<li>'+esc(n)+'</li>'}).join('');
    });
    var apk = ok ? D.apkUrl : '';
    var main=document.getElementById('main'), alt=document.getElementById('alt'), tip=document.getElementById('iostip');
    var os = p==='wechat'?wxOS:p;
    function off(el){ el.classList.add('off'); el.removeAttribute('href'); el.removeAttribute('download') }
    if(main){
      main.classList.remove('off');
      if(os==='ios'){
        main.innerHTML=ICON_I+'<span>'+(tf ? (KIND==='beta'?'加入 TestFlight 内测':'通过 TestFlight 安装') : 'iOS 版'+SOON)+'</span>';
        if(tf) main.href=tf; else off(main);
        alt.innerHTML = apk ? '安卓手机？<a href="'+esc(apk)+'" download>下载 APK</a>' : '';
        tip.textContent = tf ? '需先在 App Store 安装「TestFlight」，再点上方按钮' : 'iPhone 版正在准备 TestFlight 内测，上线后这里会出现安装按钮';
      } else {
        main.innerHTML=ICON_A+'<span>'+(apk ? (KIND==='beta'?'下载内测版 APK':'下载安卓版') : none)+'</span>';
        if(apk){ main.href=apk; main.setAttribute('download','') } else off(main);
        alt.innerHTML = tf ? 'iPhone 用户？<a href="'+esc(tf)+'">前往 TestFlight</a>' : 'iPhone 用户？iOS 版'+SOON;
        tip.textContent = apk ? '如提示「未知来源」，请在设置中允许本次安装' : '';
      }
      if(p==='wechat'){ // 微信内屏蔽直接下载
        off(main);
        alt.querySelectorAll('a').forEach(function(a){a.removeAttribute('href')});
        $('.wx [data-f="osname"]').forEach(function(e){e.textContent= wxOS==='ios'?'在 Safari 中打开':'在浏览器中打开'});
      }
    }
    $('[data-l="apk"]').forEach(function(a){ if(apk && p!=='wechat'){a.href=apk;a.style.display=''} else {a.removeAttribute('href');a.style.display='none'} });
    $('[data-l="tf"]').forEach(function(a){ if(tf){a.href=tf} else {a.removeAttribute('href');a.textContent='TestFlight '+SOON;a.classList.add('soon')} });
  }

  set('version','加载中…');
  load(0, function(json){ render(json ? pick(json) : null, !json); b.setAttribute('data-ready', json ? 'ok' : 'offline') });
})();
