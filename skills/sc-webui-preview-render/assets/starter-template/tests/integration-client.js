const assert=require('node:assert/strict');
const {WebSocket}=require('ws');
const {until}=require('./helpers');
async function main() {
  const ws=new WebSocket(process.env.SCW_TEST_URL.replace('http:','ws:'));
  const events=[];
  ws.on('message',raw=>events.push(JSON.parse(raw)));
  await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject)});
  try {
    await until(()=>events.some(event=>event.type==='state'&&event.data.status==='ready'));
    const send=(action,params={})=>ws.send(JSON.stringify({action,params}));
    async function batch(params,stop=false) {
      const offset=events.length;
      send('render/start',params);
      await until(()=>events.slice(offset).find(event=>event.type==='renderProgress'),10000);
      if(stop)send('render/stop');
      const done=await until(()=>events.slice(offset).find(event=>event.type==='renderDone'),30000);
      const relevant=events.slice(offset);
      assert.equal(relevant.some(event=>event.type==='renderError'),false,JSON.stringify(relevant));
      assert.equal(done.data.failures,0);
      let inFlight=0;
      for(const event of relevant) {
        if(event.type==='renderProgress') {inFlight++;assert.equal(inFlight,1,'NRT jobs overlapped');}
        if(event.type==='renderJobDone')inFlight--;
      }
      assert.equal(inFlight,0,'Batch done preceded job completion');
      return done.data;
    }
    const parameters={count:2,tempoMin:128,tempoMax:128,seconds:1,seedMode:'fixed',startingSeed:42};
    const first=await batch(parameters);
    assert.equal(first.completed,2);
    const repeat=await batch({...parameters,count:1});
    const stopped=await batch({...parameters,count:5,seconds:8},true);
    assert.equal(stopped.stopped,true);assert.equal(stopped.completed,1);
    // Leave one long NRT job active so the supervisor cleanup test covers scsynth too.
    const offset=events.length;
    send('render/start',{...parameters,count:1,seconds:120});
    await until(()=>events.slice(offset).find(event=>event.type==='renderProgress'));
    console.log(JSON.stringify({first,repeat,stopped,interruptReady:true}));
  } finally {ws.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1});
