import { Compositor, type Cancel } from './compositor';
import { delay, resolveControl, successor, targetPriority, type Effective, type Interval } from './controls';
import { cryptoWord, type RandomWord } from './random';
import { assert, type Papng, type Warn } from './types';

export interface Visit { frame: number; num: number; den: number; ms: number; hidden: boolean; effective: Effective }
export class Player {
  readonly compositor: Compositor;
  interval: Interval;
  visit?: Visit;
  completed = 0; ended = false; visits = 0;
  private resolved = new Map<number,Effective>();
  constructor(readonly doc: Papng, budget: number, readonly warn: Warn, readonly random: RandomWord = cryptoWord) {
    this.compositor = new Compositor(doc,budget,warn);
    this.interval = {start:0,end:doc.frames.length-1,plays:doc.plays};
  }
  async start(clipId?: string, cancel?: Cancel) {
    const clip = this.doc.clips.find(c => c.id === clipId);
    this.interval = clip ? {start:clip.start,end:clip.end,plays:clip.plays} : {start:0,end:this.doc.frames.length-1,plays:this.doc.plays};
    this.completed = 0; this.ended = false; this.visits = 0; this.resolved.clear();
    this.compositor.resetCurrent(); this.compositor.priority = targetPriority(this.doc,this.interval);
    return this.seek(this.interval.start,cancel);
  }
  async seek(frame: number, cancel?: Cancel) {
    assert(Number.isInteger(frame) && frame >= this.interval.start && frame <= this.interval.end, '프레임이 활성 구간 밖에 있습니다');
    await this.compositor.seek(frame,cancel);
    let effective = this.resolved.get(frame);
    if (!effective) { effective = resolveControl(this.doc,frame,this.interval,this.warn); this.resolved.set(frame,effective); }
    const [num,den] = delay(this.doc,frame,effective,this.random);
    this.visit = {frame,num,den,ms:num*1000/den,hidden:num === 0,effective}; this.visits++; this.ended = false;
    return this.visit;
  }
  async advance(cancel?: Cancel): Promise<Visit | undefined> {
    if (!this.visit || this.ended) return;
    const next = successor(this.doc,this.visit.frame,this.visit.effective,this.random);
    if (next.sequential && next.frame > this.interval.end) {
      this.completed++;
      if (this.interval.plays && this.completed >= this.interval.plays) { this.ended = true; return; }
      this.compositor.resetCurrent(); return this.seek(this.interval.start,cancel);
    }
    if (!next.sequential) {
      const current = this.compositor.priority.get(next.frame) ?? 0;
      this.compositor.priority.set(next.frame,Math.min(12,current+1));
    }
    return this.seek(next.frame,cancel);
  }
  async setHueOffset(index: number, offset: number, clipId?: string, cancel?: Cancel) {
    return this.setMaskAdjustment(index,offset,this.compositor.saturationOffsets[index],this.compositor.valueOffsets[index],clipId,cancel);
  }
  async setMaskAdjustment(index: number, hue: number, saturation: number, value: number, clipId?: string, cancel?: Cancel) {
    assert(Number.isInteger(index) && index >= 0 && index < this.doc.maskCount, '마스크 인덱스 오류');
    const normalized = [hue,saturation,value].map((v,i) => {
      if (!Number.isFinite(v)) { this.warn('유한하지 않은 HSV 변화량: 해당 성분을 0으로 복구'); return 0; }
      return i === 0 ? v % 360 : Math.max(-1,Math.min(1,v));
    });
    this.compositor.hueOffsets[index] = normalized[0];
    this.compositor.saturationOffsets[index] = normalized[1];
    this.compositor.valueOffsets[index] = normalized[2];
    this.compositor.invalidate();
    return this.start(clipId,cancel);
  }
}
