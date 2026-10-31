/**
 * SOFA · Diagnóstico de conexión y seguridad.
 * Muestra lo que TU rol puede ver: las cifras cambian según RLS. También
 * intenta una escritura prohibida para confirmar que la base la bloquea.
 */
import { APP_VERSION } from '../version.js';
import { html, render as paint, $ } from '../utils/dom.js';
import { friendlyError } from '../utils/ui.js';
import { headCount } from '../services/stats.js';
import { CONFIG } from '../config.js';
import { projectUrl } from '../supabase.js';
import { num, dateTime } from '../utils/formatters.js';

/** 31/10/2026 · Registro de diagnóstico: solo lo ve el Súper Admin (la base de datos ya lo exige
 *  aparte, vía RLS — esto es nomás para no ofrecer un panel vacío a quien no puede leerlo). Guarda
 *  en vivo, desde cualquier pantalla de cualquier usuario, la sesión (rol, aal) y los errores que
 *  salieron — así se puede ver qué le pasó a un cliente sin pedirle capturas de pantalla. */
async function renderDiagLog(main, ctx) {
  if (ctx.role !== 'super_admin') return '';
  const host = html`<div class="card" style="margin-top:14px"><h2>Registro de diagnóstico (solo Súper Admin)</h2>
    <p class="sub">Eventos recientes de cualquier sesión: errores de pantalla y el nivel de verificación (aal) con que entró cada quien.</p>
    <div id="diagLog"></div></div>`;
  setTimeout(async () => {
    const box = $('#diagLog', main);
    if (!box) return;
    const { data, error } = await ctx.sb.from('app_diagnostics_log').select('created_at, email, role_code, aal, route, event_type, table_name, message').order('created_at', { ascending: false }).limit(100);
    if (error) { paint(box, html`<p class="small muted">No se pudo leer el registro: ${friendlyError(error)}</p>`); return; }
    if (!data.length) { paint(box, html`<p class="small muted">Sin eventos todavía.</p>`); return; }
    paint(box, html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Cuándo</th><th>Quién</th><th>aal</th><th>Ruta</th><th>Tipo</th><th>Mensaje</th></tr></thead>
      <tbody>${data.map((r) => html`<tr><td data-l="Cuándo">${dateTime(r.created_at)}</td><td data-l="Quién">${r.email || ''} <span class="small muted">(${r.role_code || '—'})</span></td>
        <td data-l="aal">${r.aal || '—'}</td><td data-l="Ruta" class="small mono">${r.route || ''}</td>
        <td data-l="Tipo"><span class="pill ${r.event_type === 'error' ? 'warn' : ''}">${r.event_type}</span></td>
        <td data-l="Mensaje" class="small">${r.message}${r.table_name ? ` · ${r.table_name}` : ''}</td></tr>`)}</tbody></table></div>`);
  }, 0);
  return host;
}

const TABLES = [
  ['organizations', 'Organizaciones'], ['submissions', 'Radicaciones'], ['service_lines', 'Servicios'], ['payments', 'Pagos'],
  ['glosas', 'Glosas'], ['fee_rules', 'Reglas de honorarios'], ['sofa_fees', 'Honorarios SOFA'], ['leads', 'Prospectos (CRM)'],
  ['audit_log', 'Audit log'], ['procedures', 'Conceptos'], ['tariffs', 'Tarifas']
];

export async function render(main, ctx) {
  const s = ctx.session;
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Diagnóstico</h2><p>Conexión, sesión y lo que tu rol puede ver según las reglas de seguridad de la base de datos.</p></div><button class="btn" id="again">Volver a probar</button></div>
    <div class="grid two">
      <div class="card"><h2>Conexión y sesión</h2><div class="list">
        <div class="li"><div class="b"><div class="t1">Proyecto Supabase</div><div class="t2 mono">${new URL(projectUrl()).host}</div></div></div>
        <div class="li"><div class="b"><div class="t1">Usuario</div><div class="t2">${s.user.email} · ${ctx.membership.role_name}</div></div></div>
        <div class="li"><div class="b"><div class="t1">La sesión se renueva sola antes de</div><div class="t2">${dateTime(s.expires_at * 1000)}</div></div></div>
        <div class="li"><div class="b"><div class="t1">Cierre por inactividad</div><div class="t2">${CONFIG.INACTIVITY_MINUTES} minutos</div></div></div>
        <div class="li"><div class="b"><div class="t1">Versión</div><div class="t2">SOFA ${APP_VERSION} · supabase-js 2.117.2</div></div></div>
        <div class="li"><div class="b"><div class="t1">Latencia</div><div class="t2" id="lat">Midiendo…</div></div></div>
      </div></div>
      <div class="card"><h2>Prueba de seguridad</h2><p class="sub">Intenta escribir en el audit log, algo que ningún usuario puede hacer.</p><div id="sec">Probando…</div></div>
    </div>
    <div class="card" style="margin-top:14px"><h2>Filas visibles para tu rol</h2><p class="sub">Otro rol verá cifras distintas: la base de datos filtra cada consulta.</p><div id="rows"></div></div>
    ${await renderDiagLog(main, ctx)}`);

  const run = async () => {
    const t0 = performance.now();
    const counts = await Promise.allSettled(TABLES.map(([t]) => headCount(t)));
    $('#lat', main).textContent = `${Math.round(performance.now() - t0)} ms para ${TABLES.length} consultas`;
    paint($('#rows', main), html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Información</th><th class="n">Filas visibles</th></tr></thead><tbody>${TABLES.map(([t, l], i) => html`<tr><td data-l="Información">${l} <span class="small muted mono">${t}</span></td><td data-l="Filas" class="n">${counts[i].status === 'fulfilled' ? num(counts[i].value) : html`<span class="pill">${friendlyError(counts[i].reason)}</span>`}</td></tr>`)}</tbody></table></div>`);
    const { error } = await ctx.sb.from('audit_log').insert({ table_name: 'diagnostico', operation: 'INSERT' });
    paint($('#sec', main), error
      ? html`<div class="note ok">Bloqueado correctamente por la base de datos.<br><span class="small">${friendlyError(error)}</span></div>`
      : html`<div class="note bad"><b>Atención:</b> la escritura fue aceptada. Revisa que 003_rls.sql esté aplicado y avisa al administrador.</div>`);
  };
  $('#again', main).addEventListener('click', run);
  run();
}
