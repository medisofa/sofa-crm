import http from 'node:http';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const worker=await readFile(new URL('../../sw.js',import.meta.url),'utf8');
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://test');
 if(url.pathname==='/sw.js'){res.setHeader('Content-Type','text/javascript');return res.end(worker);}
 if(url.pathname==='/'||url.pathname==='/index.html'){res.setHeader('Content-Type','text/html');return res.end('<!doctype html><title>Prueba aislada de caché</title>');}
 if(url.pathname==='/js/sample.js'){res.setHeader('Content-Type','text/javascript');return res.end('export const staticAsset=true;');}
 if(url.pathname==='/js/private.js'){res.setHeader('Content-Type','text/javascript');res.setHeader('Cache-Control','private,no-store');return res.end('export const privateAsset=true;');}
 if(url.pathname.startsWith('/api/')||url.pathname==='/js/data.js'||url.pathname==='/reports/payments.json'){res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');return res.end('{"syntheticData":true}');}
 if(url.pathname==='/documents/receipt.pdf'){res.setHeader('Content-Type','application/pdf');return res.end('synthetic document');}
 res.statusCode=404;res.end('Missing');
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const context=await browser.newContext();const page=await context.newPage();await page.goto(base+'/index.html');
 await page.evaluate(async()=>{await navigator.serviceWorker.register('/sw.js');await navigator.serviceWorker.ready});
 await page.waitForFunction(()=>navigator.serviceWorker.controller);
 await page.evaluate(async()=>{
 for(const path of ['/api/patients','/api/claims','/api/export.js','/reports/payments.json','/documents/receipt.pdf','/js/data.js','/js/private.js','/js/sample.js?patient_id=123'])await fetch(path,{cache:'no-store'});
 await fetch('/js/sample.js?sofa_v=5.27.0',{headers:{Authorization:'Bearer synthetic'},cache:'no-store'});
 await fetch('/js/sample.js?v=5.27.0',{cache:'no-store'});
 });
 await page.waitForFunction(async()=>{const c=await caches.open('sofa-shell-5.27.0');return !!await c.match('/js/sample.js?v=5.27.0')});
 const urls=await page.evaluate(async()=>{const names=await caches.keys();return (await Promise.all(names.map(async n=>(await(await caches.open(n)).keys()).map(r=>r.url)))).flat()});
 assert.ok(urls.some(u=>u.endsWith('/js/sample.js?v=5.27.0')));
 for(const u of urls){assert.ok(!/\/api\/|\/reports\/|\/documents\/|data\.js|private\.js|patient_id=|sample\.js\?sofa_v=/.test(u),u);}
 await context.setOffline(true);
 assert.equal(await page.evaluate(async()=>{try{await fetch('/api/patients');return false}catch{return true}}),true);
 assert.match(await page.evaluate(async()=>(await fetch('/js/sample.js?v=5.27.0')).text()),/staticAsset/);
 console.log('PASS: solo recursos estáticos; APIs, documentos, JSON, Authorization, parámetros de datos y respuestas privadas quedan fuera de CacheStorage. Recuperación estática sin conexión.');
}finally{await browser.close();await new Promise(r=>server.close(r));}
