// The Why diagrams in 3D: in each figure, two Mac Studios (createMacKit, mac-scene.js) seen from behind,
// turned a little toward each other, with two cables between their back Thunderbolt ports.
//
// tools/why.py still writes each figure's drawing, and the drawing is what the figure shows without
// JavaScript or WebGL, until the 3D has drawn its first frame, after a lost context, and in a figure whose
// drawing is narrower than NARROW px (styles.css switches at the same width, with a container query).
//
// The script is why.py's, read from its desktop drawing so the two cannot drift apart: the 18 s run, the
// broadcast times (EMIT), the lap, how long a copy takes to cross a cable, and G, the moment the page
// opens on. In the bridge (left) each broadcast leaves both ports of the Mac that sends it; each copy
// crosses its cable, goes through the other Mac's bridge (the bracket over its ports) and out of its other
// port, and keeps going round, twenty of them after ten broadcasts, while the cables and the bridges warm
// up. With RDMALink (right) each copy crosses once and lands with a ping. Both figures read one clock, so
// they stay in step. The count, the Macs' names, bridge0 and the fe80:: addresses are HTML over the scene,
// placed with the camera when the frame changes size.
//
// The camera frames the ports, the bridges and the cables, with the Macs standing whole above them; when
// the frame is wider than that, it shows more of the Macs and lets the rest run off its sides. The stage
// has a height of its own (styles.css, --why-stage-h), so it does not grow with its width.
//
// The clock runs only while a figure is on screen, the tab shows, Pause is off (data-paused on #why,
// site.js) and motion is welcome. With prefers-reduced-motion each figure holds one frame (see now()).
// Each figure draws only while it is on screen, at most 30 frames a second, and not at all while nothing
// moves. Both draw with one WebGL context (see "the shared renderer"), and one kit for their four Macs.
// three.js loads (loadThree, shared with hero.js and viewer.js) when the figures are wide enough and
// either come near or the hero's opening is over (see "running both"), and the scene is made a step at a
// time, so making it never holds up a scroll.
(function () {
  'use strict';
  var why = document.getElementById('why');
  var figs = why ? why.querySelectorAll('.why-fig') : [];
  if (figs.length !== 2 || !('IntersectionObserver' in window) || typeof ResizeObserver === 'undefined') return;

  var NARROW = 360;          // px of drawing width (the figure's content box) from which the 3D shows; styles.css too
  var SMALL = 480;           // px of drawing width under which the labels are smaller (styles.css) and the margins too
  var FPS = 30;
  var FADE = [16.6, 17.4];   // tools/why.py FADE: the copies fade out together, then the script starts again
  var STREAK = 0.13;         // s of travel behind a copy's head: shorter than the closest two copies ever get
  var PING = 0.7;            // s, as why.py's ping

  // The script, from why.py's desktop drawing: --d on each copy that crosses (right) is EMIT - G, and on
  // each ping EMIT + arrive - G; the run's duration and delay are T and -G; a lap is LAP.
  function readScript() {
    var run = why.querySelector('.wd-run'), lap = why.querySelector('.wd-lap');
    var hops = why.querySelectorAll('.wd-hop'), pings = why.querySelectorAll('.wd-ping');
    if (!run || !lap || hops.length < 4 || hops.length !== pings.length) return null;
    function d(el) { return parseFloat(el.style.getPropertyValue('--d')); }
    var cs = window.getComputedStyle(run);
    var s = {
      T: parseFloat(cs.animationDuration), G: -parseFloat(cs.animationDelay),
      LAP: parseFloat(window.getComputedStyle(lap).animationDuration), EMIT: []
    };
    for (var i = 0; i < hops.length; i += 2) s.EMIT.push(d(hops[i]) + s.G);
    s.ARRIVE = d(pings[0]) - d(hops[0]);
    var ok = [s.T, s.G, s.LAP, s.ARRIVE].concat(s.EMIT).every(function (v) { return isFinite(v); });
    return ok && s.ARRIVE > 0 && s.LAP > 2 * s.ARRIVE ? s : null;
  }
  var S = readScript();
  if (!S) return;
  // The share of a lap a copy spends on a cable; the rest of each half lap it is in a bridge.
  var C = S.ARRIVE / S.LAP;

  // With WebGL (hasWebGL, motion.js: asked once for the page), the drawings take the stage's height
  // now (styles.css, .why-3d-soon), so nothing moves when the 3D takes their place. If the 3D cannot
  // start, fail() gives them their own height back.
  function hasWebGL() { return typeof window.hasWebGL === 'function' && window.hasWebGL(); }
  if (hasWebGL()) why.classList.add('why-3d-soon');

  var light = window.matchMedia('(prefers-color-scheme: light)');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  function theme() { return light.matches ? 'light' : 'dark'; }
  function onChange(mq, fn) {
    if (mq.addEventListener) mq.addEventListener('change', fn);
    else if (mq.addListener) mq.addListener(fn);
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function easeOut(k) { return 1 - Math.pow(1 - k, 3); }
  function smooth(a, b, v) { var k = clamp((v - a) / (b - a), 0, 1); return k * k * (3 - 2 * k); }

  // ---------- the script at time t (0 to T) ----------
  var NONE = -100;
  // How far the copies have faded at the end of the run: 1 until FADE, then down to 0.
  function fadeAt(t) { return t < FADE[0] ? 1 : t < FADE[1] ? 1 - (t - FADE[0]) / (FADE[1] - FADE[0]) : 0; }
  // How many copies are going round: two for every broadcast that has reached the other Mac.
  function countAt(t) {
    var n = 0;
    S.EMIT.forEach(function (e) { if (t >= e + S.ARRIVE) n += 2; });
    return t < FADE[1] ? n : 0;
  }
  // The warmth of the loop: each arrival adds a tenth, over 0.6 s; it fades with the copies.
  function heatAt(t) {
    var h = 0;
    S.EMIT.forEach(function (e) { h += clamp((t - e - S.ARRIVE) / 0.6, 0, 1); });
    return h / S.EMIT.length * fadeAt(t);
  }
  // Left: where each copy's head is on the loop, 0 to 1 from Mac A's first port, clockwise: cable 1
  // (A1 to B1) over [0, C), Mac B's bridge to [0.5), cable 2 (B2 to A2) to [0.5 + C), Mac A's bridge to 1.
  // Mac A sends from s = 0 (clockwise, `fwd`) and from s = 0.5 + C (counter-clockwise, `back`); Mac B,
  // every other broadcast, from 0.5 and from C.
  function loopAt(t, fwd, back) {
    S.EMIT.forEach(function (e, k) {
      if (t < e || t >= FADE[1]) { fwd[k] = back[k] = NONE; return; }
      var q = (t - e) / S.LAP, b = k % 2;
      fwd[k] = frac((b ? 0.5 : 0) + q);
      back[k] = frac((b ? C : 0.5 + C) - q);
    });
  }
  // Right: each copy's head along its cable, 0 at Mac A, 1 at Mac B; `fwd` for Mac A's broadcasts, `back`
  // for Mac B's. A head runs on past the port until its streak has gone in.
  function hopsAt(t, fwd, back) {
    var tail = (STREAK + 0.05) / S.ARRIVE;
    S.EMIT.forEach(function (e, k) {
      var h = (t - e) / S.ARRIVE;
      var on = h >= 0 && h <= 1 + tail;
      fwd[k] = on && k % 2 === 0 ? h : NONE;
      back[k] = on && k % 2 === 1 ? 1 - h : NONE;
    });
  }
  function frac(v) { return v - Math.floor(v); }

  // ---------- markup ----------
  // Each figure gets a stage after its drawing: the canvas and the labels. It stays hidden (styles.css)
  // until the figure is .is-3d. The stage takes over the drawing's description.
  var LABELS = {
    left: ['Mac A', 'Mac B', 'bridge0', 'bridge0'],
    right: ['Mac A', 'Mac B', 'bridge0', 'bridge0', 'fe80::…%en5', 'fe80::…%en6']
  };
  function stageFor(fig, side) {
    var svg = fig.querySelector('svg[role="img"]');
    var stage = document.createElement('div');
    stage.className = 'why-stage';
    stage.setAttribute('role', 'img');
    if (svg) stage.setAttribute('aria-label', svg.getAttribute('aria-label'));
    var canvas = document.createElement('canvas');
    canvas.className = 'why-canvas';
    stage.appendChild(canvas);
    var tags = document.createElement('div');
    tags.className = 'why-tags';
    tags.setAttribute('aria-hidden', 'true');
    var spans = LABELS[side].map(function (text, i) {
      var s = document.createElement('span');
      s.className = 'why-tag' + (i < 2 ? ' why-tag-mac' : i < 4 ? ' why-tag-bridge' : ' why-tag-addr');
      s.textContent = text;
      tags.appendChild(s);
      return s;
    });
    var count = document.createElement('span');
    count.className = 'why-count why-count-' + side;
    var num = document.createElement('span');
    num.className = 'why-num';
    num.textContent = side === 'left' ? '' : '0';
    var going = document.createElement('span');
    going.className = 'why-going';
    going.textContent = 'going round';
    count.appendChild(num);
    count.appendChild(going);
    tags.appendChild(count);
    stage.appendChild(tags);
    var before = fig.querySelector('.why-pause');
    fig.insertBefore(stage, before);
    return { fig: fig, stage: stage, canvas: canvas, tags: spans, count: count, num: num };
  }

  // ---------- the glow ----------
  // One material draws the light on a cable or a bridge: a sheath round it, lit by the copies' streaks and
  // by a steady glow. Each mesh maps its length (uv.x) onto the loop (or its cable) with uRange; the heads
  // are shared by every mesh of a figure. In the dark the light is added, and a streak's sheath fades
  // toward its edges (uSoft). On a light page added light washes out, so it is laid over instead (uLight):
  // each streak a solid capsule as wide as the cable, in a faint halo of its colour. Either way the steady
  // glow lights only the halo round a cable, never the cable itself, which stays graphite or white: a
  // little orange on the cable reads as copper, not light.
  var GLOW_VERT = [
    'uniform vec2 uRange;',
    'varying float vS;',
    'varying float vFacing;',
    'void main() {',
    '  vS = mix(uRange.x, uRange.y, uv.x);',
    '  vec4 mv = modelViewMatrix * vec4(position, 1.0);',
    '  vFacing = abs(dot(normalize(normalMatrix * normal), normalize(-mv.xyz)));',
    '  gl_Position = projectionMatrix * mv;',
    '}'
  ].join('\n');
  var GLOW_FRAG = [
    'uniform float uFwd[10];',
    'uniform float uBack[10];',
    'uniform float uLen;',
    'uniform float uWrap;',
    'uniform float uFade;',
    'uniform float uSteady;',
    'uniform float uSoft;',
    'uniform float uTail;',
    'uniform float uLight;',
    'uniform vec3 uColor;',
    'uniform vec3 uCore;',
    'varying float vS;',
    'varying float vFacing;',
    // d: how far a point is behind a head (negative: ahead of it). On the loop, the nearest way round.
    'float streak(float d) {',
    '  if (uWrap > 0.5) d -= floor(d + 0.5);',
    '  float lead = uLen * 0.2;',
    '  if (d < -lead || d > uLen) return 0.0;',
    '  if (d < 0.0) return smoothstep(-lead, 0.0, d);',
    '  return pow(1.0 - d / uLen, uTail);',
    '}',
    'void main() {',
    '  float p = 0.0;',
    '  for (int i = 0; i < 10; i++) {',
    '    if (uFwd[i] > -50.0) p = max(p, streak(uFwd[i] - vS));',
    '    if (uBack[i] > -50.0) p = max(p, streak(vS - uBack[i]));',
    '  }',
    '  p *= uFade;',
    '  vec3 c = mix(uColor, uCore, pow(p, 5.0));',
    // The cable's edge, seen through a sheath 0.46 / 0.2 times as wide, is where vFacing is about 0.9.
    '  float core = smoothstep(0.84, 0.92, vFacing), halo = (1.0 - core) * vFacing;',
    '  float a = uLight > 0.5 ? core * clamp(p * 1.8, 0.0, 1.0) + halo * 0.3 * p : p * pow(vFacing, uSoft);',
    '  gl_FragColor = vec4(c, clamp(a + halo * uSteady, 0.0, 1.0));',
    '}'
  ].join('\n');

  // ---------- the shared renderer ----------
  // The two figures are always on screen together, so they share one WebGL context: a renderer on a
  // canvas of its own, off the page, as large as the larger figure. A figure renders into the bottom left
  // of it and copies that, in the same frame, onto its own canvas, a 2D one. The kit (the Macs' materials,
  // textures and studio light) and the shaders are then made once for both. The picture is opaque, on
  // the panel's colour (--site-panel), so the copy is exactly what was drawn.
  // Its pixel ratio is the screen's, up to 2: the figures are never large enough for pixelRatio's budget
  // (mac-scene.js) to bring it down.
  var glCanvas = document.createElement('canvas');
  function makeShared() {
    var T = window.THREE;
    var renderer = new T.WebGLRenderer({ canvas: glCanvas, antialias: true, alpha: false });
    if (!renderer.getContext()) throw new Error('no context');
    renderer.debug.checkShaderErrors = false; // no shader logs read back after each link (mac-scene.js)
    renderer.resetState(); // after a lost context comes back, the canvas may hand over the old one (mac-scene.js)
    var pr = Math.min(window.devicePixelRatio || 1, 2);
    renderer.setPixelRatio(pr);
    renderer.outputEncoding = T.sRGBEncoding;
    renderer.toneMapping = T.ACESFilmicToneMapping;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    renderer.shadowMap.autoUpdate = false; // nothing that casts a shadow moves: each figure says when to redraw its own
    var kit = createMacKit(T, renderer);
    var sizes = {}, w0 = 0, h0 = 0;
    return {
      kit: kit, pr: pr,
      // The renderer is as large as the larger figure.
      fit: function (side, w, h) {
        sizes[side] = [w, h];
        var w1 = 0, h1 = 0;
        Object.keys(sizes).forEach(function (k) { w1 = Math.max(w1, sizes[k][0]); h1 = Math.max(h1, sizes[k][1]); });
        if (w1 !== w0 || h1 !== h0) { w0 = w1; h0 = h1; renderer.setSize(w0, h0, false); }
      },
      ground: function (color) { renderer.setClearColor(color, 1); },
      // Links a figure's shaders now, a step before its first frame.
      compile: function (scene, camera) { renderer.compile(scene, camera); },
      // Renders a figure's scene, w x h CSS px, and copies it onto `to`, its canvas's 2D context. The
      // viewport is the bottom left of the canvas, so the copy is from the canvas's bottom rows.
      draw: function (scene, camera, w, h, shadow, to) {
        renderer.setViewport(0, 0, w, h);
        renderer.shadowMap.needsUpdate = shadow;
        renderer.render(scene, camera);
        var vw = Math.floor(w * pr), vh = Math.floor(h * pr);
        to.drawImage(glCanvas, 0, glCanvas.height - vh, vw, vh, 0, 0, to.canvas.width, to.canvas.height);
      },
      // `release`: hand the context back now (the 3D is not coming back), rather than at GC.
      dispose: function (release) {
        try { kit.dispose(); } catch (e) { /* its context is gone already */ }
        renderer.dispose();
        if (release) { try { renderer.forceContextLoss(); } catch (e) { /* no WEBGL_lose_context */ } }
      }
    };
  }

  // ---------- one figure ----------
  var D = 11.5;                // cm from the middle to each Mac's centre: turned, their backs' corners 1.6 cm apart
  var TURN = 0.12;             // rad each Mac is turned toward the other
  var VIEW = [0.5, 0.13];      // the camera: rad round to the ports' side, rad above the desk
  var BOOT = 1.9;              // cm a plug stands out of its port
  var RISE = 1.35;             // cm from a port's middle up to its bridge, which runs along the ports under the grille
  var FL = 'Back, far left', ML = 'Back, middle left', MR = 'Back, middle right', FR = 'Back, far right';
  var BACK = [FL, ML, MR, FR];

  function makeFigure(el, side, shared) {
    var T = window.THREE;
    var left = side === 'left';
    var canvas = el.canvas;
    var page2d = canvas.getContext('2d'); // what the figure shows: a copy of what the shared renderer drew
    if (!page2d) throw new Error('no 2D context');
    var kit = shared.kit;
    var shadow = true; // the shadow map is drawn again on the next render (shared.draw)
    var M = kit.M;
    var look = kit.paint(theme());
    var scene = new T.Scene();
    var camera = new T.PerspectiveCamera(22, 2, 4, 900);

    // Light as the viewer's, the key from the far side and to the left, but higher, so the Macs' shadows
    // stay under them rather than run out of the frame; the rim toward the camera.
    var key = new T.DirectionalLight(0xffffff, look.key);
    key.castShadow = true;
    key.shadow.bias = -0.0004;
    key.shadow.normalBias = 0.02;
    var R = 40;
    var sc = key.shadow.camera;
    sc.left = -R; sc.right = R; sc.top = R; sc.bottom = -R; sc.near = 1; sc.far = R * 8; sc.updateProjectionMatrix();
    key.position.set(-12, 40, 12).normalize().multiplyScalar(R * 3);
    var rim = new T.DirectionalLight(0xdfe6ff, look.rim);
    rim.position.set(22, 12, -26).normalize().multiplyScalar(R * 3);
    scene.add(key, key.target, rim, rim.target);
    var ground = new T.Mesh(new T.PlaneGeometry(400, 400), new T.ShadowMaterial({ opacity: look.shadow }));
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);

    // The Macs: backs to the camera (at -z), Mac A on the left of the picture (+x), each turned toward
    // the other. Right, the two cabled ports are Ready for RDMA; the other two stay in the bridge.
    var plan = { ready: left ? [] : [FL, FR], ringed: BACK, plugged: [] };
    var macA = kit.build('studio', plan), macB = kit.build('studio', plan);
    macA.group.position.set(D, 0, 0); macA.group.rotation.y = TURN;
    macB.group.position.set(-D, 0, 0); macB.group.rotation.y = -TURN;
    scene.add(macA.group, macB.group);
    scene.updateMatrixWorld(true);
    function port(mac, name) {
      return mac.features.filter(function (f) { return f.kind === 'tb' && f.name === name; })[0];
    }
    // Cable 1 joins the two ports nearest each other, cable 2 the two furthest apart.
    var A1 = port(macA, FR), A2 = port(macA, FL), B1 = port(macB, FL), B2 = port(macB, FR);
    var blooms = [macA, macB].reduce(function (list, mac) {
      return list.concat(mac.features.filter(function (f) { return f.bloom && f.ready; }).map(function (f) { return f.bloom; }));
    }, []);

    var tmpQ = new T.Quaternion();
    function at(f, out) { return f.group.getWorldPosition(out || new T.Vector3()); }
    function out(f) { return new T.Vector3(0, 0, 1).applyQuaternion(f.group.getWorldQuaternion(tmpQ)); }
    function onMac(mac, v) { return v.clone().applyMatrix4(mac.group.matrixWorld); }

    // The plugs. Plugs and cables are graphite in the dark and white in light, so the glow on them reads
    // as light.
    var CABLE = { dark: 0x2b2c30, light: 0xe4e4e2 };
    var plugMat = new T.MeshStandardMaterial({ metalness: 0.35, roughness: 0.42 });
    var bootGeo = kit.prism(0.66, 1.2, 0.3, BOOT, 0.12);
    [A1, A2, B1, B2].forEach(function (f) {
      var boot = new T.Mesh(bootGeo, plugMat);
      boot.rotation.x = Math.PI / 2; boot.position.z = 0.02; boot.castShadow = true;
      f.group.add(boot);
    });

    // The cables: from plug to plug, leaving each along its port's normal and sagging between.
    var cableMat = new T.MeshStandardMaterial({ metalness: 0.2, roughness: 0.5, emissive: 0x000000 });
    var CABLE_R = 0.2;
    function cable(fa, fb, sag, reach) {
      var na = out(fa), nb = out(fb);
      var a = at(fa).addScaledVector(na, BOOT), b = at(fb).addScaledVector(nb, BOOT);
      var span = a.distanceTo(b), down = new T.Vector3(0, -sag, 0);
      var curve = new T.CubicBezierCurve3(a, a.clone().addScaledVector(na, span * reach).add(down),
        b.clone().addScaledVector(nb, span * reach).add(down), b);
      var mesh = new T.Mesh(new T.TubeGeometry(curve, 96, CABLE_R, 10, false), cableMat);
      mesh.castShadow = true;
      scene.add(mesh);
      // The share of the cable, port to port, that is out of the plugs.
      var len = curve.getLength(), whole = len + 2 * BOOT;
      return { curve: curve, from: BOOT / whole, to: (BOOT + len) / whole };
    }
    var cables = [cable(A1, B1, 1.9, 0.42), cable(A2, B2, 2.7, 0.62)];

    // The bridges: on each Mac's back, from one port up, along the row of ports just under the grille,
    // and down into the other: a bracket over the ports it joins, as the drawing's pill holds them.
    function bridgeCurve(fa, fb) {
      var pa = fa.pos, pb = fb.pos, z = pa.z - 0.08, top = pa.y + RISE, r = 0.45, dir = pb.x > pa.x ? 1 : -1;
      function p(x, y) { return new T.Vector3(x, y, z); }
      var path = new T.CurvePath();
      path.add(new T.LineCurve3(p(pa.x, pa.y), p(pa.x, top - r)));
      path.add(new T.QuadraticBezierCurve3(p(pa.x, top - r), p(pa.x, top), p(pa.x + dir * r, top)));
      path.add(new T.LineCurve3(p(pa.x + dir * r, top), p(pb.x - dir * r, top)));
      path.add(new T.QuadraticBezierCurve3(p(pb.x - dir * r, top), p(pb.x, top), p(pb.x, top - r)));
      path.add(new T.LineCurve3(p(pb.x, top - r), p(pb.x, pb.y)));
      return path;
    }
    // Its line is the ink, as the rings are: solid where copies go through, dashed where none do.
    var inkMat = new T.MeshBasicMaterial({ transparent: true, opacity: 0.5, depthWrite: false, toneMapped: false });
    function line(mac, curve, dashed) {
      mac.group.add(new T.Mesh(new T.TubeGeometry(curve, 120, 0.05, 6, false), dashed ? dashMat(curve.getLength()) : inkMat));
    }
    var dashMats = [];
    function dashMat(len) {
      var m = new T.ShaderMaterial({
        uniforms: { uColor: { value: new T.Color() }, uCount: { value: Math.round(len / 0.42) + 0.5 } },
        vertexShader: 'varying float vU; void main() { vU = uv.x; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
        fragmentShader: 'uniform vec3 uColor; uniform float uCount; varying float vU; void main() { if (fract(vU * uCount) > 0.55) discard; gl_FragColor = vec4(uColor, 0.45); }',
        transparent: true, depthWrite: false
      });
      dashMats.push(m);
      return m;
    }
    var bridges, bridgeMacs = [macA, macB];
    if (left) {
      bridges = [bridgeCurve(A1, A2), bridgeCurve(B1, B2)];
      line(macA, bridges[0]); line(macB, bridges[1]);
    } else {
      // Each Mac keeps its bridge, with the two ports that are not cabled; the cabled ones are out of it.
      bridges = [bridgeCurve(port(macA, MR), port(macA, ML)), bridgeCurve(port(macB, ML), port(macB, MR))];
      line(macA, bridges[0], true); line(macB, bridges[1], true);
    }

    // The light on the cables and the bridges.
    var GLOW = { cable: 0.46, bridge: 0.34 }; // cm, the sheath's radius as built
    var U = {
      fwd: { value: new Float32Array(10).fill(NONE) }, back: { value: new Float32Array(10).fill(NONE) },
      len: { value: left ? STREAK / S.LAP : STREAK / S.ARRIVE }, wrap: { value: left ? 1 : 0 },
      fade: { value: 1 }, color: { value: new T.Color() }, core: { value: new T.Color() }, soft: { value: 1.4 },
      light: { value: 0 }, tail: { value: 2 }
    };
    var glows = [];
    function glow(curve, parent, range, radius, steady) {
      var m = new T.ShaderMaterial({
        uniforms: {
          uRange: { value: new T.Vector2(range[0], range[1]) }, uFwd: U.fwd, uBack: U.back, uLen: U.len, uWrap: U.wrap,
          uFade: U.fade, uColor: U.color, uCore: U.core, uSteady: { value: steady }, uSoft: U.soft,
          uLight: U.light, uTail: U.tail
        },
        vertexShader: GLOW_VERT, fragmentShader: GLOW_FRAG, transparent: true, depthWrite: false
      });
      var mesh = new T.Mesh(new T.TubeGeometry(curve, 160, radius, 12, false), m);
      mesh.renderOrder = 2;
      parent.add(mesh);
      glows.push(m);
    }
    // A mesh over the part [f0, f1] of a path whose ends are s0 and s1 on the loop (or the cable).
    function span(s0, s1, f0, f1) { return [s0 + (s1 - s0) * f0, s0 + (s1 - s0) * f1]; }
    if (left) {
      glow(cables[0].curve, scene, span(0, C, cables[0].from, cables[0].to), GLOW.cable, 0);
      glow(cables[1].curve, scene, span(0.5 + C, 0.5, cables[1].from, cables[1].to), GLOW.cable, 0);
      glow(bridges[0], macA.group, [1, 0.5 + C], GLOW.bridge, 0);
      glow(bridges[1], macB.group, [C, 0.5], GLOW.bridge, 0);
    } else {
      glow(cables[0].curve, scene, [cables[0].from, cables[0].to], GLOW.cable, 0.2);
      glow(cables[1].curve, scene, [cables[1].from, cables[1].to], GLOW.cable, 0.2);
    }

    // Right: a ping at each port a copy lands at.
    var pings = [];
    if (!left) {
      [A1, A2, B1, B2].forEach(function (f) {
        var d = f.ringDims;
        var mesh = new T.Mesh(kit.ringGeometry(d[0] + 0.3, d[1] + 0.3, d[2] + 0.15, 0.12, 4),
          new T.MeshBasicMaterial({ transparent: true, depthWrite: false, toneMapped: false, side: T.DoubleSide }));
        mesh.position.z = 0.14; mesh.visible = false; mesh.renderOrder = 3;
        f.group.add(mesh);
        pings.push({ mesh: mesh, bloom: f.bloom, mac: f.group.parent === macA.group ? 'A' : 'B' });
      });
    }

    // What the camera frames. `need`, across and up: the cables, the bridges, and the back ports with
    // their rings. `tall`, up only: each Mac from its base to the far edge of its top, over its ports, so
    // the Macs stand whole in the picture. `body`, which the picture leans toward when it has room to
    // spare across: the whole of both Macs.
    var need = [], tall = [], body = [];
    cables.forEach(function (c) { for (var i = 0; i <= 24; i++) need.push(c.curve.getPoint(i / 24)); });
    bridges.forEach(function (curve, k) { for (var i = 0; i <= 16; i++) need.push(onMac(bridgeMacs[k], curve.getPoint(i / 16))); });
    [macA, macB].forEach(function (mac) {
      var b = mac.box, xs = [];
      mac.features.forEach(function (f) {
        if (!f.ring) return;
        xs.push(f.pos.x);
        for (var i = 0; i < 4; i++) {
          need.push(new T.Vector3((i & 1 ? 0.5 : -0.5) * f.ringDims[0], (i & 2 ? 0.5 : -0.5) * f.ringDims[1], 0).applyMatrix4(f.group.matrixWorld));
        }
      });
      [Math.min.apply(null, xs), Math.max.apply(null, xs)].forEach(function (x) {
        tall.push(onMac(mac, new T.Vector3(x, 0, b.min.z)), onMac(mac, new T.Vector3(x, b.max.y, b.max.z)));
      });
      for (var i = 0; i < 8; i++) {
        body.push(onMac(mac, new T.Vector3(i & 1 ? b.max.x : b.min.x, i & 2 ? b.max.y : b.min.y, i & 4 ? b.max.z : b.min.z)));
      }
    });

    // Where the labels sit.
    function bridgeTop(k) {
      // The middle of a bridge's bar, lifted clear of its glow.
      var mid = bridges[k].getPoint(0.5);
      return onMac(bridgeMacs[k], mid.add(new T.Vector3(0, GLOW.bridge + 0.1, 0)));
    }
    function samples(curve, n) { var pts = []; for (var i = 0; i <= n; i++) pts.push(curve.getPoint(i / n)); return pts; }
    var anchors = {
      bridgeA: bridgeTop(0), bridgeB: bridgeTop(1),
      cable1: samples(cables[0].curve, 32), cable2: samples(cables[1].curve, 32),
      macA: body.slice(0, 8), macB: body.slice(8, 16),
      topA: onMac(macA, new T.Vector3(0, macA.box.max.y, 0)), topB: onMac(macB, new T.Vector3(0, macB.box.max.y, 0))
    };

    var size = { w: 0, h: 0, inset: 0, small: false };
    var view = new T.Vector3();
    function project(v) {
      view.copy(v).project(camera);
      return [(view.x + 1) / 2 * size.w, (1 - view.y) / 2 * size.h];
    }
    // The picture's box of some points, in NDC: [left, bottom, right, top].
    function bounds(points, b) {
      b = b || [Infinity, Infinity, -Infinity, -Infinity];
      points.forEach(function (p) {
        view.copy(p).project(camera);
        b[0] = Math.min(b[0], view.x); b[1] = Math.min(b[1], view.y); b[2] = Math.max(b[2], view.x); b[3] = Math.max(b[3], view.y);
      });
      return b;
    }
    // The camera: round to the side of the ports, a little above. Back far enough that `need` fits across
    // and `need` and `tall` fit up, with room above the Macs for their names and below the cables for a
    // label; then the picture is moved so its middle sits between those margins, and across toward the
    // middle of both Macs as far as `need` allows. `reserve` keeps that many px clear on the right, for
    // the count when the picture leaves it nowhere else (see place()).
    var target = new T.Vector3();
    var dir = new T.Vector3(Math.sin(VIEW[0]) * Math.cos(VIEW[1]), Math.sin(VIEW[1]), -Math.cos(VIEW[0]) * Math.cos(VIEW[1]));
    new T.Box3().setFromPoints(need.concat(tall)).getCenter(target);
    function fit(reserve) {
      camera.aspect = size.w / size.h;
      camera.clearViewOffset();
      camera.updateProjectionMatrix();
      var m = size.small ? [22, 24, 6] : [28, 28, 10], side = size.inset + m[2];
      var top = m[0] / size.h * 2, bottom = m[1] / size.h * 2;
      var u0 = -1 + side / size.w * 2, u1 = 1 - (side + (reserve || 0)) / size.w * 2; // across, in NDC
      var dist = 120, n, v;
      for (var i = 0; i < 6; i++) {
        camera.position.copy(target).addScaledVector(dir, dist);
        camera.lookAt(target);
        camera.updateMatrixWorld();
        n = bounds(need); v = bounds(tall, n.slice());
        dist *= Math.max((n[2] - n[0]) / (u1 - u0), (v[3] - v[1]) / (2 - top - bottom));
      }
      camera.position.copy(target).addScaledVector(dir, dist);
      camera.lookAt(target);
      camera.updateMatrixWorld();
      n = bounds(need); v = bounds(tall, n.slice());
      var a = bounds(body);
      var shift = clamp((u0 + u1) / 2 - (a[0] + a[2]) / 2, u0 - n[0], u1 - n[2]);
      var cy = (v[1] + v[3]) / 2 - (bottom - top) / 2;
      camera.setViewOffset(size.w, size.h, -shift * size.w / 2, -cy * size.h / 2, size.w, size.h);
      camera.updateProjectionMatrix();
      camera.updateMatrixWorld();
      if (!place() && !reserve) fit(el.count.offsetWidth + (size.small ? 10 : 16));
    }

    // ---------- the labels ----------
    // They are placed when the frame changes size, never per frame: their sizes are read then. A box is
    // [x, y, w, h] in px.
    // A label's box at xy by the point (ax, ay) of its own box (0.5, 1: the middle of its bottom edge), dy px
    // lower, and kept inside the frame.
    function box(span, xy, ax, ay, dy) {
      var w = span.offsetWidth, h = span.offsetHeight, x0 = size.inset + 2;
      return [clamp(xy[0] - ax * w, x0, size.w - x0 - w), clamp(xy[1] - ay * h + dy, 0, size.h - h - 1), w, h];
    }
    function put(span, b) {
      span.style.transform = 'translate(' + Math.round(b[0]) + 'px, ' + Math.round(b[1]) + 'px)';
      return b;
    }
    function hits(a, b, gap) {
      return a[0] < b[0] + b[2] + gap && b[0] < a[0] + a[2] + gap && a[1] < b[1] + b[3] + gap && b[1] < a[1] + a[3] + gap;
    }
    // How many px a length r (cm) comes to, upright, at a point.
    function px(p, r) {
      var a = project(p), b = project(p.clone().add(new T.Vector3(0, r, 0)));
      return Math.abs(a[1] - b[1]);
    }
    // The point of a cable lowest in the picture.
    function lowest(points) {
      var best = null, y = -Infinity;
      points.forEach(function (p) { var q = project(p); if (q[1] > y) { y = q[1]; best = p; } });
      return best;
    }
    // A Mac's outline in the picture: the convex hull of its corners, in order.
    function hull(points) {
      var q = points.map(project).sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; }), lo = [], hi = [];
      function turn(o, a, b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
      q.forEach(function (p) { while (lo.length > 1 && turn(lo[lo.length - 2], lo[lo.length - 1], p) <= 0) lo.pop(); lo.push(p); });
      q.slice().reverse().forEach(function (p) { while (hi.length > 1 && turn(hi[hi.length - 2], hi[hi.length - 1], p) <= 0) hi.pop(); hi.push(p); });
      return lo.slice(0, -1).concat(hi.slice(0, -1));
    }
    function within(poly, x, y) {
      for (var i = 0; i < poly.length; i++) {
        var a = poly[i], b = poly[(i + 1) % poly.length];
        if ((b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]) < 0) return false;
      }
      return true;
    }
    // Whether a box, grown by `gap`, keeps inside the frame and clear of the cables (and their glow), of
    // the Macs' outlines and of the labels already placed.
    function free(b, room) {
      var g = room.gap, x0 = b[0] - g, y0 = b[1] - g, x1 = b[0] + b[2] + g, y1 = b[1] + b[3] + g, i, j;
      if (b[0] < size.inset + 2 || b[1] < 0 || b[0] + b[2] > size.w - size.inset - 2 || b[1] + b[3] > size.h - 1) return false;
      for (i = 0; i < room.cables.length; i++) {
        var q = room.cables[i];
        if (q[0] > x0 - room.r && q[0] < x1 + room.r && q[1] > y0 - room.r && q[1] < y1 + room.r) return false;
      }
      for (i = 0; i < room.macs.length; i++) {
        var poly = room.macs[i];
        for (j = 0; j < poly.length; j++) if (poly[j][0] > x0 && poly[j][0] < x1 && poly[j][1] > y0 && poly[j][1] < y1) return false;
        for (var sx = x0; sx <= x1 + 0.1; sx += Math.max(1, (x1 - x0) / 8)) {
          if (within(poly, sx, y0) || within(poly, sx, y1)) return false;
        }
        if (within(poly, x0, (y0 + y1) / 2) || within(poly, x1, (y0 + y1) / 2)) return false;
      }
      for (i = 0; i < room.placed.length; i++) if (hits(b, room.placed[i], g)) return false;
      return true;
    }
    // The free place nearest to `want` (a box), at most `reach` px away, or null.
    function seek(want, room, reach) {
      var tries = [], step = Math.max(4, Math.round(reach / 30));
      for (var dy = -reach; dy <= reach; dy += step) for (var dx = -reach; dx <= reach; dx += step) {
        if (dx * dx + dy * dy <= reach * reach) tries.push([dx * dx + dy * dy, dx, dy]);
      }
      tries.sort(function (a, b) { return a[0] - b[0]; });
      for (var i = 0; i < tries.length; i++) {
        var b = [want[0] + tries[i][1], want[1] + tries[i][2], want[2], want[3]];
        if (free(b, room)) return b;
      }
      return null;
    }
    function place() {
      var tags = el.tags, gap = size.small ? 5 : 8;
      var room = {
        gap: gap, r: px(anchors.cable2[16], GLOW.cable) * 0.8, placed: [],
        cables: anchors.cable1.concat(anchors.cable2).map(project), macs: [hull(anchors.macA), hull(anchors.macB)]
      };
      // A Mac's name: over the middle of its top, as far as the frame lets it, just above its highest corner.
      [[tags[0], anchors.topA, room.macs[0]], [tags[1], anchors.topB, room.macs[1]]].forEach(function (t) {
        var xy = project(t[1]);
        xy[1] = Math.min.apply(null, t[2].map(function (q) { return q[1]; }));
        room.placed.push(put(t[0], box(t[0], xy, 0.5, 1, -gap)));
      });
      // bridge0: over the bar of its bridge, clear of its glow.
      room.placed.push(put(tags[2], box(tags[2], project(anchors.bridgeA), 0.5, 1, -3)));
      room.placed.push(put(tags[3], box(tags[3], project(anchors.bridgeB), 0.5, 1, -3)));
      // The count: beside the outer cable, level with its lowest point, or the nearest place clear of the
      // cables and the Macs. Where there is none, fit() makes room on the right and asks again.
      var right = -Infinity, low = project(lowest(anchors.cable2));
      anchors.cable2.forEach(function (p) { right = Math.max(right, project(p)[0]); });
      var cw = el.count.offsetWidth, ch = el.count.offsetHeight;
      var count = seek([right + 2 * gap, low[1] - ch / 2, cw, ch], room, 96);
      room.placed.push(put(el.count, count || box(el.count, [right + 2 * gap, low[1]], 0, 0.5, 0)));
      if (!left) {
        // The addresses, in chips like bridge0's: en5 over the lowest point of cable 1, en6 under that of
        // cable 2, as the drawing has them, or the nearest place clear of the cables and the other labels.
        var chips = { gap: gap, r: room.r, placed: room.placed, cables: room.cables, macs: [] };
        [[tags[4], lowest(anchors.cable1), -1], [tags[5], lowest(anchors.cable2), 1]].forEach(function (t) {
          var xy = project(t[1]), w = t[0].offsetWidth, h = t[0].offsetHeight;
          var y = t[2] < 0 ? xy[1] - room.r - gap / 2 - h : xy[1] + room.r + gap / 2;
          var b = seek([xy[0] - w / 2, y, w, h], chips, 72) || box(t[0], [xy[0], y], 0.5, 0, 0);
          room.placed.push(put(t[0], b));
        });
      }
      return !!count;
    }

    // The canvas runs into the figure's padding, so the Macs run off at the panel's edges; `drawing` is the
    // figure's content width, which the labels and the cables keep within.
    function resize(w, h, drawing) {
      w = Math.round(w); h = Math.round(h); drawing = drawing || w;
      var inset = Math.max(0, Math.round((w - drawing) / 2)), small = drawing < SMALL;
      if (!w || !h || (w === size.w && h === size.h && inset === size.inset && small === size.small)) return false;
      size.w = w; size.h = h; size.inset = inset; size.small = small;
      canvas.width = Math.floor(w * shared.pr); canvas.height = Math.floor(h * shared.pr);
      shared.fit(side, w, h);
      fit();
      return true;
    }

    // Colours: the loop's orange and the accent come from styles.css, so they follow the theme there.
    var ORANGE = '#ff9f0a';
    function paint() {
      look = kit.paint(theme());
      scene.environment = kit.environment();
      key.intensity = look.key; rim.intensity = look.rim;
      ground.material.opacity = look.shadow;
      var mapSize = look.shadowMap;
      if (key.shadow.mapSize.x !== mapSize) {
        key.shadow.mapSize.set(mapSize, mapSize);
        if (key.shadow.map) { key.shadow.map.dispose(); key.shadow.map = null; }
      }
      shadow = true;
      var css = window.getComputedStyle(why);
      shared.ground(css.getPropertyValue('--site-panel').trim() || (look.additive ? '#16171a' : '#ffffff'));
      var hue = new T.Color(left ? css.getPropertyValue('--site-loop').trim() || ORANGE : css.getPropertyValue('--accent').trim() || '#3d8bff');
      // A copy's head: white light added in the dark. In light, laid over (see GLOW_FRAG), with a shorter
      // tail: the loop's in the bright orange all along (its darker text tone turns brown over white), the
      // accent's running to its text tone.
      if (look.additive) {
        U.color.value.copy(hue);
        U.core.value.set(0xffffff);
      } else {
        U.color.value.set(left ? ORANGE : hue);
        U.core.value.set(left ? ORANGE : css.getPropertyValue('--accent-text').trim() || hue);
      }
      U.light.value = look.additive ? 0 : 1;
      U.tail.value = look.additive ? 2 : 3;
      var blending = look.additive ? T.AdditiveBlending : T.NormalBlending;
      glows.forEach(function (g) { g.blending = blending; });
      inkMat.color.copy(kit.srgb(look.ink));
      plugMat.color.copy(kit.srgb(CABLE[theme()]));
      cableMat.color.copy(kit.srgb(CABLE[theme()]));
      dashMats.forEach(function (m) { m.uniforms.uColor.value.set(look.ink); });
      blooms.forEach(function (b) { b.material.color.copy(M.bloom.color); b.material.blending = blending; b.material.opacity = look.bloom; });
      pings.forEach(function (p) { p.mesh.material.color.copy(M.ready.color); p.mesh.material.blending = blending; });
      // The heat lights the dark cables from inside; a white cable would only turn peach, so in light the
      // glow round it carries the heat alone.
      if (left && look.additive) cableMat.emissive.copy(hue).convertSRGBToLinear();
      else cableMat.emissive.set(0x000000);
    }

    var shown = { count: -1, fade: -1 };
    function update(t) {
      if (left) {
        loopAt(t, U.fwd.value, U.back.value);
        var heat = heatAt(t);
        // The warmth builds in the halo round the cables, and comes late to the cables themselves: a little
        // orange light on graphite only looks like copper, so they light up only once the halo is bright,
        // in the last part of the pile-up. At its height the glow stays under the streaks.
        glows.forEach(function (g) { g.uniforms.uSteady.value = heat * heat * (look.additive ? 0.3 : 0.22); });
        cableMat.emissiveIntensity = smooth(0.7, 1, heat) * 0.3;
        U.fade.value = fadeAt(t);
        var n = countAt(t), f = n ? fadeAt(t) : 0;
        if (n !== shown.count) { el.num.textContent = n ? String(n) : ''; shown.count = n; }
        if (f !== shown.fade) { el.count.style.opacity = String(f); shown.fade = f; }
      } else {
        hopsAt(t, U.fwd.value, U.back.value);
        // A landing rings out from both ports of the Mac it reaches, and their Ready glow flares.
        pings.forEach(function (p) { p.mesh.visible = false; p.bloom.material.opacity = look.bloom; });
        S.EMIT.forEach(function (e, k) {
          var age = t - e - S.ARRIVE;
          if (age < 0 || age >= PING) return;
          var k1 = easeOut(age / PING);
          pings.forEach(function (p) {
            if (p.mac !== (k % 2 ? 'A' : 'B')) return;
            p.mesh.visible = true;
            p.mesh.scale.setScalar(1 + 1.3 * k1);
            p.mesh.material.opacity = 0.9 * (1 - k1);
            p.bloom.material.opacity = look.bloom + (1 - look.bloom) * (1 - k1);
          });
        });
      }
    }
    function render() {
      if (!size.w) return;
      shared.draw(scene, camera, size.w, size.h, shadow, page2d);
      shadow = false;
    }

    // Everything in the scene that is not the kit's; the kit and the renderer go with the shared renderer.
    function dispose() {
      kit.disposeObject(scene);
      if (key.shadow.map) key.shadow.map.dispose();
    }

    function compile() { shared.compile(scene, camera); }

    paint();
    return { side: side, canvas: canvas, el: el, resize: resize, paint: paint, update: update, render: render, compile: compile, dispose: dispose, visible: false, dirty: true };
  }

  // ---------- running both ----------
  var els = [stageFor(figs[0], 'left'), stageFor(figs[1], 'right')];
  var figures = null, shared = null, failed = false, asked = false, near = false, settled = false;
  var making = 0; // while start() makes the scene: which making it is, so a lost context can cut it short
  // Each figure's drawing width: its content box, which the container queries in styles.css measure too.
  var widths = [0, 0];
  // raf: the next frame asked for; wait: the timer before it asks. After a frame it draws, the loop asks
  // for the next one only 20 ms on (past a 60 Hz screen's next frame, before the one after), so it is
  // woken about once a frame it draws, not on every frame of the screen.
  var clock = 0, last = 0, lastDraw = 0, raf = 0, wait = 0;

  function paused() { return why.getAttribute('data-paused') === 'true'; }
  function anyVisible() { return figures && figures.some(function (f) { return f.visible; }); }
  function moving() { return !still.matches && !paused() && !document.hidden && anyVisible(); }
  // With reduced motion the left figure holds G, the full loop; the right one holds two copies halfway
  // across, since at G there is nothing on its cables to show that a copy crosses once and stops.
  function now(f) {
    if (!still.matches) return (S.G + clock) % S.T;
    return f && f.side === 'right' ? S.EMIT[S.EMIT.length - 2] + S.ARRIVE * 0.55 : S.G;
  }

  function schedule(delay) {
    if (raf || wait) return;
    if (delay > 0) wait = setTimeout(function () { wait = 0; raf = requestAnimationFrame(frame); }, delay);
    else raf = requestAnimationFrame(frame);
  }
  function frame(ms) {
    raf = 0;
    if (!figures) return;
    var go = moving();
    if (go) {
      var early = 1000 / FPS - 2 - (ms - lastDraw);
      if (last && early > 0) { schedule(early); return; }
      if (last) clock += Math.min(0.1, (ms - last) / 1000);
      last = ms; lastDraw = ms;
    } else {
      last = 0;
    }
    figures.forEach(function (f, i) {
      var t = now(f);
      if (!f.visible) return;
      if (f.want) { if (f.resize(f.wh[0], f.wh[1], widths[i])) f.dirty = true; f.want = false; }
      if (!go && !f.dirty) return;
      f.update(t);
      f.render();
      f.dirty = false;
    });
    if (go) schedule(lastDraw + 20 - performance.now());
  }
  function kick(dirty) {
    if (dirty && figures) figures.forEach(function (f) { f.dirty = true; });
    if (figures) schedule(0);
  }

  // Back to the drawings, for good ('start') or until a lost context comes back ('lost').
  function fail(why3d) {
    failed = why3d || 'start';
    making = 0;
    if (raf) { cancelAnimationFrame(raf); raf = 0; }
    if (wait) { clearTimeout(wait); wait = 0; }
    figs.forEach(function (fig) { fig.classList.remove('is-3d'); });
    if (failed === 'start') why.classList.remove('why-3d-soon');
    stop(figures || []);
    figures = null;
    // A lost context stays with the canvas, for the browser to give back; otherwise it goes now.
    if (shared) shared.dispose(failed === 'start');
    shared = null;
  }
  function stop(list) {
    list.forEach(function (f) {
      if (f.watch) f.watch.forEach(function (o) { o.disconnect(); });
      try { f.dispose(); } catch (e) { /* its context is gone already */ }
    });
  }

  // The scene is made in steps, one to a frame and in idle time where the browser gives it: the shared
  // renderer, the left figure, the right one, their shaders, and then the first frame, when the drawings
  // give way. Made at once it held the page up for about 60 ms (250 on a slow machine), mid-scroll.
  function idle(fn) {
    if (window.requestIdleCallback) window.requestIdleCallback(fn, { timeout: 200 });
    else setTimeout(fn, 16);
  }
  function start() {
    if (figures || failed || making) return;
    if (!window.THREE || typeof window.createMacKit !== 'function') { fail(); return; }
    var made = [], mine = making = {};
    var steps = [
      function () { shared = makeShared(); },
      function () { made.push(makeFigure(els[0], 'left', shared)); },
      function () { made.push(makeFigure(els[1], 'right', shared)); },
      function () { made.forEach(function (f) { f.compile(); }); }
    ];
    (function next() {
      if (making !== mine) { stop(made); return; } // lost on the way: fail() has let the rest go
      if (!steps.length) { making = 0; begin(made); return; }
      try {
        steps.shift()();
      } catch (err) {
        stop(made);
        fail();
        return;
      }
      idle(next);
    })();
  }
  function begin(made) {
    figures = made;
    figures.forEach(function (f, i) {
      f.watch = [
        // Back on screen, it draws what changed while it was off (dirty), and nothing else.
        new IntersectionObserver(function (entries) {
          f.visible = entries[entries.length - 1].isIntersecting;
          if (f.visible) kick();
        }),
        // The frame's size, from the observer rather than read every frame.
        new ResizeObserver(function (entries) {
          var r = entries[entries.length - 1].contentRect;
          f.wh = [r.width, r.height];
          f.want = true; // resize() says whether it needs drawing again
          kick();
        })
      ];
      f.watch.forEach(function (o) { o.observe(f.canvas); });
      figs[i].classList.add('is-3d');
    });
    // The first frame, now, so the drawing never gives way to an empty frame.
    figures.forEach(function (f, i) {
      f.wh = [f.canvas.clientWidth, f.canvas.clientHeight];
      f.resize(f.wh[0], f.wh[1], widths[i]);
      f.update(now(f)); f.render(); f.dirty = false;
    });
  }

  // Load once at least one figure is wide enough for the 3D and either the figures are near or the
  // hero's opening is over ('hero-settled', hero.js): from then nothing on the page moves until the reader
  // scrolls, so the scene can be made in time that is otherwise idle, before the figures are reached.
  function maybeLoad() {
    if (asked || failed || !(near || settled) || !(widths[0] >= NARROW || widths[1] >= NARROW)) return;
    asked = true;
    if (!hasWebGL() || typeof window.loadThree !== 'function') { fail(); return; }
    window.loadThree(why.getAttribute('data-three-src'), function (ok) { if (ok) start(); else fail(); });
  }
  new IntersectionObserver(function (entries) {
    near = entries[entries.length - 1].isIntersecting;
    maybeLoad();
  }, { rootMargin: '600px 0px' }).observe(why.querySelector('.why-figs'));
  document.addEventListener('hero-settled', function () { settled = true; idle(maybeLoad); });
  var ro = new ResizeObserver(function (entries) {
    entries.forEach(function (e) {
      var i = e.target === figs[0] ? 0 : 1;
      widths[i] = e.contentRect.width;
      if (figures) figures[i].want = true;
    });
    maybeLoad();
    kick();
  });
  ro.observe(figs[0]);
  ro.observe(figs[1]);

  // A lost context: the drawings, until the browser gives it back (as viewer.js does).
  glCanvas.addEventListener('webglcontextlost', function (e) { e.preventDefault(); if (figures || making) fail('lost'); }, false);
  glCanvas.addEventListener('webglcontextrestored', function () {
    if (failed !== 'lost') return;
    failed = false;
    start();
  }, false);

  // Pause (site.js), the tab, the theme and reduced motion.
  new MutationObserver(function () { last = 0; kick(true); }).observe(why, { attributes: true, attributeFilter: ['data-paused'] });
  document.addEventListener('visibilitychange', function () { last = 0; kick(); });
  onChange(light, function () { if (figures) figures.forEach(function (f) { f.paint(); }); kick(true); });
  onChange(still, function () { last = 0; kick(true); });
})();
