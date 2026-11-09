import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
 const page = await browser.newPage(); const errors = [];
 page.on('pageerror', e => errors.push(e.message));
 await page.route('**/*', async route => {
  const path = new URL(route.request().url()).pathname;
  const mocks = {
   '/': '<main></main>',
   '/js/modules/opening-history.js': 'export const OPENING_ROLES=[]; export function mountOpeningHistoryPicker() {}',
   '/js/modules/clients.js': 'export const pager=()=>"";',
   '/js/utils/diag-log.js': 'export function logDiag() {}',
   '/js/supabase.js': 'export const sb=()=>({});',
   '/js/services/claims.js': `
    export async function listClaims(args) { window.calls.push({...args}); return {data:[],count:0}; }
    export async function claimCounts() { return [{claim_status:'en_captura'},{claim_status:'en_validacion'}]; }
    export async function claimLocations() {return [];}
    export async function claimTransitions() {return [];}
    export async function captureProviders() {return [{id:'doctor',full_name:'Médico ficticio'}];}
    export async function activeArs() {return [{id:'ars',name:'ARS ficticia'}];}
    export async function claimDuplicateCandidates() {return [];}
    export async function reviewClaimDuplicate() {return null;}`
  };
  if (path in mocks) return route.fulfill({ contentType: path === '/' ? 'text/html' : 'text/javascript', body: mocks[path] });
  return route.fulfill({ contentType:'text/javascript',body:await readFile(new URL(path.slice(1),root)) });
 });
 await page.goto('http://127.0.0.1:8881/');
 await page.evaluate(async()=>{window.calls=[]; const {render}=await import('/js/modules/claims.js');await render(document.querySelector('main'),{role:'admin'});});
 await page.locator('#k button[data-g="captura"]').waitFor();
 await page.locator('#fp').selectOption('doctor');
 await page.locator('#fa').selectOption('ars');
 await page.locator('#ff').fill('2026-09-01');
 await page.locator('#ft').fill('2026-10-01');
 for(const group of ['captura','custodia','ars','atencion']) {
  await page.locator('#fs').selectOption('en_validacion');
  const n=await page.evaluate(()=>calls.length);
  await page.locator(`#k button[data-g="${group}"]`).click();
  await page.waitForFunction(n=>calls.length>n,n);
  const last=await page.evaluate(()=>calls.at(-1));
  assert.equal(last.group,group); assert.equal(last.status,''); assert.equal(last.page,0);
  assert.equal(last.providerId,'doctor'); assert.equal(last.arsId,'ars');
  assert.equal(last.from,'2026-09-01'); assert.equal(last.to,'2026-10-01');
  assert.equal(await page.locator(`#tabs [data-g="${group}"]`).getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator(`#k [data-g="${group}"]`).getAttribute('aria-pressed'),'true');
 }
 await page.locator('#funnel [data-g="cobro"]').click();
 assert.equal(await page.locator('#tabs [data-g="cobro"]').getAttribute('aria-pressed'),'true');
 await page.locator('#k [data-g="captura"]').focus(); await page.keyboard.press('Enter');
 assert.equal(await page.locator('#tabs [data-g="captura"]').getAttribute('aria-pressed'),'true');
 await page.locator('#k [data-g="ars"]').focus(); await page.keyboard.press('Space');
 assert.equal(await page.locator('#tabs [data-g="ars"]').getAttribute('aria-pressed'),'true');
 assert.deepEqual(errors,[]);
 console.log('PASS: KPI and flow filters, keyboard activation, active state, status reset and preserved filters');
} finally {await browser.close();}
