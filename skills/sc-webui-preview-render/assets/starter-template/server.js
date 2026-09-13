const express = require('express');
const http = require('node:http');
const {WebSocketServer} = require('ws');
const osc = require('node-osc');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const {schema, ports, normalizeParams, presetName} = require('./scripts/contract');
const config = ports();
const root = __dirname;
const dataRoot = path.resolve(process.env.SCW_DATA_DIR || root);
if (/[\r\n"$`\\]/.test(dataRoot)) throw Error('SCW_DATA_DIR contains shell metacharacters unsafe for Score.recordNRT');
for (const dir of ['output', 'logs', 'presets']) fs.mkdirSync(path.join(dataRoot, dir), {recursive:true});
const state = {status:'connecting', audio:'stopped', previewRunning:false, renderRunning:false, batch:null};
let lastSeen = 0;
let activeBatch = null;
let closing = false;
const hosts = new Set([`localhost:${config.httpPort}`, `127.0.0.1:${config.httpPort}`]);
const origins = new Set([...hosts].map(host => `http://${host}`));
function allowedRequest(req) {
  return hosts.has(req.headers.host) && (!req.headers.origin || origins.has(req.headers.origin));
}
const app = express();
app.use((req, res, next) => {
  if (!allowedRequest(req)) return res.status(403).json({error:'Host or Origin is not allowed'});
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Cache-Control', 'no-store');
  next();
});
app.use(express.json({limit:'16kb'}));
app.use(express.static(path.join(root, 'public')));
app.use('/output', express.static(path.join(dataRoot, 'output'), {dotfiles:'deny'}));
app.get('/params.json', (req, res) => res.json(schema));
app.get('/api/status', (req, res) => res.json(state));
const presetsDir = path.join(dataRoot, 'presets');
app.get('/api/presets', (req, res) => res.json(fs.readdirSync(presetsDir).filter(file => /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}\.json$/.test(file)).map(file => file.slice(0,-5))));
app.get('/api/presets/:name', (req, res, next) => {
  try {
    const full = path.join(presetsDir, `${presetName(req.params.name)}.json`);
    if (!fs.existsSync(full)) return res.status(404).json({error:'Preset not found'});
    if (!fs.lstatSync(full).isFile()) throw Error('Preset must be a regular file');
    res.json(JSON.parse(fs.readFileSync(full, 'utf8')));
  } catch (error) { next(error); }
});
app.post('/api/presets/:name', (req, res, next) => {
  try {
    const name = presetName(req.params.name);
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) throw Error('Preset must be an object');
    if (Object.keys(req.body).some(key => !['preview', 'render'].includes(key))) throw Error('Preset keys are preview and render');
    const data = {preview:normalizeParams('/preview/play', req.body.preview), render:normalizeParams('/render/start', req.body.render)};
    const full = path.join(presetsDir, `${name}.json`);
    const temporary = `${full}.${crypto.randomUUID()}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(data, null, 2) + '\n', {flag:'wx'});
    fs.renameSync(temporary, full);
    res.json({ok:true, name});
  } catch (error) { next(error); }
});
app.use((error, req, res, next) => res.status(400).json({error:error.message}));
const server = http.createServer(app);
const wss = new WebSocketServer({noServer:true, maxPayload:16384});
server.on('upgrade', (req, socket, head) => {
  if (!allowedRequest(req) || req.url !== '/') { socket.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return; }
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws));
});
const scClient = new osc.Client('127.0.0.1', config.languagePort);
const oscServer = new osc.Server(config.feedbackPort, '127.0.0.1');
function send(ws, type, data) {
  if (ws.readyState === 1) ws.send(JSON.stringify({type, data}));
}
function broadcast(type, data) { for (const ws of wss.clients) send(ws, type, data); }
function oscSend(address, params = {}, suffix = []) {
  const args = schema.messages[address]?.params.map(key => params[key]) || [];
  scClient.send(address, ...args, ...suffix, error => { if (error) broadcast('error', {message:error.message}); });
}
function updateState() { broadcast('state', {...state}); }
function failBatch(message) {
  broadcast('renderError', {job:0, message});
  if (activeBatch) activeBatch.errors.push(message);
}
oscServer.on('message', (message, rinfo) => {
  if (rinfo?.address && rinfo.address !== '127.0.0.1') return;
  const [address, ...args] = message;
  if (address === '/sc/status') {
    lastSeen = Date.now();
    Object.assign(state, {status:args[0], audio:args[1], previewRunning:!!args[2], renderRunning:!!args[3] || !!activeBatch});
    updateState();
  } else if (address === '/log') broadcast('log', {message:String(args[0]).slice(0,4096)});
  else if (address === '/preview/started' || address === '/preview/stopped') {
    state.previewRunning = address.endsWith('started'); updateState();
  } else if (address === '/preview/error') {
    state.previewRunning = false; broadcast('error', {message:String(args[0])}); updateState();
  } else if (address === '/render/progress' && activeBatch && args[0] === activeBatch.id) {
    state.batch = {id:activeBatch.id, current:args[1], total:args[2], file:path.basename(args[3])};
    broadcast('renderProgress', state.batch); updateState();
  } else if (address === '/render/jobDone' && activeBatch && args[0] === activeBatch.id) {
    try {
      const [id, index, outputPath, tempo, seed, take, seconds, engineDrive, fxMix] = args;
      if (path.dirname(outputPath) !== activeBatch.dir || path.extname(outputPath) !== '.wav') throw Error('Unexpected render output path');
      const stat = fs.lstatSync(outputPath);
      if (!stat.isFile() || stat.size < 44) throw Error('Rendered WAV is missing or empty');
      const metadata = {version:'1.0.0', renderMode:'NRT', sampleRate:44100, tailSeconds:1, parameters:{tempo,seed,take,seconds,engineDrive,fxMix}, batchParameters:activeBatch.params};
      fs.writeFileSync(outputPath.slice(0,-4) + '.json', JSON.stringify(metadata, null, 2) + '\n', {flag:'wx'});
      activeBatch.completed.add(index);
      broadcast('renderJobDone', {job:index, file:`/output/${id}/${path.basename(outputPath)}`});
    } catch (error) { failBatch(error.message); }
  } else if (address === '/render/error' && activeBatch && args[0] === activeBatch.id) {
    activeBatch.errors.push(String(args[2]));
    broadcast('renderError', {job:args[1], message:String(args[2])});
  } else if (address === '/render/done' && activeBatch && args[0] === activeBatch.id) {
    const [, rendered, failures, stopped] = args;
    if (activeBatch.completed.size !== rendered) failBatch('Render completion count does not match verified WAV/JSON outputs');
    if (!stopped && rendered + failures !== activeBatch.params.count) failBatch('Batch ended before every requested take completed or failed');
    const result = {id:activeBatch.id, completed:activeBatch.completed.size, failures:Math.max(failures, activeBatch.errors.length), stopped:!!stopped, manifestWritten:true};
    result.message = `${result.stopped ? 'Stopped' : 'Complete'}: ${result.completed} WAV/JSON pairs, ${result.failures} failures`;
    try {
      fs.writeFileSync(path.join(activeBatch.dir, 'batch.json'), JSON.stringify({...result, parameters:activeBatch.params, errors:activeBatch.errors}, null, 2) + '\n');
    } catch (error) {
      failBatch(`Batch manifest could not be written: ${error.message}`);
      result.manifestWritten = false; result.failures = Math.max(1, result.failures);
      result.message = `Incomplete: ${result.completed} WAV/JSON pairs; batch manifest write failed`;
    }
    activeBatch = null; state.renderRunning = false; state.batch = result;
    broadcast('renderDone', result); updateState();
  }
});
oscServer.on('error', error => { console.error(error.message); shutdown(1); });
wss.on('connection', ws => {
  send(ws, 'state', state);
  ws.on('error', error => console.error(error.message));
  ws.on('message', raw => {
    try {
      const message = JSON.parse(raw);
      if (!message || typeof message !== 'object' || Array.isArray(message)) throw Error('Message must be an object');
      const {action, params = {}} = message;
      if (!['preview/play','preview/stop','preview/setParams','render/start','render/stop'].includes(action)) throw Error('Unknown action');
      if (state.status !== 'ready') throw Error('SuperCollider is not ready');
      if (['preview/stop','render/stop'].includes(action)) {
        oscSend(`/${action}`); return;
      }
      const normalized = normalizeParams(`/${action}`, params);
      if (action === 'render/start') {
        if (activeBatch || state.renderRunning) throw Error('A batch is already running');
        const id = `${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID().slice(0,8)}`;
        const dir = path.join(dataRoot, 'output', id);
        fs.mkdirSync(dir);
        activeBatch = {id, dir, params:normalized, completed:new Set(), errors:[]};
        state.renderRunning = true; state.batch = {id, current:0, total:normalized.count}; updateState();
        oscSend('/render/start', normalized, [dir, id]);
      } else oscSend(`/${action}`, normalized);
    } catch (error) { send(ws, 'error', {message:error.message}); }
  });
});
const poll = setInterval(() => {
  oscSend('/status/get');
  if (lastSeen && Date.now() - lastSeen > 4000 && state.status !== 'disconnected') {
    state.status = 'disconnected'; state.previewRunning = false; updateState();
  }
}, 1000);
function shutdown(code = 0) {
  if (closing) return;
  closing = true; clearInterval(poll);
  for (const ws of wss.clients) ws.terminate();
  wss.close(); server.close(); oscServer.close(); scClient.close();
  setTimeout(() => process.exit(code), 50);
}
process.on('SIGINT', () => shutdown());
process.on('SIGTERM', () => shutdown());
server.on('error', error => { console.error(error.message); shutdown(1); });
server.listen(config.httpPort, '127.0.0.1', () => console.log(`SC WebUI: http://127.0.0.1:${config.httpPort}`));
