import { assert } from './types';

export class Reader {
  offset = 0;
  private view: DataView;
  constructor(readonly data: Uint8Array) { this.view = new DataView(data.buffer, data.byteOffset, data.byteLength); }
  get remaining() { return this.data.length - this.offset; }
  need(n: number) { assert(Number.isSafeInteger(n) && n >= 0 && n <= this.remaining, '잘린 바이너리 필드'); }
  bytes(n: number) { this.need(n); const value = this.data.subarray(this.offset, this.offset + n); this.offset += n; return value; }
  u8() { this.need(1); return this.data[this.offset++]; }
  u16() { this.need(2); const v = this.view.getUint16(this.offset); this.offset += 2; return v; }
  u24() { return this.u8() * 65536 + this.u16(); }
  i24() { const v = this.u24(); return v >= 0x800000 ? v - 0x1000000 : v; }
  u32() { this.need(4); const v = this.view.getUint32(this.offset); this.offset += 4; return v; }
  i32() { this.need(4); const v = this.view.getInt32(this.offset); this.offset += 4; return v; }
}
const table = Uint32Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
export function crc32(bytes: Uint8Array) {
  let c = 0xffffffff;
  for (const b of bytes) c = table[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
export function concat(parts: Uint8Array[]) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) { out.set(p, offset); offset += p.length; }
  return out;
}
// Stream into a bounded destination instead of trusting a zlib expansion ratio.
export async function inflate(parts: Uint8Array[], maximum: number): Promise<Uint8Array> {
  let part = 0;
  const input = new ReadableStream<BufferSource>({ pull(controller) { if (part < parts.length) controller.enqueue(new Uint8Array(parts[part++])); else controller.close(); } });
  const reader = input.pipeThrough(new DecompressionStream('deflate')).getReader();
  const output: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      assert(size <= maximum, '압축 해제 결과가 허용된 바이트 범위를 넘었습니다');
      output.push(value);
    }
  } catch (error) { await reader.cancel().catch(() => {}); throw error; }
  finally { reader.releaseLock(); }
  return concat(output);
}
