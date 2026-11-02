"""Revokes the throwaway development certificates that automated iPhone builds leave behind.

Each build signs on a fresh machine: Xcode creates an "Apple Development: Created via API" certificate whose
private key is lost when the machine goes away, and Apple caps how many an account may hold. This revokes only
those (DEVELOPMENT / IOS_DEVELOPMENT, named "Created via API"); the owner's own certificates (Developer ID,
Apple Distribution, and any development certificate with a person's name) are never touched.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Run by .github/workflows/ios-testflight.yml before each archive.
"""
from appstore_upload import call

THROWAWAY_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def main():
    certs = call("GET", "/certificates?limit=200&fields[certificates]=name,certificateType,displayName")["data"]
    revoked = 0
    for c in certs:
        a = c["attributes"]
        name = a.get("name") or a.get("displayName") or ""
        if a.get("certificateType") in THROWAWAY_TYPES and "Created via API" in name:
            call("DELETE", f"/certificates/{c['id']}")
            revoked += 1
    kept = len(certs) - revoked
    print(f"::notice::Revoked {revoked} throwaway build certificate(s); kept {kept} (yours are never touched).")


if __name__ == "__main__":
    main()
