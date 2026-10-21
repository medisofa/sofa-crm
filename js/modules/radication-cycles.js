/** SOFA · Radicaciones: ciclos sugeridos → selección → borrador */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, toast, friendlyError, opt } from '../utils/ui.js';
import { money, num, date, period as periodLabel } from '../utils/formatters.js';
import { captureProviders, activeArs } from '../services/claims.js';
import { listCycleSuggestions, listCycleClaims, createSubmissionFromClaims } from '../services/radication-cycles.js';
import { listSubmissions } from '../services/submissions.js';
import { claimStatus, subStatus } from '../utils/constants.js';

const isReady = (c) => ['validada','lista_para_radicar'].includes(c.claim_status);
const ym = (d) => String(d || '').slice(0,7);

export async function render(main, ctx) {
  const st = { providerId:'', arsId:'', period:'', selected:new Set() };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Radicaciones</h2>
      <p>SOFA agrupa por médico, ARS y mes de servicio. El ciclo es una sugerencia; usted decide cuáles reclamaciones incluir.</p></div>
      <div class="toolbar" style="margin:0"><a class="btn primary" href="#/captura">+ Cargar reclamaciones</a><a class="btn" href="#/preradicacion">Pre-radicación</a></div></div>
    <div class="note info"><b>Flujo:</b> carga → validación → ciclo sugerido → selección → borrador → pre-radicación → radicación. Las reclamaciones atrasadas permanecen disponibles para una secuencia posterior o complementaria.</div>
    <div class="toolbar" style="margin-top:14px">
      <select class="input" id="cyProvider" style="width:auto"><option value="">Todos los médicos</option></select>
      <select class="input" id="cyArs" style="width:auto"><option value="">Todas las ARS</option></select>
      <input class="input" id="cyPeriod" type="month" style="width:auto">
    </div>
    <div class="grid kpis" id="cyKpis"></div><div id="cycleList">${loadingView(4)}</div><div id="cycleDetail"></div>
    <div class="page-head" style="margin-top:26px"><div class="t"><h2 style="font-size:1.15rem">Radicaciones creadas</h2><p>Borradores y lotes ya constituidos continúan con el flujo actual.</p></div></div>
    <div id="existing">${loadingView(3)}</div>`);

  Promise.all([captureProviders(), activeArs()]).then(([ps, ars]) => {
    if (!$('#cyProvider', main)) return;
    paint($('#cyProvider', main), html`<option value="">Todos los médicos</option>${ps.map(p => opt(p.id,p.full_name))}`);
    paint($('#cyArs', main), html`<option value="">Todas las ARS</option>${ars.map(a => opt(a.id,a.name))}`);
  }).catch(() => {});

  async function loadCycles() {
    const box=$('#cycleList',main), detail=$('#cycleDetail',main); paint(box,loadingView(4)); paint(detail,html``); st.selected.clear();
    try {
      const rows=await listCycleSuggestions(st);
      const readyN=rows.reduce((t,r)=>t+Number(r.ready||0),0), pending=rows.reduce((t,r)=>t+Number(r.pending||0),0), amt=rows.reduce((t,r)=>t+Number(r.ready_amount||0),0);
      paint($('#cyKpis',main),html`<div class="kpi"><div class="l">Ciclos sugeridos</div><div class="v">${num(rows.length)}</div></div><div class="kpi"><div class="l">Listas</div><div class="v">${num(readyN)}</div><div class="h">${money(amt)}</div></div><div class="kpi"><div class="l">Pendientes</div><div class="v">${num(pending)}</div></div><div class="kpi"><div class="l">Ciclos atrasados</div><div class="v">${num(rows.filter(r=>r.prior_cycle).length)}</div></div>`);
      if(!rows.length){paint(box,emptyView('Sin ciclos sugeridos','No hay reclamaciones sin radicación con estos filtros.'));return;}
      paint(box,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Ciclo</th><th>Médico · ARS</th><th class="n">Total</th><th class="n">Listas</th><th class="n">Pendientes</th><th class="n">Monto listo</th><th></th></tr></thead><tbody>${rows.map((r,i)=>html`<tr><td><b>${periodLabel(r.period)}</b>${r.prior_cycle?html` <span class="pill warn">Anterior</span>`:''}</td><td>${r.provider_name}<div class="small muted">${r.ars_name}</div></td><td class="n">${num(r.claims)}</td><td class="n">${num(r.ready)}</td><td class="n">${num(r.pending)}</td><td class="n">${money(r.ready_amount)}</td><td><button class="btn sm primary" data-cycle="${i}">Revisar</button></td></tr>`)}</tbody></table></div>`);
      box.querySelectorAll('[data-cycle]').forEach(b=>b.addEventListener('click',()=>openCycle(rows[Number(b.dataset.cycle)])));
    } catch(e){paint(box,html`<div class="note bad">${friendlyError(e)}</div>`);}
  }

  async function openCycle(cycle){
    const box=$('#cycleDetail',main); paint(box,html`<div class="card" style="margin-top:14px">${loadingView(4)}</div>`);
    try {
      const claims=await listCycleClaims({providerId:cycle.provider_id,arsId:cycle.ars_id,period:`${ym(cycle.period)}-01`}); st.selected=new Set(claims.filter(isReady).map(c=>c.id));
      const draw=()=>{
        const chosen=claims.filter(c=>st.selected.has(c.id)), total=chosen.reduce((t,c)=>t+Number(c.claimed||0),0);
        paint(box,html`<div class="card" style="margin-top:14px"><div class="page-head"><div class="t"><h2>Sugerencia · ${periodLabel(cycle.period)}</h2><p>${cycle.provider_name} · ${cycle.ars_name}</p></div><button class="btn" id="cyClose">Cerrar</button></div>${cycle.prior_cycle?html`<div class="note warn">Ciclo anterior: si ya fue radicado, este lote se creará como complementario.</div>`:''}<div class="toolbar"><button class="btn sm" id="cyAll">Seleccionar listas</button><button class="btn sm" id="cyNone">Quitar selección</button><span class="small"><b>${num(chosen.length)}</b> seleccionadas · <b>${money(total)}</b></span></div><div class="table-wrap"><table class="t cards"><thead><tr><th></th><th>Fecha</th><th>Paciente</th><th>NSS</th><th>Autorización</th><th>Servicio</th><th class="n">Monto</th><th>Estado</th></tr></thead><tbody>${claims.map(c=>{const [lbl,cls]=claimStatus(c.claim_status),ok=isReady(c);return html`<tr><td><input type="checkbox" data-claim="${c.id}" ${st.selected.has(c.id)?'checked':''} ${ok?'':'disabled'}></td><td>${date(c.service_date)}</td><td><a href="#/reclamaciones/${c.id}" class="mono">${c.folio}</a><div class="small">${c.patient_name}</div></td><td class="mono">${c.member_number||'—'}</td><td class="mono">${c.authorization_number||'—'}</td><td>${c.service_name}</td><td class="n">${money(c.claimed)}</td><td><span class="pill ${cls}">${lbl}</span>${!ok?html`<div class="small muted">${c.next_step||'Pendiente'}</div>`:''}</td></tr>`;})}</tbody></table></div><div class="toolbar" style="justify-content:flex-end"><button class="btn primary" id="cyCreate" ${chosen.length?'':'disabled'}>Crear borrador con ${num(chosen.length)} reclamaciones</button></div></div>`);
        $('#cyClose',box)?.addEventListener('click',()=>paint(box,html``)); $('#cyAll',box)?.addEventListener('click',()=>{st.selected=new Set(claims.filter(isReady).map(c=>c.id));draw();}); $('#cyNone',box)?.addEventListener('click',()=>{st.selected.clear();draw();});
        box.querySelectorAll('[data-claim]').forEach(cb=>cb.addEventListener('change',()=>{cb.checked?st.selected.add(cb.dataset.claim):st.selected.delete(cb.dataset.claim);draw();}));
        $('#cyCreate',box)?.addEventListener('click',async()=>{try{const id=await createSubmissionFromClaims([...st.selected],cycle.prior_cycle?'Pendientes del ciclo original':null);toast('Borrador creado','ok');location.hash=`#/radicaciones/${id}`;}catch(e){toast(friendlyError(e),'bad');}});
      }; draw();
    } catch(e){paint(box,html`<div class="note bad" style="margin-top:14px">${friendlyError(e)}</div>`);}
  }

  async function loadExisting(){
    const box=$('#existing',main); try{const {data}=await listSubmissions({group:'todas',size:50}); if(!data.length){paint(box,emptyView('Sin radicaciones creadas','Confirme un ciclo para crear el primer borrador.'));return;} paint(box,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Radicación</th><th>Prestador</th><th>ARS</th><th>Período</th><th class="n">Servicios</th><th class="n">Reclamado</th><th>Estado</th></tr></thead><tbody>${data.map(s=>{const [lbl,cls]=subStatus(s.display_status);return html`<tr><td><a href="#/radicaciones/${s.id}" class="mono"><b>${s.folio}</b></a></td><td>${s.provider_name}</td><td>${s.ars_name}</td><td>${periodLabel(s.period)}</td><td class="n">${num(s.lines)}</td><td class="n">${money(s.claimed)}</td><td><span class="pill ${cls}">${lbl}</span></td></tr>`;})}</tbody></table></div>`);}catch(e){paint(box,html`<div class="note bad">${friendlyError(e)}</div>`);}
  }

  $('#cyProvider',main).addEventListener('change',e=>{st.providerId=e.target.value;loadCycles();}); $('#cyArs',main).addEventListener('change',e=>{st.arsId=e.target.value;loadCycles();}); $('#cyPeriod',main).addEventListener('change',e=>{st.period=e.target.value;loadCycles();});
  await Promise.all([loadCycles(),loadExisting()]);
}