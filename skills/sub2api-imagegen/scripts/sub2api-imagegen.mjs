#!/usr/bin/env node
// Standalone, single-request Sub2API client. Never log raw exceptions or provider data.
import { constants, lstatSync, mkdirSync, openSync, closeSync, readFileSync,
  writeFileSync, unlinkSync, accessSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { inspectGeneratedImage } from './image.mjs';

const CONFIG_DIR = '.sub2api-imagegen';
const TEMPLATE = '# Local plaintext credentials: keep private; never commit or paste into chat.\nSUB2API_BASE_URL=\nSUB2API_API_KEY=\n';
const MAX_IMAGE = 50 * 1024 * 1024;
const MAX_BODY = 4 * Math.ceil(MAX_IMAGE / 3) + 65536;
const SIZES = { auto: 'auto', '1:1': '1024x1024', '9:16': '864x1536' };

class Failure extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function fail(code, message) { throw new Failure(code, message); }
function configPath() { return join(homedir(), CONFIG_DIR, '.env'); }

// Intentionally a small data parser, never shell evaluation or environment expansion.
export function parseConfig(text) {
  if (Buffer.byteLength(text) > 65536) fail('config_invalid', 'Configuration file is too large.');
  const values = {};
  for (const raw of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const match = /^(SUB2API_BASE_URL|SUB2API_API_KEY)\s*=\s*(.*)$/.exec(line);
    if (!match || Object.hasOwn(values, match[1]))
      fail('config_invalid', 'Use one assignment per variable in the configuration file.');
    let value = match[2].trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      const end = value.indexOf(quote, 1);
      if (end < 0 || !/^(?:\s*#.*)?$/.test(value.slice(end + 1)))
        fail('config_invalid', 'Configuration quotes must close on the same line.');
      value = value.slice(1, end);
    } else value = value.replace(/\s+#.*$/, '').trim();
    if (/[\x00-\x1f\x7f]/.test(value)) fail('config_invalid', 'Configuration contains control characters.');
    values[match[1]] = value.trim();
  }
  return values;
}

function readConfig() {
  try {
    // Refuse symlinks so setup/status cannot follow an unexpected credential file.
    if (!lstatSync(join(homedir(), CONFIG_DIR)).isDirectory() || !lstatSync(configPath()).isFile())
      fail('config_invalid', 'Configuration must be a regular local file in its dedicated directory.');
    const fd = openSync(configPath(), constants.O_RDONLY | constants.O_NOFOLLOW);
    try { return parseConfig(readFileSync(fd, 'utf8')); } finally { closeSync(fd); }
  } catch (error) {
    if (error instanceof Failure) throw error;
    if (error.code === 'ENOENT') return {};
    fail('config_unreadable', 'Cannot read local configuration. Check its permissions.');
  }
}

export function endpoint(base) {
  let url;
  try { url = new URL(base); } catch { fail('config_invalid', 'Set a valid Sub2API base URL in the configuration file.'); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && loopback)) ||
      url.username || url.password || url.search || url.hash)
    fail('config_invalid', 'Use HTTPS (or loopback HTTP) without URL credentials, query or fragment.');
  let path = url.pathname.replace(/\/+$/, '');
  if (!path.endsWith('/v1')) path += '/v1';
  url.pathname = path + '/images/generations';
  return url.href;
}

function status() {
  const config = readConfig();
  const baseUrlConfigured = Boolean(config.SUB2API_BASE_URL);
  const apiKeyConfigured = Boolean(config.SUB2API_API_KEY);
  if (baseUrlConfigured) endpoint(config.SUB2API_BASE_URL);
  return { ready: baseUrlConfigured && apiKeyConfigured, baseUrlConfigured, apiKeyConfigured };
}

function initialize(noOpen) {
  let created = false;
  try {
    const directory = join(homedir(), CONFIG_DIR);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    if (!lstatSync(directory).isDirectory()) fail('config_invalid', 'Configuration directory must not be a symlink.');
    try {
      writeFileSync(configPath(), TEMPLATE, { flag: 'wx', mode: 0o600 });
      created = true;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (!lstatSync(configPath()).isFile()) fail('config_invalid', 'Configuration must be a regular file.');
    }
  } catch (error) {
    if (error instanceof Failure) throw error;
    fail('config_write_failed', 'Cannot create local configuration. Check directory permissions.');
  }
  const result = { configPath: configPath(), created, opened: false };
  if (!noOpen) {
    const editor = process.platform === 'darwin' ? ['open', '-e'] : ['xdg-open'];
    const opened = spawnSync(editor[0], [...editor.slice(1), configPath()], { stdio: 'ignore', shell: false });
    if (opened.error || opened.status !== 0)
      fail('editor_unavailable', 'Configuration is preserved. Open ~/.sub2api-imagegen/.env in a local editor and fill both variables yourself.');
    result.opened = true;
  }
  return result;
}

async function readBody(response, signal) {
  if (Number(response.headers.get('content-length')) > MAX_BODY)
    fail('response_too_large', 'Provider response exceeds the size limit.');
  if (!response.body) fail('invalid_response', 'Provider returned no image body.');
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      signal.throwIfAborted();
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY) fail('response_too_large', 'Provider response exceeds the size limit.');
      chunks.push(value);
    }
    signal.throwIfAborted();
    try { return JSON.parse(Buffer.concat(chunks, size).toString('utf8')); }
    catch { fail('invalid_response', 'Provider returned invalid JSON.'); }
  } finally {
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function validateImage(body) {
  const encoded = body?.data?.[0]?.b64_json;
  if (!Array.isArray(body?.data) || body.data.length !== 1 || typeof encoded !== 'string' ||
      !encoded.length || encoded.length % 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded))
    fail('invalid_response', 'Provider must return exactly one base64 image.');
  if (encoded.length > 4 * Math.ceil(MAX_IMAGE / 3)) fail('response_too_large', 'Image exceeds 50 MiB.');
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.toString('base64') !== encoded) fail('invalid_response', 'Provider returned invalid base64.');
  try { return inspectGeneratedImage(bytes); }
  catch { fail('invalid_image', 'Provider returned an incomplete or unsupported PNG/JPEG/WebP image.'); }
}

// One POST only; the deadline covers response headers and full body consumption.
export async function generate({ prompt, aspectRatio = 'auto', background = 'auto',
  timeoutSeconds = 120, outputDir = 'generated-images', signal: callerSignal }) {
  if (typeof prompt !== 'string' || !prompt.trim() || prompt.length > 20000 ||
      !Object.hasOwn(SIZES, aspectRatio) || !['auto', 'opaque'].includes(background) ||
      !Number.isFinite(timeoutSeconds) || timeoutSeconds < 0.05 || timeoutSeconds > 120)
    fail('invalid_input', 'Use a nonempty prompt (up to 20000 characters), a supported option and a 0.05–120 second timeout.');
  const config = readConfig();
  if (!config.SUB2API_BASE_URL || !config.SUB2API_API_KEY)
    fail('config_missing', 'Run init, fill both variables locally, then run status. Never paste credentials into chat.');
  const url = endpoint(config.SUB2API_BASE_URL);
  const destination = resolve(outputDir);
  try { mkdirSync(destination, { recursive: true }); accessSync(destination, constants.W_OK); }
  catch { fail('output_unwritable', 'Output directory is not writable; no request was sent.'); }
  const deadline = AbortSignal.timeout(Math.ceil(timeoutSeconds * 1000));
  const local = new AbortController();
  const signal = AbortSignal.any([deadline, local.signal, ...(callerSignal ? [callerSignal] : [])]);
  let response;
  try {
    signal.throwIfAborted();
    response = await fetch(url, {
      method: 'POST', redirect: 'manual', signal,
      headers: { Authorization: `Bearer ${config.SUB2API_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'gpt-image-2', prompt: prompt.trim(), n: 1,
        size: SIZES[aspectRatio], quality: 'low', response_format: 'b64_json', background }),
    });
    if (response.status >= 300 && response.status < 400)
      fail('redirect_refused', 'Provider redirected the request. No redirect was followed; check the configured endpoint.');
    if (!response.ok) fail(`provider_http_${response.status}`, `Sub2API returned HTTP ${response.status}. Check credentials, quota or input locally.`);
    const body = await readBody(response, signal);
    if (body?.error) fail('provider_error', 'Sub2API reported an error; no image was saved.');
    const image = validateImage(body);
    signal.throwIfAborted();
    const extension = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' }[image.contentType];
    const path = join(destination, `sub2api-${randomUUID()}.${extension}`);
    let fd;
    try {
      fd = openSync(path, 'wx', 0o600);
      writeFileSync(fd, image.bytes);
    } catch {
      if (fd !== undefined) { try { unlinkSync(path); } catch {} }
      fail('save_failed', 'Generation completed but local save failed. Do not automatically submit again.');
    } finally { if (fd !== undefined) closeSync(fd); }
    return { path, contentType: image.contentType, width: image.width, height: image.height,
      bytes: image.bytes.length, model: 'gpt-image-2', quality: 'low' };
  } catch (error) {
    if (callerSignal?.aborted) fail('cancelled', 'Local request cancelled. Provider completion/charges may be unknown; do not automatically retry.');
    if (deadline.aborted) fail('timeout', 'Request timed out. Provider completion/charges may be unknown; do not automatically retry.');
    if (error instanceof Failure) throw error;
    fail('network_error', 'Request interrupted. Check service/network access; completion/charges may be unknown. Do not automatically retry.');
  } finally {
    local.abort();
    if (response?.body && !response.body.locked) void response.body.cancel().catch(() => {});
  }
}

const HELP = `Usage: node scripts/sub2api-imagegen.mjs init [--no-open]
       node scripts/sub2api-imagegen.mjs status
       node scripts/sub2api-imagegen.mjs generate --prompt TEXT | --prompt-file FILE
         [--aspect-ratio auto|1:1|9:16] [--background auto|opaque]
         [--output-dir DIRECTORY] [--timeout-seconds 0.05..120]
Config: ~/.sub2api-imagegen/.env (SUB2API_BASE_URL, SUB2API_API_KEY).
Node.js 20.3+; macOS/Linux. No dependencies. One paid POST, no automatic retries.
Only text-to-image, gpt-image-2, low quality, 1K. SIGINT/SIGTERM cancel local waiting.
Output is JSON; errors never include upstream bodies, credentials or raw stacks.
--no-open only creates/preserves the template for headless setup.\n`;

export async function main(args) {
  const [command, ...rest] = args;
  if (!command || ['--help', '-h', 'help'].includes(command)) { process.stdout.write(HELP); return; }
  if (command === 'init' && (rest.length === 0 || (rest.length === 1 && rest[0] === '--no-open')))
    return initialize(rest.length === 1);
  if (command === 'status' && rest.length === 0) {
    const result = status();
    if (!result.ready) process.exitCode = 1;
    return result;
  }
  if (command !== 'generate') fail('usage', 'Unknown command or option. Run --help.');
  const allowed = ['--prompt', '--prompt-file', '--aspect-ratio', '--background', '--output-dir', '--timeout-seconds'];
  const options = {};
  for (let i = 0; i < rest.length; i += 2) {
    if (!allowed.includes(rest[i]) || rest[i + 1] === undefined || Object.hasOwn(options, rest[i]))
      fail('usage', 'Unknown, duplicate or incomplete option. Run --help.');
    options[rest[i]] = rest[i + 1];
  }
  if (Object.hasOwn(options, '--prompt') === Object.hasOwn(options, '--prompt-file'))
    fail('usage', 'Supply exactly one of --prompt or --prompt-file.');
  let prompt = options['--prompt'];
  if (options['--prompt-file'] !== undefined) {
    try { prompt = readFileSync(options['--prompt-file'], 'utf8'); }
    catch { fail('input_unreadable', 'Cannot read the prompt file.'); }
  }
  const controller = new AbortController();
  const cancel = () => controller.abort();
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try {
    return await generate({ prompt, aspectRatio: options['--aspect-ratio'], background: options['--background'],
      outputDir: options['--output-dir'], timeoutSeconds: options['--timeout-seconds'] === undefined ? undefined : Number(options['--timeout-seconds']),
      signal: controller.signal });
  } finally { process.off('SIGINT', cancel); process.off('SIGTERM', cancel); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try { const result = await main(process.argv.slice(2)); if (result) console.log(JSON.stringify(result)); }
  catch (error) {
    const safe = error instanceof Failure ? error : new Failure('local_error', 'Local operation failed. Check file permissions and runtime.');
    console.error(JSON.stringify({ error: safe.code, message: safe.message }));
    process.exitCode = safe.code === 'cancelled' ? 130 : 1;
  }
}
