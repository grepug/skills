#!/usr/bin/env node
// Standalone, single-request Sub2API client. Never log raw exceptions or provider data.
import { constants, lstatSync, mkdirSync, openSync, closeSync, readFileSync,
  writeFileSync, unlinkSync, accessSync, realpathSync, fstatSync, readSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, join, dirname, basename, isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { inspectGeneratedImage } from './image.mjs';

const CONFIG_DIR = '.sub2api-imagegen';
const TEMPLATE = '# Local plaintext credentials: keep private; never commit or paste into chat.\nSUB2API_BASE_URL=\nSUB2API_API_KEY=\n';
const MAX_IMAGE = 50 * 1024 * 1024;
const MAX_BODY = 4 * Math.ceil(MAX_IMAGE / 3) + 65536;
// Conservative client limits, not a claim about every Sub2API deployment.
const MAX_REFERENCES = 5;
const MAX_REFERENCE_BYTES = 20 * 1024 * 1024;
const MAX_REFERENCE_TOTAL = 50 * 1024 * 1024;
const EXTENSIONS = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };
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

export function endpoint(base, operation = 'generations') {
  if (!['generations', 'edits'].includes(operation)) fail('invalid_input', 'Unsupported image operation.');
  let url;
  try { url = new URL(base); } catch { fail('config_invalid', 'Set a valid Sub2API base URL in the configuration file.'); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && loopback)) ||
      url.username || url.password || url.search || url.hash)
    fail('config_invalid', 'Use HTTPS (or loopback HTTP) without URL credentials, query or fragment.');
  let path = url.pathname.replace(/\/+$/, '');
  if (!path.endsWith('/v1')) path += '/v1';
  url.pathname = path + '/images/' + operation;
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

// Open only explicitly supplied files, never scan a directory or fetch image URLs.
// Resolve parent aliases, refuse leaf symlinks, and check the opened inode plus
// metadata before/after a bounded read to catch replacement or concurrent changes.
function loadReferences(paths) {
  if (!Array.isArray(paths) || paths.length > MAX_REFERENCES)
    fail('invalid_references', 'Supply at most 5 explicitly authorized local reference files.');
  let total = 0;
  try {
    const entries = paths.map(path => {
      if (typeof path !== 'string' || !isAbsolute(path))
        fail('invalid_references', 'Each --image must be an absolute local file path.');
      const canonical = join(realpathSync(dirname(path)), basename(path));
      const before = lstatSync(canonical);
      if (!before.isFile()) fail('invalid_references', 'References must be regular files, not symlinks or directories.');
      if (!before.size || before.size > MAX_REFERENCE_BYTES)
        fail('reference_too_large', 'Each reference must be nonempty and at most 20 MiB.');
      total += before.size;
      if (total > MAX_REFERENCE_TOTAL) fail('reference_too_large', 'Reference files must total at most 50 MiB.');
      return { canonical, before };
    });
    return entries.map(({ canonical, before }) => {
      const fd = openSync(canonical, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      try {
        const opened = fstatSync(fd);
        if (!opened.isFile() || !sameFile(before, opened))
          fail('reference_changed', 'A reference changed during validation; no request was sent.');
        // An extra byte detects growth without an unbounded readFile allocation.
        const bytes = Buffer.alloc(opened.size + 1);
        let length = 0;
        while (length < bytes.length) {
          const count = readSync(fd, bytes, length, bytes.length - length, null);
          if (!count) break;
          length += count;
        }
        if (length !== opened.size || !sameFile(opened, fstatSync(fd)))
          fail('reference_changed', 'A reference changed while reading; no request was sent.');
        try { return inspectGeneratedImage(bytes.subarray(0, length)); }
        catch { fail('invalid_reference_image', 'References must contain complete PNG/JPEG/WebP image containers.'); }
      } finally { closeSync(fd); }
    });
  } catch (error) {
    if (error instanceof Failure) throw error;
    fail('reference_unreadable', 'Cannot safely read a reference. Check its path, file type and permissions locally; no request was sent.');
  }
}

function sameFile(a, b) {
  return a.dev === b.dev && a.ino === b.ino && a.size === b.size &&
    a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
}

// One POST only; the deadline covers serialization/upload, headers and response body.
export async function generate({ prompt, aspectRatio = 'auto', background = 'auto',
  timeoutSeconds = 120, outputDir = 'generated-images', images = [], signal: callerSignal }) {
  if (typeof prompt !== 'string' || !prompt.trim() || prompt.length > 20000 ||
      !Object.hasOwn(SIZES, aspectRatio) || !['auto', 'opaque'].includes(background) ||
      !Number.isFinite(timeoutSeconds) || timeoutSeconds < 0.05 || timeoutSeconds > 120)
    fail('invalid_input', 'Use a nonempty prompt (up to 20000 characters), a supported option and a 0.05–120 second timeout.');
  if (callerSignal?.aborted) fail('cancelled', 'Request was cancelled before submission.');
  const config = readConfig();
  if (!config.SUB2API_BASE_URL || !config.SUB2API_API_KEY)
    fail('config_missing', 'Run init, fill both variables locally, then run status. Never paste credentials into chat.');
  const references = loadReferences(images);
  const url = endpoint(config.SUB2API_BASE_URL, references.length ? 'edits' : 'generations');
  const destination = resolve(outputDir);
  try { mkdirSync(destination, { recursive: true }); accessSync(destination, constants.W_OK); }
  catch { fail('output_unwritable', 'Output directory is not writable; no request was sent.'); }
  const deadline = AbortSignal.timeout(Math.ceil(timeoutSeconds * 1000));
  const local = new AbortController();
  const signal = AbortSignal.any([deadline, local.signal, ...(callerSignal ? [callerSignal] : [])]);
  let response;
  try {
    signal.throwIfAborted();
    const fields = { model: 'gpt-image-2', prompt: prompt.trim(), n: 1,
      size: SIZES[aspectRatio], quality: 'low', response_format: 'b64_json', background };
    const headers = { Authorization: `Bearer ${config.SUB2API_API_KEY}` };
    let requestBody;
    if (references.length) {
      requestBody = new FormData();
      for (const [name, value] of Object.entries(fields)) requestBody.append(name, String(value));
      references.forEach((image, index) => requestBody.append('image[]',
        new Blob([image.bytes], { type: image.contentType }), `reference-${index + 1}.${EXTENSIONS[image.contentType]}`));
      // fetch supplies the multipart boundary; never set Content-Type manually.
    } else {
      headers['Content-Type'] = 'application/json';
      requestBody = JSON.stringify(fields);
    }
    response = await fetch(url, {
      method: 'POST', redirect: 'manual', signal,
      headers, body: requestBody,
    });
    if (response.status >= 300 && response.status < 400)
      fail('redirect_refused', 'Provider redirected the request. No redirect was followed; check the configured endpoint.');
    if (!response.ok) fail(`provider_http_${response.status}`, `Sub2API returned HTTP ${response.status}. Check credentials, quota or input locally.`);
    const body = await readBody(response, signal);
    if (body?.error) fail('provider_error', 'Sub2API reported an error; no image was saved.');
    const image = validateImage(body);
    signal.throwIfAborted();
    const extension = EXTENSIONS[image.contentType];
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
         [--image /absolute/reference.png ...] (repeat --image for each file)
         [--aspect-ratio auto|1:1|9:16] [--background auto|opaque]
         [--output-dir DIRECTORY] [--timeout-seconds 0.05..120]
Config: ~/.sub2api-imagegen/.env (SUB2API_BASE_URL, SUB2API_API_KEY).
Node.js 20.3+; macOS/Linux. No dependencies. One paid POST, no automatic retries.
Text-to-image or local references via /images/edits; gpt-image-2, low quality, 1K.
References: at most 5 PNG/JPEG/WebP files, 20 MiB each, 50 MiB total (client limits).
Only upload files explicitly authorized by the user. No URLs or masks.
SIGINT/SIGTERM cancel local waiting, including upload.
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
  const allowed = ['--prompt', '--prompt-file', '--aspect-ratio', '--background', '--output-dir', '--timeout-seconds', '--image'];
  const options = {};
  const images = [];
  for (let i = 0; i < rest.length; i += 2) {
    if (!allowed.includes(rest[i]) || rest[i + 1] === undefined ||
        (rest[i] !== '--image' && Object.hasOwn(options, rest[i])))
      fail('usage', 'Unknown, duplicate or incomplete option. Run --help.');
    if (rest[i] === '--image') images.push(rest[i + 1]);
    else options[rest[i]] = rest[i + 1];
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
      images, signal: controller.signal });
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
