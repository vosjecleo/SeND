#!/usr/bin/env python3
"""Sign exact release bytes. Private key paths/content are never logged."""
import argparse
import base64
import datetime
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

DOMAIN = b"SeND release metadata v1\n"
TRUST_PATH = Path(__file__).with_name("release-trust.json")


def sign(source, destination, key, *, manifest=False):
    if stat.S_IMODE(key.stat().st_mode) & 0o077:
        raise ValueError("Signing key must not be readable by other users.")
    public = subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-outform", "DER"],
                            check=True, capture_output=True).stdout
    # RFC 8410 SubjectPublicKeyInfo for Ed25519: algorithm OID + 32 raw bytes.
    if len(public) != 44 or public[:12] != bytes.fromhex("302a300506032b6570032100"):
        raise ValueError("An Ed25519 signing key is required.")
    trust = json.loads(TRUST_PATH.read_text())
    key_id = next((name for name, raw in trust.items() if base64.b64decode(raw) == public[12:]), None)
    if key_id is None:
        raise ValueError("Signing key is not trusted by this release.")
    if manifest:
        data = json.loads(source.read_bytes())
        now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
        data.update(signature_schema=1, signed_at=now.isoformat().replace("+00:00", "Z"),
                    expires_at=(now + datetime.timedelta(days=90)).isoformat().replace("+00:00", "Z"))
        source.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    payload = DOMAIN + source.read_bytes()
    with tempfile.TemporaryDirectory(prefix="send-sign-") as temporary:
        message, signature = Path(temporary)/"payload", Path(temporary)/"signature"
        message.write_bytes(payload)
        subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key),
                        "-in", str(message), "-out", str(signature)], check=True, capture_output=True)
        encoded = base64.b64encode(signature.read_bytes()).decode("ascii")
    destination.write_text(json.dumps({"algorithm": "Ed25519", "key_id": key_id, "signature": encoded}) + "\n")


def verify(source, signature, *, manifest=False):
    envelope = json.loads(signature.read_bytes())
    trust = json.loads(TRUST_PATH.read_text())
    if envelope.get("algorithm") != "Ed25519" or envelope.get("key_id") not in trust:
        raise ValueError("Unknown release signer.")
    public = base64.b64decode(trust[envelope["key_id"]], validate=True)
    signed = base64.b64decode(envelope["signature"], validate=True)
    if len(public) != 32 or len(signed) != 64:
        raise ValueError("Invalid release signature.")
    with tempfile.TemporaryDirectory(prefix="send-verify-") as temporary:
        message, key, raw = (Path(temporary)/name for name in ("payload", "public", "signature"))
        message.write_bytes(DOMAIN + source.read_bytes())
        key.write_bytes(bytes.fromhex("302a300506032b6570032100") + public)
        raw.write_bytes(signed)
        subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                        "-inkey", str(key), "-in", str(message), "-sigfile", str(raw)], check=True, capture_output=True)
    if manifest:
        data = json.loads(source.read_bytes())
        issued = datetime.datetime.fromisoformat(data["signed_at"].replace("Z", "+00:00"))
        expires = datetime.datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00"))
        now = datetime.datetime.now(datetime.timezone.utc)
        if (data.get("signature_schema") != 1 or expires <= now or expires <= issued or
                issued > now + datetime.timedelta(minutes=5) or expires - issued > datetime.timedelta(days=90)):
            raise ValueError("Invalid release metadata dates.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--key", type=Path, default=os.environ.get("SEND_RELEASE_SIGNING_KEY_FILE"))
    parser.add_argument("--manifest", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if not args.verify and not args.key:
        parser.error("Set SEND_RELEASE_SIGNING_KEY_FILE or provide --key.")
    try:
        if args.verify:
            verify(args.source, args.destination, manifest=args.manifest)
        else:
            sign(args.source, args.destination, args.key, manifest=args.manifest)
    except Exception:
        message = ("Release verification failed. Check the metadata, signature and trusted keys.\n"
                   if args.verify else "Release signing failed. Check the private key and trust configuration.\n")
        parser.exit(1, message)


if __name__ == "__main__":
    main()
