"""Reports where the iOS app stands in App Store Connect: each version's state and its latest review
submission, and the public TestFlight link with the newest build's Beta App Review state. Read-only. Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Run by .github/workflows/appstore-status.yml.
"""
from appstore_upload import BUNDLE_ID, call


def main():
    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    print(f"::notice::App Store page: https://apps.apple.com/app/id{app['id']}")
    for v in call("GET", f"/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]:
        a = v["attributes"]
        build = call("GET", f"/appStoreVersions/{v['id']}/build").get("data")
        number = build["attributes"]["version"] if build else "none"
        print(f"::notice::Version {a['versionString']} (build {number}): {a.get('appVersionState') or a['appStoreState']}")
    for s in call("GET", f"/reviewSubmissions?filter[app]={app['id']}&filter[platform]=IOS&limit=3")["data"]:
        a = s["attributes"]
        print(f"::notice::Review submission {a.get('submittedDate') or 'not submitted'}: {a['state']}")
    # The public TestFlight link (from appstore_testflight_public.py) and where the newest build is in beta review.
    for g in call("GET", f"/betaGroups?filter[app]={app['id']}&filter[name]=Public")["data"]:
        a = g["attributes"]
        if not a.get("isInternalGroup"):
            print(f"::notice::Public TestFlight link: {a.get('publicLink') or 'not made yet'} ({'on' if a.get('publicLinkEnabled') else 'off'})")
    builds = call("GET", f"/builds?filter[app]={app['id']}&filter[preReleaseVersion.platform]=IOS&sort=-uploadedDate&limit=1")["data"]
    if builds:
        b = builds[0]
        subs = call("GET", f"/betaAppReviewSubmissions?filter[build]={b['id']}")["data"]
        beta = call("GET", f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
        print(f"::notice::Newest build {b['attributes']['version']}: {b['attributes']['processingState']}, beta review "
              f"{subs[0]['attributes']['betaReviewState'] if subs else 'not submitted'}, external testing {beta.get('externalBuildState')}")
    # Signing certificates (name, type, expiry), to see when the account is near Apple's limit.
    certs = call("GET", "/certificates?limit=200&fields[certificates]=name,certificateType,displayName,expirationDate")["data"]
    for c in certs:
        a = c["attributes"]
        print(f"::notice::Certificate {a.get('certificateType')}: {a.get('name') or a.get('displayName')} (expires {str(a.get('expirationDate'))[:10]})")


if __name__ == "__main__":
    main()
