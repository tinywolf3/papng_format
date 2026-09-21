import { deflateSync } from 'node:zlib';
import { concat, crc32 } from '../packages/papng/src/binary';
import { ADAM7 } from '../packages/papng/src/pixels';
import { assert } from '../packages/papng/src/types';

export class Writer {
  values: number[] = [];
  bytes(data: Iterable<number>) { this.values.push(...data); return this; }
  u8(n: number) { this.values.push(n & 255); return this; }
  u16(n: number) { return this.u8(n >>> 8).u8(n); }
  u24(n: number) { return this.u8(n >>> 16).u16(n); }
  u32(n: number) { return this.u16(n >>> 16).u16(n); }
  finish() { return Uint8Array.from(this.values); }
}
export interface SampleFrame { rgba: Uint8Array; mask?: Uint16Array; width?: number; height?: number; x?: number; y?: number; num?: number; den?: number; dispose?: number; blend?: number; filter?: number }
export interface SampleDefinition {
  width: number; height: number; frames: SampleFrame[]; plays?: number; maskCount?: number;
  distributions?: {kind:number; items?:[number,number][]; parameters?:Uint8Array}[];
  controls?: {frame:number; type:number; values:number[]; payload?:Uint8Array}[];
  hints?: {display?:[number,number];bbox?:[number,number,number,number];scale?:number;pivot?:[number,number]};
  metadata?: unknown; metadataText?: string; compressedMetadata?: boolean; interlace?: boolean; poster?: Uint8Array;
}
export function pngChunk(name: string, data: Uint8Array) {
  const body = concat([new TextEncoder().encode(name),data]);
  return concat([new Writer().u32(data.length).finish(),body,new Writer().u32(crc32(body)).finish()]);
}
export function extension(d: SampleDefinition) {
  const w = new Writer().bytes([80,65,80,78,71,0,0,0]).u16(1).u16(0).u32(56), h = d.hints ?? {};
  w.u32((h.display?1:0)|(h.bbox?2:0)|(h.scale?4:0)|(h.pivot?8:0));
  for (const n of [...h.display ?? [0,0],...h.bbox ?? [0,0,0,0],h.scale ?? 0,...h.pivot ?? [0,0]]) w.u32(n);
  w.u16(d.maskCount ?? 0);
  w.u8(d.distributions?.length ?? 0);
  for (const definition of d.distributions ?? []) {
    const p = new Writer();
    if (definition.kind === 4) { p.u32(definition.items!.length); for (const [value,weight] of definition.items!) p.u24(value).u8(weight); }
    const payload = definition.parameters ?? p.finish(); w.u8(definition.kind).u24(payload.length).bytes(payload);
  }
  w.u32(d.controls?.length ?? 0);
  for (const c of d.controls ?? []) {
    const p = new Writer(), v = c.values;
    if (c.type === 0) p.u16(v[0]).u16(v[1]);
    if (c.type === 1) p.u16(v[0]).u16(v[1]).u16(v[2]).u8(v[3]);
    if (c.type === 2 || c.type === 3) p.u32(v[0]);
    if (c.type === 4 || c.type === 5) p.u32(v[0]).u32(v[1]).u8(v[2]);
    const payload = c.payload ?? p.finish(); w.u32(c.frame).u32(c.type).u32(payload.length).bytes(payload);
  }
  return w.finish();
}
function scanlines(rgba: Uint8Array, width: number, height: number, interlace = false, filter = 0) {
  const output: Uint8Array[] = [];
  for (const [x,y,dx,dy] of interlace ? ADAM7 : [[0,0,1,1]]) {
    const w = Math.max(0,Math.ceil((width-x)/dx)), h = Math.max(0,Math.ceil((height-y)/dy));
    if (!w || !h) continue;
    let previous = new Uint8Array(w*4);
    for (let row = 0; row < h; row++) {
      const line = new Uint8Array(w*4), encoded = new Uint8Array(w*4+1); encoded[0] = filter;
      for (let col = 0; col < w; col++) line.set(rgba.subarray(((y+row*dy)*width+x+col*dx)*4,((y+row*dy)*width+x+col*dx)*4+4),col*4);
      for (let i = 0; i < line.length; i++) {
        const a = i >= 4 ? line[i-4] : 0, b = previous[i], c = i >= 4 ? previous[i-4] : 0, p = a+b-c;
        const pa = Math.abs(p-a), pb = Math.abs(p-b), pc = Math.abs(p-c), predictor = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
        encoded[i+1] = (line[i]-[0,a,b,Math.floor((a+b)/2),predictor][filter]) & 255;
      }
      output.push(encoded); previous = line;
    }
  }
  return deflateSync(concat(output),{level:9});
}
export function maskExtension(d: SampleDefinition): Uint8Array | undefined {
  const maps: {width:number;height:number;data:Uint8Array}[] = [];
  const ids = new Map<string,number>(), bindings: [number,number][] = [];
  d.frames.forEach((frame,index) => {
    if (!frame.mask) return;
    const width = frame.width ?? d.width, height = frame.height ?? d.height;
    assert(frame.mask.length === width*height, 'Mask array dimensions do not match the source frame');
    const raw = new Writer(); let active = false;
    for (const word of frame.mask) {
      if (word & 0x8000) {
        assert((word & 0x7fff) < (d.maskCount ?? 0), 'Mask index outside mask_count');
        active = true; raw.u16(word);
      } else raw.u16(0);
    }
    if (!active) return;
    const bytes = raw.finish(), key = `${width}x${height}:${Buffer.from(bytes).toString('base64')}`;
    let id = ids.get(key);
    if (id === undefined) { id = maps.length; ids.set(key,id); maps.push({width,height,data:deflateSync(bytes,{level:9})}); }
    bindings.push([index,id]);
  });
  if (!bindings.length) return;
  const out = new Writer().u32(maps.length);
  for (const map of maps) out.u32(map.width).u32(map.height).u32(map.data.length).bytes(map.data);
  out.u32(bindings.length);
  for (const [frame,id] of bindings) out.u32(frame).u32(id);
  return out.finish();
}
export function encodePapng(d: SampleDefinition) {
  const parts = [Uint8Array.from([137,80,78,71,13,10,26,10]),pngChunk('IHDR',new Writer().u32(d.width).u32(d.height).bytes([8,6,0,0,d.interlace?1:0]).finish()),pngChunk('acTL',new Writer().u32(d.frames.length).u32(d.plays ?? 0).finish()),pngChunk('paEX',extension(d))];
  const maskData = maskExtension(d);
  if (maskData) parts.push(pngChunk('paMD',maskData));
  if (d.metadata || d.metadataText) {
    const text = new TextEncoder().encode(d.metadataText ?? JSON.stringify(d.metadata));
    parts.push(pngChunk('iTXt',concat([new TextEncoder().encode('PAPNG.Metadata\0'),Uint8Array.from([d.compressedMetadata?1:0,0,0,0]),d.compressedMetadata?deflateSync(text):text])));
  }
  if (d.poster) parts.push(pngChunk('IDAT',scanlines(d.poster,d.width,d.height,d.interlace)));
  let sequence = 0;
  d.frames.forEach((f,index) => {
    const width = f.width ?? d.width, height = f.height ?? d.height;
    parts.push(pngChunk('fcTL',new Writer().u32(sequence++).u32(width).u32(height).u32(f.x ?? 0).u32(f.y ?? 0).u16(f.num ?? 1).u16(f.den ?? 10).u8(f.dispose ?? 0).u8(f.blend ?? 0).finish()));
    const compressed = scanlines(f.rgba,width,height,d.interlace,f.filter ?? 0);
    parts.push(!index && !d.poster ? pngChunk('IDAT',compressed) : pngChunk('fdAT',concat([new Writer().u32(sequence++).finish(),compressed])));
  });
  parts.push(pngChunk('IEND',new Uint8Array())); return concat(parts);
}
