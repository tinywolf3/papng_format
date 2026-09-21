import type { SocketPosition } from '../../../../packages/papng/src/types';
import type { Command, Event, Info } from './protocol';

export interface Attachment { file: string; socket: string }

// Host-only resource association. A PAPNG metadata string never triggers a fetch.
export class AttachmentPreview {
  info?: Info;
  frame = -1;
  loading = false;
  private worker?: Worker;
  private abort?: AbortController;
  private generation = 0;
  private playing = false;
  private cancelReady?: () => void;
  private image = document.createElement('canvas');

  constructor(private changed: () => void, private warn: (message: string) => void) {}

  async load(binding?: Attachment) {
    const generation = ++this.generation;
    this.abort?.abort(); this.cancelReady?.(); this.worker?.terminate();
    this.worker = undefined; this.info = undefined; this.frame = -1; this.playing = false;
    this.loading = !!binding; this.changed();
    if (!binding) return;
    const abort = this.abort = new AbortController();
    const timeout = setTimeout(()=>abort.abort(),15000);
    try {
      const response = await fetch(`${import.meta.env.BASE_URL}samples/${binding.file}`,{signal:abort.signal});
      if (!response.ok) throw new Error('부속 샘플 파일을 찾을 수 없습니다');
      const buffer = await response.arrayBuffer();
      if (generation !== this.generation) return;
      const worker = this.worker = new Worker(new URL('./worker.ts',import.meta.url),{type:'module'});
      await new Promise<void>((resolve,reject)=>{
        const timer = setTimeout(()=>reject(new Error('부속 파일 준비 시간이 초과되었습니다')),15000);
        let settled=false;
        const finish = (error?:Error) => {if(settled)return;settled=true;clearTimeout(timer);this.cancelReady=undefined;error?reject(error):resolve();};
        const fail = (message:string) => {
          if(this.loading)finish(new Error(message));
          else {this.worker?.terminate();this.worker=undefined;this.info=undefined;this.frame=-1;this.playing=false;this.warn(`부속: ${message}`);this.changed();}
        };
        this.cancelReady=()=>finish();
        worker.onmessage=(event:MessageEvent<Event>)=>{
          if (generation !== this.generation) return;
          const m=event.data;
          if(m.type==='info')this.info=m.info;
          if(m.type==='image'){
            this.image.width=m.width;this.image.height=m.height;
            this.image.getContext('2d')!.putImageData(new ImageData(new Uint8ClampedArray(m.pixels),m.width,m.height),0,0);
            this.frame=m.frame;this.changed();
          }
          if(m.type==='warning')this.warn(`부속: ${m.message}`);
          if(m.type==='error')fail(m.message);
          if(m.type==='status' && m.status.ended)this.playing=false;
          if(m.type==='busy' && !m.busy && this.info)finish();
        };
        worker.onerror=()=>fail('부속 재생 작업을 시작할 수 없습니다');
        worker.postMessage({type:'load',buffer,name:binding.file} satisfies Command,[buffer]);
      });
    } catch(error) {
      if(generation === this.generation){this.worker?.terminate();this.worker=undefined;this.info=undefined;this.frame=-1;this.warn(`부속 연결 실패: ${String(error)}`);}
    } finally {
      clearTimeout(timeout);
      if(generation === this.generation){this.loading=false;this.changed();}
    }
  }

  play(startedAt:number) {
    if(!this.worker || this.loading || !this.info)return;
    this.playing=true;this.worker.postMessage({type:'play',startedAt} satisfies Command);
  }
  pause() {
    if(this.playing)this.worker?.postMessage({type:'pause'} satisfies Command);
    this.playing=false;
  }
  restart() {
    this.pause();
    if(!this.info || this.loading)return;
    this.frame=-1;this.worker?.postMessage({type:'restart'} satisfies Command);this.changed();
  }
  draw(ctx:CanvasRenderingContext2D,position:SocketPosition) {
    if(!this.info || this.frame < 0)return;
    const [x,y,r]=position,[px,py]=this.info.hints.pivot??[0,0];
    ctx.save();ctx.translate(x,y);ctx.rotate((r%360)*Math.PI/180);
    ctx.imageSmoothingEnabled=false;ctx.drawImage(this.image,-px,-py);ctx.restore();
  }
}
