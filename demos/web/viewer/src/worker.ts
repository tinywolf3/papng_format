import { parsePapng } from '../../../../packages/papng/src/parser';
import { averageMaskColors } from './mask-colors';
import { Player } from '../../../../packages/papng/src/player';
import { Cancelled } from '../../../../packages/papng/src/compositor';
import { stateBytes } from '../../../../packages/papng/src/cache';
import type { Command, Event } from './protocol';

const send = (message: Event, transfer: Transferable[] = []) => postMessage(message,{transfer});
let player: Player | undefined, clipId = '', playing = false, epoch = 0;
let visibleFrame = -1, deadline = 0, remaining = 0, timer: ReturnType<typeof setTimeout> | undefined;
let queue = Promise.resolve(), budget = 32*1024*1024, hiddenStreak = 0, lastStatus = 0;
const warnings = new Set<string>();
function warn(message: string) { if (!warnings.has(message)) { warnings.add(message); send({type:'warning',message}); } }
function status(force = true) {
  const now = performance.now();
  if (!player?.visit || (!force && now-lastStatus < 100)) return;
  lastStatus = now;
  const v = player.visit;
  send({type:'status',status:{frame:v.frame,visibleFrame,num:v.num,den:v.den,hidden:v.hidden,playing,ended:player.ended,completed:player.completed,visits:player.visits,start:player.interval.start,end:player.interval.end,control:v.effective.control?.type ?? null,recovery:v.effective.recovery,cache:player.compositor.cache.stats(),activeBytes:player.compositor.state?stateBytes(player.compositor.state):0,maskBytes:player.compositor.masks.bytes,reconstructions:player.compositor.reconstructions}});
}
function show() {
  if (!player?.visit || player.visit.hidden || !player.compositor.state) return;
  const pixels = new Uint8ClampedArray(player.compositor.state.pixels);
  visibleFrame = player.visit.frame;
  send({type:'image',pixels:pixels.buffer,width:player.doc.width,height:player.doc.height,frame:visibleFrame},[pixels.buffer]);
}
function clearImage() {
  if (!player) return;
  visibleFrame = -1;
  const pixels = new Uint8Array(player.doc.width*player.doc.height*4);
  send({type:'image',pixels:pixels.buffer,width:player.doc.width,height:player.doc.height,frame:-1},[pixels.buffer]);
}
function schedule() {
  clearTimeout(timer);
  if (!playing) return;
  timer = setTimeout(() => { const token = epoch; queue = queue.then(() => tick(token)).catch(fail); },Math.min(2147483647,Math.max(0,deadline-performance.now())));
}
function fail(error: unknown) {
  if (error instanceof Cancelled) return;
  playing = false; clearTimeout(timer); send({type:'busy',busy:false});
  send({type:'error',message:error instanceof Error?error.message:String(error)}); status();
}
async function tick(token: number) {
  if (!player || token !== epoch || !playing) return;
  const began = performance.now(); let work = 0;
  while (playing && token === epoch && player.visit && !player.ended && (player.visit.hidden || performance.now() >= deadline)) {
    const next = await player.advance(() => token !== epoch);
    if (token !== epoch) return;
    if (!next) { playing = false; break; }
    if (next.hidden) hiddenStreak++; else { hiddenStreak = 0; show(); deadline += next.ms; }
    if (hiddenStreak >= 1024) warn('시간이 진행되지 않는 순환입니다. 합성은 계속하되 UI에 제어권을 양보합니다. 일시정지할 수 있습니다.');
    if (++work >= 64 || performance.now()-began >= 8) break;
  }
  status(!playing); schedule();
}
async function firstVisible(token: number) {
  // A paused preview follows hidden setup visits too, but never spins forever.
  let n = 0;
  while (player?.visit?.hidden && !player.ended && n++ < 256) await player.advance(() => token !== epoch);
  if (token !== epoch || !player) return;
  if (player.visit?.hidden && !player.ended) warn('숨김 프레임 순환에서 미리보기를 멈췄습니다. 재생 또는 다음 버튼으로 계속할 수 있습니다.');
  show(); remaining = player.visit?.ms ?? 0; status();
}
async function handle(command: Command, token: number) {
  if (token !== epoch) return;
  const cancel = () => token !== epoch;
  if (command.type === 'load') {
    player = undefined; warnings.clear(); hiddenStreak = 0; send({type:'busy',busy:true});
    if (command.buffer.byteLength > 128*1024*1024) throw new Error('파일이 이 데모의 입력 예산 128 MiB를 넘었습니다. PAPNG 포맷 한도가 아닙니다.');
    const doc = await parsePapng(new Uint8Array(command.buffer)); if (cancel()) return;
    player = new Player(doc,budget,warn); clipId = '';
    let lastProgress = -Infinity;
    const maskColors = await averageMaskColors(doc,player.compositor.masks,cancel,(done,total) => {
      const now = performance.now();
      if (!total || (done !== total && now-lastProgress < 100)) return;
      lastProgress = now;
      send({type:'busy',busy:true,message:`원본 마스크 평균색 계산 중… ${done} / ${total} 프레임`});
    });
    if (cancel()) return;
    send({type:'info',info:{name:command.name,width:doc.width,height:doc.height,frames:doc.frames.length,bytes:doc.byteLength,maskCount:doc.maskCount,maskColors,maskMaps:doc.maskData.length,maskBindings:doc.frameMasks.size,clips:doc.clips,groups:doc.groups,sockets:doc.sockets,metadata:doc.metadataText===undefined?undefined:{text:doc.metadataText.slice(0,65536),truncated:doc.metadataText.length>65536},hints:doc.hints,distributions:doc.distributions.map(d=>({kind:d.kind,valid:d.valid})),controls:[...doc.controls.values()].flat().map(c=>({frame:c.frame,type:c.type}))}});
    for (const message of doc.warnings) warn(message);
    clearImage(); await player.start(undefined,cancel); await firstVisible(token); send({type:'busy',busy:false}); return;
  }
  if (!player) return;
  if (command.type === 'pause') { remaining = Math.max(0,deadline-performance.now()); status(); return; }
  if (command.type === 'play') {
    if (player.ended) { clearImage(); await player.start(clipId,cancel); await firstVisible(token); }
    playing = true; deadline = (command.startedAt === undefined ? performance.now() : command.startedAt-performance.timeOrigin)+remaining; status(); schedule(); return;
  }
  if (command.type === 'budget') { budget = command.bytes; player.compositor.cache.setBudget(budget); status(); return; }
  send({type:'busy',busy:true});
  if (command.type === 'hue') {
    if (command.offsets.length !== player.doc.maskCount || command.offsets.some(h => !Number.isFinite(h))) throw new Error('잘못된 색상각 변화량 배열');
    player.compositor.hueOffsets.set(command.offsets);
    clearImage(); await player.setHueOffset(command.index,command.offset,clipId,cancel);
  }
  if (command.type === 'reset-hues') { player.compositor.hueOffsets.fill(0); player.compositor.invalidate(); clearImage(); await player.start(clipId,cancel); }
  if (command.type === 'clip' || command.type === 'restart') { if (command.type === 'clip') clipId = command.id; clearImage(); await player.start(clipId,cancel); }
  if (command.type === 'seek') { await player.seek(command.frame,cancel); }
  if (command.type === 'step') { if (player.ended) { clearImage(); await player.start(clipId,cancel); } else await player.advance(cancel); }
  if (cancel()) return;
  await firstVisible(token); send({type:'busy',busy:false});
}
onmessage = (event: MessageEvent<Command>) => {
  const command = event.data;
  if (command.type !== 'budget') {
    playing = false; clearTimeout(timer);
    // Pause and play preserve any already-started transition; edits cancel it.
    if (command.type !== 'pause' && command.type !== 'play') epoch++;
  }
  const token = epoch;
  queue = queue.then(() => handle(command,token)).catch(fail);
};
