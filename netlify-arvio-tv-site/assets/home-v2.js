// Server-rendered translations keep first paint and interactive labels in the same language.
const homeCopy = JSON.parse(document.getElementById('home-copy').textContent);
const t = text => homeCopy[text] || text;
// Transparent over the hero; a soft fade keeps navigation readable after scrolling.
const siteNav = document.querySelector('.nav');
let navFrame;
function updateNavigation() { siteNav.classList.toggle('is-scrolled', window.scrollY > 24); }
window.addEventListener('scroll', () => {
  if (navFrame) return;
  navFrame = requestAnimationFrame(() => { updateNavigation(); navFrame = null; });
}, {passive:true});
updateNavigation();
/* Product showcase: real screenshots and local, user-controlled motion. */
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const finePointer = window.matchMedia('(hover:hover) and (pointer:fine)');
let paused = reduceMotion.matches;
let heroRequest = 0, heroVisible = true;
const motionButton = document.querySelector('#motion');
const display = document.querySelector('#display');
const stage = document.querySelector('#stage');
const hero = document.querySelector('#hero-screen');
const sceneAnimations = new Set();
function updateMotion() {
  document.body.classList.toggle('paused', paused);
  document.documentElement.classList.toggle('motion-allowed', !paused);
  motionButton.setAttribute('aria-pressed', String(paused));
  motionButton.textContent = paused ? t('Enable motion ↗') : t('Pause motion Ⅱ');
  if (paused) {
    sceneAnimations.forEach(animation=>animation.cancel()); sceneAnimations.clear();
    document.querySelectorAll('.screen-outgoing').forEach(el=>el.remove());
    stage.style.setProperty('--phone-y','0px'); stage.style.setProperty('--chip-y','0px');
  }
}
updateMotion();
motionButton.addEventListener('click', () => { paused = !paused; updateMotion(); });
reduceMotion.addEventListener('change', event => { paused = event.matches; updateMotion(); });
if ('IntersectionObserver' in window) {
  document.documentElement.classList.add('js');
  const observer = new IntersectionObserver(entries => entries.forEach(entry => {
    if (entry.isIntersecting) { entry.target.classList.add('seen'); observer.unobserve(entry.target); }
  }), {threshold:0.08});
  document.querySelectorAll('.reveal').forEach(element=>observer.observe(element));
  const heroObserver = new IntersectionObserver(entries=>entries.forEach(entry=>{
    heroVisible=entry.isIntersecting;
    document.body.classList.toggle('hero-offscreen',!heroVisible || document.hidden);
  }),{threshold:0});
  heroObserver.observe(document.querySelector('.hero'));
}
document.addEventListener('visibilitychange',()=>{
  document.body.classList.toggle('hero-offscreen',document.hidden || !heroVisible);
});
let pointerFrame;
stage.addEventListener('pointermove', event => {
  if (paused || !finePointer.matches) return;
  cancelAnimationFrame(pointerFrame);
  pointerFrame = requestAnimationFrame(() => {
    const rect = stage.getBoundingClientRect();
    const x = (event.clientX-rect.left)/rect.width-.5;
    const y = (event.clientY-rect.top)/rect.height-.5;
    display.style.setProperty('--ry',`${x*3}deg`); display.style.setProperty('--rx',`${-y*2}deg`);
    stage.style.setProperty('--phone-y',`${-y*12}px`);stage.style.setProperty('--chip-y',`${y*7}px`);
  });
});
stage.addEventListener('pointerleave', () => {
  cancelAnimationFrame(pointerFrame); display.style.setProperty('--rx','0deg');display.style.setProperty('--ry','0deg');
  stage.style.setProperty('--phone-y','0px');stage.style.setProperty('--chip-y','0px');
});
const screenData = {
  home:{src:'/assets/screenshots-v2/tv/01-home.webp',alt:'ARVIO 2.0 home screen on Android TV',caption:'A home for everything you love.',index:'01'},
  library:{src:'/assets/screenshots-v2/tv/03-library.webp',alt:'ARVIO 2.0 library on Android TV',caption:'Your watchlists. Your libraries. All together.',index:'02'},
  live:{src:'/assets/screenshots-v2/tv/05-tv.webp',alt:'ARVIO 2.0 live TV guide on Android TV',caption:'Your channels, with a view of what’s next.',index:'03'},
  sports:{src:'/assets/screenshots-v2/tv/06-sports.webp',alt:'ARVIO 2.0 sports page on Android TV',caption:'Stay close to the action.',index:'04'}
};
async function swapImage(element, src, alt, isCurrent) {
  const next = new Image(); next.src = src;
  try { await next.decode(); } catch { return false; }
  if (!isCurrent()) return false;
  element.src = src; element.alt = t(alt);
  if (!paused) element.animate([{opacity:.35},{opacity:1}],{duration:320,easing:'ease-out'});
  return true;
}
async function showScene(key) {
  const request = ++heroRequest, scene = screenData[key];
  const next = new Image(); next.src = scene.src;
  try { await next.decode(); } catch { document.querySelector('#screen-status').textContent=t('This preview could not load. Please try another screen.');return false; }
  if(request!==heroRequest)return false;
  sceneAnimations.forEach(animation=>animation.cancel());sceneAnimations.clear();
  document.querySelectorAll('.screen-outgoing').forEach(el=>el.remove());
  const changed = hero.getAttribute('src')!==scene.src;
  if(changed && !paused){
    const outgoing=hero.cloneNode(); outgoing.removeAttribute('id');outgoing.alt='';outgoing.setAttribute('aria-hidden','true');outgoing.className='screen-outgoing';
    hero.parentNode.append(outgoing);
    const fade=outgoing.animate([{opacity:1,transform:'translateX(0)'},{opacity:0,transform:'translateX(-14px)'}],{duration:650,easing:'cubic-bezier(.2,.75,.2,1)'});
    const enter=hero.animate([{opacity:.25,transform:'scale(1.025)'},{opacity:1,transform:'scale(1)'}],{duration:750,easing:'cubic-bezier(.2,.75,.2,1)'});
    sceneAnimations.add(fade);sceneAnimations.add(enter);
    fade.onfinish=()=>{outgoing.remove();sceneAnimations.delete(fade);};enter.onfinish=()=>sceneAnimations.delete(enter);
  }
  hero.src=scene.src;hero.alt=t(scene.alt);
  document.querySelectorAll('[data-screen]').forEach(b=>{const selected=b.dataset.screen===key;b.classList.toggle('selected',selected);b.setAttribute('aria-pressed',String(selected));});
  document.querySelector('#scene-name').textContent=t(scene.caption);
  document.querySelector('#scene-count').textContent=`${scene.index} / 04`;
  document.querySelector('#screen-status').textContent=t(scene.alt);
  return true;
}
document.querySelectorAll('[data-screen]').forEach(button=>button.addEventListener('click',()=>showScene(button.dataset.screen)));
const features = {
  library:{title:'Everything you saved.\nRight where it belongs.',copy:'Watchlists, personal lists and home servers. Browse your collections in one place, with layouts that feel at home on TV.',src:'/assets/screenshots-v2/tv/03-library.webp',alt:'ARVIO TV library with watchlists, personal lists and home servers',number:'01'},
  live:{title:'Your channels.\nA guide that feels right.',copy:'Bring your M3U or Xtream playlist. Explore channels, see what’s on next and keep your favorites close, all with your remote.',src:'/assets/screenshots-v2/tv/05-tv.webp',alt:'ARVIO live TV guide with channel listings and programme information',number:'02'},
  sports:{title:'Stay close\nto the action.',copy:'Browse sports and upcoming highlights in a dedicated view. Connect your own supported live TV sources to watch.',src:'/assets/screenshots-v2/tv/06-sports.webp',alt:'ARVIO sports page with featured channels and upcoming highlights',number:'03'}
};
const featureTabs = [...document.querySelectorAll('[data-feature]')];
let featureRequest = 0;
async function setFeature(button) {
  const request = ++featureRequest;
  const value = features[button.dataset.feature];
  if (!(await swapImage(document.querySelector('#feature-screen'),value.src,value.alt,()=>request===featureRequest))) return;
  featureTabs.forEach(b=>{b.setAttribute('aria-selected',String(b===button));b.tabIndex=b===button?0:-1;});
  document.querySelector('#feature-title').textContent=t(value.title);
  document.querySelector('#feature-title').style.whiteSpace='pre-line';
  document.querySelector('#feature-copy').textContent=t(value.copy);
  document.querySelector('.feature-number').textContent=value.number;
  document.querySelector('#feature-panel').setAttribute('aria-labelledby',button.id);
}
featureTabs.forEach((button,index)=>{
  button.addEventListener('click',()=>setFeature(button));
  button.addEventListener('keydown',event=>{
    let next;
    if(event.key==='ArrowRight') next=(index+1)%featureTabs.length;
    if(event.key==='ArrowLeft') next=(index-1+featureTabs.length)%featureTabs.length;
    if(event.key==='Home') next=0;
    if(event.key==='End') next=featureTabs.length-1;
    if(next!==undefined){event.preventDefault();featureTabs[next].focus();setFeature(featureTabs[next]);}
  });
});

function openLinkedGallery() {
  if (location.hash !== '#screens') return;
  const gallery = document.getElementById('screens');
  gallery.open = true;
  const firstGroup = gallery.querySelector('.capture-group');
  if(firstGroup) firstGroup.open = true;
  requestAnimationFrame(()=>gallery.scrollIntoView({block:'start',behavior:'instant'}));
}
window.addEventListener('hashchange',openLinkedGallery);
openLinkedGallery();
