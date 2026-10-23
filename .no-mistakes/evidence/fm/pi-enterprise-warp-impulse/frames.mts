const m = await import(process.argv[2]);
const a = m.createCalmWorkingShipAnimation();
let sawFlash=false, sawTrail=false;
for (let i=0;i<400;i++){ const f=a.render(40); const t=f.join("\n");
 if(a.warpFlash()&&!sawFlash){sawFlash=true;console.log("--- tick",i,"WARP FLASH");console.log(t.replace(/\x1b\[/g,"<"));}
 if(!a.warpFlash()&&!sawTrail&&i>5&&/[░▒]|[-~]/.test(t)){} 
 if(i==12){console.log("--- tick 12 impulse");console.log(t.replace(/\x1b\[/g,"<"));}
 a.tick(); }
console.log("flash seen:",sawFlash);
