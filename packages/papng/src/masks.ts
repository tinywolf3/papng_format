import { Reader, inflate } from './binary';
import { assert, type Papng, type Warn } from './types';

// paMD contains a pool of independently compressed maps, followed by bindings.
// Array positions are IDs, including invalid entries; never compact the pool.
export function parseMaskData(bytes: Uint8Array, doc: Papng, warn: Warn) {
  const r = new Reader(bytes);
  try {
    const count = r.u32();
    for (let i = 0; i < count; i++) {
      const width = r.u32(), height = r.u32(), size = r.u32();
      const compressed = r.bytes(size);
      const valid = width > 0 && height > 0 && width <= doc.width && height <= doc.height && size > 0;
      doc.maskData.push({width,height,compressed,valid});
      if (!valid) warn(`마스크 데이터 ${i}: 크기 오류, 원본 RGBA 사용`);
    }
    const bindings = r.u32();
    for (let i = 0; i < bindings; i++) {
      const frameIndex = r.u32(), mapIndex = r.u32();
      const frame = doc.frames[frameIndex], map = doc.maskData[mapIndex];
      if (!frame || !map?.valid || map.width !== frame.width || map.height !== frame.height) {
        warn(`프레임 ${frameIndex}: 잘못된 마스크 참조·크기, 원본 RGBA 사용`);
        continue;
      }
      if (doc.frameMasks.has(frameIndex)) { warn(`프레임 ${frameIndex}: 중복 마스크 참조 무시`); continue; }
      doc.frameMasks.set(frameIndex,mapIndex);
    }
    if (r.remaining) warn('paMD에 선언되지 않은 후행 데이터가 있습니다');
  } catch (error) {
    warn(`paMD 해석 중단, 검증한 참조만 유지: ${String(error)}`);
  }
}

export class MaskPlanes {
  // Palette edits do not invalidate membership maps. Bound their decoded cache
  // separately from color-dependent composition snapshots.
  private cache = new Map<number,Uint16Array>();
  private invalid = new Set<number>();
  bytes = 0;
  decodes = 0;
  constructor(readonly doc: Papng, readonly warn: Warn, readonly budget = 16*1024*1024) {}

  async get(frameIndex: number): Promise<Uint16Array | undefined> {
    const id = this.doc.frameMasks.get(frameIndex);
    if (id === undefined || this.invalid.has(id)) return;
    const cached = this.cache.get(id);
    if (cached) { this.cache.delete(id); this.cache.set(id,cached); return cached; }
    const map = this.doc.maskData[id];
    try {
      const expected = map.width*map.height*2;
      const bytes = await inflate([map.compressed],expected);
      assert(bytes.length === expected, '16비트 마스크 배열 길이 오류');
      const reader = new Reader(bytes), words = new Uint16Array(expected/2);
      for (let i = 0; i < words.length; i++) {
        const word = reader.u16(), active = !!(word & 0x8000);
        if (!active && word !== 0) this.warn(`마스크 데이터 ${id}: 미지정 픽셀의 하위 비트 무시`);
        if (active && (word & 0x7fff) >= this.doc.maskCount) this.warn(`마스크 데이터 ${id}: 인덱스 범위 오류, 해당 픽셀의 원본 RGBA 사용`);
        else if (active) words[i] = word;
      }
      this.decodes++;
      if (words.byteLength <= this.budget) {
        while (this.bytes+words.byteLength > this.budget) {
          const oldest = this.cache.keys().next().value!;
          this.bytes -= this.cache.get(oldest)!.byteLength; this.cache.delete(oldest);
        }
        this.cache.set(id,words); this.bytes += words.byteLength;
      }
      return words;
    } catch (error) {
      this.invalid.add(id); this.warn(`마스크 데이터 ${id}: 압축·배열 오류, 원본 RGBA 사용: ${String(error)}`);
    }
  }
}
