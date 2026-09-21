import { Cancelled, type Cancel } from '../../../../packages/papng/src/compositor';
import { MaskPlanes } from '../../../../packages/papng/src/masks';
import { decodeFrame } from '../../../../packages/papng/src/pixels';
import type { MaskGroup, Papng } from '../../../../packages/papng/src/types';

// Viewer-only reference colors, never serialized or used by the PAPNG renderer.
export interface MaskColor {
  rgb: [number, number, number] | null;
  hue: number | null;
  pixels: number;
}
export const wrapHue = (degrees: number) => ((degrees % 360) + 360) % 360;
export const displayHue = (degrees: number) => (Math.round(wrapHue(degrees)*10) % 3600)/10;
export const hueOffset = (base: number, target: number) => Math.round((wrapHue(target-base+180)-180)*10)/10;

export function maskLabel(groups: MaskGroup[], index: number) {
  const memberships = groups.filter(group => group.indices.includes(index));
  const named = memberships.find(group => group.indices.length === 1 && group.name.trim());
  return {
    name: named?.name ?? `마스크 ${String(index).padStart(2,'0')}`,
    group: memberships.filter(group => group !== named).map(group => group.name).join(' · '),
  };
}

export async function averageMaskColors(
  doc: Papng,
  masks: MaskPlanes,
  cancel: Cancel = () => false,
  progress: (done: number, total: number) => void = () => {},
): Promise<MaskColor[]> {
  const sums = new Float64Array(doc.maskCount*5); // R*A, G*A, B*A, A, source pixel count
  const total = doc.frameMasks.size;
  let done = 0, yielded = performance.now();
  const check = () => { if (cancel()) throw new Cancelled(); };
  progress(0,total);
  for (const [frameIndex] of doc.frameMasks) {
    check();
    const words = await masks.get(frameIndex);
    if (words) {
      const rgba = await decodeFrame(doc.frames[frameIndex],doc.interlace);
      check();
      for (let start = 0; start < words.length; start += 32768) {
        for (let pixel = start; pixel < Math.min(words.length,start+32768); pixel++) {
          const word = words[pixel];
          if (!(word & 0x8000)) continue;
          const i = (word & 0x7fff)*5, p = pixel*4, alpha = rgba[p+3];
          sums[i] += rgba[p]*alpha; sums[i+1] += rgba[p+1]*alpha;
          sums[i+2] += rgba[p+2]*alpha; sums[i+3] += alpha; sums[i+4]++;
        }
        if (performance.now()-yielded >= 8) {
          progress(done,total);
          await new Promise<void>(resolve => setTimeout(resolve,0));
          check(); yielded = performance.now();
        }
      }
    }
    progress(++done,total);
  }
  check();
  return Array.from({length:doc.maskCount},(_,index) => {
    const i = index*5, alpha = sums[i+3], pixels = sums[i+4];
    if (!alpha) return {rgb:null,hue:null,pixels};
    const rgb: [number,number,number] = [sums[i]/alpha,sums[i+1]/alpha,sums[i+2]/alpha];
    const [r,g,b] = rgb, high = Math.max(...rgb), low = Math.min(...rgb), chroma = high-low;
    if (chroma < 1e-10) return {rgb,hue:null,pixels};
    const sector = high === r ? (g-b)/chroma : high === g ? (b-r)/chroma+2 : (r-g)/chroma+4;
    return {rgb,hue:wrapHue(sector*60),pixels};
  });
}
