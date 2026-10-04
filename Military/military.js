(() => {
  const dialog = document.querySelector('.photo-dialog');
  const gallery = document.querySelector('.service-gallery');
  if (!dialog || !gallery || typeof dialog.showModal !== 'function') return;

  const image = dialog.querySelector('.photo-full');
  const caption = dialog.querySelector('#photo-caption');
  const closeButton = dialog.querySelector('.photo-close');
  let openingLink = null;

  gallery.addEventListener('click', (event) => {
    const link = event.target.closest('.gallery-link');
    if (!link || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    openingLink = link;
    image.src = link.href;
    image.alt = link.querySelector('img').alt;
    caption.textContent = link.querySelector('span').textContent;
    dialog.showModal();
    document.body.classList.add('photo-is-open');
    closeButton.focus();
  });

  closeButton.addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close();
  });
  // Native dialog handles Escape and keeps keyboard focus inside the open photo.
  dialog.addEventListener('close', () => {
    document.body.classList.remove('photo-is-open');
    openingLink?.focus({ preventScroll: true });
    openingLink = null;
  });
})();
