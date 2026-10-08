// The 3D viewer under "See it": a plain-JS port of the design canvas's MacViewer component.
// mac-scene.js draws the Mac (createMacScene); this file connects it to the markup in
// index.html: the model picker, the hover label, the stand-in buttons for the ports, the
// live region, the theme, and the fallback when WebGL is missing or lost.
//
// three.js (assets/vendor/three.r128.min.js, 600 KB) loads only when the viewer comes near
// the viewport, through loadThree (mac-scene.js), so the page asks for it once, whichever of the
// hero, the Why diagrams and this viewer asks first. The scene then draws only while its canvas is
// on screen and the tab shows.
//
// On a large screen, with motion and WebGL, the section is also a scroll sequence (the end of this
// file): the viewer stays pinned while the scroll turns the Mac Studio, from a back three-quarter view,
// to its back, moves in on its Thunderbolt ports and takes them out of the
// bridge one by one; then shows the MacBook Pro's ports, left side and right, and the Mac mini's, all in
// Thunderbolt Bridge. Then it lets go on the Mac mini, and the viewer is the person's again.
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
  var see = document.getElementById('see');
  var intro = see.querySelector('.intro');
  // The sequence's screens: styles.css lays it out under the same query (and no reduced motion).
  var roomy = window.matchMedia('screen and (min-width: 1024px) and (min-height: 600px)');
  var model = 'studio';
  var viewer = null;
  var failed = false; // 'start' or 'lost' once the fallback shows
  var hover = null;
  var free = true; // false while the scroll sequence drives the scene; then nothing the person does reaches it

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
        b.addEventListener('click', function () { if (viewer && free) viewer.toggle(p.id); });
        b.addEventListener('focus', function () { if (viewer && free) viewer.focusPort(p.id); });
        b.addEventListener('blur', function () { if (viewer && free) viewer.focusPort(null); });
        portsEl.appendChild(b);
      });
    }
    ports.forEach(function (p, i) { kids[i].setAttribute('aria-pressed', p.ready ? 'true' : 'false'); });
    if (changed) announceEl.textContent = changed.title + ' — ' + changed.sub;
  }

  // Whatever the old scene was showing goes with it: a new one starts with nothing hovered and every
  // port back in the bridge, so a label or an announcement left over would describe a Mac that isn't there.
  function stop() {
    if (viewer) viewer.dispose();
    viewer = null;
    showHover(null);
    announceEl.textContent = '';
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
    // The sequence goes, and the section is today's again. If it is all above the viewport, what is on
    // screen stays: the page moves by what the next section has moved, which is nothing where the
    // browser's scroll anchoring has already kept it in place. If the reader is in it, the frame comes
    // into view (landed).
    if (see.classList.contains('is-scroll')) {
      var r = see.getBoundingClientRect(), next = see.nextElementSibling, at = next.getBoundingClientRect().top;
      see.classList.remove('is-scroll');
      setUp();
      if (r.bottom < 0) window.scrollBy({ top: next.getBoundingClientRect().top - at, behavior: 'instant' });
      else if (r.top < 0) landed();
    }
  }
  // The sequence comes back with a restored context, and the section its length. If it is all above the
  // viewport, what is on screen stays, as in fail(). If the reader is in it, they go to its end, where the
  // frame is in view and the viewer is theirs.
  function resume() {
    var r = see.getBoundingClientRect(), next = see.nextElementSibling, at = next.getBoundingClientRect().top;
    setUp();
    if (!active) return;
    if (r.bottom < 0) window.scrollBy({ top: next.getBoundingClientRect().top - at, behavior: 'instant' });
    else if (r.top < 0) { y = from + span; window.scrollTo({ top: y, behavior: 'instant' }); }
  }
  // The section has just lost the sequence's length (about 2.8 viewports) with the reader in it: the
  // frame, or the fallback over it, is put in the middle of the screen, rather than wherever the page's
  // scroll position now falls.
  function landed() { block.scrollIntoView({ block: 'center', behavior: 'instant' }); }

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
    if (!viewer) { fail('start'); return; }
    fresh = true;
    apply();
  }

  // Without WebGL there is no point fetching three.js (600 KB), and three.js would log an error. The
  // page asks once (hasWebGL, motion.js); here the sequence asks first, when it decides the section's
  // layout.
  function hasWebGL() { return typeof window.hasWebGL === 'function' && window.hasWebGL(); }

  function load() {
    if (!hasWebGL() || typeof window.loadThree !== 'function') { fail('start'); return; }
    window.loadThree(root.getAttribute('data-three-src'), function (ok) { if (ok) start(); else fail('start'); });
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

  // While the sequence runs, the picker shows which Mac is on screen, and a click on another one goes to
  // its first stop there (visit, below); otherwise it picks the Mac.
  each(segs, function (b) {
    b.addEventListener('click', function () {
      if (active && !free) visit(b.getAttribute('data-model'));
      else choose(b.getAttribute('data-model'));
    });
  });
  var methods = {
    pointerdown: 'pointerDown', pointermove: 'pointerMove', pointerup: 'pointerUp',
    pointerleave: 'pointerLeave', pointercancel: 'pointerCancel', keydown: 'keyDown'
  };
  Object.keys(methods).forEach(function (type) {
    canvas.addEventListener(type, function (e) { if (viewer && free) viewer[methods[type]](e); });
  });
  // The page's theme follows the system live; the scene recolours in place.
  onChange(light, function () { if (viewer) viewer.setTheme(theme()); });
  // The scene reads reduced motion when it starts, so a change restarts it on the same canvas (the
  // renderer.resetState() guard in mac-scene.js is for this). Ports marked Ready go back to the bridge.
  // The sequence starts or stops with it.
  onChange(still, function () { setUp(); if (viewer) { stop(); start(); } });
  // three.js keeps a lost context restorable; when the browser gives it back (after a GPU reset, or
  // when iOS Safari brings a tab back), start again on the same canvas, and the sequence comes back.
  canvas.addEventListener('webglcontextrestored', function () {
    if (failed !== 'lost' || viewer) return;
    failed = false;
    fallback.hidden = true;
    block.classList.remove('is-failed');
    canvas.tabIndex = 0;
    canvas.removeAttribute('aria-hidden');
    resume();
    start();
  });
  onChange(wide, paintLabel);

  // ---------- the scroll sequence ----------
  // At 1024 x 600 and larger, with motion and WebGL, #see is .is-scroll: styles.css makes it 3.8 viewports
  // tall and pins .viewer-block, the stage, and the intro over it for 2.8 of them. Progress p runs from 0,
  // when they pin, to 1, when they let go, and each p is one picture: a Mac, the camera between the shots
  // in KEYS, and, on the Mac Studio, the four back ports Ready from their READY_AT on. Scrolling back plays
  // it backwards. The Mac Studio's part is the first 0.46 of it; then the MacBook Pro 14-inch, its left
  // ports, a turn round its front and its right port; then the Mac mini's back ports. Their ports stay in
  // Thunderbolt Bridge: the change is the Mac Studio's story. A Mac takes over from the one before at its
  // first shot, through the scene's veil (setModel, about half a second), whichever way the scroll goes.
  // The intro fades out as the Mac Studio turns away from it, so the words never leave the frame. The
  // picker stays as a progress indicator, its pressed segment the Mac on screen. From RELEASE on, the
  // viewer is the person's again: the stage loses .is-driven, its controls come back, and the scene is
  // handed back at the Mac mini's rest, where it starts without the sequence.
  // The scroll listener only reads scrollY and asks for a frame; the frame works out p from the offsets
  // measured on resize and, when p has changed, sets the scene, which draws only when something moved.
  var PI = Math.PI;
  var KEYS = [
    // p     Mac       face: the ports aim looks at, from here on   th: turn   ph: height  mul: distance
    //                 aim: 0 the Mac, 1 those ports   shift: right, of the width
    [0.000, 'studio', 'back', PI - 0.55, 0.26, 1.42, 0, 0.18],    // a back three-quarter view, beside the heading
    [0.040, 'studio', 'back', PI - 0.55, 0.26, 1.42, 0, 0.18],    // held while the heading starts to fade
    [0.150, 'studio', 'back', PI - 0.10, 0.24, 1.00, 0, 0],       // the back
    [0.250, 'studio', 'back', PI - 0.30, 0.14, 0.50, 1, 0.2],     // in on the Thunderbolt ports, beside the captions
    [0.390, 'studio', 'back', PI - 0.22, 0.14, 0.46, 1, 0.2],
    [0.455, 'studio', 'back', PI - 0.35, 0.20, 0.75, 0.5, 0.2],   // a step back
    [0.460, 'mbp', 'left', -PI / 2 + 0.45, 0.30, 0.75, 0.5, 0.26], // the MacBook Pro, from the front left
    [0.560, 'mbp', 'left', -PI / 2 + 0.30, 0.35, 0.44, 1, 0.28],  // in on its two left ports, beside its caption
    [0.635, 'mbp', 'right', 0, 0.30, 1.00, 0, 0.2],               // round its front
    [0.680, 'mbp', 'right', PI / 2 + 0.10, 0.30, 0.95, 0.2, 0.26], // to its right side
    [0.710, 'mbp', 'right', PI / 2 + 0.45, 0.32, 0.46, 1, 0.24],  // and in on its right port, from behind
    [0.755, 'mbp', 'right', PI / 2 + 0.60, 0.30, 0.70, 0.5, 0.24],
    [0.760, 'mini', 'back', PI + 0.60, 0.24, 0.85, 0.6, 0.24],    // the Mac mini, from behind on its left
    [0.850, 'mini', 'back', PI + 0.45, 0.18, 0.62, 1, 0.27],      // in on its three back ports
    [0.960, 'mini', 'back', PI - 0.55, 0.34, 1.00, 0, 0],         // out to the Mac mini's rest (mac-scene.js), where the viewer starts
    [1.000, 'mini', 'back', PI - 0.55, 0.34, 1.00, 0, 0]
  ];
  var PORTS = ['Back, far left', 'Back, middle left', 'Back, middle right', 'Back, far right'];
  var READY_AT = [0.27, 0.30, 0.33, 0.36];
  // The captions (data-caption on the stage). On the Mac Studio, the legend's lines: "In Thunderbolt
  // Bridge" while the camera comes in on the bridged ports (from where the Mac, coming closer, is clear of
  // the words), then "Ready for RDMA" from the first change until the camera steps back. On the other two,
  // the frame's own caption (.mv-info: the Mac, its chips, its ports), while each is close in, beside it.
  var CAPTIONS = [[0.22, 'bridge'], [READY_AT[0], 'ready'], [0.42, ''], [0.47, 'info'], [0.745, ''], [0.77, 'info'], [0.88, '']];
  var RELEASE = 0.975;
  // The moments PageDown and PageUp go between while the stage is pinned (addStops, motion.js): the
  // start, the Mac Studio's ports in the bridge close up, all four Ready, the MacBook Pro's left ports and
  // its right one, the Mac mini's ports, and the hand-back.
  var MOMENTS = [0, 0.25, 0.39, 0.56, 0.71, 0.85, 1];
  // Where a click on the picker goes while the sequence runs: each Mac's first stop.
  var FIRST = { studio: 0, mbp: 0.56, mini: 0.85 };

  var active = false;           // the sequence is on: .is-scroll, the screen is roomy, no reduced motion
  var from = 0, span = 1, y = 0; // where p is 0, the scroll from there to p = 1, and scrollY
  var top0 = 0, bottom0 = 0;    // where the section starts and ends, measured with the sequence
  var queued = false, shown = -1, caption = '';
  var fresh = false;            // the scene is new (or the sequence is): its next shot is taken at once

  function smooth(k) { return k * k * (3 - 2 * k); }
  // The shot at p: between the two keys either side of it, or, between two Macs' keys, the last one of the
  // Mac before, held until the next Mac's first.
  function shotAt(p) {
    var i = 0;
    while (i < KEYS.length - 1 && p >= KEYS[i + 1][0]) i++;
    var a = KEYS[i], b = KEYS[i + 1] && KEYS[i + 1][1] === a[1] ? KEYS[i + 1] : a;
    var k = b === a ? 0 : smooth(Math.max(0, Math.min(1, (p - a[0]) / (b[0] - a[0]))));
    function mix(j) { return a[j] + (b[j] - a[j]) * k; }
    return {
      model: a[1], face: a[2], th: mix(3), ph: mix(4), mul: mix(5), aim: mix(6), shift: mix(7),
      ready: a[1] === 'studio' ? PORTS.filter(function (name, j) { return p >= READY_AT[j]; }) : []
    };
  }
  function captionAt(p) {
    var cap = '';
    CAPTIONS.forEach(function (c) { if (p >= c[0]) cap = c[1]; });
    return cap;
  }

  // On when the screen is roomy and motion is fine, unless the viewer has failed. The class goes on
  // only once WebGL is known to be there, and before the section comes near, so the page does not move.
  function setUp() {
    var on = roomy.matches && !still.matches && !failed;
    if (on && !see.classList.contains('is-scroll') && 'IntersectionObserver' in window && hasWebGL()) see.classList.add('is-scroll');
    on = on && see.classList.contains('is-scroll');
    if (on === active) return;
    active = on;
    shown = -1;
    if (active) { fresh = true; measure(); return; }
    free = true; caption = '';
    block.classList.remove('is-driven', 'is-cut');
    block.removeAttribute('data-caption');
    intro.style.opacity = ''; intro.classList.remove('is-gone');
  }

  // Layout is read here only: on resize, and when anything above the section changes its height. The
  // section's content box, not the intro, which is pinned and would report where it is pinned.
  function measure() {
    if (!active) return;
    y = window.scrollY;
    var r = see.getBoundingClientRect();
    top0 = r.top + y; bottom0 = r.bottom + y;
    from = top0 + parseFloat(window.getComputedStyle(see).paddingTop);
    span = Math.max(1, bottom0 - block.offsetHeight - from);
    shown = -1;
    queue();
  }
  function queue() {
    if (queued || !active) return;
    queued = true;
    window.requestAnimationFrame(function () { queued = false; apply(); });
  }
  function apply() {
    if (!active) return;
    var p = Math.max(0, Math.min(1, (y - from) / span));
    if (p === shown && !fresh) return;
    shown = p;
    // The intro fades out as the Mac turns away from it; faded out, it takes no clicks from the viewer under
    // it (.is-gone, styles.css), and stays in the accessibility tree.
    var o = 1 - smooth(Math.max(0, Math.min(1, (p - 0.025) / 0.06)));
    intro.style.opacity = String(o);
    intro.classList.toggle('is-gone', !o);
    var shot = shotAt(p >= RELEASE ? 1 : p), cap = captionAt(p);
    if (cap !== caption) {
      caption = cap;
      block.setAttribute('data-caption', cap);
      if (cap === 'info') block.classList.remove('is-cut');
    }
    var was = free;
    free = p >= RELEASE;
    if (free !== was) {
      if (!free && root.contains(document.activeElement)) {
        // Keyboard focus that has just come into the viewer from below (Shift+Tab: the browser then
        // scrolls the control into view, which is inside the sequence): the viewer stays the person's,
        // as it does for focus from above (skip).
        if (arrived && performance.now() - arrived < 1000) { arrived = 0; skip(); return; }
        // Taken back as the person scrolls: the viewer gives up the focus (focus coming back to the
        // window would otherwise land in it again, and end the sequence).
        document.activeElement.blur();
      }
      block.classList.toggle('is-driven', !free);
      if (!free) {
        showHover(null); // and the label
        // A drag that began while the viewer was the person's ends here: its button may come up while the
        // canvas is not listening.
        if (viewer) viewer.pointerCancel();
      } else {
        block.classList.remove('is-cut');
      }
    }
    // The Mac on screen, in the picker and the caption too, even before the scene is in. Once the viewer is
    // the person's, the Mac stays the one they pick; the hand-back gives them the Mac mini.
    if (model !== shot.model && (!free || !was)) {
      // A caption still fading out goes at once, or it would fade out with the next Mac's words in it; the
      // next Mac's fades in.
      if (!free && caption !== 'info') block.classList.add('is-cut');
      choose(shot.model);
    }
    if (!viewer) return;
    if (!free) {
      viewer.steer(shot, fresh);
    } else if (!was || (fresh && model === shot.model)) {
      viewer.steer(shot, fresh);
      viewer.steer(null);
    }
    fresh = false;
  }

  // A click on the picker while the sequence runs: the page scrolls to that Mac's first stop, and the
  // sequence takes it there.
  function visit(next) {
    if (next === model || !(next in FIRST)) return;
    window.scrollTo({ top: from + FIRST[next] * span, behavior: 'smooth' });
  }

  // When keyboard focus last came into the viewer while it was the person's (see apply); a wheel, a touch
  // or any key but Tab after that is the person scrolling, not the browser.
  var arrived = 0;
  function keyboardFocus(el) {
    try { return el.matches(':focus-visible'); } catch (e) { return false; }
  }
  // Keyboard focus inside the viewer, or a click on one of its port buttons (only assistive technology
  // can reach them while they are hidden), jumps to the end of the sequence, where the viewer is the
  // person's, on the Mac mini, so the controls work from there. A port button pressed on another Mac
  // belongs to a Mac that is no longer on show, so that press does nothing. The picker is the exception:
  // a click on it goes to a Mac (visit), and the focus a click gives it (Chrome and Firefox do) stays
  // where it is. Capture: before the control's own handler.
  function skip() {
    if (!active || free) return;
    y = from + span;
    window.scrollTo({ top: y, behavior: 'instant' });
    apply();
  }
  root.addEventListener('focus', function (e) {
    if (active && free && keyboardFocus(e.target)) arrived = performance.now();
    if (e.target.closest('.mv-seg') && !keyboardFocus(e.target)) return;
    skip();
  }, true);
  ['wheel', 'touchstart'].forEach(function (type) {
    window.addEventListener(type, function () { arrived = 0; }, { passive: true });
  });
  window.addEventListener('keydown', function (e) { if (e.key !== 'Tab' && e.key !== 'Shift') arrived = 0; }, true);
  root.addEventListener('click', function (e) {
    if (e.target.closest('button') && !e.target.closest('.mv-seg')) skip();
  }, true);

  window.addEventListener('scroll', function () { y = window.scrollY; queue(); }, { passive: true });
  if (typeof window.addStops === 'function') {
    window.addStops(function () {
      return active ? MOMENTS.map(function (p) { return from + p * span; }) : null;
    });
  }
  if (typeof ResizeObserver !== 'undefined') new ResizeObserver(measure).observe(document.body);
  else window.addEventListener('resize', measure);
  // Narrower or shorter than the sequence needs: today's section, and the scene starts again as today's.
  // The section has already lost its length by now (styles.css drops it under the same query), so where
  // the reader was comes from the last measure: in the section, the frame comes into view (landed); below
  // it, scroll anchoring keeps the place.
  onChange(roomy, function () {
    var was = active, inside = active && y > top0 && y < bottom0;
    setUp();
    if (was && !active && viewer) { stop(); start(); }
    if (was && !active && inside) landed();
  });
  setUp();

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
