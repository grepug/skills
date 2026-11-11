// Native asynchronous tasks: one paid submission, recoverable GET-only waiting.
import { mkdirSync, openSync, closeSync, writeFileSync, readFileSync, renameSync, lstatSync, constants, accessSync, linkSync, unlinkSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { readConfig, endpoint, loadReferences, fail, readBody } from './sub2api-imagegen.mjs';
import { inspectGeneratedImage } from './image.mjs';
const MAX=50*1024*1024;
const ext={'image/png':'png','image/jpeg':'jpg','image/webp':'webp'};
function save(file, task, initial=false) {
  const target=initial?file:file+'.'+randomUUID()+'.tmp';
  const fd=openSync(target,'wx',0o600);
  try {writeFileSync(fd,JSON.stringify(task));} finally {closeSync(fd);}
  if(!initial)renameSync(target,file);
}
function load(file) {
  if(!lstatSync(file).isFile() || lstatSync(file).size>100000)fail('task_invalid','Task file must be a small regular local file.');
  const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW);
  let t;try{t=JSON.parse(readFileSync(fd,'utf8'));}finally{closeSync(fd);}
  if(t.version!==1 || typeof t.endpoint!=='string' || typeof t.outputDir!=='string' || !/^imgtask_[a-zA-Z0-9_-]+$/.test(t.taskId||''))
    fail('task_unrecoverable','No confirmed task ID. Submission may have been charged; investigate server logs, never automatically submit again.');
  return t;
}
function configFor(t) {
 const c=readConfig();
 if(!c.SUB2API_API_KEY || endpoint(c.SUB2API_BASE_URL)!==t.endpoint)fail('task_config_mismatch','Restore the original API endpoint and same API key before polling this task.');
 return c;
}
function result(t,file){return {taskFile:file,taskId:t.taskId,status:t.status,...(t.path?{path:t.path,...t.image}:{}),...(t.lastError?{lastError:t.lastError}:{}),resume:'wait --task-file '+file};}
async function download(url,signal) {
 let u;try{u=new URL(url);}catch{fail('download_invalid','Invalid image URL.');}
 if(u.protocol!=='https:' || u.username || u.password || u.hash)fail('download_invalid','Image download must use HTTPS without embedded credentials.');
 // No API Authorization on object-store requests, and never follow redirects.
 const r=await fetch(u,{signal,redirect:'manual'});
 if(!r.ok || r.status>=300)fail('download_failed','Image download failed; resume this task, do not regenerate.');
 if(Number(r.headers.get('content-length'))>MAX)fail('download_too_large','Image exceeds 50 MiB.');
 const reader=r.body?.getReader();if(!reader)fail('download_failed','Missing image body.');
 const chunks=[];let n=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;n+=value.length;if(n>MAX)fail('download_too_large','Image exceeds 50 MiB.');chunks.push(value);}}finally{void reader.cancel().catch(()=>{});reader.releaseLock();}
 try{return inspectGeneratedImage(Buffer.concat(chunks,n));}catch{fail('invalid_image','Unsupported or incomplete image.');}
}
// Publish only a fully written sibling file. Hard-link creation refuses overwrite.
export function publishImage(path, bytes, write=writeFileSync) {
 const temporary=path+'.'+randomUUID()+'.partial';
 try {
  write(temporary,bytes,{flag:'wx',mode:0o600});
  try {linkSync(temporary,path);}
  catch(e) {
   if(e.code!=='EEXIST')throw e;
   if(!lstatSync(path).isFile() || !readFileSync(path).equals(bytes))
    fail('save_conflict','Output exists with different contents. Do not regenerate.');
  }
 } finally {
  try {unlinkSync(temporary);} catch(e) {if(e.code!=='ENOENT')throw e;}
 }
}
export async function resumeTask(file,{wait=true,signal,waitMs=300000,pollMs=20000}={}) {
 file=resolve(file);const t=load(file);const c=configFor(t);
 if(t.status==='saved' || t.status==='failed')return result(t,file);
 const end=Date.now()+waitMs;
 while(true){
  if(signal?.aborted)return {...result(t,file),status:'waiting_cancelled'};
  const remaining=end-Date.now();if(remaining<=0)return {...result(t,file),status:'waiting_timeout'};
  const requestSignal=AbortSignal.any([AbortSignal.timeout(Math.max(1,Math.min(30000,remaining))),...(signal?[signal]:[])]);
  try {
   const poll=t.endpoint.replace(/\/generations$/,'/tasks/'+encodeURIComponent(t.taskId));
   const r=await fetch(poll,{headers:{Authorization:'Bearer '+c.SUB2API_API_KEY},redirect:'manual',signal:requestSignal});
   if(!r.ok)fail('poll_http_'+r.status,'Cannot read task; no submission was retried.');
   const b=await readBody(r,requestSignal);
   if((b.task_id||b.id)!==t.taskId || !['processing','queued','completed','failed'].includes(b.status))fail('task_response_invalid','Invalid task response.');
   t.status=b.status;delete t.lastError;save(file,t);
   if(t.status==='failed')return result(t,file);
   if(t.status==='completed') {
    if(!Array.isArray(b.result?.data)||b.result.data.length!==1 || typeof b.result.data[0].url!=='string')fail('task_response_invalid','Expected exactly one stored image URL.');
    const image=await download(b.result.data[0].url,requestSignal);
    // Reserve a stable output name in the journal before writing. A retry never overwrites a file.
    t.path ??=join(t.outputDir,'sub2api-'+randomUUID()+'.'+ext[image.contentType]);save(file,t);
    publishImage(t.path,image.bytes);
    t.status='saved';t.image={contentType:image.contentType,width:image.width,height:image.height,bytes:image.bytes.length,model:t.model,quality:'low'};save(file,t);return result(t,file);
   }
  } catch(e) {if(signal?.aborted)return {...result(t,file),status:'waiting_cancelled'};if(Date.now()>=end)return {...result(t,file),status:'waiting_timeout'};t.lastError=(requestSignal.aborted || e.name==='TimeoutError')?'poll_timeout':(typeof e.code==='string'?e.code:'poll_or_download_interrupted');save(file,t);if(!wait || !['poll_timeout','network_error','poll_or_download_interrupted','poll_http_502','poll_http_503','poll_http_504','poll_http_429'].includes(t.lastError))return result(t,file);}
  if(!wait)return result(t,file);
  const delay=Math.min(pollMs,end-Date.now());if(delay<=0)return {...result(t,file),status:'waiting_timeout'};
  try{await sleep(delay,undefined,{signal});}catch{return {...result(t,file),status:'waiting_cancelled'};}
 }
}
export async function generateAsync({prompt,model='gpt-image-2.6-sunburst',aspectRatio='auto',background='auto',outputDir='generated-images',images=[],timeoutSeconds=120,signal,onAccepted}) {
 const sizes={auto:'auto','1:1':'1024x1024','9:16':'864x1536'};
 if(typeof prompt!=='string'||!prompt.trim()||prompt.length>20000||!/^gpt-image-[a-z0-9]+(?:[.-][a-z0-9]+)*$/.test(model)||model.length>100||!Object.hasOwn(sizes,aspectRatio)||!['auto','opaque'].includes(background)||!Number.isFinite(timeoutSeconds)||timeoutSeconds<.05||timeoutSeconds>120)fail('invalid_input','Invalid generation options.');
 if(signal?.aborted)fail('cancelled','Cancelled before submission.');
 const c=readConfig();if(!c.SUB2API_API_KEY||!c.SUB2API_BASE_URL)fail('config_missing','Configure the service first.');
 const refs=loadReferences(images);const base=endpoint(c.SUB2API_BASE_URL);const dest=resolve(outputDir);mkdirSync(dest,{recursive:true});accessSync(dest,constants.W_OK);
 const file=join(dest,'sub2api-task-'+randomUUID()+'.json');const t={version:1,endpoint:base,outputDir:dest,model,status:'submitting',createdAt:new Date().toISOString(),parameters:{aspectRatio,background,referenceCount:refs.length}};
 save(file,t,true); // Durable marker exists before the paid POST; never store credentials or signed URLs.
 const fields={model,prompt:prompt.trim(),n:1,size:sizes[aspectRatio],quality:'low',response_format:'b64_json',background};
 const headers={Authorization:'Bearer '+c.SUB2API_API_KEY};let body;
 if(refs.length){body=new FormData();for(const[k,v]of Object.entries(fields))body.append(k,String(v));refs.forEach((im,i)=>body.append('image[]',new Blob([im.bytes],{type:im.contentType}),'reference-'+(i+1)+'.'+ext[im.contentType]));}
 else{headers['Content-Type']='application/json';body=JSON.stringify(fields);}
 try{
  const sig=AbortSignal.any([AbortSignal.timeout(Math.ceil(timeoutSeconds*1000)),...(signal?[signal]:[])]);
  const r=await fetch(endpoint(c.SUB2API_BASE_URL,refs.length?'edits':'generations')+'/async',{method:'POST',body,headers,redirect:'manual',signal:sig});
  if(r.status!==202)fail('submit_http_'+r.status,'Submission was not accepted.');
  const b=await readBody(r,sig);if(!/^imgtask_[a-zA-Z0-9_-]+$/.test(b.task_id||b.id||''))fail('task_response_invalid','Missing task ID.');
  t.taskId=b.task_id||b.id;t.status='processing';save(file,t);if(onAccepted)onAccepted({taskId:t.taskId,taskFile:file,status:'accepted'});
 }catch(e){t.status='submission_unknown';t.lastError=e.code||'submit_interrupted';save(file,t);return {...result(t,file),warning:'Completion and charges may be unknown. Investigate server logs; do not automatically re-submit.'};}
 return resumeTask(file,{signal});
}
