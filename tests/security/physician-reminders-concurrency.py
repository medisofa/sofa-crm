"""Run only against the isolated fixture database in sofa-reminder-tests."""
import subprocess, concurrent.futures, json
base=['docker','exec','-i','sofa-reminder-tests','psql','-U','postgres','-d','reminder_final','-v','ON_ERROR_STOP=1','-At']
org='11111111-1111-4111-8111-111111111111'
uid='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
id_='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
def sql(s): return subprocess.run(base,input=s,text=True,capture_output=True)
def call(title,version):
 data=json.dumps(dict(id=id_,version=version,kind='note',title=title))
 return sql(f"begin;set local role authenticated;select set_config('request.jwt.claim.sub','{uid}',true);select public.physician_reminders_v1('{org}','save','{data}');commit;")
r=sql('update app.physician_reminder_settings set enabled=true;');assert r.returncode==0,r.stderr
r=call('Inicial',0);assert r.returncode==0,r.stderr
with concurrent.futures.ThreadPoolExecutor(2) as executor:
 results=list(executor.map(lambda title:call(title,1),['Cambio A','Cambio B']))
assert sorted(r.returncode for r in results)==[0,3],[(r.returncode,r.stderr) for r in results]
assert any('otra ventana' in r.stderr for r in results)
r=sql(f"select version from app.physician_reminders where id='{id_}';select count(*) from app.physician_reminder_events where reminder_id='{id_}';")
assert r.stdout.strip().splitlines()==['2','2'],r.stdout
print('PASS: dos sesiones concurrentes, una edición aceptada, otra rechazada y dos eventos de auditoría.')
