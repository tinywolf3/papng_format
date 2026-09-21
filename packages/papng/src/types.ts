export interface MaskData { width: number; height: number; compressed: Uint8Array; valid: boolean }
export interface Distribution { kind: number; items?: { value: number; weight: number }[]; valid: boolean }
export interface Control { frame: number; type: number; values: number[]; valid: boolean }
export interface Clip { id: string; name: string; start: number; end: number; plays: number }
export interface MaskGroup { id: string; name: string; indices: number[] }
export type SocketPosition = [x: number, y: number, rotation: number];
export interface SocketFrame { frame: number; positions: SocketPosition[] }
export interface Sockets { names: string[]; frames: SocketFrame[] }
export interface Hints { display?: [number, number]; bbox?: [number, number, number, number]; scale?: number; pivot?: [number, number] }
export interface Frame {
  width: number; height: number; x: number; y: number;
  num: number; den: number; dispose: number; blend: number;
  compressed: Uint8Array[];
}
export interface Papng {
  width: number; height: number; plays: number; interlace: number;
  frames: Frame[]; maskCount: number; maskData: MaskData[]; frameMasks: Map<number, number>; distributions: Distribution[];
  controls: Map<number, Control[]>; clips: Clip[]; groups: MaskGroup[]; sockets?: Sockets;
  metadataText?: string; hints: Hints; warnings: string[]; byteLength: number;
}
export type Warn = (message: string) => void;
export function diagnostics(): { warnings: string[]; warn: Warn } {
  const warnings: string[] = [], seen = new Set<string>();
  return { warnings, warn(message) { if (!seen.has(message)) { seen.add(message); warnings.push(message); } } };
}
export function assert(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
export const CONTROL_NAMES = ['FIXED_DELAY', 'RANDOM_DELAY', 'RELATIVE_JUMP', 'ABSOLUTE_MOVE', 'RANDOM_RELATIVE_JUMP', 'RANDOM_ABSOLUTE_MOVE'];
export const DISTRIBUTION_NAMES = ['UNIFORM', 'TRIANGULAR', 'FAVOR_LOW', 'FAVOR_HIGH', 'WEIGHTED_VALUES'];
