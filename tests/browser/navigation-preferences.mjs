import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}}); const errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><div id="app"></div><script type="module" src="/js/app.js"></script></html>'});
  try {
   let body=await readFile(new URL(u.pathname.slice(1),root));
   if(u.pathname==='/js/app.js'){
    body=body.toString().replace(/^import .*;\n/gm,'').replace(/\nboot\(\);\s*$/,'');
    body=`import {html,render,raw,$,$$,applySidebarBadges} from '/js/utils/dom.js';
import {visibleNav,extraNav,ROLES,homeRoute} from '/js/utils/permissions.js';
import {initials} from '/js/utils/formatters.js';
const APP_VERSION='5.24.0', DEFAULT_ROUTE='inicio';
const parseHash=()=>({route:location.hash.replace(/^#\\//,'')||'mi-dashboard'});
const setDiagRoute=()=>{},sb=()=>({}),prepareProgressForUpdate=async()=>{};
const resolve=async()=>({kind:'ok',def:{route:parseHash().route,label:'Vista de prueba'},mod:{render(main){main.textContent='Datos simulados';}}});
`+body+`\nwindow.setTestUser=(id)=>{appearanceUserId=id;Object.assign(state,{session:{user:{id,email:'demo@example.test'}},profile:{full_name:'Médico de prueba'},role:'client',memberships:[],membership:{organization:'Consultorio de prueba',role_name:'Médico'}});applyTheme(getTheme());layout();}; window.setTestUser(window.localStorage.getItem('test-user')||'doctor-a');`;
   }
   return route.fulfill({body,contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':u.pathname.endsWith('.png')?'image/png':'text/plain'});
  }catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html#/mi-dashboard');
 await page.locator('#userBtn').waitFor();
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'lateral');
 assert.equal(await page.locator('#nav .nav-group-btn').filter({hasText:'Historia clínica'}).count(),1);
 await page.locator('#userBtn:visible,#topnavUserBtn:visible').click();
 assert.deepEqual(errors,[], 'Errores antes de abrir menú');
 await page.getByRole('menuitemradio',{name:'Horizontal',exact:true}).click();
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'horizontal');
 assert.equal(await page.locator('#sidebar').isVisible(),false);
 assert.equal(await page.locator('#topnav').isVisible(),true);
 assert.equal(await page.locator('#userBtn:visible,#topnavUserBtn:visible').count(),1);
 assert.equal(await page.locator('#userBtn').isVisible(),false);
 assert.equal(await page.locator('#topnavGroups button[data-fam]:not([aria-label])').count(),0);
 await page.locator('#topnavUserBtn').click();
 assert.equal(await page.locator('#topnavUserBtn').getAttribute('aria-expanded'),'true');
 await page.keyboard.press('Escape');
 assert.equal(await page.locator('#topnavUserBtn').getAttribute('aria-expanded'),'false');
 await page.locator('#topnavGroups button').filter({hasText:'Historia clínica'}).click();
 assert.equal(await page.locator('#topnavTabs a[href="#/historia-clinica"]').count(),1);
 await page.reload();await page.locator('#userBtn').waitFor({state:'attached'});
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'horizontal');
 await page.evaluate(()=>setTestUser('doctor-b'));
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'lateral');
 await page.evaluate(()=>setTestUser('doctor-a'));
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'horizontal');
 await page.locator('#userBtn:visible,#topnavUserBtn:visible').click();
 await page.getByRole('menuitemradio',{name:'En cascada',exact:true}).click();
 assert.equal(await page.locator('#sidebar').isVisible(),true);
 await page.evaluate(()=>{document.documentElement.dataset.theme='light'});
 assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--navy').trim()),'#223A5D');
 assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--red').trim()),'#861D18');
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.locator('#userBtn').isVisible(),true);
 assert.equal(await page.locator('#userBtn:visible,#topnavUserBtn:visible').count(),1);
 await page.locator('#menuBtn').click();
 assert.equal(await page.locator('#menuBtn').getAttribute('aria-expanded'),'true');
 await page.waitForFunction(()=>document.querySelector('#sidebar').getBoundingClientRect().left>=-1);
 await page.keyboard.press('Escape');
 assert.equal(await page.locator('#menuBtn').getAttribute('aria-expanded'),'false');
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 assert.deepEqual(errors,[]);
 console.log('PASS: selección real de ambos menús, navegación clínica, recarga, usuarios independientes, colores SoFa y móvil. Sin conexión a datos reales.');
} finally {await browser.close();}
