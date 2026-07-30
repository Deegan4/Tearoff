#!/usr/bin/env python3
"""
Create the next iOS version in App Store Connect and set its release notes.

Runs before the build finishes processing - a version can exist with no build
attached, so the notes are ready and waiting when the upload lands.

Idempotent: reuses the version if it already exists, and only rewrites the
notes when they differ.

Prereqs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-prepare-version.py 1.0.1          # show what would change
  python3 scripts/asc-prepare-version.py 1.0.1 --apply  # write it
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
PLATFORM = "IOS"
LOCALE = "en-US"

RELEASE_NOTES = {
    "1.0.1": """Fixes Pro not unlocking after you redeem a code in the App Store. If you were affected, Pro appears as soon as you reopen Tearoff — your purchase was never lost.

Also in this update:

• Redeem a code directly from the Pro screen, without leaving the app.
• Tearoff now tells you when notification permission is off. Deadline alerts were failing silently, which is the one thing this app cannot do quietly.
• Export failures are reported instead of the button doing nothing."""
}


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
                           for e in resp.get("errors", [])) or json.dumps(resp)[:600]
        msg = f"{msg}: {detail}"
    sys.exit("ERROR " + msg)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit("usage: asc-prepare-version.py <version> [--apply]")
    version_string = args[0]
    apply = "--apply" in sys.argv

    notes = RELEASE_NOTES.get(version_string)
    if not notes:
        die(f"no release notes defined for {version_string} - add them to RELEASE_NOTES")
    if len(notes) > 4000:
        die(f"release notes are {len(notes)} chars, over Apple's 4000 limit")

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"):
        if not os.environ.get(var):
            die(f"{var} is not set in the environment")

    st, r = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not r.get("data"):
        die("could not find the app", r)
    app_id = r["data"][0]["id"]

    st, r = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={PLATFORM}&limit=20")
    if st != 200:
        die("could not list versions", r)
    version = next((v for v in r.get("data", [])
                    if v["attributes"]["versionString"] == version_string), None)

    if version:
        print(f"version {version_string} exists ({version['attributes']['appStoreState']})")
    else:
        print(f"version {version_string} does not exist yet - would create it")
        if not apply:
            print(f"\n--- release notes ({len(notes)} chars) ---\n{notes}\n")
            print("dry run - re-run with --apply to write it")
            return
        st, r = call("POST", "/v1/appStoreVersions",
                     {"data": {"type": "appStoreVersions",
                               "attributes": {"platform": PLATFORM,
                                              "versionString": version_string},
                               "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if st not in (200, 201):
            die("could not create the version", r)
        version = r["data"]
        print(f"created version {version_string}")

    ver_id = version["id"]
    st, r = call("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    if st != 200:
        die("could not list localizations", r)
    loc = next((l for l in r.get("data", []) if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        die(f"no {LOCALE} localization on version {version_string}")

    current = (loc["attributes"].get("whatsNew") or "").strip()
    if current == notes.strip():
        print("release notes already match - nothing to do")
        return

    print(f"\n--- release notes ({len(notes)} chars) ---\n{notes}\n")
    if not apply:
        print("dry run - re-run with --apply to write it")
        return

    st, r = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
                 {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                           "attributes": {"whatsNew": notes}}})
    if st != 200:
        die("could not set the release notes", r)
    print(f"release notes set on {version_string}. Attach the build once it "
          f"finishes processing, then run scripts/asc-submit-for-review.py --apply")


if __name__ == "__main__":
    main()
