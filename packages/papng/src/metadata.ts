import { assert, type Papng, type Warn } from './types';

// JSON.parse alone silently accepts duplicate keys; PAPNG must reject them.
export function uniqueJson(text: string): unknown {
  let pos = 0;
  const space = () => { while (/[ \t\r\n]/.test(text[pos] ?? '\0')) pos++; };
  function string(): string {
    const start = pos++;
    while (pos < text.length) {
      const char = text[pos++];
      if (char === '\\') pos++;
      else if (char === '"') return JSON.parse(text.slice(start, pos));
    }
    throw new Error('잘린 JSON 문자열');
  }
  function value(depth: number): unknown {
    assert(depth < 128, '메타데이터 중첩이 뷰어의 처리 예산을 넘었습니다'); space();
    const char = text[pos];
    if (char === '"') return string();
    if (char === '{' || char === '[') {
      pos++; space();
      const object = char === '{', end = object ? '}' : ']';
      const result: Record<string, unknown> = Object.create(null), array: unknown[] = [], keys = new Set();
      if (text[pos] !== end) while (true) {
        space();
        if (object) {
          assert(text[pos] === '"', 'JSON 객체 키가 문자열이 아닙니다');
          const key = string(); space();
          assert(!keys.has(key), '중복 JSON 객체 키'); keys.add(key);
          assert(text[pos++] === ':', 'JSON 구분자 오류'); result[key] = value(depth+1);
        } else array.push(value(depth+1));
        space(); if (text[pos] !== ',') break; pos++;
      }
      assert(text[pos++] === end, 'JSON 닫는 구분자 오류'); return object ? result : array;
    }
    const match = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(pos));
    assert(match, 'JSON 값 오류'); pos += match[0].length; return JSON.parse(match[0]);
  }
  const result = value(0); space(); assert(pos === text.length, 'JSON 후행 데이터 또는 BOM'); return result;
}
const obj = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
const uint = (x: unknown): x is number => typeof x === 'number' && Number.isInteger(x) && x >= 0 && x <= 0xffffffff;
export function parseMetadata(text: string, doc: Papng, warn: Warn) {
  try {
    const data = uniqueJson(text);
    assert(obj(data) && data.schema_version === 1, '지원하지 않는 메타데이터 스키마');
    for (const key of ['clips', 'mask_groups']) assert(data[key] === undefined || Array.isArray(data[key]), '메타데이터 배열 타입 오류');
    for (const clip of (data.clips ?? []) as unknown[]) {
      if (!obj(clip) || typeof clip.id !== 'string' || !clip.id || (clip.name !== undefined && typeof clip.name !== 'string') || !uint(clip.start_frame) || !uint(clip.end_frame) || clip.start_frame > clip.end_frame || clip.end_frame >= doc.frames.length || !uint(clip.play_count)) { warn('잘못된 클립 무시'); continue; }
      if (doc.clips.some(c => c.id === clip.id)) { warn('중복 클립 ID 무시'); continue; }
      doc.clips.push({ id: clip.id, name: (clip.name ?? clip.id) as string, start: clip.start_frame, end: clip.end_frame, plays: clip.play_count });
    }
    for (const group of (data.mask_groups ?? []) as unknown[]) {
      if (!obj(group) || typeof group.id !== 'string' || !group.id || (group.name !== undefined && typeof group.name !== 'string') || !Array.isArray(group.palette_indices) || !group.palette_indices.every(i => uint(i) && i < doc.masks.length) || new Set(group.palette_indices).size !== group.palette_indices.length) { warn('잘못된 마스크 그룹 무시'); continue; }
      if (doc.groups.some(g => g.id === group.id)) { warn('중복 마스크 그룹 ID 무시'); continue; }
      doc.groups.push({ id: group.id, name: (group.name ?? group.id) as string, indices: group.palette_indices });
    }
  } catch (error) { doc.clips = []; doc.groups = []; warn(`메타데이터 무시: ${String(error)}`); }
}
