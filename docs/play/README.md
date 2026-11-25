# Two Degrees on Google Play

This folder is the Google Play store listing. `play-listing.yml` sends it to Play Console whenever it changes on
`main` (or when you run it), and `android.yml` sends new builds to the closed test.

- `listing.json`: the title (Two Degrees Weather), short and full description, contact email and website.
- `icon.png`: 512 x 512, from the C° icon (Google rounds the corners).
- `feature-graphic.png`: 1024 x 500.
- `phone-1.png` to `phone-5.png`: the Android app in the emulator, from the self-test's screenshots
  (`ci-shots-android` branch), in the App Store's order: every temperature in both units, ten days, every
  detail, all your cities, widgets. The status and gesture bars are cropped and the sides widened to 9:16;
  the widget picture leaves out the self-test's deliberately offline widget.

## Once, in Play Console

Play Console gives a new app its package name from the first App Bundle you upload, so the first one goes up
by hand. After that, the workflows do it.

1. **Create app**: app name **Two Degrees Weather**, default language **English (United States)**, **App**,
   **Free**, and tick the declarations. It doesn't ask for a package name; the first bundle sets it
   (`com.bradcowdrey.twodegrees`).
2. **Store settings** (Grow users, Store presence, Store settings): category **Weather**; email
   **legal@bradcowdrey.com**; website https://bradcowdrey.com/two-degrees.
3. **App content** (Policy and programs, App content): the answers are below.
4. **Closed test** (Test and release, Testing, Closed testing): use the default track (Closed testing, Alpha;
   the workflow releases to it). Testers: create an email list of at least 12 testers' Google accounts.
   Countries and regions: where your testers are (or all). Copy the opt-in link for the testers.
5. **First release, by hand**: on that track, Create new release. Accept Play App Signing (Google keeps the app
   signing key; the key in the `ANDROID_KEYSTORE_*` secrets becomes the upload key). Upload `app-release.aab`
   from the newest green run of the Android workflow on `main`: Actions, Android, the run, Artifacts,
   **two-degrees-android**, then `bundle/release/app-release.aab` in the zip. Its log must say "Release APK
   signed with the permanent key"; Play refuses a debug-signed bundle. (The GitHub release has only the APK.)
   Then Save, review and roll out to the closed test. Play reviews a new app's first release.
6. **Service account** (lets the workflows in): in Google Cloud, enable the Google Play Android Developer API,
   create a service account and a JSON key for it. In Play Console, Users and permissions, invite its email with
   permission for Two Degrees to release to testing tracks and to edit the store listing. Save the whole JSON
   as the repository secret `PLAY_SERVICE_ACCOUNT_JSON`. Then run **Google Play listing** once (Actions).

Play phones get Google's app signing key, not the GitHub APK's key, so a phone with the GitHub APK has to
uninstall it before installing from Play.

**12 testers, 14 days**: this is a personal developer account, so the app reaches production only after a
closed test with at least 12 testers opted in for 14 days in a row. Each tester opens the opt-in link with
their Google account and installs from Play. Keep a few spares in case someone drops out. Then Dashboard,
Apply for production.

## How builds reach testers

- **Which builds**: a push to `main` that changes `VERSION` (a release), and **Run workflow** on the Android
  workflow on `main`. Pull requests, other branches and other pushes don't go to Play. The upload is the
  job's last step, so only a build that passed the emulator self-test and is signed with the upload key goes.
  It's named like "2.3.6 (1234)", with this version's Android lines from `CHANGELOG.md` as What's new.
- **Version codes**: the number of commits on `main` (`git rev-list --count HEAD`, in
  `android/app/build.gradle.kts`; the workflow checks out the whole history). Every new commit on `main` has a
  higher number. A build of a commit already on Play is skipped. So never rewrite `main`'s history, and to send
  a build again, push or Run workflow; don't re-run an old run, whose commit has a lower number.
- While Play still lists the app as a draft, uploads arrive as draft releases; roll them out in Play Console
  (the workflow says so as a warning).
- The store listing goes up from this folder with `play-listing.yml`.

## Secrets

- `PLAY_SERVICE_ACCOUNT_JSON` (new): the service account's JSON key. Without it, nothing is sent to Play and
  the builds still pass.
- `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (already
  used by `android.yml`): the upload key. Without them, builds pass but are debug-signed and skip Play. If the
  build stops at `packageRelease` with "Failed to read key", a password doesn't match the keystore.

## Suggested App content answers

Checked against the Android code and the Terms (Sections 15 and 25).

- **Privacy policy**: https://bradcowdrey.com/legal
- **Ads**: No.
- **App access**: All functionality is available without special access. No account; the first launch shows
  the terms (Agree), then asks whether to use your location (either answer works).
- **Content rating**: category **All other app types** (a utility; not a game, social, news or entertainment
  app). Answer **No** to every question: violence, fear, sexuality, language, controlled substances, crude
  humour, gambling, users interacting or sharing content, sharing location with other users, digital
  purchases, unrestricted internet (the rain map is one fixed page whose only links are its credits).
  Expect Everyone / PEGI 3 / IARC 3+.
- **Target audience**: 13-15, 16-17 and 18 and over; not under 13 (the Terms say the apps aren't directed to
  children). Appeals to children: No.
- **News app**: No. **Government app**: No (it shows US National Weather Service alerts, names the source and
  says it isn't affiliated). **Financial features**: none. **Health**: none (UV, air quality and pollen are
  weather). **Advertising ID**: No (no ads or analytics libraries).

### Data safety

- Collects or shares any of the required data types: **Yes**.
- All data encrypted in transit: **Yes** (every connection is HTTPS).
- Account creation: **none**.
- Users can ask for deletion: **Yes**. Removing a city or turning off Use My Location deletes it on the phone,
  uninstalling deletes everything, and Terms Section 16 offers deletion by email. Bradley holds none of it.

| Data type | Collected | Shared | Processed ephemerally | Required? | Why |
|---|---|---|---|---|---|
| Location: **Approximate location** | Yes | No | No | Optional | App functionality |
| App activity: **In-app search history** | Yes | No | No | Optional | App functionality |

Everything else (personal info, precise location, contacts, files, photos, messages, health, financial info,
web browsing, crash logs and diagnostics, device IDs): not collected.

What the app sends, and to whom:
- **Use My Location** (off until you say yes) asks Android for approximate location only
  (`ACCESS_COARSE_LOCATION`), only while the app is open. The phone's own location service names the place;
  the app rounds the position to about a kilometre and sends that to Open-Meteo (forecast, air quality, past
  weather), to the National Weather Service for US places (alerts) and to the rain map (its page on GitHub
  Pages; RainViewer and OpenFreeMap see the map area). None of it reaches Bradley.
- **City search**: what you type goes to Open-Meteo's place search (offline, the built-in list answers).

Where Google's definitions leave room for judgement:
- **Shared**: these services do what the user asked for (fetch the weather, draw the map), which fits Google's
  service-provider and user-initiated exceptions, so "not shared". Ticking Shared as well is the most cautious
  reading; nothing else changes.
- **Ephemeral**: Bradley can't vouch for the services' own server logs, so No.
- **Saved cities' coordinates** are places you chose, not where your phone is, so they aren't "Location".
- **Search**: a typed city name is barely personal, but it leaves the phone, so declaring it is the safer choice.
- **IP address**: every connection shows the phone's IP address to the service it reaches (Terms Section 15).
  Google has no separate type for it and the app doesn't use it.
- **Android backup** is on, so your own Google backup may hold your cities and settings. That's the user's
  backup, never Bradley's.
- Notifications are worked out on the phone; there's no push server.
- The App Store says "Data Not Collected" under Apple's narrower definition; Google counts what leaves the phone.
