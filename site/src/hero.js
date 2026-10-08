// The hero's opening, after motion.js has started it (html.hero-go). From 1024 px the headline is on the left
// and the Mac Studio in 3D (mac-scene.js) on the right, on its stage, and the app icon's two lanes, drawn as
// light, run behind the headline and on into two of the Mac's back Thunderbolt ports. It plays once: the
// Mac comes up at its front three-quarters, every port in Thunderbolt Bridge, and turns to its back while
// the lanes draw in from the left; they reach their ports as the Mac settles, and as each one arrives its
// port leaves the bridge (the ring closes: Ready for RDMA). Back, middle right follows, as the first
// screenshot of How it works, right under the hero, shows it. A single pulse of light then runs along the
// lanes into the ports, and nothing moves after that; the scene stops drawing.
//
// The lanes (svg.hero-link) are built here, in CSS pixels: each one comes in apart from the window's left
// edge, curves in to its place beside the other at the headline's first line break, runs behind the
// headline, and leaves it for its port in the same S it came in by, arriving much as a cable leaves the
// port's face. mac-scene.js projects the two ports, and the way out of them, with the camera where the
// turn ends, so the lanes end on the ports; they are built again whenever the page's layout or the theme
// changes, and when the Mac settles. Once the opening is over, the document hears 'hero-settled' (why3d.js
// waits for it to make its own scene while nothing moves).
//
// styles.css lays the hero out around the stage only on a screen 1024 px and wider, under html.gl (WebGL
// is there: motion.js), without reduced motion, and while .hero is not .is-static. Narrower, the copy takes
// the width and How it works, right under it, opens on the app's own picture of the Mac, so there is no
// stage, three.js is not fetched for it, and the lanes are the static drawing behind the headline
// (styles.css draws it in on html.hero-go). This file adds .is-static when there is no WebGL, three.js
// does not load or the context is lost: the hero is then the plain one, centred, with the static lanes
// behind the headline. A context the browser gives back brings the stage back, at the opening's end if
// it had played. three.js loads when the stage comes near the viewport (at once on a desktop). The scene
// draws only while the stage is on screen and the tab shows (mac-scene.js), and the turn starts only once
// the stage is well in view and the tab shows, so nobody misses it.
(function () {
  'use strict';
  var hero = document.getElementById('top');
  var stage = hero && hero.querySelector('.hero-stage');
  var link = hero && hero.querySelector('.hero-link');
  var h1 = hero && hero.querySelector('h1');
  if (!stage || !link || !h1) return;
  // Without IntersectionObserver there is no telling when the stage is in view: keep the plain hero.
  if (!('IntersectionObserver' in window)) { hero.classList.add('is-static'); return; }
  var canvas = stage.querySelector('.hero-canvas');
  var light = window.matchMedia('(prefers-color-scheme: light)');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  var wide = window.matchMedia('(min-width: 1024px)');   // the side-by-side hero (styles.css)
  var PI = Math.PI;

  // The camera, round the Mac (mac-scene.js: th is the turn, ph the height, mul the distance). It starts at
  // the front three-quarters, a little low and back, and ends at the back three-quarters seen from the
  // Mac's left, where the Thunderbolt ports face the headline and the lanes can come to them from it.
  var FROM = { th: -0.62, ph: 0.2, mul: 1.1 };
  var TO = { th: -(PI - 0.55), ph: 0.3, mul: 1 };
  var TURN = 2800;                     // ms
  var LANES = ['Back, far left', 'Back, middle left'];   // the cyan lane's port, then the blue one's
  var THEN = 'Back, middle right';     // leaves the bridge NEXT ms after the second
  // The lanes draw in over the turn, with its easing, so each one's tip is as far along as the Mac is
  // round; the blue one runs LAG behind. A lane is within a few pixels of its port at ARRIVE.
  var LAG = 140, ARRIVE = Math.round(TURN * 0.88);
  var PULSE_AT = 500, PULSE = 1100;    // ms after the blue lane arrives, and how long the pulse runs
  var PULSE_EASE = 'cubic-bezier(0.45, 0, 0.25, 1)';
  var PULSE_DASH = [3.2, 2.2, 1.3, 0.6];  // em: the pulse's four dashes, .pulse-1 to .pulse-4 (styles.css)
  var NEXT = 340;                      // ms
  var EARLIEST = 450;                  // ms after navigation: the headline is on its way first
  // ms after the turn starts: nothing moves from here on. About 4.2 s: with the turn starting EARLIEST
  // after navigation, the opening is over within five seconds of hero-go (WCAG 2.2.2), as the viewer's
  // idle turn is (mac-scene.js, IDLE). three.js arriving later than that starts the turn, and so ends
  // it, later.
  var SETTLED = ARRIVE + LAG + PULSE_AT + PULSE;

  var scene = null, ports = [], drawn = false, inView = false, played = false, failed = false;
  var done = false;   // the opening has started once: a scene made again after a lost context starts at its end
  var go = document.documentElement.classList.contains('hero-go');
  var timers = [], anims = [];

  function theme() { return light.matches ? 'light' : 'dark'; }
  function onChange(mq, fn) {
    if (mq.addEventListener) mq.addEventListener('change', fn);
    else if (mq.addListener) mq.addListener(fn);
  }
  // A slow start and a long, soft landing: an in-out cubic with its middle moved earlier.
  function settle(k) {
    k = Math.pow(k, 0.8);
    return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
  }
  // The stage's colours come from styles.css (--stage-edge is the page's background), so the frame melts
  // into the page and the pool of light is the one the stage shows before the scene is in.
  function backdrop() {
    var css = window.getComputedStyle(stage);
    var edge = css.getPropertyValue('--stage-edge').trim(), lift = css.getPropertyValue('--stage-lift').trim();
    return edge && lift ? [edge, lift] : null;
  }
  function portId(name) {
    for (var i = 0; i < ports.length; i++) if (ports[i].name === name) return ports[i].id;
    return null;
  }
  function ready(name) {
    var id = portId(name);
    if (id && scene) scene.setReady(id, true);
  }
  function later(fn, ms) { timers.push(setTimeout(fn, ms)); }

  // ---------- the lanes ----------
  var laneA = link.querySelectorAll('path.lane-a'), laneB = link.querySelectorAll('path.lane-b');
  var bodies = link.querySelectorAll('g:not(.link-pulse) path');
  var grads = ['link-a', 'link-b', 'link-core'].map(function (id) { return document.getElementById(id); });
  var shape = null;   // what the last build measured: where the pair starts, as a share of each lane

  function n(v) { return Math.round(v * 10) / 10; }
  function pt(x, y) { return n(x) + ' ' + n(y); }
  function each(list, fn) { for (var i = 0; i < list.length; i++) fn(list[i], i); }

  // Builds the lanes for the layout as it is now. False when they are not shown (below 1024 px, the plain
  // hero) or the ports cannot be found; the caller then leaves them alone.
  function build() {
    if (!scene || !wide.matches || still.matches || hero.classList.contains('is-static')) return false;
    var idA = portId(LANES[0]), idB = portId(LANES[1]);
    var pa = idA && scene.portAt(idA, TO), pb = idB && scene.portAt(idB, TO);
    if (!pa || !pb) return false;
    var box = hero.getBoundingClientRect(), cv = canvas.getBoundingClientRect();
    // The drawing starts at the window's left edge, ox px left of the hero (which is at most 1440 px wide
    // and centred), so the lanes come in from the edge however wide the window. Its x is the hero's + ox.
    var ox = Math.max(0, box.left - document.documentElement.getBoundingClientRect().left);
    var css = window.getComputedStyle(h1);
    var fs = parseFloat(css.fontSize), lh = parseFloat(css.lineHeight) || fs * 0.98;
    var range = document.createRange();
    range.selectNodeContents(h1);
    var text = range.getBoundingClientRect();
    var top = h1.getBoundingClientRect().top - box.top;
    var left = text.left - box.left + ox, right = text.right - box.left + ox;
    // The ports, in the drawing's pixels.
    var A = { x: cv.left - box.left + ox + pa.x, y: cv.top - box.top + pa.y, dx: pa.dx, dy: pa.dy };
    var B = { x: cv.left - box.left + ox + pb.x, y: cv.top - box.top + pb.y, dx: pb.dx, dy: pb.dy };
    var W = box.width + ox, H = Math.ceil(cv.bottom - box.top + fs * 0.3);
    link.setAttribute('viewBox', '0 0 ' + n(W) + ' ' + H);
    link.style.left = -ox + 'px';
    link.style.width = n(W) + 'px';
    link.style.height = H + 'px';
    link.style.setProperty('--k', String(fs / 100));

    // As the drawing behind the plain headline: the pair 0.16 em apart at the first line break, the lanes
    // 1.7 em apart where they come in. They run in from the window's edge, start to close in 0.2 em left of
    // the hero, and are side by side 2.4 em into the headline; the pair leaves it a quarter em past its
    // longest line.
    var y = top + lh, g = fs * 0.08, spread = fs * 0.85;
    var a = ox + fs * 0.2, c = left + fs * 2.4, out = right + fs * 0.25;
    function head(s) {
      var y0 = y + s * spread, y1 = y + s * g, k = (c - a) / 2;
      return 'M' + pt(0, y0) + 'H' + n(a) + 'C' + pt(a + k, y0) + ' ' + pt(c - k, y1) + ' ' + pt(c, y1);
    }
    // The cyan lane, to its port: out along the line, then down in the same S as the one the lanes came in
    // by, into the port much as a cable leaves it: its face's normal, leant halfway to the line's own way.
    var ya = y - g, D = Math.sqrt((A.x - out) * (A.x - out) + (A.y - ya) * (A.y - ya));
    var ux = A.dx - 1, uy = A.dy, u = Math.sqrt(ux * ux + uy * uy) || 1;
    var dive = 'C' + pt(out + D * 0.62, ya) + ' ' + pt(A.x + ux / u * D * 0.36, A.y + uy / u * D * 0.36) + ' ' + pt(A.x, A.y);
    var headA = head(-1), headB = head(1);
    var la = headA + 'H' + n(out) + dive;
    // The blue lane keeps beside it, 2g to its right, all the way down; only near the end does it close in
    // to the ports' own spacing, and then it runs on the last few pixels to its port.
    var probe = laneA[0];
    probe.setAttribute('d', 'M' + pt(out, ya) + dive);
    var L = probe.getTotalLength(), N = Math.max(24, Math.ceil(L / 4)), at = [];
    for (var i = 0; i <= N; i++) at.push(probe.getPointAtLength(L * i / N));
    var hx = at[N].x - at[N - 1].x, hy = at[N].y - at[N - 1].y, hl = Math.sqrt(hx * hx + hy * hy) || 1;
    var across = ((B.x - A.x) * -hy + (B.y - A.y) * hx) / hl;
    var lb = headB + 'H' + n(out);
    for (i = 1; i <= N; i++) {
      var p0 = at[i - 1], p1 = at[Math.min(N, i + 1)];
      var tx = p1.x - p0.x, ty = p1.y - p0.y, tl = Math.sqrt(tx * tx + ty * ty) || 1;
      var t = Math.max(0, (i / N - 0.7) / 0.3), off = 2 * g + (across - 2 * g) * t * t * (3 - 2 * t);
      lb += 'L' + pt(at[i].x - ty / tl * off, at[i].y + tx / tl * off);
    }
    lb += 'L' + pt(B.x, B.y);
    each(laneA, function (p) { p.setAttribute('d', la); });
    each(laneB, function (p) { p.setAttribute('d', lb); });
    // Where the pair starts, as a share of each lane: the pulse starts there.
    var total = probe.getTotalLength();
    probe.setAttribute('d', headA); var fa = probe.getTotalLength() / total; probe.setAttribute('d', la);
    probe = laneB[0];
    var totalB = probe.getTotalLength();
    probe.setAttribute('d', headB); var fb = probe.getTotalLength() / totalB; probe.setAttribute('d', lb);
    shape = { a: fa, b: fb, la: total, lb: totalB, fs: fs };

    // The colours along x (styles.css names them): faded in at the edge, dim where the lanes come in, half
    // strength behind the headline, full from where they leave it, and a white core from there on.
    var end = Math.max(A.x, B.x);
    var stops = [0, fs * 0.5, c, right - fs * 0.4, out + fs * 0.6, end];
    grads.forEach(function (gr, i) {
      gr.setAttribute('x1', '0'); gr.setAttribute('x2', n(end)); gr.setAttribute('y1', '0'); gr.setAttribute('y2', '0');
      each(gr.querySelectorAll('stop'), function (st, j) {
        var x = i === 2 ? [0, 0, 0, out, out + fs * 1.2, end][j] : stops[j];
        st.setAttribute('offset', String(Math.max(0, Math.min(1, x / end)).toFixed(4)));
      });
    });
    return true;
  }

  function stopAnims() {
    anims.forEach(function (an) { try { an.cancel(); } catch (e) { /* gone */ } });
    anims = [];
  }

  // The turn's easing for the Web Animations that draw the lanes: settle(), sampled, where the browser
  // takes linear() easing, and an in-out curve near it elsewhere.
  var EASE = 'cubic-bezier(0.55, 0, 0.15, 1)';
  if (window.CSS && CSS.supports && CSS.supports('animation-timing-function', 'linear(0, 1)')) {
    var at = [];
    for (var i = 0; i <= 24; i++) at.push(settle(i / 24).toFixed(4) + ' ' + (i * 100 / 24).toFixed(2) + '%');
    EASE = 'linear(' + at.join(', ') + ')';
  }

  // The lanes draw in from the left with the turn, the blue one LAG behind; each one's port leaves the
  // bridge as it arrives, Back, middle right follows, and then the pulse. Without Web Animations the
  // lanes are simply there, and the rest keeps its time.
  function drawLanes() {
    hero.classList.add('is-linked');
    if (link.animate) {
      var hide = { strokeDasharray: '1 2', strokeDashoffset: 1 }, show = { strokeDasharray: '1 2', strokeDashoffset: 0 };
      each(bodies, function (p) {
        var lag = p.classList.contains('lane-b') ? LAG : 0;
        anims.push(p.animate([hide, show], { duration: TURN, delay: lag, easing: EASE, fill: 'backwards' }));
      });
    }
    later(function () { ready(LANES[0]); }, ARRIVE);
    later(function () { ready(LANES[1]); }, ARRIVE + LAG);
    later(function () { ready(THEN); }, ARRIVE + LAG + NEXT);
    if (link.animate) later(pulse, ARRIVE + LAG + PULSE_AT);
  }
  // One pulse along each lane, from where the pair starts into the port. Its dashes are centred on a point
  // that runs from there to past the lane's end, so the pulse slips into the port.
  function pulse() {
    if (!shape) return;
    each(link.querySelectorAll('.link-pulse'), function (group, i) {
      each(group.querySelectorAll('path'), function (p) {
        var b = p.classList.contains('lane-b'), from = b ? shape.b : shape.a, em = shape.fs / (b ? shape.lb : shape.la);
        var len = PULSE_DASH[i] * em, to = 1 + PULSE_DASH[0] * em / 2, dash = len + ' 3';
        anims.push(p.animate([
          { strokeDasharray: dash, strokeDashoffset: len / 2 - from, opacity: 0 },
          { strokeDasharray: dash, opacity: 1, offset: 0.18 },
          { strokeDasharray: dash, strokeDashoffset: len / 2 - to, opacity: 1 }
        ], { duration: PULSE, easing: PULSE_EASE, fill: 'backwards' }));
      });
    });
  }

  // ---------- the scene ----------
  // A scene's canvas keeps its WebGL context until the page lets it go. So the canvas goes with the scene:
  // a fresh one takes its place, and dispose() (mac-scene.js), seeing the old one off the page, hands its
  // context back at once. A scene made later gets a context of its own.
  function stop() {
    timers.forEach(clearTimeout);
    timers = [];
    stopAnims();
    if (scene) {
      var old = canvas;
      canvas = old.cloneNode(false);
      old.parentNode.replaceChild(canvas, old);
      scene.dispose();
    }
    scene = null; drawn = false; played = false; shape = null;
    stage.classList.remove('is-on');
    hero.classList.remove('is-linked');
  }
  // why: 'lost' when the context was lost (mac-scene.js onFail). The browser gives a lost context back
  // to its canvas (after a GPU reset, say), and then the stage comes back, on its fresh canvas.
  function fail(why) {
    var old = canvas;
    stop();
    failed = true;
    hero.classList.add('is-static');
    if (why !== 'lost') return;
    old.addEventListener('webglcontextrestored', function () {
      // The old canvas has its context back, but nothing draws with it now: let that go at once.
      try {
        var gl = old.getContext('webgl2') || old.getContext('webgl');
        var lose = gl && gl.getExtension('WEBGL_lose_context');
        if (lose) lose.loseContext();
      } catch (e) { /* it goes when the canvas is collected */ }
      failed = false;
      hero.classList.remove('is-static');
      start();
    }, { once: true });
  }

  function play() {
    if (played || !drawn || !inView || !go || document.hidden || still.matches) return;
    var wait = EARLIEST - performance.now();
    if (wait > 0) { later(play, wait); return; }
    played = true; done = true;
    stage.classList.add('is-on'); // the canvas fades in over the pool of light (styles.css)
    scene.turnTo(TO, TURN, settle);
    later(function () { if (scene) build(); }, TURN); // settled: measure again
    later(function () { document.dispatchEvent(new Event('hero-settled')); }, SETTLED);
    if (build()) drawLanes();
  }

  // The layout changed: build the lanes again. If the opening has played without them (the scene came
  // back after a lost context, already at its end), they are simply there now, and their ports are out
  // of the bridge.
  function relayout() {
    if (!scene || !build()) return;
    if (played && !anims.length && !hero.classList.contains('is-linked')) {
      hero.classList.add('is-linked');
      ready(LANES[0]); ready(LANES[1]); ready(THEN);
    }
  }

  function start() {
    if (scene || failed || still.matches) return;
    var T = window.THREE;
    if (!T || !T.WebGLRenderer || typeof window.createMacScene !== 'function') { fail(); return; }
    var atEnd = done;   // made again after a lost context: the opening is over, so the scene starts at its end
    try {
      scene = window.createMacScene(T, canvas, {
        theme: theme(),
        model: 'studio',
        idle: false,
        // Every port in the bridge (at the opening's end, all but the three it took out), and no cable: the
        // lanes are the cables.
        plan: { ready: atEnd ? [LANES[0], LANES[1], THEN] : [], plugged: [] },
        pose: atEnd ? TO : FROM,
        backdrop: backdrop,
        onPorts: function (list) { ports = list; },
        onFail: fail
      });
    } catch (err) {
      scene = null;
    }
    if (!scene) { fail(); return; }
    // The first frame compiles the shaders; the turn starts after it, so it never opens on a skipped frame.
    var made = scene;
    window.requestAnimationFrame(function () {
      window.requestAnimationFrame(function () {
        if (scene !== made) return;
        drawn = true;
        if (atEnd) { played = true; stage.classList.add('is-on'); }
        relayout();
        play();
      });
    });
  }

  // No WebGL (hasWebGL, motion.js, which has set html.gl by now if there is), or no mac-scene.js: no
  // three.js (600 KB) and no error from it.
  if (typeof window.hasWebGL !== 'function' || typeof window.loadThree !== 'function') { fail(); return; }
  if (!window.hasWebGL()) { fail(); return; }

  // One request for three.js for the whole page (loadThree, mac-scene.js), shared with why3d.js and
  // viewer.js.
  var asked = false;
  function load() {
    if (asked || failed || still.matches) return;
    asked = true;
    if (!window.hasWebGL()) { fail(); return; }
    window.loadThree(stage.getAttribute('data-three-src'), function (ok) { if (ok) start(); else fail(); });
  }

  // Near the viewport: load. Well in view (60% of the stage): play. The stage is display: none below
  // 1024 px and under reduced motion, so neither fires then.
  new IntersectionObserver(function (entries) {
    if (entries[entries.length - 1].isIntersecting) load();
  }, { rootMargin: '400px 0px' }).observe(stage);
  new IntersectionObserver(function (entries) {
    inView = entries[entries.length - 1].intersectionRatio >= 0.6;
    play();
  }, { threshold: [0, 0.6] }).observe(stage);
  document.addEventListener('visibilitychange', function () { play(); });
  document.addEventListener('hero-go', function () { go = true; play(); });

  // The lanes follow the layout: the window's size (wider than the hero, only the hero's place changes),
  // the headline's font coming in, the theme. Built at most once a frame.
  var queued = false;
  function soon() {
    if (queued) return;
    queued = true;
    window.requestAnimationFrame(function () { queued = false; relayout(); });
  }
  window.addEventListener('resize', soon);
  if (typeof ResizeObserver !== 'undefined') {
    var ro = new ResizeObserver(soon);
    ro.observe(hero); ro.observe(h1);
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(relayout, function () {});
  onChange(wide, relayout);
  onChange(light, function () { if (scene) { scene.setTheme(theme()); relayout(); } });
  // Reduced motion turned on: the hero goes plain (styles.css) and the scene goes. Turned off again: the
  // stage comes back, and plays from the start once it is in view. (While three.js is still on its way,
  // its load event starts the scene.)
  onChange(still, function () {
    if (still.matches) { stop(); done = false; }
    else if (!asked) load();
    else if (window.THREE) start();
  });
})();
