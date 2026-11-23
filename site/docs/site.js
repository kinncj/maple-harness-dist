/* Maple Harness documentation: colour theme, copy buttons, the screenshot viewer, the phone drawer, "On this page" highlighting and the
   offline search. No other origin is contacted. Text from the index is only ever set with textContent. */
(function () {
  'use strict';
  var root = document.documentElement, KEY = 'maple-theme';

  /* Colour theme: the system's, unless the reader picked light or dark. The button goes
     system -> light -> dark -> system; the page was painted with the right one before this ran. */
  var themeBtn = document.getElementById('theme');
  var mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function pref() { var t = null; try { t = localStorage.getItem(KEY); } catch (e) {} return t === 'light' || t === 'dark' ? t : 'system'; }
  function apply() {
    var p = pref(), t = p === 'system' ? (mq && mq.matches ? 'dark' : 'light') : p;
    root.setAttribute('data-theme', t);
    root.setAttribute('data-theme-pref', p);
    if (p === 'system') root.setAttribute('data-theme-auto', ''); else root.removeAttribute('data-theme-auto');
    if (themeBtn) {
      var name = p === 'system' ? 'same as your system (' + t + ')' : p;
      themeBtn.setAttribute('title', 'Colour theme: ' + name + '. Click to change.');
      themeBtn.setAttribute('aria-label', 'Colour theme: ' + name + '. Activate to change.');
    }
  }
  apply();
  if (mq) { var onSys = function () { if (pref() === 'system') apply(); }; if (mq.addEventListener) mq.addEventListener('change', onSys); else if (mq.addListener) mq.addListener(onSys); }
  if (themeBtn) themeBtn.addEventListener('click', function () {
    var next = {system: 'light', light: 'dark', dark: 'system'}[pref()];
    try { if (next === 'system') localStorage.removeItem(KEY); else localStorage.setItem(KEY, next); } catch (e) {}
    apply();
    toast('Theme: ' + (next === 'system' ? 'same as your system' : next));
  });

  /* A short message at the bottom of the screen, also read out by screen readers. */
  var toastEl = document.getElementById('toast'), toastTimer;
  function toast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove('on'); }, 1600);
  }
  function copyText(text, ok, fail) {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(ok, fail);
    } else {
      var ta = document.createElement('textarea');
      ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      var done = false; try { done = document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(ta);
      (done ? ok : fail)();
    }
  }

  /* Copy buttons on code blocks. */
  [].forEach.call(document.querySelectorAll('.codeblock'), function (cb) {
    var code = cb.querySelector('pre');
    if (!code) return;
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'copy'; b.textContent = 'Copy';
    var lang = cb.querySelector('.lang');
    b.setAttribute('aria-label', 'Copy this ' + (lang ? lang.textContent + ' ' : '') + 'code');
    b.addEventListener('click', function () {
      copyText(code.textContent.replace(/\n$/, ''), function () {
        b.textContent = 'Copied'; b.classList.add('done'); toast('Copied to the clipboard');
        setTimeout(function () { b.textContent = 'Copy'; b.classList.remove('done'); }, 1600);
      }, function () { toast('Select the text and copy it'); });
    });
    cb.appendChild(b);
  });

  /* Heading links: a click copies the address of that section too. */
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a.anchor');
    if (!a) return;
    var url = location.href.split('#')[0] + a.getAttribute('href');
    copyText(url, function () { toast('Link to this section copied'); }, function () {});
  });

  /* Screenshots open larger in a dialog (Esc or the button closes it, focus returns to the picture). */
  var dlg = null, dlgImg, dlgCap, opener = null;
  function lightbox(img, caption) {
    if (!window.HTMLDialogElement) return;
    if (!dlg) {
      dlg = document.createElement('dialog');
      dlg.className = 'lightbox';
      dlg.setAttribute('aria-label', 'Enlarged screenshot');
      var close = document.createElement('button');
      close.type = 'button'; close.textContent = '×'; close.setAttribute('aria-label', 'Close');
      close.addEventListener('click', function () { dlg.close(); });
      dlgImg = document.createElement('img');
      dlgCap = document.createElement('p');
      dlg.appendChild(close); dlg.appendChild(dlgImg); dlg.appendChild(dlgCap);
      dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
      dlg.addEventListener('close', function () { if (opener) opener.focus(); });
      document.body.appendChild(dlg);
    }
    dlgImg.src = img.currentSrc || img.src;
    dlgImg.alt = img.alt;
    dlgCap.textContent = caption || '';
    dlgCap.hidden = !caption;
    dlg.showModal();
  }
  [].forEach.call(document.querySelectorAll('figure'), function (fig) {
    var shots = [].slice.call(fig.querySelectorAll('img.shot'));
    if (!shots.length) return;
    var cap = fig.querySelector('figcaption');
    shots.forEach(function (img) {
      var b = document.createElement('button');
      b.type = 'button'; b.className = 'zoom' + (img.classList.contains('shot-dark') ? ' shot-dark' : img.classList.contains('shot-light') ? ' shot-light' : '');
      b.setAttribute('aria-label', 'Enlarge: ' + (img.alt || 'screenshot'));
      img.parentNode.insertBefore(b, img);
      b.appendChild(img);
      b.addEventListener('click', function () { opener = b; lightbox(img, cap ? cap.textContent.trim() : ''); });
    });
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
  var tocLinks = [].slice.call(document.querySelectorAll('.toc ol a'));
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

  /* The sidebar: on a wide screen, scroll it (not the page) so the current page's link is in view. */
  if (side && window.innerWidth > 860) {
    var curLink = side.querySelector('details [aria-current=page]');
    if (curLink && curLink.offsetParent !== null) {
      var lr = curLink.getBoundingClientRect(), sr = side.getBoundingClientRect();
      if (lr.bottom > sr.bottom - 24 || lr.top < sr.top) side.scrollTop += lr.top - sr.top - sr.height / 3;
    }
  }

  /* Search: a dialog opened by the search button, Ctrl+K or Cmd+K, or "/". The index is a same-origin script
     (docs/search-index.js, written by the build), loaded the first time the dialog opens, so it also works from
     file://. Results are pages first, then sections, each with the section and page it lives in. */
  var finders = [].slice.call(document.querySelectorAll('.find'));
  if (!finders.length) return;
  var base = finders[0].getAttribute('data-docs') || '', state = 'idle', waiting = [], sel = -1;
  var mac = /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent || '');
  if (mac) finders.forEach(function (f) { var k = f.querySelector('.find-k'); if (k) k.textContent = '⌘ K'; });
  function load(cb) {
    if (state === 'ready') return cb();
    waiting.push(cb);
    if (state === 'loading') return;
    state = 'loading';
    var sc = document.createElement('script');
    sc.src = base + 'search-index.js';
    sc.onload = function () { state = 'ready'; prep(); var w = waiting; waiting = []; w.forEach(function (f) { f(); }); };
    sc.onerror = function () { state = 'idle'; waiting = []; if (list) { list.textContent = ''; list.appendChild(none('The search index did not load', 'Try again in a moment, or browse the sidebar.')); } };
    document.head.appendChild(sc);
  }
  var docs = [];
  function prep() {
    docs = (window.MAPLE_SEARCH || []).map(function (d) {
      return {d: d, h: d.h.toLowerCase(), p: d.p.toLowerCase(), x: d.x.toLowerCase(), page: d.u.indexOf('#') < 0};
    });
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  var NS = 'http://www.w3.org/2000/svg';
  function icon(d) {
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '18'); svg.setAttribute('height', '18');
    svg.setAttribute('aria-hidden', 'true'); svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '1.8'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round');
    var path = document.createElementNS(NS, 'path');
    path.setAttribute('d', d);
    svg.appendChild(path);
    return svg;
  }
  var I_PAGE = 'M6.5 3h7.5l4.5 4.5V21h-12zM14 3v4.5h4.5M9 13h6M9 17h4', I_HASH = 'M5 9h14M5 15h14M10 4L8 20M16 4l-2 16',
      I_FIND = 'M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M20 20l-4-4';
  /* Text with the search words marked, built from text nodes only. */
  function marked(tag, cls, text, terms) {
    var e = el(tag, cls), low = text.toLowerCase(), i = 0;
    while (i < text.length) {
      var best = -1, len = 0;
      for (var k = 0; k < terms.length; k++) {
        var at = low.indexOf(terms[k], i);
        if (at >= 0 && (best < 0 || at < best || (at === best && terms[k].length > len))) { best = at; len = terms[k].length; }
      }
      if (best < 0) { e.appendChild(document.createTextNode(text.slice(i))); break; }
      if (best > i) e.appendChild(document.createTextNode(text.slice(i, best)));
      e.appendChild(el('mark', null, text.slice(best, best + len)));
      i = best + len;
    }
    return e;
  }
  function none(title, text) { var li = el('li', 'none'); li.appendChild(el('b', null, title)); li.appendChild(document.createTextNode(text)); return li; }
  /* A word that starts at t's position (not inside another word) counts more than a match mid-word. */
  function wordAt(s, t) {
    var i = s.indexOf(t);
    while (i >= 0) { if (i === 0 || !/[a-z0-9]/.test(s.charAt(i - 1))) return 2; i = s.indexOf(t, i + 1); }
    return s.indexOf(t) >= 0 ? 1 : 0;
  }
  function terms(qv) {
    return qv.toLowerCase().split(/[\s,]+/).filter(function (t) { return t.length > 1; }).map(function (t) {
      return t.length > 3 && /[^s]s$/.test(t) ? t.slice(0, -1) : t; // "budgets" finds "budget" too
    });
  }
  function score(o, ts, phrase, mode) {
    var sc = 0, titleHit = true;
    for (var i = 0; i < ts.length; i++) {
      var t = ts[i], h = wordAt(o.h, t), p = o.page ? 0 : wordAt(o.p, t), x = wordAt(o.x, t); // a page's heading is its title: count it once
      if (!h && !p && !x) return [0, false];
      if (!p && !(o.page && h)) titleHit = false;
      sc += h * 6 + p * 3 + x;
    }
    if (ts.length > 1 && phrase) { if (o.h.indexOf(phrase) >= 0) sc += 12; else if (o.x.indexOf(phrase) >= 0) sc += 4; }
    if (o.page && titleHit) sc += 6;
    if (o.d.m) sc += (o.d.m === 'both' || o.d.m === mode) ? 3 : -2;
    return [sc, titleHit];
  }
  var dlg = null, sq, list, count, opener = null;
  function build() {
    dlg = el('dialog', 'sdlg');
    dlg.setAttribute('aria-label', 'Search the documentation');
    var bar = el('div', 'sdlg-bar');
    bar.appendChild(icon(I_FIND));
    sq = el('input');
    sq.type = 'search'; sq.id = 'sq'; sq.autocomplete = 'off'; sq.spellcheck = false;
    sq.placeholder = 'Search the docs: a setting, a command, a question';
    sq.setAttribute('role', 'combobox'); sq.setAttribute('aria-autocomplete', 'list'); sq.setAttribute('aria-controls', 'sres');
    sq.setAttribute('aria-expanded', 'true'); sq.setAttribute('aria-label', 'Search the documentation');
    bar.appendChild(sq);
    var touch = window.matchMedia && matchMedia('(hover: none)').matches;
    var x = el('button', 'sdlg-x', touch ? 'Close' : 'Esc');
    x.type = 'button'; x.setAttribute('aria-label', 'Close the search');
    x.addEventListener('click', function () { shut(); });
    bar.appendChild(x);
    list = el('ul', 'sdlg-list');
    list.id = 'sres'; list.setAttribute('role', 'listbox'); list.setAttribute('aria-label', 'Search results');
    var foot = el('div', 'sdlg-foot');
    [['↑ ↓', 'move'], ['Enter', 'open'], ['Esc', 'close']].forEach(function (k) {
      var sp = el('span', 'sdlg-keys'); sp.appendChild(el('kbd', null, k[0])); sp.appendChild(document.createTextNode(k[1])); foot.appendChild(sp);
    });
    count = el('span', 'sdlg-n', 'Searches every page and section, offline.');
    count.setAttribute('aria-live', 'polite');
    foot.appendChild(count);
    dlg.appendChild(bar); dlg.appendChild(list); dlg.appendChild(foot);
    document.body.appendChild(dlg);
    sq.addEventListener('input', function () { load(run); });
    sq.addEventListener('keydown', onKey);
    list.addEventListener('click', function (e) { if (e.target.closest('a')) shut(true); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) shut(); });
    dlg.addEventListener('close', function () { if (opener && opener.focus && !dlg.navigating) opener.focus(); dlg.navigating = false; });
  }
  function open(from) {
    if (!dlg) build();
    opener = from || document.activeElement;
    if (dlg.open) { sq.focus(); sq.select(); return; }
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute('open', '');
    sq.focus(); sq.select();
    load(run);
  }
  function shut(navigating) {
    if (!dlg) return;
    dlg.navigating = !!navigating;
    if (dlg.close) dlg.close(); else { dlg.removeAttribute('open'); dlg.dispatchEvent(new Event('close')); }
  }
  function item(d, ts, kind) {
    var li = el('li'), a = el('a');
    li.setAttribute('role', 'presentation');
    a.href = base + d.u;
    a.setAttribute('role', 'option');
    a.setAttribute('aria-selected', 'false');
    a.appendChild(icon(kind === 'page' ? I_PAGE : I_HASH));
    a.appendChild(marked('span', 'r-t', kind === 'page' ? d.p : d.h, ts));
    var w = el('span', 'r-w', kind === 'page' ? (d.s || 'Docs') : (d.s ? d.s + ' › ' : '') + d.p);
    if (d.m && d.m !== 'both' && d.m !== root.getAttribute('data-mode')) w.appendChild(el('span', 'mtag', modeNames[d.m] || d.m));
    a.appendChild(w);
    var x = (d.x || '').replace(/`/g, ''), low = x.toLowerCase(), at = ts.length ? low.indexOf(ts[0]) : -1;
    var start = at > 60 ? x.indexOf(' ', at - 50) + 1 : 0;
    if (x) a.appendChild(marked('span', 'r-x', (start ? '…' : '') + x.slice(start, start + 200), ts));
    li.appendChild(a);
    return li;
  }
  function group(title) { var li = el('li', 'grp-h', title); li.setAttribute('role', 'presentation'); return li; }
  function run() {
    var qv = sq.value.trim(), ts = terms(qv), mode = root.getAttribute('data-mode');
    list.textContent = '';
    sel = -1;
    sq.removeAttribute('aria-activedescendant');
    if (!ts.length) {
      // Nothing typed yet: the first pages of the reading order, as a place to start.
      var starts = docs.filter(function (o) { return o.page && o.d.s === 'Get started' && (!o.d.m || o.d.m === 'both' || o.d.m === mode); }).slice(0, 6);
      if (starts.length) { list.appendChild(group('Start here')); starts.forEach(function (o) { list.appendChild(item(o.d, [], 'page')); }); }
      count.textContent = 'Searches every page and section, offline.';
      ids();
      return;
    }
    var phrase = qv.toLowerCase(), pages = [], secs = [];
    docs.forEach(function (o) {
      var r = score(o, ts, phrase, mode);
      if (!r[0]) return;
      if (o.page && r[1]) pages.push([r[0], o]); else secs.push([r[0], o]);
    });
    var by = function (a, b) { return b[0] - a[0]; };
    pages.sort(by); secs.sort(by);
    var shownPages = pages.slice(0, 6), perPage = {}, shownSecs = [];
    for (var i = 0; i < secs.length && shownSecs.length < 40; i++) {
      var u = secs[i][1].d.u.split('#')[0];
      perPage[u] = (perPage[u] || 0) + 1;
      if (perPage[u] <= 3) shownSecs.push(secs[i]);
    }
    if (shownPages.length) { list.appendChild(group('Pages')); shownPages.forEach(function (h) { list.appendChild(item(h[1].d, ts, 'page')); }); }
    if (shownSecs.length) { list.appendChild(group('Sections')); shownSecs.forEach(function (h) { list.appendChild(item(h[1].d, ts, 'sec')); }); }
    var total = pages.length + secs.length;
    if (!total) {
      list.appendChild(none('Nothing found, sorry. Not even a loonie under the couch.', 'Try fewer or other words (a setting name, a command, a symptom), or open Troubleshooting.'));
      count.textContent = 'No results';
    } else {
      count.textContent = total === 1 ? '1 result' : (shownPages.length + shownSecs.length < total ? 'Top ' + (shownPages.length + shownSecs.length) + ' of ' + total + ' results' : total + ' results');
      move(0);
    }
    ids();
  }
  function ids() { [].forEach.call(list.querySelectorAll('a'), function (a, i) { a.id = 'sr' + i; }); }
  function move(to) {
    var as = list.querySelectorAll('a');
    if (!as.length) return;
    sel = (to + as.length) % as.length;
    [].forEach.call(as, function (a, i) { a.setAttribute('aria-selected', i === sel ? 'true' : 'false'); });
    sq.setAttribute('aria-activedescendant', as[sel].id);
    as[sel].scrollIntoView({block: 'nearest'});
  }
  function onKey(e) {
    var as = list.querySelectorAll('a');
    if (e.key === 'Escape') {
      // A search field clears itself on Esc and keeps the dialog open; here one Esc closes the search.
      e.preventDefault(); shut();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (as.length) move(sel < 0 ? (e.key === 'ArrowDown' ? 0 : -1) : sel + (e.key === 'ArrowDown' ? 1 : -1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (as.length) as[sel >= 0 ? sel : 0].click();
    }
  }
  finders.forEach(function (f) { f.addEventListener('click', function () { open(f); }); });
  document.addEventListener('keydown', function (e) {
    var t = e.target, typing = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    if ((e.key === 'k' || e.key === 'K') && (e.ctrlKey || e.metaKey) && !e.altKey) {
      e.preventDefault();
      if (dlg && dlg.open && document.activeElement === sq) shut(); else open(document.activeElement);
    } else if (e.key === '/' && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault(); open(document.activeElement);
    }
  });
})();
