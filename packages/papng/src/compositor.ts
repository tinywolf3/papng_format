import { decodeFrame } from './pixels';
import { StateCache, type CachedState } from './cache';
import { type Frame, type Papng, type Warn } from './types';

export class Cancelled extends Error {}
export type Cancel = () => boolean;
export class Compositor {
  state?: CachedState;
  readonly cache: StateCache;
  priority = new Map<number,number>();
  reconstructions = 0;
  constructor(readonly doc: Papng, budget: number, readonly warn: Warn) { this.cache = new StateCache(budget); }
  invalidate() { this.state = undefined; this.cache.clear(); }
  resetCurrent() { this.state = undefined; }
  private dispose(state: CachedState) {
    const frame = this.doc.frames[state.frame];
    if (frame.dispose === 2) { state.pixels = state.previous!; state.previous = undefined; }
    else if (frame.dispose === 1) for (let row = frame.y; row < frame.y+frame.height; row++) state.pixels.fill(0,(row*this.doc.width+frame.x)*4,(row*this.doc.width+frame.x+frame.width)*4);
  }
  private blend(canvas: Uint8ClampedArray, source: Uint8ClampedArray, f: Frame) {
    for (let y = 0; y < f.height; y++) for (let x = 0; x < f.width; x++) {
      const s = (y*f.width+x)*4, d = ((y+f.y)*this.doc.width+x+f.x)*4;
      if (f.blend === 0 || source[s+3] === 255) { canvas.set(source.subarray(s,s+4),d); continue; }
      const sa = source[s+3]/255, da = canvas[d+3]/255, alpha = sa+da*(1-sa);
      if (!sa) continue;
      for (let c = 0; c < 3; c++) canvas[d+c] = Math.floor((source[s+c]*sa+canvas[d+c]*da*(1-sa))/alpha+0.5);
      canvas[d+3] = Math.floor(alpha*255+0.5);
    }
  }
  async seek(target: number, cancelled: Cancel = () => false): Promise<CachedState> {
    if (this.state?.frame === target) return this.state;
    const exact = this.cache.get(target,this.priority.get(target) ?? 0);
    if (exact) { this.state = exact; return exact; }
    let state = this.state && this.state.frame < target ? this.state : undefined;
    const prefix = this.cache.nearestBefore(target,state?.frame ?? -1);
    if (prefix) state = prefix;
    if (!state) state = {frame:-1,pixels:new Uint8ClampedArray(this.doc.width*this.doc.height*4)};
    // Do not publish partially reconstructed state. A cancelled seek is invalidated by its caller.
    this.state = undefined;
    for (let index = state.frame+1; index <= target; index++) {
      if (cancelled()) throw new Cancelled();
      if (state.frame >= 0) this.dispose(state);
      const frame = this.doc.frames[index];
      const source = await decodeFrame(frame,this.doc.interlace,this.doc.masks,this.warn);
      if (cancelled()) throw new Cancelled();
      state.previous = frame.dispose === 2 ? state.pixels.slice() : undefined;
      this.blend(state.pixels,source,frame); state.frame = index; this.reconstructions++;
      if (index === target || this.priority.has(index) || index % 16 === 0) this.cache.put(state,this.priority.get(index) ?? 0);
      if (index % 8 === 7) await new Promise<void>(resolve => setTimeout(resolve,0));
    }
    this.state = state; return state;
  }
}
