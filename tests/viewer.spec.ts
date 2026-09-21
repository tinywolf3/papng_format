import { test, expect, type Page } from '@playwright/test';
import { encodePapng } from '../tools/sample-writer';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const artifacts=fileURLToPath(new URL('../builds/web/viewer-tests/',import.meta.url));
mkdirSync(artifacts,{recursive:true});
const canvas=(page:Page)=>page.locator('#canvas');
const pixels=(page:Page)=>canvas(page).evaluate((node:HTMLCanvasElement)=>Array.from(node.getContext('2d')!.getImageData(0,0,node.width,node.height).data));
async function choose(page:Page,file:string,frame=0){await page.locator(`[data-file="${file}"]`).click();await expect(page.locator('#file-name')).toHaveText(file);await expect(canvas(page)).toHaveAttribute('data-frame',String(frame));await expect(page.locator('#loading')).toBeHidden();}
async function seek(page:Page,frame:number){await page.locator('#seek').evaluate((node:HTMLInputElement,frame)=>{node.value=String(frame);node.dispatchEvent(new Event('change',{bubbles:true}));},frame);await expect(canvas(page)).toHaveAttribute('data-frame',String(frame));}
async function upload(page:Page,bytes:Uint8Array,name='test.papng'){await page.locator('#file').setInputFiles({name,mimeType:'application/octet-stream',buffer:Buffer.from(bytes)});}

test.beforeEach(async({page})=>{await page.goto('/');await expect(canvas(page)).toHaveAttribute('data-frame','0');});

test('all six bundled files load without warnings, errors or browser exceptions',async({page})=>{
  const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  for(const [file,frame] of [['palette-creature.papng',0],['distribution-beats.papng',0],['jump-orbit.papng',0],['hidden-growth.papng',3],['restore-previous.papng',0],['300-frame-spectrum.papng',0]] as const){
    await choose(page,file,frame);expect((await pixels(page)).some((n,i)=>i%4===3&&n>0)).toBe(true);await expect(page.locator('#messages p')).toHaveCount(0);
  }
  await seek(page,299);await expect(page.locator('#frame-label')).toHaveText('299 / 299');expect(errors).toEqual([]);
});

test('H16 controls change actual canvas colors, lock during playback and reset coherently',async({page})=>{
  const original=await pixels(page),hue=page.getByRole('spinbutton',{name:'마스크 0 H16',exact:true});
  await hue.fill('0');await hue.press('Tab');await expect.poll(async()=>JSON.stringify(await pixels(page))).not.toBe(JSON.stringify(original));
  await expect(canvas(page)).toHaveAttribute('data-frame','0');
  await page.locator('#play').click();await expect(page.locator('#play')).toContainText('일시정지');await expect(hue).toBeDisabled();
  await page.locator('#play').click();await expect(hue).toBeEnabled();
  await page.locator('#reset-hues').click();await expect(canvas(page)).toHaveAttribute('data-frame','0');await expect.poll(()=>pixels(page)).toEqual(original);
  // Rapid edits followed immediately by playback must not lose any palette change.
  await page.evaluate(()=>{
    for(const [i,value] of [[0,10000],[1,20000]]){const n=document.querySelectorAll<HTMLInputElement>('.hue-number')[i];n.value=String(value);n.dispatchEvent(new Event('change'));}
    document.querySelector<HTMLButtonElement>('#play')!.click();
  });
  await expect(page.locator('#play')).toContainText('일시정지');await page.locator('#play').click();
  await expect(hue).toHaveValue('10000');await expect(page.getByRole('spinbutton',{name:'마스크 1 H16',exact:true})).toHaveValue('20000');
  await expect(page.locator('.error-message')).toHaveCount(0);
});

test('clip ranges and cache disabled preserve canonical partial-frame images',async({page})=>{
  await page.locator('#clip').selectOption('blink');await expect(canvas(page)).toHaveAttribute('data-frame','2');await expect(page.locator('#seek')).toHaveAttribute('min','2');await expect(page.locator('#seek')).toHaveAttribute('max','4');
  await choose(page,'restore-previous.papng');await seek(page,2);const expected=await pixels(page);
  await page.locator('#budget').selectOption('0');await seek(page,1);await seek(page,2);expect(await pixels(page)).toEqual(expected);
  await expect(page.locator('#cache-summary')).toHaveText('0 B / 0 B');await expect(page.locator('#messages p')).toHaveCount(0);
});

test('hidden setup is composited without ever being presented, and finite playback keeps the last positive frame',async({page})=>{
  await choose(page,'hidden-growth.papng',3);expect((await pixels(page)).filter((n,i)=>i%4===3&&n>0).length).toBeGreaterThan(30);
  const bytes=encodePapng({width:1,height:1,plays:1,frames:[{rgba:Uint8Array.from([255,0,0,255]),num:1,den:100},{rgba:Uint8Array.from([0,0,255,255]),num:0}]});
  await upload(page,bytes);await expect(page.locator('#file-name')).toHaveText('test.papng');await expect(canvas(page)).toHaveAttribute('data-frame','0');await page.locator('#play').click();
  await expect(page.locator('#play-state')).toHaveText('재생 완료');await expect(canvas(page)).toHaveAttribute('data-frame','0');expect(await pixels(page)).toEqual([255,0,0,255]);
});

test('zero-time self-loop yields, reports the condition, stays hidden, and can be paused',async({page})=>{
  const bytes=encodePapng({width:1,height:1,frames:[{rgba:Uint8Array.from([255,0,0,255]),num:0}],controls:[{frame:0,type:3,values:[0]}]});
  await upload(page,bytes,'zero-loop.papng');await expect(page.locator('#file-name')).toHaveText('zero-loop.papng');await expect(canvas(page)).toHaveAttribute('data-frame','-1');
  await expect(page.locator('.warning-message').first()).toContainText('숨김 프레임 순환');await page.locator('#play').click();await expect(page.locator('#play')).toContainText('일시정지');
  await expect(page.locator('#messages')).toContainText('시간이 진행되지 않는 순환');await page.locator('#play').click();await expect(page.locator('#play')).toHaveText('▶ 재생');
  await expect(canvas(page)).toHaveAttribute('data-frame','-1');expect(await pixels(page)).toEqual([0,0,0,0]);
  await choose(page,'palette-creature.papng');await expect(page.locator('#messages p')).toHaveCount(0);
});

test('bad file gives an actionable error and a subsequent renamed PAPNG recovers',async({page})=>{
  await upload(page,Uint8Array.from([1,2,3]),'broken.papng');await expect(page.locator('.error-message')).toContainText('시그니처');
  await upload(page,encodePapng({width:1,height:1,frames:[{rgba:Uint8Array.from([4,5,6,255])}]}),'renamed.png');
  await expect(page.locator('#file-name')).toHaveText('renamed.png');await expect(canvas(page)).toHaveAttribute('data-frame','0');expect(await pixels(page)).toEqual([4,5,6,255]);await expect(page.locator('.error-message')).toHaveCount(0);
});

test('desktop and mobile layouts stay within the viewport and retain functional hue editing',async({page})=>{
  await page.locator('#hints').check();await expect(page.locator('#overlay rect')).toHaveCount(1);await expect(page.locator('#overlay path')).toHaveCount(1);
  await page.screenshot({path:`${artifacts}/desktop.png`,fullPage:true});
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  const hue=page.getByRole('spinbutton',{name:'마스크 0 H16',exact:true});await hue.fill('65535');await hue.press('Tab');await expect(hue).toHaveValue('65535');await expect(page.locator('.error-message')).toHaveCount(0);
  await page.screenshot({path:`${artifacts}/mobile.png`,fullPage:true});
});
