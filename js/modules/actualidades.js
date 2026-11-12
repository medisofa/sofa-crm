/** SOFA · Actualidades médicas — noticias y recursos de salud para profesionales.
 *  Muestra fuentes curadas organizadas por categoría (nacional, internacional, eventos).
 *  El contenido es estático y se actualiza manualmente. Visible para todos los roles.
 *  5.32.0 · Búsqueda, destacados, recuerdo de categoría en localStorage y exportación
 *  de FUENTES/CATEGORIAS para que el widget de Inicio reutilice la misma fuente única. */
import { html, render as paint, $ } from '../utils/dom.js';

export const CATEGORIAS = [
  { key: 'all',      label: 'Todas' },
  { key: 'nac',      label: 'República Dominicana' },
  { key: 'intl',     label: 'Internacional' },
  { key: 'eventos',  label: 'Congresos y eventos' },
  { key: 'farma',    label: 'Fármacos y guías' }
];

/** Fuentes curadas. `destacada: true` marca las que se promueven con chip ⭐ en el listado
 *  y son elegibles para el widget rotativo de Inicio.
 *  `url` abre en nueva pestaña (target=_blank, rel="noopener noreferrer"). */
export const FUENTES = [
  // ── Nacionales ──────────────────────────────────────────────────────────────
  {
    cat: 'nac', titulo: 'Colegio Médico Dominicano',
    desc: 'Novedades gremiales, resoluciones, bienestar y formación continua.',
    url: 'https://colegiomedico.org.do', etiqueta: 'CMD', destacada: true
  },
  {
    cat: 'nac', titulo: 'Ministerio de Salud Pública',
    desc: 'Boletines epidemiológicos, disposiciones y protocolos nacionales.',
    url: 'https://msp.gob.do', etiqueta: 'MSP', destacada: true
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
    url: 'https://www.nejm.org', etiqueta: 'NEJM', destacada: true
  },
  {
    cat: 'intl', titulo: 'The Lancet',
    desc: 'Investigación médica y de salud pública con enfoque en políticas y equidad.',
    url: 'https://www.thelancet.com', etiqueta: 'Lancet'
  },
  {
    cat: 'intl', titulo: 'OPS / OMS — Américas',
    desc: 'Alertas epidemiológicas, guías clínicas y noticias de salud pública en la región.',
    url: 'https://www.paho.org/es', etiqueta: 'OPS', destacada: true
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
    url: 'https://colegiomedico.org.do/eventos', etiqueta: 'CMD', destacada: true
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
    url: 'https://www.uptodate.com', etiqueta: 'UpToDate', destacada: true
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

const STORAGE_KEY = 'sofa:actualidades:cat';
const normaliza = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** Aplica filtro de categoría y búsqueda libre (titulo, desc, etiqueta). Ordena alfabéticamente
 *  por título dentro de cada resultado; los destacados suben al tope cuando no hay búsqueda. */
export function filterFuentes({ cat = 'all', q = '' } = {}) {
  const qn = normaliza(q.trim());
  const base = cat === 'all' ? FUENTES : FUENTES.filter((f) => f.cat === cat);
  const filtered = qn
    ? base.filter((f) => normaliza(f.titulo).includes(qn) || normaliza(f.desc).includes(qn) || normaliza(f.etiqueta).includes(qn))
    : base;
  return [...filtered].sort((a, b) => {
    if (!qn && !!b.destacada !== !!a.destacada) return b.destacada ? 1 : -1;
    return a.titulo.localeCompare(b.titulo, 'es');
  });
}

/** Devuelve `n` fuentes destacadas intercalando categorías (nac/intl/eventos), con un orden
 *  estable por día: el mismo visitante ve lo mismo si refresca, pero al día siguiente rota.
 *  Lo usa el widget de Inicio. */
export function destacadasDelDia(n = 3, seed = new Date().toISOString().slice(0, 10)) {
  const destacadas = FUENTES.filter((f) => f.destacada);
  // Agrupo por categoría para intercalar y evitar que salgan 3 del mismo origen.
  const porCat = destacadas.reduce((acc, f) => { (acc[f.cat] ||= []).push(f); return acc; }, {});
  const prng = mulberry32(hashSeed(seed));
  Object.values(porCat).forEach((arr) => shuffle(arr, prng));
  const ordenCats = Object.keys(porCat).sort((a, b) => prng() - 0.5);
  const out = [];
  let i = 0;
  while (out.length < n) {
    const cat = ordenCats[i % ordenCats.length];
    const pool = porCat[cat];
    if (pool && pool.length) out.push(pool.shift());
    i++;
    if (i > destacadas.length * 2) break;
  }
  return out.slice(0, n);
}

function hashSeed(s) { let h = 2166136261 >>> 0; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function shuffle(arr, prng) { for (let i = arr.length - 1; i > 0; i--) { const j = Math.floor(prng() * (i + 1)); [arr[i], arr[j]] = [arr[j], arr[i]]; } return arr; }

function leerCatGuardada() {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    return CATEGORIAS.some((c) => c.key === v) ? v : 'all';
  } catch { return 'all'; }   // modo privado / storage bloqueado
}
function guardarCat(cat) { try { localStorage.setItem(STORAGE_KEY, cat); } catch { /* ok */ } }

export async function render(root) {
  root.replaceChildren();

  let catActiva = leerCatGuardada();
  let busqueda = '';

  function renderContent() {
    const fuentes = filterFuentes({ cat: catActiva, q: busqueda });
    const grid = $('#act-grid', root);
    if (!fuentes.length) {
      paint(grid, html`<div class="act-empty" role="status">
        <p>No se encontraron fuentes para «${busqueda}» en esta categoría.</p>
        <button type="button" class="i18-btn i18-sec" id="act-clear">Limpiar búsqueda</button>
      </div>`);
      $('#act-clear', grid)?.addEventListener('click', () => {
        busqueda = ''; const input = $('#act-q', root); if (input) input.value = '';
        renderContent();
      });
      return;
    }
    paint(grid, html`${fuentes.map((f) => html`
      <a class="act-card ${f.destacada ? 'destacada' : ''}" href="${f.url}" target="_blank" rel="noopener noreferrer">
        <div class="act-head">
          <span class="act-etiqueta">${f.etiqueta}</span>
          ${f.destacada ? html`<span class="act-chip-destacada" title="Fuente destacada">⭐ Destacada</span>` : ''}
        </div>
        <strong class="act-titulo">${f.titulo}</strong>
        <p class="act-desc">${f.desc}</p>
        <span class="act-link">Ir al sitio ↗</span>
      </a>`)}`);
  }

  paint(root, html`
    <div class="i18-wrap act-wrap">
      <div class="page-head">
        <div class="t">
          <h2>Actualidades médicas</h2>
          <p>Fuentes de referencia y recursos seleccionados para profesionales de la salud en la República Dominicana.</p>
        </div>
      </div>

      <div class="act-controls">
        <div class="act-tabs" role="tablist" id="act-tabs">
          ${CATEGORIAS.map((c) => html`
            <button class="act-tab ${c.key === catActiva ? 'activa' : ''}" role="tab"
              aria-selected="${c.key === catActiva ? 'true' : 'false'}"
              data-cat="${c.key}">${c.label}</button>`)}
        </div>
        <div class="act-search">
          <input id="act-q" type="search" placeholder="Buscar fuente, especialidad o institución…"
            aria-label="Buscar en actualidades" autocomplete="off">
        </div>
      </div>

      <div id="act-grid" class="act-grid"></div>

      <p class="act-pie">Los enlaces abren el sitio oficial de cada organización en una nueva pestaña. SOFA no es responsable del contenido externo.</p>
    </div>
  `);

  renderContent();

  // Pestañas de categoría — guardan la elección en localStorage para la próxima visita.
  $('#act-tabs', root).addEventListener('click', (e) => {
    const btn = e.target.closest('[data-cat]');
    if (!btn) return;
    catActiva = btn.dataset.cat;
    guardarCat(catActiva);
    $$('.act-tab', root).forEach((t) => {
      t.classList.toggle('activa', t.dataset.cat === catActiva);
      t.setAttribute('aria-selected', t.dataset.cat === catActiva ? 'true' : 'false');
    });
    renderContent();
  });

  // Buscador — debounce corto para que no repinte en cada tecla.
  let debounce;
  $('#act-q', root).addEventListener('input', (e) => {
    clearTimeout(debounce);
    debounce = setTimeout(() => { busqueda = e.target.value; renderContent(); }, 120);
  });
}

/** Alias de $$ para el módulo (evita importar desde dom.js dos veces). */
function $$(sel, root2 = document) { return [...root2.querySelectorAll(sel)]; }
