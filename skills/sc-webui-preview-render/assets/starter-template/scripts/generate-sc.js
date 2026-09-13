#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const {schema} = require('./contract');
const outFile = path.join(__dirname, '../sc/generated/osc_handlers.scd');
function dictionary(address) {
  return `IdentityDictionary[${schema.messages[address].params.map((key, index) => {
    const type = {int:'asInteger', float:'asFloat', string:'asString'}[schema.params[key].type];
    return `\\${key} -> msg[${index + 1}].${type}`;
  }).join(', ')}]`;
}
function handler(name, address, body) {
  const def = schema.messages[address];
  const size = 1 + (def?.params.length || 0) + (def?.suffix?.length || 0);
  return `OSCdef(\\${name}, { |msg, time, addr|\n  if((addr.ip == "127.0.0.1") and: { msg.size == ${size} }, { ${body} });\n}, '${address}');\n`;
}
let sc = '// Generated from params.json. Run npm run generate.\n';
sc += handler('previewPlay', '/preview/play', `~previewPlay.(${dictionary('/preview/play')})`);
sc += handler('previewSetParams', '/preview/setParams', `~previewSetParams.(${dictionary('/preview/setParams')})`);
sc += handler('previewStop', '/preview/stop', '~previewStop.()');
const n = schema.messages['/render/start'].params.length;
sc += handler('renderStart', '/render/start', `~runBatch.(${dictionary('/render/start')}, msg[${n + 1}].asString, msg[${n + 2}].asString)`);
sc += handler('renderStop', '/render/stop', '~batchStop = true');
sc += handler('statusGet', '/status/get', '~sendStatus.()');
fs.mkdirSync(path.dirname(outFile), {recursive:true});
fs.writeFileSync(outFile, sc);
console.log('Generated sc/generated/osc_handlers.scd');
