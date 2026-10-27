// Offline contract tests: only temporary HOME directories and loopback HTTP.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync, statSync,
  readdirSync, cpSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { endpoint, parseConfig, generate } from './sub2api-imagegen.mjs';
import { inspectGeneratedImage } from './image.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const CLI = join(scriptDir, 'sub2api-imagegen.mjs');
const fixtures = JSON.parse(readFileSync(join(scriptDir, 'fixtures.json'), 'utf8'));
const SECRET = 'test-only-secret-never-echo';

function workspace(t) {
  const home = mkdtempSync(join(tmpdir(), 'sub2api-test-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  return home;
}
function config(home, base) {
  mkdirSync(join(home, '.sub2api-imagegen'), { recursive: true });
  writeFileSync(join(home, '.sub2api-imagegen', '.env'),
    `SUB2API_BASE_URL=${base}\nSUB2API_API_KEY=${SECRET}\n`);
}
function cli(home, args, { script = CLI, env = {}, onStart } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], {
      cwd: home, env: { ...process.env, HOME: home, ...env }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    child.on('error', reject);
    child.on('close', (code, signal) => resolve({ code, signal, stdout, stderr }));
    onStart?.(child);
  });
}
async function server(t, handler) {
  const requests = [];
  const srv = createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    requests.push({ url: req.url, auth: req.headers.authorization, method: req.method, body: JSON.parse(raw || '{}') });
    handler(req, res, requests);
  });
  srv.listen(0, '127.0.0.1');
  await once(srv, 'listening');
  t.after(() => { srv.closeAllConnections(); srv.close(); });
  return { base: `http://127.0.0.1:${srv.address().port}`, requests };
}
function image(res, ext = 'png') { res.end(JSON.stringify({ data: [{ b64_json: fixtures[ext] }] })); }
function safeError(result, code) {
  assert.notEqual(result.code, 0);
  assert.equal(JSON.parse(result.stderr).error, code);
  assert.ok(!result.stdout.includes(SECRET) && !result.stderr.includes(SECRET));
  assert.ok(!result.stderr.includes(' at '));
}

test('first init opens a blank local template; repeat preserves content and permissions', async t => {
  const home = workspace(t);
  const bin = join(home, 'bin'); mkdirSync(bin);
  // Stub the OS opener: no real editor or production configuration is touched.
  const recorder = '#!/bin/sh\nprintf "%s\\n" "$@" > "$HOME/open-args"\n';
  for (const name of ['open', 'xdg-open']) writeFileSync(join(bin, name), recorder, { mode: 0o755 });
  const first = await cli(home, ['init'], { env: { PATH: bin } });
  assert.equal(first.code, 0, first.stderr);
  assert.equal(JSON.parse(first.stdout).opened, true);
  const path = join(home, '.sub2api-imagegen', '.env');
  assert.ok(readFileSync(path, 'utf8').includes('SUB2API_BASE_URL=\nSUB2API_API_KEY=\n'));
  assert.ok(readFileSync(join(home, 'open-args'), 'utf8').includes(path));
  assert.equal(statSync(path).mode & 0o777, 0o600);
  assert.equal(statSync(dirname(path)).mode & 0o777, 0o700);
  config(home, 'https://example.invalid/v1');
  const before = readFileSync(path);
  const repeat = await cli(home, ['init', '--no-open']);
  assert.equal(repeat.code, 0);
  assert.equal(JSON.parse(repeat.stdout).created, false);
  assert.deepEqual(readFileSync(path), before);
  assert.ok(!repeat.stdout.includes(SECRET));
});

test('headless init can be completed manually; editor failure preserves template', async t => {
  const home = workspace(t);
  const result = await cli(home, ['init'], { env: { PATH: join(home, 'no-editor') } });
  safeError(result, 'editor_unavailable');
  assert.ok(statSync(join(home, '.sub2api-imagegen', '.env')).isFile());
  assert.equal((await cli(home, ['init', '--no-open'])).code, 0);
});

test('status exposes only booleans; missing configuration prevents generation', async t => {
  const home = workspace(t);
  const missing = await cli(home, ['status']);
  assert.equal(missing.code, 1);
  assert.deepEqual(JSON.parse(missing.stdout), { ready: false, baseUrlConfigured: false, apiKeyConfigured: false });
  safeError(await cli(home, ['generate', '--prompt', 'cat']), 'config_missing');
  config(home, 'https://example.invalid/prefix');
  const ready = await cli(home, ['status']);
  assert.equal(ready.code, 0);
  assert.deepEqual(JSON.parse(ready.stdout), { ready: true, baseUrlConfigured: true, apiKeyConfigured: true });
  assert.ok(!ready.stdout.includes('example.invalid') && !ready.stdout.includes(SECRET));
});

test('configuration is parsed as literal data; malformed input is not echoed', async t => {
  const home = workspace(t);
  const literal = `$(touch ${join(home, 'executed')})`;
  assert.equal(parseConfig(`SUB2API_API_KEY='${literal}' # local\n`).SUB2API_API_KEY, literal);
  assert.equal(parseConfig('SUB2API_API_KEY="abc#def"\n').SUB2API_API_KEY, 'abc#def');
  assert.deepEqual(readdirSync(home), []);
  for (const text of [`export SUB2API_API_KEY=${SECRET}`, `SUB2API_API_KEY='${SECRET}`, 'SUB2API_API_KEY=x\nSUB2API_API_KEY=y']) {
    assert.throws(() => parseConfig(text), error => !error.message.includes(SECRET));
  }
});

test('config directory/file symlinks are refused and never overwritten', async t => {
  const home = workspace(t);
  const target = join(home, 'target'); writeFileSync(target, 'preserve');
  mkdirSync(join(home, '.sub2api-imagegen'));
  symlinkSync(target, join(home, '.sub2api-imagegen', '.env'));
  safeError(await cli(home, ['init', '--no-open']), 'config_invalid');
  safeError(await cli(home, ['status']), 'config_invalid');
  assert.equal(readFileSync(target, 'utf8'), 'preserve');
});

test('base URLs support optional /v1 and prefixes, with sensitive URL parts rejected', () => {
  for (const suffix of ['', '/', '/v1', '/v1/'])
    assert.equal(endpoint(`https://example.invalid${suffix}`), 'https://example.invalid/v1/images/generations');
  assert.equal(endpoint('https://example.invalid/router/v1/'), 'https://example.invalid/router/v1/images/generations');
  assert.equal(endpoint('https://example.invalid/router'), 'https://example.invalid/router/v1/images/generations');
  for (const bad of ['http://example.invalid', 'https://u:p@example.invalid', 'https://example.invalid/?token=x', 'https://example.invalid/#x', 'file:///tmp/x'])
    assert.throws(() => endpoint(bad));
});

test('mock API receives one supported request; output format and bytes match PNG/JPEG/WebP', async t => {
  const home = workspace(t);
  let format = 'png';
  const api = await server(t, (_req, res) => image(res, format));
  const paths = new Set();
  for (const [index, ext] of ['png', 'jpg', 'webp'].entries()) {
    format = ext;
    config(home, `${api.base}${index === 1 ? '/v1/' : ''}`);
    const promptPath = join(home, 'prompt.txt'); writeFileSync(promptPath, 'A quiet room');
    const ratio = ['auto', '1:1', '9:16'][index];
    const result = await cli(home, ['generate', '--prompt-file', promptPath, '--aspect-ratio', ratio,
      '--background', 'opaque', '--output-dir', join(home, 'artifacts')]);
    assert.equal(result.code, 0, result.stderr);
    const output = JSON.parse(result.stdout);
    assert.equal(extname(output.path), `.${ext}`);
    assert.deepEqual(readFileSync(output.path), Buffer.from(fixtures[ext], 'base64'));
    assert.equal(output.width, 2); assert.equal(output.height, 3);
    assert.ok(!paths.has(output.path)); paths.add(output.path);
    const request = api.requests[index];
    assert.equal(request.url, '/v1/images/generations');
    assert.equal(request.auth, `Bearer ${SECRET}`);
    assert.equal(request.method, 'POST');
    assert.deepEqual(request.body, { model: 'gpt-image-2', prompt: 'A quiet room', n: 1,
      size: ['auto', '1024x1024', '864x1536'][index], quality: 'low', response_format: 'b64_json', background: 'opaque' });
  }
  assert.equal(api.requests.length, 3);
  // A second generation never replaces an existing file.
  const result = await cli(home, ['generate', '--prompt', 'cat', '--output-dir', join(home, 'artifacts')]);
  assert.equal(result.code, 0);
  assert.equal(readdirSync(join(home, 'artifacts')).length, 4);
});

test('invalid and unsupported options are rejected before a paid request', async t => {
  const home = workspace(t);
  const api = await server(t, (_req, res) => image(res)); config(home, api.base);
  for (const args of [ ['--prompt', ' '], ['--prompt', 'cat', '--aspect-ratio', '16:9'],
    ['--prompt', 'cat', '--background', 'transparent'], ['--prompt', 'cat', '--reference-image', 'x'],
    ['--prompt', 'cat', '--timeout-seconds', '121'], ['--prompt', 'cat', '--quality', 'high'],
    ['--prompt', 'cat', '--prompt-file', 'x'] ]) {
    assert.notEqual((await cli(home, ['generate', ...args])).code, 0);
  }
  assert.equal(api.requests.length, 0);
});

test('HTTP/provider failures, bad JSON/base64/images and oversized responses never leak or retry', async t => {
  const home = workspace(t);
  let respond;
  const api = await server(t, (_req, res) => respond(res)); config(home, api.base);
  const cases = [
    ['provider_http_401', res => { res.writeHead(401); res.end(SECRET); }],
    ['provider_http_429', res => { res.writeHead(429); res.end(SECRET); }],
    ['provider_http_503', res => { res.writeHead(503); res.end(SECRET); }],
    ['provider_error', res => res.end(JSON.stringify({ error: { message: SECRET } }))],
    ['invalid_response', res => res.end(SECRET)],
    ['invalid_response', res => res.end(JSON.stringify({ data: [{ b64_json: '!!!!' }] }))],
    ['invalid_response', res => res.end(JSON.stringify({ data: [{ url: 'https://example.invalid/image' }] }))],
    ['invalid_image', res => res.end(JSON.stringify({ data: [{ b64_json: Buffer.from(SECRET).toString('base64') }] }))],
    ['response_too_large', res => { res.writeHead(200, { 'content-length': 80 * 1024 * 1024 }); res.end('x'); }],
    ['response_too_large', res => { res.writeHead(200); for (let i = 0; i < 72; i++) res.write(Buffer.alloc(1024 * 1024)); res.end(); }],
  ];
  for (const [code, handler] of cases) {
    respond = handler;
    safeError(await cli(home, ['generate', '--prompt', 'cat']), code);
  }
  assert.equal(api.requests.length, cases.length);
  assert.deepEqual(readdirSync(join(home, 'generated-images')), []);
});

test('redirect refuses even a second loopback destination without forwarding Authorization', async t => {
  const home = workspace(t);
  const target = await server(t, (_req, res) => image(res));
  const api = await server(t, (_req, res) => { res.writeHead(307, { location: `${target.base}/stolen` }); res.end(); });
  config(home, api.base);
  safeError(await cli(home, ['generate', '--prompt', 'cat']), 'redirect_refused');
  assert.equal(api.requests.length, 1); assert.equal(target.requests.length, 0);
});

test('interrupted response body is a sanitized network error with only one request', async t => {
  const home = workspace(t);
  const api = await server(t, (_req, res) => {
    res.writeHead(200); res.write('{');
    setTimeout(() => res.destroy(new Error(SECRET)), 20);
  });
  config(home, api.base);
  safeError(await cli(home, ['generate', '--prompt', 'cat']), 'network_error');
  assert.equal(api.requests.length, 1);
});

test('local save failure after generation never triggers a second paid request', async t => {
  const home = workspace(t);
  const output = join(home, 'output');
  const api = await server(t, (_req, res) => {
    rmSync(output, { recursive: true }); writeFileSync(output, 'occupied');
    image(res);
  });
  config(home, api.base);
  safeError(await cli(home, ['generate', '--prompt', 'cat', '--output-dir', output]), 'save_failed');
  assert.equal(api.requests.length, 1);
  assert.equal(readFileSync(output, 'utf8'), 'occupied');
});

test('single deadline covers waiting for both headers and hanging body; no retries', async t => {
  const home = workspace(t);
  let body = false;
  const api = await server(t, (_req, res) => { if (body) { res.writeHead(200); res.write('{'); } });
  config(home, api.base);
  for (body of [false, true]) {
    const started = Date.now();
    safeError(await cli(home, ['generate', '--prompt', 'cat', '--timeout-seconds', '0.1']), 'timeout');
    assert.ok(Date.now() - started < 5000);
  }
  assert.equal(api.requests.length, 2);
});

test('SIGINT and SIGTERM cancel local waiting during headers/body without resubmitting', async t => {
  const home = workspace(t);
  let currentChild, cancelSignal, body = false;
  const api = await server(t, (_req, res) => {
    if (body) { res.writeHead(200); res.write('{'); }
    setTimeout(() => currentChild.kill(cancelSignal), 20);
  });
  config(home, api.base);
  for (cancelSignal of ['SIGINT', 'SIGTERM']) for (body of [false, true]) {
    const result = await cli(home, ['generate', '--prompt', 'cat'], { onStart: child => { currentChild = child; } });
    safeError(result, 'cancelled'); assert.equal(result.code, 130);
  }
  assert.equal(api.requests.length, 4);
});

test('already cancelled generation sends nothing', async t => {
  const home = workspace(t);
  const api = await server(t, (_req, res) => image(res)); config(home, api.base);
  const previous = process.env.HOME; process.env.HOME = home;
  try {
    await assert.rejects(generate({ prompt: 'cat', outputDir: join(home, 'out'), signal: AbortSignal.abort() }), { code: 'cancelled' });
  } finally { process.env.HOME = previous; }
  assert.equal(api.requests.length, 0);
});

test('truncated containers are rejected for every supported image format', () => {
  for (const encoded of Object.values(fixtures)) {
    const bytes = Buffer.from(encoded, 'base64');
    assert.throws(() => inspectGeneratedImage(bytes.subarray(0, -1)));
  }
});

test('complete skill works after copying to an unrelated directory, without a package install', async t => {
  const home = workspace(t);
  const copy = join(home, 'copied-skill'); cpSync(dirname(scriptDir), copy, { recursive: true });
  const api = await server(t, (_req, res) => image(res)); config(home, api.base);
  const script = join(copy, 'scripts', 'sub2api-imagegen.mjs');
  assert.equal((await cli(home, ['status'], { script })).code, 0);
  const result = await cli(home, ['generate', '--prompt', 'cat'], { script });
  assert.equal(result.code, 0, result.stderr);
  assert.ok(statSync(JSON.parse(result.stdout).path).isFile());
});

test('a symlinked skill installation executes its CLI rather than silently exiting', async t => {
  const home = workspace(t);
  const link = join(home, 'installed-skill');
  symlinkSync(dirname(scriptDir), link, 'dir');
  const script = join(link, 'scripts', 'sub2api-imagegen.mjs');
  const help = await cli(home, ['--help'], { script });
  assert.equal(help.code, 0); assert.ok(help.stdout.includes('Usage:'));
  const initialized = await cli(home, ['init', '--no-open'], { script });
  assert.equal(initialized.code, 0); assert.equal(JSON.parse(initialized.stdout).created, true);
});
