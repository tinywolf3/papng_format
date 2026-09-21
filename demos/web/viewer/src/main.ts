import './style.css';
import { hueRgb } from '../../../../packages/papng/src/pixels';
import { CONTROL_NAMES, DISTRIBUTION_NAMES } from '../../../../packages/papng/src/types';
import type { Command, Event, Info, Status } from './protocol';

interface Sample {file:string;title:string;subtitle:string;features:string[];frames:number;width:number;height:number}
const icons = {play:'▶',pause:'Ⅱ',next:'→',restart:'↺'};
document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <header class="topbar"><a class="brand" href="./" aria-label="PAPNG Pixel lab"><span class="brand-mark" aria-hidden="true">▦</span><b>PAPNG<span> / Pixel lab</span></b></a><div class="header-right"><span class="version">FORMAT 1.0</span><span class="local-badge"><i></i> 로컬에서만 처리</span><button id="open-file" class="button light">＋ 파일 열기</button><input id="file" type="file" accept=".papng,.png,.apng" hidden /></div></header>
  <main class="workspace">
    <aside class="library"><div class="section-label">EXPLORE <span id="sample-count">06</span></div><h1>작은 픽셀,<br><em>다양한 가능성.</em></h1><p class="intro">샘플을 선택하고 색과 움직임을<br>직접 바꿔 보세요.</p><nav id="samples" aria-label="PAPNG 샘플"></nav><div id="drop-zone" class="drop-zone" tabindex="0" role="button" aria-label="PAPNG 파일 놓기 또는 선택"><span aria-hidden="true">↥</span><b>나의 픽셀아트 열기</b><small>.papng 파일을 이곳에 놓으세요</small></div><p class="privacy">파일은 서버로 업로드되지 않습니다.</p></aside>
    <section class="stage-column" aria-label="픽셀아트 미리보기"><div class="preview-heading"><div><div class="section-label">CANVAS</div><h2 id="title">팔레트 정원</h2><p id="subtitle">파일을 불러오는 중입니다.</p></div><span id="dimensions" class="pill">— × —</span></div>
      <div class="canvas-stage" id="canvas-stage"><div class="stage-corner top-left"></div><div class="stage-corner bottom-right"></div><div id="canvas-wrap"><canvas id="canvas" width="24" height="24" aria-label="복원된 PAPNG 픽셀아트"></canvas><svg id="overlay" aria-hidden="true"></svg></div><div class="stage-label"><span id="file-name">PAPNG RESOURCE</span><span id="zoom-label">10×</span></div><div id="loading" class="loading" hidden>픽셀 복원 중…</div></div>
      <div class="view-options"><label>배율 <select id="zoom" aria-label="픽셀 배율"><option value="auto">자동</option><option value="4">4×</option><option value="8">8×</option><option value="12">12×</option><option value="16">16×</option></select></label><label class="check"><input type="checkbox" id="hints"> 바운딩 박스 · 피벗</label><button id="checker" class="subtle" aria-pressed="true">투명 배경 ▦</button></div>
      <section class="transport" aria-label="재생 제어"><div class="transport-top"><div class="transport-buttons"><button id="restart" class="icon-button" aria-label="처음부터">↺</button><button id="play" class="button accent" disabled>▶ 재생</button><button id="step" class="icon-button" aria-label="다음 방문">→</button></div><span id="play-state" class="play-state">준비 중</span><label class="clip-label">클립 <select id="clip" aria-label="애니메이션 클립"><option value="">전체 애니메이션</option></select></label></div><div class="timeline"><input id="seek" type="range" min="0" max="1" value="0" step="1" aria-label="프레임 이동"><output id="frame-label">000 / 000</output></div><div class="frame-facts"><span>지연 <b id="delay">—</b></span><span>제어 <b id="control">—</b></span><span>완료 <b id="loops">0</b></span></div></section>
      <section class="detail-panel"><div class="section-label">INSIDE THIS FILE</div><div id="features" class="feature-tags"></div><div class="cache-heading"><label for="budget">프레임 캐시 <select id="budget"><option value="0">사용 안 함</option><option value="4">4 MiB</option><option value="16">16 MiB</option><option value="32" selected>32 MiB</option><option value="64">64 MiB</option></select></label><span id="cache-summary">0 B / 32 MiB</span></div><div class="meter"><i id="cache-meter"></i></div><p id="cache-details" class="technical">점프 대상과 자주 찾는 프레임을 우선 보관합니다.</p><details><summary>분포와 프레임 제어 보기</summary><div id="records" class="records"></div></details></section>
    </section>
    <aside class="inspector"><div class="palette-heading"><div><div class="section-label">MASK PALETTE</div><h2>색상 실험실 <span id="mask-count">0</span></h2></div><button id="reset-hues" class="subtle" title="원래 색상각으로 초기화">초기화 ↺</button></div><p class="palette-intro">명암은 그대로, 색상각만 새롭게.<br>H 값을 움직여 팔레트를 바꿔 보세요.</p><div id="palette-note" class="palette-note">색상 변경 시 처음부터 복원합니다.</div><div id="palette"></div><div class="inspector-note"><span>알아두기</span><p>마스크의 채도와 명도는 각 픽셀에 저장됩니다. 팔레트에서는 색상각과 알파를 공유합니다.</p><p>변경한 색은 이 미리보기에만 적용됩니다.</p></div><div id="messages" role="status" aria-live="polite"></div></aside>
  </main><footer><span><i class="status-dot"></i> PAPNG 1.0 · RGBA8</span><span>픽셀아트를 위한 작은 실험실</span><span id="file-size">—</span></footer>`;
const element = <T extends HTMLElement>(id:string) => document.getElementById(id) as T;
const worker = new Worker(new URL('./worker.ts',import.meta.url),{type:'module'});
const send = (command:Command,transfer:Transferable[]=[]) => worker.postMessage(command,transfer);
const canvas = element<HTMLCanvasElement>('canvas'), ctx = canvas.getContext('2d',{alpha:true})!;
let info: Info | undefined, status: Status | undefined, samples: Sample[] = [], loadToken = 0;
let originalHues: number[] = [], lastSample: Sample | undefined, messageCount = 0;
const bytes = (n:number) => n >= 1048576 ? `${(n/1048576).toFixed(1)} MiB` : n >= 1024 ? `${(n/1024).toFixed(1)} KiB` : `${n} B`;
function message(text:string,error=false) { const p=document.createElement('p');p.className=error?'error-message':'warning-message';p.textContent=text;if(messageCount++<30)element('messages').append(p); }
function fit() {
  if (!info) return;
  const stage = element('canvas-stage'), available = Math.min(stage.clientWidth-64,stage.clientHeight-80);
  const requested = Number(element<HTMLSelectElement>('zoom').value);
  let w = info.width, h = info.height;
  if (!requested && info.hints.display) [w,h] = info.hints.display;
  else { const scale = requested || info.hints.scale || 10; w *= scale; h *= scale; }
  const factor = Math.min(1,available/Math.max(w,h)); w *= factor; h *= factor;
  const wrap = element('canvas-wrap'); wrap.style.width=`${Math.max(1,w)}px`; wrap.style.height=`${Math.max(1,h)}px`;
  element('zoom-label').textContent=`${(w/info.width).toFixed(1).replace('.0','')}×`;
  const overlay = element<SVGElement & HTMLElement>('overlay'); overlay.setAttribute('viewBox',`0 0 ${info.width} ${info.height}`); overlay.replaceChildren();
  if (element<HTMLInputElement>('hints').checked) {
    const make=(name:string,attrs:Record<string,string|number>)=>{const e=document.createElementNS('http://www.w3.org/2000/svg',name);Object.entries(attrs).forEach(([k,v])=>e.setAttribute(k,String(v)));overlay.append(e);};
    if (info.hints.bbox) { const [x,y,w,h]=info.hints.bbox;make('rect',{x,y,width:w,height:h,fill:'none',stroke:'#c7f56b','stroke-width':.15}); }
    if (info.hints.pivot) { const [x,y]=info.hints.pivot;make('path',{d:`M ${x-1},${y} h 2 M ${x},${y-1} v 2`,stroke:'#ffae80','stroke-width':.2}); }
  }
}
function renderPalette() {
  const root=element('palette');root.replaceChildren();if(!info)return;
  element('mask-count').textContent=String(info.masks.length).padStart(2,'0');
  if (!info.masks.length) { const p=document.createElement('p');p.className='empty';p.textContent='이 파일은 일반 RGBA 픽셀을 사용합니다. 마스크 팔레트가 없습니다.';root.append(p);return; }
  info.masks.forEach((mask,index)=>{
    const card=document.createElement('div');card.className='mask-card';
    card.innerHTML=`<div class="mask-top"><span class="swatch"></span><div><b class="mask-name"></b><small class="mask-group"></small></div><span class="mask-index">${String(index).padStart(2,'0')}</span></div><div class="hue-caption"><span>HUE</span><output></output></div><input class="hue-range" type="range" min="0" max="65535" step="1" aria-label="마스크 ${index} 색상각"><div class="mask-values"><label>H16 <input class="hue-number" type="number" min="0" max="65535" step="1" aria-label="마스크 ${index} H16"></label><span>A <b>${mask.alpha}</b></span><button class="mask-reset subtle" aria-label="마스크 ${index} 색상 초기화">↺</button></div>`;
    card.querySelector('.mask-name')!.textContent=`마스크 ${String(index).padStart(2,'0')}`;
    card.querySelector('.mask-group')!.textContent=info!.groups.filter(g=>g.indices.includes(index)).map(g=>g.name).join(' · ')||'공유 팔레트';
    const range=card.querySelector<HTMLInputElement>('.hue-range')!,number=card.querySelector<HTMLInputElement>('.hue-number')!;
    const update=(hue:number)=>{range.value=number.value=String(hue);card.querySelector('output')!.textContent=`${(hue*360/65536).toFixed(1)}°`;(card.querySelector('.swatch') as HTMLElement).style.backgroundColor=`rgba(${hueRgb(hue).join(',')},${mask.alpha/255})`;};
    const change=(hue:number)=>{if(!Number.isInteger(hue)||hue<0||hue>65535||status?.playing||!info)return;mask.hue=hue;update(hue);send({type:'hue',index,hue,hues:info.masks.map(m=>m.hue)});};
    range.oninput=()=>change(Number(range.value));number.onchange=()=>{if(number.value!==''&&number.checkValidity())change(Number(number.value));else update(mask.hue);};
    card.querySelector<HTMLButtonElement>('.mask-reset')!.onclick=()=>change(originalHues[index]);
    update(mask.hue);root.append(card);
  });
}
function renderInfo(next:Info) {
  info=next;status=undefined;originalHues=next.masks.map(m=>m.hue);
  element('file-name').textContent=next.name;element('dimensions').textContent=`${next.width} × ${next.height}`;
  element('file-size').textContent=`${bytes(next.bytes)} · ${next.frames} frames`;
  element('title').textContent=lastSample?.title??next.name;element('subtitle').textContent=lastSample?.subtitle??'나의 PAPNG 리소스';
  const clips=element<HTMLSelectElement>('clip');clips.replaceChildren(new Option('전체 애니메이션',''));
  next.clips.forEach(clip=>clips.add(new Option(clip.name,clip.id)));
  element<HTMLInputElement>('seek').max=String(next.frames-1);
  const features=element('features');features.replaceChildren();
  for(const name of lastSample?.features??[`${next.masks.length} masks`,`${next.distributions.length} distributions`,`${next.controls.length} controls`]){const tag=document.createElement('span');tag.textContent=name;features.append(tag);}
  const records=element('records');records.replaceChildren();
  next.distributions.forEach((d,i)=>{const p=document.createElement('p');p.textContent=`분포 ${i} · ${DISTRIBUTION_NAMES[d.kind]??'RESERVED'}${d.valid?'':' · 오류'}`;records.append(p);});
  next.controls.forEach(c=>{const p=document.createElement('p');p.textContent=`프레임 ${c.frame} → ${CONTROL_NAMES[c.type]??'RESERVED'}`;records.append(p);});
  renderPalette();fit();element<HTMLButtonElement>('play').disabled=false;
}
function renderStatus(next:Status) {
  status=next;
  element('play').textContent=next.playing?`${icons.pause} 일시정지`:`${icons.play} 재생`;
  element('play-state').textContent=next.ended?'재생 완료':next.playing?'재생 중':next.hidden?'숨김 프레임에서 대기':'일시정지';
  element('play-state').classList.toggle('is-playing',next.playing);
  const seek=element<HTMLInputElement>('seek');seek.min=String(next.start);seek.max=String(next.end);seek.value=String(next.frame);
  element('frame-label').textContent=`${String(next.frame).padStart(3,'0')} / ${String(next.end).padStart(3,'0')}`;
  element('delay').textContent=next.hidden?'0 · 합성만':`${(next.num*1000/next.den).toFixed(1).replace('.0','')} ms`;
  element('control').textContent=next.recovery?'10 ms 복구':next.control===null?'순차 진행':CONTROL_NAMES[next.control];
  element('loops').textContent=String(next.completed);
  element('cache-summary').textContent=`${bytes(next.cache.bytes)} / ${bytes(next.cache.budget)}`;
  element('cache-meter').style.width=`${next.cache.budget?next.cache.bytes/next.cache.budget*100:0}%`;
  element('cache-details').textContent=`${next.cache.entries}개 보관 · 적중 ${next.cache.hits} · 해제 ${next.cache.evictions} · 현재 합성 ${bytes(next.activeBytes)} · 복원 ${next.reconstructions}회`;
  element('palette-note').textContent=next.playing?'일시정지하면 색상각을 변경할 수 있습니다.':'색상 변경 시 처음부터 복원합니다.';
  document.querySelectorAll<HTMLInputElement|HTMLButtonElement>('#palette input, #palette button, #reset-hues').forEach(e=>e.disabled=next.playing);
}
worker.onmessage=(event:MessageEvent<Event>)=>{
  const m=event.data;
  if(m.type==='info')renderInfo(m.info);
  if(m.type==='status')renderStatus(m.status);
  if(m.type==='image'){canvas.width=m.width;canvas.height=m.height;ctx.putImageData(new ImageData(new Uint8ClampedArray(m.pixels),m.width,m.height),0,0);canvas.dataset.frame=String(m.frame);fit();}
  if(m.type==='warning')message(m.message);
  if(m.type==='error'){message(m.message,true);element('subtitle').textContent='처리할 수 없는 파일입니다. 다른 샘플이나 파일을 열어 주세요.';element('loading').hidden=true;}
  if(m.type==='busy')element('loading').hidden=!m.busy;
};
worker.onerror=()=>message('재생 작업을 시작할 수 없습니다. 이 브라우저의 Web Worker 지원을 확인하세요.',true);
async function load(buffer:ArrayBuffer,name:string,sample?:Sample) {
  lastSample=sample;messageCount=0;element('messages').replaceChildren();element('loading').hidden=false;
  element<HTMLButtonElement>('play').disabled=true;send({type:'load',buffer,name},[buffer]);
  document.querySelectorAll<HTMLButtonElement>('.sample-card').forEach(e=>e.classList.toggle('selected',e.dataset.file===sample?.file));
}
async function loadSample(sample:Sample){const token=++loadToken;try{const response=await fetch(`${import.meta.env.BASE_URL}samples/${sample.file}`);if(!response.ok)throw new Error('샘플 파일을 찾을 수 없습니다');const buffer=await response.arrayBuffer();if(token===loadToken)await load(buffer,sample.file,sample);}catch(error){message(String(error),true);}}
async function loadFile(file:File){const token=++loadToken;if(file.size>128*1024*1024){message('파일이 뷰어의 입력 예산 128 MiB를 넘었습니다.',true);return;}const buffer=await file.arrayBuffer();if(token===loadToken)await load(buffer,file.name);}
element<HTMLButtonElement>('open-file').onclick=()=>element<HTMLInputElement>('file').click();
element<HTMLInputElement>('file').onchange=event=>{const input=event.target as HTMLInputElement;if(input.files?.[0])void loadFile(input.files[0]);input.value='';};
element('drop-zone').onclick=()=>element<HTMLInputElement>('file').click();
element('drop-zone').onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();element<HTMLInputElement>('file').click();}};
window.addEventListener('dragover',e=>{e.preventDefault();element('drop-zone').classList.add('dragging');});
window.addEventListener('drop',e=>{e.preventDefault();element('drop-zone').classList.remove('dragging');if(e.dataTransfer?.files[0])void loadFile(e.dataTransfer.files[0]);});
window.addEventListener('dragleave',()=>element('drop-zone').classList.remove('dragging'));
element('play').onclick=()=>send({type:status?.playing?'pause':'play'});
element('restart').onclick=()=>send({type:'restart'});element('step').onclick=()=>send({type:'step'});
element<HTMLInputElement>('seek').onchange=e=>send({type:'seek',frame:Number((e.target as HTMLInputElement).value)});
element<HTMLSelectElement>('clip').onchange=e=>send({type:'clip',id:(e.target as HTMLSelectElement).value});
element<HTMLSelectElement>('budget').onchange=e=>send({type:'budget',bytes:Number((e.target as HTMLSelectElement).value)*1048576});
element('reset-hues').onclick=()=>{if(info){info.masks.forEach((m,i)=>m.hue=originalHues[i]);renderPalette();send({type:'reset-hues'});}};
element('zoom').onchange=fit;element('hints').onchange=fit;new ResizeObserver(fit).observe(element('canvas-stage'));
element('checker').onclick=()=>{const stage=element('canvas-stage'),off=stage.classList.toggle('solid');element('checker').setAttribute('aria-pressed',String(!off));};
async function init(){try{const response=await fetch(`${import.meta.env.BASE_URL}samples/manifest.json`);if(!response.ok)throw new Error('샘플 목록을 불러올 수 없습니다');samples=await response.json();element('sample-count').textContent=String(samples.length).padStart(2,'0');samples.forEach((sample,index)=>{const button=document.createElement('button');button.className='sample-card';button.dataset.file=sample.file;button.innerHTML=`<span class="sample-symbol symbol-${index}">${['✿','▥','◌','♧','◇','▰'][index]??'▦'}</span><span class="sample-copy"><b></b><small></small></span><span class="sample-arrow">↗</span>`;button.querySelector('b')!.textContent=sample.title;button.querySelector('small')!.textContent=`${sample.width} × ${sample.height} · ${sample.frames} frames`;button.onclick=()=>void loadSample(sample);element('samples').append(button);});if(samples[0])await loadSample(samples[0]);}catch(error){message(`${String(error)}. 파일 열기는 계속 사용할 수 있습니다.`,true);element('loading').hidden=true;}}
void init();
