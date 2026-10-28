#!/usr/bin/env bash
# SOFA only. Creates encrypted-location-ready local database dumps; never commits patient data.
set -Eeuo pipefail
umask 077
: "${SOFA_DB_URL:?Set SOFA_DB_URL securely on your own workstation; never commit it}"
command -v supabase >/dev/null || { echo 'Supabase CLI required' >&2; exit 2; }
command -v sha256sum >/dev/null || { echo 'sha256sum required' >&2; exit 2; }
# Fail closed if the URL cannot be identified as SOFA's project.
if [[ "$SOFA_DB_URL" != *bpwjhgpzhzhiocoxrvzq* ]]; then
  echo 'STOP: connection URL must identify approved SOFA project bpwjhgpzhzhiocoxrvzq' >&2
  exit 3
fi
DEST="${SOFA_BACKUP_DIR:-$HOME/sofa-private-backups/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$DEST"
chmod 700 "$DEST"
supabase db dump --db-url "$SOFA_DB_URL" --role-only -f "$DEST/roles.sql"
supabase db dump --db-url "$SOFA_DB_URL" -f "$DEST/schema.sql"
supabase db dump --db-url "$SOFA_DB_URL" --data-only --use-copy -f "$DEST/data.sql"
for f in roles.sql schema.sql data.sql; do
  test -s "$DEST/$f" || { echo "STOP: missing/empty $f" >&2; exit 4; }
done
(cd "$DEST" && sha256sum roles.sql schema.sql data.sql > SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt)
printf 'DB_DUMPS_CREATED: %s\nRESTORE_VERIFIED: NO\nSTORAGE_OBJECTS_INCLUDED: NO\n' "$DEST"
