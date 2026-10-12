# Diroid

<p align="center">
  <img src="Screenshots/hero.png" width="640" alt="Diroid's app icon over its file browser window">
</p>

<p align="center"><em>Pronounced "dir-oid"</em></p>

A native macOS app for browsing your Android device's storage over USB
- no MTP
- no kernel extension
- no background daemon

## What is this?

- macOS has no built-in way to see an Android device's files when you plug it in over USB. 
Every existing solution wraps `libmtp` in a FUSE filesystem, which means a kernel extension, kernel-level trust, and (in practice) a lot of flakiness getting it to actually mount.
- Diroid uses Android's USB debugging protocol (ADB) directly to the local `adb` server the same way Android Studio's "Device File Explorer" does but reimplemented from scratch in Swift.
- No `adb` binary shelled out to, no third-party libraries, no elevated privileges, no daemons running in the background.

## Features

- Browse your Android device's storage like a Finder window.
- List and Grid views (toggle in the path bar), groupable by Name, Size, or Date Modified
- Double-click a file to pull it and open it in the default app macOS would use for that file type
- Right-click → **Save to…** to copy a file to a folder you choose, without opening it
- Right-click → **Rename…** to rename or move a file or folder
- Right-click → **Delete** to remove a file, or a folder and everything in it (with a confirmation prompt first)
- **New Folder…** button (bottom left) to create a folder in the current directory
- **Upload Files…** button (bottom right) to push local files onto the Android device
- Click path breadcrumbs to move to that folder.
- The whole filesystem is browsable (permission-restricted system folders show an error)
- **Refresh** (↻) button to reconnect after unplugging/replugging your Android device
- If the `adb` server isn't running, Diroid says so and shows the command to start it, with a copy button for pasting into Terminal

### Screenshots

<img src="Screenshots/Screenshot2.jpg" width="700" alt="Diroid's list view of an Android device's DCIM folder, with the New Folder dialog open">

List view, and the New Folder dialog.

<img src="Screenshots/Screenshot1.jpg" width="700" alt="Grid view grouped by date, with the Group By menu and the right-click menu (Rename, Save to, Delete) open">

Grid view, the Group By menu (top right), and the right-click menu on a file.

## Install

With [Homebrew](https://brew.sh) (Apple silicon Macs):

```bash
brew install --cask ike-V/diroid/diroid
```

### First launch: macOS blocks it

Diroid isn't signed with an Apple Developer ID or notarized yet, so macOS blocks it the first time ("Apple could not verify Diroid is free of malware"). Do one of these, once:

- **Terminal:** `xattr -dr com.apple.quarantine /Applications/Diroid.app`
- **System Settings:** try to open Diroid, then go to System Settings → Privacy & Security, scroll to **Security**, and click **Open Anyway**.

Diroid also needs an `adb` server running — see Requirements.

## Requirements

- macOS 13 (Ventura) or later
- An Android device with **USB debugging** enabled: Settings → About phone (or About tablet) → tap "Build number" 7 times to unlock Developer options → Developer options → USB debugging
- The `adb` server running on your Mac — easiest way is Homebrew: `brew install --cask android-platform-tools`. Diroid talks to this same background server; it doesn't shell out to the `adb` binary itself.
- To build from source: Xcode, set as the active developer directory: `sudo xcode-select -s /Applications/Xcode.app` (the Command Line Tools alone can't build SwiftUI's `@State` macro on the macOS 27 SDK)

## Build from source

```bash
git clone https://github.com/ike-V/Diroid.git
cd Diroid
./build.sh
open Diroid.app
```

## First run

- Plug in your Android device before or after launching 
- The first time, you'll get a prompt on the Android device itself asking to authorize this computer for USB debugging; accept it (check "always allow" to skip this next time).
- If you unplug/replug while the app is already open, hit the refresh (↻) button.

## Credits

The Android robot in the app icon is reproduced or modified from work created and shared by Google and used according to terms described in the [Creative Commons 3.0 Attribution License](https://creativecommons.org/licenses/by/3.0/).

## License

All rights reserved. See [LICENSE](LICENSE).
