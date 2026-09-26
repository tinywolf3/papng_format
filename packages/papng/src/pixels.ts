import { inflate } from './binary';
import { assert, type Frame } from './types';

export const ADAM7 = [[0,0,8,8], [4,0,8,8], [0,4,4,8], [2,0,4,4], [0,2,2,4], [1,0,2,2], [0,1,1,2]];
export function hueRgb(hue: number, saturation = 255, value = 255): [number, number, number] {
  const s = saturation / 255, v = value / 255, q = hue * 6 / 65536;
  const c = v * s, x = c * (1 - Math.abs(q % 2 - 1)), m = v - c;
  const rgb = [[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][Math.floor(q)];
  return rgb.map(n => Math.max(0, Math.min(255, Math.floor((n + m) * 255 + 0.5)))) as [number, number, number];
}
function paeth(a: number, b: number, c: number) {
  const p = a + b - c, pa = Math.abs(p-a), pb = Math.abs(p-b), pc = Math.abs(p-c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
export async function decodeFrame(frame: Frame, interlace: number): Promise<Uint8ClampedArray> {
  const passes = interlace ? ADAM7 : [[0,0,1,1]];
  const dimensions = passes.map(([x,y,dx,dy]) => [Math.max(0, Math.ceil((frame.width-x)/dx)), Math.max(0, Math.ceil((frame.height-y)/dy))]);
  const expected = dimensions.reduce((n, [w,h]) => n + (w && h ? h * (w * 4 + 1) : 0), 0);
  const raw = await inflate(frame.compressed, expected);
  assert(raw.length === expected, 'PNG 스캔라인 크기가 일치하지 않습니다');
  const pixels = new Uint8ClampedArray(frame.width * frame.height * 4);
  let offset = 0;
  for (let pass = 0; pass < passes.length; pass++) {
    const [x,y,dx,dy] = passes[pass], [w,h] = dimensions[pass];
    if (!w || !h) continue;
    let previous = new Uint8Array(w * 4);
    for (let row = 0; row < h; row++) {
      const filter = raw[offset++];
      assert(filter <= 4, '알 수 없는 PNG 필터');
      const line = raw.slice(offset, offset + w * 4); offset += w * 4;
      for (let i = 0; i < line.length; i++) {
        const a = i >= 4 ? line[i-4] : 0, b = previous[i], c = i >= 4 ? previous[i-4] : 0;
        line[i] = (line[i] + [0,a,b,Math.floor((a+b)/2),paeth(a,b,c)][filter]) & 255;
      }
      for (let col = 0; col < w; col++) pixels.set(line.subarray(col*4,col*4+4), ((y+row*dy)*frame.width+x+col*dx)*4);
      previous = line;
    }
  }
  return pixels;
}

// Compute HSV from the original RGB at full floating-point precision.
// Identity edits bypass conversion entirely.
export function shiftHue(r: number, g: number, b: number, degrees: number, saturation = 0, value = 0): [number, number, number] {
  const delta = Number.isFinite(degrees) ? ((degrees % 360) + 360) % 360 : 0;
  saturation = Number.isFinite(saturation) ? Math.max(-1, Math.min(1, saturation)) : 0;
  value = Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0;
  if (delta === 0 && saturation === 0 && value === 0) return [r,g,b];
  const high = Math.max(r,g,b), low = Math.min(r,g,b), chroma = high-low;
  let sector = chroma === 0 ? 0 : high === r ? (g-b)/chroma : high === g ? (b-r)/chroma+2 : (r-g)/chroma+4;
  sector = ((sector+delta/60)%6+6)%6;
  const sat = Math.max(0,Math.min(1,(high === 0 ? 0 : chroma/high)+saturation));
  const val = Math.max(0,Math.min(255,high+value*255));
  const c = val*sat, m = val-c, x = c*(1-Math.abs(sector%2-1));
  const channels = [[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][Math.floor(sector)];
  // Absorb floating-point noise at exact RGB8 half-step boundaries.
  return channels.map(n => Math.max(0,Math.min(255,Math.floor(n+m+0.5+1e-10)))) as [number,number,number];
}
