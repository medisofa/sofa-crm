"""Synthetic fixture database only; proves stale tabs cannot overwrite checkpoints."""
import subprocess,json,concurrent.futures
base=['docker','exec','-i','sofa-reminder-tests','psql','-U','postgres','-d','intake_drafts','-v','ON_ERROR_STOP=1','-At']
uid='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';draft='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
def sql(s):return subprocess.run(base,input=s,text=True,capture_output=True)
def save(version,name):
 p=json.dumps(dict(schema=1,source_name=name,scope_ids=['11111111-1111-4111-8111-111111111111'],rows=[dict(raw={'__row':2,'Paciente *':name})]))
 return sql(f"begin;set local role authenticated;select set_config('request.jwt.claim.sub','{uid}',true);select public.google_intake_drafts_v1('save','{draft}',{version},'{p}','{uid}');commit;")
r=save(0,'inicial.csv');assert r.returncode==0,r.stderr
with concurrent.futures.ThreadPoolExecutor(2)as executor:results=list(executor.map(lambda name:save(1,name),['primera.csv','segunda.csv']))
assert sorted(r.returncode for r in results)==[0,3],[(r.returncode,r.stderr)for r in results]
assert any('otra pestaña' in r.stderr for r in results)
r=sql(f"select revision from app.google_intake_drafts where id='{draft}';select count(*)from app.google_intake_draft_events where draft_id='{draft}';")
assert r.stdout.strip().splitlines()==['2','2'],r.stdout
print('PASS: dos sesiones, un checkpoint aceptado, otro rechazado por versión; sin sobrescritura ni evento duplicado.')
