import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,readdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {generateAsync,resumeTask} from './async.mjs';
const png=JSON.parse(readFileSync(new URL('./fixtures.json',import.meta.url))).png;
function setup(t){const home=mkdtempSync(join(tmpdir(),'async-image-'));const old=process.env.HOME,fetch=globalThis.fetch;process.env.HOME=home;mkdirSync(join(home,'.sub2api-imagegen'));writeFileSync(join(home,'.sub2api-imagegen/.env'),'SUB2API_BASE_URL=https://api.example.test\nSUB2API_API_KEY=test-secret\n');t.after(()=>{process.env.HOME=old;globalThis.fetch=fetch;rmSync(home,{recursive:true,force:true});});return home;}
const json=x=>new Response(JSON.stringify(x),{status:200});
test('async saves one POST result without forwarding auth to storage; resume is idempotent',async t=>{const h=setup(t);let posts=0,polls=0;globalThis.fetch=async(url,o)=>{url=String(url);if(o.method==='POST'){posts++;assert.equal(url,'https://api.example.test/v1/images/generations/async');return new Response(JSON.stringify({task_id:'imgtask_test'}),{status:202});}if(url.includes('/tasks/')){polls++;return json({task_id:'imgtask_test',status:'completed',result:{data:[{url:'https://storage.example.test/a?signature=secret'}]}});}assert.equal(o.headers,undefined);return new Response(Buffer.from(png,'base64'));};const r=await generateAsync({prompt:'test',outputDir:h});assert.equal(r.status,'saved');assert.equal(posts,1);assert.equal((await resumeTask(r.taskFile)).status,'saved');assert.equal(polls,1);const data=readFileSync(r.taskFile,'utf8');assert(!data.includes('test-secret'));assert(!data.includes('signature='));});
test('unknown submit is journaled, cannot resume or submit again implicitly',async t=>{const h=setup(t);let posts=0;globalThis.fetch=async()=>{posts++;throw Error('private provider error');};const r=await generateAsync({prompt:'test',outputDir:h});assert.equal(r.status,'submission_unknown');assert.equal(posts,1);await assert.rejects(resumeTask(r.taskFile),/No confirmed task ID/);assert(!JSON.stringify(r).includes('private provider'));});
test('foreground timeout preserves id, polling resumes with GET only',async t=>{const h=setup(t);const f=join(h,'task.json');writeFileSync(f,JSON.stringify({version:1,endpoint:'https://api.example.test/v1/images/generations',outputDir:h,taskId:'imgtask_pending',status:'processing'}));let n=0;globalThis.fetch=async(u,o)=>{assert.notEqual(o.method,'POST');n++;return json({task_id:'imgtask_pending',status:'processing'});};assert.equal((await resumeTask(f,{waitMs:35,pollMs:10})).status,'waiting_timeout');assert(n>=2);assert.equal(JSON.parse(readFileSync(f)).status,'processing');assert.equal((await resumeTask(f,{wait:false})).taskId,'imgtask_pending');});
test('failed task does not download or resubmit',async t=>{const h=setup(t);const f=join(h,'task.json');writeFileSync(f,JSON.stringify({version:1,endpoint:'https://api.example.test/v1/images/generations',outputDir:h,taskId:'imgtask_failed',status:'processing'}));let n=0;globalThis.fetch=async()=>{n++;return json({task_id:'imgtask_failed',status:'failed',error:{message:'secret'}});};assert.equal((await resumeTask(f)).status,'failed');assert.equal((await resumeTask(f)).status,'failed');assert.equal(n,1);});
test('changed API origin is refused before sending credentials',async t=>{const h=setup(t);const f=join(h,'task.json');writeFileSync(f,JSON.stringify({version:1,endpoint:'https://attacker.example/v1/images/generations',outputDir:h,taskId:'imgtask_failed'}));globalThis.fetch=()=>assert.fail('must not fetch');await assert.rejects(resumeTask(f),/original API endpoint/);});

test('CLI async entry point submits once and exits on failed task',async t=>{const h=setup(t);const {createServer}=await import('node:http');const {spawn}=await import('node:child_process');let posts=0;const srv=createServer((req,res)=>{res.setHeader('Content-Type','application/json');if(req.method==='POST'){posts++;res.statusCode=202;res.end(JSON.stringify({task_id:'imgtask_cli'}));}else res.end(JSON.stringify({task_id:'imgtask_cli',status:'failed'}));});await new Promise(r=>srv.listen(0,'127.0.0.1',r));t.after(()=>srv.close());writeFileSync(join(h,'.sub2api-imagegen/.env'),`SUB2API_BASE_URL=http://127.0.0.1:${srv.address().port}\nSUB2API_API_KEY=test-secret\n`);const child=spawn(process.execPath,[new URL('./sub2api-imagegen.mjs',import.meta.url).pathname,'generate','--mode','async','--prompt','test','--output-dir',h],{env:{...process.env,HOME:h}});let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);const timer=setTimeout(()=>child.kill(),5000);const code=await new Promise(r=>child.on('close',r));clearTimeout(timer);assert.equal(code,0);assert.equal(posts,1);assert.equal(JSON.parse(out).status,'failed');assert.equal(JSON.parse(err).status,'accepted');});
test('async references use edits multipart exactly once',async t=>{const h=setup(t);const image=join(h,'ref.png');writeFileSync(image,Buffer.from(png,'base64'));let posts=0;globalThis.fetch=async(url,o)=>{if(o.method==='POST'){posts++;assert.equal(url,'https://api.example.test/v1/images/edits/async');assert(o.body instanceof FormData);assert.equal(o.body.getAll('image[]').length,1);assert.equal(o.headers['Content-Type'],undefined);return new Response(JSON.stringify({task_id:'imgtask_edit'}),{status:202});}return json({task_id:'imgtask_edit',status:'failed'});};assert.equal((await generateAsync({prompt:'test',images:[image],outputDir:h})).status,'failed');assert.equal(posts,1);});

test('partial local write cannot poison final path and retry publishes complete bytes',async t=>{
 const h=setup(t),path=join(h,'image.png'),bytes=Buffer.from(png,'base64');
 const {publishImage}=await import('./async.mjs');
 assert.throws(()=>publishImage(path,bytes,(file,data,options)=>{writeFileSync(file,data.subarray(0,8),options);throw Object.assign(Error('disk full'),{code:'ENOSPC'});}));
 assert(!readdirSync(h).includes('image.png'));
 assert(!readdirSync(h).some(x=>x.endsWith('.partial')));
 publishImage(path,bytes);assert.deepEqual(readFileSync(path),bytes);
 publishImage(path,bytes);assert.deepEqual(readFileSync(path),bytes);
 assert.throws(()=>publishImage(path,Buffer.from('different')),/different contents/);
 assert.deepEqual(readFileSync(path),bytes);
});
test('individual query TimeoutError retries GET within foreground deadline',async t=>{
 const h=setup(t),f=join(h,'task.json');
 writeFileSync(f,JSON.stringify({version:1,endpoint:'https://api.example.test/v1/images/generations',outputDir:h,taskId:'imgtask_timeout',status:'processing'}));
 let n=0;globalThis.fetch=async(u,o)=>{assert.notEqual(o.method,'POST');if(++n===1)throw new DOMException('request timed out','TimeoutError');return json({task_id:'imgtask_timeout',status:'failed'});};
 const r=await resumeTask(f,{waitMs:1000,pollMs:1});assert.equal(r.status,'failed');assert.equal(n,2);
});
test('atomic publication refuses symlink destination without touching target',async t=>{
 const h=setup(t),target=join(h,'user-file'),path=join(h,'image.png');
 const {symlinkSync}=await import('node:fs');const {publishImage}=await import('./async.mjs');
 writeFileSync(target,'user data');symlinkSync(target,path);
 assert.throws(()=>publishImage(path,Buffer.from(png,'base64')),/different contents/);
 assert.equal(readFileSync(target,'utf8'),'user data');
});
