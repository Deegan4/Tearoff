#!/usr/bin/env python3
"""
Attach an uploaded build to a version in App Store Connect, waiting for Apple
to finish processing it first.

A freshly uploaded build appears almost immediately but sits in PROCESSING for
5-15 minutes, and cannot be attached until it reaches VALID. --wait polls
rather than making a human come back to it.

Prereqs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-attach-build.py 1.0.1 11                    # inspect
  python3 scripts/asc-attach-build.py 1.0.1 11 --apply --wait 20  # wait, attach
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
PLATFORM = "IOS"


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


def find_build(app_id, build_number):
    st, r = call("GET", f"/v1/builds?filter[app]={app_id}"
                        f"&filter[version]={build_number}&limit=5")
    if st != 200:
        die("could not list builds", r)
    return r.get("data", [None])[0] if r.get("data") else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        sys.exit("usage: asc-attach-build.py <version> <build> [--apply] [--wait MIN]")
    version_string, build_number = args[0], args[1]
    apply = "--apply" in sys.argv
    wait_min = int(sys.argv[sys.argv.index("--wait") + 1]) if "--wait" in sys.argv else 0

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
    if not version:
        die(f"version {version_string} does not exist - run asc-prepare-version.py first")
    ver_id = version["id"]
    print(f"version {version_string} ({version['attributes']['appStoreState']})")

    deadline = time.time() + wait_min * 60
    while True:
        build = find_build(app_id, build_number)
        state = build["attributes"].get("processingState") if build else "NOT_FOUND"
        print(f"build {build_number}: {state}", flush=True)
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            die(f"build {build_number} finished processing as {state} - it cannot be "
                f"attached; check the email from Apple for the reason")
        if time.time() >= deadline:
            if not apply:
                print("\ndry run - re-run with --apply --wait <minutes> to attach")
                return
            die(f"build {build_number} still {state} after {wait_min} min")
        print("  still processing, checking again in 60s...", flush=True)
        time.sleep(60)

    if not apply:
        print("\ndry run - re-run with --apply to attach it")
        return

    st, r = call("PATCH", f"/v1/appStoreVersions/{ver_id}/relationships/build",
                 {"data": {"type": "builds", "id": build["id"]}})
    if st not in (200, 204):
        die("could not attach the build", r)
    print(f"attached build {build_number} to {version_string}. "
          f"Now run: python3 scripts/asc-submit-for-review.py --apply")


if __name__ == "__main__":
    main()
