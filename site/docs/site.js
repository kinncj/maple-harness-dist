/* Maple Harness documentation: colour theme, the phone drawer, "On this page" highlighting and the
   offline search. No other origin is contacted. Text from the index is only ever set with textContent. */
(function () {
  'use strict';
  var root = document.documentElement, KEY = 'maple-theme';

  /* Colour theme (the page is painted with the stored choice before this runs). */
  var themeBtn = document.getElementById('theme');
  function theme() { return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'; }
  function label() {
    if (!themeBtn) return;
    var t = theme();
    themeBtn.setAttribute('title', 'Colour theme: ' + t + ' (click to change)');
    themeBtn.setAttribute('aria-label', 'Colour theme: ' + t + '. Activate to change.');
  }
  label();
  if (themeBtn) themeBtn.addEventListener('click', function () {
    var next = theme() === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem(KEY, next); } catch (e) {}
    root.setAttribute('data-theme', next);
    label();
  });

  /* The release notice: dismissing it stores its version, so the inline script hides it before the first
     paint from then on, until a newer release is announced. Without storage it is hidden on this page only. */
  var relx = document.getElementById('relx');
  if (relx) relx.addEventListener('click', function () {
    try { localStorage.setItem('maple-release-dismissed', root.getAttribute('data-release') || ''); } catch (e) {}
    root.classList.add('rel-off');
    var home = document.querySelector('.top .brand');
    if (home) home.focus();
  });

  /* The documentation mode (Single user, Teams & hubs). Each tab is a link to that mode's first page, so
     it works without scripts; the page was painted in the right mode already (see the inline script).
     Here: mark the current tab, remember a choice, and move between tabs with the arrow keys. */
  var modeList = document.querySelector('.modes'), modeTabs = [], modeNames = {};
  if (modeList) {
    modeTabs = [].slice.call(modeList.querySelectorAll('[role=tab]'));
    var curMode = root.getAttribute('data-mode');
    modeTabs.forEach(function (t) {
      var m = t.getAttribute('data-m'), on = m === curMode;
      modeNames[m] = t.textContent;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.tabIndex = on ? 0 : -1;
      t.addEventListener('click', function () { try { localStorage.setItem('maple-docs-mode', m); } catch (e) {} });
    });
    modeList.addEventListener('keydown', function (e) {
      var i = modeTabs.indexOf(document.activeElement), j = -1;
      if (i < 0) return;
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') j = (i + 1) % modeTabs.length;
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') j = (i - 1 + modeTabs.length) % modeTabs.length;
      else if (e.key === 'Home') j = 0;
      else if (e.key === 'End') j = modeTabs.length - 1;
      else if (e.key === ' ') { e.preventDefault(); modeTabs[i].click(); return; }
      if (j >= 0) { e.preventDefault(); modeTabs[j].focus(); }
    });
  }

  /* The sidebar is a drawer on phones. */
  var menu = document.getElementById('menu'), scrim = document.getElementById('scrim'), side = document.getElementById('side');
  function drawer(open) {
    document.body.classList.toggle('nav-open', open);
    if (menu) menu.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open && side) {
      var cur = side.querySelector('[aria-current=page]') || side.querySelector('a');
      if (cur) { cur.scrollIntoView({block: 'center'}); cur.focus({preventScroll: true}); }
    } else if (!open && menu && side && side.contains(document.activeElement)) {
      menu.focus();
    }
  }
  if (menu) menu.addEventListener('click', function () { drawer(!document.body.classList.contains('nav-open')); });
  if (scrim) scrim.addEventListener('click', function () { drawer(false); });
  if (side) side.addEventListener('click', function (e) { if (e.target.closest('a')) drawer(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && document.body.classList.contains('nav-open')) drawer(false);
  });
  window.addEventListener('resize', function () {
    if (window.innerWidth > 860 && document.body.classList.contains('nav-open')) drawer(false);
  });

  /* "On this page": highlight the section being read. Without IntersectionObserver the list is static. */
  var tocLinks = [].slice.call(document.querySelectorAll('.toc a'));
  if (tocLinks.length && 'IntersectionObserver' in window) {
    var byId = {}, visible = {};
    tocLinks.forEach(function (a) { byId[decodeURIComponent(a.getAttribute('href').slice(1))] = a; });
    var heads = Object.keys(byId).map(function (id) { return document.getElementById(id); }).filter(Boolean);
    var mark = function (id) { tocLinks.forEach(function (a) { a.classList.toggle('on', a === byId[id]); }); };
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { visible[e.target.id] = e.isIntersecting; });
      for (var i = 0; i < heads.length; i++) { if (visible[heads[i].id]) { mark(heads[i].id); return; } }
      // Nothing in the band: the reader is inside a long section; keep the last heading above.
      var above = null;
      for (var j = 0; j < heads.length; j++) { if (heads[j].getBoundingClientRect().top < 90) above = heads[j]; }
      if (above) mark(above.id);
    }, {rootMargin: '-70px 0px -65% 0px'});
    heads.forEach(function (h) { io.observe(h); });
  }

  /* Search: the index is a same-origin script, loaded the first time the box is used. */
  var box = document.querySelector('.search'), q = document.getElementById('q'), list = document.getElementById('results');
  if (!box || !q || !list) return;
  var base = box.getAttribute('data-docs') || '', state = 'idle', waiting = [], sel = -1;
  function load(cb) {
    if (state === 'ready') return cb();
    waiting.push(cb);
    if (state === 'loading') return;
    state = 'loading';
    var s = document.createElement('script');
    s.src = base + 'search-index.js';
    s.onload = function () { state = 'ready'; var w = waiting; waiting = []; w.forEach(function (f) { f(); }); };
    s.onerror = function () { state = 'idle'; waiting = []; };
    document.head.appendChild(s);
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function close() { list.hidden = true; q.setAttribute('aria-expanded', 'false'); q.removeAttribute('aria-activedescendant'); sel = -1; }
  function run() {
    var terms = q.value.toLowerCase().split(/\s+/).filter(function (t) { return t.length > 1; });
    list.textContent = '';
    sel = -1;
    if (!terms.length) { close(); return; }
    var hits = [];
    (window.MAPLE_SEARCH || []).forEach(function (d) {
      var h = d.h.toLowerCase(), p = d.p.toLowerCase(), x = d.x.toLowerCase(), score = 0;
      for (var i = 0; i < terms.length; i++) {
        var t = terms[i], w = 0;
        if (h.indexOf(t) >= 0) w += 10;
        if (p.indexOf(t) >= 0) w += 4;
        if (x.indexOf(t) >= 0) w += 1;
        if (!w) return;
        score += w;
      }
      if (d.h === d.p) score += 1;
      if (d.m && (d.m === 'both' || d.m === root.getAttribute('data-mode'))) score += 2;
      hits.push([score, d]);
    });
    hits.sort(function (a, b) { return b[0] - a[0]; });
    hits.slice(0, 8).forEach(function (hit, n) {
      var d = hit[1], li = el('li'), a = el('a');
      a.href = base + d.u;
      a.id = 'r' + n;
      a.setAttribute('role', 'option');
      a.appendChild(el('span', 'where', d.h));
      if (d.h !== d.p || d.m) {
        var pg = el('span', 'page', d.h !== d.p ? d.p : '');
        if (d.m) pg.appendChild(el('span', 'mtag', d.m === 'both' ? 'Both modes' : (modeNames[d.m] || d.m)));
        a.appendChild(pg);
      }
      var x = d.x, at = x.toLowerCase().indexOf(terms[0]), start = at > 50 ? x.indexOf(' ', at - 40) + 1 : 0;
      if (x) a.appendChild(el('span', 'snip', (start ? '…' : '') + x.slice(start, start + 170)));
      li.appendChild(a);
      list.appendChild(li);
    });
    if (!hits.length) list.appendChild(el('li', 'none', 'No results. Try other words, or open Troubleshooting.'));
    list.hidden = false;
    q.setAttribute('aria-expanded', 'true');
  }
  q.addEventListener('focus', function () { load(function () {}); });
  q.addEventListener('input', function () { load(run); });
  q.addEventListener('keydown', function (e) {
    var as = list.querySelectorAll('a');
    if (e.key === 'Escape') { if (!list.hidden) { close(); e.stopPropagation(); } else { q.blur(); } return; }
    if (!as.length || list.hidden) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + as.length) % as.length;
      [].forEach.call(as, function (a, i) { a.setAttribute('aria-selected', i === sel ? 'true' : 'false'); });
      q.setAttribute('aria-activedescendant', as[sel].id);
      as[sel].scrollIntoView({block: 'nearest'});
    } else if (e.key === 'Enter') {
      e.preventDefault();
      (as[sel >= 0 ? sel : 0]).click();
    }
  });
  document.addEventListener('keydown', function (e) {
    var t = e.target, typing = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    if (e.key === '/' && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) { e.preventDefault(); q.focus(); }
  });
  document.addEventListener('click', function (e) { if (!e.target.closest('.search')) close(); });
})();
