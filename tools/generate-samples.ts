import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { encodePapng, type SampleDefinition } from './sample-writer';

const directory = fileURLToPath(new URL('../samples/',import.meta.url));
type Color = [number,number,number,number];
const masks = [{hue:27000,alpha:255},{hue:54000,alpha:255},{hue:9000,alpha:255},{hue:34000,alpha:140}];
const masked = (index: number, v = 230, s = 185): Color => [index,s,v,1];
function art(width: number, height: number) {
  const rgba = new Uint8Array(width*height*4);
  const pixel = (x: number,y: number,c: Color) => { if (x >= 0 && y >= 0 && x < width && y < height) rgba.set(c,(y*width+x)*4); };
  const rect = (x: number,y: number,w: number,h: number,c: Color) => { for(let yy=y;yy<y+h;yy++) for(let xx=x;xx<x+w;xx++) pixel(xx,yy,c); };
  return {rgba,pixel,rect};
}
function sprite(phase: number) {
  const a = art(24,24), bob = phase % 4 === 2 ? -1 : 0;
  a.rect(5,21,14,1,[35,43,62,120]);
  a.rect(8,7+bob,8,1,masked(0,150)); a.rect(6,8+bob,12,2,masked(0,180));
  a.rect(5,10+bob,14,8,masked(0)); a.rect(6,18+bob,12,2,masked(0,180));
  a.rect(8,20+bob,3,1,masked(0,130)); a.rect(14,20+bob,3,1,masked(0,130));
  a.rect(7,10+bob,3,2,masked(0,255,90));
  a.rect(8,13+bob,2,phase===3?1:3,[26,32,47,255]); a.rect(15,13+bob,2,phase===3?1:3,[26,32,47,255]);
  a.rect(11,17+bob,3,1,[26,32,47,255]);
  a.rect(9,5+bob,6,2,masked(1)); a.rect(11,3+bob,2,3,masked(1,255));
  a.pixel(11,6+bob,masked(2,255)); a.pixel(12,5+bob,masked(2,255));
  a.rect(18,6-phase%3,2,2,masked(2)); a.pixel(19,5-phase%3,masked(2));
  a.rect(2,15,2,3,masked(3));
  return a.rgba;
}
const samples: {file:string;title:string;subtitle:string;features:string[];definition:SampleDefinition}[] = [];
samples.push({file:'palette-creature.papng',title:'팔레트 정원',subtitle:'같은 명암, 다른 색상각',features:['mask-palette','alpha','display','bbox','scale','pivot','clips','mask-groups'],definition:{width:24,height:24,masks,frames:Array.from({length:8},(_,i)=>({rgba:sprite(i),num:1,den:8})),hints:{display:[240,240],bbox:[2,3,19,19],scale:10,pivot:[12,21]},metadata:{schema_version:1,clips:[{id:'idle',name:'기본 · 전체',start_frame:0,end_frame:7,play_count:0},{id:'blink',name:'깜빡임 · 뒤쪽 클립',start_frame:2,end_frame:4,play_count:3}],mask_groups:[{id:'body',name:'몸과 그림자',palette_indices:[0,3]},{id:'flower',name:'꽃과 반짝임',palette_indices:[1,2]}]}}});
samples.push({file:'distribution-beats.papng',title:'확률의 박자',subtitle:'다섯 분포가 바꾸는 머무는 시간',features:['FIXED_DELAY','RANDOM_DELAY','UNIFORM','TRIANGULAR','FAVOR_LOW','FAVOR_HIGH','WEIGHTED_VALUES','den-zero'],definition:{width:24,height:24,masks,frames:Array.from({length:6},(_,i)=>{const a=art(24,24);for(let b=0;b<6;b++){a.rect(2+b*3,20-(b+1)*2,2,(b+1)*2,masked(i===b?2:0,i===b?255:100));}return{rgba:a.rgba,num:1,den:5};}),distributions:[{kind:1},{kind:2},{kind:3},{kind:4,items:[[150,1],[400,3],[900,1]]}],controls:[{frame:0,type:0,values:[50,0]},...Array.from({length:5},(_,i)=>({frame:i+1,type:1,values:i===4?[0,0,1000,4]:[100,900,1000,i]}))],hints:{scale:10}}});
samples.push({file:'jump-orbit.papng',title:'점프 궤도',subtitle:'상대·절대·랜덤 이동과 재방문',features:['RELATIVE_JUMP','ABSOLUTE_MOVE','RANDOM_RELATIVE_JUMP','RANDOM_ABSOLUTE_MOVE','backward','self-target','target-cache'],definition:{width:24,height:24,masks,frames:Array.from({length:8},(_,i)=>{const a=art(24,24);for(let n=0;n<8;n++){const angle=n*Math.PI/4,x=Math.round(11+8*Math.cos(angle)),y=Math.round(11+8*Math.sin(angle));a.rect(x,y,3,3,masked(n===i?2:0,n===i?255:100));}a.rect(9,10,6,4,masked(1));return{rgba:a.rgba,num:4,den:10};}),distributions:[{kind:4,items:[[-2,2],[0,1],[1,5]]}],controls:[{frame:0,type:2,values:[2]},{frame:2,type:3,values:[4]},{frame:4,type:4,values:[0,0,1]},{frame:5,type:5,values:[0,7,0]}],hints:{scale:10}}});
const base = art(16,16); base.rect(2,11,12,3,masked(0,140));
const trunk = art(4,8); trunk.rect(1,0,2,8,[111,73,66,255]);
const leaves = art(12,7); leaves.rect(2,0,8,2,masked(0)); leaves.rect(0,2,12,4,masked(0));
const flower = art(4,4);flower.rect(1,0,2,4,masked(1));flower.rect(0,1,4,2,masked(1));flower.rect(1,1,2,2,masked(2));
samples.push({file:'hidden-growth.papng',title:'보이지 않는 준비',subtitle:'0 지연 프레임 세 장이 나무를 완성',features:['zero-delay','partial-frames','SOURCE','OVER','BACKGROUND','finite-plays'],definition:{width:16,height:16,masks,plays:3,frames:[{rgba:base.rgba,num:0},{rgba:trunk.rgba,width:4,height:8,x:6,y:5,num:0,blend:1},{rgba:leaves.rgba,width:12,height:7,x:2,y:1,num:0,blend:1},{rgba:flower.rgba,width:4,height:4,x:9,y:2,num:8,den:10,blend:1,dispose:1},{rgba:flower.rgba,width:4,height:4,x:3,y:4,num:8,den:10,blend:1}],hints:{scale:15}}});
const backdrop=art(16,16);backdrop.rect(2,3,12,10,masked(0,125));
const glass=art(7,7);glass.rect(0,0,7,7,masked(3));glass.rect(2,2,3,3,masked(2,255));
const dot=art(2,2);dot.rect(0,0,2,2,masked(1));
samples.push({file:'restore-previous.papng',title:'유리와 잔상',subtitle:'반투명 OVER와 PREVIOUS 상태 복원',features:['PREVIOUS','OVER','partial-frames','interlace','compressed-metadata','backward'],definition:{width:16,height:16,masks,interlace:true,compressedMetadata:true,frames:[{rgba:backdrop.rgba,num:4,den:10},{rgba:glass.rgba,width:7,height:7,x:5,y:5,num:7,den:10,blend:1,dispose:2},{rgba:dot.rgba,width:2,height:2,x:3,y:4,num:6,den:10,blend:1}],controls:[{frame:2,type:2,values:[-1]}],metadata:{schema_version:1,mask_groups:[{id:'glass',name:'반투명 유리',palette_indices:[3]}]},hints:{scale:15}}});
samples.push({file:'300-frame-spectrum.papng',title:'300개의 작은 순간',subtitle:'1 × 1 캔버스 · 프레임 256을 넘어',features:['1x1','over-256-frames','ordinary-rgba','finite-plays','empty-palettes'],definition:{width:1,height:1,plays:1,frames:Array.from({length:300},(_,i)=>({rgba:Uint8Array.from([Math.round(127+127*Math.sin(i/47)),Math.round(127+127*Math.sin(i/47+2)),Math.round(127+127*Math.sin(i/47+4)),255]),num:1,den:100})),hints:{scale:128}}});
await mkdir(directory,{recursive:true});
for (const sample of samples) await writeFile(`${directory}/${sample.file}`,encodePapng(sample.definition));
await writeFile(`${directory}/manifest.json`,JSON.stringify(samples.map(({definition,...sample})=>({...sample,frames:definition.frames.length,width:definition.width,height:definition.height})),null,2)+'\n');
console.log(`Generated ${samples.length} deterministic PAPNG samples.`);
