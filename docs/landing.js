(function(){
/* Line icons: <span data-i="name" data-s="size" data-w="stroke"> is filled with the matching SVG. */
const P={dashboard:'M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z',check:'M5 12l5 5L20 6',todos:'M9 5h9M9 12h9M9 19h9M4 5l1 1 2-2M4 12l1 1 2-2M4 19l1 1 2-2',university:'M3 9l9-5 9 5-9 5zM7 11v5c0 1 2.2 2.5 5 2.5s5-1.5 5-2.5v-5M21 9v5',office:'M4 8h16v12H4zM9 8V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v3M4 13h16',products:'M4 4h4v16H4zM10 4h4v10h-4zM16 4h4v13h-4z',workout:'M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10',plus:'M12 5v14M5 12h14',calendar:'M4 6h16v15H4zM4 10h16M8 3v4M16 3v4',clock:'M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z',flag:'M5 21V4M5 4h12l-2 4 2 4H5',chevRight:'M9 6l6 6-6 6',chevLeft:'M15 6l-6 6 6 6',search:'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM21 21l-4-4',fire:'M12 22c4 0 7-2.7 7-7 0-3-2-5-3-7-.5 1.5-1.5 2-2.5 2 0-2 .5-4-1.5-6-.3 3-2 4-3.5 6S5 12 5 15c0 4.3 3 7 7 7z',target:'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM12 12h.01',trophy:'M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v2a3 3 0 0 0 3 3M17 6h3v2a3 3 0 0 1-3 3M9 19h6M10 15v4M14 15v4',book:'M5 4h14v16H7a2 2 0 0 1-2-2zM5 16h14',bell:'M18 9a6 6 0 0 0-12 0c0 6-2 7-2 7h16s-2-1-2-7M10 21h4',settings:'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19 12a7 7 0 0 0-.1-1l2-1.6-2-3.4-2.4 1a7 7 0 0 0-1.7-1L14.5 2h-4l-.3 2.5a7 7 0 0 0-1.7 1l-2.4-1-2 3.4L4.1 11a7 7 0 0 0 0 2l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 1.7 1l.3 2.5h4l.3-2.5a7 7 0 0 0 1.7-1l2.4 1 2-3.4-2-1.6a7 7 0 0 0 .1-1z',tag:'M3 12V4h8l9 9-8 8zM7.5 7.5h.01',note:'M5 4h11l3 3v13H5zM9 9h6M9 13h6M9 17h3',sun:'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 2v2M12 20v2M4 12H2M22 12h-2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19',moon:'M20.5 14.2A8.2 8.2 0 0 1 9.8 3.5 7 7 0 1 0 20.5 14.2z',activity:'M3 12h4l3 8 4-16 3 8h4',sparkle:'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z',folder:'M4 6h6l2 2h8v11H4z',sidebar:'M4 5h16v14H4zM9.5 5v14',bold:'M7 5h6a3.5 3.5 0 0 1 0 7H7zM7 12h7a3.5 3.5 0 0 1 0 7H7z',italic:'M10 5h8M6 19h8M14 5l-4 14',code:'M9 8l-4 4 4 4M15 8l4 4-4 4',sigma:'M17 5H7l6 7-6 7h10',list:'M10 6h10M10 12h10M10 18h10M5 6h.01M5 12h.01M5 18h.01',quote:'M5 11h4v6H5zM5 11c0-3 1-5 4-6M14 11h4v6h-4zM14 11c0-3 1-5 4-6',codeblock:'M4 5h16v14H4zM10 10l-2 2 2 2M14 10l2 2-2 2',heading:'M6 5v14M18 5v14M6 12h12',pin:'M9 4h6l-1 6 3 3H7l3-3zM12 13v7',copy:'M8 8h11v12H8zM5 16V4h11',inbox:'M4 13h4l2 3h4l2-3h4M4 13l2-8h12l2 8v6H4z',lock:'M6 11h12v10H6zM8 11V8a4 4 0 0 1 8 0v3',wifi:'M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01',eye:'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',bolt:'M13 2L4 14h7l-1 8 9-12h-7z',download:'M12 4v11M7 10l5 5 5-5M5 20h14',keyboard:'M3 6h18v12H3zM7 10h.01M11 10h.01M15 10h.01M7 14h10',windows:'M3 5h12v10H3zM9 9h12v10H9z',bookpages:'M12 6c-2-1.5-4.5-2-8-2v15c3.5 0 6 .5 8 2 2-1.5 4.5-2 8-2V4c-3.5 0-6 .5-8 2zM12 6v15'};
/* Extra icons for the 2.0 page. Paths are split on "M", so each subpath starts with M. */
Object.assign(P,{palette:'M12 3a9 9 0 1 0 0 18c1.1 0 1.6-.8 1.6-1.6 0-.5-.2-.8-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.7-1.6 1.6-1.6H16a5 5 0 0 0 5-5c0-4-4-7.4-9-7.4zM7.5 11.5h.01M10 7.5h.01M14.5 7.5h.01',image:'M4 5h16v14H4zM4 16l5-5 4 4 2-2 5 5M15.5 9.5h.01',cloud:'M7 18a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 9.5a4.3 4.3 0 0 1-.5 8.5z',link:'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1'});
const ico=(n,s=18,w=1.7)=>`<svg class="ico" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${(P[n]||'').split('M').filter(Boolean).map(d=>`<path d="M${d}"/>`).join('')}</svg>`;
const paint=root=>root.querySelectorAll('[data-i]').forEach(el=>{el.innerHTML=ico(el.dataset.i,+el.dataset.s||18,+el.dataset.w||1.7)});

/* Storage can throw (private windows, blocked site data); the page works without it. */
const load=(k,d)=>{try{return localStorage.getItem(k)||d}catch(_){return d}};
const save=(k,v)=>{try{localStorage.setItem(k,v)}catch(_){}};
const root=document.documentElement;

/* Space themes: the same three mesh colours the app uses (SpaceTheme.swift). */
const TH=[['dawn','Dawn','Peach, periwinkle and a little pink. The default.',['#ffd3b0','#c9d5ff','#f7c6e0']],
 ['dusk','Dusk','Lavender and rose, like the sky just after sunset.',['#d9c6ff','#f4c6ea','#bccaff']],
 ['ember','Ember','Warm apricot and honey for long evenings.',['#ffc996','#ffe3a8','#ffae93']],
 ['lagoon','Lagoon','Cool blues and aqua, calm and clear.',['#b9dcff','#c2eff2','#d0caff']],
 ['meadow','Meadow','Fresh greens with a touch of lime.',['#c6ecca','#e6f3b9','#b6e6db']],
 ['orchid','Orchid','Pink, lilac and coral, softly blended.',['#f8c3e1','#e2cdfc','#ffd2c9']],
 ['paper','Paper','Quiet, warm neutrals. Almost no colour at all.',['#ebe4d6','#f4efe5','#e2dbcf']],
 ['ink','Ink','Deep indigo, plum and teal. The dark theme.',['#3b3f8f','#5b2f7a','#1f4f7a']]];
let theme=load('msl-theme','dawn');if(!TH.some(t=>t[0]===theme))theme='dawn';
const grad=c=>`radial-gradient(60% 80% at 8% 10%,${c[0]} 0%,transparent 70%),radial-gradient(60% 90% at 92% 0%,${c[1]} 0%,transparent 70%),radial-gradient(55% 70% at 55% 60%,${c[2]} 0%,transparent 72%)`;
function renderTheme(){
 const t=TH.find(x=>x[0]===theme),dark=theme==='ink',stage=document.getElementById('thStage');
 /* Ink is too dark for the page's own bands, so the page keeps Dawn's there and only the preview goes dark. */
 const page=dark?TH[0][3]:t[3];
 ['--m1','--m2','--m3'].forEach((k,i)=>root.style.setProperty(k,page[i]));
 if(!stage)return;
 stage.classList.toggle('dark',dark);
 stage.querySelector('.band').style.background=grad(t[3]);
 document.getElementById('thName').textContent=t[1];
 document.getElementById('thDesc').textContent=t[2];
 document.getElementById('thPick').innerHTML=TH.map(([id,n,,c])=>`<button class="th${id===theme?' on':''}" data-th="${id}" aria-pressed="${id===theme}"><i style="background:${grad(c)},${c[1]}"></i>${n}</button>`).join('');
}

/* Accent: MySelf follows the Mac's accent colour; the swatches show it on this page. */
const ACC=[['Blue','#007aff'],['Purple','#a550a7'],['Pink','#f74f9e'],['Red','#ff5257'],['Orange','#f7821b'],['Yellow','#ffc600'],['Green','#62ba46'],['Graphite','#8c8c8c']];
let accent=load('msl-accent','#007aff');
if(!ACC.some(a=>a[1]===accent))accent='#007aff';
function renderAccent(){
 root.style.setProperty('--accent',accent);
 const el=document.getElementById('swatches');if(!el)return;
 el.innerHTML=ACC.map(([n,c])=>`<button class="sw${c===accent?' on':''}" data-acc="${c}" title="${n}" aria-label="${n}" style="background:${c}"></button>`).join('')+`<span class="mut" style="margin-left:4px">${ACC.find(a=>a[1]===accent)[0]}</span>`;
}

/* Quick Open demo: the same groups the app shows, each in its space's colour. */
const C={dashboard:'#5856d6',todos:'#1f9a5a',university:'#7a4fe0',office:'#2f6fec',book:'#e06a00',products:'#1f8a4f',note:'#11808e',bookpages:'#8f5a26',settings:'#8a8a90',flag:'#7a4fe0'};
const QO=[['Pages','dashboard','Dashboard','⌘1'],['Pages','todos','TODOs','⌘2'],['Pages','university','University','⌘3'],['Pages','office','Office Tasks','⌘4'],['Pages','book','Job Study','⌘5'],['Pages','products','Product Dev','⌘6'],['Pages','note','Notes','⌘8'],['Pages','bookpages','Book Notes','⌘9'],
 ['Items','office','Sign off Q2 OKR document','Office'],['Items','todos','Call dentist for cleaning appointment','Today'],['Items','flag','DSA: Implement an AVL tree','Assignment'],['Items','book','System Design · Rate limiter design','Job Study'],['Items','products','Drag-and-drop field reordering','FormFlow'],['Items','note','Eigenvalues & Eigenvectors','University'],['Items','note','Binary search template','Algorithms'],['Items','bookpages','Sapiens','Yuval Noah Harari'],
 ['Actions','todos','New Todo','⌘N'],['Actions','office','New Office Task','⇧⌘N'],['Actions','note','New Note','⌥⌘N'],['Actions','settings','Settings','⌘,']];
let qi=0,qr=[];
const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;');
function renderQO(){
 const inp=document.getElementById('qoIn'),list=document.getElementById('qoList');if(!inp)return;
 const q=inp.value.trim().toLowerCase();qr=QO.filter(r=>!q||r[2].toLowerCase().includes(q)||r[3].toLowerCase().includes(q));
 if(qi>=qr.length)qi=Math.max(0,qr.length-1);
 if(!qr.length){list.innerHTML=`<div class="qo-empty">No results for “${esc(inp.value)}”</div>`;return}
 let g='',h='';qr.forEach((r,i)=>{if(r[0]!==g){g=r[0];h+=`<div class="qo-g">${g}</div>`}h+=`<div class="qo-r${i===qi?' on':''}" data-qi="${i}"><span class="ic" style="background:${C[r[1]]}">${ico(r[1],13,2)}</span><span class="tt">${esc(r[2])}</span><span class="sb">${r[3]}</span></div>`});
 list.innerHTML=h;const on=list.querySelector('.qo-r.on');if(on){const t=on.offsetTop-list.offsetTop,b=t+on.offsetHeight;if(t<list.scrollTop)list.scrollTop=t-30;else if(b>list.scrollTop+list.clientHeight)list.scrollTop=b-list.clientHeight+6}
}

/* Light / Dark picker */
function setTheme(d){document.querySelectorAll('[data-theme-btn]').forEach(b=>b.classList.toggle('on',(b.dataset.themeBtn==='dark')===d))}

/* Widgets demo: the tick and + work as they do on the desktop. */
function widgetClick(b){
 if(b.dataset.wgMode){document.getElementById('widgets').classList.toggle('dark',b.dataset.wgMode==='dark');document.querySelectorAll('[data-wg-mode]').forEach(x=>x.classList.toggle('on',x===b))}
 else if('wgPlus' in b.dataset){const c=b.previousElementSibling;c.textContent=(parseInt(c.textContent)+1)+'×';c.style.color='var(--w-orange)'}
 else{b.classList.toggle('on');b.parentElement.classList.toggle('done');const w=b.closest('[data-wg-focus]');w.querySelector('[data-wg-left]').textContent=(5-w.querySelectorAll('.wg-ck.on').length)+' left'}
}

/* Screenshots open full size. */
function zoom(img){
 const d=document.getElementById('zoom');if(!d||!d.showModal)return;
 const z=d.querySelector('img');z.src=img.currentSrc||img.src;z.alt=img.alt;d.showModal();
}

document.addEventListener('click',e=>{
 const w=e.target.closest('[data-wg-mode],[data-wg-plus],.wg-ck');if(w){widgetClick(w);return}
 const shot=e.target.closest('.shot img');if(shot){zoom(shot);return}
 if(e.target.closest('#zoom')){document.getElementById('zoom').close();return}
 const b=e.target.closest('[data-acc],[data-theme-btn],[data-qi],[data-th]');if(!b)return;
 if(b.dataset.acc){accent=b.dataset.acc;save('msl-accent',accent);renderAccent()}
 else if(b.dataset.th){theme=b.dataset.th;save('msl-theme',theme);renderTheme()}
 else if(b.dataset.themeBtn)setTheme(b.dataset.themeBtn==='dark');
 else if(b.dataset.qi){qi=+b.dataset.qi;renderQO()}
});
document.addEventListener('mouseover',e=>{const r=e.target.closest('[data-qi]');if(r&&+r.dataset.qi!==qi){qi=+r.dataset.qi;renderQO()}});
document.addEventListener('DOMContentLoaded',()=>{
 paint(document);renderAccent();renderTheme();renderQO();
 const inp=document.getElementById('qoIn');
 inp.addEventListener('input',()=>{qi=0;renderQO()});
 inp.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){qi=Math.min(qi+1,qr.length-1);renderQO();e.preventDefault()}if(e.key==='ArrowUp'){qi=Math.max(qi-1,0);renderQO();e.preventDefault()}});
});
})();
