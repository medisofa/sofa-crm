"""Offline integration tests for jwt_neon_gateway.
Run: python -m pytest -q tests/security/test_jwt_neon_gateway.py
No real Neon connection or secrets. Real network E2E requires separate staging credentials.
"""
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jwt_neon_gateway as gateway

PRIVATE = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PUBLIC_PEM = PRIVATE.public_key().public_bytes(
    encoding=__import__("cryptography.hazmat.primitives.serialization",fromlist=["Encoding"]).Encoding.PEM,
    format=__import__("cryptography.hazmat.primitives.serialization",fromlist=["PublicFormat"]).PublicFormat.SubjectPublicKeyInfo,
).decode()
ISSUER = "https://sofa.test.invalid"
AUDIENCE = "sofa-test"

def token(subject="doctor_a", *, minutes=5, issuer=ISSUER, audience=AUDIENCE):
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub":subject,"iss":issuer,"aud":audience,
                       "iat":now,"nbf":now,"exp":now+timedelta(minutes=minutes)},
                      PRIVATE, algorithm="RS256")

class FakeCursor:
    def __init__(self, trace):
        self.trace=trace
        self.role=None
        self.org=None
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def execute(self,sql,params=None):
        self.trace.append((sql,params))
        if sql.startswith("SET LOCAL ROLE "):
            self.role=sql.split()[-1]
        else:
            self.org=params[0]
    def fetchall(self):
        expected={"sofa_test_doctor_a":"A","sofa_test_doctor_b":"B"}
        return [(self.org,100)] if self.org==expected[self.role] else []

class FakeConn:
    def __init__(self,trace): self.trace=trace
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def transaction(self): return self
    def cursor(self): return FakeCursor(self.trace)

@pytest.fixture
def client(monkeypatch):
    trace=[]
    for k,v in {
        "SOFA_TEST_GATEWAY_ENABLED":"YES",
        "SOFA_TEST_DATABASE_URL":"postgresql://dummy.invalid/neondb",
        "SOFA_TEST_JWT_PUBLIC_KEY_PEM":PUBLIC_PEM,
        "SOFA_TEST_JWT_ISSUER":ISSUER,
        "SOFA_TEST_JWT_AUDIENCE":AUDIENCE,
    }.items(): monkeypatch.setenv(k,v)
    monkeypatch.setattr(gateway.psycopg,"connect",lambda *a,**k:FakeConn(trace))
    return TestClient(gateway.app),trace

def call(c,org,t=None):
    return c.get("/claims/"+org,headers={"Authorization":"Bearer "+t} if t else {})

def test_a_own(client):
    c,trace=client
    assert call(c,"A",token()).status_code==200
    assert trace[0][0]=="SET LOCAL ROLE sofa_test_doctor_a"
    assert trace[1][1]==("A",)

def test_b_own(client):
    c,trace=client
    assert call(c,"B",token("doctor_b")).status_code==200
    assert trace[0][0]=="SET LOCAL ROLE sofa_test_doctor_b"

def test_a_cross_hidden(client):
    c,_=client
    assert call(c,"B",token()).json()==[]

def test_b_cross_hidden(client):
    c,_=client
    assert call(c,"A",token("doctor_b")).json()==[]

def test_missing_bearer(client):
    c,_=client
    assert call(c,"A").status_code==401

def test_expired(client):
    c,_=client
    assert call(c,"A",token(minutes=-5)).status_code==401

def test_wrong_issuer(client):
    c,_=client
    assert call(c,"A",token(issuer="https://invalid.example")).status_code==401

def test_wrong_audience(client):
    c,_=client
    assert call(c,"A",token(audience="wrong")).status_code==401

def test_unknown_user(client):
    c,_=client
    assert call(c,"A",token("other")).status_code==403

def test_tampered_signature(client):
    c,_=client
    parts=token().split(".")
    parts[2]=("A" if parts[2][0]!="A" else "B")+parts[2][1:]
    assert call(c,"A",".".join(parts)).status_code==401

def test_claim_cannot_choose_role(client):
    c,trace=client
    assert call(c,"B",token("doctor_a")).json()==[]
    assert trace[0][0]=="SET LOCAL ROLE sofa_test_doctor_a"

def test_sql_injection_org_rejected(client):
    c,trace=client
    assert call(c,"A%3BDELETE",token()).status_code==400
    assert trace==[]
