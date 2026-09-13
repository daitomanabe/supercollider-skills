// Optional: install Playwright + Chromium, or set PLAYWRIGHT_MODULE to an existing module.
// Run with an NRT-only supervisor already ready at SCW_TEST_URL.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
async function main() {
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:900}});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const artifacts=path.resolve(process.env.SCW_BROWSER_ARTIFACTS || 'logs');fs.mkdirSync(artifacts,{recursive:true});
  try {
    await page.goto(process.env.SCW_TEST_URL || 'http://127.0.0.1:48761');
    await page.waitForFunction(()=>document.querySelector('#scStatus').textContent.includes('ready'));
    assert.equal(await page.locator('#btnPlay').isDisabled(),true,'Run this QA with SCW_NRT_ONLY=1');
    for(const [id,value] of [['p_tempo','137'],['p_seed','99'],['p_seconds','2'],['p_engineDrive','2.5']])await page.locator('#'+id).fill(value);
    await page.locator('#btnCopy').click();
    for(const [id,value] of [['r_tempoMin','137'],['r_tempoMax','137'],['r_startingSeed','99'],['r_seconds','2'],['r_engineDrive','2.5'],['r_seedMode','fixed']])assert.equal(await page.locator('#'+id).inputValue(),value);
    await page.locator('#btnReset').click();
    assert.equal(await page.locator('#p_seed').inputValue(),'0');assert.equal(await page.locator('#p_engineDrive').inputValue(),'1.2');
    assert.equal(await page.locator('#r_startingSeed').inputValue(),'99','Reset must not mutate render snapshot');
    await page.locator('#r_count').fill('1');await page.locator('#r_seconds').fill('1');
    await page.locator('#btnBatchStart').click();
    await page.waitForFunction(()=>document.querySelector('#progressText').textContent.includes('1 WAV/JSON pairs, 0 failures'));
    await page.reload();await page.waitForFunction(()=>document.querySelector('#progressText').textContent.includes('1 WAV/JSON pairs, 0 failures'));
    await page.evaluate(()=>ws.close());
    await page.waitForFunction(()=>document.querySelector('#wsStatus').textContent==='WS: disconnected');
    await page.waitForFunction(()=>document.querySelector('#wsStatus').textContent==='WS: connected'&&!document.querySelector('#btnBatchStart').disabled);
    await page.screenshot({path:path.join(artifacts,'browser-desktop.png'),fullPage:true});
    await page.setViewportSize({width:390,height:844});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    await page.screenshot({path:path.join(artifacts,'browser-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    const report={passed:true,viewports:[[1280,900],[390,844]],pageErrors:errors,copy:true,resetIsolation:true,batchRender:true,reloadState:true,reconnect:true,noHorizontalOverflow:true,audiblePreviewTested:false};
    fs.writeFileSync(path.join(artifacts,'browser-result.json'),JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report,null,2));
  } finally {await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1});
