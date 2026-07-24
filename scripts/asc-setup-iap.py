#!/usr/bin/env python3
"""
Create Tearoff's three in-app purchases in App Store Connect.

Prereqs:
  1. The Tearoff app record must already exist in App Store Connect
     (New App → bundle id com.tearoff.app). Apple's API cannot create the
     app record itself; this is the one manual step.
  2. These env vars must be set (they already are on this machine):
       ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH
     pip install pyjwt cryptography  (already installed here)

Run:
  python3 scripts/asc-setup-iap.py check     # verify app exists + list current IAPs
  python3 scripts/asc-setup-iap.py create     # create sub group + 3 products

Product IDs match VaultCore's TearoffProduct exactly:
  com.tearoff.pro.monthly   ($2.99/mo  auto-renewable)
  com.tearoff.pro.yearly    ($14.99/yr auto-renewable)
  com.tearoff.pro.lifetime  ($39.99    non-consumable)

Pricing, localizations, and review info are quickest to finish in the
portal after the products exist; this script registers the products,
subscription group, and periods.
"""
import os, sys, time, json, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.tearoff.app"
GROUP_NAME = "Tearoff Pro"
SUBS = [
    ("com.tearoff.pro.monthly", "Tearoff Pro Monthly", "ONE_MONTH"),
    ("com.tearoff.pro.yearly",  "Tearoff Pro Yearly",  "ONE_YEAR"),
]
NONCONSUMABLE = ("com.tearoff.pro.lifetime", "Tearoff Pro Lifetime")


def _key():
    with open(os.environ["ASC_PRIVATE_KEY_PATH"]) as f:
        return f.read()


def token():
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, _key(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method)
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
    out = [f"{e.get('status')} {e.get('code')}: {e.get('title')} — {e.get('detail')}"
           for e in resp.get("errors", [])]
    return "; ".join(out) or json.dumps(resp)[:400]


def find_app():
    st, resp = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name,bundleId")
    if st != 200:
        print("ERROR finding app:", st, errs(resp)); sys.exit(1)
    data = resp.get("data", [])
    if not data:
        print(f"No app for {BUNDLE_ID}. Create it in App Store Connect first "
              "(New App → this bundle id), then re-run.")
        sys.exit(2)
    return data[0]["id"], data[0]["attributes"]["name"]


def create_sub_group(app_id):
    st, resp = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
    for g in resp.get("data", []):
        if g["attributes"].get("referenceName") == GROUP_NAME:
            print("  sub group exists:", g["id"]); return g["id"]
    body = {"data": {"type": "subscriptionGroups",
                     "attributes": {"referenceName": GROUP_NAME},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
    st, resp = call("POST", "/v1/subscriptionGroups", body)
    if st not in (200, 201):
        print("  ERROR sub group:", st, errs(resp)); sys.exit(1)
    gid = resp["data"]["id"]; print("  created sub group:", gid); return gid


def create_subscription(group_id, product_id, name, period):
    body = {"data": {"type": "subscriptions", "attributes": {
        "name": name, "productId": product_id, "subscriptionPeriod": period,
        "familySharable": False},
        "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group_id}}}}}
    st, resp = call("POST", "/v1/subscriptions", body)
    if st in (200, 201):
        print(f"  created subscription {product_id}:", resp["data"]["id"])
    elif any(e.get("code") == "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE" or
             "already" in (e.get("detail") or "").lower() for e in resp.get("errors", [])):
        print(f"  subscription {product_id} already exists")
    else:
        print(f"  ERROR subscription {product_id}:", st, errs(resp))


def create_nonconsumable(app_id, product_id, name):
    body = {"data": {"type": "inAppPurchases", "attributes": {
        "name": name, "productId": product_id, "inAppPurchaseType": "NON_CONSUMABLE",
        "familySharable": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
    st, resp = call("POST", "/v2/inAppPurchases", body)
    if st in (200, 201):
        print(f"  created non-consumable {product_id}:", resp["data"]["id"])
    elif any("already" in (e.get("detail") or "").lower() for e in resp.get("errors", [])):
        print(f"  non-consumable {product_id} already exists")
    else:
        print(f"  ERROR non-consumable {product_id}:", st, errs(resp))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    app_id, app_name = find_app()
    print(f"App: {app_id} — {app_name}")
    if cmd == "check":
        st, resp = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200&fields[inAppPurchasesV2]=name,productId,state")
        for p in resp.get("data", []):
            a = p["attributes"]; print("  IAP:", a.get("productId"), a.get("state"))
        st, resp = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?include=subscriptions")
        for s in resp.get("included", []) if resp.get("included") else []:
            print("  SUB:", s["attributes"].get("productId"), s["attributes"].get("state"))
        return
    if cmd == "create":
        gid = create_sub_group(app_id)
        for pid, name, period in SUBS:
            create_subscription(gid, pid, name, period)
        create_nonconsumable(app_id, *NONCONSUMABLE)
        print("Done. Finish pricing + localizations in App Store Connect.")


if __name__ == "__main__":
    main()
