/* Progressive enhancements. Lesson text and navigation work without JavaScript. */
(() => {
  'use strict';
  const menu = document.querySelector('.menu-toggle');
  const sidebar = document.querySelector('.docs-sidebar');
  document.body.classList.add('js-ready');
  const narrow = window.matchMedia('(max-width: 700px)');
  const syncMenu = () => { menu.hidden = !narrow.matches; };
  syncMenu();
  narrow.addEventListener('change', syncMenu);
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    sidebar.classList.toggle('is-open', open);
  });

  const escapeHtml = value => value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const keywords = new Set(('Option Explicit Import As Module Public Private Const Dim Number Double Text Boolean Type Class Enum End New Nothing Me Property Get Set Value Sub Function Return Call ByRef ByVal Optional If Then Else ElseIf Select Case For To Down Step Do Loop Until Continue Exit True False And Or Not Is Mod Print Game Window Size By Clear Fill Draw Rectangle Circle At Color Centered Get Key Show Screen Wait Milliseconds Program Load Save From Default Play Sound Music Stop').toLowerCase().split(' '));
  document.querySelectorAll('pre > code').forEach(code => {
    const source = code.textContent;
    if (code.classList.contains('language-smile')) {
      const pattern = /'[^\n]*|"(?:""|[^"\n])*"|\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z_0-9]*\b/g;
      let result = '', cursor = 0;
      for (const match of source.matchAll(pattern)) {
        result += escapeHtml(source.slice(cursor, match.index));
        const token = match[0];
        const kind = token[0] === "'" ? 'comment' : token[0] === '"' ? 'string' : /^\d/.test(token) ? 'number' : keywords.has(token.toLowerCase()) ? 'keyword' : '';
        result += kind ? `<span class="token-${kind}">${escapeHtml(token)}</span>` : escapeHtml(token);
        cursor = match.index + token.length;
      }
      code.innerHTML = result + escapeHtml(source.slice(cursor));
    }
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy-button';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy code sample');
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = 'Copied';
      } catch {
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = 'Selected · Ctrl+C';
      }
      window.setTimeout(() => { button.textContent = 'Copy'; }, 2500);
    });
    code.parentElement.append(button);
  });

  const search = document.getElementById('doc-search');
  const results = document.getElementById('search-results');
  const searchStatus = document.getElementById('search-status');
  document.querySelector('.search-box').hidden = false;
  let searchTimer;
  search.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = window.setTimeout(() => {
      const query = search.value.trim().toLowerCase();
      results.replaceChildren();
      results.hidden = query.length < 2;
      if (results.hidden) { searchStatus.textContent = ''; return; }
      const words = query.split(/\s+/);
      const found = (window.SMILE_SEARCH || []).map(item => {
        const title = item.title.toLowerCase();
        const haystack = `${title} ${item.text}`.toLowerCase();
        const score = words.every(word => haystack.includes(word)) ? (title.includes(query) ? 10 : 1) + (item.section ? 2 : 0) : 0;
        return {item, score};
      }).filter(entry => entry.score).sort((a, b) => b.score - a.score).slice(0, 12);
      for (const {item} of found) {
        const link = document.createElement('a');
        link.href = item.href;
        link.textContent = item.title;
        if (item.section) {
          const context = document.createElement('small');
          context.textContent = item.section;
          link.append(context);
        }
        results.append(link);
      }
      if (!found.length) {
        const message = document.createElement('p');
        message.textContent = 'No matches. Try “loop”, “sound”, “arena”, or a function name.';
        results.append(message);
      }
      searchStatus.textContent = `${found.length}${found.length === 12 ? ' or more' : ''} results.`;
    }, 120);
  });
  search.addEventListener('keydown', event => {
    if (event.key === 'Escape') { results.hidden = true; search.blur(); }
    if (event.key === 'ArrowDown') { results.querySelector('a')?.focus(); event.preventDefault(); }
  });

  document.querySelectorAll('[data-api-filter]').forEach(filter => {
    const entries = [...document.querySelectorAll('[data-api]')];
    filter.addEventListener('input', () => {
      const query = filter.value.trim().toLowerCase();
      let count = 0;
      entries.forEach(entry => {
        entry.hidden = !entry.textContent.toLowerCase().includes(query);
        if (!entry.hidden) count++;
      });
      document.querySelectorAll('.api-group').forEach(group => { group.hidden = !group.querySelector('[data-api]:not([hidden])'); });
      const status = document.querySelector('[data-api-count]');
      if (status) status.textContent = count ? `${count} ${count === 1 ? 'function' : 'functions'} shown` : 'No functions found. Try a different name or clear the filter.';
    });
  });

  document.querySelectorAll('.doc-content table').forEach(table => {
    if (table.parentElement.classList.contains('table-wrap')) return;
    const wrap = document.createElement('div');
    wrap.className = 'table-wrap';
    wrap.tabIndex = 0;
    wrap.setAttribute('role', 'region');
    wrap.setAttribute('aria-label', 'Reference table. Scroll horizontally if needed.');
    table.before(wrap);
    wrap.append(table);
  });

  const x = document.getElementById('lab-x');
  const y = document.getElementById('lab-y');
  if (x && y) {
    const draw = () => {
      document.getElementById('lab-rect').setAttribute('x', x.value);
      document.getElementById('lab-rect').setAttribute('y', y.value);
      document.getElementById('lab-x-value').value = x.value;
      document.getElementById('lab-y-value').value = y.value;
      document.getElementById('lab-code-x').textContent = x.value;
      document.getElementById('lab-code-y').textContent = y.value;
    };
    x.addEventListener('input', draw);
    y.addEventListener('input', draw);
    draw();
  }

  if ('IntersectionObserver' in window) {
    const tocLinks = [...document.querySelectorAll('.page-toc a')];
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        tocLinks.forEach(link => link.classList.toggle('active', link.hash === `#${entry.target.id}`));
      }
    }, {rootMargin:'-100px 0px -65% 0px'});
    document.querySelectorAll('.doc-content h2[id]').forEach(heading => observer.observe(heading));
  }
})();
