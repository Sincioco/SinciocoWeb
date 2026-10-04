// Progressive enhancement only: every project and section link works without JS.
(() => {
  const menu = document.querySelector('.section-menu');
  if (!menu) return;
  const compact = window.matchMedia('(max-width:760px)');
  const updateMenu = () => { menu.open = !compact.matches; };
  updateMenu();
  compact.addEventListener('change', updateMenu);
  const links = [...menu.querySelectorAll('a[href^="#"]')];
  const sections = links.map(link => document.getElementById(decodeURIComponent(link.hash.slice(1))));
  let current = '';
  const markCurrent = id => {
    if (id === current) return;
    current = id;
    links.forEach(link => {
      if (link.hash === '#' + id) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    });
  };
  const header = document.querySelector('.site-header');
  const updateOffset = () => {
    document.documentElement.style.scrollPaddingTop = `${header.getBoundingClientRect().height + 20}px`;
  };
  new ResizeObserver(updateOffset).observe(header);
  let scheduled = false;
  const updateSection = () => {
    scheduled = false;
    const cutoff = header.getBoundingClientRect().height + 45;
    let active = sections[0];
    for (const section of sections) {
      if (section && section.getBoundingClientRect().top <= cutoff) active = section;
    }
    if (active) markCurrent(active.id);
  };
  window.addEventListener('scroll', () => {
    if (!scheduled) { scheduled = true; requestAnimationFrame(updateSection); }
  }, { passive:true });
  links.forEach(link => link.addEventListener('click', () => {
    if (compact.matches) menu.open = false;
    // Open a collapsed source detail when a section is linked directly.
    const target = document.getElementById(decodeURIComponent(link.hash.slice(1)));
    for (let parent = target?.parentElement; parent; parent = parent.parentElement) {
      if (parent instanceof HTMLDetailsElement) parent.open = true;
    }
    markCurrent(target?.id);
  }));
  updateOffset();
  updateSection();
})();
