#!/bin/bash
# Creates a stable self-signed code-signing identity in the login keychain, once.
# Signing every build with the SAME identity keeps the app's code requirement
# stable, so macOS Keychain "Always Allow" grants persist across rebuilds
# (ad-hoc `codesign -s -` changes identity every build → constant re-prompts).
set -euo pipefail

IDENTITY_NAME="Dani's DB Viewer Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Already present? (find-identity without -v lists untrusted ones too — we sign
# by hash, so trust is not required.)
if security find-identity "$KEYCHAIN" 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
    echo "signing identity already exists: $IDENTITY_NAME"
    exit 0
fi

echo "creating self-signed code-signing identity: $IDENTITY_NAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Self-signed cert. Needs BOTH keyUsage=digitalSignature and EKU=codeSigning,
# or macOS rejects it for the code-signing policy.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

# -legacy: OpenSSL 3 defaults to a PKCS12 cipher macOS's security can't read.
openssl pkcs12 -export -out "$TMP/id.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:danisdbviewer -legacy >/dev/null 2>&1

# Import key+cert; -T codesign lets codesign use it without prompting.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P danisdbviewer \
    -T /usr/bin/codesign >/dev/null 2>&1

echo "created: $IDENTITY_NAME (self-signed; signed-by-hash, no trust needed)"
