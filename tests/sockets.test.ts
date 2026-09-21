import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parsePapng } from '../packages/papng/src/parser';
import { parseSockets, socketsAt } from '../packages/papng/src/sockets';
import { Player } from '../packages/papng/src/player';
import { encodePapng, pngChunk } from '../tools/sample-writer';
import { concat, Reader } from '../packages/papng/src/binary';

const definitions=[{name:'hand'},{name:'head'}];
const records=[{frame_index:0,positions:[[2,3,-90],[1.5,-2,370]]},{frame_index:3,positions:[[4,5,30],[2,1]]},{frame_index:6,positions:[[2,3],[1.5,-2]]}];
const load=(sockets:unknown,extra={})=>parsePapng(encodePapng({width:1,height:1,frames:Array.from({length:8},()=>({rgba:Uint8Array.of(255,0,0,255)})),metadata:{schema_version:1,sockets,...extra}}));

test('sparse socket poses resolve by numeric frame index, including reverse visits and omitted rotation',async()=>{
  const doc=await load({definitions,frames:records});assert.deepEqual(doc.warnings,[]);
  assert.deepEqual(doc.sockets?.names,['hand','head']);
  for(const [frame,source] of [[0,0],[5,3],[7,6],[2,0],[3,3],[1,0],[6,6]])assert.equal(socketsAt(doc.sockets,frame)?.frame,source);
  assert.deepEqual(socketsAt(doc.sockets,7)?.positions,[[2,3,0],[1.5,-2,0]]);
  assert.deepEqual(socketsAt(doc.sockets,3)?.positions[1],[2,1,0]);
  assert.equal(socketsAt(doc.sockets,-1),undefined);assert.equal(socketsAt(doc.sockets,NaN),undefined);
});

test('a clip can inherit a socket record before its start without traversing socket state',async()=>{
  const doc=await load({definitions,frames:records},{clips:[{id:'middle',start_frame:4,end_frame:7,play_count:1}]});
  const p=new Player(doc,0,()=>{});await p.start('middle');
  assert.equal(p.visit?.frame,4);assert.equal(socketsAt(doc.sockets,p.visit!.frame)?.frame,3);
  await p.seek(7);await p.seek(4);assert.equal(socketsAt(doc.sockets,p.visit!.frame)?.frame,3);
});

test('invalid later poses are skipped as a whole; duplicates use the first valid input record and order is numeric',async()=>{
  const doc=await load({definitions,frames:[
    {frame_index:3,positions:[[99,99]]},records[2],records[0],records[1],
    {frame_index:3,positions:[[9,9],[9,9]]},
    {frame_index:4,positions:[[8,8,9],null]},
    {frame_index:5,positions:[[8,8,'9'],[9,9]]},
    {frame_index:8,positions:[[9,9],[9,9]]}
  ]});
  assert.deepEqual(doc.sockets?.frames.map(f=>f.frame),[0,3,6]);
  assert.deepEqual(socketsAt(doc.sockets,5)?.positions,[[4,5,30],[2,1,0]]);
  assert.ok(doc.warnings.some(w=>w.includes('중복')));
});

test('invalid socket definitions or missing frame zero disable only sockets, preserving clips and image',async()=>{
  for(const sockets of [null,[],{}, {definitions:[{name:'a'},{name:'a'}],frames:records}, {definitions:[{name:''}],frames:records}, {definitions,frames:records.slice(1)}, {definitions,frames:[{frame_index:0,positions:[[0,0],[false,0]]}]}, {definitions:[],frames:records}]) {
    const doc=await load(sockets,{clips:[{id:'all',start_frame:0,end_frame:7,play_count:0}]});
    assert.equal(doc.sockets,undefined);assert.equal(doc.clips.length,1);assert.ok(doc.warnings.length);
    const p=new Player(doc,0,()=>{});await p.start();assert.deepEqual([...p.compositor.state!.pixels],[255,0,0,255]);
  }
  const empty=await load({definitions:[],frames:[]});assert.deepEqual(empty.warnings,[]);assert.equal(empty.sockets,undefined);
  const warnings:string[]=[];
  assert.equal(parseSockets({definitions:[{name:'a'}],frames:[{frame_index:0,positions:[[Infinity,0]]}]},1,w=>warnings.push(w)),undefined);
  assert.ok(warnings.length);
});

test('published bilingual metadata examples load and reset rotation at frame six',async()=>{
  for(const lang of ['ko','en']) {
    const text=readFileSync(new URL(`../spec/PAPNG-1.0.${lang}.md`,import.meta.url),'utf8');
    const metadata=JSON.parse(/```json\n([\s\S]*?)```/.exec(text)![1]);
    const doc=await parsePapng(encodePapng({width:1,height:1,maskCount:3,frames:Array.from({length:8},()=>({rgba:Uint8Array.of(0,0,0,0)})),metadata}));
    assert.deepEqual(doc.warnings,[]);assert.deepEqual(socketsAt(doc.sockets,5)?.positions[0],[13,14,30]);
    assert.deepEqual(socketsAt(doc.sockets,7)?.positions[0],[12,15,0]);
  }
});

test('duplicated PAPNG.Metadata disables sockets with the other optional metadata',async()=>{
  const source=encodePapng({width:1,height:1,frames:[{rgba:Uint8Array.of(0,0,0,0)}],metadata:{schema_version:1,sockets:{definitions,frames:[records[0]]}}});
  const r=new Reader(source);r.offset=8;const parts=[source.slice(0,8)];
  while(r.remaining){const size=r.u32(),kind=String.fromCharCode(...r.bytes(4)),data=r.bytes(size);r.u32();parts.push(pngChunk(kind,data));if(kind==='iTXt')parts.push(pngChunk(kind,data));}
  const doc=await parsePapng(concat(parts));assert.equal(doc.sockets,undefined);assert.ok(doc.warnings.some(w=>w.includes('중복 PAPNG.Metadata')));
});
