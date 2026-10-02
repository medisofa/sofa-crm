/**
 * SOFA · Ficha de una reclamación. Responde el principio rector de la Iteración 12:
 * qué servicio, paciente, médico, ARS, códigos, tarifa contratada en la fecha, cuánto se reclamó,
 * dónde está físicamente, quién es responsable, si fue validada / radicada, cuánto pagó la ARS,
 * si hubo glosa y cuánto queda pendiente.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError, busy } from '../utils/ui.js';
import { money, date, dateTime } from '../utils/formatters.js';
import { claimStatus, CLAIM_MOVE_LABELS, DISCREPANCY_STATUS, CARE_MODES } from '../utils/constants.js';
import { can, isStaff, canOpen } from '../utils/permissions.js';
import { profileNames } from '../services/submissions.js';
import { renderDossier } from './dossier-card.js';
import {
  getClaim, claimHistory, claimAudits, claimDiscrepancies, claimChecks, claimLocations, claimTransitions,
  claimPaymentLines, claimGlosaItems, recheckContract, claimTimeline, claimResubmissions, resubmitClaims
} from '../services/claims.js';

const kv = (pairs) => html`<dl class="kv">${pairs.map(([k, v]) => html`<dt>${k}</dt><dd>${v == null || v === '' ? '—' : v}</dd>`)}</dl>`;
const CHECKS = [['contracted', 'Servicio contratado para el médico con la ARS'], ['tariff', 'Monto igual a la tarifa contractual (o diferencia autorizada)'],
  ['ident', 'Paciente y NSS registrados'], ['auth', 'Autorización registrada'], ['code', 'Servicio con código SIMON / CUPS'], ['docs', 'Documentos obligatorios completos'],
  ['duplicate', 'Sin duplicados', true], ['date', 'Fecha del servicio válida']];
/** Enlace solo si el rol puede abrir ese módulo; si no, el dato como texto */
const lnk = (href, role, content, cls = '') => (canOpen(href, role) ? html`<a href="${href}" class="${cls}">${content}</a>` : html`<span class="${cls}">${content}</span>`);
const careMode = (c) => CARE_MODES.find(([v]) => v === c)?.[1] || c;

export async function render(main, ctx) {
  const id = ctx.arg; const role = ctx.role;
  const staff = isStaff(role); const showMoney = can('claims.money', role);
  paint(main, html`<div id="cl">${loadingView(6)}</div>`);
  const box = $('#cl', main);
  let S = {};

  async function load() {
    const c = await getClaim(id);
    if (!c) return null;
    const [hist, audits, discs, checks, locs, trans, pays, glosas, timeline, resubs] = await Promise.all([
      claimHistory(id), claimAudits(id), claimDiscrepancies(id), claimChecks(id).catch(() => null), claimLocations(), claimTransitions(),
      showMoney ? claimPaymentLines(id).catch(() => []) : Promise.resolve([]), showMoney ? claimGlosaItems(id).catch(() => []) : Promise.resolve([]),
      claimTimeline(id).catch(() => []), claimResubmissions(id).catch(() => [])
    ]);
    const names = await profileNames([c.created_by, c.updated_by, ...hist.map((h) => h.changed_by), ...audits.map((a) => a.auditor_id),
      ...discs.flatMap((d) => [d.created_by, d.decided_by])].filter(Boolean)).catch(() => ({}));
    return { c, hist, audits, discs, checks, locs, trans, pays, glosas, names, timeline, resubs };
  }
  async function refresh() {
    try {
      const d = await load();
      if (!d) { paint(box, emptyView('Reclamación no encontrada', 'No existe o tu usuario no tiene acceso a ella.', html`<a class="btn" href="#/reclamaciones">Volver</a>`)); return; }
      S = d; draw();
    } catch (err) { console.error(err); paint(box, errorView(err, 'rc')); box.querySelector('[data-retry]')?.addEventListener('click', refresh); }
  }

  function draw() {
    const { c, hist, audits, discs, checks, locs, trans, pays, glosas, names, timeline, resubs } = S;
    // Reenvío: solo reclamaciones devueltas por la ARS que no se han reenviado desde su última devolución
    const lastDev = hist.filter((h) => h.to_status === 'devuelta').map((h) => h.changed_at).sort().pop();
    const canResubmit = can('claims.resubmit', role) && lastDev && ['devuelta', 'en_validacion', 'con_inconsistencia', 'validada'].includes(c.claim_status)
      && !resubs.some((r) => r.created_at > lastDev);
    const [lbl, cls] = claimStatus(c.claim_status);
    ctx.setTitle(c.folio);
    const moves = trans.filter((t) => t.from_code === c.claim_status && t.allowed_roles.includes(role)
      && !(t.to_code === 'con_inconsistencia' || (t.to_code === 'validada' && c.claim_status !== 'lista_para_radicar')));
    const canAudit = can('claims.audit', role) && ['retirada', 'en_validacion', 'con_inconsistencia', 'devuelta'].includes(c.claim_status);
    const pendingDisc = discs.find((d) => d.status === 'pendiente');
    const who = (uid) => (uid ? names[uid] || 'Usuario' : '—');
    const lastAudit = audits[0];
    const radicada = ['radicada', 'en_proceso_ars', 'devuelta', 'pago_parcial', 'glosada', 'pagada', 'cerrada'].includes(c.claim_status);

    paint(box, html`
    <div class="page-head"><div class="t"><p><a href="#/reclamaciones">← Reclamaciones</a></p>
      <h2><span class="mono">${c.folio}</span> <span class="pill ${cls}">${lbl}</span></h2>
      <p>${c.service_name} · ${c.patient_name} · ${c.provider_name} · ${c.ars_name} · ${date(c.service_date)}</p></div>
      <div class="toolbar no-print" style="margin:0">
        ${moves.map((t) => html`<button class="btn ${['retirada', 'lista_para_radicar', 'en_validacion'].includes(t.to_code) ? 'primary' : ''}" data-to="${t.to_code}">${CLAIM_MOVE_LABELS[t.to_code] || claimStatus(t.to_code)[0]}</button>`)}
        ${canAudit ? html`<button class="btn primary" id="audit">Auditar expediente</button>` : ''}
        ${c.claim_status === 'pendiente_configuracion' && can('claims.recheck', role) ? html`<button class="btn" id="recheck">Volver a buscar contrato</button>` : ''}
        ${can('claims.override', role) ? html`<button class="btn" id="force">Cambio excepcional…</button>` : ''}
        ${canResubmit ? html`<button class="btn primary" id="resubmit">Reenviar en radicación complementaria</button>` : ''}
        <button class="btn" id="print">Imprimir</button>
      </div></div>

    ${c.claim_status === 'pendiente_configuracion' ? html`<div class="note bad">Este servicio no está contratado para ${c.provider_name} con ${c.ars_name} en la fecha del servicio. Configure la tarifa en ${lnk('#/contratos', role, 'Tarifario contractual')} y pulse “Volver a buscar contrato”, o autorice la excepción.</div>` : ''}
    ${pendingDisc ? html`<div class="note warn">Diferencia tarifaria pendiente de autorizar: registrado ${money(pendingDisc.registered_amount)} vs. contrato ${money(pendingDisc.tariff_amount)} (${money(pendingDisc.diff_amount)}).
      ${can('claims.discrepancy', role) ? html` <button class="btn" data-decide="${pendingDisc.id}">Decidir</button>` : ''}</div>` : ''}

    <div class="grid two">
      <div class="card"><h2>¿Dónde está y quién la tiene?</h2>
        ${kv([['Ubicación actual', html`<b>${c.location_name || '—'}</b>`], ['Responsable', html`<b>${c.custodian_name || 'Sin responsable asignado'}</b>`],
          ['Estado', html`<span class="pill ${cls}">${lbl}</span> desde ${dateTime(c.status_changed_at)}`], ['Última acción', c.last_action ? html`${c.last_action}<div class="small muted">${dateTime(c.last_action_at)}</div>` : ''],
          ['Próximo paso', html`<b>${c.next_step}</b>`], ['¿Fue validada?', lastAudit ? html`${lastAudit.result === 'validada' ? '✓ Sí' : '✕ Con inconsistencia'} · ${who(lastAudit.auditor_id)} · ${dateTime(lastAudit.audited_at)}` : 'No'],
          ['¿Fue radicada?', radicada ? html`Sí · lote ${lnk(`#/radicaciones/${c.submission_id}`, role, c.submission_folio, 'mono')}` : html`No · lote ${lnk(`#/radicaciones/${c.submission_id}`, role, c.submission_folio, 'mono')}`]])}
      </div>
      <div class="card"><h2>Servicio, códigos y contrato aplicado</h2>
        ${kv([['Servicio', c.service_name], ['Código SIMON', c.simon ? html`<span class="mono">${c.simon}</span>` : ''], ['Código CUPS', c.cups ? html`<span class="mono">${c.cups}</span>` : ''],
          ['Código interno', c.internal_code ? html`<span class="mono">${c.internal_code}</span>` : ''],
          ['Tarifa contratada en la fecha', c.contracted ? html`<b>${money(c.tariff_amount)}</b>` : html`<span class="pill bad">No contratado</span>${c.contract_override_reason ? html`<div class="small">Excepción: ${c.contract_override_reason}</div>` : ''}`],
          ['Vigencia aplicada', c.tariff_valid_from ? `${date(c.tariff_valid_from)} – ${c.tariff_valid_to ? date(c.tariff_valid_to) : 'abierta'}` : ''], ['Contrato', c.contract_ref],
          ['Cantidad × unitario', `${c.quantity} × ${money(c.unit_amount)}`], ['Monto reclamado', html`<b>${money(c.claimed)}</b>`]])}
        <p class="small muted">Estos datos son la fotografía del contrato al registrar la reclamación: un cambio posterior del catálogo o de la tarifa no los modifica.</p>
      </div>
    </div>

    <div class="grid two" style="margin-top:14px">
      <div class="card"><h2>Paciente y registro</h2>
        ${kv([['Paciente', c.patient_name], ['NSS / afiliado', c.member_number], ['Cédula', c.patient_doc], ['Autorización', c.authorization_number ? html`<span class="mono">${c.authorization_number}</span>` : ''],
          ['Fecha del servicio', date(c.service_date)], ['Modalidad', c.care_mode ? careMode(c.care_mode) : ''], ['Centro / clínica', c.clinic_name],
          ['Médico', c.provider_name], ...(staff ? [['Cliente', c.client_name]] : []), ['ARS', c.ars_name],
          ['Registrada por', html`${c.created_by_name || who(c.created_by)} · ${dateTime(c.created_at)}`], ['Última modificación', html`${who(c.updated_by)} · ${dateTime(c.updated_at)}`]])}
      </div>
      <div class="card"><h2>Revisión automática${checks ? html` · ${checks.ok ? html`<span class="pill ok">Lista</span>` : html`<span class="pill bad">Con pendientes</span>`}` : ''}</h2>
        ${checks ? html`<div class="list">${CHECKS.map(([k, label, inverse]) => { const good = inverse ? !checks[k] : !!checks[k]; return html`<div class="li"><span aria-hidden="true" style="font-weight:700;color:${good ? 'var(--ok)' : 'var(--bad)'}">${good ? '✓' : '✕'}</span><div class="b"><div class="t1">${label}</div>${k === 'docs' && !good ? html`<div class="t2">Faltan: ${(checks.missing_documents || []).join(', ')}</div>` : ''}</div><span class="sr-only">${good ? 'Cumple' : 'No cumple'}</span></div>`; })}</div>
          <p class="small muted">El detalle de documentos está en el <a href="#dossier">Expediente</a>.</p>` : html`<p class="small muted">No disponible.</p>`}
      </div>
    </div>

    <div class="card" id="dossier" style="margin-top:14px"></div>

    ${showMoney ? html`<div class="card" style="margin-top:14px"><h2>Resultado financiero de esta reclamación</h2>
      <div class="grid kpis">
        <div class="kpi"><div class="l">Reclamado</div><div class="v">${money(c.claimed)}</div></div>
        <div class="kpi"><div class="l">Reconocido</div><div class="v">${money(c.recognized)}</div><div class="h">Reclamado menos glosa aceptada</div></div>
        <div class="kpi"><div class="l">Pagado</div><div class="v">${money(c.paid)}</div><div class="h">${c.last_paid_on ? `Último pago ${date(c.last_paid_on)}` : 'Sin pagos'}${c.payment_refs ? ` · Ref. ${c.payment_refs}` : ''}</div></div>
        <div class="kpi"><div class="l">Glosado</div><div class="v" style="${Number(c.glosado) ? 'color:var(--bad)' : ''}">${money(c.glosado)}</div><div class="h">${c.glosa_reason || 'Sin glosa'}${Number(c.recovered) ? ` · recuperado ${money(c.recovered)}` : ''}</div></div>
        <div class="kpi"><div class="l">Saldo pendiente</div><div class="v">${radicada ? money(c.balance) : '—'}</div></div>
      </div>
      <div class="grid two" style="margin-top:10px">
        <div><h3 class="small">Reparto de pagos</h3>${pays.length ? html`<div class="list">${pays.map((p) => html`<div class="li" style="${p.superseded_at ? 'opacity:.55' : ''}"><div class="b">
          <div class="t1">${money(p.amount)} · ${p.method === 'automatico' ? 'Reparto proporcional' : p.method === 'manual' ? 'Ajuste manual' : 'Migrado'}${p.superseded_at ? ' · reemplazado' : ''}</div>
          <div class="t2">${date(p.payments?.paid_on)} · Ref. <span class="mono">${p.payments?.reference || '—'}</span>${p.reason ? ` · ${p.reason}` : ''}</div></div></div>`)}</div>` : html`<p class="small muted">Sin pagos aplicados.</p>`}</div>
        <div><h3 class="small">Glosas</h3>${glosas.length ? html`<div class="list">${glosas.map((g) => html`<div class="li"><div class="b"><div class="t1">${lnk(`#/glosas/${g.glosa_id}`, role, `${money(g.amount)} · ${g.glosa_reasons?.name || g.reason_code}`)}</div>
          <div class="t2">Notificada ${date(g.glosas?.notified_on)} · aceptada ${money(g.accepted_amount)} · recuperada ${money(g.recovered_amount)}</div></div></div>`)}</div>` : html`<p class="small muted">Sin glosas.</p>`}</div>
      </div></div>` : ''}

    <div class="grid two" style="margin-top:14px">
      <div class="card"><h2>Auditorías · ${audits.length}</h2>${audits.length ? html`<div class="list">${audits.map((a) => html`<div class="li"><div class="b">
        <div class="t1"><span class="pill ${a.result === 'validada' ? 'ok' : 'bad'}">${a.result === 'validada' ? 'Validada' : 'Con inconsistencia'}</span> ${who(a.auditor_id)} · ${dateTime(a.audited_at)}</div>
        ${a.observations ? html`<div class="t2">${a.observations}</div>` : ''}${a.errors?.length ? html`<div class="t2">Errores: ${a.errors.join('; ')}</div>` : ''}
        ${a.missing_documents?.length ? html`<div class="t2">Faltan: ${a.missing_documents.join(', ')}</div>` : ''}${a.corrections ? html`<div class="t2">Corregir: ${a.corrections}</div>` : ''}</div></div>`)}</div>` : html`<p class="small muted">Aún no se ha auditado.</p>`}
        ${discs.length ? html`<h3 class="small" style="margin-top:12px">Diferencias tarifarias</h3><div class="list">${discs.map((d) => html`<div class="li"><div class="b">
          <div class="t1"><span class="pill ${DISCREPANCY_STATUS[d.status]?.[1] || ''}">${DISCREPANCY_STATUS[d.status]?.[0] || d.status}</span> ${money(d.registered_amount)} vs. ${money(d.tariff_amount)} (${money(d.diff_amount)} · ${d.diff_pct ?? '—'} %)</div>
          <div class="t2">${d.reason || ''} · ${who(d.created_by)} ${dateTime(d.created_at)}${d.decided_at ? ` · decidió ${who(d.decided_by)} ${dateTime(d.decided_at)}: ${d.decision_note}` : ''}</div></div>
          ${d.status === 'pendiente' && can('claims.discrepancy', role) ? html`<button class="btn" data-decide="${d.id}">Decidir</button>` : ''}</div>`)}</div>` : ''}
      </div>
      <div class="card"><h2>¿Qué ocurrió? · historial</h2><div class="list timeline">${hist.map((h) => html`<div class="li"><div class="b">
        <div class="t1">${h.from_status ? `${claimStatus(h.from_status)[0]} → ` : ''}<b>${claimStatus(h.to_status)[0]}</b>${h.is_override ? html` <span class="pill warn">Excepción</span>` : ''}</div>
        <div class="t2">${dateTime(h.changed_at)} · ${who(h.changed_by)}${h.to_location ? ` · ${locs.find((l) => l.code === h.to_location)?.name || h.to_location}` : ''}${h.custodian_label ? ` · responsable: ${h.custodian_label}` : ''}</div>
        ${h.comment ? html`<div class="t2">${h.comment}</div>` : ''}</div></div>`)}</div></div>
    </div>
    ${timeline.length ? html`<div class="card" style="margin-top:14px"><h2>Línea de tiempo · ${timeline.filter((t) => t.done_at).length} de 14 hitos</h2>
      <p class="small muted">Días entre hitos y desde la captura. Los hitos que no ocurrieron (por ejemplo, sin glosa) quedan en blanco.</p>
      <div class="table-wrap"><table class="t"><thead><tr><th>#</th><th>Hito</th><th>Fecha</th><th class="n">Días desde el anterior</th><th class="n">Días desde la captura</th></tr></thead><tbody>
      ${timeline.map((t) => html`<tr style="${t.done_at ? '' : 'opacity:.5'}"><td>${t.step}</td><td>${t.done_at ? '✓ ' : '○ '}${t.label}</td><td>${t.done_at ? dateTime(t.done_at) : '—'}</td>
        <td class="n">${t.days_from_prev ?? '—'}</td><td class="n">${t.days_from_start ?? '—'}</td></tr>`)}</tbody></table></div>
      ${resubs.length ? html`<h3 class="small" style="margin-top:12px">Reenvíos</h3><div class="list">${resubs.map((r) => html`<div class="li"><div class="b"><div class="t1">De ${lnk(`#/radicaciones/${r.from?.id}`, role, r.from?.folio, 'mono')} a ${lnk(`#/radicaciones/${r.to?.id}`, role, r.to?.folio, 'mono')} · ${dateTime(r.created_at)}</div><div class="t2">${r.reason}</div></div></div>`)}</div>` : ''}
    </div>` : ''}`);
    bind();
  }

  function bind() {
    const { c, locs, trans } = S;
    renderDossier($('#dossier', box), c, role, refresh);
    box.querySelectorAll('[data-to]').forEach((b) => b.addEventListener('click', async () => {
      const { moveDialog } = await import('./claim-dialogs.js');
      try { const n = await moveDialog([id], b.dataset.to, { role, transitions: trans, locations: locs, from: c.claim_status }); if (n != null) { toast('Reclamación actualizada', 'ok'); refresh(); } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    $('#audit', box)?.addEventListener('click', async () => {
      const { auditDialog } = await import('./claim-dialogs.js');
      try { const n = await auditDialog([id], { missing: S.checks?.missing_documents || [] }); if (n != null) { toast('Auditoría registrada', 'ok'); refresh(); } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
    box.querySelectorAll('[data-decide]').forEach((b) => b.addEventListener('click', async () => {
      const { decideDialog } = await import('./claim-dialogs.js');
      const d = S.discs.find((x) => x.id === b.dataset.decide);
      try { if (await decideDialog(d)) { toast('Decisión registrada', 'ok'); refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    $('#recheck', box)?.addEventListener('click', (e) => busy(e.currentTarget, async () => {
      try { const r = await recheckContract(id); toast(r.contracted ? `Contrato encontrado: tarifa ${money(r.tariff_amount)}` : 'Sigue sin contrato vigente para esa fecha', r.contracted ? 'ok' : 'bad'); refresh(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    $('#force', box)?.addEventListener('click', async () => {
      const { formDialog, opt } = await import('../utils/ui.js');
      const { CLAIM_STATUS } = await import('../utils/constants.js');
      const to = await formDialog({ title: 'Cambio excepcional de estado', submitLabel: 'Continuar',
        body: html`<p class="small">Solo para corregir errores del proceso. Radicada y los estados financieros no se asignan manualmente; Validada se registra con “Auditar expediente”.</p>
          <div class="field"><label for="fx">Nuevo estado</label><select id="fx" name="to">${Object.entries(CLAIM_STATUS).filter(([k]) => !['radicada', 'pagada', 'pago_parcial', 'glosada', 'validada', 'con_inconsistencia', c.claim_status].includes(k)).map(([k, [l]]) => opt(k, l))}</select></div>`,
        onSubmit: async (d) => d.to });
      if (!to) return;
      const { moveDialog } = await import('./claim-dialogs.js');
      try { const n = await moveDialog([id], to, { role: '__override__', transitions: trans, locations: locs, from: c.claim_status }); if (n != null) { toast('Cambio registrado como excepción', 'ok'); refresh(); } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
    $('#print', box)?.addEventListener('click', () => window.print());
    $('#resubmit', box)?.addEventListener('click', async () => {
      const { resubmitDialog } = await import('./claim-dialogs.js');
      try { const sub = await resubmitDialog([id], c.submission_folio); if (sub) { toast('Radicación complementaria creada', 'ok'); location.hash = `#/radicaciones/${sub}`; } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  }

  refresh();
}
