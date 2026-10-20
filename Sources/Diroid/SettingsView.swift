import SwiftUI

/// The Settings window (⌘,): tabs in the style of Finder's settings.
struct SettingsView: View {
    @Environment(\.accent) private var accent

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            SidebarSettings()
                .tabItem { Label("Sidebar", systemImage: "sidebar.left") }
        }
        .tint(accent.color)
    }
}

/// Whether Dirian looks for a newer release when it opens.
private struct GeneralSettings: View {
    @EnvironmentObject private var prefs: AppPrefs

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $prefs.checkForUpdates)

            Text("When Dirian opens, it reads the latest release number from GitHub, at most once a day. You can also check any time from Dirian > Check for Updates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460, height: 120, alignment: .topLeading)
    }
}

/// Pick the accent color from the same colors as Finder's tags.
private struct AppearanceSettings: View {
    @EnvironmentObject private var prefs: AppPrefs

    var body: some View {
        Form {
            Picker("Accent color:", selection: $prefs.accent) {
                ForEach(AccentChoice.allCases) { choice in
                    Label {
                        Text(choice.name)
                    } icon: {
                        Circle().fill(choice.color).frame(width: 12, height: 12)
                    }
                    .tag(choice)
                }
            }
            .pickerStyle(.radioGroup)

            Text("Used for icons, folders and highlights. Dirian for Android uses the same color when you share a folder to it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460, height: 280, alignment: .topLeading)
    }
}

/// Choose which shortcuts and device folders appear in the browser's sidebar.
private struct SidebarSettings: View {
    @EnvironmentObject private var prefs: AppPrefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Show these items in the sidebar:")
                    .padding(.bottom, 4)

                header("Shortcuts")
                ForEach(AppPrefs.shortcuts, id: \.name) { shortcut in
                    Toggle(isOn: shown($prefs.hiddenShortcuts, shortcut.name)) {
                        Label(shortcut.name, systemImage: shortcut.symbol)
                    }
                }

                header("Folders")
                if prefs.knownFolders.isEmpty {
                    Text("Connect a device to choose which of its folders to show.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.knownFolders, id: \.self) { name in
                        Toggle(isOn: shown($prefs.hiddenFolders, name)) {
                            Label(name, systemImage: "folder")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 440)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
    }

    /// A checkbox binding for "shown": on unless `name` is in the hidden set.
    private func shown(_ hidden: Binding<Set<String>>, _ name: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.wrappedValue.contains(name) },
            set: { isShown in
                if isShown { hidden.wrappedValue.remove(name) } else { hidden.wrappedValue.insert(name) }
            })
    }
}
