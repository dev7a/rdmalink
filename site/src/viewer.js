// The 3D viewer under "See it": a plain-JS port of the design canvas's MacViewer component.
// mac-scene.js draws the Mac (createMacScene); this file connects it to the markup in
// index.html: the model picker, the hover label, the stand-in buttons for the ports, the
// live region, the theme, and the fallback when WebGL is missing or lost.
//
// three.js (assets/vendor/three.r128.min.js, 600 KB) loads only when the viewer comes near
// the viewport. The scene then draws only while its canvas is on screen and the tab shows.
(function () {
  'use strict';
  var root = document.getElementById('viewer');
  if (!root) return;
  var block = root.parentNode; // .viewer-block, which holds the legend shown outside the compact frame
  var canvas = root.querySelector('.mv-canvas');
  var portsEl = root.querySelector('.mv-ports');
  var announceEl = root.querySelector('.mv-announce');
  var label = root.querySelector('.mv-label');
  var labelTitle = root.querySelector('.mv-label-title');
  var labelSub = root.querySelector('.mv-label-sub');
  var labelText = root.querySelector('.mv-label-text');
  var fallback = root.querySelector('.mv-fallback');
  var fallbackText = root.querySelector('.mv-fallback-text');
  var segs = root.querySelectorAll('.mv-seg');
  var infos = root.querySelectorAll('[data-info]');

  // Without JavaScript the <noscript> fallback covers the frame, so the markup starts in the failed
  // state (is-failed hides the picker, the caption, the legend and the hint) with the canvas out of the
  // Tab order and the accessibility tree. With it, they come back here; fail() takes them away again.
  block.classList.remove('is-failed');
  canvas.removeAttribute('aria-hidden');
  canvas.tabIndex = 0;

  var ACCENT = '#3d8bff';
  var NAMES = { studio: 'Mac Studio', mbp: 'MacBook Pro 14-inch', mini: 'Mac mini' };
  var light = window.matchMedia('(prefers-color-scheme: light)');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  var wide = window.matchMedia('(min-width: 1200px)'); // the wide frame; styles.css switches at the same width
  var model = 'studio';
  var viewer = null;
  var failed = false; // 'start' or 'lost' once the fallback shows
  var hover = null;

  function theme() { return light.matches ? 'light' : 'dark'; }
  function each(list, fn) { for (var i = 0; i < list.length; i++) fn(list[i], i); }
  function onChange(mq, fn) {
    if (mq.addEventListener) mq.addEventListener('change', fn);
    else if (mq.addListener) mq.addListener(fn);
  }

  // The hover label, placed as MacViewer placed it: centred on the port and 22 px above it,
  // or below it when the port is near the top of the frame, and kept inside the frame.
  function paintLabel() {
    var hv = hover;
    if (!hv) { label.hidden = true; return; }
    labelTitle.textContent = hv.title;
    labelText.textContent = hv.sub;
    labelSub.hidden = !hv.sub;
    label.setAttribute('data-state', hv.ready ? 'ready' : hv.thunderbolt ? 'tb' : 'other');
    label.hidden = false;
    var w = canvas.clientWidth, half = label.offsetWidth / 2 + 8;
    label.style.left = Math.max(half, Math.min(w - half, hv.x)) + 'px';
    label.style.top = hv.y + 'px';
    label.style.transform = hv.y < (wide.matches ? 150 : 120) ? 'translate(-50%, 22px)' : 'translate(-50%, calc(-100% - 22px))';
  }
  function showHover(hv) { hover = hv; paintLabel(); }

  // Real buttons stand in for the Thunderbolt ports, for the keyboard and screen readers:
  // focusing one turns the Mac to face its port and rings it; pressing it toggles Ready.
  function showPorts(ports, changed) {
    var kids = portsEl.children;
    var same = kids.length === ports.length && ports.every(function (p, i) { return kids[i].getAttribute('data-id') === p.id; });
    if (!same) {
      portsEl.textContent = '';
      ports.forEach(function (p) {
        var b = document.createElement('button');
        b.type = 'button';
        b.textContent = p.name;
        b.setAttribute('data-id', p.id);
        b.addEventListener('click', function () { if (viewer) viewer.toggle(p.id); });
        b.addEventListener('focus', function () { if (viewer) viewer.focusPort(p.id); });
        b.addEventListener('blur', function () { if (viewer) viewer.focusPort(null); });
        portsEl.appendChild(b);
      });
    }
    ports.forEach(function (p, i) { kids[i].setAttribute('aria-pressed', p.ready ? 'true' : 'false'); });
    if (changed) announceEl.textContent = changed.title + ' — ' + changed.sub;
  }

  function stop() {
    if (viewer) viewer.dispose();
    viewer = null;
  }

  // No WebGL, or the context was lost for good: the hub screenshot and one line instead.
  function fail(why) {
    stop();
    failed = why;
    fallbackText.textContent = why === 'lost'
      ? 'The 3D view stopped. Reload the page to bring it back.'
      : 'The 3D view could not start in this browser.';
    fallback.hidden = false;
    block.classList.add('is-failed');
    showHover(null);
    portsEl.textContent = '';
    announceEl.textContent = '';
    canvas.tabIndex = -1;
    canvas.setAttribute('aria-hidden', 'true');
  }

  function start() {
    if (viewer || failed) return;
    var T = window.THREE;
    if (!T || !T.WebGLRenderer || typeof window.createMacScene !== 'function') { fail('start'); return; }
    try {
      viewer = window.createMacScene(T, canvas, {
        accent: ACCENT,
        theme: theme(),
        model: model,
        reducedMotion: still.matches,
        onHover: showHover,
        onCursor: function (cursor) { canvas.style.cursor = cursor; },
        onPorts: showPorts,
        onFail: function () { fail('lost'); }
      });
    } catch (err) {
      viewer = null;
    }
    if (!viewer) fail('start');
  }

  // Without WebGL there is no point fetching three.js (600 KB), and three.js would log an error.
  function hasWebGL() {
    try {
      var c = document.createElement('canvas');
      var gl = c.getContext('webgl2') || c.getContext('webgl');
      var lose = gl && gl.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
      return !!gl;
    } catch (e) { return false; }
  }

  function load() {
    if (!hasWebGL()) { fail('start'); return; }
    if (window.THREE) { start(); return; }
    var script = document.createElement('script');
    script.src = root.getAttribute('data-three-src');
    script.onload = start;
    script.onerror = function () { fail('start'); };
    document.head.appendChild(script);
  }

  function choose(next) {
    if (next === model || !NAMES[next]) return;
    model = next;
    each(segs, function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-model') === next ? 'true' : 'false'); });
    each(infos, function (el) { el.hidden = el.getAttribute('data-info') !== next; });
    canvas.setAttribute('aria-label', NAMES[next] + ' in 3D, with its ports. Drag, or use the left and right arrow keys, to turn it.');
    showHover(null);
    announceEl.textContent = ''; // the last port announced belonged to the other Mac
    if (viewer) viewer.setModel(next);
  }

  each(segs, function (b) {
    b.addEventListener('click', function () { choose(b.getAttribute('data-model')); });
  });
  var methods = {
    pointerdown: 'pointerDown', pointermove: 'pointerMove', pointerup: 'pointerUp',
    pointerleave: 'pointerLeave', pointercancel: 'pointerCancel', keydown: 'keyDown'
  };
  Object.keys(methods).forEach(function (type) {
    canvas.addEventListener(type, function (e) { if (viewer) viewer[methods[type]](e); });
  });
  // The page's theme follows the system live; the scene recolours in place.
  onChange(light, function () { if (viewer) viewer.setTheme(theme()); });
  // The scene reads reduced motion when it starts, so a change restarts it on the same canvas (the
  // renderer.resetState() guard in mac-scene.js is for this). Ports marked Ready go back to the bridge.
  onChange(still, function () { if (viewer) { stop(); start(); } });
  // three.js keeps a lost context restorable; when the browser gives it back (after a GPU reset, or
  // when iOS Safari brings a tab back), start again on the same canvas.
  canvas.addEventListener('webglcontextrestored', function () {
    if (failed !== 'lost' || viewer) return;
    failed = false;
    fallback.hidden = true;
    block.classList.remove('is-failed');
    canvas.tabIndex = 0;
    canvas.removeAttribute('aria-hidden');
    start();
  });
  onChange(wide, paintLabel);

  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      if (!entries.some(function (e) { return e.isIntersecting; })) return;
      io.disconnect();
      load();
    }, { rootMargin: '600px 0px' });
    io.observe(root);
  } else {
    load();
  }
})();
