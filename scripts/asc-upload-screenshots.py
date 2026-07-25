#!/usr/bin/env python3
"""
Upload App Store screenshots to the inflight iOS version via the App Store
Connect API. Replaces the chosen display-size set with the given images, in the
order listed, so re-running is idempotent.

Prereqs (already set on this machine):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH   (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-upload-screenshots.py APP_IPHONE_65 \
      fastlane/screenshots/en-US-6.5-framed/01-print.png \
      fastlane/screenshots/en-US-6.5-framed/02-vault.png \
      fastlane/screenshots/en-US-6.5-framed/03-detail.png \
      fastlane/screenshots/en-US-6.5-framed/04-add.png

The first arg is the screenshotDisplayType (e.g. APP_IPHONE_65 for 6.5",
APP_IPHONE_67 for 6.7", APP_IPHONE_69 for 6.9"). The rest are image paths in
display order. Locale defaults to en-US.
"""
import os, sys, time, json, hashlib, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
LOCALE = "en-US"


def token():
    now = int(time.time())
    with open(os.environ["ASC_PRIVATE_KEY_PATH"]) as f:
        key = f.read()
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(
        url, data=json.dumps(body).encode() if body is not None else None, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")}


def errs(resp):
    out = [f"{e.get('status')} {e.get('code')}: {e.get('detail')}" for e in resp.get("errors", [])]
    return "; ".join(out) or json.dumps(resp)[:400]


def upload_bytes(op, data):
    """Execute one appScreenshot uploadOperation (a raw PUT to signed storage)."""
    chunk = data[op["offset"]:op["offset"] + op["length"]]
    req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
    for h in op.get("requestHeaders", []):
        req.add_header(h["name"], h["value"])
    with urllib.request.urlopen(req) as r:
        return r.status


def find_app():
    st, resp = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name")
    data = resp.get("data") or []
    if not data:
        sys.exit(f"No app for {BUNDLE_ID}")
    return data[0]["id"], data[0]["attributes"]["name"]


def editable_version(app_id):
    st, resp = call("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10"
                           "&fields[appStoreVersions]=versionString,appStoreState,platform")
    for v in resp.get("data", []):
        a = v["attributes"]
        if a.get("platform") == "IOS" and a.get("appStoreState") in (
            "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            return v["id"], a.get("versionString")
    sys.exit("No editable iOS version found (need PREPARE_FOR_SUBMISSION).")


def localization(version_id):
    st, resp = call("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
                           f"?limit=200&fields[appStoreVersionLocalizations]=locale")
    for l in resp.get("data", []):
        if l["attributes"].get("locale") == LOCALE:
            return l["id"]
    sys.exit(f"No {LOCALE} localization on the version.")


def get_or_create_set(loc_id, display_type):
    st, resp = call("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets"
                           "?include=appScreenshots&limit=50")
    for s in resp.get("data", []):
        if s["attributes"].get("screenshotDisplayType") == display_type:
            existing = [r["id"] for r in s.get("relationships", {})
                        .get("appScreenshots", {}).get("data", [])]
            return s["id"], existing
    body = {"data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": display_type},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}
    st, resp = call("POST", "/v1/appScreenshotSets", body)
    if st not in (200, 201):
        sys.exit(f"Could not create screenshot set: {errs(resp)}")
    return resp["data"]["id"], []


def delete_screenshot(sid):
    call("DELETE", f"/v1/appScreenshots/{sid}")


def upload_one(set_id, path):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    reserve = {"data": {"type": "appScreenshots",
                        "attributes": {"fileSize": len(data), "fileName": name},
                        "relationships": {"appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": set_id}}}}}
    st, resp = call("POST", "/v1/appScreenshots", reserve)
    if st not in (200, 201):
        raise RuntimeError(f"reserve failed: {errs(resp)}")
    sid = resp["data"]["id"]
    for op in resp["data"]["attributes"].get("uploadOperations", []):
        upload_bytes(op, data)
    checksum = hashlib.md5(data).hexdigest()
    commit = {"data": {"type": "appScreenshots", "id": sid,
                       "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}}
    st, resp = call("PATCH", f"/v1/appScreenshots/{sid}", commit)
    if st not in (200, 201):
        raise RuntimeError(f"commit failed: {errs(resp)}")
    return sid


def set_order(set_id, ids):
    body = {"data": [{"type": "appScreenshots", "id": i} for i in ids]}
    st, resp = call("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots", body)
    if st not in (200, 201, 204):
        print("  WARN could not set order:", errs(resp))


def main():
    if len(sys.argv) < 3:
        sys.exit("Usage: asc-upload-screenshots.py DISPLAY_TYPE image1 [image2 ...]")
    display_type = sys.argv[1]
    paths = sys.argv[2:]
    for p in paths:
        if not os.path.isfile(p):
            sys.exit(f"Not found: {p}")

    app_id, name = find_app()
    print(f"App: {app_id} — {name}")
    vid, vstr = editable_version(app_id)
    print(f"Version: {vstr} ({vid})")
    loc_id = localization(vid)
    set_id, existing = get_or_create_set(loc_id, display_type)
    print(f"Set [{display_type}]: {set_id} ({len(existing)} existing)")

    for sid in existing:
        delete_screenshot(sid)
    if existing:
        print(f"  cleared {len(existing)} existing screenshot(s)")

    ids = []
    for p in paths:
        sid = upload_one(set_id, p)
        ids.append(sid)
        print(f"  uploaded {os.path.basename(p)} -> {sid}")

    set_order(set_id, ids)
    print(f"Done. {len(ids)} screenshot(s) uploaded in order. Verify in App Store Connect.")


if __name__ == "__main__":
    main()
