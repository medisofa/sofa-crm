import assert from 'node:assert/strict';import {readFile}from'node:fs/promises';
const calls=[];globalThis.__opsSb=()=>({rpc:async(name,args)=>{calls.push({name,args});return {data:name==='bank_workspace_claims'?[{line_id:'claim',authorization_number:'00123',applied:75}]:[{old_number:null,new_number:'00123',reason:'QA correction'}]};}});
async function load(path){const source=(await readFile(new URL(path,import.meta.url),'utf8')).replace(/^import .*;\n/gm,'');return import('data:text/javascript;base64,'+Buffer.from('const sb=()=>globalThis.__opsSb();\n'+source).toString('base64'));}
const bank=await load('../js/services/reconciliation-workspace.js');const history=await load('../js/services/claim-authorization.js');
const results=await bank.bankWorkspaceClaims({organizationId:'org',paymentId:'pay'});assert.equal(results[0].authorization_number,'00123');
assert.deepEqual(calls.at(-1),{name:'bank_workspace_claims',args:{p_org:'org',p_payment:'pay',p_search:null}});
await bank.bankWorkspaceClaims({organizationId:'org',search:' 00123 '});assert.deepEqual(calls.at(-1),{name:'bank_workspace_claims',args:{p_org:'org',p_payment:null,p_search:'00123'}});
assert.equal((await history.listClaimAuthorizationHistory('claim'))[0].new_number,'00123');assert.deepEqual(calls.at(-1),{name:'claim_authorization_history',args:{p_line:'claim'}});
assert.ok(calls.every(c=>['bank_workspace_claims','claim_authorization_history'].includes(c.name)),'Consultas no escriben ni asocian pagos');
globalThis.__opsSb=()=>({rpc:async()=>({error:new Error('Read denied')})});await assert.rejects(()=>bank.bankWorkspaceClaims({organizationId:'org',search:'00123'}),/Read denied/);await assert.rejects(()=>history.listClaimAuthorizationHistory('claim'),/Read denied/);
console.log('PASS: consultas por cliente/pago/autorización e historial, ceros iniciales y errores explícitos; sin escrituras.');
