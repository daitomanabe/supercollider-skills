const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {normalizeParams, presetName, ports} = require('../scripts/contract');
test('reject malformed, unbounded and unknown transport parameters', () => {
  for (const params of [null, [], {tempo:0}, {tempo:Infinity}, {tempo:128.5}, {tempo:'128'}, {outputDir:'/tmp'}, {constructor:3}]) {
    assert.throws(() => normalizeParams('/preview/play', params));
  }
  assert.throws(() => normalizeParams('/render/start', {tempoMin:140,tempoMax:120}));
  assert.throws(() => normalizeParams('/render/start', {seedMode:'arbitrary'}));
  assert.equal(normalizeParams('/preview/play', {tempo:130}).tempo,130);
  assert.equal(normalizeParams('/preview/play', {}).seconds,8);
});
test('preset names cannot escape their directory and ports are strict', () => {
  for (const name of ['../escape','a/b','..','', 'a'.repeat(65)]) assert.throws(() => presetName(name));
  assert.equal(presetName('tone_1-test'),'tone_1-test');
  for (const value of ['1','3x','70000','48762']) assert.throws(() => ports({SCW_HTTP_PORT:value}));
  assert.equal(ports({SCW_HTTP_PORT:'49871'}).httpPort,49871);
});
test('generation works in a file-only clone and is reproducible', () => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'scw-generate-'));
  try {
    fs.mkdirSync(path.join(dir,'scripts'));
    for(const file of ['params.json','config.json','scripts/contract.js','scripts/generate-sc.js']) fs.copyFileSync(path.join(__dirname,'..',file),path.join(dir,file));
    const run=() => {const result=spawnSync(process.execPath,['scripts/generate-sc.js'],{cwd:dir,encoding:'utf8'});assert.equal(result.status,0,result.stderr);return fs.readFileSync(path.join(dir,'sc/generated/osc_handlers.scd'),'utf8');};
    const first=run(); assert.equal(run(),first);
    assert.match(first,/~runBatch/); assert.match(first,/msg.size == 12/);
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
