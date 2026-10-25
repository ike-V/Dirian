import SwiftUI

/// The file browser window, styled like Syndroid's Synd Apps and Actions windows:
/// a plain list of icon/title/caption rows and a bottom-right button bar instead of a toolbar.
struct FileBrowserView: View {
    private enum Layout { case list, grid }

    @StateObject private var model = FileBrowserModel()
    @StateObject private var share = MacShareModel()
    @State private var layout = Layout.list
    @State private var groupBy = GroupByOption.none
    @AppStorage("sidebarFoldersExpanded") private var foldersExpanded = true
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.accent) private var accent

    private var groups: [EntryGroup] {
        groupedEntries(model.entries, by: groupBy)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 260)
        } detail: {
            browser
        }
        .frame(minWidth: 720, minHeight: 420)
        .modifier(ShareAlerts(share: share))
        .onChange(of: model.sidebarFolders) { names in prefs.noteFolders(names) }
        .onReceive(NotificationCenter.default.publisher(for: .deviceBecameReady)) { _ in model.connectAndLoadRoot() }
        .onAppear {
            let browser = model, preferences = prefs
            share.selectedSerial = { [weak browser] in browser?.selectedSerial }
            share.accentHex = { [weak preferences] in preferences?.accent.hexString }
            model.connectAndLoadRoot()
            model.startWatchingDevices()
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The device, Android-style categories, and a collapsible list of its top-level folders.
    private var sidebar: some View {
        List {
            deviceRow
            Section {
                ForEach(FileCategory.allCases.filter { !prefs.hiddenShortcuts.contains($0.rawValue) }) { category in
                    sidebarItem(category.rawValue, symbol: category.symbol, selected: model.category == category) {
                        groupBy = .dateModified
                        Task { await model.loadCategory(category) }
                    }
                }
                if !prefs.hiddenShortcuts.contains("Downloads") {
                    sidebarRow("Downloads", symbol: "arrow.down.circle", path: "\(FileBrowserModel.rootPath)/Download")
                }
            }
            Section {
                if foldersExpanded {
                    ForEach(model.sidebarFolders.filter { !prefs.hiddenFolders.contains($0) }, id: \.self) { name in
                        sidebarRow(name, symbol: "folder", path: "\(FileBrowserModel.rootPath)/\(name)")
                    }
                }
            } header: {
                Button { withAnimation(.easeInOut(duration: 0.15)) { foldersExpanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text("Folders")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(foldersExpanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)   // the whole header row stays clickable
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }

    /// The device's root folder, with a switcher beside it when more than one device is connected.
    private var deviceRow: some View {
        HStack(spacing: 0) {
            sidebarRow(model.deviceName, symbol: "iphone", path: FileBrowserModel.rootPath)
            if model.devices.count > 1 {
                Menu {
                    Picker("Device", selection: Binding(
                        get: { model.selectedSerial ?? "" },
                        set: { model.selectDevice($0) }
                    )) {
                        ForEach(model.devices) { device in
                            Text(model.label(for: device)).tag(device.serial)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Switch device")
            }
        }
    }

    /// A sidebar row for a folder; selected only while that folder (not a category) is open.
    private func sidebarRow(_ title: String, symbol: String, path: String) -> some View {
        sidebarItem(title, symbol: symbol, selected: model.category == nil && model.currentPath == path) {
            Task { await model.load(path: path) }
        }
    }

    private func sidebarItem(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(accent.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(selected ? accent.color.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            Group {
                if let problem = model.connectionProblem {
                    connectionProblemView(problem)
                } else if layout == .list {
                    List {
                        ForEach(groups) { group in
                            if group.title.isEmpty {
                                ForEach(group.entries) { entry in row(for: entry) }
                            } else {
                                Section(header: Text(group.title)) {
                                    ForEach(group.entries) { entry in row(for: entry) }
                                }
                            }
                        }
                    }
                } else {
                    gridView
                }
            }
            Divider()
            Group {
                if let category = model.category {
                    Text(category.rawValue)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(accent.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    breadcrumbView
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(minWidth: 500)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.connectAndLoadRoot() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
            }
            ToolbarItem(placement: .primaryAction) {
                if model.isLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .glassBackgroundHidden()
            ToolbarItem(placement: .primaryAction) { layoutButton("list.bullet", .list) }
            ToolbarItem(placement: .primaryAction) { layoutButton("square.grid.2x2", .grid) }
            ToolbarItem(placement: .primaryAction) { groupByMenu }
            gap
            ToolbarItem(placement: .primaryAction) {
                Button { model.makeDirectory() } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(model.category != nil)
                .help("New Folder…")
            }
            gap
            ToolbarItem(placement: .primaryAction) {
                Button { model.uploadFiles() } label: {
                    Label("Upload Files…", systemImage: "square.and.arrow.up")
                }
                .disabled(model.category != nil)
                .help("Upload Files…")
            }
            gap
            ToolbarItem(placement: .primaryAction) { ShareButton(share: share) }
        }
    }

    /// Splits the toolbar's glass into separate groups (macOS 26+).
    @ToolbarContentBuilder
    private var gap: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }

    private var breadcrumbView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(pathComponents(model.currentPath).enumerated()), id: \.element.fullPath) { index, component in
                        if index > 1 {
                            Text("/").foregroundStyle(.secondary)
                        }
                        BreadcrumbSegment(label: component.label, isCurrent: component.fullPath == model.currentPath) {
                            Task { await model.load(path: component.fullPath) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.currentPath) { path in
                proxy.scrollTo(path, anchor: .trailing)
            }
        }
        .font(.system(.callout, design: .monospaced))
    }

    private var groupByMenu: some View {
        Menu {
            Picker("Group By", selection: $groupBy) {
                ForEach(GroupByOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Group")
            } icon: {
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(groupBy == .none ? Color.primary : accent.color)
        }
        .menuIndicator(.hidden)
        .help("Group By")
    }

    private func layoutButton(_ symbol: String, _ value: Layout) -> some View {
        Button { layout = value } label: {
            Label(value == .list ? "List" : "Grid", systemImage: symbol)
                .foregroundStyle(layout == value ? accent.color : Color.primary)
        }
        .help(value == .list ? "List View" : "Grid View")
    }

    private func iconStyle(for entry: AdbDirEntry) -> AnyShapeStyle {
        entry.isDirectory ? AnyShapeStyle(accent.folderGradient) : AnyShapeStyle(accent.color)
    }

    /// The size, plus the folder a category result is in.
    private func caption(for entry: AdbDirEntry) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)
        guard let path = entry.fullPath else { return size }
        let folder = (path as NSString).deletingLastPathComponent
            .dropFirst(FileBrowserModel.rootPath.count).drop { $0 == "/" }
        return "\(size) · \(folder.isEmpty ? "Internal storage" : String(folder))"
    }

    private func row(for entry: AdbDirEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: entry.isDirectory ? 22 : 13))
                .frame(width: 24, height: 20)
                .foregroundStyle(iconStyle(for: entry))
            VStack(alignment: .leading, spacing: 2) {
                RowNameText(entry.name)
                if !entry.isDirectory {
                    Text(caption(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .interactions(model: model, entry: entry)
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    if !group.title.isEmpty {
                        Text(group.title).font(.headline).padding(.horizontal, 12)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 96), spacing: 12)], spacing: 16) {
                        ForEach(group.entries) { entry in
                            VStack(spacing: 4) {
                                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                                    .font(.system(size: 40))
                                    .foregroundStyle(iconStyle(for: entry))
                                Text(entry.name)
                                    .font(.system(size: 10))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                if !entry.isDirectory {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 96)
                            .padding(.vertical, 6)
                            .interactions(model: model, entry: entry)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func connectionProblemView(_ problem: ConnectionProblem) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(problem.title).font(.headline)
            Text(problem.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let command = problem.command {
                CommandBox(command: command)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A command in monospaced text with a button that copies exactly that command.
struct CommandBox: View {
    let command: String
    @State private var copied = false
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(accent.color)
            }
            .buttonStyle(.plain)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A file/folder row's name, tinted green on hover.
private struct RowNameText: View {
    let name: String
    @State private var isHovering = false
    @Environment(\.accent) private var accent

    init(_ name: String) { self.name = name }

    var body: some View {
        Text(name)
            .font(.system(size: 12.5))
            .lineLimit(1)
            .foregroundStyle(isHovering ? accent.color : .primary)
            .onHover { isHovering = $0 }
    }
}

/// One clickable, hoverable segment of the path breadcrumb; the current folder stays green.
private struct BreadcrumbSegment: View {
    let label: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accent) private var accent

    var body: some View {
        Text(label)
            .foregroundStyle(isCurrent || isHovering ? accent.color : .secondary)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Splits an absolute path like "/storage/emulated/0" into breadcrumb segments, each
/// paired with the full path up to and including that segment. The root "/" is always
/// the first segment, so it's just another clickable stop in the chain.
private func pathComponents(_ path: String) -> [(label: String, fullPath: String)] {
    var result: [(label: String, fullPath: String)] = [("/", "/")]
    var accumulated = ""
    for part in path.split(separator: "/") {
        accumulated += "/\(part)"
        result.append((String(part), accumulated))
    }
    return result
}

private extension ToolbarContent {
    /// Hides the macOS 26 Liquid Glass background behind a toolbar item; no-op earlier.
    @ToolbarContentBuilder
    func glassBackgroundHidden() -> some ToolbarContent {
        if #available(macOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

private extension View {
    /// Double-click to open, plus the rename/save/delete context menu.
    func interactions(model: FileBrowserModel, entry: AdbDirEntry) -> some View {
        contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(entry: entry) }
            .contextMenu {
                Button("Rename…") { model.rename(entry: entry) }
                if !entry.isDirectory {
                    Button("Save to…") { model.saveToFolder(entry: entry) }
                }
                Button("Delete", role: .destructive) { model.delete(entry: entry) }
            }
    }
}
