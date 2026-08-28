#!/bin/bash
# Creates the stable self-signed code signing identity Cadence builds against.
#
# Why this exists: macOS TCC ties Accessibility and Input Monitoring grants to an
# app's code signature. Ad-hoc signing ("-") produces a new cdhash on every build,
# so every rebuild looked like a brand new app and silently dropped both grants —
# which broke Fn push-to-talk and auto-paste. A self-signed leaf stays constant, so
# a grant given once survives all future rebuilds.
#
# Run once per machine. Idempotent.

set -euo pipefail

IDENTITY_NAME="Cadence Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "✓ '$IDENTITY_NAME' already present."
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# macOS security(1) cannot read OpenSSL 3 defaults, so force legacy PKCS12 encryption.
openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem \
  -passout pass:cadence -name "$IDENTITY_NAME" \
  -legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

security import identity.p12 -k "$KEYCHAIN" -P cadence -T /usr/bin/codesign -A

# Prompts for the login password once; without trust codesign will not accept the leaf.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem

security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
echo "✓ '$IDENTITY_NAME' created. Rebuild Cadence, then grant permissions one final time."
