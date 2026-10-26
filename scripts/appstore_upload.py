"""Fills in the App Store version page through the App Store Connect API: text (from
appstore/metadata.json), screenshots (from appstore/screenshots), copyright, review notes, and the build.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the API key), BUILD (a build number, or empty for the newest
processed one), CONTACT_NAME / CONTACT_PHONE / CONTACT_EMAIL (App Review's contact; empty leaves it as is),
SUBMIT=1 to submit the version for App Review once it's filled in, SKIP_SCREENSHOTS=1 to keep the
screenshots already uploaded. Run by .github/workflows/appstore-metadata.yml. Needs PyJWT and cryptography.
Screenshots replace whatever is in each set, so running it twice is safe.
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.bradcowdrey.twodegrees"
EDITABLE = "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY"
ROOT = os.path.join(os.path.dirname(__file__), "..", "appstore")


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:   # Apple's reasons, on one line so they show in the annotation
            errors = json.loads(detail).get("errors", [])
            detail = " | ".join(f"{x.get('title', '')}: {x.get('detail', '')}" + "".join(
                f" [{a.get('code', '')}] {a.get('detail', a.get('title', ''))}" for a in (x.get("meta") or {}).get("associatedErrors", {}).get(next(iter((x.get("meta") or {}).get("associatedErrors", {}) or [""]), ""), []) if isinstance(a, dict))
                for x in errors) or detail
        except ValueError:
            pass
        print(f"::error::{method} {path} → {e.code}: {' '.join(detail.split())[:1500]}")
        raise SystemExit(1)


def step(text):
    print(f"== {text}", flush=True)


def main():
    meta = json.load(open(os.path.join(ROOT, "metadata.json")))

    step("App and version")
    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    versions = call("GET", f"/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]={EDITABLE}")["data"]
    if not versions:
        print("::error::No iOS version waiting to be submitted. Create one in App Store Connect (＋ next to iOS App).")
        raise SystemExit(1)
    version = versions[0]
    print(f"app {app['attributes']['name']}, version {version['attributes']['versionString']} ({version['attributes']['appStoreState']})")

    step("Copyright")
    call("PATCH", f"/appStoreVersions/{version['id']}",
         {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": {"copyright": meta["copyright"]}}})

    step("Text")
    locs = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == meta["locale"]), locs[0])
    call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"],
        "attributes": {k: meta[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}}})
    print(f"{loc['attributes']['locale']}: description, keywords, promotional text, support and marketing URLs")

    step("Build")
    number = os.environ.get("BUILD", "").strip()
    query = f"/builds?filter[app]={app['id']}&filter[preReleaseVersion.platform]=IOS&filter[processingState]=VALID&sort=-uploadedDate&limit=20"
    if number:
        query += f"&filter[version]={number}"
    builds = call("GET", query)["data"]
    if not builds:
        print(f"::error::No processed build {number or ''} yet; Apple may still be processing it. Try again in a few minutes.")
        raise SystemExit(1)
    build = builds[0]
    call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    print(f"build {build['attributes']['version']}")

    step("App Review notes and contact")
    detail = call("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attrs = {"notes": meta["reviewNotes"], "demoAccountRequired": False}
    name = os.environ.get("CONTACT_NAME", "").strip().split(" ", 1)
    for key, value in [("contactFirstName", name[0] if name[0] else ""), ("contactLastName", name[1] if len(name) > 1 else ""),
                       ("contactPhone", os.environ.get("CONTACT_PHONE", "").strip()), ("contactEmail", os.environ.get("CONTACT_EMAIL", "").strip())]:
        if value:
            attrs[key] = value
    if "contactPhone" in attrs:
        print("contact details set")
    if detail:
        call("PATCH", f"/appStoreReviewDetails/{detail['id']}", {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}})
    else:
        call("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print("notes set; sign-in not required (your contact details stay yours to enter)")

    if os.environ.get("SKIP_SCREENSHOTS") == "1":
        print("== Screenshots: kept as uploaded")
    else:
        step("Screenshots")
        sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        for display, files in meta["screenshots"].items():
            shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display), None)
            if not shot_set:
                shot_set = call("POST", "/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                                "attributes": {"screenshotDisplayType": display},
                                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
            for old in call("GET", f"/appScreenshotSets/{shot_set['id']}/appScreenshots")["data"]:
                call("DELETE", f"/appScreenshots/{old['id']}")
            for name in files:
                data = open(os.path.join(ROOT, "screenshots", name), "rb").read()
                shot = call("POST", "/appScreenshots", {"data": {"type": "appScreenshots",
                            "attributes": {"fileName": name, "fileSize": len(data)},
                            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": shot_set["id"]}}}}})["data"]
                for op in shot["attributes"]["uploadOperations"]:
                    part = data[op["offset"]:op["offset"] + op["length"]]
                    req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                                 headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                    urllib.request.urlopen(req).read()
                call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
                     "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
                print(f"{display}: {name}")

        # Apple processes uploads for a moment; report any it rejects.
        time.sleep(20)
        problems = []
        for s in call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
            for shot in call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
                state = (shot["attributes"].get("assetDeliveryState") or {}).get("state")
                if state == "FAILED":
                    problems.append(f"{shot['attributes']['fileName']}: {shot['attributes']['assetDeliveryState'].get('errors')}")
        for p in problems:
            print(f"::error::Screenshot rejected: {p}")
        if problems:
            raise SystemExit(1)
    if os.environ.get("SUBMIT") == "1":
        step("Submit for App Review")
        open_subs = call("GET", f"/reviewSubmissions?filter[app]={app['id']}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"]
        sub = open_subs[0] if open_subs else call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions",
              "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        if not call("GET", f"/reviewSubmissions/{sub['id']}/items")["data"]:
            call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                 "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
        call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
        state = call("GET", f"/reviewSubmissions/{sub['id']}")["data"]["attributes"]["state"]
        print(f"::notice::Submitted version {version['attributes']['versionString']} (build {build['attributes']['version']}) for App Review: {state}.")
        return
    print(f"::notice::Version {version['attributes']['versionString']} is filled in with build {build['attributes']['version']}: text, screenshots, copyright and review notes. Add your contact details under App Review Information, then Add for Review.")


if __name__ == "__main__":
    main()
