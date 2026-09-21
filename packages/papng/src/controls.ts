import { type Control, type Papng, type Warn } from './types';
import { sample, type RandomWord } from './random';

export interface Interval { start: number; end: number; plays: number }
export interface Effective { control?: Control; recovery: boolean }
export function validControl(control: Control, doc: Papng, interval: Interval): boolean {
  if (!control.valid) return false;
  const {type,values:v,frame} = control;
  const targetOK = (value: number) => Number.isSafeInteger(value) && value >= interval.start && value <= interval.end && value >= 0 && value < doc.frames.length;
  if (type === 0) return true;
  if (type === 2) return targetOK(frame+v[0]);
  if (type === 3) return targetOK(v[0]);
  const distribution = doc.distributions[v[type === 1 ? 3 : 2]];
  if (!distribution?.valid) return false;
  const valueOK = (value: number) => type === 1 ? value >= 0 : targetOK(type === 4 ? frame+value : value);
  if (distribution.kind === 4) return distribution.items!.every(item => !item.weight || valueOK(item.value));
  return v[0] <= v[1] && valueOK(v[0]) && valueOK(v[1]);
}
export function resolveControl(doc: Papng, frame: number, interval: Interval, warn: Warn): Effective {
  const candidates = doc.controls.get(frame);
  if (!candidates) return { recovery: false };
  const control = candidates.find(c => validControl(c,doc,interval));
  if (!control) warn(`프레임 ${frame}: 잘못된 제어, 10 ms 후 순차 진행`);
  return { control, recovery: !control };
}
export function delay(doc: Papng, frame: number, effective: Effective, random: RandomWord): [number, number] {
  if (effective.recovery) return [1,100];
  const c = effective.control;
  if (c?.type === 0) return [c.values[0],c.values[1] || 100];
  if (c?.type === 1) {
    const [min,max,den,index] = c.values;
    return [sample(doc.distributions[index],min,max,random),den || 100];
  }
  return [doc.frames[frame].num, doc.frames[frame].den || 100];
}
export function successor(doc: Papng, frame: number, effective: Effective, random: RandomWord): { frame: number; sequential: boolean } {
  const c = effective.control;
  if (!c || c.type <= 1) return { frame: frame+1, sequential: true };
  if (c.type === 2) return {frame:frame+c.values[0],sequential:false};
  if (c.type === 3) return {frame:c.values[0],sequential:false};
  const [min,max,index] = c.values;
  const selected = sample(doc.distributions[index],min,max,random);
  return {frame: c.type === 4 ? frame+selected : selected, sequential:false};
}
// Sparse target hints only. Never materialize every member of a random interval.
export function targetPriority(doc: Papng, interval: Interval): Map<number, number> {
  const priority = new Map<number,number>([[0,3],[interval.start,5]]);
  const add = (frame: number, weight: number) => { if (frame >= interval.start && frame <= interval.end) priority.set(frame,Math.min(12,(priority.get(frame) ?? 0)+weight)); };
  for (const clip of doc.clips) add(clip.start,3);
  for (const [frame,records] of doc.controls) {
    if (frame < interval.start || frame > interval.end) continue;
    const c = records.find(c => validControl(c,doc,interval)); if (!c) continue;
    if (c.type === 2) add(frame+c.values[0],4);
    if (c.type === 3) add(c.values[0],4);
    if (c.type >= 4) {
      const [min,max,index] = c.values, distribution = doc.distributions[index];
      const shift = c.type === 4 ? frame : 0;
      if (distribution.kind === 4) {
        // Only a bounded set of high-weight destinations is worth proactively marking.
        const items = distribution.items!;
        if (items.length <= 256) for (const item of items) if (item.weight) add(shift+item.value,2);
      } else if (max-min <= 32) for (let value = min; value <= max; value++) add(shift+value,1);
    }
  }
  return priority;
}
