// Pruebas de interfaz 1.7.6: lector .xlsx, importación por import_claims y borrado de lotes por delete_submission
import { chromium } from 'playwright';
import path from 'node:path';
const FX = path.resolve(process.argv[2]);
const URL = 'http://127.0.0.1:8765/test.html';
let pass = 0, fail = 0;
const t = (name, ok, extra = '') => { if (ok) { pass++; console.log(`APROBADA  ${name}`); } else { fail++; console.log(`FALLÓ     ${name} ${extra}`); } };

const browser = await chromium.launch();
const page = await browser.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(URL);

// ---------- 1. Lector .xlsx
const readFx = (f) => page.evaluate(async (u) => { const m = await import('./js/utils/xlsx-lite.js'); const b = await (await fetch(u)).arrayBuffer(); try { return await m.readXlsx(b); } catch (e) { return { error: e.message }; } }, f);
// los archivos se sirven copiándolos dentro de app/fx
const xo = await readFx('fx/openpyxl.xlsx');
t('openpyxl: 4 filas (sin la vacía)', Array.isArray(xo) && xo.length === 4, JSON.stringify(xo));
t('openpyxl: encabezado con tildes', xo[0]?.[0] === 'Médico' && xo[0]?.[8] === 'Autorización');
t('openpyxl: fecha de Excel → AAAA-MM-DD', xo[1]?.[5] === '2026-10-05', xo[1]?.[5]);
t('openpyxl: fecha y hora → AAAA-MM-DD', xo[3]?.[5] === '2026-09-30', xo[3]?.[5]);
t('openpyxl: fecha escrita como texto se conserva', xo[2]?.[5] === '03/10/2026');
t('openpyxl: número sin decimales falsos', xo[1]?.[11] === '1500' && xo[3]?.[11] === '1234.5', `${xo[1]?.[11]} ${xo[3]?.[11]}`);
t('openpyxl: NSS numérico como texto', xo[2]?.[7] === '987654321');
t('openpyxl: celdas vacías en medio quedan vacías', xo[2]?.[2] === '' && xo[2]?.[3] === '2501');
const xl = await readFx('fx/lo/lo_src.xlsx');
t('LibreOffice: mismas filas y fecha', Array.isArray(xl) && xl.length === 4 && xl[1]?.[5] === '2026-10-05' && xl[0]?.[6] === 'Paciente', JSON.stringify(xl?.[1]));
const bad = await readFx('fx/bad.xlsx');
t('Archivo que no es .xlsx: mensaje que dice qué hacer', /Súbalo como \.xlsx o CSV/.test(bad.error || ''), JSON.stringify(bad));
const old = await readFx('fx/old.xlsx');
t('Excel antiguo .xls: pide guardarlo como .xlsx', /guárdelo como \.xlsx/.test(old.error || ''), JSON.stringify(old));

// ---------- 2. Mapeo de columnas
const map = await page.evaluate(async () => {
  const m = await import('./js/modules/claims-import.js');
  const byHeader = m.toClaimRows([['Fecha de atención', 'Prestador', 'Aseguradora', 'CUPS', 'Nombre paciente', 'No. Afiliado', 'Monto'], ['2026-10-01', 'Dra. Ana', 'Humano', '890201', 'Juan', '123', '1,500']]);
  const byOrder = m.toClaimRows(m.splitText('Dra. Ana\tHumano\tCONSULTA\t\t\t01/10/2026\tJuan Pérez\t123\tA1'));
  const csv = m.toClaimRows(m.splitText('Médico;ARS;Servicio;Fecha;Paciente;NSS;Notas\n"Pérez; Ana";Humano;RX;01/10/2026;Juan;123;"dijo ""hola"""'));
  return { byHeader, byOrder, csv };
});
t('Encabezados por sinónimo (Prestador, Aseguradora, No. Afiliado…)', map.byHeader.length === 1 && map.byHeader[0].medico === 'Dra. Ana' && map.byHeader[0].ars === 'Humano' && map.byHeader[0].nss === '123' && map.byHeader[0].fecha === '2026-10-01' && map.byHeader[0].monto === '1,500', JSON.stringify(map.byHeader));
t('Sin encabezado: orden de la plantilla', map.byOrder[0].medico === 'Dra. Ana' && map.byOrder[0].fecha === '01/10/2026' && map.byOrder[0].autorizacion === 'A1', JSON.stringify(map.byOrder));
t('CSV con ; entre comillas y comillas dobles', map.csv[0].medico === 'Pérez; Ana' && map.csv[0].notas === 'dijo "hola"', JSON.stringify(map.csv));
t('Todas las claves que espera import_claims', Object.keys(map.byOrder[0]).join() === 'medico,ars,servicio,simon,cups,fecha,paciente,nss,autorizacion,cedula,modo,monto,cantidad,clinica,notas');

// ---------- 3. Diálogo de importación
await page.evaluate(() => {
  window.__calls = [];
  window.__mode = 'errores';
  window.__rpcImpl = async (name, args) => {
    if (name !== 'import_claims') return { data: null, error: { message: 'rpc inesperada ' + name } };
    if (args.p_commit) return { data: { total: args.p_rows.length, valid: args.p_rows.length, errors: [], rows: [], imported: args.p_rows.length }, error: null };
    if (window.__mode === 'errores') return { data: { total: 3, valid: 2, errors: [{ row: 2, errors: ['ARS inexistente: SENASA'], data: args.p_rows[1] }], rows: [{ row: 1, provider: 'Dra. Ana Pérez', ars: 'ARS Humano', service: 'Consulta', service_date: '2026-10-05', patient_name: 'Juan', amount: 1500 }] }, error: null };
    return { data: { total: 3, valid: 3, errors: [], rows: [{ row: 1, provider: 'Dra. Ana Pérez', ars: 'ARS Humano', service: 'Consulta', service_date: '2026-10-05', patient_name: 'Juan', amount: null }] }, error: null };
  };
  window.__dlg = import('./js/modules/claims-import.js').then((m) => m.importClaimsDialog()).then((r) => { window.__dlgResult = r; });
});
await page.waitForSelector('dialog #ci_file');
await page.setInputFiles('dialog #ci_file', path.join(FX, 'openpyxl.xlsx'));
await page.waitForFunction(() => /3 filas/.test(document.querySelector('#ci_cnt').textContent));
t('Archivo .xlsx leído: 3 filas de datos', true);
await page.click('dialog button[type=submit]');
await page.waitForTimeout(300);
t('Importar sin vista previa no llama a la base', window_calls(await page.evaluate(() => window.__calls)).length === 0);
await page.click('#ci_check');
await page.waitForSelector('#ci_rep .note');
const calls1 = await page.evaluate(() => window.__calls);
t('Vista previa llama import_claims con p_commit = false', calls1.length === 1 && calls1[0].args.p_commit === false && calls1[0].args.p_rows.length === 3);
t('Las filas viajan con las claves de la base y la fecha convertida', calls1[0]?.args.p_rows[0].medico === 'Dra. Ana Pérez' && calls1[0]?.args.p_rows[0].fecha === '2026-10-05' && calls1[0]?.args.p_rows[1].simon === '2501', JSON.stringify(calls1[0]?.args.p_rows[0]));
t('Muestra la fila con error y qué corregir', (await page.textContent('#ci_rep')).includes('ARS inexistente: SENASA'));
await page.click('dialog button[type=submit]');
await page.waitForTimeout(300);
t('Con errores no se importa (no hay llamada con p_commit = true)', (await page.evaluate(() => window.__calls)).every((c) => c.args.p_commit === false));
await page.evaluate(() => { window.__mode = 'ok'; });
await page.click('#ci_check');
await page.waitForFunction(() => /0 con errores/.test(document.querySelector('#ci_rep').textContent));
t('Sin monto muestra "Tarifa contratada"', (await page.textContent('#ci_rep')).includes('Tarifa contratada'));
await page.click('dialog button[type=submit]');
await page.waitForFunction(() => window.__dlgResult !== undefined);
const calls2 = await page.evaluate(() => window.__calls);
const res = await page.evaluate(() => window.__dlgResult);
t('Importar llama import_claims con p_commit = true y cierra', calls2.at(-1).args.p_commit === true && res?.imported === 3 && !(await page.$('dialog')));

// Pegado con más de 2,000 filas: se frena antes de llamar
await page.evaluate(() => { window.__calls = []; window.__dlgResult = undefined; window.__dlg = import('./js/modules/claims-import.js').then((m) => m.importClaimsDialog()).then((r) => { window.__dlgResult = r; }); });
await page.waitForSelector('dialog #ci_paste');
await page.fill('#ci_paste', Array.from({ length: 2001 }, (_, i) => `Dra. Ana\tHumano\tRX\t\t\t01/10/2026\tPaciente ${i}\t${i}\tA`).join('\n'));
await page.click('#ci_check');
await page.waitForTimeout(300);
t('Más de 2,000 filas: aviso y no llama a la base', (await page.evaluate(() => window.__calls)).length === 0 && /divídalo|divida/.test(await page.textContent('dialog')));
await page.setInputFiles('dialog #ci_file', path.join(FX, 'old.xlsx'));
await page.waitForTimeout(300);
t('Archivo .xls antiguo en el diálogo: mensaje en el campo', /guárdelo como \.xlsx/.test(await page.textContent('dialog')));
await page.click('dialog [data-cancel]');
await page.waitForFunction(() => window.__dlgResult !== undefined);
t('Cancelar devuelve null', (await page.evaluate(() => window.__dlgResult)) === null);

// ---------- 4. Borrar lote
await page.evaluate(() => {
  window.__calls = []; window.__storage = []; window.__delResult = undefined;
  window.__rpcImpl = async (name, args) => {
    if (name !== 'delete_submission') return { data: null, error: { message: 'rpc inesperada' } };
    return { data: { folio: 'RAD-2026-0006', claims: 2, files: [{ bucket: 'claim-documents', path: 'org/a.pdf' }, { bucket: 'claim-documents', path: 'org/b.pdf' }] }, error: null };
  };
  import('./js/modules/submission.js').then((m) => m.deleteSubmissionDialog('sub-1', 'RAD-2026-0006', 2)).then((r) => { window.__delResult = r; });
});
await page.waitForSelector('dialog #dl_c');
t('El diálogo advierte cuántas reclamaciones se borran', /2 reclamaciones/.test(await page.textContent('dialog')));
await page.fill('#dl_r', 'corto');
await page.fill('#dl_c', 'rad-2026-0006');
await page.click('dialog button[type=submit]');
await page.waitForTimeout(300);
const txt = await page.textContent('dialog');
t('Motivo corto y folio mal escrito: no llama a la base y dice qué hacer', (await page.evaluate(() => window.__calls)).length === 0 && /mínimo 10/.test(txt) && /Escriba exactamente RAD-2026-0006/.test(txt));
await page.fill('#dl_r', 'Lote cargado dos veces por error');
await page.fill('#dl_c', 'RAD-2026-0006');
await page.click('dialog button[type=submit]');
await page.waitForFunction(() => window.__delResult !== undefined);
const dc = await page.evaluate(() => ({ calls: window.__calls, st: window.__storage, r: window.__delResult }));
t('Llama delete_submission con id, motivo y folio', dc.calls.length === 1 && dc.calls[0].args.p_submission === 'sub-1' && dc.calls[0].args.p_reason === 'Lote cargado dos veces por error' && dc.calls[0].args.p_confirm === 'RAD-2026-0006');
t('Quita del almacenamiento los archivos que devolvió la base', dc.st.length === 1 && dc.st[0].bucket === 'claim-documents' && dc.st[0].paths.length === 2 && dc.r.filesLeft === 0);

// Error de la base (lote con pagos): se muestra dentro del diálogo, sin cerrarlo
await page.evaluate(() => {
  window.__delResult = undefined;
  window.__rpcImpl = async () => ({ data: null, error: { code: '23514', message: 'El lote tiene pagos registrados: no se borra' } });
  import('./js/modules/submission.js').then((m) => m.deleteSubmissionDialog('sub-2', 'RAD-2026-0007', 1)).then((r) => { window.__delResult = r; });
});
await page.waitForSelector('dialog #dl_c');
await page.fill('#dl_r', 'Lote cargado dos veces por error');
await page.fill('#dl_c', 'RAD-2026-0007');
await page.click('dialog button[type=submit]');
await page.waitForSelector('dialog .fd-msg .note');
t('Rechazo de la base se muestra en el diálogo', (await page.textContent('dialog .fd-msg')).includes('El lote tiene pagos registrados'));
await page.click('dialog [data-cancel]');
await page.waitForFunction(() => window.__delResult === null && !document.querySelector('dialog'));
t('Cancelar el borrado devuelve null', true);

// Archivos que no se pudieron borrar
await page.evaluate(() => {
  window.__storageError = true; window.__delResult3 = undefined;
  window.__rpcImpl = async () => ({ data: { folio: 'RAD-1', claims: 1, files: [{ bucket: 'claim-documents', path: 'x.pdf' }] }, error: null });
  import('./js/modules/submission.js').then((m) => m.deleteSubmissionDialog('s', 'RAD-1', 1)).then((r) => { window.__delResult3 = r; });
});
await page.waitForSelector('dialog #dl_c');
await page.fill('#dl_r', 'Lote cargado dos veces por error'); await page.fill('#dl_c', 'RAD-1');
await page.click('dialog button[type=submit]');
await page.waitForFunction(() => window.__delResult3 !== undefined);
t('Si el almacenamiento falla, se informa cuántos archivos quedaron', (await page.evaluate(() => window.__delResult3?.filesLeft)) === 1);

t('Sin errores de JavaScript en la página', errors.length === 0, errors.join(' | '));
await page.screenshot({ path: path.join(FX, '..', 'ultimo.png') });
await browser.close();
console.log(`\n${pass} de ${pass + fail} pruebas aprobadas`);
process.exit(fail ? 1 : 0);
function window_calls(c) { return c; }
