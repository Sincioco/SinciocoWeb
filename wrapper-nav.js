/* Preserve bookmarked fragments when opening the fixed hosted page. */
(() => {
  'use strict';
  const targets = Object.freeze({
    book: 'https://sincioco.github.io/SinStar_Audio_BookOne/',
    storyboard: 'https://sincioco.github.io/SinStar_Storyboard/'
  });
  const page = document.documentElement.getAttribute('data-hosted-page');
  if (!Object.prototype.hasOwnProperty.call(targets, page)) return;
  const frame = document.getElementById('hosted-content');
  const openLink = document.getElementById('open-hosted-content');
  if (!frame || !openLink) return;
  function preserveFragment() {
    const destination = new URL(targets[page]);
    destination.hash = window.location.hash;
    const href = destination.href;
    if (frame.getAttribute('src') !== href) frame.setAttribute('src', href);
    if (openLink.getAttribute('href') !== href) openLink.setAttribute('href', href);
  }
  preserveFragment();
  window.addEventListener('hashchange', preserveFragment);
})();
