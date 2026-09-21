import JSON5 from 'json5';
import { assert } from './types';

// Assemble containers ourselves so duplicate names are detected before they can
// be overwritten. JSON5 validates and decodes every scalar and property name.
export function uniqueJson5(text: string): unknown {
  assert(!text.startsWith('\ufeff'), 'PAPNG.Metadata는 BOM 없이 저장해야 합니다');
  let pos = 0;
  const white = (c: string) => /\s/u.test(c);
  function space() {
    while (pos < text.length) {
      if (white(text[pos])) { pos++; continue; }
      if (text.startsWith('//',pos)) {
        pos += 2;
        while (pos < text.length && !/[\r\n\u2028\u2029]/u.test(text[pos])) pos++;
      } else if (text.startsWith('/*',pos)) {
        const end = text.indexOf('*/',pos+2);
        assert(end >= 0, '닫히지 않은 JSON5 주석'); pos = end+2;
      } else break;
    }
  }
  function token(): string {
    const start = pos, quote = text[pos];
    if (quote === '"' || quote === "'") {
      pos++;
      while (pos < text.length) {
        const c = text[pos++];
        if (c === '\\') pos++;
        else if (c === quote) return text.slice(start,pos);
      }
      throw new Error('닫히지 않은 JSON5 문자열');
    }
    while (pos < text.length && !white(text[pos]) && !'{}[]:,/\"\''.includes(text[pos])) pos++;
    assert(pos > start, 'JSON5 값 또는 멤버 이름 오류');
    return text.slice(start,pos);
  }
  function value(depth: number): unknown {
    assert(depth < 128, '메타데이터 중첩이 뷰어의 처리 예산을 넘었습니다'); space();
    const char = text[pos];
    if (char !== '{' && char !== '[') return JSON5.parse(token());
    const object = char === '{', end = object ? '}' : ']';
    const result: Record<string,unknown> = Object.create(null), array: unknown[] = [], keys = new Set<string>();
    pos++; space();
    if (text[pos] !== end) while (true) {
      space();
      if (object) {
        const raw = token();
        const key = Object.keys(JSON5.parse(`{${raw}:null}`))[0];
        assert(!keys.has(key), '중복 JSON5 객체 키'); keys.add(key); space();
        assert(text[pos++] === ':', 'JSON5 멤버 구분자 오류'); result[key] = value(depth+1);
      } else array.push(value(depth+1));
      space();
      if (text[pos] !== ',') break;
      pos++; space(); if (text[pos] === end) break;
    }
    assert(text[pos++] === end, 'JSON5 닫는 구분자 오류');
    return object ? result : array;
  }
  const result = value(0); space(); assert(pos === text.length, 'JSON5 후행 데이터'); return result;
}
