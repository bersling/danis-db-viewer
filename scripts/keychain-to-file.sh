#!/bin/bash
# One-time migration: copy passwords from the old macOS Keychain items into the
# new plaintext secrets file. Values are never printed.
#
# Run this yourself (it reads Keychain values, so the agent can't):
#   bash scripts/keychain-to-file.sh
set -euo pipefail

DIR="$HOME/Library/Application Support/DanisDBViewer"
STORE="$DIR/connections.json"
SECRETS="$DIR/secrets.json"
SERVICE="com.danis.dbviewer"

[ -f "$STORE" ] || { echo "no connections.json"; exit 1; }
[ -f "$SECRETS" ] || echo '{}' > "$SECRETS"
chmod 600 "$SECRETS"

# List all connection UUIDs + names.
python3 - "$STORE" <<'PY' | while IFS=$'\t' read -r uuid name; do
import json, sys
for c in json.load(open(sys.argv[1])):
    print(f"{c['id']}\t{c['name']}")
PY
  # Read the password from the Keychain (created by `security`, so no prompt).
  if pw="$(security find-generic-password -s "$SERVICE" -a "$uuid" -w 2>/dev/null)"; then
    VAL="$pw" UUID="$uuid" SECRETS="$SECRETS" python3 <<'PY'
import json, os
p = os.environ["SECRETS"]; d = json.load(open(p))
d[os.environ["UUID"]] = os.environ["VAL"]
json.dump(d, open(p, "w"), indent=2, sort_keys=True)
PY
    pw=""; VAL=""
    echo "✓ migrated: $name"
  else
    echo "· no keychain password for: $name (skip)"
  fi
done

chmod 600 "$SECRETS"
echo
echo "Done → $SECRETS"
echo "Restart the app; passwords now load from the file (no Keychain prompts)."
