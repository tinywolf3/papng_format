import { Reader } from './binary';
import { assert, type Control, type Papng, type Warn } from './types';

export function parseExtension(bytes: Uint8Array, doc: Papng, warn: Warn) {
  const r = new Reader(bytes);
  r.bytes(8); const major = r.u16(), minor = r.u16(), size = r.u32();
  assert(major === 1 && size >= 56 && size <= bytes.length && (minor !== 0 || size === 56), '사용할 수 없는 paEX 헤더');
  if (minor > 0) warn(`PAPNG 1.${minor}: 알려진 기능만 사용`);
  const flags = r.u32(), dw = r.u32(), dh = r.u32(), bx = r.i32(), by = r.i32(), bw = r.u32(), bh = r.u32(), scale = r.u32(), px = r.i32(), py = r.i32();
  if (flags & 1) { if (dw && dh) doc.hints.display = [dw,dh]; else warn('잘못된 출력 크기 힌트 무시'); }
  if (flags & 2) { if (bx >= 0 && by >= 0 && bw && bh && bx+bw <= doc.width && by+bh <= doc.height) doc.hints.bbox = [bx,by,bw,bh]; else warn('잘못된 바운딩 박스 힌트 무시'); }
  if (flags & 4) { if (scale) doc.hints.scale = scale; else warn('잘못된 픽셀 배수 힌트 무시'); }
  if (flags & 8) doc.hints.pivot = [px,py];
  if (flags >>> 4) warn('알 수 없는 힌트 비트 무시');
  r.offset = size;
  // Once a section is fully bounded it can be retained after later truncation.
  try {
    const count = r.u16();
    if (count > 32768) warn('32768개를 초과한 마스크 개수: 마스크 기능 비활성화');
    else doc.maskCount = count;
    const distributionCount = r.u8();
    for (let i = 0; i < distributionCount; i++) {
      const kind = r.u8(), length = r.u24(), p = new Reader(r.bytes(length));
      const d = { kind, valid: false, items: undefined as { value: number; weight: number }[] | undefined };
      if (kind <= 3) d.valid = length === 0;
      else if (kind === 4 && length >= 4) {
        const count = p.u32();
        if (count > 0 && length === 4+4*count) {
          d.items = Array.from({length: count}, () => ({ value: p.i24(), weight: p.u8() }));
          d.valid = d.items.some(item => item.weight > 0);
        }
      }
      doc.distributions.push(d);
      if (!d.valid) warn(`분포 ${i+1} 정의가 유효하지 않습니다`);
    }
    const controlCount = r.u32();
    for (let i = 0; i < controlCount; i++) {
      const frame = r.u32(), type = r.u32(), length = r.u32(), p = new Reader(r.bytes(length));
      const valid = [4,7,4,4,9,9][type] === length;
      let values: number[] = [];
      if (valid) {
        if (type === 0) values = [p.u16(),p.u16()];
        if (type === 1) values = [p.u16(),p.u16(),p.u16(),p.u8()];
        if (type === 2) values = [p.i32()];
        if (type === 3) values = [p.u32()];
        if (type === 4) values = [p.i32(),p.i32(),p.u8()];
        if (type === 5) values = [p.u32(),p.u32(),p.u8()];
      }
      const control: Control = { frame, type, values, valid };
      if (frame >= doc.frames.length) { warn('존재하지 않는 프레임의 제어 무시'); continue; }
      const records = doc.controls.get(frame) ?? [];
      if (records.length) warn(`프레임 ${frame}: 중복 제어, 첫 유효 레코드 사용`);
      records.push(control); doc.controls.set(frame, records);
    }
    if (r.remaining) warn('paEX에 선언되지 않은 후행 데이터가 있습니다');
  } catch (error) { warn(`paEX 본문 해석 중단, 검증한 앞부분만 유지: ${String(error)}`); }
}
