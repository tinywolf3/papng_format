import { assert, type Distribution } from './types';

export type RandomWord = () => number;
export const cryptoWord: RandomWord = () => crypto.getRandomValues(new Uint32Array(1))[0];
export function randomBelow(limit: bigint, word: RandomWord = cryptoWord): bigint {
  assert(limit > 0n && limit <= 1n << 64n, '난수 범위 오류');
  if (limit === 1n) return 0n;
  const domain = 1n << 64n, threshold = domain - domain % limit;
  while (true) {
    const draw = (BigInt(word() >>> 0) << 32n) | BigInt(word() >>> 0);
    if (draw < threshold) return draw % limit;
  }
}
export function cumulative(kind: number, k: bigint, n: bigint): bigint {
  const triangle = (v: bigint) => v * (v + 1n) / 2n;
  if (kind === 0) return k;
  if (kind === 2) return k*n-k*(k-1n)/2n;
  if (kind === 3) return triangle(k);
  const middle = (n+1n)/2n;
  if (k <= middle) return triangle(k);
  const tail = k-middle;
  return triangle(middle)+tail*(n-middle)-tail*(tail-1n)/2n;
}
export function sample(distribution: Distribution, minimum: number, maximum: number, word: RandomWord = cryptoWord): number {
  assert(distribution.valid, '잘못된 분포');
  if (distribution.kind === 4) {
    const items = distribution.items!;
    let draw = randomBelow(BigInt(items.reduce((sum,item) => sum+item.weight,0)),word);
    for (const item of items) { if (draw < BigInt(item.weight)) return item.value; draw -= BigInt(item.weight); }
    throw new Error('가중치 합 오류');
  }
  assert(minimum <= maximum, '역전된 랜덤 범위');
  const n = BigInt(maximum)-BigInt(minimum)+1n, draw = randomBelow(cumulative(distribution.kind,n,n),word);
  // Exact integer CDF inversion: no range allocation, even for a 2^32-wide interval.
  let lo = 1n, hi = n;
  while (lo < hi) { const mid = (lo+hi)/2n; if (cumulative(distribution.kind,mid,n) > draw) hi = mid; else lo = mid+1n; }
  return minimum+Number(lo-1n);
}
