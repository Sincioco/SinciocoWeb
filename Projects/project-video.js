// The trailer owns its player and hover state; section navigation stays independent.
(() => {
  const video = document.querySelector('.project-video');
  if (!video) return;
  const frame = video.querySelector('.project-video-frame');
  const fallback = frame.querySelector('a');
  const status = video.querySelector('.project-video-status');
  // YouTube requires an HTTP Referer. Local files keep their working external link.
  if (!/^https?:$/.test(location.protocol)) {
    status.textContent = 'Open this page through the website preview for inline playback, or select the image to watch on YouTube.';
    return;
  }
  const iframe = document.createElement('iframe');
  iframe.title = 'Sin Star I trailer';
  iframe.allow = 'autoplay; encrypted-media; fullscreen; picture-in-picture';
  iframe.allowFullscreen = true;
  iframe.referrerPolicy = 'strict-origin-when-cross-origin';
  iframe.src = `https://www.youtube.com/embed/${video.dataset.videoId}?enablejsapi=1&playsinline=1&rel=0&origin=${encodeURIComponent(location.origin)}`;
  fallback.hidden = true;
  frame.append(iframe);
  let player;
  let ready = false;
  let hovering = false;
  let visible = false;
  const play = () => {
    if (!ready || !visible || !hovering) return;
    player.unMute();
    player.playVideo();
  };
  const pause = () => { if (ready) player.pauseVideo(); };
  frame.addEventListener('pointerenter', event => {
    if (event.pointerType !== 'mouse') return;
    hovering = true;
    play();
  });
  frame.addEventListener('pointerleave', event => {
    if (event.pointerType !== 'mouse') return;
    hovering = false;
    pause();
  });
  new IntersectionObserver(entries => {
    visible = entries[0].intersectionRatio > 0.5;
    if (visible) play(); else pause();
  }, { threshold:[0, 0.51] }).observe(frame);
  window.onYouTubeIframeAPIReady = () => {
    player = new YT.Player(iframe, { events:{
      onReady:() => { ready = true; play(); },
      onAutoplayBlocked:() => {
        status.textContent = 'Select Play in the video to start with sound. Your browser blocked automatic playback.';
      },
      onStateChange:event => {
        if (event.data === YT.PlayerState.PLAYING) status.textContent = 'Playing inline. Use the video controls for sound and playback.';
        if (event.data === YT.PlayerState.PAUSED) status.textContent = 'Hover to resume with sound, or use the video controls.';
      },
      onError:() => {
        ready = false;
        iframe.hidden = true;
        fallback.hidden = false;
        status.textContent = 'Inline playback is unavailable. Select the image or trailer link to watch on YouTube.';
      }
    } });
  };
  const api = document.createElement('script');
  api.src = 'https://www.youtube.com/iframe_api';
  api.onerror = () => { status.textContent = 'Select Play in the video, or use the YouTube link below.'; };
  document.head.append(api);
})();
