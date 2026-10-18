"""SOFA: isolated JWT -> HTTP -> Neon PostgreSQL RLS integration gateway.

TEST-ONLY. Never deploy as production API. Requires an isolated Neon test database,
two restricted PostgreSQL roles, synthetic rows, and a dedicated DB account with
only SET privileges for those roles. Do NOT use an owner/superuser or service_role
credential in an internet-exposed API.

Dependencies: fastapi, uvicorn, psycopg[binary], PyJWT, cryptography
Environment:
  SOFA_TEST_DATABASE_URL: restricted test DB connection URL (never commit)
  SOFA_TEST_JWT_PUBLIC_KEY_PEM: public RSA key of trusted test issuer
  SOFA_TEST_JWT_ISSUER: exact issuer
  SOFA_TEST_JWT_AUDIENCE: exact audience
  SOFA_TEST_GATEWAY_ENABLED=YES
No public network listener is required: test via FastAPI TestClient.
"""
import os
import re
from contextlib import contextmanager
from fastapi import FastAPI, Header, HTTPException
import jwt
import psycopg

app = FastAPI(title="SOFA RLS JWT test gateway", docs_url=None, redoc_url=None)
# The verified JWT subject maps to a server-maintained role allowlist.
SUBJECT_TO_ROLE = {
    "doctor_a": "sofa_test_doctor_a",
    "doctor_b": "sofa_test_doctor_b",
}
SAFE_ROLES = frozenset(SUBJECT_TO_ROLE.values())
ORG_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

def require_config():
    names = ("SOFA_TEST_DATABASE_URL", "SOFA_TEST_JWT_PUBLIC_KEY_PEM",
             "SOFA_TEST_JWT_ISSUER", "SOFA_TEST_JWT_AUDIENCE")
    if os.environ.get("SOFA_TEST_GATEWAY_ENABLED") != "YES":
        raise HTTPException(503, "Test gateway disabled")
    if not all(os.environ.get(k) for k in names):
        raise HTTPException(503, "Test gateway not configured")

def verified_role(authorization):
    require_config()
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Bearer token required")
    try:
        claims = jwt.decode(
            authorization[7:], os.environ["SOFA_TEST_JWT_PUBLIC_KEY_PEM"],
            algorithms=["RS256"], issuer=os.environ["SOFA_TEST_JWT_ISSUER"],
            audience=os.environ["SOFA_TEST_JWT_AUDIENCE"],
            options={"require": ["sub", "iss", "aud", "exp", "iat", "nbf"]},
        )
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid token")
    role = SUBJECT_TO_ROLE.get(claims["sub"])
    if role not in SAFE_ROLES:
        raise HTTPException(403, "Unrecognized test identity")
    return role

@app.get("/claims/{org}")
def claims_for_org(org: str, authorization: str | None = Header(default=None)):
    role = verified_role(authorization)
    if not ORG_PATTERN.fullmatch(org):
        raise HTTPException(400, "Invalid organization")
    try:
        with psycopg.connect(os.environ["SOFA_TEST_DATABASE_URL"],
                             connect_timeout=5) as conn:
            # SET LOCAL is scoped to this transaction; role is fixed by server allowlist.
            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute("SET LOCAL ROLE " + role)
                    cur.execute(
                        "SELECT org_id, amount FROM sofa_test.claims "
                        "WHERE org_id = %s ORDER BY id", (org,)
                    )
                    rows = cur.fetchall()
        return [{"org_id": row[0], "amount": str(row[1])} for row in rows]
    except psycopg.Error:
        # No database error details in client response.
        raise HTTPException(503, "Test database unavailable")
