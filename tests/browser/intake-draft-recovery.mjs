import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const A='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',B='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',LEGACY='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const drafts=new Map(),commits=new Map(),events=[];let eventId=0,imports=0,failSave=false;
const clone=value=>JSON.parse(JSON.stringify(value));
const commitRows=(owner,origin)=>[...commits.entries()].filter(([key,r])=>key.startsWith(origin+':row:')&&r.owner===owner).map(([key,r])=>({row:key.split(':row:')[1],result:r.result,removed:false}));
const getDraft=d=>({draft:{id:d.id,version:d.version,payload:clone(d.payload),updated_at:d.at},commits:commitRows(d.owner,d.payload.origin_id||d.id)});
function api(name,args,actor){
 if(name==='google_intake_drafts_v1'){
  if(args.p_owner!==actor)return {error:{message:'Sesión distinta'}};
  const d=drafts.get(args.p_id),owned=d?.owner===actor;
  if(args.p_action==='list')return {data:{items:[...drafts.values()].filter(r=>r.owner===actor&&!r.archived).map(r=>({id:r.id,source_name:r.payload.source_name,rows:r.payload.rows.length,revision:r.version,updated_at:r.at}))}};
  if(args.p_action==='latest'){const latest=[...drafts.values()].filter(r=>r.owner===actor&&!r.archived).at(-1);return {data:latest?getDraft(latest):{draft:null}};}
  if(args.p_action==='get')return owned?{data:getDraft(d)}:{error:{message:'No tiene acceso'}};
  if(args.p_action==='legacy_list')return {data:{items:actor===A&&![...drafts.values()].some(d=>d.owner===A&&(d.payload.origin_id||d.id)===LEGACY)?[{id:LEGACY,updated_at:new Date().toISOString(),rows:2}]:[]}};
  if(args.p_action==='legacy_get'||args.p_action==='events')return {data:{events:events.filter(e=>e.owner===actor&&e.record_id.startsWith(args.p_id+':row:')).map(({owner,...e})=>clone(e)),commits:commitRows(actor,args.p_id)}};
  if(args.p_action==='archive'){if(owned)d.archived=true;return {data:{archived:true,version:d?.version}};}
  if(args.p_action==='save'){
   if(failSave)return {error:{message:'Sin conexión al guardar'}};
   if(d&&!owned)return {error:{message:'No tiene acceso'}};
   if(d?.archived)return {error:{message:'Carga descartada en otra pestaña'}};
   if(d&&JSON.stringify(d.payload)===JSON.stringify(args.p_payload))return {data:{version:d.version,updated_at:d.at}};
   if((d?.version||0)!==args.p_version)return {error:{message:'La carga cambió en otra pestaña. No se sobrescribirá.'}};
   const saved={id:args.p_id,owner:actor,payload:clone(args.p_payload),version:(d?.version||0)+1,at:new Date().toISOString()};drafts.set(saved.id,saved);return {data:{version:saved.version,updated_at:saved.at}};
  }
 }
 if(name==='log_google_intake_edit'){
  const id=++eventId;events.push({id,owner:actor,record_id:args.p_record_id,operation:'CORRECCION_CARGA_EXTERNA',old_values:{fields:args.p_fields,values:args.p_before},new_values:{fields:args.p_fields,values:args.p_after}});return {data:id};
 }
 if(name==='global_patient_lookup')return {data:{match:'none'}};
 if(name==='google_intake_review_v1'){
  const prior=commits.get(args.p_record_id);
  if(args.p_action==='duplicates')return prior?{data:{duplicate:false,already_imported:true,result:prior.result}}:{data:{duplicate:false,folios:[]}};
  if(args.p_action==='commit'){if(!prior){imports++;commits.set(args.p_record_id,{owner:actor,result:{id:'claim-'+imports,folio:'F-'+imports}});}return {data:commits.get(args.p_record_id).result};}
 }
 throw Error('Unexpected '+name);
}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 async function newPage(actor=A){
  const page=await browser.newPage({viewport:{width:1440,height:1000}});page.on('dialog',d=>d.accept());
  await page.addInitScript(actor=>{window.testUser=actor;},actor);
  await page.route('**/*',async route=>{
   const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
   if(u.pathname==='/rpc'){const {name,args,actor}=route.request().postDataJSON();return route.fulfill({contentType:'application/json',body:JSON.stringify(api(name,args,actor))});}
   if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:`<!doctype html><html lang="es" data-theme="dark"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><main id="main" class="page"></main><script type="module">window.mockDB={async rpc(name,args){return(await fetch('/rpc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,args,actor:window.testUser})})).json()}};window.intake=await import('/js/modules/google-intake.js');await intake.render(document.querySelector('main'),{role:'billing',session:{user:{id:window.testUser}}});window.prepareUpdate=(await import('/js/utils/progress-guard.js')).prepareProgressForUpdate;window.ready=true;</script></html>`});
   if(u.pathname==='/js/config.js')return route.fulfill({contentType:'text/javascript',body:'export const CONFIG={};'});
   if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB;'});
   if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
   if(u.pathname==='/js/modules/clients.js')return route.fulfill({contentType:'text/javascript',body:'export const pager=()=>"";'});
   if(u.pathname==='/js/services/calidad-dato.js')return route.fulfill({contentType:'text/javascript',body:'export const cie10Suggestions=async()=>[];'});
   if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:`export const captureProviders=async()=>[{id:'provider',full_name:'Médico Prueba',organization_id:'11111111-1111-4111-8111-111111111111'}];export const activeArs=async()=>[{id:'ars',name:'ARS Prueba'}];export const contractedServices=async()=>[{procedure_id:'procedure',name:'Consulta',amount:850}];export const listContracts=async()=>[];export const contractHistory=async()=>[];export const createContractTariff=async()=>{};export const setContractStatus=async()=>{};export const importContracts=async()=>{};export const searchCatalog=async()=>[];`});
   try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404});}
  });
  await page.goto('http://127.0.0.1:8881/preview.html#/carga-google');await page.waitForFunction(()=>window.ready===true);return page;
 }
 const header='Médico / Prestador *,ARS *,Fecha del servicio *,Paciente *,NSS / No. afiliado *,Servicio / Procedimiento *,No. autorización,Monto a reclamar\n';
 const row=(name,member)=>`Médico Prueba,ARS Prueba,10/01/2026,${name},${member},Consulta,AU${member},\n`;
 const source=header+row('Original uno','111')+row('Paciente dos','222');
 const saved=page=>page.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved'&&!document.querySelector('#gcsv').disabled);
 const upload=async(page,text=source)=>{await page.locator('#gcsv').setInputFiles({name:'original.csv',mimeType:'text/csv',buffer:Buffer.from(text)});await page.locator('#validate').click();await saved(page);};
 const page=await newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await upload(page);
 await page.locator('[data-edit-row="2"]').click();await page.locator('dialog [name="patient"]').fill('Edición pendiente');
 await page.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved');
 await page.reload();await page.waitForFunction(()=>window.ready===true);
 assert.equal(await page.locator('#gcsv').evaluate(el=>el.files.length),0);
 await page.locator('#gi-resume-editor').click();
 assert.equal(await page.locator('dialog [name="patient"]').inputValue(),'Edición pendiente');
 await page.getByRole('button',{name:'Guardar corrección',exact:true}).click();await saved(page);
 await page.locator('[data-exclude-row="3"]').click();
 await page.locator('#gi-action-reason').fill('Fila excluida durante revisión');await page.getByRole('button',{name:'Confirmar y registrar',exact:true}).click();await saved(page);
 await page.locator('#approve').click();await page.getByRole('button',{name:'Aprobar',exact:true}).click();await saved(page);
 await page.reload();await page.waitForFunction(()=>window.ready===true);
 assert.match(await page.locator('#preview').textContent(),/Edición pendiente/);
 assert.equal(await page.locator('[data-restore-row="3"]').count(),1);
 assert.match(await page.locator('#summary').textContent(),/1 aprobada/);
 const otherUser=await newPage(B);assert.equal(await otherUser.locator('#preview tbody tr').count(),0);
 assert.ok(!(await otherUser.locator('main').textContent()).includes('Edición pendiente'));await otherUser.close();
 // Two tabs keep their own text; the stale tab can preserve a separate copy without overwriting.
 const second=await newPage(A);
 await page.locator('[data-edit-row="2"]').click();await page.locator('dialog [name="patient"]').fill('Texto de la primera pestaña');
 await page.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved');
 await second.locator('[data-edit-row="2"]').click();
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='error');
 await second.locator('#gi-fork-progress').click();await saved(second);
 await second.locator('[data-edit-row="2"]').click();await second.locator('dialog [name="patient"]').fill('Texto de la segunda pestaña');
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved');
 const competing=[...drafts.values()].find(d=>d.payload.editor?.values?.patient==='Texto de la segunda pestaña');
 competing.version++;competing.payload={...competing.payload,concurrent_update:true};
 await second.locator('dialog [name="patient"]').fill('Texto de la segunda pestaña final');
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='error');
 await second.locator('dialog [data-editor-copy]').click();
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved');
 await second.getByRole('button',{name:'Guardar corrección',exact:true}).click();await saved(second);
 assert.ok([...drafts.values()].some(d=>d.payload.editor?.values?.patient==='Texto de la primera pestaña'));
 assert.ok([...drafts.values()].some(d=>d.payload.rows.some(r=>r.raw['Paciente *']==='Texto de la segunda pestaña final')));
 // Updates are blocked if a checkpoint fails; retrying saves before allowing the update.
 await second.locator('[data-edit-row="2"]').click();await second.locator('dialog [name="notes"]').fill('Cambio que debe sobrevivir');
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='saved');
 failSave=true;await second.locator('dialog [name="notes"]').fill('Cambio con red interrumpida');
 await second.waitForFunction(()=>document.querySelector('#gi-draft-status').dataset.state==='error');
 await second.getByRole('button',{name:'Guardar corrección',exact:true}).click();
 await second.getByRole('alert').waitFor();
 const denied=await second.evaluate(async()=>{try{await prepareUpdate();return false}catch{return true}});assert.equal(denied,true);
 failSave=false;
 await second.getByRole('button',{name:'Guardar corrección',exact:true}).click();await saved(second);
 assert.equal(await second.evaluate(async()=>{await prepareUpdate();return true}),true);
 await second.reload();await second.waitForFunction(()=>window.ready===true);
 assert.match(await second.locator('#preview').textContent(),/Texto de la segunda pestaña/);
 await second.locator('#approve').click();await second.getByRole('button',{name:'Aprobar',exact:true}).click();await saved(second);
 await second.locator('#import').click();await second.getByRole('button',{name:'Confirmar e importar',exact:true}).click();await saved(second);
 assert.equal(imports,1);
 await second.reload();await second.waitForFunction(()=>window.ready===true);assert.equal(imports,1);
 assert.equal(await second.locator('#import').isDisabled(),true);
 assert.equal(await second.getByText('Importada',{exact:true}).count(),1);
 assert.equal(await second.evaluate(()=>Object.keys(localStorage).length),0);
 // First-upgrade recovery: original CSV plus actor-owned audit events, no automatic claim creation.
 events.push({id:++eventId,owner:A,record_id:LEGACY+':row:2',operation:'CORRECCION_CARGA_EXTERNA',old_values:{fields:['Paciente *'],values:{'Paciente *':'Original uno'}},new_values:{fields:['Paciente *'],values:{'Paciente *':'Recuperado desde bitácora'}}});
 events.push({id:++eventId,owner:A,record_id:LEGACY+':row:3',operation:'CORRECCION_CARGA_EXTERNA',old_values:{values:{}},new_values:{fields:['estado','accion','motivo'],values:{accion:'EXCLUSION_FILA',valores:{'Paciente *':'Paciente dos'}}}});
 const legacyPage=await newPage(A);
 await legacyPage.locator('#gcsv').setInputFiles({name:'original.csv',mimeType:'text/csv',buffer:Buffer.from(source)});
 await legacyPage.getByText('Recuperar una revisión anterior al autoguardado',{exact:true}).click();
 await legacyPage.locator('#gi-legacy-list').selectOption(LEGACY);
 await legacyPage.locator('#gi-legacy-progress').click();await legacyPage.getByRole('button',{name:'Recuperar revisión',exact:true}).click();await saved(legacyPage);
 assert.match(await legacyPage.locator('#preview').textContent(),/Recuperado desde bitácora/);
 assert.equal(await legacyPage.locator('[data-restore-row="3"]').count(),1);
 assert.equal(imports,1);
 await legacyPage.reload();await legacyPage.waitForFunction(()=>window.ready===true);
 assert.match(await legacyPage.locator('#preview').textContent(),/Recuperado desde bitácora/);
 assert.deepEqual(errors,[]);
 console.log('PASS: editor sin confirmar, correcciones, exclusiones y aprobaciones sobreviven a recarga; aislamiento por usuario; conflictos conservan ambas copias; actualización bloqueada sin guardar; importaciones no se duplican; recuperación desde bitácora y sin almacenamiento local.');
}finally{await browser.close();}
