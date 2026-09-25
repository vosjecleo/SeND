#!/usr/bin/env python3
"""Local-only Last.fm-enabled preview. Never prints credentials/tokens."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request
import urllib.error


def credential(path: Path) -> str:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
        raise SystemExit(f"Credential must be an owned, regular 0600 file: {path.name}")
    value = path.read_text().strip()
    if not re.fullmatch(r"[a-fA-F0-9]{32}", value):
        raise SystemExit(f"Unexpected credential format: {path.name}")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--target", choices=("linux", "web"), default="linux")
    parser.add_argument("--credentials-directory", type=Path, default=Path("/home/cleo"))
    parser.add_argument("--flutter", default="/home/cleo/.flutter-sdk/bin/flutter")
    args = parser.parse_args()
    key = credential(args.credentials_directory / "lastfm-api.key")
    secret = credential(args.credentials_directory / "lastfm-shared.key")
    params = {"api_key": key, "method": "auth.getToken"}
    signed = "".join(k + params[k] for k in sorted(params)) + secret
    params.update(api_sig=hashlib.md5(signed.encode()).hexdigest(), format="json")
    request = urllib.request.Request("https://ws.audioscrobbler.com/2.0/",
                                     data=urllib.parse.urlencode(params).encode(), method="POST")
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            data = json.loads(response.read(131073))
        if not isinstance(data.get("token"), str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,256}", data["token"]):
            code = data.get("error")
            raise SystemExit(f"Last.fm credential check rejected (API code {code if isinstance(code, int) else 'unknown'}).")
    except urllib.error.HTTPError as error:
        raise SystemExit(f"Last.fm credential check failed (HTTP {error.code}).") from None
    except Exception:
        raise SystemExit("Last.fm credential check failed; no credentials or response data were logged.") from None
    print("Last.fm application authentication verified (token not displayed).", flush=True)
    if args.check_only:
        return
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="deltiecord-private-build-") as folder:
        config = Path(folder) / "lastfm-defines.json"
        fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump({"LASTFM_API_KEY": key, "LASTFM_API_SECRET": secret,
                       "LASTFM_PUBLIC_DISPLAY_APPROVED": True}, stream)
        env = dict(os.environ)
        env["RUSTFLAGS"] = (env.get("RUSTFLAGS", "") + " -C link-dead-code").strip()
        command = [args.flutter, "build", args.target, "--release", "--no-pub",
                   f"--dart-define-from-file={config}"]
        if args.target == "web":
            command += ["--no-web-resources-cdn", "--no-wasm-dry-run"]
        result = subprocess.run(command, cwd=repo, env=env)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
