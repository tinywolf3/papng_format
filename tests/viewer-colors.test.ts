import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { averageMaskColors, displayHue, hueOffset, maskLabel } from '../demos/web/viewer/src/mask-colors';
import { parsePapng } from '../packages/papng/src/parser';
import { MaskPlanes } from '../packages/papng/src/masks';
import { Cancelled } from '../packages/papng/src/compositor';
import { encodePapng, type SampleDefinition } from '../tools/sample-writer';

const rgba = (...values: number[]) => Uint8Array.from(values);
const mask = (...values: number[]) => Uint16Array.from(values);
async function reference(definition: SampleDefinition) {
  const doc = await parsePapng(encodePapng(definition));
  return averageMaskColors(doc,new MaskPlanes(doc,() => {}));
}

test('viewer averages source RGB with alpha weights across shared maps, including hidden frames',async() => {
  const doc = await parsePapng(encodePapng({width:1,height:1,maskCount:1,frames:[
    {rgba:rgba(255,0,0,200),mask:mask(0x8000),num:0},
    {rgba:rgba(0,0,255,100),mask:mask(0x8000),num:60000},
    {rgba:rgba(0,255,0,0),mask:mask(0x8000)},
  ]}));
  assert.equal(doc.maskData.length,1);
  const colors = await averageMaskColors(doc,new MaskPlanes(doc,() => {}));
  assert.deepEqual(colors,[{rgb:[170,0,85],hue:330,pixels:3}]);
  assert.equal(doc.frames[0].num,0); // Computing a reference does not normalize timing.
});

test('mean RGB hue wraps through red, excludes unassigned pixels, and includes alpha one',async() => {
  const colors = await reference({width:3,height:1,maskCount:1,frames:[
    {rgba:rgba(255,0,42,1,255,42,0,1,0,255,0,255),mask:mask(0x8000,0x8000,0)},
  ]});
  assert.deepEqual(colors,[{rgb:[255,21,21],hue:0,pixels:2}]);
});

test('averages use each source rectangle once, not canvas composition or frame duration',async() => {
  const colors = await reference({width:2,height:1,maskCount:1,frames:[
    {rgba:rgba(255,0,0,255,255,0,0,255),mask:mask(0x8000,0x8000),num:500},
    {rgba:rgba(0,0,255,255),mask:mask(0x8000),width:1,height:1,x:1,blend:1,num:1},
  ]});
  assert.deepEqual(colors,[{rgb:[170,0,85],hue:330,pixels:3}]);
});

test('achromatic means, fully transparent masks, and unused slots have no invented H',async() => {
  const colors = await reference({width:3,height:1,maskCount:4,frames:[
    {rgba:rgba(96,96,96,255,255,0,0,0,0,255,0,255),mask:mask(0x8000,0x8001,0)},
  ]});
  assert.deepEqual(colors,[{rgb:[96,96,96],hue:null,pixels:1},{rgb:null,hue:null,pixels:1},{rgb:null,hue:null,pixels:0},{rgb:null,hue:null,pixels:0}]);
});

test('reference scan reports progress and cancels when a new resource replaces it',async() => {
  const doc = await parsePapng(encodePapng({width:1,height:1,maskCount:1,frames:Array.from({length:3},() => ({rgba:rgba(255,0,0,255),mask:mask(0x8000)}))}));
  let cancelled = false; const progress: number[] = [];
  await assert.rejects(averageMaskColors(doc,new MaskPlanes(doc,() => {}),() => cancelled,(done,total) => {
    assert.equal(total,3); progress.push(done); if (done === 1) cancelled = true;
  }),Cancelled);
  assert.deepEqual(progress,[0,1]);
});

test('H controls use rounded reference degrees, shortest offsets, and wrap without drifting',() => {
  assert.equal(String(displayHue(148.4)),'148.4'); assert.equal(String(displayHue(296.8)),'296.8');
  assert.equal(displayHue(359.96),0); assert.equal(displayHue(-10),350);
  assert.equal(hueOffset(350,10),20); assert.equal(hueOffset(10,350),-20);
  const base = displayHue(126.6666667);
  assert.equal(hueOffset(base,base),0);
  assert.equal(displayHue(base+hueOffset(base,20)),20);
});

test('sample mask names come from singleton groups while broader group labels remain',async() => {
  const manifest = JSON.parse(readFileSync(new URL('../samples/manifest.json',import.meta.url),'utf8'));
  for (const sample of manifest) {
    const doc = await parsePapng(readFileSync(new URL(`../samples/${sample.file}`,import.meta.url)));
    for (let index=0;index<doc.maskCount;index++) {
      assert.ok(doc.groups.some(group => group.indices.length === 1 && group.indices[0] === index && group.name.trim()),`${sample.file}: mask ${index}`);
      assert.ok(!maskLabel(doc.groups,index).name.startsWith('마스크 '));
    }
  }
  assert.deepEqual(maskLabel([
    {id:'all',name:'몸체와 장식',indices:[0,3]},
    {id:'body',name:'몸체',indices:[0]},
    {id:'alias',name:'다른 이름',indices:[0]},
  ],0),{name:'몸체',group:'몸체와 장식 · 다른 이름'});
  assert.deepEqual(maskLabel([],8),{name:'마스크 08',group:''});
});
