import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { encodePapng, type SampleDefinition } from './sample-writer';
import { hueRgb } from '../packages/papng/src/pixels';

const directory = fileURLToPath(new URL('../samples/',import.meta.url));
type Color = [number,number,number,number,number?];
const paintColors = [{hue:27000,alpha:255},{hue:54000,alpha:255},{hue:9000,alpha:255},{hue:34000,alpha:140}];
const painted = (index: number, v = 230, s = 185): Color => [...hueRgb(paintColors[index].hue,s,v),paintColors[index].alpha,index];
function art(width: number, height: number) {
  const rgba = new Uint8Array(width*height*4), mask = new Uint16Array(width*height);
  const pixel = (x: number,y: number,c: Color) => { if (x >= 0 && y >= 0 && x < width && y < height) { rgba.set(c.slice(0,4) as number[],(y*width+x)*4); mask[y*width+x] = c[4] === undefined ? 0 : 0x8000|c[4]; } };
  const rect = (x: number,y: number,w: number,h: number,c: Color) => { for(let yy=y;yy<y+h;yy++) for(let xx=x;xx<x+w;xx++) pixel(xx,yy,c); };
  return {rgba,mask,pixel,rect};
}
function sprite(phase: number) {
  const a = art(24,24), bob = phase % 4 === 2 ? -1 : 0;
  a.rect(5,21,14,1,[35,43,62,120]);
  a.rect(8,7+bob,8,1,painted(0,150)); a.rect(6,8+bob,12,2,painted(0,180));
  a.rect(5,10+bob,14,8,painted(0)); a.rect(6,18+bob,12,2,painted(0,180));
  a.rect(8,20+bob,3,1,painted(0,130)); a.rect(14,20+bob,3,1,painted(0,130));
  a.rect(7,10+bob,3,2,painted(0,255,90));
  a.rect(8,13+bob,2,phase===3?1:3,[26,32,47,255]); a.rect(15,13+bob,2,phase===3?1:3,[26,32,47,255]);
  a.rect(11,17+bob,3,1,[26,32,47,255]);
  a.rect(9,5+bob,6,2,painted(1)); a.rect(11,3+bob,2,3,painted(1,255));
  a.pixel(11,6+bob,painted(2,255)); a.pixel(12,5+bob,painted(2,255));
  a.rect(18,6-phase%3,2,2,painted(2)); a.pixel(19,5-phase%3,painted(2));
  a.rect(2,15,2,3,painted(3));
  return {rgba:a.rgba,mask:a.mask};
}
const samples: {file:string;title:string;subtitle:string;features:string[];definition:SampleDefinition}[] = [];
samples.push({file:'palette-creature.papng',title:'팔레트 정원',subtitle:'원본 RGBA 보존 · 색상각 변화량 편집',features:['mask16','original-rgba','per-pixel-alpha','shared-maps','display','bbox','scale','pivot','clips','mask-groups'],definition:{width:24,height:24,maskCount:4,frames:Array.from({length:8},(_,i)=>({...sprite(i),num:1,den:8})),hints:{display:[240,240],bbox:[2,3,19,19],scale:10,pivot:[12,21]},metadata:{schema_version:1,clips:[{id:'idle',name:'기본 · 전체',start_frame:0,end_frame:7,play_count:0},{id:'blink',name:'깜빡임 · 뒤쪽 클립',start_frame:2,end_frame:4,play_count:3}],mask_groups:[{id:'body',name:'몸체와 장식',palette_indices:[0,3]},{id:'flower',name:'꽃과 반짝임',palette_indices:[1,2]}]}}});
samples.push({file:'distribution-beats.papng',title:'확률의 박자',subtitle:'다섯 분포가 바꾸는 머무는 시간',features:['FIXED_DELAY','RANDOM_DELAY','UNIFORM','TRIANGULAR','FAVOR_LOW','FAVOR_HIGH','WEIGHTED_VALUES','den-zero'],definition:{width:24,height:24,maskCount:4,frames:Array.from({length:6},(_,i)=>{const a=art(24,24);for(let b=0;b<6;b++){a.rect(2+b*3,20-(b+1)*2,2,(b+1)*2,painted(i===b?2:0,i===b?255:100));}return{rgba:a.rgba,mask:a.mask,num:1,den:5};}),distributions:[{kind:1},{kind:2},{kind:3},{kind:4,items:[[150,1],[400,3],[900,1]]}],controls:[{frame:0,type:0,values:[50,0]},...Array.from({length:5},(_,i)=>({frame:i+1,type:1,values:i===4?[0,0,1000,4]:[100,900,1000,i]}))],hints:{scale:10}}});
samples.push({file:'jump-orbit.papng',title:'점프 궤도',subtitle:'상대·절대·랜덤 이동과 재방문',features:['RELATIVE_JUMP','ABSOLUTE_MOVE','RANDOM_RELATIVE_JUMP','RANDOM_ABSOLUTE_MOVE','backward','self-target','target-cache'],definition:{width:24,height:24,maskCount:4,frames:Array.from({length:8},(_,i)=>{const a=art(24,24);for(let n=0;n<8;n++){const angle=n*Math.PI/4,x=Math.round(11+8*Math.cos(angle)),y=Math.round(11+8*Math.sin(angle));a.rect(x,y,3,3,painted(n===i?2:0,n===i?255:100));}a.rect(9,10,6,4,painted(1));return{rgba:a.rgba,mask:a.mask,num:4,den:10};}),distributions:[{kind:4,items:[[-2,2],[0,1],[1,5]]}],controls:[{frame:0,type:2,values:[2]},{frame:2,type:3,values:[4]},{frame:4,type:4,values:[0,0,1]},{frame:5,type:5,values:[0,7,0]}],hints:{scale:10}}});
const base = art(16,16); base.rect(2,11,12,3,painted(0,140));
const trunk = art(4,8); trunk.rect(1,0,2,8,[111,73,66,255]);
const leaves = art(12,7); leaves.rect(2,0,8,2,painted(0)); leaves.rect(0,2,12,4,painted(0));
const flower = art(4,4);flower.rect(1,0,2,4,painted(1));flower.rect(0,1,4,2,painted(1));flower.rect(1,1,2,2,painted(2));
samples.push({file:'hidden-growth.papng',title:'보이지 않는 준비',subtitle:'0 지연 프레임 세 장이 나무를 완성',features:['zero-delay','partial-frames','SOURCE','OVER','BACKGROUND','finite-plays'],definition:{width:16,height:16,maskCount:4,plays:3,frames:[{rgba:base.rgba,mask:base.mask,num:0},{rgba:trunk.rgba,mask:trunk.mask,width:4,height:8,x:6,y:5,num:0,blend:1},{rgba:leaves.rgba,mask:leaves.mask,width:12,height:7,x:2,y:1,num:0,blend:1},{rgba:flower.rgba,mask:flower.mask,width:4,height:4,x:9,y:2,num:8,den:10,blend:1,dispose:1},{rgba:flower.rgba,mask:flower.mask,width:4,height:4,x:3,y:4,num:8,den:10,blend:1}],hints:{scale:15}}});
const backdrop=art(16,16);backdrop.rect(2,3,12,10,painted(0,125));
const glass=art(7,7);glass.rect(0,0,7,7,painted(3));glass.rect(2,2,3,3,painted(2,255));
const dot=art(2,2);dot.rect(0,0,2,2,painted(1));
samples.push({file:'restore-previous.papng',title:'유리와 잔상',subtitle:'반투명 OVER와 PREVIOUS 상태 복원',features:['PREVIOUS','OVER','partial-frames','interlace','compressed-metadata','backward'],definition:{width:16,height:16,maskCount:4,interlace:true,compressedMetadata:true,frames:[{rgba:backdrop.rgba,mask:backdrop.mask,num:4,den:10},{rgba:glass.rgba,mask:glass.mask,width:7,height:7,x:5,y:5,num:7,den:10,blend:1,dispose:2},{rgba:dot.rgba,mask:dot.mask,width:2,height:2,x:3,y:4,num:6,den:10,blend:1}],controls:[{frame:2,type:2,values:[-1]}],metadata:{schema_version:1,mask_groups:[{id:'glass',name:'반투명 유리',palette_indices:[3]}]},hints:{scale:15}}});
samples.push({file:'300-frame-spectrum.papng',title:'300개의 작은 순간',subtitle:'1 × 1 캔버스 · 프레임 256을 넘어',features:['1x1','over-256-frames','ordinary-rgba','finite-plays','empty-palettes'],definition:{width:1,height:1,plays:1,frames:Array.from({length:300},(_,i)=>({rgba:Uint8Array.from([Math.round(127+127*Math.sin(i/47)),Math.round(127+127*Math.sin(i/47+2)),Math.round(127+127*Math.sin(i/47+4)),255]),num:1,den:100})),hints:{scale:128}}});
const ribbons = art(28,14);
const alphas = [0,1,32,64,128,192,255];
for (let band = 0; band < 7; band++) {
  ribbons.rect(band*4,1,4,5,[240,85,60,alphas[band],0]);
  ribbons.rect(band*4,8,4,5,[60,160,240,alphas[band],0]);
}
samples.push({file:'alpha-ribbons.papng',title:'하나의 마스크, 일곱 알파',subtitle:'원본 알파 0·1·32·64·128·192·255와 마스크 공유',features:['mask16','per-pixel-alpha','alpha-one','original-hue-variation','shared-maps'],definition:{width:28,height:14,maskCount:1,frames:Array.from({length:4},(_,i)=>({rgba:Uint8Array.from(ribbons.rgba,(v,n)=>n%4===3?v:Math.max(0,v-i*8)),mask:ribbons.mask,num:5,den:10})),metadata:{schema_version:1,mask_groups:[{id:'ribbons',name:'두 색상 · 일곱 알파',palette_indices:[0]}]},hints:{scale:12}}});
// A single-index mask group supplies a display name using existing v1 metadata.
const maskNames: Record<string,string[]> = {
  'palette-creature.papng': ['몸체','꽃잎','꽃술과 반짝임','반투명 장식'],
  'distribution-beats.papng': ['기본 막대','예비 마스크 1','강조 막대','예비 마스크 3'],
  'jump-orbit.papng': ['궤도 점','중앙 본체','활성 궤도 점','예비 마스크 3'],
  'hidden-growth.papng': ['땅과 나뭇잎','꽃잎','꽃술','예비 마스크 3'],
  'restore-previous.papng': ['배경','이동 점','유리 중심','반투명 유리'],
  'alpha-ribbons.papng': ['두 색상 · 일곱 알파'],
};
for (const sample of samples) {
  const names = maskNames[sample.file];
  if (!names) continue;
  const metadata = (sample.definition.metadata ?? {schema_version:1}) as Record<string,unknown>;
  const groups = (metadata.mask_groups ?? []) as {id:string;name:string;palette_indices:number[]}[];
  names.forEach((name,index) => {
    if (!groups.some(group => group.palette_indices.length === 1 && group.palette_indices[0] === index))
      groups.push({id:`mask-${index}`,name,palette_indices:[index]});
  });
  sample.definition.metadata = {...metadata,mask_groups:groups};
}
await mkdir(directory,{recursive:true});
for (const sample of samples) await writeFile(`${directory}/${sample.file}`,encodePapng(sample.definition));
await writeFile(`${directory}/manifest.json`,JSON.stringify(samples.map(({definition,...sample})=>({...sample,frames:definition.frames.length,width:definition.width,height:definition.height})),null,2)+'\n');
console.log(`Generated ${samples.length} deterministic PAPNG samples.`);
