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

test('all nine bundled files load without warnings, errors or browser exceptions',async({page})=>{
  const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  for(const [file,frame] of [['palette-creature.papng',0],['distribution-beats.papng',0],['jump-orbit.papng',0],['hidden-growth.papng',3],['restore-previous.papng',0],['alpha-ribbons.papng',0],['socket-buddy.papng',0],['socket-wand.papng',0],['300-frame-spectrum.papng',0]] as const){
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

test('socket attachment draws the child pivot at the selected pose and preserves sparse rotations on backward seek',async({page})=>{
  await choose(page,'socket-buddy.papng');await expect(page.locator('#attachment-state')).toContainText('pivot (5, 17)');
  await expect(page.locator('#play')).toBeEnabled();
  await expect(page.locator('#socket-pose')).toHaveText('x 29 · y 27 · r 0° · 정의 프레임 0');
  // Child (4,3), relative to pivot (5,17), lands at parent (28,13).
  const pixelAt=async(x:number,y:number)=>canvas(page).evaluate((c:HTMLCanvasElement,[x,y])=>Array.from(c.getContext('2d')!.getImageData(x,y,1,1).data),[x,y]);
  await expect.poll(()=>pixelAt(28,13)).toEqual([255,195,70,255]);
  await page.locator('#show-attachment').uncheck();expect(await pixelAt(28,13)).toEqual([0,0,0,0]);await page.locator('#show-attachment').check();
  await seek(page,3);await expect(page.locator('#socket-pose')).toHaveText('x 30 · y 25 · r -35° · 정의 프레임 2');
  await expect(page.locator('#overlay [data-socket="0"]')).toHaveAttribute('transform','translate(30 25) rotate(-35)');
  const rotated=await pixels(page);await seek(page,5);await expect(page.locator('#socket-pose')).toContainText('r 0° · 정의 프레임 4');
  await seek(page,3);await expect.poll(()=>pixels(page)).toEqual(rotated);
  await page.locator('#socket-select').selectOption('1');await expect(page.locator('#socket-pose')).toHaveText('x 21 · y 11 · r 12.5° · 정의 프레임 2');
  await page.locator('#clip').selectOption('raised');await expect(page.locator('#socket-pose')).toContainText('정의 프레임 2');
  await page.locator('#show-sockets').uncheck();await expect(page.locator('#overlay g')).toHaveCount(0);
  await page.locator('#show-sockets').check();await page.locator('#socket-select').selectOption('0');
  await page.screenshot({path:`${artifacts}/sockets-desktop.png`,fullPage:true});
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:`${artifacts}/sockets-mobile.png`,fullPage:true});
});

test('accessory animates on its own timeline and pause, restart, hue edits and resource changes control both players',async({page})=>{
  await choose(page,'socket-buddy.papng');await expect(page.locator('#play')).toBeEnabled();
  await page.locator('#play').click();
  await expect.poll(()=>page.evaluate(()=>document.querySelector<HTMLCanvasElement>('#canvas')!.dataset.frame==='0' && document.querySelector<HTMLElement>('#attachment-state')!.dataset.frame!=='0'),{intervals:[15]}).toBe(true);
  await page.locator('#play').click();await expect(page.locator('#play-state')).toHaveText('일시정지');
  const before=await page.locator('#attachment-state').getAttribute('data-frame');
  await page.waitForTimeout(280);await expect(page.locator('#attachment-state')).toHaveAttribute('data-frame',before!);
  await page.locator('#restart').click();await expect(canvas(page)).toHaveAttribute('data-frame','0');await expect(page.locator('#attachment-state')).toHaveAttribute('data-frame','0');
  await seek(page,3);const hue=page.getByRole('spinbutton',{name:'마스크 0 변화량',exact:true});await hue.fill('40');await hue.press('Tab');
  await expect(canvas(page)).toHaveAttribute('data-frame','0');await expect(page.locator('#socket-pose')).toHaveAttribute('data-source','0');await expect(page.locator('#attachment-state')).toHaveAttribute('data-frame','0');
  await page.locator('#play').click();await choose(page,'alpha-ribbons.papng');await expect(page.locator('#socket-panel')).toBeHidden();
  const alone=await pixels(page);await page.waitForTimeout(200);expect(await pixels(page)).toEqual(alone);
  await expect(page.locator('#messages p')).toHaveCount(0);
});

test('a missing accessory does not stop its parent, and optional sockets never load file paths from metadata',async({page})=>{
  await page.route('**/samples/socket-wand.papng',route=>route.fulfill({status:404,body:''}));
  await choose(page,'socket-buddy.papng');await expect(page.locator('#messages')).toContainText('부속 연결 실패');
  await expect(page.locator('#play')).toBeEnabled();await page.locator('#play').click();await expect(canvas(page)).not.toHaveAttribute('data-frame','0');
  const data=encodePapng({width:1,height:1,frames:[{rgba:Uint8Array.of(255,0,0,255)}],metadata:{schema_version:1,sockets:{definitions:[{name:'<script>socket</script>',file:'socket-wand.papng'}],frames:[{frame_index:0,positions:[[0,0]]}]}}});
  await upload(page,data);await expect(page.locator('#file-name')).toHaveText('test.papng');
  await expect(page.locator('#socket-select option')).toHaveText('0 · <script>socket</script>');await expect(page.locator('#show-attachment')).toBeDisabled();await expect(page.locator('#messages p')).toHaveCount(0);
});

test('hidden terminal visits keep the displayed socket, stop the accessory, and replay restarts both',async({page})=>{
  const data=encodePapng({width:48,height:40,plays:1,frames:[{rgba:new Uint8Array(48*40*4),num:3,den:10},{rgba:new Uint8Array(48*40*4),num:0}],metadata:{schema_version:1,sockets:{definitions:[{name:'right_hand'}],frames:[{frame_index:0,positions:[[29,27]]},{frame_index:1,positions:[[1,1,90]]}]}}});
  await page.route('**/samples/socket-buddy.papng',route=>route.fulfill({body:Buffer.from(data)}));
  await choose(page,'socket-buddy.papng');await expect(page.locator('#play')).toBeEnabled();await page.locator('#play').click();
  await expect(page.locator('#play-state')).toHaveText('재생 완료');await expect(canvas(page)).toHaveAttribute('data-frame','0');await expect(page.locator('#socket-pose')).toHaveAttribute('data-source','0');
  const frame=await page.locator('#attachment-state').getAttribute('data-frame');await page.waitForTimeout(170);await expect(page.locator('#attachment-state')).toHaveAttribute('data-frame',frame!);
  await page.locator('#play').click();await expect(page.locator('#attachment-state')).toHaveAttribute('data-frame','0');
});

test('changing samples cancels an accessory that is still downloading',async({page})=>{
  let release!:()=>void;const released=new Promise<void>(resolve=>release=resolve);
  await page.route('**/samples/socket-wand.papng',async route=>{await released;await route.continue().catch(()=>{});});
  await choose(page,'socket-buddy.papng');await expect(page.locator('#attachment-state')).toHaveText('부속 파일 준비 중…');await expect(page.locator('#play')).toBeDisabled();
  await choose(page,'palette-creature.papng');release();await expect(page.locator('#play')).toBeEnabled();await expect(page.locator('#socket-panel')).toBeHidden();
  await page.waitForTimeout(200);await expect(page.locator('#messages p')).toHaveCount(0);await expect(page.locator('#file-name')).toHaveText('palette-creature.papng');
});


test('JSON5 developer notes are readable in compressed and uncompressed samples without affecting playback',async({page})=>{
  for(const file of ['socket-buddy.papng','restore-previous.papng']) {
    await choose(page,file);
    await expect(page.locator('#metadata-panel')).toBeVisible();
    await page.locator('#metadata-panel').evaluate((node:HTMLDetailsElement)=>{node.open=true;});
    await expect(page.locator('#metadata-source')).toContainText('// PAPNG 개발자 참고:');
    await expect(page.locator('#metadata-source')).toContainText('/* PAPNG.Metadata 스키마 */');
    await expect(page.locator('#metadata-source')).toContainText('developer_notes:');
    await expect(page.locator('#metadata-note')).toContainText('읽기 전용');
    await expect(page.locator('#messages p')).toHaveCount(0);
  }
  await choose(page,'socket-buddy.papng');
  const source=await page.request.get('/samples/socket-buddy-metadata.json5');
  expect(source.ok()).toBe(true);
  expect(await page.locator('#metadata-source').textContent()).toBe(await source.text());
  await page.setViewportSize({width:390,height:844});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:`${artifacts}/json5-mobile.png`,fullPage:true});
});

test('JSON5 source is displayed literally and clears on missing or invalid metadata',async({page})=>{
  const text=`// <img src="bad" onerror="globalThis.metadataExecuted=true">
{schema_version:1,developer_notes:'<script>globalThis.metadataExecuted=true</script>',}`;
  const frame={rgba:Uint8Array.of(12,34,56,255)};
  await upload(page,encodePapng({width:1,height:1,frames:[frame],metadataText:text}),'notes.papng');
  await expect(page.locator('#file-name')).toHaveText('notes.papng');
  expect(await page.locator('#metadata-source').textContent()).toBe(text);
  await expect(page.locator('#metadata-source img, #metadata-source script')).toHaveCount(0);
  expect(await page.evaluate(()=>Reflect.get(globalThis,'metadataExecuted'))).toBeUndefined();
  expect(await pixels(page)).toEqual([12,34,56,255]);
  for(const [name,metadataText] of [['none.papng',undefined],['duplicate.papng',"{schema_version:1,'schema_version':1}"]] as const) {
    await upload(page,encodePapng({width:1,height:1,frames:[frame],metadataText}),name);
    await expect(page.locator('#file-name')).toHaveText(name);
    await expect(page.locator('#metadata-panel')).toBeHidden();
    await expect(page.locator('#metadata-source')).toHaveText('');
    expect(await pixels(page)).toEqual([12,34,56,255]);
    if(metadataText)await expect(page.locator('#messages')).toContainText('중복 JSON5');
  }
});

test('long JSON5 notes have a bounded preview while metadata beyond the preview still works',async({page})=>{
  const text=`{schema_version:1,/*${'x'.repeat(70000)}*/sockets:{definitions:[{name:'tail_socket'}],frames:[{frame_index:0,positions:[[0,0]]}]}}`;
  await upload(page,encodePapng({width:1,height:1,frames:[{rgba:Uint8Array.of(1,2,3,255)}],metadataText:text}),'long-notes.papng');
  await expect(page.locator('#file-name')).toHaveText('long-notes.papng');
  await page.locator('#metadata-panel').evaluate((node:HTMLDetailsElement)=>{node.open=true;});
  expect(await page.locator('#metadata-source').textContent()).toBe(text.slice(0,65536));
  await expect(page.locator('#metadata-note')).toContainText('65,536자');
  await expect(page.locator('#socket-select option')).toHaveText('0 · tail_socket');
  await expect(page.locator('#messages p')).toHaveCount(0);
});
