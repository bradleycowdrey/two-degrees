"""Checks App Store Connect before the Mac App Store build, reading only and changing nothing.

It says whether this Mac build number is already uploaded (then there's nothing to do), whether the app's record
has the macOS platform yet (uploads for a platform the record lacks are refused), and how many Macs the account
has registered (signing the archive for development needs at least one). Only counts are printed, never device
names or identifiers, because the logs are public.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUILD (the build number). Writes skip=true|false to GITHUB_OUTPUT.
Run by .github/workflows/mac-appstore.yml. Needs PyJWT and cryptography.
"""
import os

from appstore_upload import BUNDLE_ID, call


def output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            f.write(f"{key}={value}\n")


def main():
    build = os.environ["BUILD"]
    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        print(f"::error::No app in App Store Connect has the bundle ID {BUNDLE_ID}.")
        raise SystemExit(1)
    app = apps[0]["id"]

    done = call("GET", f"/builds?filter[app]={app}&filter[preReleaseVersion.platform]=MAC_OS&filter[version]={build}&limit=1")["data"]
    if done:
        print(f"::notice::Mac build {build} is already in App Store Connect, so nothing to upload. A new commit gives a new build number.")
        output("skip", "true")
        return
    output("skip", "false")

    versions = call("GET", f"/apps/{app}/appStoreVersions?filter[platform]=MAC_OS&limit=1")["data"]
    if versions:
        print("the app's record has the macOS platform")
    else:
        print("::warning::The app's App Store Connect record has no macOS version yet. If the upload is refused for that "
              "reason, add the macOS platform to the app in App Store Connect (or create a MAC_OS version through the API) and run this again.")

    macs = call("GET", "/devices?filter[platform]=MAC_OS&filter[status]=ENABLED&limit=200&fields[devices]=status")["data"]
    print(f"{len(macs)} Mac(s) registered in the account")
    if not macs:
        print("::warning::No Mac is registered in the account, and a development-signed archive needs one. Register any Mac you "
              "own, or run this workflow with archive signing set to local.")


if __name__ == "__main__":
    main()
