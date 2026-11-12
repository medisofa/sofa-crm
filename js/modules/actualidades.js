/** SOFA · Actualidades médicas — noticias y recursos de salud para profesionales.
 *  Muestra fuentes curadas organizadas por categoría (nacional, internacional, eventos).
 *  El contenido es estático y se actualiza manualmente. Visible para todos los roles. */
import { html, render as paint, $, raw } from '../utils/dom.js';

const CATEGORIAS = [
  { key: 'all',      label: 'Todas' },
  { key: 'nac',      label: 'República Dominicana' },
  { key: 'intl',     label: 'Internacional' },
  { key: 'eventos',  label: 'Congresos y eventos' },
  { key: 'farma',    label: 'Fármacos y guías' }
];

/** Fuentes curadas. url abre en nueva pestaña (target=_blank). */
const FUENTES = [
  // ── Nacionales ──────────────────────────────────────────────────────────────
  {
    cat: 'nac', titulo: 'Colegio Médico Dominicano',
    desc: 'Novedades gremiales, resoluciones, bienestar y formación continua.',
    url: 'https://colegiomedico.org.do', etiqueta: 'CMD'
  },
  {
    cat: 'nac', titulo: 'Ministerio de Salud Pública',
    desc: 'Boletines epidemiológicos, disposiciones y protocolos nacionales.',
    url: 'https://msp.gob.do', etiqueta: 'MSP'
  },
  {
    cat: 'nac', titulo: 'PROMESE / CAL',
    desc: 'Farmacopea oficial, disponibilidad de medicamentos esenciales y convocatorias.',
    url: 'https://promesecal.gob.do', etiqueta: 'PROMESE'
  },
  {
    cat: 'nac', titulo: 'SENASA',
    desc: 'Novedades del seguro nacional de salud: cobertura, procedimientos y resoluciones.',
    url: 'https://senasa.gob.do', etiqueta: 'SENASA'
  },
  {
    cat: 'nac', titulo: 'ARS Humano',
    desc: 'Actualizaciones de tarifarios, habilitación de servicios y circulares.',
    url: 'https://www.humano.com.do', etiqueta: 'ARS'
  },
  {
    cat: 'nac', titulo: 'ARS Universal',
    desc: 'Novedades de cobertura, PSS y procedimientos de autorización.',
    url: 'https://www.universalrd.com', etiqueta: 'ARS'
  },
  // ── Internacionales ─────────────────────────────────────────────────────────
  {
    cat: 'intl', titulo: 'New England Journal of Medicine',
    desc: 'Artículos originales, revisiones clínicas y editoriales de impacto global.',
    url: 'https://www.nejm.org', etiqueta: 'NEJM'
  },
  {
    cat: 'intl', titulo: 'The Lancet',
    desc: 'Investigación médica y de salud pública con enfoque en políticas y equidad.',
    url: 'https://www.thelancet.com', etiqueta: 'Lancet'
  },
  {
    cat: 'intl', titulo: 'OPS / OMS — Américas',
    desc: 'Alertas epidemiológicas, guías clínicas y noticias de salud pública en la región.',
    url: 'https://www.paho.org/es', etiqueta: 'OPS'
  },
  {
    cat: 'intl', titulo: 'Medscape en Español',
    desc: 'Noticias médicas, CME y guías clínicas actualizadas en castellano.',
    url: 'https://espanol.medscape.com', etiqueta: 'Medscape'
  },
  {
    cat: 'intl', titulo: 'BMJ (British Medical Journal)',
    desc: 'Investigación clínica, políticas de salud y práctica basada en evidencia.',
    url: 'https://www.bmj.com', etiqueta: 'BMJ'
  },
  {
    cat: 'intl', titulo: 'PubMed / MEDLINE',
    desc: 'Base de datos de literatura biomédica de la Biblioteca Nacional de Medicina de EE.UU.',
    url: 'https://pubmed.ncbi.nlm.nih.gov', etiqueta: 'PubMed'
  },
  // ── Congresos y eventos ─────────────────────────────────────────────────────
  {
    cat: 'eventos', titulo: 'Congreso Médico Nacional — CMD',
    desc: 'Agenda de los congresos, simposios y jornadas científicas organizados por el CMD.',
    url: 'https://colegiomedico.org.do/eventos', etiqueta: 'CMD'
  },
  {
    cat: 'eventos', titulo: 'ALAD — Congreso de Diabetes',
    desc: 'Asociación Latinoamericana de Diabetes: congreso anual y calendarios de formación.',
    url: 'https://www.alad-latinoamerica.org', etiqueta: 'ALAD'
  },
  {
    cat: 'eventos', titulo: 'Interamerican Heart Foundation',
    desc: 'Eventos y guías de cardiología para Latinoamérica y el Caribe.',
    url: 'https://www.iahf.org', etiqueta: 'IAHF'
  },
  {
    cat: 'eventos', titulo: 'AHA — American Heart Association',
    desc: 'Congresos, guías clínicas de cardiología y formación en RCP.',
    url: 'https://www.heart.org', etiqueta: 'AHA'
  },
  // ── Fármacos y guías ────────────────────────────────────────────────────────
  {
    cat: 'farma', titulo: 'Vademécum Dominicano (FEDOMEDICA)',
    desc: 'Referencia de medicamentos disponibles en el país, dosis e interacciones.',
    url: 'https://www.fedomedica.org', etiqueta: 'RD'
  },
  {
    cat: 'farma', titulo: 'UpToDate',
    desc: 'Guías clínicas y recomendaciones basadas en evidencia por especialidad.',
    url: 'https://www.uptodate.com', etiqueta: 'UpToDate'
  },
  {
    cat: 'farma', titulo: 'Cochrane Library en Español',
    desc: 'Revisiones sistemáticas y metaanálisis para decisiones clínicas.',
    url: 'https://www.cochranelibrary.com', etiqueta: 'Cochrane'
  },
  {
    cat: 'farma', titulo: 'Drugs.com',
    desc: 'Información de medicamentos, interacciones y efectos adversos.',
    url: 'https://www.drugs.com', etiqueta: 'Drugs'
  }
];

export async function render(root) {
  root.replaceChildren();

  let catActiva = 'all';

  function renderContent() {
    const fuentes = catActiva === 'all' ? FUENTES : FUENTES.filter((f) => f.cat === catActiva);
    paint($('#act-grid', root), html`
      ${fuentes.map((f) => html`
        <a class="act-card" href="${f.url}" target="_blank" rel="noopener noreferrer">
          <span class="act-etiqueta">${f.etiqueta}</span>
          <strong class="act-titulo">${f.titulo}</strong>
          <p class="act-desc">${f.desc}</p>
          <span class="act-link">Ir al sitio ↗</span>
        </a>`)}
    `);
  }

  paint(root, html`
    <div class="i18-wrap act-wrap">
      <div class="page-head">
        <div class="t">
          <h2>Actualidades médicas</h2>
          <p>Fuentes de referencia y recursos seleccionados para profesionales de la salud en la República Dominicana.</p>
        </div>
      </div>

      <div class="act-tabs" role="tablist" id="act-tabs">
        ${CATEGORIAS.map((c) => html`
          <button class="act-tab ${c.key === catActiva ? 'activa' : ''}" role="tab"
            aria-selected="${c.key === catActiva ? 'true' : 'false'}"
            data-cat="${c.key}">${c.label}</button>`)}
      </div>

      <div id="act-grid" class="act-grid"></div>

      <p class="act-pie">Los enlaces abren el sitio oficial de cada organización en una nueva pestaña. SOFA no es responsable del contenido externo.</p>
    </div>
  `);

  renderContent();

  // eventos de las pestañas
  $('#act-tabs', root).addEventListener('click', (e) => {
    const btn = e.target.closest('[data-cat]');
    if (!btn) return;
    catActiva = btn.dataset.cat;
    $$('.act-tab', root).forEach((t) => {
      t.classList.toggle('activa', t.dataset.cat === catActiva);
      t.setAttribute('aria-selected', t.dataset.cat === catActiva ? 'true' : 'false');
    });
    renderContent();
  });
}

/** Alias de $$ para el módulo (evita importar desde dom.js dos veces). */
function $$(sel, root2 = document) { return [...root2.querySelectorAll(sel)]; }
