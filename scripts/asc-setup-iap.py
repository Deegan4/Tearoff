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
  python3 scripts/asc-setup-iap.py check     # verify app exists + list current IAPs + prices
  python3 scripts/asc-setup-iap.py create    # create sub group + 3 products
  python3 scripts/asc-setup-iap.py price     # set USD prices on all 3 products

Product IDs match VaultCore's TearoffProduct exactly:
  com.tearoff.pro.monthly   ($2.99/mo  auto-renewable)
  com.tearoff.pro.yearly    ($14.99/yr auto-renewable)
  com.tearoff.pro.lifetime  ($39.99    non-consumable)

`price` sets the US storefront price; App Store Connect auto-generates the
equivalent price in every other territory from it. Prices are keyed off
Apple's fixed price points, so the script looks up the USA price point whose
customer price equals the target and assigns it (subscriptions get a
`subscriptionPrice`; the lifetime IAP gets an `inAppPurchasePriceSchedule`
with USA as the base territory). Idempotent: it skips a product already at
the target price. Localizations and review info still finish in the portal.
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

# Target US customer price per product, as the string Apple's price points use.
PRICES_USD = {
    "com.tearoff.pro.monthly":  "2.99",
    "com.tearoff.pro.yearly":   "14.99",
    "com.tearoff.pro.lifetime": "39.99",
}
USA = "USA"  # App Store territory id for the United States.


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
    # `path` may be a relative path or a full pagination URL (links.next).
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(
        url,
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


def get_all(path):
    """GET every page of a collection, following links.next. Returns the
    flattened data list, or None on the first non-200 (after printing it)."""
    items, url = [], path
    while url:
        st, resp = call("GET", url)
        if st != 200:
            print("  ERROR paging:", st, errs(resp)); return None
        items.extend(resp.get("data", []))
        url = (resp.get("links") or {}).get("next")
    return items


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


# ---- product lookup -------------------------------------------------------

def subscriptions(app_id):
    """Map productId -> subscription id for the app's subscriptions."""
    st, resp = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?include=subscriptions&limit=200")
    out = {}
    for s in resp.get("included", []) or []:
        if s.get("type") == "subscriptions":
            out[s["attributes"]["productId"]] = s["id"]
    return out


def nonconsumables(app_id):
    """Map productId -> IAP id for the app's one-time purchases."""
    items = get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId") or []
    return {p["attributes"]["productId"]: p["id"] for p in items}


# ---- pricing --------------------------------------------------------------

def find_price_point(items, target):
    """Return the price point id whose US customer price equals `target`."""
    for pp in items or []:
        if pp["attributes"].get("customerPrice") == target:
            return pp["id"]
    return None


def sub_current_prices(sub_id):
    """Set of US customer-price strings currently on a subscription."""
    st, resp = call("GET",
        f"/v1/subscriptions/{sub_id}/prices?include=subscriptionPricePoint&limit=200")
    points = {p["id"]: p["attributes"].get("customerPrice")
              for p in resp.get("included", []) or []
              if p.get("type") == "subscriptionPricePoints"}
    prices = set()
    for pr in resp.get("data", []):
        rel = pr.get("relationships", {}).get("subscriptionPricePoint", {}).get("data")
        if rel and rel["id"] in points:
            prices.add(points[rel["id"]])
    return prices


def price_subscription(sub_id, product_id, target):
    if target in sub_current_prices(sub_id):
        print(f"  {product_id} already priced ${target}"); return
    points = get_all(f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]={USA}&limit=200")
    pp_id = find_price_point(points, target)
    if not pp_id:
        print(f"  ERROR {product_id}: no US price point for ${target}"); return
    body = {"data": {"type": "subscriptionPrices",
        "attributes": {"startDate": None, "preserveCurrentPrice": False},
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp_id}}}}}
    st, resp = call("POST", "/v1/subscriptionPrices", body)
    if st in (200, 201):
        print(f"  priced {product_id} at ${target}")
    else:
        print(f"  ERROR pricing {product_id}:", st, errs(resp))


def iap_current_prices(iap_id):
    """Set of US customer-price strings on the IAP's active price schedule."""
    st, resp = call("GET",
        f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule?include=manualPrices,automaticPrices"
        "&fields[inAppPurchasePrices]=startDate")
    # The included price points carry the customer price; gather them all.
    return {p["attributes"].get("customerPrice")
            for p in resp.get("included", []) or []
            if p.get("type") == "inAppPurchasePricePoints"}


def price_nonconsumable(iap_id, product_id, target):
    if target in iap_current_prices(iap_id):
        print(f"  {product_id} already priced ${target}"); return
    points = get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]={USA}&limit=200")
    pp_id = find_price_point(points, target)
    if not pp_id:
        print(f"  ERROR {product_id}: no US price point for ${target}"); return
    # A price schedule is a compound create: the manual US price is an included
    # object the top-level relationship points at by a client-chosen temp id.
    ph = "usd-base"
    body = {"data": {"type": "inAppPurchasePriceSchedules",
        "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
            "baseTerritory": {"data": {"type": "territories", "id": USA}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": ph}]}}},
      "included": [{"type": "inAppPurchasePrices", "id": ph,
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp_id}},
                "territory": {"data": {"type": "territories", "id": USA}}}}]}
    st, resp = call("POST", "/v1/inAppPurchasePriceSchedules", body)
    if st in (200, 201):
        print(f"  priced {product_id} at ${target}")
    else:
        print(f"  ERROR pricing {product_id}:", st, errs(resp))


def set_prices(app_id):
    subs = subscriptions(app_id)
    for pid, _, _ in SUBS:
        if pid in subs:
            price_subscription(subs[pid], pid, PRICES_USD[pid])
        else:
            print(f"  {pid} not found — run `create` first")
    ncs = nonconsumables(app_id)
    npid = NONCONSUMABLE[0]
    if npid in ncs:
        price_nonconsumable(ncs[npid], npid, PRICES_USD[npid])
    else:
        print(f"  {npid} not found — run `create` first")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    app_id, app_name = find_app()
    print(f"App: {app_id} — {app_name}")
    if cmd == "check":
        st, resp = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=name,productId,state")
        for p in resp.get("data", []):
            a = p["attributes"]
            prices = iap_current_prices(p["id"])
            price = next((x for x in prices if x), None)
            print("  IAP:", a.get("productId"), a.get("state"),
                  f"${price}" if price else "(no price)")
        st, resp = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?include=subscriptions")
        for s in resp.get("included", []) if resp.get("included") else []:
            if s.get("type") != "subscriptions":
                continue
            prices = sub_current_prices(s["id"])
            price = next(iter(prices), None)
            print("  SUB:", s["attributes"].get("productId"), s["attributes"].get("state"),
                  f"${price}" if price else "(no price)")
        return
    if cmd == "create":
        gid = create_sub_group(app_id)
        for pid, name, period in SUBS:
            create_subscription(gid, pid, name, period)
        create_nonconsumable(app_id, *NONCONSUMABLE)
        print("Done. Run `price` to set prices, then finish localizations in App Store Connect.")
        return
    if cmd == "price":
        set_prices(app_id)
        print("Done. Verify with `check`; finish localizations + review info in App Store Connect.")
        return
    print(f"Unknown command '{cmd}'. Use: check | create | price")


if __name__ == "__main__":
    main()
