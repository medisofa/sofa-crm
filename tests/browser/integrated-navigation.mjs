/** Synthetic navigation regression: no connection to Supabase or patient data. */
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}}); const errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async request=>{
  const u=new URL(request.request().url());
  if(u.hostname!=='127.0.0.1')return request.abort();
  if(u.pathname==='/preview.html')return request.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><div id="app"></div><script type="module" src="/js/app.js"></script></html>'});
  try {
   let body=await readFile(new URL(u.pathname.slice(1),root));
   if(u.pathname==='/js/app.js'){
    const favoritesImports=(body.toString().match(/^import .*nav-favorites.*;\n/gm)||[]).join('');
    body=body.toString().replace(/^import .*;\n/gm,'').replace(/\nboot\(\);\s*$/,'');
    body=`import {html,render,raw,$,$$,applySidebarBadges} from '/js/utils/dom.js';
import {visibleNav,extraNav,ROLES,homeRoute} from '/js/utils/permissions.js';
import {initials} from '/js/utils/formatters.js';
${favoritesImports}
const APP_VERSION='navigation-test', DEFAULT_ROUTE='inicio';
const parseHash=()=>({route:location.hash.replace(/^#\\//,'')||'mi-dashboard'});
const setDiagRoute=()=>{},sb=()=>({}),prepareProgressForUpdate=async()=>{};
const resolve=async()=>({kind:'ok',def:{route:parseHash().route,label:'Vista de prueba'},mod:{render(main){main.textContent='Datos simulados';}}});
`+body+`\nwindow.setTestContext=({id='admin-a',org='org-a',role='admin',viewAs=null}={})=>{appearanceUserId=id;Object.assign(state,{session:{user:{id,email:'demo@example.test'}},profile:{full_name:'Persona de prueba'},role,memberships:[],membership:{organization_id:org,organization:'Organización de prueba',role_name:ROLES[role]?.name},viewAs});location.hash='#/mi-dashboard';layout();};window.testPermissionRoutes=(role)=>[...visibleNav(role).flatMap(g=>g.items),...extraNav(role)].map(i=>i.route);window.setTestContext();`;
   }
   return request.fulfill({body,contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':u.pathname.endsWith('.png')?'image/png':'text/plain'});
  }catch{return request.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8892/preview.html#/mi-dashboard');
 await page.locator('#userBtn').waitFor();
 assert.deepEqual(errors,[], 'Arranque sin errores');
 assert.equal(await page.locator('#nav .nav-group-btn').filter({hasText:'ARS y contratos'}).count(),1);
 assert.equal(await page.locator('#nav .nav-group-btn').filter({hasText:'Desarrollo y crecimiento'}).count(),1);
 const allowedAdmin=await page.evaluate(()=>testPermissionRoutes('admin'));
 const menuLinks=await page.locator('#nav a[href^="#/"]').evaluateAll(links=>links.map(a=>a.getAttribute('href').slice(2)));
 assert.ok(menuLinks.every(r=>allowedAdmin.includes(r)),'Todos los accesos respetan permisos');
 // Pin an existing route through search; no new route or privilege is introduced.
 await page.locator('#navSearch').fill('Tarifario contractual');
 const pin=page.locator('#nav [data-nav-favorite="contratos"]');await pin.waitFor();
 const initiallyPinned=await page.locator('#navFavorites a[href="#/contratos"]').count();
 if(initiallyPinned)await pin.click();
 await page.locator('#nav [data-nav-favorite="contratos"]').click();
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),1);
 await page.evaluate(()=>setTestContext({id:'admin-b'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),0,'Favoritos aislados por usuario');
 await page.evaluate(()=>setTestContext({id:'admin-a',org:'org-b'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),0,'Favoritos aislados por organización');
 await page.evaluate(()=>setTestContext({id:'admin-a'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),1,'Favorito restaurado en contexto original');
 // Switching to a role with narrower permissions must not surface an admin favourite.
 await page.evaluate(()=>setTestContext({id:'admin-a',role:'capturer'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),0);
 await page.locator('#navSearch').fill('Usuarios y roles');
 assert.equal(await page.locator('#nav a[href="#/usuarios"]').count(),0,'Búsqueda no aumenta permisos');
 await page.evaluate(()=>setTestContext({id:'doctor-a',role:'client'}));
 assert.equal(await page.locator('#nav .nav-group-btn').filter({hasText:'Historia clínica'}).count(),1,'Médico conserva familias propias');
 await page.locator('#navSearch').fill('Reconsideración');
 assert.equal(await page.locator('#nav a[href="#/reconsideracion"]').count(),1,'Búsqueda conserva accesos adicionales del médico');
 await page.evaluate(()=>setTestContext({id:'admin-a',role:'admin'}));
 const mapToggle=page.locator('#navMapToggle');await mapToggle.click();
 assert.equal(await page.locator('#nav a[href="#/contratos"]').count()>0,true,'Catálogo conserva módulos existentes');
 const beforeSupport=await page.evaluate(()=>JSON.stringify({...localStorage}));
 await page.evaluate(()=>setTestContext({id:'admin-a',role:'client',viewAs:{role:'client',orgName:'Consultorio de ejemplo'}}));
 assert.equal(await page.locator('[data-nav-favorite]:enabled').count(),0,'Modo soporte no modifica favoritos');
 const afterSupport=await page.evaluate(()=>JSON.stringify({...localStorage}));
 assert.equal(afterSupport,beforeSupport,'Modo soporte no persiste preferencias');
 await page.evaluate(()=>setTestContext({id:'admin-a'}));
 // Horizontal layout exposes the same catalogue and favorites without replacing main.
 await page.locator('#userBtn').click();
 await page.getByRole('menuitemradio',{name:'Horizontal',exact:true}).click();
 assert.equal(await page.locator('.app').getAttribute('data-menu'),'horizontal');
 await page.locator('#topnavCatalog').click();
 await page.waitForFunction(()=>document.querySelector('#sidebar').getBoundingClientRect().left>=-1);
 assert.equal(await page.locator('#appContent').getAttribute('inert'),'');
 assert.equal(await page.locator('#navSearch').evaluate(e=>e===document.activeElement),true,'Catálogo enfoca búsqueda');
 await page.locator('#navSearch').fill('Tarifario contractual');
 assert.equal(await page.locator('#nav a[href="#/contratos"]').count(),1);
 await page.keyboard.press('Escape');
 assert.equal(await page.locator('#sidebar').isVisible(),false,'Escape cierra catálogo horizontal');
 assert.equal(await page.locator('#topnavCatalog').evaluate(e=>e===document.activeElement),true,'Escape restaura foco en Mis módulos');
 await page.locator('#topnavGroups [data-fam="Favoritos"]').click();
 assert.equal(await page.locator('#topnavTabs a[href="#/contratos"]').count(),1);
 await page.locator('#topnavTabs [data-nav-favorite="contratos"]').click();
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),0,'Estrella horizontal permite quitar favorito');
 await page.locator('#topnavGroups [data-fam="ARS y contratos"]').click();
 await page.locator('#topnavTabs [data-nav-favorite="contratos"]').click();
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),1,'Estrella horizontal permite fijar favorito');
 await page.evaluate(()=>setTestContext({id:'admin-a',org:'org-b'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),0,'Favorito horizontal mantiene aislamiento de organización');
 await page.evaluate(()=>setTestContext({id:'admin-a'}));
 assert.equal(await page.locator('#navFavorites a[href="#/contratos"]').count(),1);
 await page.locator('#topnavUserBtn').click();
 await page.getByRole('menuitemradio',{name:'En cascada',exact:true}).click();
 // Screenshot contains the actual application shell and synthetic profile only.
 await page.locator('#navSearch').fill('');
 await page.screenshot({path:'/workspace/artifacts/sofa-menu-integrado/implementacion.png',fullPage:true});
 for(const width of [390,320]){
  await page.setViewportSize({width,height:844});await page.locator('#menuBtn').click();
  await page.waitForFunction(()=>document.querySelector('#sidebar').getBoundingClientRect().left>=-1);
  assert.equal(await page.locator('#appContent').getAttribute('inert'),'');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin desbordamiento móvil');
  await page.keyboard.press('Escape');assert.equal(await page.locator('#menuBtn').getAttribute('aria-expanded'),'false');
 }
 assert.deepEqual(errors,[]);
 console.log('PASS: menú integrado, permisos actuales, búsqueda de extras, favoritos por usuario/organización/rol, soporte readonly, catálogo/favoritos horizontales, foco y móvil.');
} finally {await browser.close();}
