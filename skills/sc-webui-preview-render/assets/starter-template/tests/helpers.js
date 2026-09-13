const {spawnSync} = require('node:child_process');
const net = require('node:net');
const dgram = require('node:dgram');
const crypto = require('node:crypto');
async function freePorts() {
  for(let attempt=0;attempt<50;attempt++) {
    const first=crypto.randomInt(45000,55000);
    const ports=[first,first+1,first+2,first+3];
    let available=true;
    for(const port of ports) {
      const result=spawnSync('lsof',['-nP',`-i:${port}`],{encoding:'utf8'});
      if(result.error) throw result.error;
      if(result.stdout.trim()) {available=false;break;}
      for(const udp of [false,true]) {
        const endpoint=udp?dgram.createSocket('udp4'):net.createServer();
        const ok=await new Promise(resolve=>{
          endpoint.once('error',()=>resolve(false));
          const ready=()=>endpoint.close(()=>resolve(true));
          if(udp)endpoint.bind(port,'127.0.0.1',ready);else endpoint.listen(port,'127.0.0.1',ready);
        });
        if(!ok) available=false;
      }
    }
    if(available)return ports;
  }
  throw Error('Could not find four free test ports');
}
async function until(predicate, timeout=5000) {
  const end=Date.now()+timeout;
  while(Date.now()<end) {const value=await predicate();if(value)return value;await new Promise(resolve=>setTimeout(resolve,25));}
  throw Error('Timed out waiting for test condition');
}
module.exports={freePorts,until};
