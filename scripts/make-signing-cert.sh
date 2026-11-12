#!/usr/bin/env bash
# Creates the self-signed "AulaWheel Code Signing" certificate that signs every release. Run it once, ever:
# macOS ties permission grants to this exact certificate, so a new one makes every user grant them again.
# Writes the .p12 and its password to OUT_DIR (default ~/AulaWheel-signing), imports it into the login keychain,
# and pins its SHA-1 in scripts/release-cert.sha1, which releases are checked against.
set -euo pipefail

NAME="AulaWheel Code Signing"
OUT_DIR="${1:-$HOME/AulaWheel-signing}"
P12="$OUT_DIR/AulaWheel-signing.p12"
PASSWORD_FILE="$OUT_DIR/AulaWheel-signing.password"
PIN_FILE="$(cd "$(dirname "$0")" && pwd)/release-cert.sha1"
OPENSSL=/usr/bin/openssl  # LibreSSL writes a PKCS#12 that `security import` can read

if [[ -s "$PIN_FILE" ]]; then
    echo "error: $PIN_FILE already pins the release certificate." >&2
    echo "Import its backup (security import <file>.p12 -T /usr/bin/codesign) rather than making a new one: a new certificate makes every user grant permissions again." >&2
    exit 1
fi
if [[ "$(security find-identity -p codesigning)" == *"\"$NAME\""* ]]; then
    echo "error: a \"$NAME\" identity is already in your keychain." >&2
    echo "Use it (or its backup) rather than making a new one: a new certificate makes every user grant permissions again." >&2
    exit 1
fi
if [[ -e "$P12" ]]; then
    echo "error: $P12 already exists. Import it with: security import \"$P12\" -T /usr/bin/codesign" >&2
    exit 1
fi

umask 077
mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 20 years, since renewing it would also change the certificate.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
printf '%s' "$("$OPENSSL" rand -base64 24)" > "$PASSWORD_FILE"  # no newline, to match the secret
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$P12" -passout file:"$PASSWORD_FILE"

security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$(cat "$PASSWORD_FILE")" -T /usr/bin/codesign >/dev/null
"$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' > "$PIN_FILE"

cat <<EOF
Created "$NAME" ($(cat "$PIN_FILE")) and imported it into your login keychain.

1. Commit $PIN_FILE.

2. Give the certificate to the release workflow:

     base64 -i "$P12" | gh secret set SIGNING_CERT_P12
     gh secret set SIGNING_CERT_PASSWORD < "$PASSWORD_FILE"

3. Back up both files in $OUT_DIR somewhere safe (a password manager), then delete the folder.
   Losing them means every user grants Accessibility and Input Monitoring again after the next release.

scripts/build-app.sh now signs local builds with it too. If macOS asks whether codesign may use
the key, choose Always Allow.
EOF
