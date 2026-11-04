#!/usr/bin/env python3
"""
App Store Connect API で配布用の署名一式を用意する（Mac なし・CI 専用）。

  ensure       配布証明書（Apple Distribution）と App Store 用プロファイルを揃え、
               一時キーチェーンに取り込み、xcconfig と ExportOptions.plist を書き出す
  list-certs   チームの証明書を一覧表示する（上限に達したときに何を失効させるか見る）
  revoke-cert  証明書を失効させる（--id）

証明書の秘密鍵は毎回作り直さず、scripts/ci/signing/distribution.p12.enc に暗号化して保存し、
以後の実行はそれを復号して再利用する。暗号化のパスフレーズは ASC_PRIVATE_KEY（.p8）の SHA-256 から
導出するので、新しい Secret は要らない。.p8 を作り直したら復号できなくなり、証明書も作り直しになる。

環境変数: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY（.p8 の生テキストでも base64 でも可）
標準ライブラリと openssl / security コマンドだけで動く。
"""

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
STORE_P12 = "distribution.p12.enc"
STORE_META = "distribution.json"


# ---------------------------------------------------------------- 補助

def log(msg):
    print(msg, flush=True)


def fail(msg, code=1):
    print(f"::error::{msg}", flush=True)
    sys.exit(code)


def run(cmd, input_bytes=None, check=True, capture=True):
    r = subprocess.run(cmd, input=input_bytes, capture_output=capture)
    if check and r.returncode != 0:
        err = (r.stderr or b"").decode("utf-8", "replace")
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(cmd)}\n{err}")
    return r.stdout if capture else b""


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def load_private_key_text():
    raw = os.environ.get("ASC_PRIVATE_KEY", "")
    if not raw.strip():
        fail("ASC_PRIVATE_KEY が空です")
    text = raw.strip()
    if "BEGIN PRIVATE KEY" not in text:
        try:
            text = base64.b64decode(text).decode("utf-8").strip()
        except Exception:
            fail("ASC_PRIVATE_KEY が .p8 の生テキストでも base64 でもありません")
    return text + "\n"


def der_ecdsa_to_raw(sig):
    """DER の ECDSA 署名 (r, s) を JWS の raw 形式（32 バイト + 32 バイト）に変換する。"""
    if sig[0] != 0x30:
        raise ValueError("ECDSA 署名が DER ではありません")
    i = 2
    if sig[1] & 0x80:
        i = 2 + (sig[1] & 0x7F)
    parts = []
    for _ in range(2):
        if sig[i] != 0x02:
            raise ValueError("ECDSA 署名の INTEGER が見つかりません")
        length = sig[i + 1]
        value = sig[i + 2:i + 2 + length]
        i += 2 + length
        value = value.lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
    return parts[0] + parts[1]


class ASCClient:
    def __init__(self, key_id, issuer_id, key_text):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self._key_path = None
        self._token = None
        self._token_exp = 0
        fd, path = tempfile.mkstemp(suffix=".p8")
        with os.fdopen(fd, "w") as f:
            f.write(key_text)
        os.chmod(path, 0o600)
        self._key_path = path

    def token(self):
        now = int(time.time())
        if self._token and now < self._token_exp - 60:
            return self._token
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
        signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
            b64url(json.dumps(payload, separators=(",", ":")).encode())
        der = run(["openssl", "dgst", "-sha256", "-sign", self._key_path, "-binary"], input_bytes=signing_input.encode())
        self._token = signing_input + "." + b64url(der_ecdsa_to_raw(der))
        self._token_exp = now + 1200
        return self._token

    def request(self, method, path, body=None, ok=(200, 201, 204)):
        url = path if path.startswith("http") else API + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token())
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                status = resp.status
        except urllib.error.HTTPError as e:
            raw = e.read()
            status = e.code
        parsed = None
        if raw:
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = {"raw": raw.decode("utf-8", "replace")}
        if status not in ok:
            raise ASCError(status, parsed)
        return parsed

    def get_all(self, path):
        items = []
        url = path
        while url:
            page = self.request("GET", url)
            items.extend(page.get("data", []))
            url = (page.get("links") or {}).get("next")
        return items


class ASCError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}")
        self.status = status
        self.body = body

    def messages(self):
        errs = (self.body or {}).get("errors") or []
        out = []
        for e in errs:
            out.append(f"{e.get('code', '')}: {e.get('title', '')} — {e.get('detail', '')}")
        if not out:
            out.append(json.dumps(self.body, ensure_ascii=False)[:800])
        return out

    def __str__(self):
        return f"HTTP {self.status}\n" + "\n".join(self.messages())


# ---------------------------------------------------------------- 証明書

def list_certificates(client):
    certs = client.get_all("/v1/certificates?limit=200")
    rows = []
    for c in certs:
        a = c["attributes"]
        rows.append({
            "id": c["id"],
            "type": a.get("certificateType"),
            "name": a.get("name"),
            "displayName": a.get("displayName"),
            "serial": (a.get("serialNumber") or "").upper().lstrip("0"),
            "expires": a.get("expirationDate"),
            "platform": a.get("platform"),
        })
    return rows


def print_certificates(rows):
    log("")
    log("チームの証明書:")
    log(f"  {'ID':<12} {'種類':<20} {'期限':<22} 名前")
    for r in rows:
        log(f"  {r['id']:<12} {str(r['type']):<20} {str(r['expires'])[:19]:<22} {r['displayName'] or r['name']}")
    log("")


def cert_serial_from_p12(p12_path, password):
    pem = run(["openssl", "pkcs12", "-in", p12_path, "-nokeys", "-clcerts", "-passin", "pass:" + password])
    out = run(["openssl", "x509", "-noout", "-serial", "-enddate"], input_bytes=pem).decode()
    serial = re.search(r"serial=([0-9A-Fa-f]+)", out).group(1).upper().lstrip("0")
    enddate = re.search(r"notAfter=(.+)", out).group(1).strip()
    return serial, enddate


def decrypt_store(store_dir, passphrase, out_p12):
    enc = os.path.join(store_dir, STORE_P12)
    if not os.path.exists(enc):
        return False
    r = subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-md", "sha256", "-salt",
                        "-in", enc, "-out", out_p12, "-pass", "pass:" + passphrase], capture_output=True)
    if r.returncode != 0:
        log("::warning::保存済みの証明書を復号できません（ASC_PRIVATE_KEY が変わった？）。作り直します")
        return False
    return True


def encrypt_store(store_dir, passphrase, p12_path):
    os.makedirs(store_dir, exist_ok=True)
    run(["openssl", "enc", "-aes-256-cbc", "-md", "sha256", "-salt",
         "-in", p12_path, "-out", os.path.join(store_dir, STORE_P12), "-pass", "pass:" + passphrase])


def create_certificate(client, workdir):
    key_pem = os.path.join(workdir, "dist_key.pem")
    csr_pem = os.path.join(workdir, "dist.csr")
    run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
         "-keyout", key_pem, "-out", csr_pem,
         "-subj", "/CN=Fog CI Distribution/O=Fog/C=JP"])
    csr_text = open(csr_pem).read()
    body = {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_text}}}
    try:
        resp = client.request("POST", "/v1/certificates", body)
    except ASCError as e:
        text = str(e)
        if "maximum" in text.lower() or e.status == 409:
            print_certificates(list_certificates(client))
            fail("証明書の上限に達しています。上の一覧から不要な DISTRIBUTION 証明書を選び、"
                 "Actions の『signing-admin』ワークフローで revoke するか、developer.apple.com の "
                 "Certificates で Revoke してから再実行してください。\n" + text, code=2)
        raise
    data = resp["data"]
    cert_der = base64.b64decode(data["attributes"]["certificateContent"])
    cer_path = os.path.join(workdir, "dist.cer")
    with open(cer_path, "wb") as f:
        f.write(cert_der)
    cert_pem = run(["openssl", "x509", "-inform", "DER", "-in", cer_path])
    cert_pem_path = os.path.join(workdir, "dist_cert.pem")
    with open(cert_pem_path, "wb") as f:
        f.write(cert_pem)
    return data["id"], key_pem, cert_pem_path


def build_p12(key_pem, cert_pem, out_p12, password):
    run(["openssl", "pkcs12", "-export", "-inkey", key_pem, "-in", cert_pem, "-out", out_p12,
         "-passout", "pass:" + password, "-name", "Fog CI Distribution",
         "-macalg", "sha1", "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES"])


def ensure_certificate(client, store_dir, passphrase, workdir):
    """保存済みの証明書が有効ならそれを、無ければ新規作成して保存する。(p12_path, cert_id, changed)"""
    p12 = os.path.join(workdir, "distribution.p12")
    if decrypt_store(store_dir, passphrase, p12):
        serial, enddate = cert_serial_from_p12(p12, passphrase)
        rows = list_certificates(client)
        match = next((r for r in rows if r["serial"] == serial), None)
        if match:
            exp = match["expires"] or ""
            if exp and exp[:10] > dt.date.today().isoformat():
                log(f"保存済みの配布証明書を再利用します: {match['id']}（期限 {exp[:10]}）")
                return p12, match["id"], False
            log("::warning::保存済みの証明書は期限切れです。作り直します")
        else:
            log("::warning::保存済みの証明書は Apple 側に存在しません（失効済み？）。作り直します")

    log("配布証明書（Apple Distribution）を新規作成します")
    cert_id, key_pem, cert_pem = create_certificate(client, workdir)
    build_p12(key_pem, cert_pem, p12, passphrase)
    encrypt_store(store_dir, passphrase, p12)
    serial, enddate = cert_serial_from_p12(p12, passphrase)
    with open(os.path.join(store_dir, STORE_META), "w") as f:
        json.dump({
            "certificateId": cert_id,
            "serialNumber": serial,
            "notAfter": enddate,
            "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "note": "CI が自動生成した Apple Distribution 証明書。p12 は ASC_PRIVATE_KEY の SHA-256 で暗号化。",
        }, f, ensure_ascii=False, indent=2)
        f.write("\n")
    log(f"証明書を作成し保存しました: {cert_id}（期限 {enddate}）")
    return p12, cert_id, True


# ---------------------------------------------------------------- キーチェーン

def import_into_keychain(p12, p12_password, keychain_path, keychain_password):
    if os.path.exists(keychain_path):
        os.remove(keychain_path)
    run(["security", "create-keychain", "-p", keychain_password, keychain_path])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain_path])
    run(["security", "unlock-keychain", "-p", keychain_password, keychain_path])
    run(["security", "import", p12, "-k", keychain_path, "-P", p12_password, "-A",
         "-t", "cert", "-f", "pkcs12", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s",
         "-k", keychain_password, keychain_path])
    current = run(["security", "list-keychains", "-d", "user"]).decode()
    others = [line.strip().strip('"') for line in current.splitlines() if line.strip()]
    run(["security", "list-keychains", "-d", "user", "-s", keychain_path] + others)
    run(["security", "default-keychain", "-d", "user", "-s", keychain_path])
    identities = run(["security", "find-identity", "-v", "-p", "codesigning", keychain_path]).decode()
    log(identities.strip())
    if "Apple Distribution" not in identities:
        fail("キーチェーンに Apple Distribution の署名 ID が見つかりません（証明書と秘密鍵が揃っていない）")


# ---------------------------------------------------------------- プロファイル

def bundle_id_resource(client, identifier):
    items = client.get_all(f"/v1/bundleIds?filter[identifier]={identifier}&limit=200")
    for it in items:
        if it["attributes"].get("identifier") == identifier:
            return it["id"]
    fail(f"App ID '{identifier}' が Apple Developer に登録されていません。"
         f"docs/05_setup_for_developer.md §2 の手順で Identifiers に追加してください")


def ensure_profile(client, identifier, cert_id, workdir):
    name = f"Fog CI AppStore {identifier}"
    existing = client.get_all(f"/v1/profiles?filter[name]={urllib.request.quote(name)}&limit=200")
    for p in existing:
        if p["attributes"].get("name") == name:
            client.request("DELETE", f"/v1/profiles/{p['id']}")
    bid = bundle_id_resource(client, identifier)
    body = {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        },
    }}
    resp = client.request("POST", "/v1/profiles", body)
    attrs = resp["data"]["attributes"]
    content = base64.b64decode(attrs["profileContent"])
    uuid = attrs["uuid"]
    for d in [os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
              os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")]:
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, uuid + ".mobileprovision"), "wb") as f:
            f.write(content)
    log(f"プロファイルを作成しました: {name}（{uuid}, {attrs.get('profileState')}）")
    return name, uuid


# ---------------------------------------------------------------- 出力

def write_build_files(out_dir, team_id, targets, profiles):
    os.makedirs(out_dir, exist_ok=True)
    lines = [
        "// CI が生成する手動署名の設定（scripts/ci/asc_signing.py ensure）",
        "CODE_SIGN_STYLE = Manual",
        "CODE_SIGN_IDENTITY = Apple Distribution",
        f"DEVELOPMENT_TEAM = {team_id}",
        "// ターゲット名ごとのプロファイル。パッケージのターゲット（Core, Core_Core）は空になり、プロファイル不要のまま署名される",
        "PROVISIONING_PROFILE_SPECIFIER = $(FOG_PROFILE_$(TARGET_NAME))",
    ]
    for target, identifier in targets.items():
        lines.append(f"FOG_PROFILE_{target} = {profiles[identifier]}")
    with open(os.path.join(out_dir, "Signing.xcconfig"), "w") as f:
        f.write("\n".join(lines) + "\n")

    export = {
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "teamID": team_id,
        "provisioningProfiles": {identifier: profiles[identifier] for identifier in targets.values()},
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": True,
    }
    with open(os.path.join(out_dir, "ExportOptions.plist"), "wb") as f:
        plistlib.dump(export, f)


def github_output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            f.write(f"{key}={value}\n")


# ---------------------------------------------------------------- コマンド

def make_client():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    if not key_id or not issuer:
        fail("ASC_KEY_ID / ASC_ISSUER_ID が設定されていません")
    return ASCClient(key_id, issuer, load_private_key_text())


def cmd_ensure(args):
    client = make_client()
    passphrase = hashlib.sha256(load_private_key_text().encode()).hexdigest()
    targets = {}
    for spec in args.target:
        name, _, identifier = spec.partition("=")
        if not name or not identifier:
            fail(f"--target は TargetName=bundle.id の形式です: {spec}")
        targets[name] = identifier
    workdir = tempfile.mkdtemp(prefix="fog-signing-")
    try:
        p12, cert_id, changed = ensure_certificate(client, args.store, passphrase, workdir)
        keychain = os.path.expanduser("~/Library/Keychains/fog-ci.keychain-db")
        keychain_password = hashlib.sha256(os.urandom(32)).hexdigest()
        import_into_keychain(p12, passphrase, keychain, keychain_password)
        profiles = {}
        for identifier in targets.values():
            name, _ = ensure_profile(client, identifier, cert_id, workdir)
            profiles[identifier] = name
        write_build_files(args.out, args.team_id, targets, profiles)
        github_output("store_changed", "true" if changed else "false")
        github_output("certificate_id", cert_id)
        log(f"署名の準備ができました（xcconfig / ExportOptions.plist → {args.out}）")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def cmd_list_certs(args):
    print_certificates(list_certificates(make_client()))


def cmd_revoke_cert(args):
    client = make_client()
    rows = list_certificates(client)
    target = next((r for r in rows if r["id"] == args.id), None)
    if not target:
        print_certificates(rows)
        fail(f"証明書 {args.id} が見つかりません")
    client.request("DELETE", f"/v1/certificates/{args.id}")
    log(f"失効させました: {args.id} {target['type']} {target['displayName'] or target['name']}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("ensure")
    e.add_argument("--team-id", required=True)
    e.add_argument("--target", action="append", required=True, help="TargetName=bundle.id（複数可）")
    e.add_argument("--store", default="scripts/ci/signing", help="暗号化した証明書の保存先")
    e.add_argument("--out", default="build/signing", help="xcconfig と ExportOptions.plist の出力先")
    e.set_defaults(func=cmd_ensure)
    sub.add_parser("list-certs").set_defaults(func=cmd_list_certs)
    r = sub.add_parser("revoke-cert")
    r.add_argument("--id", required=True)
    r.set_defaults(func=cmd_revoke_cert)
    args = p.parse_args()
    try:
        args.func(args)
    except ASCError as e:
        fail(f"App Store Connect API エラー: {e}")
    except RuntimeError as e:
        fail(str(e))


if __name__ == "__main__":
    main()
