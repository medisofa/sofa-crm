/** SOFA · 3.8 · Iteración 48 · Habilitación vista por el cliente.
 *  Semáforo por área, qué falta y qué entregar; el cliente marca «lo entregué» y SOFA decide el color.
 *  Simulacro de inspección para imprimir (cliente y equipo SOFA).
 *  07/11/2026: documentos adjuntos — el cliente puede adjuntar un PDF o imagen al marcar un
 *  requisito como entregado. El archivo va al bucket "habilitation-documents" (ruta
 *  clients/{org_id}/{item_id}/{uuid}-{nombre}); la ruta queda en habilitation_items.client_storage_path. */
import { rpc, h, fmtDate, note, guarded, clientOptions, clientName } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';
import { sb } from '../supabase.js';
import { compressImage, fileProblem, safeName, sizeLabel } from '../services/documents.js';

const ST = { verde: 'Listo', amarillo: 'Corregible (menos de 15 días)', rojo: 'Requiere inversión u obra', pendiente: 'Pendiente' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const sel = h('select', { id: 'mh-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mi habilitación' : 'Habilitación vista por el cliente'),
    h('p', { class: 'i18-sub' }, 'Qué está listo, qué falta y qué debe entregar para habilitar su establecimiento ante el MISPAS.'),
    client ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'mh-org' }, 'Cliente', sel)), box));
  if (!client) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { box.replaceChildren(note(e.message, 'error')); } }

  async function load() {
    const org = client ? ctx.membership?.organization_id : sel.value;
    if (!org) { box.replaceChildren(note(client ? 'No se encontró su consultorio.' : 'Elija un cliente.')); return; }
    const d = await guarded(box, () => rpc('client_habilitation', { p_org: org }));
    if (!d) return;
    if (!d.length) { box.replaceChildren(note(client ? 'No tiene casos de habilitación con SOFA. Si lo necesita, pídalo en «Mi cuenta con SOFA».' : 'El cliente no tiene casos de habilitación.')); return; }
    box.replaceChildren(...d.map((c) => caseCard(c, org)));
  }

  function caseCard(c, orgId) {
    const k = c.counts; const pct = k.applicable ? Math.round((100 * k.verde) / k.applicable) : 0;
    const sim = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Simulacro de inspección (imprimir)');
    sim.addEventListener('click', () => simulacro(c));
    return h('section', { class: 'i18-card' }, h('h3', {}, `${c.name} · ${c.type}`),
      h('div', { class: 'i18-sub' }, `${c.folio || ''} · ${c.stage_label}${c.target_date ? ` · meta ${fmtDate(c.target_date)}` : ''}${c.license_valid_until ? ` · licencia vence ${fmtDate(c.license_valid_until)} (${c.license_days_left} días)` : ''}${c.pss_code ? ` · PSS ${c.pss_code}` : ''}`),
      h('div', { class: 'mh-bar', role: 'img', 'aria-label': `${pct} % listo` }, h('span', { style: `width:${pct}%` })),
      h('p', {}, `${pct} % listo · ${k.verde} listos · ${k.amarillo} corregibles · ${k.rojo} con obra · ${k.pendiente} pendientes${k.critical_open ? ` · ${k.critical_open} crítico(s) abiertos` : ''}`),
      h('div', { class: 'i18-bar' }, sim),
      ...(c.areas || []).map((a) => h('details', { open: a.items.some((i) => i.status !== 'verde') }, h('summary', {}, `${a.area} (${a.items.filter((i) => i.status === 'verde').length} de ${a.items.length})`),
        h('ul', { class: 'mh-items' }, a.items.map((i) => itemRow(i, orgId))))));
  }

  function itemRow(i, orgId) {
    const li = h('li', {});
    li.append(
      h('span', { class: `ecf-l ${i.status === 'verde' ? 'verde' : i.status === 'pendiente' ? 'gris' : i.status === 'amarillo' ? 'amarillo' : 'rojo'}` }, ST[i.status] || i.status), ' ',
      h('strong', {}, i.requirement),
      ...[
        i.critical ? h('span', { class: 'cs-over' }, ' · crítico') : null,
        i.hint ? h('div', { class: 'i18-sub' }, `Qué entregar: ${i.hint}`) : null,
        i.notes ? h('div', { class: 'i18-sub' }, `SOFA: ${i.notes}`) : null,
      ].filter(Boolean));

    if (i.submitted_at) {
      li.append(h('div', { class: 'i18-sub' }, `Entregado el ${fmtDate(i.submitted_at)}: ${i.client_note}`));
      if (i.storage_path && i.file_name) {
        const openBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', style: 'margin-top:4px' }, `📎 ${i.file_name}`);
        openBtn.addEventListener('click', async () => {
          openBtn.disabled = true;
          try {
            const { data, error } = await sb().storage.from('habilitation-documents').createSignedUrl(i.storage_path, 120);
            if (error || !data?.signedUrl) throw error || new Error('No se pudo generar el enlace.');
            const win = window.open('', '_blank');
            if (win) { win.opener = null; win.location.href = data.signedUrl; }
            else { li.append(note(`Abre el archivo manualmente: ${data.signedUrl}`, 'info')); }
          } catch (err) {
            li.append(note(err.message || 'No se pudo abrir el documento.', 'error'));
          } finally { openBtn.disabled = false; }
        });
        li.append(openBtn);
      }
    } else if (i.can_submit) {
      const input = h('input', { type: 'text', maxlength: '500', placeholder: 'Qué entregó y cómo', 'aria-label': `Nota de entrega para ${i.requirement}` });
      const fileInput = h('input', { type: 'file', accept: 'application/pdf,image/jpeg,image/png,image/webp', style: 'display:none', 'aria-label': `Adjuntar archivo para ${i.requirement}` });
      const fileLabel = h('label', { class: 'i18-btn i18-sec', style: 'cursor:pointer' }, '📎 Adjuntar');
      fileLabel.appendChild(fileInput);
      const fileStatus = h('span', { class: 'i18-sub', style: 'display:none' });
      fileInput.addEventListener('change', () => {
        const f = fileInput.files[0];
        if (!f) { fileStatus.style.display = 'none'; return; }
        const prob = fileProblem(f);
        fileStatus.textContent = prob ? `⚠ ${prob}` : `📎 ${f.name} · ${sizeLabel(f.size)}`;
        fileStatus.style.display = '';
      });
      const btn = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Lo entregué');
      const errBox = h('div', { 'aria-live': 'polite' });
      btn.addEventListener('click', async () => {
        const val = input.value.trim();
        if (val.length < 5) { input.focus(); errBox.replaceChildren(note('Cuente qué entregó y cómo (al menos 5 caracteres).', 'error')); return; }
        const f = fileInput.files[0];
        if (f) { const prob = fileProblem(f); if (prob) { errBox.replaceChildren(note(prob, 'error')); return; } }
        btn.disabled = true;
        try {
          let storagePath = null; let storedName = null;
          if (f) {
            const ready = await compressImage(f);
            const path = `clients/${orgId}/${i.id}/${crypto.randomUUID()}-${safeName(ready.name)}`;
            const { error: upErr } = await sb().storage.from('habilitation-documents').upload(path, ready, { contentType: ready.type, upsert: false, cacheControl: '3600' });
            if (upErr) throw upErr;
            storagePath = path; storedName = ready.name;
          }
          await rpc('habilitation_item_submit', { p_item: i.id, p_note: val, p_storage_path: storagePath, p_file_name: storedName });
          await load();
        } catch (err) { btn.disabled = false; errBox.replaceChildren(note(err.message || 'No se pudo registrar la entrega.', 'error')); }
      });
      li.append(h('div', { class: 'i18-actions' }, input, fileLabel, fileStatus, btn), errBox);
    }
    return li;
  }

  async function simulacro(c) {
    const w = openPrint();
    try {
      const s = await rpc('habilitation_mock_inspection', { p_case: c.id });
      const ok = fillPrint(w, `Simulacro de inspección · ${s.name}`, `${s.type} · ${s.stage_label} · ${s.folio || ''} · ${fmtDate(s.generated_on)}`, [
        s.unconfirmed_catalog ? { warn: 'Lista base de SOFA: confirme los requisitos vigentes con el MISPAS antes de la inspección.' } : null,
        { p: 'Recorra el establecimiento con esta lista como lo haría el inspector. Marque cada punto y anote lo que falte.' },
        { table: { head: ['✓', 'Área', 'Requisito', 'Crítico', 'Estado actual', 'Evidencia'], rows: s.items.map((i) => ['☐', i.area, i.requirement, i.critical ? 'Sí' : '', ST[i.status] || i.status, i.hint || '']) } }].filter(Boolean));
      if (!ok) box.prepend(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error'));
    } catch (e) { if (w) w.close(); box.prepend(note(e.message, 'error')); }
  }

  sel.addEventListener('change', load);
  await load();
}
export default render;
