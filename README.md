# TECHO5 Deck for macOS

TECHO5 Deck is a SwiftUI menu bar app for the [TECHO5 Deck agent](https://github.com/HuskerMinion/techo5/blob/main/docs/deck.md#computer-buttons). It runs on macOS 13 or later on Apple silicon and Intel.

## Install and open on macOS

1. Download the universal Mac ZIP from [GitHub Releases](https://github.com/aptonline/Techo5-Deck-Menu/releases/latest).
2. Unzip it and drag **TECHO5 Deck.app** into **Applications**. If the standalone Deck agent is running, stop it to free TCP port 4470. Then open **TECHO5 Deck.app**.
3. If macOS blocks the app because it can’t verify the developer, open **System Settings → Privacy & Security**. Scroll to **Security** and click **Open Anyway** next to the message about TECHO5 Deck.
4. Confirm that you want to open TECHO5 Deck and authenticate if prompted. Then click the grid icon in the menu bar.

The GitHub build uses ad hoc signing and ships without Apple notarisation. If **Open Anyway** is missing, try opening the app again and then return to **Privacy & Security**. The option is available for about an hour after the launch attempt. [Apple’s instructions for opening an app from an unidentified developer](https://support.apple.com/en-gb/guide/mac-help/mh40617/mac)

## First launch

1. Click the grid icon in the menu bar. The app downloads and verifies the engine from the official TECHO5 GitHub release on first launch.
2. In the menu, use **Show** or **Copy** next to **Pairing Key**. On your Echo Show's setup page, go to **Screen → Deck → Computers** to pair.
3. Allow local network access if macOS asks. For shortcuts and typing, follow the upstream [macOS permissions instructions](https://github.com/HuskerMinion/techo5/blob/main/docs/deck.md#macos). The menu links to Accessibility settings. In **Settings**, enable **Launch at Login** after moving the app to Applications if you want it to start with your Mac.

In the **Engine** row, choose **… → Check for Engine Updates** to install the newest stable GitHub release independently of the menu bar app. The version is shown below the status. The wrapper verifies the published SHA-256 before installing and restores the previous engine if the replacement fails to start.

The app uses the agent's standard settings directory, `~/Library/Application Support/TECHO5 Deck`. An existing pairing key and script list are reused. **Pairing Key → … → Generate New Key** invalidates existing pairings and requires confirmation.

## Menu bar app updates

Choose **Settings → Check for App Updates…** to compare your installed version with the latest published GitHub release. If the versions differ, your browser downloads the universal Mac ZIP. Unzip it and replace the app after quitting your running copy.

## Build in Xcode

Open `TECHO5 Deck.xcodeproj`, choose **My Mac**, and run the **TECHO5 Deck** scheme. The provided universal build is ad hoc signed for local testing. Use your Developer ID and notarization for distribution.
