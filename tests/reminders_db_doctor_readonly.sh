#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STORE="$TMP_DIR/stores"
mkdir -p "$STORE"
DB="$STORE/Data-test.sqlite"

sqlite3 "$DB" <<'SQL'
create table ZREMCDBASESECTION (Z_PK integer primary key, ZDISPLAYNAME text);
create table ZREMCDBASELIST (Z_PK integer primary key, ZNAME text);
create table ZREMCDREMINDER (Z_PK integer primary key, ZTITLE text);
insert into ZREMCDBASESECTION (ZDISPLAYNAME) values ('IMPORTANT'), ('URGENT');
insert into ZREMCDBASELIST (ZNAME) values ('MONEY'), ('WORK');
insert into ZREMCDREMINDER (ZTITLE) values ('Example');
SQL

"$ROOT/bin/smart-shadow" reminders-db-doctor --store-root "$STORE" > "$TMP_DIR/out.json"

for pattern in \
  '"mode"[[:space:]]*:[[:space:]]*"read_only"' \
  '"write_api"[[:space:]]*:[[:space:]]*false' \
  '"read_only"[[:space:]]*:[[:space:]]*true' \
  '"has_section_table"[[:space:]]*:[[:space:]]*true' \
  '"ZREMCDBASESECTION"[[:space:]]*:[[:space:]]*2' \
  '"ZREMCDBASELIST"[[:space:]]*:[[:space:]]*2' \
  '"ZREMCDREMINDER"[[:space:]]*:[[:space:]]*1'
do
  if ! rg -q "$pattern" "$TMP_DIR/out.json"; then
    echo "expected reminders-db-doctor output to contain pattern: $pattern"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
done
