import './style.css';
import { socketsAt } from '../../../../packages/papng/src/sockets';
import { AttachmentPreview, type Attachment } from './attachment';
import { shiftHue } from '../../../../packages/papng/src/pixels';
import { displayHue, hueOffset, maskLabel } from './mask-colors';
import { CONTROL_NAMES, DISTRIBUTION_NAMES } from '../../../../packages/papng/src/types';
import type { Command, Event, Info, Status } from './protocol';

interface Sample {file:string;title:string;subtitle:string;features:string[];frames:number;width:number;height:number;attachment?:Attachment}
const icons = {play:'▶',pause:'Ⅱ',next:'→',restart:'↺'};
document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <header class="topbar"><a class="brand" href="./" aria-label="PAPNG Pixel lab"><span class="brand-mark" aria-hidden="true">▦</span><b>PAPNG<span> / Pixel lab</span></b></a><div class="header-right"><span class="version">FORMAT 1.0</span><span class="local-badge"><i></i> 로컬에서만 처리</span><button id="open-file" class="button light">＋ 파일 열기</button><input id="file" type="file" accept=".papng,.png,.apng" hidden /></div></header>
  <main class="workspace">
    <aside class="library"><div class="section-label">EXPLORE <span id="sample-count">07</span></div><h1>작은 픽셀,<br><em>다양한 가능성.</em></h1><p class="intro">샘플을 선택하고 색과 움직임을<br>직접 바꿔 보세요.</p><nav id="samples" aria-label="PAPNG 샘플"></nav><div id="drop-zone" class="drop-zone" tabindex="0" role="button" aria-label="PAPNG 파일 놓기 또는 선택"><span aria-hidden="true">↥</span><b>나의 픽셀아트 열기</b><small>.papng 파일을 이곳에 놓으세요</small></div><p class="privacy">파일은 서버로 업로드되지 않습니다.</p></aside>
    <section class="stage-column" aria-label="픽셀아트 미리보기"><div class="preview-heading"><div><div class="section-label">CANVAS</div><h2 id="title">팔레트 정원</h2><p id="subtitle">파일을 불러오는 중입니다.</p></div><span id="dimensions" class="pill">— × —</span></div>
      <div class="canvas-stage" id="canvas-stage"><div class="stage-corner top-left"></div><div class="stage-corner bottom-right"></div><div id="canvas-wrap"><canvas id="canvas" width="24" height="24" aria-label="복원된 PAPNG 픽셀아트"></canvas><svg id="overlay" aria-hidden="true"></svg></div><div class="stage-label"><span id="file-name">PAPNG RESOURCE</span><span id="zoom-label">10×</span></div><div id="loading" class="loading" hidden>픽셀 복원 중…</div></div>
      <div class="view-options"><label>배율 <select id="zoom" aria-label="픽셀 배율"><option value="auto">자동</option><option value="4">4×</option><option value="8">8×</option><option value="12">12×</option><option value="16">16×</option></select></label><label class="check"><input type="checkbox" id="hints"> 바운딩 박스 · 피벗</label><button id="checker" class="subtle" aria-pressed="true">투명 배경 ▦</button></div>
      <section id="socket-panel" class="socket-panel" hidden aria-label="소켓 연결 예제"><div class="section-label">SOCKETS · ATTACHMENTS</div><h3>소켓에 부속 연결</h3><div class="socket-options"><label>연결 지점 <select id="socket-select" aria-label="연결할 소켓"></select></label><label class="check"><input id="show-sockets" type="checkbox" checked> 소켓 표시</label><label class="check"><input id="show-attachment" type="checkbox" checked> 부속 표시</label></div><p id="socket-pose" class="socket-pose"></p><p id="attachment-state" class="technical"></p><p class="technical">소켓의 방향으로 회전하고 부속의 pivot을 맞춥니다. 부속은 자체 속도로 재생됩니다.</p></section>
      <section class="transport" aria-label="재생 제어"><div class="transport-top"><div class="transport-buttons"><button id="restart" class="icon-button" aria-label="처음부터">↺</button><button id="play" class="button accent" disabled>▶ 재생</button><button id="step" class="icon-button" aria-label="다음 방문">→</button></div><span id="play-state" class="play-state">준비 중</span><label class="clip-label">클립 <select id="clip" aria-label="애니메이션 클립"><option value="">전체 애니메이션</option></select></label></div><div class="timeline"><input id="seek" type="range" min="0" max="1" value="0" step="1" aria-label="프레임 이동"><output id="frame-label">000 / 000</output></div><div class="frame-facts"><span>지연 <b id="delay">—</b></span><span>제어 <b id="control">—</b></span><span>완료 <b id="loops">0</b></span></div></section>
      <section class="detail-panel"><div class="section-label">INSIDE THIS FILE</div><div id="features" class="feature-tags"></div><div class="cache-heading"><label for="budget">프레임 캐시 <select id="budget"><option value="0">사용 안 함</option><option value="4">4 MiB</option><option value="16">16 MiB</option><option value="32" selected>32 MiB</option><option value="64">64 MiB</option></select></label><span id="cache-summary">0 B / 32 MiB</span></div><div class="meter"><i id="cache-meter"></i></div><p id="cache-details" class="technical">점프 대상과 자주 찾는 프레임을 우선 보관합니다.</p><details><summary>분포와 프레임 제어 보기</summary><div id="records" class="records"></div></details></section>
    </section>
    <aside class="inspector"><div class="palette-heading"><div><div class="section-label">MASK PALETTE</div><h2>색상 실험실 <span id="mask-count">0</span></h2></div><button id="reset-hues" class="subtle" title="색상각 변화량을 0으로 초기화">초기화 ↺</button></div><p class="palette-intro">원본 평균색의 H에서 시작합니다.<br>H 또는 ΔH를 움직여 색을 시험하세요.</p><div id="palette-note" class="palette-note">색상 변경 시 처음부터 복원합니다.</div><p id="mask-sharing" class="technical"></p><div id="mask-pages" class="mask-pages" hidden><button id="mask-prev" class="icon-button" aria-label="이전 마스크 페이지">‹</button><span id="mask-page-label"></span><button id="mask-next" class="icon-button" aria-label="다음 마스크 페이지">›</button><label>번호 <input id="mask-goto" type="number" min="0" step="1" value="0" aria-label="마스크 번호로 이동"></label></div><div id="palette"></div><div class="inspector-note"><span>알아두기</span><p>원본 RGBA와 마스크 소속을 따로 저장합니다. 같은 마스크 안에서도 픽셀마다 색상과 알파가 다를 수 있습니다. ΔH가 0이면 원본색입니다.</p><p>기준색은 전체 원본 프레임의 RGB를 알파로 가중 평균한 색입니다. 완전 투명 픽셀은 제외하며, 재생 시간과 방문 횟수는 반영하지 않습니다.</p><p>H는 기준색을 회전하는 조절값입니다. 각 픽셀은 원래의 색상각 차이를 유지합니다. 변경한 색은 이 미리보기에만 적용됩니다.</p></div><div id="messages" role="status" aria-live="polite"></div></aside>
  </main><footer><span><i class="status-dot"></i> PAPNG 1.0 · RGBA8</span><span>픽셀아트를 위한 작은 실험실</span><span id="file-size">—</span></footer>`;
const element = <T extends HTMLElement>(id:string) => document.getElementById(id) as T;
const worker = new Worker(new URL('./worker.ts',import.meta.url),{type:'module'});
function send(command:Command,transfer:Transferable[]=[]) {
  if(command.type==='play') {
    if(status?.ended)attachment.restart();
    const startedAt=performance.timeOrigin+performance.now();
    attachment.play(startedAt);command={...command,startedAt};
  } else if(command.type!=='load' && command.type!=='budget') {
    attachment.pause();
    if(command.type!=='pause')attachment.restart();
  }
  worker.postMessage(command,transfer);
}
const canvas = element<HTMLCanvasElement>('canvas'), ctx = canvas.getContext('2d',{alpha:true})!;
let info: Info | undefined, status: Status | undefined, samples: Sample[] = [], loadToken = 0;
let resourceLoading = false;
let offsets: number[] = [], maskPage = 0, lastSample: Sample | undefined, messageCount = 0;
let baseImage: ImageData | undefined;
const attachment = new AttachmentPreview(()=>{drawScene();updatePlayAvailability();},text=>message(text,true));
function updatePlayAvailability(){element<HTMLButtonElement>('play').disabled=resourceLoading || attachment.loading || !info;}
function pose(){return socketsAt(info?.sockets,Number(canvas.dataset.frame??-1));}
function drawScene() {
  if(!info || !baseImage)return;
  ctx.putImageData(baseImage,0,0);
  const record=pose(),index=Number(element<HTMLSelectElement>('socket-select').value),position=record?.positions[index];
  if(position && element<HTMLInputElement>('show-attachment').checked)attachment.draw(ctx,position);
  const readout=element('socket-pose');
  readout.textContent=position?`x ${position[0]} · y ${position[1]} · r ${position[2]}° · 정의 프레임 ${record!.frame}`:'출력 프레임 없음';
  readout.dataset.source=String(record?.frame??-1);
  const state=element('attachment-state');state.dataset.frame=String(attachment.frame);
  state.textContent=attachment.loading?'부속 파일 준비 중…':attachment.info?`${attachment.info.name} · 부속 프레임 ${attachment.frame} / ${attachment.info.frames-1} · pivot (${(attachment.info.hints.pivot??[0,0]).join(', ')})`:lastSample?.attachment?'부속을 불러오지 못했습니다. 소켓 정보는 계속 확인할 수 있습니다.':'이 파일의 소켓 정보입니다. 자동으로 연결되는 부속은 없습니다.';
  fit();
}
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
  if(element<HTMLInputElement>('show-sockets').checked) {
    pose()?.positions.forEach(([x,y,r],index)=>{
      const group=document.createElementNS('http://www.w3.org/2000/svg','g');
      group.dataset.socket=String(index);group.setAttribute('transform',`translate(${x} ${y}) rotate(${r%360})`);
      const color=String(index)===element<HTMLSelectElement>('socket-select').value?'#ffae80':'#b3caff';
      const circle=document.createElementNS('http://www.w3.org/2000/svg','circle');
      circle.setAttribute('r','0.7');circle.setAttribute('fill','none');circle.setAttribute('stroke',color);circle.setAttribute('stroke-width','.25');
      const arrow=document.createElementNS('http://www.w3.org/2000/svg','path');
      arrow.setAttribute('d','M 0 0 H 3 M 2 -0.7 L 3 0 L 2 0.7');arrow.setAttribute('fill','none');arrow.setAttribute('stroke',color);arrow.setAttribute('stroke-width','.25');
      group.append(circle,arrow);overlay.append(group);
    });
  }
}
function renderSockets() {
  const sockets=info?.sockets,select=element<HTMLSelectElement>('socket-select');
  element('socket-panel').hidden=!sockets;select.replaceChildren();
  sockets?.names.forEach((name,index)=>select.add(new Option(`${index} · ${name}`,String(index))));
  const preferred=sockets?.names.indexOf(lastSample?.attachment?.socket??'')??-1;
  select.value=String(Math.max(0,preferred));
  element<HTMLInputElement>('show-attachment').disabled=!lastSample?.attachment;
  element<HTMLInputElement>('show-attachment').checked=!!lastSample?.attachment;
}
function renderPalette() {
  const root = element('palette'); root.replaceChildren(); if (!info) return;
  const count = info.maskCount, pageSize = 16;
  element('mask-count').textContent = String(count).padStart(2,'0');
  element('mask-pages').hidden = count <= pageSize;
  const first = maskPage*pageSize, end = Math.min(count,first+pageSize);
  element('mask-page-label').textContent = `${first}–${end-1}`;
  element<HTMLButtonElement>('mask-prev').disabled = maskPage === 0;
  element<HTMLButtonElement>('mask-next').disabled = end >= count;
  element<HTMLInputElement>('mask-goto').max = String(Math.max(0,count-1));
  element('mask-sharing').textContent = `${info.maskBindings}개 프레임 → ${info.maskMaps}개 마스크 배열 공유`;
  if (!count) {
    const p = document.createElement('p'); p.className = 'empty';
    p.textContent = '원본 RGBA만 사용하는 파일입니다. 마스크가 없습니다.'; root.append(p); return;
  }
  for (let index = first; index < end; index++) {
    const color = info.maskColors[index], label = maskLabel(info.groups,index);
    const base = color.hue === null ? null : displayHue(color.hue);
    const card = document.createElement('div'); card.className = 'mask-card';
    card.innerHTML = `<div class="mask-top"><span class="swatch-pair"><span class="swatch-sample"><span class="swatch original-swatch" role="img" aria-label="마스크 ${index} 원본 평균색"></span><small>원본</small></span><span class="swatch-sample"><span class="swatch modified-swatch" role="img" aria-label="마스크 ${index} 수정색"></span><small>수정</small></span></span><div><b class="mask-name"></b><small class="mask-group"></small></div><span class="mask-index">${index}</span></div><div class="hue-caption"><span>원본 평균 H</span><output class="average-hue"></output></div><input class="hue-range" type="range" min="0" max="359.9" step="0.1" aria-label="마스크 ${index} 색상각"><div class="mask-values"><label>H <input class="hue-target" type="number" min="0" max="359.9" step="0.1" placeholder="—" aria-label="마스크 ${index} H"></label><label>ΔH <input class="hue-number" type="number" min="-180" max="180" step="0.1" aria-label="마스크 ${index} 변화량"></label><button class="mask-reset subtle" aria-label="마스크 ${index} 색상 초기화">↺</button></div><p class="hue-offset-note"></p>`;
    card.querySelector('.mask-name')!.textContent = label.name;
    card.querySelector('.mask-group')!.textContent = label.group || '픽셀별 색상 · 알파 유지';
    card.querySelector('.average-hue')!.textContent = base !== null ? `${base.toFixed(1)}°` : color.rgb ? '무채색 · H 없음' : color.pixels ? '완전 투명 · H 없음' : '대상 픽셀 없음';
    const swatch = card.querySelector<HTMLElement>('.original-swatch')!;
    const modifiedSwatch = card.querySelector<HTMLElement>('.modified-swatch')!;
    modifiedSwatch.title = '원본 평균색에 ΔH를 적용한 미리보기';
    modifiedSwatch.classList.toggle('empty-swatch',!color.rgb);
    swatch.title = '원본 평균색';
    swatch.style.backgroundColor = color.rgb ? `rgb(${color.rgb.join(',')})` : 'transparent';
    swatch.classList.toggle('empty-swatch',!color.rgb);
    const range = card.querySelector<HTMLInputElement>('.hue-range')!;
    const target = card.querySelector<HTMLInputElement>('.hue-target')!;
    const number = card.querySelector<HTMLInputElement>('.hue-number')!;
    range.dataset.unavailable = target.dataset.unavailable = String(base === null);
    range.hidden = base === null;
    const update = (offset:number) => {
      number.value = String(offset);
      modifiedSwatch.style.backgroundColor = color.rgb ? `rgb(${shiftHue(...color.rgb,offset).join(',')})` : 'transparent';
      const h = base === null ? '' : String(displayHue(base+offset));
      target.value = h; range.value = h || '0';
      card.querySelector('.hue-offset-note')!.textContent = offset === 0 ? 'ΔH 0° · 원본색' : `ΔH ${offset>0?'+':''}${offset.toFixed(1)}° · 픽셀 알파 유지`;
    };
    const change = (offset:number) => {
      if (!Number.isFinite(offset) || offset < -180 || offset > 180 || status?.playing || resourceLoading) return;
      offsets[index] = offset; update(offset); send({type:'hue',index,offset,offsets:[...offsets]});
    };
    const changeTarget = (h:number) => { if (base !== null && Number.isFinite(h) && h >= 0 && h < 360) change(hueOffset(base,h)); };
    range.oninput = () => changeTarget(Number(range.value));
    target.onchange = () => { if (target.value!=='' && target.checkValidity()) changeTarget(Number(target.value)); else update(offsets[index]); };
    number.onchange = () => { if (number.value!=='' && number.checkValidity()) change(Number(number.value)); else update(offsets[index]); };
    card.querySelector<HTMLButtonElement>('.mask-reset')!.onclick = () => change(0);
    update(offsets[index]); root.append(card);
  }
  root.querySelectorAll<HTMLInputElement|HTMLButtonElement>('input,button').forEach(e=>e.disabled=resourceLoading || !!status?.playing || e.dataset.unavailable==='true');
}
function renderInfo(next:Info) {
  resourceLoading=false;
  document.querySelectorAll<HTMLInputElement|HTMLButtonElement|HTMLSelectElement>('#restart, #step, #seek, #clip, #reset-hues').forEach(e=>e.disabled=false);
  info=next;status=undefined;offsets=Array(next.maskCount).fill(0);maskPage=0;
  element('file-name').textContent=next.name;element('dimensions').textContent=`${next.width} × ${next.height}`;
  element('file-size').textContent=`${bytes(next.bytes)} · ${next.frames} frames`;
  element('title').textContent=lastSample?.title??next.name;element('subtitle').textContent=lastSample?.subtitle??'나의 PAPNG 리소스';
  const clips=element<HTMLSelectElement>('clip');clips.replaceChildren(new Option('전체 애니메이션',''));
  next.clips.forEach(clip=>clips.add(new Option(clip.name,clip.id)));
  element<HTMLInputElement>('seek').max=String(next.frames-1);
  const features=element('features');features.replaceChildren();
  for(const name of lastSample?.features??[`${next.maskCount} masks`,`${next.distributions.length} distributions`,`${next.controls.length} controls`]){const tag=document.createElement('span');tag.textContent=name;features.append(tag);}
  const records=element('records');records.replaceChildren();
  next.distributions.forEach((d,i)=>{const p=document.createElement('p');p.textContent=`분포 ${i} · ${DISTRIBUTION_NAMES[d.kind]??'RESERVED'}${d.valid?'':' · 오류'}`;records.append(p);});
  next.controls.forEach(c=>{const p=document.createElement('p');p.textContent=`프레임 ${c.frame} → ${CONTROL_NAMES[c.type]??'RESERVED'}`;records.append(p);});
  renderSockets();renderPalette();fit();updatePlayAvailability();
}
function renderStatus(next:Status) {
  if(next.ended)attachment.pause();
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
  element('cache-details').textContent=`${next.cache.entries}개 보관 · 적중 ${next.cache.hits} · 해제 ${next.cache.evictions} · 현재 합성 ${bytes(next.activeBytes)} · 마스크 캐시 ${bytes(next.maskBytes)} · 복원 ${next.reconstructions}회`;
  element('palette-note').textContent=next.playing?'일시정지하면 색상각을 변경할 수 있습니다.':'색상 변경 시 처음부터 복원합니다.';
  document.querySelectorAll<HTMLInputElement|HTMLButtonElement>('#palette input, #palette button, #reset-hues').forEach(e=>e.disabled=resourceLoading || next.playing || e.dataset.unavailable==='true');
}
worker.onmessage=(event:MessageEvent<Event>)=>{
  const m=event.data;
  if(m.type==='info')renderInfo(m.info);
  if(m.type==='status')renderStatus(m.status);
  if(m.type==='image'){canvas.width=m.width;canvas.height=m.height;baseImage=new ImageData(new Uint8ClampedArray(m.pixels),m.width,m.height);canvas.dataset.frame=String(m.frame);drawScene();}
  if(m.type==='warning')message(m.message);
  if(m.type==='error'){attachment.pause();message(m.message,true);element('subtitle').textContent='처리할 수 없는 파일입니다. 다른 샘플이나 파일을 열어 주세요.';element('loading').hidden=true;}
  if(m.type==='busy'){element('loading').hidden=!m.busy;element('loading').textContent=m.message??'픽셀 복원 중…';}
};
worker.onerror=()=>message('재생 작업을 시작할 수 없습니다. 이 브라우저의 Web Worker 지원을 확인하세요.',true);
async function load(buffer:ArrayBuffer,name:string,sample?:Sample) {
  resourceLoading=true;info=undefined;baseImage=undefined;status=undefined;
  canvas.width=1;canvas.height=1;canvas.dataset.frame='-1';
  element('overlay').replaceChildren();element('socket-panel').hidden=true;
  document.querySelectorAll<HTMLInputElement|HTMLButtonElement|HTMLSelectElement>('#palette input, #palette button, #restart, #step, #seek, #clip, #reset-hues').forEach(e=>e.disabled=true);
  lastSample=sample;messageCount=0;element('messages').replaceChildren();element('loading').hidden=false;element('loading').textContent='파일을 읽는 중…';
  element<HTMLButtonElement>('play').disabled=true;void attachment.load(sample?.attachment);send({type:'load',buffer,name},[buffer]);
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
element('reset-hues').onclick=()=>{if(info){offsets.fill(0);renderPalette();send({type:'reset-hues'});}};
element('mask-prev').onclick=()=>{maskPage=Math.max(0,maskPage-1);renderPalette();};
element('mask-next').onclick=()=>{if(info)maskPage=Math.min(Math.ceil(info.maskCount/16)-1,maskPage+1);renderPalette();};
element<HTMLInputElement>('mask-goto').onchange=e=>{const n=Number((e.target as HTMLInputElement).value);if(info&&Number.isInteger(n)&&n>=0&&n<info.maskCount){maskPage=Math.floor(n/16);renderPalette();}};
element('socket-select').onchange=drawScene;element('show-attachment').onchange=drawScene;element('show-sockets').onchange=fit;
element('zoom').onchange=fit;element('hints').onchange=fit;new ResizeObserver(fit).observe(element('canvas-stage'));
element('checker').onclick=()=>{const stage=element('canvas-stage'),off=stage.classList.toggle('solid');element('checker').setAttribute('aria-pressed',String(!off));};
async function init(){try{const response=await fetch(`${import.meta.env.BASE_URL}samples/manifest.json`);if(!response.ok)throw new Error('샘플 목록을 불러올 수 없습니다');samples=await response.json();element('sample-count').textContent=String(samples.length).padStart(2,'0');samples.forEach((sample,index)=>{const button=document.createElement('button');button.className='sample-card';button.dataset.file=sample.file;button.innerHTML=`<span class="sample-symbol symbol-${index}">${['✿','▥','◌','♧','◇','▰'][index]??'▦'}</span><span class="sample-copy"><b></b><small></small></span><span class="sample-arrow">↗</span>`;button.querySelector('b')!.textContent=sample.title;button.querySelector('small')!.textContent=`${sample.width} × ${sample.height} · ${sample.frames} frames`;button.onclick=()=>void loadSample(sample);element('samples').append(button);});if(samples[0])await loadSample(samples[0]);}catch(error){message(`${String(error)}. 파일 열기는 계속 사용할 수 있습니다.`,true);element('loading').hidden=true;}}
void init();
