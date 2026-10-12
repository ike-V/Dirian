import SwiftUI

/// The file browser window, styled like Syndroid's Synd Apps and Actions windows:
/// a plain list of icon/title/caption rows and a bottom-right button bar instead of a toolbar.
struct FileBrowserView: View {
    private enum Layout { case list, grid }

    @StateObject private var model = FileBrowserModel()
    @StateObject private var share = MacShareModel()
    @State private var layout = Layout.list
    @State private var groupBy = GroupByOption.none

    private var groups: [EntryGroup] {
        groupedEntries(model.entries, by: groupBy)
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
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
            HStack {
                Button("New Folder…") { model.makeDirectory() }
                Spacer()
                ShareMenu(share: share)
                Spacer()
                Button("Upload Files…") { model.uploadFiles() }
            }
            .padding(12)
        }
        .frame(minWidth: 500, minHeight: 420)
        .onAppear { model.connectAndLoadRoot() }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            breadcrumbView
            Spacer()
            if model.isLoading {
                ProgressView().scaleEffect(0.6)
            }
            HStack(spacing: 2) {
                layoutButton("list.bullet", .list)
                layoutButton("square.grid.2x2", .grid)
            }
            groupByMenu
            Button { model.connectAndLoadRoot() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(pathComponents(model.currentPath).enumerated()), id: \.element.fullPath) { index, component in
                    if index > 1 {
                        Text("/").foregroundStyle(.secondary)
                    }
                    BreadcrumbSegment(label: component.label) {
                        Task { await model.load(path: component.fullPath) }
                    }
                }
            }
        }
        .font(.system(.callout, design: .monospaced))
        .frame(maxWidth: 360)
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
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .foregroundStyle(groupBy == .none ? .secondary : Color.androidGreen)
                .frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func layoutButton(_ symbol: String, _ value: Layout) -> some View {
        Button { layout = value } label: {
            Image(systemName: symbol)
                .foregroundStyle(layout == value ? Color.androidGreen : .secondary)
                .frame(width: 28, height: 22)
                .background(layout == value ? Color.androidGreen.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func row(for entry: AdbDirEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .font(.system(size: entry.isDirectory ? 22 : 13))
                .frame(width: 24, height: 20)
                .foregroundStyle(Color.androidGreen)
            VStack(alignment: .leading, spacing: 2) {
                RowNameText(entry.name)
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
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
                                Image(systemName: entry.isDirectory ? "folder" : "doc")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.androidGreen)
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
private struct CommandBox: View {
    let command: String
    @State private var copied = false

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
                    .foregroundStyle(Color.androidGreen)
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

    init(_ name: String) { self.name = name }

    var body: some View {
        Text(name)
            .font(.system(size: 12.5))
            .lineLimit(1)
            .foregroundStyle(isHovering ? Color.androidGreen : .primary)
            .onHover { isHovering = $0 }
    }
}

/// One clickable, hoverable segment of the path breadcrumb.
private struct BreadcrumbSegment: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(label)
            .foregroundStyle(isHovering ? Color.androidGreen : .secondary)
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
