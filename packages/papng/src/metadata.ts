import { uniqueJson5 } from './json5';
import { parseSockets } from './sockets';
import { assert, type Papng, type Warn } from './types';

const obj = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
const uint = (x: unknown): x is number => typeof x === 'number' && Number.isInteger(x) && x >= 0 && x <= 0xffffffff;
export function parseMetadata(text: string, doc: Papng, warn: Warn) {
  try {
    const data = uniqueJson5(text);
    assert(obj(data) && data.schema_version === 1, '지원하지 않는 메타데이터 스키마');
    for (const key of ['clips', 'mask_groups']) assert(data[key] === undefined || Array.isArray(data[key]), '메타데이터 배열 타입 오류');
    doc.sockets = parseSockets(data.sockets,doc.frames.length,warn);
    for (const clip of (data.clips ?? []) as unknown[]) {
      if (!obj(clip) || typeof clip.id !== 'string' || !clip.id || (clip.name !== undefined && typeof clip.name !== 'string') || !uint(clip.start_frame) || !uint(clip.end_frame) || clip.start_frame > clip.end_frame || clip.end_frame >= doc.frames.length || !uint(clip.play_count)) { warn('잘못된 클립 무시'); continue; }
      if (doc.clips.some(c => c.id === clip.id)) { warn('중복 클립 ID 무시'); continue; }
      doc.clips.push({ id: clip.id, name: (clip.name ?? clip.id) as string, start: clip.start_frame, end: clip.end_frame, plays: clip.play_count });
    }
    for (const group of (data.mask_groups ?? []) as unknown[]) {
      if (!obj(group) || typeof group.id !== 'string' || !group.id || (group.name !== undefined && typeof group.name !== 'string') || !Array.isArray(group.palette_indices) || !group.palette_indices.every(i => uint(i) && i < doc.maskCount) || new Set(group.palette_indices).size !== group.palette_indices.length) { warn('잘못된 마스크 그룹 무시'); continue; }
      if (doc.groups.some(g => g.id === group.id)) { warn('중복 마스크 그룹 ID 무시'); continue; }
      doc.groups.push({ id: group.id, name: (group.name ?? group.id) as string, indices: group.palette_indices });
    }
    doc.metadataText = text;
  } catch (error) { doc.clips = []; doc.groups = []; doc.sockets = undefined; doc.metadataText = undefined; warn(`메타데이터 무시: ${String(error)}`); }
}
