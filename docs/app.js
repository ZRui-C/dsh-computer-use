/* DSH Computer Use product site interactions */
(function () {
  'use strict';

  var repository = 'https://github.com/ZRui-C/dsh-computer-use';

  document.querySelectorAll('[data-repo-link]').forEach(function (link) {
    link.href = repository;
  });
  document.querySelectorAll('[data-release-link]').forEach(function (link) {
    link.href = repository + '/releases';
  });
  document.querySelectorAll('[data-repo-path]').forEach(function (link) {
    link.href = repository + '/blob/main/' + link.getAttribute('data-repo-path');
  });

  document.querySelectorAll('.copy').forEach(function (button) {
    button.addEventListener('click', function () {
      var code = button.closest('.code-block').querySelector('pre');
      if (!code) return;
      copyText(code.innerText.replace(/\n$/, ''), function () {
        button.textContent = '已复制';
        button.classList.add('copied');
        window.setTimeout(function () {
          button.textContent = '复制';
          button.classList.remove('copied');
        }, 1500);
      });
    });
  });

  function copyText(text, done) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () {
        fallbackCopy(text, done);
      });
      return;
    }
    fallbackCopy(text, done);
  }

  function fallbackCopy(text, done) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
    } catch (error) {
      return;
    } finally {
      document.body.removeChild(textarea);
    }
    done();
  }

  var nav = document.getElementById('nav');
  var toggle = document.getElementById('navToggle');
  var links = document.getElementById('navLinks');

  function closeMenu() {
    if (!toggle || !links) return;
    links.classList.remove('open');
    toggle.classList.remove('open');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.setAttribute('aria-label', '打开菜单');
  }

  if (toggle && links) {
    toggle.addEventListener('click', function () {
      var open = links.classList.toggle('open');
      toggle.classList.toggle('open', open);
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      toggle.setAttribute('aria-label', open ? '关闭菜单' : '打开菜单');
    });
    links.addEventListener('click', function (event) {
      if (event.target.tagName === 'A') closeMenu();
    });
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') closeMenu();
    });
  }

  function updateNav() {
    if (nav) nav.classList.toggle('scrolled', window.scrollY > 8);
  }
  window.addEventListener('scroll', updateNav, { passive: true });
  updateNav();

  var sections = Array.prototype.slice.call(document.querySelectorAll('main section[id]'));
  var navAnchors = Array.prototype.slice.call(document.querySelectorAll('.nav-links a[href^="#"]'));
  if ('IntersectionObserver' in window && navAnchors.length) {
    var sectionObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navAnchors.forEach(function (anchor) {
          anchor.classList.toggle('active', anchor.getAttribute('href') === '#' + entry.target.id);
        });
      });
    }, { rootMargin: '-25% 0px -65% 0px' });
    sections.forEach(function (section) {
      sectionObserver.observe(section);
    });
  }
})();
