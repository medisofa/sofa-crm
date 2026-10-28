"""Run only after fixture + candidate + regression in an owned disposable container."""
import concurrent.futures
import json
import re
import subprocess
import sys

container = sys.argv[1]
if not re.fullmatch(r"sofa-user-repair-qa(?:-[a-z0-9-]+)?", container):
    raise SystemExit("Use a dedicated sofa-user-repair-qa container")

def sql(source):
    return subprocess.run(
        ["docker", "--host=unix:///var/run/docker.sock", "exec", "-i", container,
         "psql", "-X", "-qAt", "-U", "postgres", "-v", "ON_ERROR_STOP=1"],
        input=source, text=True, capture_output=True,
    )

marker = sql("SELECT value FROM public.sofa_user_repair_fixture_marker;")
assert marker.returncode == 0 and marker.stdout.strip() == "synthetic-user-repair-only"
claims = "SET ROLE authenticated; SET request.jwt.claims='" + json.dumps({
    "sub": "00000000-0000-4000-8000-000000000001", "aal": "aal2"
}) + "';"
preview = sql(claims + "SELECT public.admin_user_repair_preview('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000101')->>'expected';")
assert preview.returncode == 0, preview.stderr
token = preview.stdout.strip().splitlines()[-1]
assert re.fullmatch(r"[a-f0-9]{32}", token)
statement = claims + "SELECT public.admin_repair_user_access('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000101','Prueba de concurrencia sintética','qa-3@example.test','" + token + "');"
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(sql, [statement, statement]))
assert sorted(r.returncode for r in results) == [0, 3], [r.stderr for r in results]
count = sql("SELECT count(*) FROM public.user_access_repair_audit WHERE user_id='00000000-0000-4000-8000-000000000003';")
assert count.returncode == 0 and count.stdout.strip() == "1", count.stdout
print("PASS: two concurrent requests produce exactly one correction and one audit record")
