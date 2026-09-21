import type { SocketPosition, SocketFrame, Sockets, Warn } from './types';

const object = (x: unknown): x is Record<string,unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
const finite = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x);

// Reject a whole position record: per-socket inheritance would mix poses.
export function parseSockets(data: unknown, frameCount: number, warn: Warn): Sockets | undefined {
  if (data === undefined) return;
  if (!object(data) || !Array.isArray(data.definitions) || !Array.isArray(data.frames)) {
    warn('소켓 비활성화: definitions와 frames 배열이 필요합니다'); return;
  }
  const names: string[] = [], seen = new Set<string>();
  for (const definition of data.definitions) {
    if (!object(definition) || typeof definition.name !== 'string' || !definition.name || seen.has(definition.name)) {
      warn('소켓 비활성화: 이름은 비어 있지 않고 중복되지 않아야 합니다'); return;
    }
    names.push(definition.name); seen.add(definition.name);
  }
  if (!names.length) {
    if (data.frames.length) warn('소켓 비활성화: 빈 정의에는 프레임 레코드를 넣을 수 없습니다');
    return;
  }
  const records = new Map<number,SocketFrame>();
  for (const record of data.frames) {
    if (!object(record) || !finite(record.frame_index) || !Number.isInteger(record.frame_index) || record.frame_index < 0 || record.frame_index >= frameCount || !Array.isArray(record.positions) || record.positions.length !== names.length || !record.positions.every(p => Array.isArray(p) && (p.length === 2 || p.length === 3) && p.every(finite))) {
      warn('잘못된 소켓 프레임 레코드 무시'); continue;
    }
    if (records.has(record.frame_index)) { warn('중복 소켓 프레임: 첫 번째 유효 레코드 사용'); continue; }
    const positions = record.positions.map(p => [p[0],p[1],p[2] ?? 0] as SocketPosition);
    records.set(record.frame_index,{frame:record.frame_index,positions});
  }
  if (!records.has(0)) { warn('소켓 비활성화: 유효한 0번 프레임 레코드가 필요합니다'); return; }
  return {names,frames:[...records.values()].sort((a,b)=>a.frame-b.frame)};
}

// A sparse, immutable frame-index lookup, independent of visits, clips or caches.
export function socketsAt(sockets: Sockets | undefined, frame: number): SocketFrame | undefined {
  if (!sockets || !Number.isInteger(frame) || frame < 0) return;
  let low = 0, high = sockets.frames.length;
  while (low < high) {
    const mid = low + Math.floor((high-low)/2);
    if (sockets.frames[mid].frame <= frame) low = mid+1; else high = mid;
  }
  return sockets.frames[low-1];
}
