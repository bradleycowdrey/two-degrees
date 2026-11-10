"""Opens the iPhone and iPad app to anyone through a public TestFlight link, until the App Store listing is live.

Through the App Store Connect API it fills in the beta app's test information (description, feedback email,
privacy and marketing URLs) and its Beta App Review contact and notes, gives the build its What to Test text
(the top of CHANGELOG.md), answers the export compliance question if the build hasn't, adds the build to an
external group named "Public", submits it for Beta App Review, and turns on the group's public link.
Each step checks what is already there first, so running it again only does what's missing.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the API key), BUILD (a build number, or empty for the newest
processed one), WAIT_MINUTES (how long to wait for that build to finish processing, default 0),
CONTACT_NAME / CONTACT_PHONE / CONTACT_EMAIL (Beta App Review's contact and the testers' feedback email).
Run by .github/workflows/testflight-public.yml. Needs PyJWT and cryptography.
"""
import json
import os
import re
import time

from appstore_upload import BUNDLE_ID, call, step

GROUP = "Public"
PRIVACY_URL = "https://bradcowdrey.com/legal"
MARKETING_URL = "https://bradcowdrey.com/two-degrees"
HERE = os.path.dirname(os.path.abspath(__file__))
META = json.load(open(os.path.join(HERE, "..", "appstore", "metadata.json")))


def soft_call(method, path, body=None):
    """Like call, but returns None on an error instead of stopping, for steps Apple may not allow yet."""
    try:
        return call(method, path, body)
    except SystemExit:
        return None


def whats_new(version):
    """The CHANGELOG.md section for this version (the newest one if it has none), as plain text."""
    text = open(os.path.join(HERE, "..", "CHANGELOG.md"), encoding="utf-8").read()
    sections = re.split(r"^## ", text, flags=re.M)
    released = [s for s in sections[1:] if s.startswith("[")]
    newest = next((s for s in released if s.startswith(f"[{version}]")), released[0])
    title, _, body = newest.partition("\n")
    body = re.sub(r"\*\*(.+?)\*\*", r"\1", body)               # bold
    body = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", body)        # links keep their text
    body = re.sub(r"\n  +", " ", body).strip()                  # wrapped list items on one line
    version = title.split("]")[0].strip("[")
    return f"Two Degrees {version}\n\n{body}\n\nEvery temperature in °F and °C at once. Tell us what you think with TestFlight's Send Beta Feedback."[:4000]


def find_build(app, number, wait_minutes):
    """The build to share: the given number, or the newest processed one. Waits for processing if asked."""
    deadline = time.time() + wait_minutes * 60
    base = f"/builds?filter[app]={app['id']}&filter[preReleaseVersion.platform]=IOS&filter[expired]=false&sort=-uploadedDate&limit=10"
    while True:
        if number:
            builds = call("GET", base + f"&filter[version]={number}")["data"]
        else:
            builds = call("GET", base + "&filter[processingState]=VALID")["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "not uploaded yet"
        if state == "VALID":
            return builds[0]
        if state in ("FAILED", "INVALID"):
            print(f"::error::Build {number} failed Apple's processing ({state}).")
            raise SystemExit(1)
        if time.time() >= deadline:
            print(f"::error::Build {number or '(newest)'} is {state.lower()}; Apple may still be processing it. Run this again in a few minutes.")
            raise SystemExit(1)
        print(f"build {number or '(newest)'}: {state.lower()}, waiting")
        time.sleep(30)


def main():
    step("App")
    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    print(f"{app['attributes']['name']} ({app['id']})")
    email = os.environ.get("CONTACT_EMAIL", "").strip()

    step("Test information")
    attrs = {"description": META["description"][:4000], "privacyPolicyUrl": PRIVACY_URL, "marketingUrl": MARKETING_URL}
    if email:
        attrs["feedbackEmail"] = email
    locs = call("GET", f"/apps/{app['id']}/betaAppLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == META["locale"]), None)
    if loc:
        call("PATCH", f"/betaAppLocalizations/{loc['id']}", {"data": {"type": "betaAppLocalizations", "id": loc["id"], "attributes": attrs}})
        print(f"{META['locale']}: updated")
    else:
        call("POST", "/betaAppLocalizations", {"data": {"type": "betaAppLocalizations", "attributes": {"locale": META["locale"], **attrs},
             "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})
        print(f"{META['locale']}: added")
    if not email:
        print("::warning::No feedback email (APP_REVIEW_EMAIL), so the one in App Store Connect is kept. Beta review needs one.")

    step("Beta App Review contact and notes")
    detail = call("GET", f"/apps/{app['id']}/betaAppReviewDetail")["data"]
    review = {"demoAccountRequired": False, "notes": re.sub(r"Two Degrees \d+(\.\d+)+ ", "Two Degrees ", META["reviewNotes"])[:4000]}
    name = os.environ.get("CONTACT_NAME", "").strip().split(" ", 1)
    for key, value in [("contactFirstName", name[0]), ("contactLastName", name[1] if len(name) > 1 else ""),
                       ("contactPhone", os.environ.get("CONTACT_PHONE", "").strip()), ("contactEmail", email)]:
        if value:
            review[key] = value
    call("PATCH", f"/betaAppReviewDetails/{detail['id']}", {"data": {"type": "betaAppReviewDetails", "id": detail["id"], "attributes": review}})
    print("contact " + ("set" if "contactPhone" in review else "kept as it is (no APP_REVIEW_PHONE)") + "; notes set; no sign-in needed")

    step("Build")
    build = find_build(app, os.environ.get("BUILD", "").strip(), int(os.environ.get("WAIT_MINUTES") or 0))
    number = build["attributes"]["version"]
    print(f"build {number}")
    # The app only uses standard HTTPS, which is exempt. Info.plist already says so; this covers a build that doesn't.
    if build["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
        print("export compliance: uses only exempt encryption")
    notes = whats_new(call("GET", f"/builds/{build['id']}/preReleaseVersion")["data"]["attributes"]["version"])
    blocs = call("GET", f"/builds/{build['id']}/betaBuildLocalizations")["data"]
    bloc = next((l for l in blocs if l["attributes"]["locale"] == META["locale"]), None)
    if bloc:
        call("PATCH", f"/betaBuildLocalizations/{bloc['id']}", {"data": {"type": "betaBuildLocalizations", "id": bloc["id"], "attributes": {"whatsNew": notes}}})
    else:
        call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": META["locale"], "whatsNew": notes},
             "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    print("What to Test: " + notes.splitlines()[0])

    step(f'Group "{GROUP}"')
    groups = call("GET", f"/betaGroups?filter[app]={app['id']}&filter[name]={GROUP}")["data"]
    group = next((g for g in groups if g["attributes"]["name"] == GROUP and not g["attributes"].get("isInternalGroup")), None)
    if group:
        print("found")
    else:
        # The public link is turned on at the end, once the group has a build in review.
        group = call("POST", "/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": GROUP, "isInternalGroup": False, "feedbackEnabled": True},
                     "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        print("created")
    have = {b["id"] for b in call("GET", f"/betaGroups/{group['id']}/relationships/builds?limit=200")["data"]}
    if build["id"] in have:
        print(f"build {number} already in the group")
    else:
        call("POST", f"/betaGroups/{group['id']}/relationships/builds", {"data": [{"type": "builds", "id": build["id"]}]})
        print(f"build {number} added")

    step("Beta App Review")
    subs = call("GET", f"/betaAppReviewSubmissions?filter[build]={build['id']}")["data"]
    if subs:
        state = subs[0]["attributes"]["betaReviewState"]
        print(f"build {number} was already submitted: {state}")
    else:
        sub = call("POST", "/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
                   "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})["data"]
        state = sub["attributes"]["betaReviewState"]
        print(f"build {number} submitted: {state}")

    step("Public link")
    a = group["attributes"]
    if not a.get("publicLinkEnabled") or a.get("publicLinkLimitEnabled"):
        changed = soft_call("PATCH", f"/betaGroups/{group['id']}", {"data": {"type": "betaGroups", "id": group["id"],
                            "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}}})
        if changed:
            a = changed["data"]["attributes"]
        else:
            print("::notice::The error above is expected until Beta App Review approves a build; a later run turns the link on.")
    link = a.get("publicLink")
    if not link:
        print("::warning::Apple hasn't made the public link yet (it may need the build through Beta App Review first). A later scheduled run turns it on once the build is approved.")
        return
    print(f"::notice::Public TestFlight link: {link} (build {number}, beta review {state})")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"## Two Degrees on TestFlight\n\nPublic link: {link}\n\nBuild {number}, Beta App Review: {state}.\n\n"
                    "For the download buttons, commit this as `docs/testflight.json`:\n\n"
                    f"```json\n{json.dumps({'url': link})}\n```\n")


if __name__ == "__main__":
    main()
