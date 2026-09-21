import type { MaskColor } from './mask-colors';
import type { Clip, Hints, MaskGroup } from '../../../../packages/papng/src/types';
export type Command =
  | {type:'load';buffer:ArrayBuffer;name:string}
  | {type:'play'|'pause'|'restart'|'step'|'reset-hues'}
  | {type:'seek';frame:number}
  | {type:'hue';index:number;offset:number;offsets:number[]}
  | {type:'clip';id:string}
  | {type:'budget';bytes:number};
export interface Info {name:string;width:number;height:number;frames:number;bytes:number;maskCount:number;maskColors:MaskColor[];maskMaps:number;maskBindings:number;clips:Clip[];groups:MaskGroup[];hints:Hints;distributions:{kind:number;valid:boolean}[];controls:{frame:number;type:number}[]}
export interface Status {frame:number;visibleFrame:number;num:number;den:number;hidden:boolean;playing:boolean;ended:boolean;completed:number;visits:number;start:number;end:number;control:number|null;recovery:boolean;cache:{bytes:number;budget:number;entries:number;hits:number;misses:number;evictions:number};activeBytes:number;maskBytes:number;reconstructions:number}
export type Event =
  | {type:'info';info:Info}
  | {type:'image';pixels:ArrayBuffer;width:number;height:number;frame:number}
  | {type:'status';status:Status}
  | {type:'warning';message:string}
  | {type:'error';message:string}
  | {type:'busy';busy:boolean;message?:string};
