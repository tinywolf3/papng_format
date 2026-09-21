import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import JSON5 from 'json5';
import { uniqueJson5 } from '../packages/papng/src/json5';
import { parsePapng } from '../packages/papng/src/parser';
import { encodePapng } from '../tools/sample-writer';

const rgba=Uint8Array.of(255,0,0,128);
const load=(metadataText:string,compressedMetadata=false)=>parsePapng(encodePapng({width:1,height:1,maskCount:1,frames:[{rgba}],metadataText,compressedMetadata}));
const plain=`{"schema_version":1,"clips":[{"id":"idle","start_frame":0,"end_frame":0,"play_count":0}],"mask_groups":[{"id":"body","palette_indices":[0]}],"sockets":{"definitions":[{"name":"hand"}],"frames":[{"frame_index":0,"positions":[[0,0]]}]}}`;
const annotated=`// Test asset notes
{
  schema_version: +1,
  /* authoring information; no effect on playback */
  developer_notes: {name:'참고 정보', url:'https://example.invalid/reference',},
  clips:[{id:'idle',start_frame:0x0,end_frame:0.,play_count:+0,},],
  mask_groups:[{id:'body',palette_indices:[0,],},],
  sockets:{definitions:[{name:'hand',},],frames:[{frame_index:0,positions:[[0,0,],],},],},
} // end
`;

test('plain and compressed JSON5 metadata preserve source comments and match ordinary JSON semantics',async()=>{
  const expected=await load(plain);
  for(const compressed of [false,true]) {
    const doc=await load(annotated,compressed);assert.deepEqual(doc.warnings,[]);
    assert.deepEqual(doc.clips,expected.clips);assert.deepEqual(doc.groups,expected.groups);assert.deepEqual(doc.sockets,expected.sockets);
    assert.equal(doc.metadataText,annotated);
  }
});

test('JSON5 scalar syntax and whitespace match the reference library while retaining own safe object members',()=>{
  const text=String.raw`{
    café:'value', \u006bey:'\x41\v\0\z',
    numbers:[.25,25.,+3,-0xA,1e2,Infinity,-Infinity,NaN,-NaN,],
    lines:'a\
b',
    comment:'/* literal */ // literal',
    __proto__:{polluted:true}, constructor:{prototype:{polluted:true}},
  }`;
  const reference=JSON5.parse(text),actual=uniqueJson5(text) as Record<string,unknown>;
  // Property prototypes deliberately differ; parsed values must agree.
  assert.equal(JSON5.stringify(actual),JSON5.stringify(reference));
  assert.equal(Object.getPrototypeOf(actual),null);assert.equal(({} as {polluted?:boolean}).polluted,undefined);
  for(const white of ['\t','\v','\f','\u00a0','\u1680','\u2000','\u2028','\u2029','\u3000']) {
    const input=`{${white}schema_version${white}:${white}1${white},${white}}`;
    assert.equal((uniqueJson5(input) as {schema_version:number}).schema_version,1);
  }
  assert.equal((uniqueJson5('{a:"x\\\r\ny"}') as {a:string}).a,'xy');
});

test('duplicate JSON5 names are rejected after decoding quotes and identifier escapes, including unknown objects',async()=>{
  for(const text of [
    `{schema_version:1, 'schema_version':1}`,
    String.raw`{schema_version:1, schema_\u0076ersion:1}`,
    String.raw`{schema_version:1, notes:{a:1,'\x61':2}}`,
    `{schema_version:1, notes:[{a:1,a:2}]}`,
    `{schema_version:1, notes:{__proto__:1,'__proto__':2}}`,
  ]) {
    assert.throws(()=>uniqueJson5(text),/중복 JSON5/);
    const doc=await load(text);assert.ok(doc.warnings.length);assert.equal(doc.metadataText,undefined);assert.deepEqual(doc.clips,[]);
  }
});

test('invalid JSON5, executable expressions and excessive nesting recover as optional metadata errors',async()=>{
  for(const text of [
    '{schema_version:1} trailing', '{schema_version:1,,}', '{schema_version:1, n:[,]}',
    '{schema_version:1, n:[1,,]}', '{schema_version:1 /* open}', "{schema_version:1, n:'open}",
    '{schema_version:1, n:undefined}', '{schema_version:1, n:()=>1}', '{schema_version:1, n:(globalThis.test=1)}',
    '{schema_version:1, n:1+1}', '{schema_version:1, n:0b10}', '{schema_version:1, 0:2}',
    '{schema_version:1, n:"raw\nline"}', '\ufeff{schema_version:1}',
    '{schema_version:1, n:'+ '['.repeat(128)+'0'+']'.repeat(128)+'}',
  ]) {
    const doc=await load(text);assert.ok(doc.warnings.length,text);assert.equal(doc.metadataText,undefined);
    assert.equal(doc.frames.length,1);
  }
  assert.equal((globalThis as {test?:number}).test,undefined);
});

test('recognized numeric fields reject nonfinite values but developer-only values are ignored',async()=>{
  const doc=await load(`{schema_version:1, developer_notes:{budget:Infinity, pending:NaN}, clips:[
    {id:'good',start_frame:0,end_frame:0,play_count:0},
    {id:'bad',start_frame:0,end_frame:0,play_count:Infinity},
  ], sockets:{definitions:[{name:'hand'}], frames:[{frame_index:0,positions:[[NaN,0]]}]}}`);
  assert.deepEqual(doc.clips.map(c=>c.id),['good']);assert.equal(doc.sockets,undefined);assert.ok(doc.warnings.length);
  assert.ok(doc.metadataText?.includes('developer_notes'));
});

test('the developer reference file is exactly the text embedded in the socket sample',async()=>{
  const source=readFileSync(new URL('../samples/socket-buddy-metadata.json5',import.meta.url),'utf8');
  const doc=await parsePapng(readFileSync(new URL('../samples/socket-buddy.papng',import.meta.url)));
  assert.equal(doc.metadataText,source);assert.ok(source.includes('//'));assert.ok(source.includes('/*'));assert.ok(source.includes('developer_notes:'));
  assert.deepEqual(doc.warnings,[]);
});
