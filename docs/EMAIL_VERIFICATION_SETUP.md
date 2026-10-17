# Email verification: branding and in-app links

Firebase Authentication sends the verification and password-reset emails
itself. The app code cannot change their subject, sender name or wording, and
it cannot change where the link in the email points. Those settings are in the
Firebase Console. This guide lists the console steps, and what the code
already does.

Project: `daily-expense-buddy-e0980` · Android package: `com.dailyexpensebuddy.app`

## What the code already does

| Piece | Where |
|---|---|
| In-app link handler at `/auth/action`. It applies the code with Firebase (`applyActionCode`), reloads the user, then shows the result: verified, expired, invalid, network error with retry, or unsupported. Password-reset links get a "new password" form (`verifyPasswordResetCode` / `confirmPasswordReset`). | `lib/features/auth/presentation/email_action_page.dart` |
| The route opens in every sign-in state, before the splash and intro. It is never used as a post-login return path. | `lib/app/router.dart`, `lib/app/routes.dart` |
| Verification emails continue to `https://daily-expense-buddy-e0980.web.app/verify-email`. If Firebase rejects that continue URL, the app falls back to the default link, so sign-up never breaks. | `lib/data/firebase/firebase_auth_repository.dart` |
| Android App Links for `/auth/action` and `/verify-email` on `daily-expense-buddy-e0980.web.app` and `.firebaseapp.com` | `android/app/src/main/AndroidManifest.xml` |
| Digital Asset Links file (package plus SHA-256 of the signing key) | `web/.well-known/assetlinks.json` |
| Hosting now publishes `.well-known/` (it used to be excluded by the `**/.*` ignore rule) | `firebase.json` |
| The verify-pending screen checks automatically every 4 s and on app resume. Resend has a 60 s cooldown and handles errors and rate limits. Success is shown only after Firebase reports `emailVerified`. | `lib/features/auth/presentation/auth_pages.dart` |

## Steps you must do in the Firebase Console

### 1. App name shown in emails (fixes the project ID in the subject)

The default subject is `Verify your email for %APP_NAME%`. `%APP_NAME%` is the
project's **public-facing name**.

Console → ⚙ Project settings → General → **Public-facing name** → set
`Daily Expense Buddy` → Save.

### 2. Email template

Console → Authentication → **Templates** → *Email address verification* → ✎ Edit.

- **Sender name:** `Daily Expense Buddy`
- **Reply-to:** an address you read (optional)
- **Subject:** `Verify your email address — Daily Expense Buddy`
- **Message:** paste the following. `%LINK%` and `%APP_NAME%` are Firebase
  placeholders: keep them exactly as written.

```html
<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#1f2937">
  <div style="background:#1E63E9;color:#ffffff;padding:20px 24px;border-radius:12px 12px 0 0">
    <h1 style="margin:0;font-size:20px">Daily Expense Buddy</h1>
    <p style="margin:4px 0 0;font-size:13px;opacity:.85">Track Today. Spend Smarter.</p>
  </div>
  <div style="border:1px solid #e5e7eb;border-top:0;padding:24px;border-radius:0 0 12px 12px">
    <p>Hello,</p>
    <p>Welcome to Daily Expense Buddy! We are happy to have you here.</p>
    <p>Please verify your email address to complete your account setup and start using Daily Expense Buddy.</p>
    <p style="text-align:center;margin:28px 0">
      <a href="%LINK%" style="background:#1E63E9;color:#ffffff;text-decoration:none;padding:12px 24px;border-radius:999px;font-weight:bold;display:inline-block">Verify My Email</a>
    </p>
    <p>After verification, return to the app to continue.</p>
    <p style="font-size:13px;color:#6b7280">If you did not create this account, you can ignore this email.</p>
    <p>Thank you,<br>The Daily Expense Buddy Team</p>
  </div>
</div>
```

Do the same for **Password reset**, using its own wording. The subject is
`Reset your password — Daily Expense Buddy`.

> If the console locks the message body for a template, the sender name,
> subject and public-facing name still apply.

### 3. Make links open the app (custom action URL)

Do this **only after step 4** (hosting is deployed). Otherwise the links lead
to a 404.

Console → Authentication → Templates → any template → ✎ → **Customize action
URL** → `https://daily-expense-buddy-e0980.web.app/auth/action` → Save.
This setting applies to every template.

The result:
- **Android, app installed:** the App Link opens Daily Expense Buddy on the
  verification screen. The app verifies the code with Firebase and shows
  success or a clear error.
- **Android without the app, desktop, or other mail apps:** the same URL opens
  the web app, which runs the same verification.

### 4. Deploy the web app (needed for assetlinks.json and the web flow)

```bash
flutter build web --release
firebase deploy --only hosting
```

Check it with:

```bash
curl https://daily-expense-buddy-e0980.web.app/.well-known/assetlinks.json
```

### 5. Authorized domains

Console → Authentication → Settings → **Authorized domains**. Both
`daily-expense-buddy-e0980.web.app` and `daily-expense-buddy-e0980.firebaseapp.com`
must be listed. They are added automatically. Add any custom domain you use.

### 6. Signing key for App Links

`assetlinks.json` currently lists the **debug** keystore's SHA-256
(`B8:33:C1:…:95:42`). Release builds in this repository are signed with that
same key (see `android/app/build.gradle.kts`). When you set up a real release
keystore, or publish through Play App Signing, add that SHA-256 to
`sha256_cert_fingerprints` and redeploy hosting:

```bash
keytool -list -v -keystore <your.keystore> -alias <alias>
```

On a device, run `adb shell pm get-app-links com.dailyexpensebuddy.app`. It
should show the domains as `verified`.

## Why not Dynamic Links?

Firebase Dynamic Links is deprecated. This setup uses standard Android App
Links over HTTPS, which need no extra service. iOS Universal Links can be added
the same way: add an `apple-app-site-association` file and the Associated
Domains entitlement. iOS hasn't been built in this environment, so that part
is not configured.
