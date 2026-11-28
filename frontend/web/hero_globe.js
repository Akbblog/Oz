// Landing-page globe. Draws with COBE (vendor/cobe.esm.js, MIT, loaded on
// demand) and exposes a tiny API to the Flutter app:
//
//   const globe = await window.ilGlobe.mount(hostElement, {
//     markers: [{ key: 'USA', lat: 39.5, lng: -98.5 }, ...],
//   });                       // resolves to null when WebGL is unavailable
//   globe.pulse('USA', 'India');  // light a country up, draw an arc from it
//   globe.hover(nx, ny);          // pointer position, -0.5 .. 0.5 from centre
//   globe.leave();
//   globe.dragStart(); globe.drag(dxPixels); globe.dragEnd(pixelsPerSecond);
//   globe.destroy();
//
// The host element ignores pointer events on purpose: the app listens for
// them, so the mouse wheel keeps scrolling the page over the globe.
(function () {
  'use strict';

  var LIB = 'vendor/cobe.esm.js';
  var libPromise = null;

  function loadLib() {
    if (!libPromise) {
      var url = new URL(LIB, document.baseURI).href;
      libPromise = import(url).then(function (m) { return m.default; });
    }
    return libPromise;
  }

  function hasWebGL() {
    try {
      var c = document.createElement('canvas');
      return !!(c.getContext('webgl2') || c.getContext('webgl') || c.getContext('experimental-webgl'));
    } catch (e) {
      return false;
    }
  }

  // Longitude/latitude the globe should face -> COBE angles.
  function facing(lat, lng) {
    return {
      phi: Math.PI - ((lng * Math.PI) / 180 - Math.PI / 2),
      theta: (lat * Math.PI) / 180,
    };
  }

  var WARM = [0.98, 0.74, 0.32];
  var TEAL = [0.42, 0.85, 0.95];
  var VIOLET = [0.62, 0.55, 1.0];

  async function mount(host, options) {
    if (!host || !hasWebGL()) return null;
    var createGlobe;
    try {
      createGlobe = await loadLib();
    } catch (e) {
      return null;
    }

    var markers = (options && options.markers) || [];
    var byKey = {};
    markers.forEach(function (m) { byKey[m.key] = m; });

    host.style.position = 'relative';
    host.style.pointerEvents = 'none';
    host.style.overflow = 'visible';
    var canvas = document.createElement('canvas');
    canvas.style.cssText =
      'position:absolute;inset:0;width:100%;height:100%;opacity:0;transition:opacity 900ms ease;contain:layout paint size;';
    host.appendChild(canvas);

    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var size = Math.max(120, Math.round(host.clientWidth || 480));

    var start = facing(20, 62); // Middle East / South Asia first
    var phi = start.phi;
    var spin = 0;            // leftover speed from a drag (radians / second)
    var dragging = false;
    var lean = 0, leanTarget = 0;
    var nod = 0, nodTarget = 0;
    var pulses = {};         // key -> time it was lit
    var arcs = [];           // { from, to, born }
    var destroyed = false;
    var raf = 0;
    var last = performance.now();
    var visible = true;

    var globe;
    try {
      globe = createGlobe(canvas, {
        devicePixelRatio: dpr,
        width: size,
        height: size,
        phi: phi,
        theta: 0.3,
        dark: 1,
        diffuse: 1.25,
        scale: 1,
        mapSamples: 20000,
        mapBrightness: 5.2,
        mapBaseBrightness: 0.04,
        baseColor: [0.36, 0.72, 0.82],
        markerColor: WARM,
        glowColor: [0.16, 0.42, 0.50],
        offset: [0, 0],
        opacity: 0.92,
        markers: [],
        arcs: [],
        arcColor: TEAL,
        arcWidth: 0.55,
        arcHeight: 0.32,
        markerElevation: 0.02,
      });
    } catch (e) {
      host.removeChild(canvas);
      return null;
    }

    var io = null;
    if ('IntersectionObserver' in window) {
      io = new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        if (visible && !raf && !destroyed) {
          last = performance.now();
          raf = requestAnimationFrame(frame);
        }
      });
      io.observe(host);
    }
    var ro = null;
    if ('ResizeObserver' in window) {
      ro = new ResizeObserver(function () {
        var s = Math.max(120, Math.round(host.clientWidth || size));
        if (s !== size) size = s;
      });
      ro.observe(host);
    }

    function frame(now) {
      raf = 0;
      if (destroyed) return;
      var dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      var t = now / 1000;

      if (!dragging) {
        phi += (0.11 + spin) * dt;
        spin *= Math.pow(0.12, dt);
      }
      var ease = 1 - Math.pow(0.004, dt);
      lean += (leanTarget - lean) * ease;
      nod += (nodTarget - nod) * ease;

      // Markers breathe; a pulsing one swells for a moment.
      var list = markers.map(function (m, i) {
        var s = 0.034 + 0.006 * Math.sin(t * 2.1 + i * 1.7);
        var lit = pulses[m.key];
        if (lit !== undefined) {
          var age = t - lit;
          if (age < 1.6) s += 0.055 * Math.sin((age / 1.6) * Math.PI);
          else delete pulses[m.key];
        }
        return { location: [m.lat, m.lng], size: s };
      });

      arcs = arcs.filter(function (a) { return t - a.born < 3.4; });
      var arcList = arcs.map(function (a) {
        var age = (t - a.born) / 3.4;
        var k = Math.sin(age * Math.PI);            // fade in and out
        var c = a.kind === 'lead' ? WARM : VIOLET;
        return {
          from: [a.from.lat, a.from.lng],
          to: [a.to.lat, a.to.lng],
          color: [c[0] * k, c[1] * k, c[2] * k],
        };
      });

      globe.update({
        phi: phi + lean,
        theta: 0.3 + nod,
        width: size,
        height: size,
        markers: list,
        arcs: arcList,
      });

      if (visible) raf = requestAnimationFrame(frame);
    }

    raf = requestAnimationFrame(frame);
    requestAnimationFrame(function () { canvas.style.opacity = '1'; });

    return {
      pulse: function (fromKey, toKey) {
        var a = byKey[fromKey];
        if (!a) return;
        var t = performance.now() / 1000;
        pulses[fromKey] = t;
        var b = toKey && byKey[toKey];
        if (b && b !== a) arcs.push({ from: a, to: b, born: t, kind: 'lead' });
      },
      link: function (fromKey, toKey) {
        var a = byKey[fromKey], b = byKey[toKey];
        if (a && b && a !== b) arcs.push({ from: a, to: b, born: performance.now() / 1000, kind: 'ambient' });
      },
      hover: function (nx, ny) {
        leanTarget = Math.max(-0.5, Math.min(0.5, nx)) * 0.5;
        nodTarget = Math.max(-0.5, Math.min(0.5, ny)) * 0.32;
      },
      leave: function () { leanTarget = 0; nodTarget = 0; },
      dragStart: function () { dragging = true; spin = 0; },
      drag: function (dx) { phi += dx * 0.0085; },
      dragEnd: function (velocity) {
        dragging = false;
        spin = Math.max(-5, Math.min(5, velocity * 0.0085));
      },
      destroy: function () {
        destroyed = true;
        if (raf) cancelAnimationFrame(raf);
        if (io) io.disconnect();
        if (ro) ro.disconnect();
        try { globe.destroy(); } catch (e) { /* context already lost */ }
        if (canvas.parentNode) canvas.parentNode.removeChild(canvas);
      },
    };
  }

  window.ilGlobe = { mount: mount };
})();
