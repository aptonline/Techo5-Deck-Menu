# TECHO5 Deck for macOS

TECHO5 Deck is a SwiftUI menu bar app for the [TECHO5 Deck agent](https://github.com/HuskerMinion/techo5/blob/main/docs/deck.md#computer-buttons). It runs on macOS 13 or later on Apple silicon and Intel.

## First launch

1. If the standalone Deck agent is running, stop it before opening the menu bar app. Deck uses TCP port 4470 by default.
2. Unzip the app and move it to Applications. Open it, then click the grid icon in the menu bar. The app downloads and verifies the engine from the official TECHO5 GitHub release on first launch.
3. In the menu, use **Show** or **Copy** next to **Pairing Key**. On your Echo Show's setup page, go to **Screen → Deck → Computers** to pair.
4. Allow local network access if macOS asks. For shortcuts and typing, follow the upstream [macOS permissions instructions](https://github.com/HuskerMinion/techo5/blob/main/docs/deck.md#macos). The menu links to Accessibility settings. In **Settings**, enable **Launch at Login** after moving the app to Applications if you want it to start with your Mac.

In the **Engine** row, choose **… → Check for Engine Updates** to install the newest stable GitHub release independently of the menu bar app. The version is shown below the status. The wrapper verifies the published SHA-256 before installing and restores the previous engine if the replacement fails to start.

The app uses the agent's standard settings directory, `~/Library/Application Support/TECHO5 Deck`. An existing pairing key and script list are reused. **Pairing Key → … → Generate New Key** invalidates existing pairings and requires confirmation.

## Menu bar app updates

Choose **Settings → Check for App Updates…** to open the app’s release page in your browser. The first time, enter the HTTPS address where you get menu bar app releases. You can change it later under **Settings → Change App Updates URL…**.

## Build in Xcode

Open `TECHO5 Deck.xcodeproj`, choose **My Mac**, and run the **TECHO5 Deck** scheme. The provided universal build is ad hoc signed for local testing. Use your Developer ID and notarization for distribution.
