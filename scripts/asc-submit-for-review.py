#!/usr/bin/env python3
"""
Submit the editable iOS version for App Review via the App Store Connect API.

Creates a review submission (or reuses an open one), adds the version as an
item, then marks the submission submitted. Reuses the existing build - this
uploads nothing.

Before submitting it names any IAP, subscription or subscription group still
sitting in a blocking state. Those hold the whole submission back, and the API
hides them behind "Version is not ready to be submitted yet" - which reads like
a transient delay and is not one. Clearing each takes a press of "Update
Review" on that purchase's own page in App Store Connect; there is no API for
it, so the script reports them and refuses to spin.

Prereqs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-submit-for-review.py          # inspect, change nothing
  python3 scripts/asc-submit-for-review.py --apply  # actually submit
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
PLATFORM = "IOS"

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}
OPEN_SUBMISSION = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}

# An IAP, subscription or subscription group left in one of these states after a
# rejection holds the whole submission back. The API will not say so: it reports
# only "Version is not ready to be submitted yet", which reads like a transient
# delay and is not one. Each blocker needs "Update Review" pressed on its own
# page in App Store Connect to move it back to READY_FOR_REVIEW.
BLOCKING_ITEM = {"REJECTED", "DEVELOPER_ACTION_NEEDED", "MISSING_METADATA"}


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


def blockers(app_id):
    """Purchases holding the submission back, as (kind, name, state) tuples.

    The submission item endpoint reports a bare state with no usable
    relationship, so walk the purchases themselves to get names worth printing.
    """
    found = []

    st, r = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200")
    if st == 200:
        for i in r.get("data", []):
            a = i["attributes"]
            if a.get("state") in BLOCKING_ITEM:
                found.append(("In-App Purchase", a.get("productId") or a.get("name"), a["state"]))

    st, r = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
    if st == 200:
        for g in r.get("data", []):
            gid = g["id"]
            gname = g["attributes"].get("referenceName") or gid
            gst, gr = call("GET", f"/v1/subscriptionGroups/{gid}/subscriptions?limit=200")
            if gst == 200:
                for s in gr.get("data", []):
                    a = s["attributes"]
                    if a.get("state") in BLOCKING_ITEM:
                        found.append(("Subscription", a.get("productId") or a.get("name"), a["state"]))
            # The group itself carries a review state only via its submission
            # item, so surface it whenever any of its subscriptions is blocked.
            if any(k == "Subscription" for k, _, _ in found):
                found.append(("Subscription Group", gname, "check in App Store Connect"))

    return found


def report_blockers(app_id):
    found = blockers(app_id)
    if not found:
        return False
    print("\nBlocked by these purchases - each needs 'Update Review' pressed on "
          "its own page in App Store Connect:")
    for kind, name, state in found:
        print(f"  - {kind}: {name} [{state}]")
    print("\nUntil every one is back to Ready for Review, 'Resubmit to App "
          "Review' stays greyed out and the API reports only \"Version is not "
          "ready to be submitted yet\". Retrying will not clear it.")
    return True


def main():
    apply = "--apply" in sys.argv

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"):
        if not os.environ.get(var):
            die(f"{var} is not set in the environment")

    st, r = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not r.get("data"):
        die("could not find the app", r)
    app_id = r["data"][0]["id"]

    st, r = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={PLATFORM}&limit=10")
    if st != 200:
        die("could not list versions", r)
    version = next((v for v in r.get("data", [])
                    if v["attributes"]["appStoreState"] in EDITABLE), None)
    if not version:
        states = [v["attributes"]["appStoreState"] for v in r.get("data", [])]
        die(f"no submittable version found (states seen: {states})")
    ver_id = version["id"]
    ver_str = version["attributes"]["versionString"]
    print(f"version {ver_str} ({version['attributes']['appStoreState']})")

    st, r = call("GET", f"/v1/apps/{app_id}/reviewSubmissions?limit=20")
    if st != 200:
        die("could not list review submissions", r)
    subs = [s for s in r.get("data", []) if s["attributes"]["state"] in OPEN_SUBMISSION]

    # Prefer the submission that already holds items - after a rejection that is
    # the one carrying the version and the IAPs, and resubmitting it is what the
    # "Resubmit to App Review" button in App Store Connect does. An empty
    # READY_FOR_REVIEW shell is useless: attaching a version that already belongs
    # to another open submission is refused.
    def item_count(s):
        st, r = call("GET", f"/v1/reviewSubmissions/{s['id']}/items?limit=1")
        return r.get("meta", {}).get("paging", {}).get("total", 0) if st == 200 else 0

    sub = max(subs, key=item_count) if subs else None
    if sub:
        n = item_count(sub)
        print(f"review submission {sub['id']} ({sub['attributes']['state']}, {n} items)")
        if sub["attributes"]["state"] in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
            print("already submitted - nothing to do")
            return

    blocked = report_blockers(app_id)

    if not apply:
        print("\ndry run - re-run with --apply to submit for review")
        return
    if blocked:
        sys.exit("ERROR refusing to submit while purchases are blocked "
                 "(clear them first, then re-run)")

    if not sub or item_count(sub) == 0:
        if not sub:
            st, r = call("POST", "/v1/reviewSubmissions",
                         {"data": {"type": "reviewSubmissions",
                                   "attributes": {"platform": PLATFORM},
                                   "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
            if st not in (200, 201):
                die("could not create a review submission", r)
            sub = r["data"]
            print(f"created review submission {sub['id']}")
        st, r = call("POST", "/v1/reviewSubmissionItems",
                     {"data": {"type": "reviewSubmissionItems",
                               "relationships": {
                                   "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                                   "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
        if st not in (200, 201):
            die("could not attach the version to the submission", r)
        print(f"attached version {ver_str} to the submission")
    sub_id = sub["id"]

    # "Version is not ready to be submitted yet" is worth retrying only briefly:
    # right after a metadata edit Apple does reprocess the version. But the same
    # message is also what a blocked purchase looks like through the API, and
    # that never clears on its own - so re-check for blockers on every attempt
    # and stop the moment one appears, rather than spinning for the full window.
    deadline = time.time() + (int(sys.argv[sys.argv.index("--wait") + 1])
                              if "--wait" in sys.argv else 0) * 60
    while True:
        st, r = call("PATCH", f"/v1/reviewSubmissions/{sub_id}",
                     {"data": {"type": "reviewSubmissions", "id": sub_id,
                               "attributes": {"submitted": True}}})
        if st == 200:
            print(f"SUBMITTED - state is now {r['data']['attributes']['state']}")
            return
        transient = "not ready to be submitted" in json.dumps(r)
        if transient and report_blockers(app_id):
            sys.exit("ERROR blocked by the purchases listed above - not retrying")
        if not transient or time.time() >= deadline:
            die("could not submit for review", r)
        print(f"not ready yet, retrying in 90s "
              f"({int((deadline - time.time()) / 60)} min left)...", flush=True)
        time.sleep(90)


if __name__ == "__main__":
    main()
