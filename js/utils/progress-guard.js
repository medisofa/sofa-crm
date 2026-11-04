/** Registered screens save their private drafts before an application update. */
const guards=new Set();
export function registerProgressGuard(root,guard){
  const entry={root,...guard};guards.add(entry);
  return ()=>guards.delete(entry);
}
function relevant(){
  for(const entry of guards)if(!entry.root.isConnected&&!entry.pending())guards.delete(entry);
  return [...guards];
}
export async function prepareProgressForUpdate(){
  for(const entry of relevant())await entry.flush();
  if(relevant().some(entry=>entry.pending()))throw Error('Hay una acción o un guardado pendiente. Espere a que termine antes de actualizar.');
}
window.addEventListener('beforeunload',event=>{
  if(relevant().some(entry=>entry.pending())){event.preventDefault();event.returnValue='';}
});
