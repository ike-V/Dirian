import SwiftUI

/// The file browser window, styled like Syndroid's Synd Apps and Actions windows:
/// a plain list of icon/title/caption rows and a bottom-right button bar instead of a toolbar.
struct FileBrowserView: View {
    private enum Layout { case list, grid }

    @StateObject private var model = FileBrowserModel()
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
            Button {
                if let parent = parentPath(model.currentPath) {
                    Task { await model.load(path: parent) }
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(model.currentPath == "/")
            Text(model.currentPath)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
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
                .font(.system(size: entry.isDirectory ? 17 : 13))
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.androidGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.system(size: 12.5)).lineLimit(1)
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The path one level up, or nil at the root.
private func parentPath(_ path: String) -> String? {
    guard path != "/" else { return nil }
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
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
