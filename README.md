# Dirian

<p align="center">
  <img src="Screenshots/hero.png" width="640" alt="Dirian's app icon over its file browser window">
</p>

<p align="center"><em>Pronounced "dir-ee-an"</em></p>

Dirian is a native macOS app for browsing an Android device's files over USB. It can also share a selected directory back to the Android device.

It needs no MTP, no kernel extension and no background process of its own.

## Screenshots

<img src="Screenshots/recent.png" width="700" alt="Dirian's Recent view: files from the last 7 days grouped by date, with the sidebar's Recent, Images, Videos, Audio, Documents and Downloads shortcuts and the Folders list">

The sidebar shortcuts, here Recent, grouped by date.

<img src="Screenshots/camera-grid.png" width="700" alt="Dirian's grid view of an Android device's DCIM/Camera folder grouped by date, with the path bar at the bottom">

Grid view, and the path bar at the bottom.

<img src="Screenshots/group-by.png" width="700" alt="Dirian's Group By menu (None, Name, Size, Date Modified) open from the toolbar">

The Group By menu in the toolbar.

<img src="Screenshots/context-menu.png" width="700" alt="Dirian's right-click menu on a file, showing Rename, Save to and Delete">

The right-click menu on a file.

<img src="Screenshots/new-folder.png" width="700" alt="Dirian's list view of the Documents folder with the New Folder dialog open">

List view, and the New Folder dialog.

## Why Dirian?

macOS can't show an Android device's files when you plug it in over USB. Existing tools wrap `libmtp` in a FUSE filesystem, which needs a kernel extension and is often unreliable to mount.

Dirian talks to the `adb` server you already run, using Android's USB debugging protocol, the same way Android Studio's Device File Explorer does. It's written from scratch in Swift. It doesn't run the `adb` binary, uses no third-party libraries and needs no elevated privileges.

## Features

### Browse

- Browse your Android device's storage like a Finder window. The whole filesystem is browsable, and permission-restricted system folders show an error.
- A sidebar shows the device's name and its top-level folders, which you can collapse.
- The sidebar shortcuts Recent, Images, Videos, Audio, Documents and Downloads list matching files from the device's common folders, newest first. Recent covers the last 7 days.
- List and Grid views, groupable by Name, Size or Date Modified.
- The path bar at the bottom shows where you are. Click any segment to jump to that folder.

### Manage files

- Double-click a file to pull it and open it in the default Mac app for its type.
- Right-click → **Save to…** copies a file to a folder you choose, without opening it.
- Right-click → **Rename…** renames or moves a file or folder.
- Right-click → **Delete** removes a file, or a folder and everything in it, after a confirmation prompt.
- **New Folder…** creates a folder in the current directory.
- **Upload Files…** pushes local files onto the Android device.

### Connection

- **Refresh** (↻) reconnects after you unplug and replug the device.
- If the `adb` server isn't running, Dirian says so and shows the command to start it, with a copy button for pasting into Terminal.

Dirian can also share a Mac folder back to the device. See [Share Mac to Android](#share-mac-to-android).

## Share Mac to Android

Dirian can share a Mac folder to the Android device over the same USB cable, so you can browse it from the device. Browsing the Android device from the Mac doesn't need Dirian for Android. Sharing does.

1. Install Dirian for Android on the device (see [Dirian for Android](#dirian-for-android)).
2. In Dirian, click **Share Mac to Android** in the toolbar and choose the folder to share. The picker opens in iCloud Drive the first time, then at your last folder. Sharing starts when you pick it.
3. Dirian for Android opens on the device showing that folder: list or grid, group by, open files, **Save to…** or **Move to this device…**, **Upload** (copy or move), rename, new folder and delete.

While sharing, the button turns green and reads **Stop Sharing**. Click it to end. To share a different folder, stop and click again.

### How it works

- **Serving:** Dirian serves the folder from a small HTTP server on the Mac's loopback address (127.0.0.1:47615) and exposes it to the Android device with `adb reverse`, over the same adb server connection. No network or Wi-Fi is involved.
- **Security:** `adb reverse` opens the port to every app on the Android device, so each request needs a random token that Dirian passes to Dirian for Android when it launches it. A new token is made every time sharing starts. Only the chosen folder is served, and symlinks that lead outside it are hidden.

### Good to know

- **Nothing is overwritten:** an upload with a taken name is renamed ("name (1)"). Deleting from the Android device moves the item to the Mac's Trash.
- **App not installed:** if Dirian for Android isn't installed, Dirian says so and offers to open its Google Play page or the APK download on the Android device.
- **Limits:** USB only, one device at a time (the first one adb lists), and sharing stops when Dirian quits or the cable is unplugged.

## Install

With [Homebrew](https://brew.sh) (Apple silicon Macs):

```bash
brew install --cask ike-V/dirian/dirian
```

Dirian also needs an `adb` server running. See [Requirements](#requirements).

### First launch: macOS blocks it

Dirian isn't signed with an Apple Developer ID or notarized yet, so macOS blocks it the first time ("Apple could not verify Dirian is free of malware"). Do one of these, once:

- **Terminal:** `xattr -dr com.apple.quarantine /Applications/Dirian.app`
- **System Settings:** try to open Dirian, then go to System Settings → Privacy & Security, scroll to **Security**, and click **Open Anyway**.

### Dirian for Android

Only needed for [Share Mac to Android](#share-mac-to-android). Neither link works yet:

- [Google Play](https://play.google.com/store/apps/details?id=com.ikev.dirian): not published yet
- [GitHub Releases](https://github.com/ike-V/Dirian/releases/latest): APK, first release pending

Or build it (Android SDK and Gradle, or Android Studio) and install it:

```bash
cd android
gradle assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Requirements

- macOS 13 (Ventura) or later.
- An Android device with **USB debugging** enabled: Settings → About phone (or About tablet) → tap "Build number" 7 times to unlock Developer options → Developer options → USB debugging.
- The `adb` server running on your Mac. The easiest way is Homebrew: `brew install --cask android-platform-tools`. Dirian talks to this same server directly and doesn't run the `adb` binary itself.
- For Share Mac to Android: Dirian for Android on the device (Android 8.0 or later).

## Connecting your device

- Plug in your Android device before or after launching Dirian.
- The first time, a prompt on the device asks you to authorize this computer for USB debugging. Accept it, and check "always allow" to skip it next time.
- If you unplug and replug while Dirian is open, click Refresh (↻).

## Build from source

You need Xcode, set as the active developer directory: `sudo xcode-select -s /Applications/Xcode.app`. The Command Line Tools alone can't build SwiftUI's `@State` macro on the macOS 27 SDK.

```bash
git clone https://github.com/ike-V/Dirian.git
cd Dirian
./build.sh
open Dirian.app
```

## License

All rights reserved. See [LICENSE](LICENSE).
