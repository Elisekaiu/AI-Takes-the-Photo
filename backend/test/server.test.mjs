import test from 'node:test';
import assert from 'node:assert/strict';
import { createCameraServer, validateInput, callVisionAI } from '../server.mjs';

const id = '10242d94-28b2-47cd-a5c1-3310044ba477';
const jpeg = Buffer.concat([Buffer.from([0xFF,0xD8]), Buffer.alloc(100, 0x44), Buffer.from([0xFF,0xD9])]).toString('base64');
const fakeFetch = async (_url, options) => {
  assert.equal(options.headers.authorization,'Bearer test-key');
  const body = JSON.parse(options.body);
  assert.equal(body.store,false);
  assert.equal(body.text.format.type,'json_schema');
  assert.equal(body.input[0].content[1].type,'input_image');
  return { ok: true, json: async () => ({ output: [{type:'message',content:[{type:'output_text',text:JSON.stringify({action:'CAPTURE',say:'这幕我想拍！'})}]}] }) };
};

test('keeps the input small and checks real JPEG framing', () => {
  assert.equal(validateInput({sessionId:id,imageBase64:jpeg}).sessionId,id);
  assert.throws(()=>validateInput({sessionId:'fake',imageBase64:jpeg}));
  assert.throws(()=>validateInput({sessionId:id,imageBase64:Buffer.alloc(150).toString('base64')}));
  assert.throws(()=>validateInput({sessionId:id,imageBase64:'x'.repeat(190_000)}));
});

test('calls the Responses API with a picture and structured CAPTURE decision', async () => {
  const d = await callVisionAI(validateInput({sessionId:id,imageBase64:jpeg}),{apiKey:'test-key',fetchImpl:fakeFetch});
  assert.deepEqual(d,{action:'CAPTURE',say:'这幕我想拍！'});
});

test('text-only chat never triggers a shutter', async () => {
  const textOnly = validateInput({sessionId:id,message:'你觉得怎么样'});
  const d=await callVisionAI(textOnly,{apiKey:'test-key',fetchImpl:async (_u,o)=>{
    const b=JSON.parse(o.body);
    assert.equal(b.input[0].content.length,1);
    return {ok:true,json:async()=>({output:[{content:[{type:'output_text',text:JSON.stringify({action:'CAPTURE',say:'聊聊天也好呀'})}]}]})};
  }});
  assert.equal(d.action,'WAIT');
});

test('HTTP server validates auth, rejects invalid images, and responds without user data logs', async () => {
  const server=createCameraServer({env:{OPENAI_API_KEY:'test-key',CAMERA_DEMO_TOKEN:'local-token'},fetchImpl:fakeFetch});
  await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
  const address=server.address();
  const url=`http://127.0.0.1:${address.port}/api/decide`;
  try{
    const unauthorized=await fetch(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({sessionId:id,imageBase64:jpeg})});
    assert.equal(unauthorized.status,401);
    const invalid=await fetch(url,{method:'POST',headers:{'content-type':'application/json','authorization':'Bearer local-token'},body:'{}'});
    assert.equal(invalid.status,400);
    const okay=await fetch(url,{method:'POST',headers:{'content-type':'application/json','authorization':'Bearer local-token'},body:JSON.stringify({sessionId:id,imageBase64:jpeg})});
    assert.equal(okay.status,200);
    assert.equal((await okay.json()).action,'CAPTURE');
  }finally{await new Promise(ok=>server.close(ok));}
});
