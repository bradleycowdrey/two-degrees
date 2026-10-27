"""Reports where the iOS app stands in App Store Connect: each version's state and its latest review
submission. Read-only. Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Run by .github/workflows/appstore-status.yml.
"""
from appstore_upload import BUNDLE_ID, call


def main():
    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    for v in call("GET", f"/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]:
        a = v["attributes"]
        build = call("GET", f"/appStoreVersions/{v['id']}/build").get("data")
        number = build["attributes"]["version"] if build else "none"
        print(f"::notice::Version {a['versionString']} (build {number}): {a.get('appVersionState') or a['appStoreState']}")
    for s in call("GET", f"/reviewSubmissions?filter[app]={app['id']}&filter[platform]=IOS&limit=3")["data"]:
        a = s["attributes"]
        print(f"::notice::Review submission {a.get('submittedDate') or 'not submitted'}: {a['state']}")


if __name__ == "__main__":
    main()
