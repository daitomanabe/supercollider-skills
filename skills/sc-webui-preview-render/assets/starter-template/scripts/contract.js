const schema = require('../params.json');
const defaults = require('../config.json');
const ENV_PORTS = {httpPort:'SCW_HTTP_PORT', feedbackPort:'SCW_FEEDBACK_PORT', languagePort:'SCW_LANGUAGE_PORT', audioPort:'SCW_AUDIO_PORT'};
function ports(env = process.env) {
  const out = {};
  for (const [key, name] of Object.entries(ENV_PORTS)) {
    const value = env[name] === undefined ? defaults[key] : Number(env[name]);
    if (!Number.isInteger(value) || value < 1024 || value > 65535) throw Error(`${name} must be an integer port in 1024..65535`);
    out[key] = value;
  }
  if (new Set(Object.values(out)).size !== 4) throw Error('All four service ports must differ');
  return out;
}
function validateSchema() {
  for (const [key, def] of Object.entries(schema.params)) {
    if (!/^[a-z][A-Za-z0-9]*$/.test(key)) throw Error(`Unsafe SC parameter identifier: ${key}`);
    if (!['int', 'float', 'string'].includes(def.type)) throw Error(`Unsupported type: ${key}`);
    validateValue(key, def.default);
  }
  for (const [address, def] of Object.entries(schema.messages)) {
    if (!/^\/[a-zA-Z/]+$/.test(address)) throw Error(`Unsafe OSC address: ${address}`);
    for (const key of def.params) if (!schema.params[key]) throw Error(`Unknown parameter: ${key}`);
    if (new Set(def.params).size !== def.params.length) throw Error(`Repeated parameter: ${address}`);
  }
}
function validateValue(key, value) {
  const def = schema.params[key];
  if (!def) throw Error(`Unknown parameter: ${key}`);
  if (def.type === 'string') {
    if (typeof value !== 'string' || !def.options?.some(([, option]) => option === value)) throw Error(`Invalid option: ${key}`);
  } else {
    if (typeof value !== 'number' || !Number.isFinite(value) || (def.type === 'int' && !Number.isInteger(value))) throw Error(`Invalid ${def.type}: ${key}`);
    if (value < def.min || value > def.max) throw Error(`${key} must be in ${def.min}..${def.max}`);
  }
  return value;
}
function normalizeParams(address, input = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw Error('params must be an object');
  const def = schema.messages[address];
  if (!def) throw Error('Unknown action');
  for (const key of Object.keys(input)) if (!def.params.includes(key)) throw Error(`Unexpected parameter: ${key}`);
  const result = {};
  for (const key of def.params) result[key] = validateValue(key, input[key] === undefined ? schema.params[key].default : input[key]);
  if (result.tempoMin > result.tempoMax) throw Error('tempoMin must not exceed tempoMax');
  return result;
}
function presetName(name) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(name)) throw Error('Preset name must contain 1..64 letters, digits, underscores or hyphens');
  return name;
}
validateSchema();
module.exports = {schema, ports, normalizeParams, presetName, validateSchema};
