(function(){
  var KIND = document.body.getAttribute('data-kind'); // release | beta
  var C = (window.HH_CONFIG||{})[KIND];
  // ---- 平台识别（?ua=ios|android|wechat|desktop 可覆盖，用于预览） ----
  var q = (location.search.match(/[?&]ua=([a-z]+)/)||[])[1];
  var ua = navigator.userAgent||'';
  var isWx = /MicroMessenger/i.test(ua), isIOS = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints>1),
      isAnd = /Android/i.test(ua);
  var p = q || (isWx ? 'wechat' : isIOS ? 'ios' : isAnd ? 'android' : (/Mobi/i.test(ua) ? 'android' : 'desktop'));
  // 微信里也需要知道真实系统，用来给出对应提示文字
  var wxOS = q==='wechat' ? 'ios' : (isIOS?'ios':'android');
  var b = document.body;
  b.classList.add(p==='desktop'?'is-desktop':'is-mobile');
  if(p==='wechat') b.classList.add('is-wechat');
  function $(s){return document.querySelectorAll(s)}
  function set(k,v){ $('[data-f="'+k+'"]').forEach(function(e){e.textContent=v}) }
  ['version','build','date','size','minOS'].forEach(function(k){set(k,C[k])});
  $('[data-f="notes"]').forEach(function(ul){ul.innerHTML=C.notes.map(function(n){return '<li>'+n.replace(/</g,'&lt;')+'</li>'}).join('')});
  // ---- 二维码（本地 qrcode-generator 生成 SVG，离线可用） ----
  $('[data-qr]').forEach(function(el){
    var qr = qrcode(0,'M'); qr.addData(C.pageUrl); qr.make();
    var n = qr.getModuleCount(), cell = +el.getAttribute('data-qr')/(n+8), s='';
    for(var r=0;r<n;r++)for(var c=0;c<n;c++) if(qr.isDark(r,c)) s+='M'+(c+4)+' '+(r+4)+'h1v1h-1z';
    var px = cell*(n+8);
    el.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="'+px+'" height="'+px+'" viewBox="0 0 '+(n+8)+' '+(n+8)+'" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path d="'+s+'" fill="#3D3A45"/></svg>';
  });
  // ---- 按钮 ----
  var ICON_A='<svg viewBox="0 0 24 24" fill="#fff"><path d="M17.5 9.5l1.6-2.8a.4.4 0 00-.7-.4l-1.6 2.8A9.6 9.6 0 0012 8a9.6 9.6 0 00-4.8 1.1L5.6 6.3a.4.4 0 00-.7.4l1.6 2.8A8.5 8.5 0 002 16.5h20a8.5 8.5 0 00-4.5-7zM7.5 14a1 1 0 110-2 1 1 0 010 2zm9 0a1 1 0 110-2 1 1 0 010 2z"/></svg>';
  var ICON_I='<svg viewBox="0 0 24 24" fill="#fff"><path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9s-2-.9-3.4-.9A5 5 0 003.5 9.3c-1.8 3.1-.5 7.7 1.3 10.2.8 1.2 1.8 2.6 3.1 2.5 1.2-.1 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.6-1-2.2-4.2zM14 5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>';
  var main=document.getElementById('main'), alt=document.getElementById('alt'), tip=document.getElementById('iostip');
  var os = p==='wechat'?wxOS:p;
  if(main){
    if(os==='ios'){
      main.innerHTML=ICON_I+'<span>'+(KIND==='beta'?'加入 TestFlight 内测':'通过 TestFlight 安装')+'</span>'; main.href=C.testflightUrl;
      alt.innerHTML='安卓手机？<a href="'+C.apkUrl+'" download>下载 APK</a>';
      tip.textContent='需先在 App Store 安装「TestFlight」，再点上方按钮';
    } else {
      main.innerHTML=ICON_A+'<span>'+(KIND==='beta'?'下载内测版 APK':'下载安卓版')+'</span>'; main.href=C.apkUrl; main.setAttribute('download','');
      alt.innerHTML='iPhone 用户？<a href="'+C.testflightUrl+'">前往 TestFlight</a>';
      tip.textContent='如提示「未知来源」，请在设置中允许本次安装';
    }
    if(p==='wechat'){ // 微信内屏蔽直接下载
      main.classList.add('off'); main.removeAttribute('href'); main.removeAttribute('download');
      alt.querySelectorAll('a').forEach(function(a){a.removeAttribute('href')});
      $('.wx [data-f="osname"]').forEach(function(e){e.textContent= wxOS==='ios'?'在 Safari 中打开':'在浏览器中打开'});
    }
  }
  $('[data-l="apk"]').forEach(function(a){a.href=C.apkUrl});
  $('[data-l="tf"]').forEach(function(a){a.href=C.testflightUrl});
})();
