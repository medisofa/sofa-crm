"""Only the isolated claims_review fixture database; no production access."""
import subprocess,json,concurrent.futures,os
base=['docker','exec','-i','sofa-reminder-tests','psql','-U','postgres','-d',os.getenv('SOFA_INTAKE_TEST_DB','claims_review'),'-v','ON_ERROR_STOP=1','-At']
def sql(s):return subprocess.run(base,input=s,text=True,capture_output=True)
data=json.dumps(dict(provider='33333333-3333-4333-8333-333333333333',ars='55555555-5555-4555-8555-555555555555',procedure='66666666-6666-4666-8666-666666666666',service_date='2026-01-10',patient='Prueba aislada',member='CONCUR',authorization='AU-CONCUR',amount=750,expected_tariff=850,discrepancy_reason='Acuerdo individual autorizado',review_confirmed=True))
def call(key):return sql("begin;set local role authenticated;select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);select set_config('test.role','billing',true);select public.google_intake_review_v1('"+key+"','commit','"+data+"');commit;")
with concurrent.futures.ThreadPoolExecutor(2) as executor:results=list(executor.map(call,['concurrent-a','concurrent-b']))
assert sorted(r.returncode for r in results)==[0,3],[(r.returncode,r.stderr) for r in results]
assert any('duplicada' in r.stderr for r in results)
r=sql('select count(*) from public.service_lines;select count(*) from app.google_intake_commits;select count(*) from public.audit_log;')
assert r.stdout.strip().splitlines()==['1','1','2'],r.stdout
print('PASS: dos importaciones simultáneas, una reclamación creada y la otra bloqueada como duplicada; bitácora atómica.')
