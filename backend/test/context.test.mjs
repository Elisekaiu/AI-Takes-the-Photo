import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CameraContextSessions, CAMERA_CONTEXT_LIMITS,
  OneShotCameraInbox, makeCameraCheckpoint
} from '../context.mjs';
import { createCameraServer } from '../server.mjs';

const id = '37234a5c-a14f-4c8e-9a73-f4003921bf10';
const jpeg = Buffer.concat([
  Buffer.from([0xff, 0xd8]), Buffer.alloc(110, 0x71), Buffer.from([0xff, 0xd9])
]).toString('base64');
const contextMsg = (n) => ({
  sessionId: id, imageBase64: jpeg, message: '你喜欢这只玩偶吗？', hasPhoto: false,
  recent: Array.from({length: n},(_,i)=>({role:'user',text:'一句最近的话'+i}))
});

const visionReply = (action = 'WAIT', say = '这张看起来很可爱。') => ({
  ok:true,
  json:async()=>({output:[{content:[{type:'output_text',text:JSON.stringify({action,say})}]}]})
});

test('per-camera memory is bounded, rotates its short visual window after five frames',()=>{
  let now = 100_000;
  const sessions = new CameraContextSessions({now:()=>now});
  const s = sessions.start(id, {mainContext: 'A'.repeat(800)});
  assert.equal(s.mainIntro.length,600);
  for(let i=0;i<17;i++){
    const request=contextMsg(24);
    const prompt=sessions.context(s,request);
    assert(prompt.length<=CAMERA_CONTEXT_LIMITS.maxContextChars);
    assert(prompt.includes('打开相机前'));
    sessions.record(s,request,{action:'WAIT',say:'看到一只玩偶'+i});
    now+=500;
  }
  assert.equal(s.framesReviewed,17);
  assert.equal(s.visualWindow,3);
  assert(s.notes.length<=CAMERA_CONTEXT_LIMITS.noteLines);
  assert(!('imageBase64' in s),'no image bytes saved in the session');
  assert.equal(s.lastAdvice,'看到一只玩偶16');
  const done=sessions.end(id,{photosSaved:2});
  assert.equal(done.framesReviewed,17);
  assert.equal(done.photosSaved,2);
  assert(!JSON.stringify(done).includes('data:image'));
  assert.equal(sessions.has(id),false);
  assert.equal(sessions.end(id,{photosSaved:2}),null,'duplicate close is idempotent');
  assert.throws(()=>sessions.start(id),/session_closed/);
});

test('empty camera session makes no fabricated experience and expired sessions vanish',()=>{
  let now=100_000;
  const sessions=new CameraContextSessions({now:()=>now});
  sessions.start(id);
  assert.equal(sessions.end(id,{photosSaved:0}),null);
  const other='4f80697b-c6ae-468d-a11d-a855530d775e';
  sessions.start(other);
  now+=CAMERA_CONTEXT_LIMITS.sessionMs+1;
  sessions.reap();
  assert.equal(sessions.has(other),false);
  const missing=makeCameraCheckpoint({id,framesReviewed:0,textTurns:0,mainIntro:'',lastAdvice:''},{photosSaved:0,now});
  assert.equal(missing,null);
});

test('main-thread handoff is one-time only after success, expires within two hours',()=>{
  let now=100_000;
  const inbox=new OneShotCameraInbox({now:()=>now});
  const done=makeCameraCheckpoint({id,framesReviewed:1,textTurns:1,lastUser:'老公你看玩偶',lastAdvice:'好喜欢这张'},{photosSaved:0,now});
  assert(inbox.offer(done));
  const receipt=inbox.peek();
  assert(receipt.text.includes('好喜欢这张'));
  assert(receipt.text.includes('0 张照片'));
  assert.equal(inbox.peek().text,receipt.text,'failed main turn must not consume');
  inbox.acknowledge(receipt);
  assert.equal(inbox.peek(),null);
  const next={...done,id:'815ed73c-4b4b-46dc-b56e-a785095b350e'};
  inbox.offer(next);
  now+=CAMERA_CONTEXT_LIMITS.checkpointMs+1;
  assert.equal(inbox.peek(),null);
});

test('HTTP begin -> stateless vision decisions -> end returns a tiny checkpoint without frames',async()=>{
  const seen=[];
  const server=createCameraServer({
    env:{OPENAI_API_KEY:'test-key',CAMERA_DEMO_TOKEN:'test-token'},
    fetchImpl:async (_url,options)=>{
      const req=JSON.parse(options.body);
      seen.push(req);
      assert.equal(req.store,false);
      assert.equal(req.input[0].content.filter(x=>x.type==='input_image').length,1);
      assert(req.input[0].content[0].text.length<2300);
      return visionReply('CAPTURE','这只小玩偶，我想留住。');
    }
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}`;
  const post=async(route,payload)=>{
    const response=await fetch(url+route,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer test-token'},body:JSON.stringify(payload)});
    return [response.status,await response.json()];
  };
  try{
    const [startedCode,started]=await post('/api/session/start',{sessionId:id,mainContext:'刚刚我们在聊看云。'});
    assert.equal(startedCode,200);
    assert.equal(started.ok,true);
    const [decisionCode,decision]=await post('/api/decide',contextMsg(12));
    assert.equal(decisionCode,200);
    assert.equal(decision.action,'CAPTURE');
    assert(seen[0].input[0].content[0].text.includes('看云'));
    const [endCode,ended]=await post('/api/session/end',{sessionId:id,photosSaved:0});
    assert.equal(endCode,200);
    assert.equal(ended.checkpoint.photosSaved,0,'decision is not a saved photo');
    assert.equal(ended.checkpoint.framesReviewed,1);
    assert.equal(typeof ended.checkpoint.summary,'string');
    assert(!JSON.stringify(ended).includes(jpeg));
    assert.equal((await post('/api/session/end',{sessionId:id,photosSaved:5}))[1].checkpoint,null);
    assert.equal((await post('/api/decide',contextMsg(1)))[0],400);
  }finally{await new Promise(resolve=>server.close(resolve));}
});

test('can close a session while vision model thinks without publishing a stale shutter',async()=>{
  let finish, announceStarted;
  const delayed=new Promise(resolve=>{finish=resolve});
  const modelStarted=new Promise(resolve=>{announceStarted=resolve});
  const server=createCameraServer({
    env:{OPENAI_API_KEY:'test-key'},
    fetchImpl:async()=>{
      announceStarted();
      await delayed;
      return visionReply('CAPTURE','拍！');
    }
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}`;
  const send=async(path,obj)=>{
    const response=await fetch(url+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(obj)});
    return [response.status,await response.json()];
  };
  try{
    await send('/api/session/start',{sessionId:id});
    const pending=send('/api/decide',contextMsg(0));
    // Deterministically wait until the fake model really started.
    await modelStarted;
    const [ended]=await send('/api/session/end',{sessionId:id,photosSaved:0});
    assert.equal(ended,200);
    finish();
    const [code,result]=await pending;
    assert.equal(code,410);
    assert.equal(result.error,'camera_session_ended');
  }finally{finish();await new Promise(resolve=>server.close(resolve));}
});


test('24-frame vision cap prevents unbounded model calls while manual photography remains available',async()=>{
  let charged=0;
  const server=createCameraServer({
    env:{OPENAI_API_KEY:'test-key'},
    fetchImpl:async()=>{charged++;return visionReply('WAIT','挺可爱的。');}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  async function send(path,payload){
    const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});
    return [r.status,await r.json()];
  }
  try{
    await send('/api/session/start',{sessionId:id});
    for(let i=0;i<CAMERA_CONTEXT_LIMITS.maxVisionFrames;i++){
      const [status]=await send('/api/decide',{...contextMsg(0),message:''});
      assert.equal(status,200);
    }
    assert.equal(charged,24);
    const [status,last]=await send('/api/decide',{...contextMsg(0),message:''});
    assert.equal(status,200);
    assert.equal(last.action,'WAIT');
    assert.equal(charged,24,'frame cap must avoid a 25th model call');
    const [,ended]=await send('/api/session/end',{sessionId:id,photosSaved:2});
    assert.equal(ended.checkpoint.framesReviewed,24);
    assert.equal(ended.checkpoint.photosSaved,2);
  }finally{await new Promise(resolve=>server.close(resolve));}
});
