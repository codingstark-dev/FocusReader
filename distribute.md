# Distributing Focus Reader for macOS

When users download Focus Reader from the internet, macOS automatically adds a **quarantine flag** (`com.apple.quarantine`) to the files. When they try to run it, Gatekeeper inspects the app and may block it, showing a warning that the app "cannot be opened because it is from an unidentified developer" or, in some cases, warning about "malware."

Here is how to set up official distribution to prevent this, and how users can bypass it in the meantime.

---

## 🔒 1. Official Solution: Signing and Notarization

To distribute Focus Reader without Gatekeeper warnings, you must sign it with an official Apple Developer ID certificate and submit it to Apple's Notarization Service.

### Prerequisites:
1. A paid **Apple Developer Account** ($99/year).
2. A **Developer ID Application** certificate installed in your macOS Keychain.
3. An **App-Specific Password** generated from your Apple ID account (for notarization).

### Step-by-Step Signing & Notarization:

1. **Sign with your Developer ID Application certificate:**
   Run the build script passing your certificate identity name:
   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
   ```
   This will sign the app with the **Hardened Runtime** enabled (required by Apple for notarization).

2. **Zip the `.app` bundle for notarization:**
   ```bash
   ditto -c -k --keepParent FocusReaderApp/FocusReader.app FocusReaderApp/FocusReader.zip
   ```

3. **Submit to Apple's Notarization Service:**
   Use Xcode's `notarytool` to upload the zip:
   ```bash
   xcrun notarytool submit FocusReaderApp/FocusReader.zip \
     --apple-id "your-apple-id@email.com" \
     --password "your-app-specific-password" \
     --team-id "YOURTEAMID" \
     --wait
   ```

4. **Staple the notarization ticket to the app:**
   Once notarization succeeds, staple the ticket so that macOS can verify it offline:
   ```bash
   xcrun stapler staple FocusReaderApp/FocusReader.app
   ```

5. **Re-package the DMG:**
   Re-run the DMG generation part of the script, or create the DMG with the stapled `.app` bundle.

---

## 🔓 2. Workarounds for Users (Unsigned / Ad-hoc Signed Builds)

If you distribute the app without signing and notarizing it, users will see a Gatekeeper warning. You can provide these simple instructions to your users:

### Option A: The Right-Click Method (Easiest)
1. Open the **Applications** folder (or where you copied the app).
2. **Right-click** (or Control-click) `FocusReader.app` and choose **Open**.
3. A prompt will appear saying macOS cannot verify the developer. Click **Open** anyway.
4. The app will open, and macOS will remember this preference so it opens normally next time.

### Option B: Open Anyway in System Settings
1. Double-click the app to try to open it (which triggers the block).
2. Open **System Settings** on your Mac.
3. Go to **Privacy & Security** and scroll down to the **Security** section.
4. You will see a message: `"FocusReader" was blocked from use because it is not from an identified developer.`
5. Click **Open Anyway**, authenticate, and confirm.

### Option C: Remove the Quarantine Flag (Terminal)
If the above options don't work (or for advanced users), they can remove the macOS quarantine flag by running the following command in Terminal:
```bash
xattr -cr /Applications/FocusReader.app
```
*(Note: Replace `/Applications/FocusReader.app` with the path to the app if it's in another folder.)*
This immediately stops Gatekeeper from checking the app as an internet download, and it will launch instantly.
