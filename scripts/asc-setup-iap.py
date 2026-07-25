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
  python3 scripts/asc-setup-iap.py meta      # fill listing copy, IAP/sub localizations, category

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
EN = "en-US"

# ---- listing copy (en-US) -------------------------------------------------
# App Store field limits: subtitle 30, keywords 100, promo 170, IAP/sub name 30,
# IAP/sub description 45, app description 4000. Kept within them below.
PRIMARY_CATEGORY = "UTILITIES"
SUPPORT_URL = "https://github.com/Deegan4/Tearoff/issues"
# GitHub renders this Markdown at a public, reachable URL (resolves once the
# PRIVACY.md on `main` is merged).
PRIVACY_URL = "https://github.com/Deegan4/Tearoff/blob/main/PRIVACY.md"

SUBTITLE = "Never miss a return window"
KEYWORDS = "receipt,return,warranty,refund,deadline,reminder,tracker,expense,scanner,purchases"
PROMO_TEXT = ("Scan a receipt and Tearoff tracks its return and warranty "
              "deadlines, then reminds you before they close. Your data stays "
              "on your device and your private iCloud.")
DESCRIPTION = (
    "Tearoff turns a paper receipt into a deadline you won't miss.\n\n"
    "Every purchase has a clock on it — a return window that closes, a warranty "
    "that expires. Tearoff tracks both and reminds you before they run out, so "
    "you never eat the cost of a missed return or a lapsed warranty again.\n\n"
    "HOW IT WORKS\n"
    "- Add a purchase or scan its receipt.\n"
    "- Tearoff works out the return and warranty windows and shows exactly "
    "where each date came from — printed on the receipt, a store policy, or an "
    "estimate — so you always know how much to trust it.\n"
    "- You get a reminder before each deadline, and a Home Screen widget that "
    "keeps the next ones in view.\n\n"
    "PRIVATE BY DESIGN\n"
    "Your receipts stay on your device and sync only through your own private "
    "iCloud. No accounts, no ads, no tracking, and nothing sent to us.\n\n"
    "FREE\n"
    "- Add receipts by hand\n"
    "- Return-deadline reminders\n"
    "- Your full receipt vault\n\n"
    "TEAROFF PRO\n"
    "- Scan receipts with the camera and let Tearoff read them for you\n"
    "- Warranty tracking\n"
    "- Export your vault\n"
    "- Home Screen widgets\n\n"
    "Pro is available monthly, yearly, or as a one-time lifetime purchase.")

# Subscription group display name shown to users at purchase.
GROUP_DISPLAY_NAME = "Tearoff Pro"
# (productId, display name <=30, description <=45)
SUB_LOCALIZATION = [
    ("com.tearoff.pro.monthly", "Tearoff Pro Monthly", "All Pro features, billed monthly."),
    ("com.tearoff.pro.yearly",  "Tearoff Pro Yearly",  "All Pro features, billed yearly."),
]
LIFETIME_NAME = "Tearoff Pro Lifetime"
LIFETIME_DESC = "All Pro features, one-time purchase."


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
    elif st == 409:
        # Apple's API cannot create the FIRST (base) price for a subscription —
        # it returns a generic RELATIONSHIP.INVALID. The initial price must be
        # set once in the App Store Connect UI; after that the API can manage it.
        print(f"  {product_id}: set the initial ${target} price once in the ASC "
              f"UI (Apple API can't create a subscription's first price).")
    else:
        print(f"  ERROR pricing {product_id}:", st, errs(resp))


def iap_current_prices(iap_id):
    """Set of US customer-price strings on the IAP's active price schedule.
    The schedule's id equals the IAP id; its manual prices carry the point."""
    st, resp = call("GET",
        f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices"
        "?include=inAppPurchasePricePoint")
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
    # object the top-level relationship points at by a client-chosen local id,
    # which Apple requires in ${...} form for inline creation.
    ph = "${usd-base}"
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


# ---- listing metadata -----------------------------------------------------

def upsert_localization(kind, list_path, rel_name, parent_type, parent_id, locale, attrs):
    """Create or update one localization row. Looks it up by locale in
    `list_path`; PATCHes if it exists, else POSTs with the parent relationship.
    `kind` is the resource type (also its /v1 collection path)."""
    sep = "&" if "?" in list_path else "?"
    st, resp = call("GET", f"{list_path}{sep}limit=200")
    existing = None
    if st == 200:
        existing = next((x for x in resp.get("data", [])
                         if x["attributes"].get("locale") == locale), None)
    if existing:
        body = {"data": {"type": kind, "id": existing["id"], "attributes": attrs}}
        st, r = call("PATCH", f"/v1/{kind}/{existing['id']}", body)
        verb = "updated"
    else:
        a = dict(attrs); a["locale"] = locale
        body = {"data": {"type": kind, "attributes": a,
                         "relationships": {rel_name: {"data": {"type": parent_type, "id": parent_id}}}}}
        st, r = call("POST", f"/v1/{kind}", body)
        verb = "created"
    if st in (200, 201):
        print(f"  {verb} {kind} [{locale}]")
        return True
    print(f"  ERROR {kind} [{locale}]:", st, errs(r))
    return False


def set_category(app_id):
    st, infos = call("GET", f"/v1/apps/{app_id}/appInfos")
    for inf in infos.get("data", []):
        if inf["attributes"].get("state") != "PREPARE_FOR_SUBMISSION":
            continue
        body = {"data": {"type": "appInfos", "id": inf["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY_CATEGORY}}}}}
        st, r = call("PATCH", f"/v1/appInfos/{inf['id']}", body)
        print(f"  category {PRIMARY_CATEGORY}:",
              "set" if st in (200, 201) else errs(r))


def set_meta(app_id):
    # Subscription group display name.
    st, groups = call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
    for g in groups.get("data", []):
        if g["attributes"].get("referenceName") == GROUP_NAME:
            upsert_localization(
                "subscriptionGroupLocalizations",
                f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations",
                "subscriptionGroup", "subscriptionGroups", g["id"], EN,
                {"name": GROUP_DISPLAY_NAME})

    # Per-subscription name + description.
    subs = subscriptions(app_id)
    for pid, disp, desc in SUB_LOCALIZATION:
        if pid in subs:
            upsert_localization(
                "subscriptionLocalizations",
                f"/v1/subscriptions/{subs[pid]}/subscriptionLocalizations",
                "subscription", "subscriptions", subs[pid], EN,
                {"name": disp, "description": desc})
        else:
            print(f"  {pid} not found — run `create` first")

    # Non-consumable name + description.
    ncs = nonconsumables(app_id)
    lid = ncs.get(NONCONSUMABLE[0])
    if lid:
        upsert_localization(
            "inAppPurchaseLocalizations",
            f"/v2/inAppPurchases/{lid}/inAppPurchaseLocalizations",
            "inAppPurchaseV2", "inAppPurchases", lid, EN,
            {"name": LIFETIME_NAME, "description": LIFETIME_DESC})
    else:
        print(f"  {NONCONSUMABLE[0]} not found — run `create` first")

    # App version listing: description, keywords, promo, support URL.
    st, vers = call("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=1")
    if vers.get("data"):
        vid = vers["data"][0]["id"]
        upsert_localization(
            "appStoreVersionLocalizations",
            f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations",
            "appStoreVersion", "appStoreVersions", vid, EN,
            {"description": DESCRIPTION, "keywords": KEYWORDS,
             "supportUrl": SUPPORT_URL, "promotionalText": PROMO_TEXT})

    # App info: subtitle + privacy policy URL (name already set).
    st, infos = call("GET", f"/v1/apps/{app_id}/appInfos")
    for inf in infos.get("data", []):
        if inf["attributes"].get("state") != "PREPARE_FOR_SUBMISSION":
            continue
        upsert_localization(
            "appInfoLocalizations",
            f"/v1/appInfos/{inf['id']}/appInfoLocalizations",
            "appInfo", "appInfos", inf["id"], EN,
            {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL})

    set_category(app_id)


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
        print("Done. Verify with `check`.")
        return
    if cmd == "meta":
        set_meta(app_id)
        print("Done. Verify with `check`. Still manual in ASC: screenshots, "
              "age rating, and the App Privacy (data collection) questions.")
        return
    print(f"Unknown command '{cmd}'. Use: check | create | price | meta")


if __name__ == "__main__":
    main()
