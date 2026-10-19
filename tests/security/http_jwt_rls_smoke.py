#!/usr/bin/env python3
"""SOFA: HTTP JWT/RLS smoke test. Read-only. Run against a REST staging instance
with real test-user JWTs. Never use service_role or production patient records.
Environment: SOFA_TEST_REST_URL, SOFA_TEST_ANON_KEY, SOFA_TEST_JWT_A,
SOFA_TEST_JWT_B, SOFA_TEST_ORG_A, SOFA_TEST_ORG_B.
JWTs must be obtained by actual authentication of isolated synthetic test users.
"""
import os, json, urllib.request, urllib.parse, sys

keys = ["SOFA_TEST_REST_URL","SOFA_TEST_ANON_KEY","SOFA_TEST_JWT_A",
        "SOFA_TEST_JWT_B","SOFA_TEST_ORG_A","SOFA_TEST_ORG_B"]
missing = [key for key in keys if not os.environ.get(key)]
if missing:
    print("SKIP: missing staging credentials/configuration: "+", ".join(missing))
    sys.exit(2)
base = os.environ["SOFA_TEST_REST_URL"].rstrip("/")
if not base.startswith("https://"):
    raise SystemExit("FAIL: HTTPS required")
if os.environ.get("SOFA_TEST_CONFIRM_ISOLATED") != "YES":
    raise SystemExit("FAIL: confirm isolated staging REST target (SOFA_TEST_CONFIRM_ISOLATED=YES)")
anon = os.environ["SOFA_TEST_ANON_KEY"]
org_a,org_b = os.environ["SOFA_TEST_ORG_A"],os.environ["SOFA_TEST_ORG_B"]
def query(jwt,org):
    url=base+"/service_lines?select=organization_id&organization_id=eq."+urllib.parse.quote(org,safe="")
    req=urllib.request.Request(url,headers={"apikey":anon,"Authorization":"Bearer "+jwt,"Accept":"application/json"})
    with urllib.request.urlopen(req,timeout=20) as res:
        data=json.loads(res.read().decode())
        return data
results = []
for user,jwt,home,other in [
    ("A",os.environ["SOFA_TEST_JWT_A"],org_a,org_b),
    ("B",os.environ["SOFA_TEST_JWT_B"],org_b,org_a)]:
    own=query(jwt,home)
    cross=query(jwt,other)
    # Requires >=1 seeded own service_line; otherwise this is not a valid positive control.
    if not own:
        raise SystemExit(f"FAIL: user {user} has no own visible fixture")
    if cross:
        raise SystemExit(f"FAIL: user {user} can read another organization's service_lines")
    results.append(f"PASS: {user} own={len(own)} cross=0")
print("\n".join(results))
