import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { encodePapng, extension, pngChunk, Writer, type SampleDefinition } from '../tools/sample-writer';
import { Reader, concat } from '../packages/papng/src/binary';
import { parsePapng } from '../packages/papng/src/parser';
import { Compositor } from '../packages/papng/src/compositor';
import { Player } from '../packages/papng/src/player';
import { MaskPlanes } from '../packages/papng/src/masks';
import { shiftHue } from '../packages/papng/src/pixels';
import { diagnostics } from '../packages/papng/src/types';

const red = Uint8Array.from([255,0,0,128]);
const base = (extra:Partial<SampleDefinition> = {}):SampleDefinition => ({width:1,height:1,maskCount:1,frames:[{rgba:red,mask:Uint16Array.from([0x8000])}],...extra});
function transform(bytes:Uint8Array,fn:(name:string,data:Uint8Array)=>Uint8Array[]) {
  const r=new Reader(bytes);r.offset=8;const result:Uint8Array[]=[bytes.slice(0,8)];
  while(r.remaining){const n=r.u32(),name=String.fromCharCode(...r.bytes(4)),data=r.bytes(n);r.u32();result.push(...fn(name,data));}
  return concat(result);
}
function withMaps(definition:SampleDefinition, maps:{width:number;height:number;raw?:number[];compressed?:Uint8Array}[], bindings:[number,number][]) {
  const w=new Writer().u32(maps.length);
  for(const m of maps){const raw=new Writer();for(const value of m.raw??[])raw.u16(value);const bytes=m.compressed??deflateSync(raw.finish());w.u32(m.width).u32(m.height).u32(bytes.length).bytes(bytes);}
  w.u32(bindings.length);for(const [frame,id] of bindings)w.u32(frame).u32(id);
  return transform(encodePapng(definition),(name,data)=>[pngChunk(name,name==='paMD'?w.finish():data)]);
}

test('mask_count is the only serialized palette field and includes all 32768 slots',async()=>{
  const definition=base({maskCount:32768,frames:[{rgba:red,mask:Uint16Array.from([0xffff])}]});
  const body=extension(definition);assert.equal(body.length,63);assert.deepEqual([...body.slice(56,58)],[0x80,0]);
  const doc=await parsePapng(encodePapng(definition));assert.equal(doc.maskCount,32768);
  const c=new Compositor(doc,64,()=>{});c.hueOffsets[32767]=-180;
  assert.deepEqual([...(await c.seek(0)).pixels],[0,255,255,128]);
});

test('identical map arrays share one record even when frame colors, alpha or offsets differ',async()=>{
  const membership=Uint16Array.from([0x8000]);
  const doc=await parsePapng(encodePapng(base({width:2,frames:[
    {rgba:Uint8Array.from([1,2,3,255,4,5,6,255])},
    {rgba:red,width:1,height:1,x:0,mask:membership},
    {rgba:Uint8Array.from([255,0,0,1]),width:1,height:1,x:1,mask:membership},
  ]})));
  assert.equal(doc.maskData.length,1);assert.deepEqual([...doc.frameMasks],[[1,0],[2,0]]);
  const c=new Compositor(doc,0,()=>{});c.hueOffsets[0]=180;
  assert.deepEqual([...(await c.seek(2)).pixels],[0,255,255,128,0,255,255,1]);
  assert.equal(c.masks.decodes,1);assert.equal(c.masks.bytes,2);
  c.hueOffsets[0]=0;c.invalidate();await c.seek(2);assert.equal(c.masks.decodes,1);
});

test('unassigned frames omit paMD and bindings do not inherit from previous frames',async()=>{
  const empty=await parsePapng(encodePapng(base({frames:[{rgba:red,mask:new Uint16Array(1)}]})));
  assert.equal(empty.maskCount,1);assert.equal(empty.maskData.length,0);assert.equal(empty.frameMasks.size,0);
  const doc=await parsePapng(encodePapng(base({frames:[{rgba:red,mask:Uint16Array.from([0x8000])},{rgba:red}]})));
  const c=new Compositor(doc,0,()=>{});c.hueOffsets[0]=180;
  assert.deepEqual([...(await c.seek(0)).pixels],[0,255,255,128]);
  assert.deepEqual([...(await c.seek(1)).pixels],[...red]);
});

test('mask_count zero still validates explicitly supplied all-zero or invalid arrays',async()=>{
  for(const word of [0,0x8000]) {
    const bytes=withMaps(base(),[{width:1,height:1,raw:[word]}],[[0,0]]);
    const noSlots=transform(bytes,(name,data)=>{const copy=data.slice();if(name==='paEX'){copy[56]=0;copy[57]=0;}return[pngChunk(name,copy)];});
    const doc=await parsePapng(noSlots),{warn,warnings}=diagnostics();
    assert.equal(doc.frameMasks.size,1);
    assert.deepEqual([...(await new Compositor(doc,0,warn).seek(0)).pixels],[...red]);
    assert.equal(warnings.length,word?1:0);
  }
});

test('mask order is row-major, independent of image filters and Adam7',async()=>{
  const pixels=Uint8Array.from({length:7*5*4},(_,i)=>i%4===0?255:i%4===3?i%256:0);
  const mask=Uint16Array.from({length:35},(_,i)=>i%3===0?0x8000:0);
  for(let filter=0;filter<=4;filter++){
    const doc=await parsePapng(encodePapng({width:7,height:5,maskCount:1,interlace:true,frames:[{rgba:pixels,mask,filter}]}));
    const c=new Compositor(doc,0,()=>{});c.hueOffsets[0]=180;const out=(await c.seek(0)).pixels;
    for(let i=0;i<35;i++)assert.deepEqual([...out.slice(i*4,i*4+4)],mask[i]?[0,255,255,pixels[i*4+3]]:[...pixels.slice(i*4,i*4+4)]);
  }
});

test('invalid indices and inactive low bits preserve source RGBA with warnings',async()=>{
  const definition=base({width:4,frames:[{rgba:concat([red,red,red,red]),mask:Uint16Array.from([0x8000,0,0,0])}]});
  const doc=await parsePapng(withMaps(definition,[{width:4,height:1,raw:[0,0x8000,0x8001,0x7fff]}],[[0,0]]));
  const {warn,warnings}=diagnostics(),c=new Compositor(doc,0,warn);c.hueOffsets[0]=180;
  assert.deepEqual([...(await c.seek(0)).pixels],[...red,0,255,255,128,...red,...red]);assert.equal(warnings.length,2);
});

test('malformed map slots preserve IDs; first structurally valid duplicate binding wins',async()=>{
  const doc=await parsePapng(withMaps(base(),[{width:0,height:1,raw:[]},{width:1,height:1,raw:[0x8000]}],[[0,0],[0,1],[0,1]]));
  assert.equal(doc.maskData.length,2);assert.equal(doc.frameMasks.get(0),1);assert.ok(doc.warnings.length>=2);
  const c=new Compositor(doc,0,()=>{});c.hueOffsets[0]=180;assert.deepEqual([...(await c.seek(0)).pixels],[0,255,255,128]);
});

test('out-of-range references and dimension mismatches keep original pixels and controls',async()=>{
  const d=base({controls:[{frame:0,type:0,values:[123,1000]}]});
  for(const bindings of [[[0,7]],[[1,0]]] as [number,number][][]){
    const doc=await parsePapng(withMaps(d,[{width:1,height:1,raw:[0x8000]}],bindings));
    const p=new Player(doc,0,()=>{});await p.setHueOffset(0,180);assert.deepEqual([...p.compositor.state!.pixels],[...red]);assert.equal(p.visit!.ms,123);assert.ok(doc.warnings.length);
  }
  const doc=await parsePapng(withMaps(base({width:2,frames:[{rgba:concat([red,red]),mask:Uint16Array.from([0x8000,0])}]}),[{width:1,height:1,raw:[0x8000]}],[[0,0]]));
  assert.equal(doc.frameMasks.size,0);assert.ok(doc.warnings.length);
});

test('corrupt, short, oversized and trailing zlib data recover without affecting alpha',async()=>{
  const variants=[Uint8Array.from([1,2,3]),deflateSync(Uint8Array.from([0x80])),deflateSync(Uint8Array.from([0x80,0,0,0])),concat([deflateSync(Uint8Array.from([0x80,0])),Uint8Array.from([1])])];
  for(const compressed of variants){
    const doc=await parsePapng(withMaps(base(),[{width:1,height:1,compressed}],[[0,0]]));
    const {warn,warnings}=diagnostics(),c=new Compositor(doc,0,warn);c.hueOffsets[0]=180;
    assert.deepEqual([...(await c.seek(0)).pixels],[...red]);assert.equal(warnings.length,1);
    c.invalidate();await c.seek(0);assert.equal(warnings.length,1);
  }
});

test('duplicate, misplaced or CRC-broken paMD is disabled as a unit',async()=>{
  const original=encodePapng(base());let maskChunk=new Uint8Array();
  transform(original,(name,data)=>{if(name==='paMD')maskChunk=pngChunk(name,data);return[];});
  const duplicate=transform(original,(name,data)=>name==='paMD'?[maskChunk,maskChunk]:[pngChunk(name,data)]);
  const misplaced=concat([transform(original,(name,data)=>name==='paMD'||name==='IEND'?[]:[pngChunk(name,data)]),maskChunk,pngChunk('IEND',new Uint8Array())]);
  const broken=transform(original,(name,data)=>{const chunk=pngChunk(name,data);if(name==='paMD')chunk[chunk.length-1]^=1;return[chunk];});
  for(const bytes of [duplicate,misplaced,broken]){
    const doc=await parsePapng(bytes);assert.equal(doc.frameMasks.size,0);assert.ok(doc.warnings.length);const p=new Player(doc,0,()=>{});await p.setHueOffset(0,180);assert.deepEqual([...p.compositor.state!.pixels],[...red]);
  }
});

test('truncation keeps only fully bounded bindings; oversized mask count leaves control parsing aligned',async()=>{
  const bytes=encodePapng(base({controls:[{frame:0,type:0,values:[50,1000]}]}));
  const truncated=transform(bytes,(name,data)=>[pngChunk(name,name==='paMD'?data.slice(0,-1):data)]);
  const doc=await parsePapng(truncated);assert.equal(doc.frameMasks.size,0);assert.ok(doc.warnings.length);assert.equal(doc.controls.get(0)![0].values[0],50);
  const overCount=transform(bytes,(name,data)=>{const copy=data.slice();if(name==='paEX'){copy[56]=0x80;copy[57]=1;}return[pngChunk(name,copy)];});
  const invalid=await parsePapng(overCount);assert.equal(invalid.maskCount,0);assert.equal(invalid.controls.get(0)![0].type,0);
});

test('hue offsets preserve chroma, vary per original hue, wrap, and never accumulate edits',async()=>{
  assert.deepEqual(shiftHue(255,0,0,120),[0,255,0]);assert.deepEqual(shiftHue(0,255,0,120),[0,0,255]);
  assert.deepEqual(shiftHue(255,0,0,-120),[0,0,255]);assert.deepEqual(shiftHue(17,29,31,360),[17,29,31]);assert.deepEqual(shiftHue(42,42,42,120),[42,42,42]);
  const {warn,warnings}=diagnostics(),p=new Player(await parsePapng(encodePapng(base())),64,warn);
  await p.setHueOffset(0,120);await p.setHueOffset(0,-120);assert.deepEqual([...p.compositor.state!.pixels],[0,0,255,128]);
  await p.setHueOffset(0,0);assert.deepEqual([...p.compositor.state!.pixels],[...red]);
  await p.setHueOffset(0,Infinity);assert.deepEqual([...p.compositor.state!.pixels],[...red]);assert.equal(warnings.length,1);
});

test('mask cache budget is bounded independently and eviction never changes membership',async()=>{
  const doc=await parsePapng(encodePapng(base({maskCount:2,frames:[{rgba:red,mask:Uint16Array.from([0x8000])},{rgba:red,mask:Uint16Array.from([0x8001])}]})));
  const cache=new MaskPlanes(doc,()=>{},2);assert.deepEqual([...(await cache.get(0))!],[0x8000]);assert.deepEqual([...(await cache.get(1))!],[0x8001]);assert.equal(cache.bytes,2);await cache.get(0);assert.equal(cache.decodes,3);
  const none=new MaskPlanes(doc,()=>{},0);await none.get(0);assert.equal(none.bytes,0);
});

test('published shared-mask binary vector is interoperable with the reader',async()=>{
  const text=readFileSync(new URL('../spec/PAPNG-1.0.ko.md',import.meta.url),'utf8');
  const hex=/<!-- vector: shared-mask-data -->\s*```hex\s*([\s\S]*?)```/.exec(text)![1];
  const bytes=Uint8Array.from(Buffer.from(hex.replace(/\s/g,''),'hex'));
  const definition=base({width:2,frames:[{rgba:concat([red,red]),mask:Uint16Array.from([0x8000,0])},{rgba:concat([red,red])}]});
  const file=transform(encodePapng(definition),(name,data)=>[pngChunk(name,name==='paMD'?bytes:data)]);
  const doc=await parsePapng(file);assert.deepEqual(doc.warnings,[]);assert.deepEqual([...doc.frameMasks],[[0,0],[1,0]]);
  const c=new Compositor(doc,0,()=>{});c.hueOffsets[0]=180;assert.deepEqual([...(await c.seek(1)).pixels],[0,255,255,128,...red]);
});
