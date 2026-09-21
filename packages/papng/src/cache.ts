export interface CachedState { frame: number; pixels: Uint8ClampedArray; previous?: Uint8ClampedArray }
interface Entry { state: CachedState; bytes: number; tick: number; priority: number; hits: number }
export const stateBytes = (s: CachedState) => s.pixels.byteLength+(s.previous?.byteLength ?? 0);
export function cloneState(s: CachedState): CachedState { return {frame:s.frame,pixels:s.pixels.slice(),previous:s.previous?.slice()}; }
export class StateCache {
  private entries = new Map<number,Entry>();
  private tick = 0;
  used = 0; hits = 0; misses = 0; evictions = 0;
  constructor(public budget: number) {}
  clear() { this.entries.clear(); this.used = 0; this.hits = 0; this.misses = 0; this.evictions = 0; }
  get(frame: number, priority = 0): CachedState | undefined {
    const entry = this.entries.get(frame);
    if (!entry) { this.misses++; return; }
    entry.tick = ++this.tick; entry.priority = Math.max(priority,entry.priority); entry.hits = Math.min(8,entry.hits+1); this.hits++;
    return cloneState(entry.state);
  }
  nearestBefore(frame: number, after = -1) {
    let best = after;
    for (const index of this.entries.keys()) if (index < frame && index > best) best = index;
    return best > after ? this.get(best) : undefined;
  }
  put(state: CachedState, priority = 0) {
    const size = stateBytes(state);
    if (size > this.budget || this.budget === 0) return;
    const existing = this.entries.get(state.frame);
    if (existing) { existing.tick = ++this.tick; existing.priority = Math.max(priority,existing.priority); return; }
    this.entries.set(state.frame,{state:cloneState(state),bytes:size,tick:++this.tick,priority,hits:0});
    this.used += size; this.trim();
  }
  setBudget(bytes: number) { this.budget = Math.max(0,bytes); this.trim(); }
  private trim() {
    while (this.used > this.budget) {
      let victim = -1, lowest = Infinity;
      for (const [frame,e] of this.entries) {
        const score = (1+e.priority+Math.log2(1+e.hits))/(1+this.tick-e.tick);
        if (score < lowest) { lowest = score; victim = frame; }
      }
      const entry = this.entries.get(victim)!; this.used -= entry.bytes; this.entries.delete(victim); this.evictions++;
    }
  }
  stats() { return { bytes:this.used,budget:this.budget,entries:this.entries.size,hits:this.hits,misses:this.misses,evictions:this.evictions }; }
}
