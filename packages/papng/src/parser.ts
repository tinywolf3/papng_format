import { Reader, crc32, inflate } from './binary';
import { assert, diagnostics, type Frame, type Papng } from './types';
import { parseExtension } from './extensions';
import { parseMetadata } from './metadata';
import { parseMaskData } from './masks';

const signature = [137,80,78,71,13,10,26,10], magic = [80,65,80,78,71,0,0,0];
export async function parsePapng(bytes: Uint8Array): Promise<Papng> {
  const { warnings, warn } = diagnostics();
  const doc: Papng = { width: 0, height: 0, plays: 0, interlace: 0, frames: [], maskCount: 0, maskData: [], frameMasks: new Map(), distributions: [{kind:0,valid:true}], controls: new Map(), hints: {}, clips: [], groups: [], warnings, byteLength: bytes.length };
  assert(signature.every((b,i) => bytes[i] === b), 'PNG 시그니처가 없습니다');
  const r = new Reader(bytes); r.offset = 8;
  const extensions: { data: Uint8Array; valid: boolean }[] = [], metadata: Uint8Array[] = [], maskChunks: {data:Uint8Array; valid:boolean}[] = [];
  let current: Frame | undefined, count = 0, sequence = 0, idat = false, endedIdat = false, ended = false, currentUsesIdat = false;
  while (r.remaining) {
    const length = r.u32(); assert(length <= 0x7fffffff, 'PNG 청크 길이 범위 오류');
    const start = r.offset, name = String.fromCharCode(...r.bytes(4)), data = r.bytes(length), crc = r.u32();
    assert(/^[A-Za-z]{2}[A-Z][A-Za-z]$/.test(name), 'PNG 청크 이름 오류');
    const valid = crc32(bytes.subarray(start, start+length+4)) === crc;
    assert(valid || name === 'paEX' || name === 'paMD' || name === 'iTXt', `${name} CRC 오류`);
    assert(doc.width || name === 'IHDR', 'IHDR이 첫 청크가 아닙니다');
    if (idat && name !== 'IDAT') endedIdat = true;
    const p = new Reader(data);
    if (name === 'IHDR') {
      assert(!doc.width && length === 13, 'IHDR 구조 오류');
      doc.width = p.u32(); doc.height = p.u32();
      assert(doc.width > 0 && doc.height > 0 && doc.width <= 0x7fffffff && doc.height <= 0x7fffffff, 'PNG 크기 오류');
      assert(p.u8() === 8 && p.u8() === 6 && p.u8() === 0 && p.u8() === 0, 'PAPNG는 RGBA8 PNG만 지원합니다');
      doc.interlace = p.u8(); assert(doc.interlace <= 1, 'PNG 인터레이스 오류');
      // Host capacity, explicitly not a PAPNG format limit. A state can require two canvases.
      assert(doc.width * doc.height * 4 <= 128 * 1024 * 1024, '이 뷰어의 캔버스 처리 예산(128 MiB)을 초과했습니다. 포맷 한도가 아닙니다.');
      if (doc.width * doc.height > 4096 * 4096) warn('큰 캔버스: 복원 시간과 메모리 사용량이 높을 수 있습니다');
    } else if (name === 'acTL') {
      assert(!count && !idat && length === 8, 'acTL 구조 또는 위치 오류'); count = p.u32(); doc.plays = p.u32(); assert(count > 0, '빈 APNG 애니메이션');
    } else if (name === 'fcTL') {
      assert(count && length === 26 && p.u32() === sequence++, 'fcTL 시퀀스 또는 구조 오류');
      assert(!current || current.compressed.length, '프레임 데이터 누락');
      current = { width:p.u32(), height:p.u32(), x:p.u32(), y:p.u32(), num:p.u16(), den:p.u16(), dispose:p.u8(), blend:p.u8(), compressed:[] };
      assert(current.width > 0 && current.height > 0 && current.x+current.width <= doc.width && current.y+current.height <= doc.height && current.dispose <= 2 && current.blend <= 1, '프레임 범위 또는 합성 연산 오류');
      if (!idat) assert(doc.frames.length === 0 && current.width === doc.width && current.height === doc.height && current.x === 0 && current.y === 0, '기본 이미지 프레임 크기 오류');
      currentUsesIdat = !idat;
      doc.frames.push(current);
    } else if (name === 'IDAT') {
      assert(count && !endedIdat, 'IDAT 순서 오류'); idat = true;
      if (current) current.compressed.push(data);
    } else if (name === 'fdAT') {
      assert(idat && current && !currentUsesIdat && length >= 4 && p.u32() === sequence++, 'fdAT 시퀀스 또는 위치 오류'); current.compressed.push(p.bytes(p.remaining));
    } else if (name === 'paEX') {
      extensions.push({ data, valid: valid && !idat });
    } else if (name === 'paMD') {
      maskChunks.push({data,valid:valid && !idat && extensions.length === 1});
    } else if (name === 'iTXt') {
      if (valid) metadata.push(data); else warn('iTXt CRC 오류: 메타데이터 무시');
    } else if (name === 'IEND') {
      assert(length === 0 && idat, 'IEND 오류'); ended = true; break;
    } else {
      assert(name[0] !== name[0].toUpperCase() || name === 'PLTE', `알 수 없는 필수 PNG 청크: ${name}`);
      if (name === 'iCCP' || name === 'gAMA' || name === 'cHRM') warn('이 데모는 색 관리 프로파일을 적용하지 않고 인코딩된 RGB 값을 표시합니다');
    }
  }
  assert(ended && !r.remaining && doc.frames.length === count && current?.compressed.length, 'APNG 종료 또는 프레임 개수 오류');
  const recognized = extensions.filter(e => magic.every((b,i) => e.data[i] === b));
  assert(recognized.length > 0, 'PAPNG 식별자가 없습니다. 이 뷰어는 일반 PNG 가져오기 도구가 아닙니다.');
  const ext = recognized[0];
  assert(ext.data.length >= 10 && new DataView(ext.data.buffer,ext.data.byteOffset).getUint16(8) === 1, '지원하지 않는 PAPNG 주 버전');
  let extensionUsable = false;
  if (extensions.length !== 1 || !ext.valid) warn('paEX 중복·CRC·위치 오류: 확장 비활성화');
  else {
    try { parseExtension(ext.data,doc,warn); extensionUsable = true; }
    catch (error) { doc.maskCount = 0; doc.controls.clear(); doc.distributions = [{kind:0,valid:true}]; doc.hints = {}; warn(`확장 비활성화: ${String(error)}`); }
  }
  if (maskChunks.length > 1 || maskChunks.some(c => !c.valid)) warn('paMD 중복·CRC·위치 오류: 원본 RGBA 사용');
  else if (maskChunks.length === 1 && extensionUsable) parseMaskData(maskChunks[0].data,doc,warn);
  let seenMetadata = false;
  for (const bytes of metadata) {
    const zero = bytes.indexOf(0);
    if (zero < 0 || new TextDecoder().decode(bytes.subarray(0,zero)) !== 'PAPNG.Metadata') continue;
    if (seenMetadata) { doc.clips = []; doc.groups = []; warn('중복 PAPNG.Metadata: 메타데이터 비활성화'); break; }
    seenMetadata = true;
    try {
      const p = new Reader(bytes.subarray(zero+1)), compression = p.u8(), method = p.u8();
      assert(compression <= 1 && method === 0, 'iTXt 압축 플래그 오류');
      for (let n = 0; n < 2; n++) { const end = p.data.indexOf(0,p.offset); assert(end >= 0, 'iTXt 필드 구분자 누락'); p.bytes(end-p.offset+1); }
      const textBytes = p.bytes(p.remaining);
      const decoded = compression ? await inflate([textBytes], 8*1024*1024) : textBytes;
      assert(decoded.length <= 8*1024*1024, '메타데이터가 뷰어의 8 MiB 처리 예산을 초과했습니다');
      parseMetadata(new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(decoded),doc,warn);
    } catch (error) { warn(`메타데이터 무시: ${String(error)}`); }
  }
  return doc;
}
