#!/bin/bash
# Creates a self-signed code-signing certificate "ProClick Mini Dev" in the login keychain,
# so every build keeps the same signature and macOS remembers its permissions.
# Safe to run again: does nothing if the identity already exists.
set -euo pipefail

NAME="ProClick Mini Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already set up."
    exit 0
fi

# macOS's own LibreSSL: Homebrew OpenSSL 3+ writes PKCS#12 files `security import` can't read.
OPENSSL=/usr/bin/openssl

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -out "$TMP/cert.p12" -passout pass:proclick
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P proclick -T /usr/bin/codesign
echo "Trusting the certificate for code signing (macOS asks for your password)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\""
