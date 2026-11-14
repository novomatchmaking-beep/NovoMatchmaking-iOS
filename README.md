# Novo Matchmaking — iOS app (v6)

Bundle ID `com.novo.matchmaking` · Website `https://www.hknovo.com` · iOS 16+ · iPhone & iPad

## Build & run
1. Open `NovoMatchmaking.xcodeproj` in Xcode 16 or later.
2. Select the **NovoMatchmaking** target, open **Signing & Capabilities**, and choose your **Team**.
3. Choose an iPhone simulator or device, then select **Product ▸ Clean Build Folder** and **Run**.

> **Free Apple ID (Personal Team)?** Free teams can't use Push Notifications. Delete the **Push Notifications** capability in Signing & Capabilities, or clear the `CODE_SIGN_ENTITLEMENTS` build setting, and the app will still build. A paid Apple Developer Program account ($99/yr) is required for the App Store anyway.

## What's in v6
| Area | What changed |
|---|---|
| Project | Added `SDKROOT = iphoneos`, which was missing, so the project now builds for iOS. Added proper Debug/Release settings, version numbers (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`), and the code split into readable files |
| App Store validation | Added the iPad orientation set (required when a universal app supports only portrait on iPhone), `ITSAppUsesNonExemptEncryption = NO`, and a privacy manifest (`PrivacyInfo.xcprivacy`) |
| Web content | Embedded frames are no longer blocked (reCAPTCHA, Google Maps, YouTube, payment widgets). `target=_blank` / `window.open` links now work. JavaScript `alert` / `confirm` / `prompt` dialogs now appear. Camera and microphone work for hknovo.com |
| Links | Pages outside hknovo.com open in their own app (WhatsApp, Instagram, Facebook) or in Safari. `tel:`, `mailto:`, `sms:` and `whatsapp:` links work |
| UX | Full-screen website with no bottom bar. The status bar (time, signal, Wi-Fi, battery) area is tinted with the colour at the top of each page. The page runs to the bottom edge and the website's own safe-area spacing is used, so the footer menu sits snugly above the home indicator. If a page change fails while a page is showing, a small "tap to retry" message appears instead of a full-screen error. Its icons turn dark or white automatically. Brief network errors such as -1003 or timeouts are retried quietly before an error screen appears. Pull down to refresh, swipe from the left edge to go back, a thin loading bar, and friendly offline / error screens that reconnect automatically |
| Branding | The app icon uses the M-heart monogram, so it reads clearly at small sizes. The original full logo is in `Design/`. The launch screen shows the logo and fades into the app without a jump |
| Push | Added the push entitlement. The website asks for notification permission (see below), and the device token is passed to the website (see below), and tapping a notification opens the URL in its payload |

## Settings you may want to change — `AppConfig.swift`
- `homeURL` is the start page.
- `footerTightening` moves the website's footer menu closer to the bottom edge (default 20 points). Raise it to move the footer lower, or lower it if the labels touch the home bar.
- `extraInAppHosts` lists sites that must stay inside the app, such as a payment gateway or Google sign-in page that redirects back to hknovo.com. Add them here if a checkout or login flow jumps out to Safari.

## Push notifications — what the website team needs to do
The app only *receives* notifications. Your server sends them.
1. In the Apple Developer portal, create an **APNs Auth Key (.p8)**.
2. On hknovo.com, save each member's device token. The app provides it in three ways:
   ```js
   // a) listen for it
   window.addEventListener('novo:push-token', e => saveToken(e.detail.token)); // POST to your backend
   // b) or read it
   window.NovoApp?.pushToken || localStorage.getItem('novoPushToken');
   ```
3. Ask for permission from a button on your site. The app has no button of its own for this, so without this step members are never asked:
   ```js
   window.webkit?.messageHandlers?.novo?.postMessage({ action: 'requestPush' });
   ```
4. Send through APNs with a payload like `{"aps":{"alert":"You have a new match!","sound":"default"},"url":"https://www.hknovo.com/matches"}`. Tapping the notification opens `url`.

The website can detect the app with `window.NovoApp?.platform === 'ios'` or by checking that the user agent contains `NovoMatchmakingApp`. Use this to hide download-the-app banners or a duplicate footer navigation.

## App Store submission checklist
- [ ] **Guideline 4.2 (Minimum Functionality)** is the main rejection risk for apps that wrap a website. Make sure the app shows real value: member login, profiles, matches and messaging, plus push notifications. In App Review notes, describe the native features: push alerts for matches, camera profile photos, pull-to-refresh, and offline handling.
- [ ] **Demo account**: give App Review a working member login if parts of the site are behind sign-in.
- [ ] **Account deletion (5.1.1(v))**: if members can create accounts, there must be a way to delete the account from inside the app (a page on the site is fine).
- [ ] **Privacy policy URL** and the **App Privacy** questionnaire in App Store Connect. These must describe what hknovo.com collects (name, photos, contact details and so on).
- [ ] **Age rating**: dating and matchmaking apps are generally rated 18+ (or 17+ under older rating schemes).
- [ ] Screenshots: 6.9" iPhone, plus 13" iPad (because the app supports iPad). To make it iPhone-only instead, set `TARGETED_DEVICE_FAMILY = 1`.
- [ ] Before each new upload, raise **Build** (`CURRENT_PROJECT_VERSION`) in the target's General tab.

## Troubleshooting
- **"You're offline"**: the device has no connection. The app retries automatically when it reconnects.
- **"We couldn't load the page" plus an error code**: open the same URL in Safari. If Safari also fails, the problem is the website's hosting, DNS or TLS.
- **"The page came back empty"**: the server returned a blank page. Check the website's hosting.
- **Debug builds** can be inspected from a Mac with Safari ▸ Develop ▸ *your device* ▸ Novo Matchmaking.
