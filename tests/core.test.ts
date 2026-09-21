import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { encodePapng, extension, pngChunk, Writer, type SampleDefinition } from '../tools/sample-writer';
import { parsePapng } from '../packages/papng/src/parser';
import { decodeFrame, hueRgb } from '../packages/papng/src/pixels';
import { Player } from '../packages/papng/src/player';
import { Compositor } from '../packages/papng/src/compositor';
import { StateCache, stateBytes } from '../packages/papng/src/cache';
import { cumulative, randomBelow, sample } from '../packages/papng/src/random';
import { concat, Reader } from '../packages/papng/src/binary';
import { diagnostics } from '../packages/papng/src/types';

const rgba = (...values:number[]) => Uint8Array.from(values);
const red = rgba(255,0,0,255), blue = rgba(0,0,255,255), green = rgba(0,255,0,255), clear = rgba(0,0,0,0);
const simple = (extra:Partial<SampleDefinition> = {}):SampleDefinition => ({width:1,height:1,frames:[{rgba:red}],...extra});
const load = (d:SampleDefinition) => parsePapng(encodePapng(d));
const silent = () => {};
function draw(value:bigint) { let i=0;return ()=>++i%2 ? Number(value>>32n) : Number(value&0xffffffffn); }
function rewrite(bytes:Uint8Array, callback:(name:string,data:Uint8Array)=>Uint8Array|undefined) {
  const r=new Reader(bytes);r.offset=8;const parts=[bytes.slice(0,8)];
  while(r.remaining){const n=r.u32(),name=String.fromCharCode(...r.bytes(4)),data=r.bytes(n);r.u32();const next=callback(name,data);if(next)parts.push(pngChunk(name,next));}
  return concat(parts);
}

test('published samples cover every v1 control, distribution, hint and optional metadata',async()=>{
  const manifest=JSON.parse(readFileSync(new URL('../samples/manifest.json',import.meta.url),'utf8'));
  const controls=new Set<number>(),kinds=new Set<number>();let hints=false,clips=false,groups=false;
  for(const entry of manifest){
    const doc=await parsePapng(readFileSync(new URL(`../samples/${entry.file}`,import.meta.url)));
    assert.deepEqual(doc.warnings,[],entry.file);assert.equal(doc.frames.length,entry.frames);
    assert.equal(doc.width,entry.width);assert.equal(doc.height,entry.height);
    for(const list of doc.controls.values())for(const c of list)controls.add(c.type);
    doc.distributions.forEach(d=>kinds.add(d.kind));hints ||=Object.keys(doc.hints).length===4;clips ||=!!doc.clips.length;groups ||=!!doc.groups.length;
    const compositor=new Compositor(doc,1024*1024,silent);
    for(let i=0;i<doc.frames.length;i++)await compositor.seek(i);
  }
  assert.deepEqual([...controls].sort(),[0,1,2,3,4,5]);assert.deepEqual([...kinds].sort(),[0,1,2,3,4]);assert.ok(hints&&clips&&groups);
});

for(const interlace of [false,true])for(let filter=0;filter<=4;filter++)test(`raw RGBA preservation: filter ${filter}, Adam7 ${interlace}`,async()=>{
  const width=11,height=9,pixels=Uint8Array.from({length:width*height*4},(_,i)=>i%4===3?255:(i*31+17)%256);
  const doc=await load({width,height,interlace,frames:[{rgba:pixels,filter}]});
  assert.deepEqual(await decodeFrame(doc.frames[0],doc.interlace,[],silent),new Uint8ClampedArray(pixels));
});

test('mask markers restore H16/S8/V8 before compositing; palette alpha 1 is not a second marker',async()=>{
  const doc=await load({width:4,height:1,masks:[{hue:32768,alpha:1},{hue:0,alpha:128}],frames:[{rgba:rgba(0,255,255,1,1,128,200,1,8,255,255,1,17,29,31,2)}]});
  const {warn,warnings}=diagnostics(),decoded=await decodeFrame(doc.frames[0],0,doc.masks,warn);
  assert.deepEqual([...decoded],[0,255,255,1,...hueRgb(0,128,200),128,0,0,0,0,17,29,31,2]);assert.equal(warnings.length,1);
  assert.deepEqual(hueRgb(0),[255,0,0]);assert.deepEqual(hueRgb(32768),[0,255,255]);assert.deepEqual(hueRgb(65535),[255,0,0]);
});

test('poster outside animation is never used as its initial canvas or frame number',async()=>{
  const doc=await load({width:2,height:1,poster:concat([blue,blue]),frames:[{width:1,height:1,x:1,rgba:red}]});
  assert.equal(doc.frames.length,1);const c=new Compositor(doc,100,silent);
  assert.deepEqual([...(await c.seek(0)).pixels],[...clear,...red]);
});

test('hidden frames contribute; BACKGROUND/PREVIOUS, self, backward and cached seeks restore canonical state',async()=>{
  const doc=await load({width:2,height:1,frames:[
    {rgba:concat([red,clear]),num:0},
    {rgba:blue,width:1,height:1,x:1,dispose:2,blend:1},
    {rgba:green,width:1,height:1,x:0,dispose:1,blend:1},
    {rgba:blue,width:1,height:1,x:1,blend:1},
  ]});
  const expected=[[...red,...clear],[...red,...blue],[...green,...clear],[...clear,...blue]];
  for(const budget of [0,16,1024]){
    const c=new Compositor(doc,budget,silent);
    for(const target of [0,1,1,2,3,1,3,0,2,1,2])assert.deepEqual([...(await c.seek(target)).pixels],expected[target]);
    assert.ok(c.cache.used<=budget);
  }
});

test('straight-alpha OVER and SOURCE clearing obey PNG semantics',async()=>{
  const doc=await load(simple({frames:[{rgba:red},{rgba:rgba(0,0,255,128),blend:1,dispose:2},{rgba:clear,blend:0}]}));
  const c=new Compositor(doc,100,silent);
  assert.deepEqual([...(await c.seek(1)).pixels],[127,0,128,255]);
  assert.deepEqual([...(await c.seek(2)).pixels],[0,0,0,0]);
});

test('reconstruction consumes no RNG; random delay is drawn on entry and random target after wait',async()=>{
  const doc=await load(simple({frames:Array.from({length:4},()=>({rgba:red})),controls:[
    {frame:0,type:3,values:[2]},
    {frame:1,type:1,values:[100,200,1000,0]},
    {frame:2,type:5,values:[1,3,0]},
  ]}));
  let calls=0;const p=new Player(doc,0,silent,()=>{calls++;return 0;});
  await p.start();assert.equal(calls,0);await p.advance();assert.equal(p.visit?.frame,2);assert.equal(calls,0);
  await p.advance();assert.equal(p.visit?.frame,1);assert.equal(calls,4);assert.equal(p.visit?.ms,100);
  await p.compositor.seek(3);assert.equal(calls,4);
});

test('same-target visit neither disposes nor reblends and explicit jumps do not complete a loop',async()=>{
  const doc=await load(simple({plays:1,frames:[{rgba:rgba(200,0,0,128),blend:1,dispose:1}],controls:[{frame:0,type:2,values:[0]}]}));
  const p=new Player(doc,0,silent);await p.start();const first=p.compositor.state!.pixels.slice();
  for(let i=0;i<5;i++)await p.advance();assert.deepEqual(p.compositor.state!.pixels,first);assert.equal(p.completed,0);assert.equal(p.visits,6);assert.equal(p.compositor.reconstructions,1);
});

test('zero denominator, fractional positive delay, zero delay and finite repeat count remain distinct',async()=>{
  const doc=await load(simple({plays:1,frames:[{rgba:red,num:7,den:0},{rgba:blue},{rgba:green,num:0}],controls:[{frame:1,type:0,values:[1,65535]}]}));
  const p=new Player(doc,100,silent);await p.start();assert.equal(p.visit?.ms,70);
  await p.advance();assert.equal(p.visit?.hidden,false);assert.ok(p.visit!.ms<1);
  await p.advance();assert.equal(p.visit?.hidden,true);assert.equal(p.ended,false);
  assert.equal(await p.advance(),undefined);assert.equal(p.ended,true);assert.equal(p.completed,1);
});

test('invalid weighted candidates recover as a whole; zero-weight candidates are ignored and duplicate controls use first valid',async()=>{
  const {warn,warnings}=diagnostics();
  const doc=await load(simple({frames:[{rgba:red,num:900},{rgba:blue},{rgba:green}],
    distributions:[{kind:4,items:[[-1,1],[2,5]]},{kind:4,items:[[-1,0],[2,5]]}],
    controls:[{frame:0,type:1,values:[0,0,1000,1]},{frame:1,type:3,values:[99]},{frame:1,type:5,values:[0,0,2]}]}));
  const p=new Player(doc,100,warn,()=>0);await p.start();assert.equal(p.visit?.ms,10);assert.equal(p.visit?.effective.recovery,true);
  await p.advance();assert.equal(p.visit?.frame,1);assert.equal(p.visit?.effective.control?.type,5);await p.advance();assert.equal(p.visit?.frame,2);assert.equal(warnings.length,1);
});

test('clip starts reconstruct prefix, restrict targets and invalidate resolution from another playback context',async()=>{
  const doc=await load({width:2,height:1,frames:[{rgba:concat([red,clear])},{rgba:blue,width:1,height:1,x:1},{rgba:green,width:1,height:1,x:0}],controls:[{frame:1,type:3,values:[0]}],metadata:{schema_version:1,clips:[{id:'tail',start_frame:1,end_frame:2,play_count:1}]}});
  const p=new Player(doc,100,silent);await p.start('tail');assert.deepEqual([...p.compositor.state!.pixels],[...red,...blue]);assert.equal(p.visits,1);assert.equal(p.visit?.ms,10);assert.equal(p.visit?.effective.recovery,true);
  await p.advance();await p.advance();assert.equal(p.completed,1);assert.equal(p.ended,true);
  await p.start();await p.advance();assert.equal(p.visit?.effective.recovery,false);await p.advance();assert.equal(p.visit?.frame,0);
});

test('changing hue discards palette-dependent snapshots and reconstructs from frame zero',async()=>{
  const doc=await load(simple({masks:[{hue:0,alpha:255}],frames:[{rgba:rgba(0,255,255,1)},{rgba:clear,blend:1}]}));
  const p=new Player(doc,100,silent);await p.start();await p.advance();assert.deepEqual([...p.compositor.state!.pixels],[...red]);
  await p.setHue(0,32768);assert.equal(p.visit?.frame,0);assert.deepEqual([...p.compositor.state!.pixels],[0,255,255,255]);
  await p.advance();assert.deepEqual([...p.compositor.state!.pixels],[0,255,255,255]);
});

test('cache accounts for PREVIOUS, isolates snapshots, and retains a target longer without exceeding budget',()=>{
  const cache=new StateCache(8),state=(frame:number)=>({frame,pixels:new Uint8ClampedArray(4)});
  cache.put(state(0),10);cache.put(state(1));cache.put(state(2));assert.ok(cache.get(0));assert.equal(cache.get(1),undefined);assert.equal(cache.used,8);
  const copy=cache.get(0)!;copy.pixels[0]=255;assert.equal(cache.get(0)!.pixels[0],0);
  assert.equal(stateBytes({...state(4),previous:new Uint8ClampedArray(4)}),8);
  cache.setBudget(0);assert.equal(cache.used,0);cache.put(state(3));assert.equal(cache.stats().entries,0);
});

test('integer CDF matches each normative discrete weight for even and odd ranges',()=>{
  for(let n=1;n<=9;n++)for(let kind=0;kind<=3;kind++){
    const expected=Array.from({length:n},(_,i)=>[1,Math.min(i+1,n-i),n-i,i+1][kind]);
    let sum=0;for(let i=0;i<n;i++){
      assert.equal(cumulative(kind,BigInt(i+1),BigInt(n))-cumulative(kind,BigInt(i),BigInt(n)),BigInt(expected[i]));
      for(let j=0;j<expected[i];j++)assert.equal(sample({kind,valid:true},-4,n-5,draw(BigInt(sum+j))),i-4);
      sum+=expected[i];
    }
  }
});

test('full 32-bit ranges and probabilities above Number precision use exact integer arithmetic',()=>{
  const n=1n<<32n,total=cumulative(2,n,n);assert.ok(total>BigInt(Number.MAX_SAFE_INTEGER));
  assert.equal(sample({kind:2,valid:true},0,0xffffffff,draw(total-1n)),0xffffffff);
  assert.equal(sample({kind:0,valid:true},-2147483648,2147483647,draw(n-1n)),2147483647);
  const words=[0xffffffff,0xffffffff,0,4];assert.equal(randomBelow(10n,()=>words.shift()!),4n);assert.equal(words.length,0);
});

test('weighted values are signed int24 outputs, duplicates add weight and zero weights never win',async()=>{
  const doc=await load(simple({distributions:[{kind:4,items:[[-8388608,1],[123,0],[8388607,2],[8388607,1]]}]}));
  const d=doc.distributions[1];assert.equal(sample(d,900,0,draw(0n)),-8388608);
  for(let i=1;i<=3;i++)assert.equal(sample(d,900,0,draw(BigInt(i))),8388607);
});

test('malformed definitions retain distribution index slots and recover only affected controls',async()=>{
  const doc=await load(simple({distributions:[{kind:99},{kind:4,items:[[123,1]]}],controls:[{frame:0,type:1,values:[0,0,1000,2]}]}));
  assert.equal(doc.distributions.length,3);assert.equal(doc.distributions[1].valid,false);
  const p=new Player(doc,0,silent);await p.start();assert.equal(p.visit?.ms,123);assert.equal(p.visit?.effective.recovery,false);
});

test('bad paEX CRC disables extensions but keeps zero-time semantics; truncated body keeps a complete palette',async()=>{
  const definition=simple({masks:[{hue:0,alpha:255}],frames:[{rgba:rgba(0,255,255,1),num:0}]});
  const bytes=encodePapng(definition),r=new Reader(bytes);r.offset=8;
  while(r.remaining){const n=r.u32(),name=String.fromCharCode(...r.bytes(4));r.bytes(n);const offset=r.offset;r.u32();if(name==='paEX'){bytes[offset]^=1;break;}}
  const doc=await parsePapng(bytes);assert.equal(doc.masks.length,0);assert.ok(doc.warnings.length);const p=new Player(doc,0,silent);await p.start();assert.equal(p.visit?.hidden,true);assert.deepEqual([...p.compositor.state!.pixels],[...clear]);
  const truncated=rewrite(encodePapng(definition),(name,data)=>name==='paEX'?extension(definition).slice(0,61):data);
  const restored=await parsePapng(truncated);assert.equal(restored.masks.length,1);assert.ok(restored.warnings.length);
});

test('duplicate JSON keys, BOM and duplicate metadata disable optional metadata',async()=>{
  for(const metadataText of ['{"schema_version":1,"schema_version":1,"clips":[]}','\ufeff{"schema_version":1}']){
    const doc=await load(simple({metadataText}));assert.equal(doc.clips.length,0);assert.ok(doc.warnings.length);
  }
  const doc=await load(simple({metadata:{schema_version:1,clips:[{id:'a',start_frame:0,end_frame:0,play_count:1},{id:'bad',start_frame:true,end_frame:0,play_count:1},{id:'a',start_frame:0,end_frame:0,play_count:7}]},compressedMetadata:true}));
  assert.equal(doc.clips.length,1);assert.equal(doc.clips[0].plays,1);assert.ok(doc.warnings.length);
  const bytes=encodePapng(simple({metadata:{schema_version:1,clips:[{id:'a',start_frame:0,end_frame:0,play_count:1}]}}));
  const r=new Reader(bytes);r.offset=8;let textChunk=new Uint8Array();
  while(r.remaining){const n=r.u32(),name=String.fromCharCode(...r.bytes(4)),data=r.bytes(n);r.u32();if(name==='iTXt')textChunk=pngChunk(name,data);}
  const duplicate=await parsePapng(concat([bytes.slice(0,-12),textChunk,bytes.slice(-12)]));
  assert.equal(duplicate.clips.length,0);assert.ok(duplicate.warnings.some(s=>s.includes('중복 PAPNG.Metadata')));
});

test('malformed container CRC, sequence, unsupported format and incomplete pixels fail explicitly',async()=>{
  const bytes=encodePapng(simple());bytes[bytes.length-1]^=1;await assert.rejects(parsePapng(bytes),/CRC/);
  const noExt=rewrite(encodePapng(simple()),(name,data)=>name==='paEX'?undefined:data);await assert.rejects(parsePapng(noExt),/식별자/);
  const wrongSequence=rewrite(encodePapng(simple()),(name,data)=>name==='fcTL'?concat([new Writer().u32(9).finish(),data.slice(4)]):data);await assert.rejects(parsePapng(wrongSequence),/시퀀스/);
  const doc=await load(simple());doc.frames[0].width=2;await assert.rejects(decodeFrame(doc.frames[0],0,[],silent),/길이|크기/);
});
