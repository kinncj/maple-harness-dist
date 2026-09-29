/* The landing page: colour theme, the install switch and its copy button, and the three-part tabs.
   Without this script the page still works: both install commands and all three panels are shown. */
(function () {
  'use strict';
  var root = document.documentElement, KEY = 'maple-theme';

  var themeBtn = document.getElementById('theme');
  function theme() { return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'; }
  function label() {
    var t = theme();
    themeBtn.setAttribute('title', 'Colour theme: ' + t + ' (click to change)');
    themeBtn.setAttribute('aria-label', 'Colour theme: ' + t + '. Activate to change.');
  }
  label();
  themeBtn.addEventListener('click', function () {
    var next = theme() === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem(KEY, next); } catch (e) {}
    root.setAttribute('data-theme', next);
    label();
  });

  /* Install: one command, with a macOS and Linux | Windows switch. Windows is picked when the browser says so. */
  var CMDS = {
    sh: 'curl -fsSL https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.sh | bash',
    ps: 'irm https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.ps1 | iex'
  };
  var pre = document.getElementById('cmd'), box = document.getElementById('cmdbox');
  var osTabs = [].slice.call(document.querySelectorAll('.seg [data-os]'));
  function pick(os, focus) {
    osTabs.forEach(function (b) {
      var on = b.getAttribute('data-os') === os;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      b.tabIndex = on ? 0 : -1;
      if (on) { box.setAttribute('aria-labelledby', b.id); if (focus) b.focus(); }
    });
    pre.textContent = CMDS[os];
  }
  osTabs.forEach(function (b, i) {
    b.addEventListener('click', function () { pick(b.getAttribute('data-os')); });
    b.addEventListener('keydown', function (e) {
      var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (d) { e.preventDefault(); pick(osTabs[(i + d + osTabs.length) % osTabs.length].getAttribute('data-os'), true); }
    });
  });
  var platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
  if (/^win/i.test(platform)) pick('ps');

  var live = document.getElementById('copied'), copy = document.getElementById('copy');
  copy.addEventListener('click', function () {
    var text = pre.textContent.trim();
    function done(ok) {
      copy.textContent = ok ? 'Copied' : 'Press Ctrl+C';
      live.textContent = ok ? 'Copied to the clipboard' : 'Select the command and copy it';
      setTimeout(function () { copy.textContent = 'Copy'; }, 1600);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
    } else {
      var r = document.createRange(); r.selectNodeContents(pre);
      var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
      var ok = false; try { ok = document.execCommand('copy'); } catch (e) {} done(ok);
    }
  });

  /* The three parts. Old links to #terminal, #setup and #remote open their tab. */
  var tabs = [].slice.call(document.querySelectorAll('.tabs [role=tab]'));
  function show(t, focus) {
    tabs.forEach(function (x) {
      var on = x === t;
      x.setAttribute('aria-selected', on ? 'true' : 'false');
      x.tabIndex = on ? 0 : -1;
      document.getElementById(x.getAttribute('aria-controls')).hidden = !on;
    });
    if (focus) t.focus();
  }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { show(t); });
    t.addEventListener('keydown', function (e) {
      var n = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
      if (n !== null) { e.preventDefault(); show(tabs[(n + tabs.length) % tabs.length], true); }
    });
  });
  function fromHash() {
    var id = decodeURIComponent(location.hash.slice(1));
    var t = tabs.filter(function (x) { return x.getAttribute('aria-controls') === id; })[0];
    if (t) { show(t); document.getElementById(id).scrollIntoView(); return; }
    if (id === 'numbers') { document.getElementById('numbers').scrollIntoView(); }
  }
  show(tabs[0]);
  if (location.hash) fromHash();
  window.addEventListener('hashchange', fromHash);
})();
