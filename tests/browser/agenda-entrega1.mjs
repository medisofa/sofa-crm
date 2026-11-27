// Usage: SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/agenda-entrega1.mjs
// Primera entrega de la agenda (5.47.0). Datos ficticios; nada sale del navegador.
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const shots=process.env.SOFA_SHOTS || '';
const browser=await chromium.launch({executablePath:process.env.SOFA_CHROMIUM || '/usr/bin/chromium',args:['--no-sandbox']});
async function open(viewport){
 const page=await browser.newPage({viewport,timezoneId:'America/Santo_Domingo'});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB; export const supabase=null;'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:'export const captureProviders=async()=>[{id:"p1",full_name:"Dra. Ana Ejemplo",organization_id:"o1"}]; export const activeArs=async()=>[{id:"s",name:"SeNaSa"}];'});
  try{return route.fulfill({body:await readFile(root+u.pathname),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  const iso=(d)=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  const now=new Date(),today=iso(now),later=new Date(now);later.setDate(now.getDate()+10);window.later=iso(later);window.today=today;
  const A=(id,t,name,status,extra={})=>({id,date:today,appointment_date:today,time:t,appointment_time:t+':00',duration_min:30,patient_name:name,phone:'8095550000',payer_type:'privado',status,reason:'Motivo reservado',modality:'presencial',virtual_link:null,eligibility_status:'no_verificada',center_id:'c1',...extra});
  const list=[A('a1','08:00','Paciente Programado Apellido Largo','programada',{payer_type:'ars',ars_id:'s',ars:{name:'SeNaSa'},ars_name:'SeNaSa',member_number:'100'}),
   A('a2','08:30','Paciente Confirmado','confirmada'),A('a3','09:00','Paciente Consulta','en_consulta'),
   A('a4','09:30','Paciente Virtual','confirmada',{modality:'virtual',virtual_link:'https://meet.example.com/qa'}),A('a5','10:00','Paciente Atendido','atendida')];
  window.calls=[];window.opened=[];window.open=(u)=>{opened.push(u);};
  window.mockDB={
   rpc(name,args){calls.push({name,args});
    const data=name==='day_summary'?{appointments:{total:5,atendida:1,no_asistio:0,pendiente:4},ars_claims:{count:0,claimed:0},private:{count:0,billed:0,pending:0},collected:{total:0},unregistered:[]}
     :name==='agenda_week'?{schedule:[1,2,3,4,5,6,7].map(w=>({weekday:w,start:'08:00',end:'12:00',slot_min:30})),appointments:args.p_days===1&&args.p_from!==today?[]:list,busy:[]}
     :name==='my_agenda_scopes'?{centers_by_provider:{p1:[{id:'c1',name:'Centro QA'}]},reception:[]}:'a2';
    return Promise.resolve({data,error:null});},
   from(table){const rows=table==='appointments'?list:[];const q=new Proxy({},{get:(_,k)=>k==='then'?(ok,ko)=>Promise.resolve({data:rows,error:null}).then(ok,ko):()=>q});return q;}};
  window.day=await import('/js/modules/agenda.js');window.week=await import('/js/modules/agenda-semana.js');
  await day.render(document.querySelector('main'),{role:'client'});
 });
 await page.locator('[data-appt="a1"]').waitFor();
 return {page,errors};
}
const calls=(page,name)=>page.evaluate((n)=>calls.filter(c=>c.name===n).map(c=>c.args),name);
const toWeek=(page)=>page.evaluate(async()=>{const m=document.createElement('main');m.className='page';document.querySelector('main').replaceWith(m);await week.render(m,{role:'client'});});
const overflow=(page)=>page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
try {
 for(const [tag,vp] of [['pc',{width:1366,height:900}],['movil',{width:390,height:844}]]){
  const {page,errors}=await open(vp);
  // 1. Lista del día: el nombre no se aplasta ni lo tapa el estado; un botón principal según el estado.
  const layout=await page.evaluate(()=>[...document.querySelectorAll('[data-appt]')].map(r=>{const n=r.querySelector('.ag-info').getBoundingClientRect(),s=r.querySelector('.ag-status').getBoundingClientRect();
   return {width:n.width,overlap:!(s.left>=n.right-1||s.top>=n.bottom-1||s.bottom<=n.top+1)};}));
  assert.ok(layout.every(l=>l.width>=200&&!l.overlap),JSON.stringify(layout));
  const primary=(id)=>page.locator(`[data-appt="${id}"] .ag-act > .btn.primary`).allInnerTexts();
  assert.deepEqual(await primary('a1'),['Confirmó']);assert.deepEqual(await primary('a2'),['Llegó']);
  assert.deepEqual(await primary('a3'),['Atendido']);assert.deepEqual(await primary('a4'),['Entrar a la consulta virtual']);
  assert.ok(await page.locator('[data-appt="a1"] .ag-act > [data-st="en_espera"]').isVisible(),'hoy se puede marcar llegada sin abrir Más');
  assert.equal(await page.locator('[data-appt="a2"] [data-st="cancelada"]').isVisible(),false);
  await page.locator('[data-appt="a2"] summary').click();
  for(const sel of ['[data-attend]','[data-edit]','[data-st="no_asistio"]','[data-st="cancelada"]']) assert.ok(await page.locator(`[data-appt="a2"] ${sel}`).isVisible(),sel);
  // 4. «En consulta» se reconoce y no ofrece devolver al paciente a la sala.
  assert.equal(await page.locator('[data-appt="a3"] .ag-status').innerText(),'En consulta');
  assert.equal(await page.locator('[data-appt="a3"] [data-st="en_espera"]').count(),0);
  // Recordatorio sin el motivo de la cita.
  await page.locator('[data-appt="a2"] [data-wa]').click();
  const msg=decodeURIComponent((await page.evaluate(()=>opened[0])));
  assert.match(msg,/le recordamos su cita/);assert.doesNotMatch(msg,/Motivo reservado/);
  assert.equal(await overflow(page),0);
  if(shots) await page.screenshot({path:`${shots}/dia-${tag}.png`,fullPage:true});
  // 3. Mover la cita a otro día: fecha visible, horas libres, y vuelve a «Programada».
  await page.locator('[data-edit="a2"]').click();
  assert.equal(await page.locator('#ap_d').inputValue(),await page.evaluate(()=>today));
  await page.locator('#ap_d').fill(await page.evaluate(()=>later));
  await page.locator('[data-slot="09:00"]').click();
  assert.equal(await page.locator('#ap_t').inputValue(),'09:00');
  assert.match(await page.locator('#ap_moved').innerText(),/volverá a «Programada»/);assert.doesNotMatch(await page.locator('#ap_moved').innerText(),/elegibilidad/);
  if(shots) await page.screenshot({path:`${shots}/editar-${tag}.png`});
  await page.getByRole('button',{name:'Guardar',exact:true}).click();
  await page.waitForFunction(()=>calls.some(c=>c.name==='set_appointment_status'));
  const saved=(await calls(page,'save_appointment_modality'))[0];
  assert.equal(saved.p_date,await page.evaluate(()=>later));assert.equal(saved.p_time,'09:00');
  assert.deepEqual((await calls(page,'set_appointment_status'))[0],{p_id:'a2',p_status:'programada',p_note:null});
  // Con ARS, mover de día pide verificar de nuevo la elegibilidad.
  await page.locator('[data-appt="a1"] summary').click();await page.locator('[data-edit="a1"]').click();
  await page.locator('#ap_d').fill(await page.evaluate(()=>later));
  assert.match(await page.locator('#ap_moved').innerText(),/Verifique de nuevo la elegibilidad/);
  await page.keyboard.press('Escape');
  // 2 y 5. Semana: en el celular un día a la vez; en la computadora el estado y la elegibilidad se leen.
  await toWeek(page);
  await page.locator('.wk-week').waitFor({state:'attached'});
  if(tag==='pc'){
   assert.ok(await page.locator('.wk-week').isVisible());assert.equal(await page.locator('.wk-mobile').isVisible(),false);
   const cards=await page.evaluate(()=>[...document.querySelectorAll('.wk-ap')].map(c=>{k=c.getBoundingClientRect(),ls=[...c.querySelectorAll('.wk-line')];return {text:ls.map(l=>l.innerText).join(' | '),inside:ls.every(l=>l.getBoundingClientRect().bottom<=k.bottom+0.5&&l.scrollWidth<=l.clientWidth)};}));
   assert.ok(cards.every(c=>c.inside),JSON.stringify(cards));
   assert.ok(cards.some(c=>c.text.includes('⚠ Eleg.')&&c.text.includes('Programada')));
   assert.ok(cards.some(c=>c.text.includes('En consulta')));
  }else{
   assert.equal(await page.locator('.wk-week').isVisible(),false);assert.ok(await page.locator('.wk-mobile').isVisible());
   assert.equal(await page.locator('[data-day][aria-pressed="true"]').getAttribute('data-day'),await page.evaluate(()=>today));
   assert.ok(await page.locator('.wk-mobile').getByText('Paciente Confirmado').isVisible());
   const link=await page.locator('.wk-mobile').getByRole('link',{name:'Entrar a la consulta virtual'}).boundingBox();assert.ok(link.height>=44);
   const other=page.locator('[data-day][aria-pressed="false"]').first();await other.click();
   assert.equal(await page.locator('.wk-mobile').getByText('Paciente Confirmado').count(),0);
   await page.locator('[data-day="'+await page.evaluate(()=>today)+'"]').click();
  }
  assert.equal(await overflow(page),0);
  if(shots) await page.screenshot({path:`${shots}/semana-${tag}.png`,fullPage:true});
  if(tag==='movil'){await page.locator('.wk-mobile [data-open]').first().click();assert.equal(await page.evaluate(()=>location.hash),'#/agenda');}
  assert.deepEqual(errors,[]);await page.close();
 }
 console.log('OK · primera entrega de la agenda (computadora y celular)');
} finally { await browser.close(); }
