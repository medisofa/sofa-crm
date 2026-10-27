#!/usr/bin/env bash
# Solo contenedor nuevo y desechable. No usa conexiones ni credenciales de producción.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
dkr() { env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host=unix:///var/run/docker.sock "$@"; }
qa_name="sofa-user-repair-qa-$(date -u +%Y%m%d%H%M%S)-$$"
image='postgres@sha256:eee6c6e1b0894fa4fe0075eb054af9fd1cf39a35321c2d4110626cfe506411fb'
dkr info >/dev/null
dkr run -d --rm --name "$qa_name" -e POSTGRES_HOST_AUTH_METHOD=trust "$image" >/dev/null
trap 'dkr rm -f "$qa_name" >/dev/null 2>&1 || true' EXIT
for attempt in {1..30}; do
  # El servidor temporal de inicialización solo usa socket; esperar al TCP final.
  if dkr exec "$qa_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  if [[ "$attempt" == 30 ]]; then echo 'PostgreSQL QA no inició' >&2; exit 1; fi
  sleep 1
done
for sql in tests/security/user_repair_fixture.sql docs/sql/PROPOSED_user_access_repair.sql tests/security/user_repair_regression.sql; do
  dkr exec -i "$qa_name" psql -X -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
python3 tests/security/user_repair_concurrency.py "$qa_name"
echo 'QA sintética aprobada; no certifica el esquema ni sesiones reales de producción.'
