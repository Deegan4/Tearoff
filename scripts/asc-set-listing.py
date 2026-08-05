#!/usr/bin/env python3
"""
Push the App Store listing metadata in docs/app-store-listing.md to App Store
Connect: name, subtitle, keywords, promotional text, description, and what's
new, plus the support and marketing URLs.

Two ASC resources are involved and they are easy to confuse:

  appInfoLocalizations        name, subtitle, privacyPolicyUrl   (app-level)
  appStoreVersionLocalizations  keywords, promotionalText,       (per-version)
                                description, whatsNew,
                                supportUrl, marketingUrl

Name and subtitle are app-level, so they only accept writes while an app info
is in an editable state. Everything else rides on the editable version.

Idempotent: every field is compared first, and only differences are written.

Prereqs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (pip: pyjwt, cryptography)

Run:
  python3 scripts/asc-set-listing.py            # diff against what's live
  python3 scripts/asc-set-listing.py --apply    # write the differences
  python3 scripts/asc-set-listing.py --apply --only keywords,subtitle
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
LOCALE = "en-US"

EDITABLE_VERSION = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                    "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}

# Apple's caps. Exceeding one is a hard API error, so it is checked locally
# first with a message that says which field and by how much.
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170,
          "description": 4000, "whatsNew": 4000}

# ---------------------------------------------------------------------------
# The listing itself. Source of truth is docs/app-store-listing.md — keep the
# two in step, and treat that document as the place to edit prose.
# ---------------------------------------------------------------------------

APP_INFO = {
    "name": "Tearoff: Receipt Deadlines",
    "subtitle": "Return & Warranty Reminders",
    "privacyPolicyUrl": "https://deegan4.github.io/Tearoff/privacy.html",
}

KEYWORDS = ("scanner,tracker,refund,expiry,policy,organizer,proof,"
            "purchase,alerts,window,exchange,slip,guarantee")

PROMOTIONAL_TEXT = (
    "Every purchase has a clock on it. Scan a receipt, and Tearoff tracks the "
    "return window and the warranty — then reminds you before either one closes."
)

DESCRIPTION = """You didn't mean to keep it. You just forgot the receipt was in your pocket, the box was still in the hall, and the 30 days were up on Tuesday.

Tearoff puts a clock on every purchase. Scan the receipt, and it tracks two deadlines — when you can still return the item, and how long the warranty runs — then reminds you before either one closes.

SCAN IT, OR TYPE IT
Point the camera at a paper receipt and Tearoff reads it on your device: merchant, date, total, and any return or warranty terms printed on the slip itself. No account, no upload, no sign-up. Your first three scans are free, so you can see it work before you decide anything. Prefer to log it by hand? That takes about ten seconds and is free, forever.

IT TELLS YOU WHERE EVERY DATE CAME FROM
This is the part other trackers skip. A deadline is only worth trusting if you know where it came from, so Tearoff labels every single one:

• "You set this" — you entered or corrected it
• "Printed on your receipt" — read straight off the slip
• "Published return policy" — from a curated retailer policy table
• "Estimate" — a typical window for that kind of purchase, clearly flagged

When Tearoff isn't sure, it says so instead of inventing a date. It will never quietly hand you a confident-looking deadline it can't justify.

RETAILER POLICIES, DATED AND VERSIONED
Return policies change. Tearoff's policy table records when each one took effect, so a purchase you made last spring keeps the policy that was actually in force when you bought it — not whatever the store switched to since.

A REMINDER WHILE IT STILL MATTERS
Alerts arrive with enough runway to actually drive to the store. The Home Screen widget keeps your next closing deadline in view, so the vault isn't something you have to remember to open.

PRINT A PROOF SLIP
Every saved purchase prints as a clean thermal-style receipt with the return-by date, the warranty date, and a scannable barcode — ready to hand over at the returns desk or share with whoever gave you the gift.

YOUR VAULT, YOUR DEVICE
No account. No ads. No analytics on your receipts. Everything lives on your iPhone and syncs through your own private iCloud account if you're signed in. Tearoff's usage counters are counts only, stored on-device, and never leave it.

FREE
• Log purchases by hand, unlimited
• Three receipt scans to try
• Return-deadline tracking and reminders
• Your full receipt vault

TEAROFF PRO
• Unlimited camera scanning with on-device receipt extraction
• Warranty tracking and warranty alerts
• One tap straight to the retailer's own returns page
• Home Screen widgets, with snooze
• A nudge when you're near a store where something is still returnable
• Export your vault as CSV, plus a Year in Review PDF

Pro is $2.99/month, $14.99/year, or $39.99 once for lifetime access.

Made for iOS 26. Built in SwiftUI, with the deadline logic in a separate, fully tested package — because the part that's least allowed to guess is the part most worth testing.

—
Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account at confirmation of purchase. Manage or cancel in your Apple Account settings.
Privacy Policy: https://deegan4.github.io/Tearoff/privacy.html
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

WHATS_NEW = """• Pro now unlocks correctly when you buy or restore it outside the app
• Redeem an offer code without leaving Tearoff
• Alerts and export no longer fail silently — if something goes wrong, it says so
• More reliable purchase verification behind the scenes

Thanks for trying Tearoff. If something isn't working, the support link on our site reaches us directly."""

VERSION_FIELDS = {
    "keywords": KEYWORDS,
    "promotionalText": PROMOTIONAL_TEXT,
    "description": DESCRIPTION,
    "whatsNew": WHATS_NEW,
    "supportUrl": "https://deegan4.github.io/Tearoff/#support",
    "marketingUrl": "https://deegan4.github.io/Tearoff/",
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
                           for e in resp.get("errors", [])) or json.dumps(resp)[:400]
        msg = f"{msg}: {detail}"
    sys.exit("ERROR " + msg)


def preview(value, width=72):
    """One-line preview of a possibly multi-line field."""
    flat = " ".join((value or "").split())
    return flat if len(flat) <= width else flat[:width - 1] + "…"


def diff_fields(current, wanted, only):
    """Fields whose live value differs from what we want to set."""
    out = {}
    for field, value in wanted.items():
        if only and field not in only:
            continue
        if (current.get(field) or "") != value:
            out[field] = value
    return out


def check_limits(fields):
    for field, value in fields.items():
        cap = LIMITS.get(field)
        if cap and len(value) > cap:
            die(f"{field} is {len(value)} chars, {len(value) - cap} over Apple's {cap} limit")


def report(label, current, changes, skipped_note=None):
    print(f"\n=== {label} ===")
    if skipped_note:
        print(f"  {skipped_note}")
        return
    if not changes:
        print("  already matches - nothing to do")
        return
    for field, value in changes.items():
        cap = LIMITS.get(field)
        size = f" [{len(value)}/{cap}]" if cap else ""
        print(f"  {field}{size}")
        print(f"    from: {preview(current.get(field) or '(empty)')}")
        print(f"      to: {preview(value)}")


def main():
    apply = "--apply" in sys.argv
    only = set()
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"):
        if not os.environ.get(var):
            die(f"{var} is not set in the environment")

    st, r = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not r.get("data"):
        die("could not find the app", r)
    app_id = r["data"][0]["id"]

    # --- app-level: name, subtitle, privacy policy URL ----------------------
    st, r = call("GET", f"/v1/apps/{app_id}/appInfos")
    if st != 200:
        die("could not list app infos", r)
    # The editable app info is the one not yet locked to a live version.
    info = next((i for i in r.get("data", [])
                 if i["attributes"].get("appStoreState") in EDITABLE_VERSION), None)
    info_changes, info_current, info_loc_id = {}, {}, None
    info_note = None
    if not info:
        states = [i["attributes"].get("appStoreState") for i in r.get("data", [])]
        info_note = (f"no editable app info (states: {states}) - name and subtitle "
                     "can only change alongside a version under review")
    else:
        st, r = call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")
        if st != 200:
            die("could not list app info localizations", r)
        loc = next((l for l in r.get("data", []) if l["attributes"]["locale"] == LOCALE), None)
        if not loc:
            die(f"no {LOCALE} app info localization")
        info_loc_id = loc["id"]
        info_current = loc["attributes"]
        info_changes = diff_fields(info_current, APP_INFO, only)

    # --- version-level: everything else -------------------------------------
    st, r = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")
    if st != 200:
        die("could not list versions", r)
    version = next((v for v in r.get("data", [])
                    if v["attributes"]["appStoreState"] in EDITABLE_VERSION), None)
    wanted_version_fields = VERSION_FIELDS
    if not version:
        # Nothing editable: the app is live. Apple still allows promotional
        # text to change on a shipped version without another review pass, so
        # fall back to that one field rather than refusing outright. Everything
        # else genuinely needs a new version.
        version = next((v for v in r.get("data", [])
                        if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)
        if not version:
            states = [v["attributes"]["appStoreState"] for v in r.get("data", [])]
            die(f"no editable and no live version found (states seen: {states})")
        wanted_version_fields = {"promotionalText": VERSION_FIELDS["promotionalText"]}
        print("NOTE the live version is the only one available. Promotional text "
              "can still be updated without review; name, subtitle, keywords,\n"
              "     description and what's new need a new version — create one with\n"
              "     python3 scripts/asc-prepare-version.py")
    ver_id = version["id"]
    print(f"app {app_id} · version {version['attributes']['versionString']} "
          f"({version['attributes']['appStoreState']})")

    st, r = call("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    if st != 200:
        die("could not list version localizations", r)
    loc = next((l for l in r.get("data", []) if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        die(f"no {LOCALE} localization on this version")
    ver_loc_id = loc["id"]
    ver_current = loc["attributes"]
    ver_changes = diff_fields(ver_current, wanted_version_fields, only)

    check_limits({**info_changes, **ver_changes})
    report("App information (name, subtitle)", info_current, info_changes, info_note)
    report("Version metadata", ver_current, ver_changes)

    if not info_changes and not ver_changes:
        print("\nEverything already matches. Nothing written.")
        return

    if not apply:
        print("\ndry run - re-run with --apply to write it")
        return

    if info_changes:
        st, r = call("PATCH", f"/v1/appInfoLocalizations/{info_loc_id}",
                     {"data": {"type": "appInfoLocalizations", "id": info_loc_id,
                               "attributes": info_changes}})
        if st != 200:
            die("could not update app info", r)
        print(f"\nwrote app info: {', '.join(info_changes)}")

    if ver_changes:
        st, r = call("PATCH", f"/v1/appStoreVersionLocalizations/{ver_loc_id}",
                     {"data": {"type": "appStoreVersionLocalizations", "id": ver_loc_id,
                               "attributes": ver_changes}})
        if st != 200:
            die("could not update version metadata", r)
        print(f"wrote version metadata: {', '.join(ver_changes)}")

    print("\nNot submitted for review - this only stages the metadata. "
          "Review it in App Store Connect, then submit when you're ready.")


if __name__ == "__main__":
    main()
