#!/usr/bin/env python3
"""
Append the Terms of Use (EULA) + Privacy Policy links to the App Store
description of the editable iOS version, satisfying the App Review rejection
that flagged a missing functional EULA link for auto-renewable subscriptions.

Idempotent: if the EULA URL is already in the description, nothing is written.

Prereqs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-set-description-terms.py          # show what would change
  python3 scripts/asc-set-description-terms.py --apply  # write it
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
LOCALE = "en-US"

EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIVACY_URL = "https://deegan4.github.io/Tearoff/privacy.html"
BLOCK = f"Terms of Use (EULA): {EULA_URL}\nPrivacy Policy: {PRIVACY_URL}"

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}


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


def die(msg, resp=None):
    if resp is not None:
        detail = "; ".join(f"{e.get('status')} {e.get('code')}: {e.get('detail')}"
                           for e in resp.get("errors", [])) or json.dumps(resp)[:400]
        msg = f"{msg}: {detail}"
    sys.exit("ERROR " + msg)


def main():
    apply = "--apply" in sys.argv

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"):
        if not os.environ.get(var):
            die(f"{var} is not set in the environment")

    st, r = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not r.get("data"):
        die("could not find the app", r)
    app_id = r["data"][0]["id"]

    st, r = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")
    if st != 200:
        die("could not list versions", r)
    version = next((v for v in r.get("data", [])
                    if v["attributes"]["appStoreState"] in EDITABLE), None)
    if not version:
        states = [v["attributes"]["appStoreState"] for v in r.get("data", [])]
        die(f"no editable version found (states seen: {states})")
    ver_id = version["id"]
    print(f"version {version['attributes']['versionString']} "
          f"({version['attributes']['appStoreState']})")

    st, r = call("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    if st != 200:
        die("could not list localizations", r)
    loc = next((l for l in r.get("data", []) if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        die(f"no {LOCALE} localization on this version")
    loc_id = loc["id"]
    desc = loc["attributes"].get("description") or ""

    if EULA_URL in desc:
        print("description already contains the EULA link - nothing to do")
        return

    new_desc = desc.rstrip() + "\n\n" + BLOCK
    if len(new_desc) > 4000:
        die(f"new description would be {len(new_desc)} chars, over Apple's 4000 limit")

    print(f"\n--- appending ({len(desc)} -> {len(new_desc)} chars) ---\n{BLOCK}\n")
    if not apply:
        print("dry run - re-run with --apply to write it")
        return

    st, r = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}",
                 {"data": {"type": "appStoreVersionLocalizations", "id": loc_id,
                           "attributes": {"description": new_desc}}})
    if st != 200:
        die("could not update the description", r)
    print("description updated. Submit for review in App Store Connect "
          "(reuse the existing build - no new upload needed).")


if __name__ == "__main__":
    main()
