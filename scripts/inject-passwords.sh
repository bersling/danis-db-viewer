#!/bin/bash
# Inject DB passwords into Dani's DB Viewer's secrets file, WITHOUT printing them.
#
# Values flow: GitLab CI/CD variable ──curl──▶ shell var ──▶ secrets.json
# Never echoed to the terminal. The secrets file lives OUTSIDE the repo
# (~/Library/Application Support/DanisDBViewer/secrets.json, chmod 600) and is a
# plaintext { "<uuid>": "<password>" } map the app reads directly.
#
# Usage:
#   export GITLAB_TOKEN=...            # a token that can read the CI/CD variables
#   GITLAB_HOST=code.taskbase.com \
#   scripts/inject-passwords.sh scripts/password-map.tsv
#
# Mapping file (TSV, '#' comments allowed), one line per connection:
#   <connection-name>\t<gitlab-project-path-or-id>\t<ci-variable-key>
# e.g.
#   LapProdRO\ttaskbase/tb\tLAP_DB_RO_PASSWORD
set -euo pipefail

HOST="${GITLAB_HOST:-code.taskbase.com}"
TOKEN="${GITLAB_TOKEN:?set GITLAB_TOKEN to a token that can read the CI/CD variables}"
MAP="${1:?usage: inject-passwords.sh <map.tsv>}"
DIR="$HOME/Library/Application Support/DanisDBViewer"
STORE="$DIR/connections.json"
SECRETS="$DIR/secrets.json"

[ -f "$STORE" ] || { echo "no connections.json at $STORE — add data sources first"; exit 1; }
[ -f "$SECRETS" ] || echo '{}' > "$SECRETS"
chmod 600 "$SECRETS"

# name -> uuid, read from connections.json (no secrets involved)
uuid_for() {
  python3 - "$STORE" "$1" <<'PY'
import json, sys
store, name = sys.argv[1], sys.argv[2]
for c in json.load(open(store)):
    if c.get("name") == name:
        print(c["id"]); break
PY
}

url_encode() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }

ok=0; fail=0
while IFS=$'\t' read -r name project var || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue;; esac
  uuid="$(uuid_for "$name")"
  if [ -z "$uuid" ]; then echo "✗ $name — not found in connections.json"; fail=$((fail+1)); continue; fi

  proj_enc="$(url_encode "$project")"
  api="https://$HOST/api/v4/projects/$proj_enc/variables/$var"

  # Fetch the value straight into a shell var; never printed.
  value="$(curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$api" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"], end="")')" \
    || { echo "✗ $name — could not fetch $var from $project"; fail=$((fail+1)); continue; }

  if [ -z "$value" ]; then echo "✗ $name — empty value for $var"; fail=$((fail+1)); continue; fi

  # Upsert into secrets.json under the connection UUID. Python reads the value
  # from an env var (not argv) so it never appears in the process list.
  VAL="$value" UUID="$uuid" SECRETS="$SECRETS" python3 <<'PY'
import json, os
p = os.environ["SECRETS"]
d = json.load(open(p))
d[os.environ["UUID"]] = os.environ["VAL"]
json.dump(d, open(p, "w"), indent=2, sort_keys=True)
PY
  value=""; VAL=""   # drop from memory
  echo "✓ $name — password stored"
  ok=$((ok+1))
done < "$MAP"

chmod 600 "$SECRETS"
echo
echo "$ok stored, $fail failed → $SECRETS"
echo "Reconnect in the app — passwords resolve from the file automatically (no Keychain prompt)."
