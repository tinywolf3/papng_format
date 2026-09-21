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

test('all seven bundled files load without warnings, errors or browser exceptions',async({page})=>{
  const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  for(const [file,frame] of [['palette-creature.papng',0],['distribution-beats.papng',0],['jump-orbit.papng',0],['hidden-growth.papng',3],['restore-previous.papng',0],['alpha-ribbons.papng',0],['300-frame-spectrum.papng',0]] as const){
    await choose(page,file,frame);expect((await pixels(page)).some((n,i)=>i%4===3&&n>0)).toBe(true);await expect(page.locator('#messages p')).toHaveCount(0);
  }
  await seek(page,299);await expect(page.locator('#frame-label')).toHaveText('299 / 299');expect(errors).toEqual([]);
});

test('Hue-offset controls change actual canvas colors, lock during playback and reset coherently',async({page})=>{
  const original=await pixels(page),hue=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true});
  const target=page.getByRole('spinbutton',{name:'마스크 0 H',exact:true});
  await expect(target).toHaveValue('148.4');expect(await target.evaluate((node:HTMLInputElement)=>node.checkValidity())).toBe(true);
  await hue.fill('120');await hue.press('Tab');await expect.poll(async()=>JSON.stringify(await pixels(page))).not.toBe(JSON.stringify(original));
  await expect(canvas(page)).toHaveAttribute('data-frame','0');
  await page.locator('#play').click();await expect(page.locator('#play')).toContainText('일시정지');await expect(hue).toBeDisabled();
  await page.locator('#play').click();await expect(hue).toBeEnabled();
  await page.locator('#reset-hues').click();await expect(canvas(page)).toHaveAttribute('data-frame','0');await expect.poll(()=>pixels(page)).toEqual(original);
  // Rapid edits followed immediately by playback must not lose any palette change.
  await page.evaluate(()=>{
    for(const [i,value] of [[0,90],[1,-60]]){const n=document.querySelectorAll<HTMLInputElement>('.hue-number')[i];n.value=String(value);n.dispatchEvent(new Event('change'));}
    document.querySelector<HTMLButtonElement>('#play')!.click();
  });
  await expect(page.locator('#play')).toContainText('일시정지');await page.locator('#play').click();
  await expect(hue).toHaveValue('90');await expect(page.getByRole('spinbutton',{name:'마스크 1 변화량',exact:true})).toHaveValue('-60');
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
  const hue=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true});await hue.fill('-180');await hue.press('Tab');await expect(hue).toHaveValue('-180');await expect(page.locator('.error-message')).toHaveCount(0);
  await page.screenshot({path:`${artifacts}/mobile.png`,fullPage:true});
});


test('shared masks keep distinct original alphas while editing hue',async({page})=>{
  await choose(page,'alpha-ribbons.papng');
  await expect(page.locator('#mask-sharing')).toHaveText('4개 프레임 → 1개 마스크 배열 공유');
  const before=await pixels(page),alphas=before.filter((_,i)=>i%4===3);
  expect(new Set(alphas)).toEqual(new Set([0,1,32,64,128,192,255]));
  const hue=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true});await hue.fill('180');await hue.press('Tab');
  await expect.poll(async()=>JSON.stringify(await pixels(page))).not.toBe(JSON.stringify(before));
  expect((await pixels(page)).filter((_,i)=>i%4===3)).toEqual(alphas);
  await page.locator('#reset-hues').click();await expect.poll(()=>pixels(page)).toEqual(before);
});

test('32768 masks are paginated and the highest index is editable without changing alpha',async({page})=>{
  const bytes=encodePapng({width:1,height:1,maskCount:32768,frames:[{rgba:Uint8Array.from([255,0,0,128]),mask:Uint16Array.from([0xffff])}]});
  await upload(page,bytes,'max-masks.papng');await expect(page.locator('#mask-count')).toHaveText('32768');await expect(page.locator('.mask-card')).toHaveCount(16);
  await page.getByRole('spinbutton',{name:'마스크 번호로 이동'}).fill('32767');await page.getByRole('spinbutton',{name:'마스크 번호로 이동'}).press('Tab');
  const hue=page.getByRole('spinbutton',{name:'마스크 32767 변화량',exact:true});await hue.fill('180');await hue.press('Tab');
  await expect.poll(()=>pixels(page)).toEqual([0,255,255,128]);await expect(page.locator('.error-message')).toHaveCount(0);
});


test('mean H defaults to original RGB and H edits synchronize offsets without changing the reference',async({page})=>{
  const bytes=encodePapng({width:1,height:1,maskCount:2,frames:[
    {rgba:Uint8Array.from([255,0,0,255]),mask:Uint16Array.from([0x8000]),num:0},
    {rgba:Uint8Array.from([0,0,255,255]),mask:Uint16Array.from([0x8000]),num:1,den:1},
  ],metadata:{schema_version:1,mask_groups:[{id:'all',name:'상위 그룹',palette_indices:[0,1]},{id:'named',name:'색상 실험 <원본>',palette_indices:[0]}]}});
  await upload(page,bytes,'average-hue.papng');await expect(page.locator('#file-name')).toHaveText('average-hue.papng');await expect(canvas(page)).toHaveAttribute('data-frame','1');
  const card=page.locator('.mask-card').first(),target=page.getByRole('spinbutton',{name:'마스크 0 H',exact:true}),offset=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true});
  await expect(card.locator('.mask-name')).toHaveText('색상 실험 <원본>');await expect(card.locator('.mask-group')).toHaveText('상위 그룹');
  await expect(card.locator('.average-hue')).toHaveText('300.0°');await expect(target).toHaveValue('300');await expect(offset).toHaveValue('0');
  const original=await pixels(page);expect(original).toEqual([0,0,255,255]);
  await target.fill('0');await target.press('Tab');await expect(offset).toHaveValue('60');await expect.poll(()=>pixels(page)).toEqual([255,0,255,255]);
  await expect(card.locator('.average-hue')).toHaveText('300.0°');
  await offset.fill('-120');await offset.press('Tab');await expect(target).toHaveValue('180');await expect.poll(()=>pixels(page)).toEqual([0,255,0,255]);
  await page.locator('#play').click();await expect(target).toBeDisabled();await expect(offset).toBeDisabled();await page.locator('#play').click();await expect(target).toBeEnabled();
  await card.locator('.mask-reset').click();await expect(target).toHaveValue('300');await expect(offset).toHaveValue('0');await expect.poll(()=>pixels(page)).toEqual(original);
  await choose(page,'palette-creature.papng');await expect(page.locator('.mask-name').first()).toHaveText('몸체');await expect(page.locator('.mask-group').first()).toHaveText('몸체와 장식');
});

test('undefined reference hues stay disabled after rendering while offset editing remains available',async({page})=>{
  const bytes=encodePapng({width:2,height:1,maskCount:3,frames:[{rgba:Uint8Array.from([80,80,80,255,255,0,0,0]),mask:Uint16Array.from([0x8000,0x8001])}]});
  await upload(page,bytes,'no-hue.papng');await expect(page.locator('#file-name')).toHaveText('no-hue.papng');await expect(canvas(page)).toHaveAttribute('data-frame','0');
  await expect(page.locator('.average-hue')).toHaveText(['무채색 · H 없음','완전 투명 · H 없음','대상 픽셀 없음']);
  for(let i=0;i<3;i++)await expect(page.getByRole('spinbutton',{name:`마스크 ${i} H`,exact:true})).toBeDisabled();
  const offset=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true}),original=await pixels(page);
  await offset.fill('120');await offset.press('Tab');await expect(page.locator('#loading')).toBeHidden();expect(await pixels(page)).toEqual(original);
  await expect(page.getByRole('spinbutton',{name:'마스크 0 H',exact:true})).toBeDisabled();await expect(offset).toBeEnabled();
  await expect(page.locator('.error-message')).toHaveCount(0);
});
