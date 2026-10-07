/* Public clip browser: verified YouTube IDs only, with a single active player. */
(() => {
  const choices=[...document.querySelectorAll('[data-youtube]')];
  const host=document.getElementById('clip-screen');
  const title=document.getElementById('clip-title');
  const direct=document.getElementById('clip-direct');
  const search=document.getElementById('clip-search');
  const count=document.getElementById('clip-count');
  function choose(button,autoplay){
    const id=button.dataset.youtube;
    if(!/^[A-Za-z0-9_-]{11}$/.test(id))return;
    const frame=document.createElement('iframe');
    frame.src='https://www.youtube-nocookie.com/embed/'+id+'?playsinline=1&rel=0'+(autoplay?'&autoplay=1':'');
    frame.title=button.dataset.title;
    frame.allow='autoplay; encrypted-media; picture-in-picture; fullscreen';
    frame.allowFullscreen=true;
    frame.referrerPolicy='strict-origin-when-cross-origin';
    host.replaceChildren(frame);
    title.textContent=button.dataset.title;
    direct.href='https://youtu.be/'+id;direct.hidden=false;
    choices.forEach(item=>item.setAttribute('aria-current',String(item===button)));
    try{history.replaceState(null,'','#'+encodeURIComponent(button.id));}catch{}
  }
  choices.forEach(button=>button.addEventListener('click',()=>choose(button,true)));
  search.addEventListener('input',()=>{
    const query=search.value.toLocaleLowerCase().trim();let visible=0;
    document.querySelectorAll('.clip-list li').forEach(row=>{
      row.hidden=!row.textContent.toLocaleLowerCase().includes(query);
      if(!row.hidden)visible++;
    });
    count.textContent=visible+' clips shown';
  });
  const selected=choices.find(button=>button.id===decodeURIComponent(location.hash.slice(1)));
  if(selected)choose(selected,false);
})();
