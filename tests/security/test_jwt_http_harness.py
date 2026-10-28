"""SOFA isolated HTTP/JWT authentication harness. SYNTHETIC ONLY.
No Neon or Supabase credentials, data or network connections.
Run: python -m pytest -q tests/security/test_jwt_http_harness.py
Dependencies: fastapi, httpx, PyJWT, cryptography, pytest.
"""
from datetime import datetime, timedelta, timezone
from uuid import uuid4
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI, Header, HTTPException
from fastapi.testclient import TestClient

ISSUER = "https://sofa.test.invalid/auth"
AUDIENCE = "sofa-staging"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PUBLIC_KEY = KEY.public_key()
USERS = {"doctor_a": "A", "doctor_b": "B"}
CLAIMS = {"A": [{"id": "synthetic-A", "org": "A"}],
          "B": [{"id": "synthetic-B", "org": "B"}]}
app = FastAPI()

def token(subject="doctor_a", *, minutes=5, issuer=ISSUER, audience=AUDIENCE, key=KEY):
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": subject, "iss": issuer, "aud": audience,
                       "iat": now, "nbf": now, "exp": now + timedelta(minutes=minutes),
                       "jti": str(uuid4())}, key, algorithm="RS256")

@app.get("/claims/{org}")
def read_claims(org: str, authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing bearer token")
    try:
        payload = jwt.decode(authorization[7:], PUBLIC_KEY, algorithms=["RS256"],
                             issuer=ISSUER, audience=AUDIENCE,
                             options={"require": ["sub", "iss", "aud", "exp", "iat", "nbf"]})
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid bearer token")
    # Server-side authorization: ignore client-provided tenant/role claims.
    home = USERS.get(payload["sub"])
    if home is None:
        raise HTTPException(403, "Unknown subject")
    if org != home:
        raise HTTPException(403, "Tenant access denied")
    return CLAIMS[org]

client = TestClient(app)
def get(org, bearer=None):
    headers = {"Authorization": "Bearer " + bearer} if bearer else {}
    return client.get("/claims/" + org, headers=headers)

def test_a_reads_own(): assert get("A", token()).status_code == 200
def test_b_reads_own(): assert get("B", token("doctor_b")).status_code == 200
def test_a_cannot_read_b(): assert get("B", token()).status_code == 403
def test_b_cannot_read_a(): assert get("A", token("doctor_b")).status_code == 403
def test_missing_token(): assert get("A").status_code == 401
def test_expired_token(): assert get("A", token(minutes=-5)).status_code == 401
def test_wrong_issuer(): assert get("A", token(issuer="https://evil.invalid")).status_code == 401
def test_wrong_audience(): assert get("A", token(audience="another-app")).status_code == 401
def test_unknown_subject(): assert get("A", token("unknown")).status_code == 403
def test_tampered_signature():
    forged = token()
    parts = forged.split(".")
    parts[2] = ("A" if parts[2][0] != "A" else "B") + parts[2][1:]
    assert get("A", ".".join(parts)).status_code == 401
def test_untrusted_tenant_claim_ignored():
    forged = jwt.encode({"sub":"doctor_a","iss":ISSUER,"aud":AUDIENCE,
                         "exp":datetime.now(timezone.utc)+timedelta(minutes=5),
                         "iat":datetime.now(timezone.utc),"nbf":datetime.now(timezone.utc),
                         "tenant":"B","role":"admin"}, KEY, algorithm="RS256")
    assert get("B", forged).status_code == 403
