import Cocoa
import ServiceManagement
import SwiftUI

final class PanelModel: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let item: MenuBarItem
        let title: String
    }

    struct Section: Identifiable {
        let id: String
        let title: String?
        let rows: [Row]
    }

    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 26
    static let listPadding: CGFloat = 5
    static let maxListHeight: CGFloat = 420

    @Published private(set) var sections: [Section] = []
    @Published var selection = 0
    @Published var collapsed = true
    /// Bumped every time the panel is shown, so the search field can grab focus again.
    @Published var presentation = 0
    @Published var query = "" {
        didSet { rebuild() }
    }

    var items: [MenuBarItem] = [] {
        didSet { rebuild() }
    }
    var screen: NSScreen?

    var onActivate: (MenuBarItem, _ forceClick: Bool) -> Void = { _, _ in }
    var onToggleCollapsed: () -> Void = {}

    var rows: [Row] { sections.flatMap(\.rows) }

    var listHeight: CGFloat {
        let headers = CGFloat(sections.filter { $0.title != nil }.count) * Self.headerHeight
        let content = max(CGFloat(rows.count), 1) * Self.rowHeight + headers + Self.listPadding * 2
        return min(content, Self.maxListHeight)
    }

    func moveSelection(by delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func activateSelection(forceClick: Bool = false) {
        guard let row = rows.first(where: { $0.id == selection }) else { return }
        onActivate(row.item, forceClick)
    }

    private func rebuild() {
        let siblings = Dictionary(grouping: items, by: \.pid).mapValues(\.count)
        let titled = items.map { ($0, Self.title(for: $0, siblings: siblings[$0.pid] ?? 1)) }
        var nextID = 0
        func rows(_ entries: [(MenuBarItem, String)]) -> [Row] {
            entries.map { entry in
                defer { nextID += 1 }
                return Row(id: nextID, item: entry.0, title: entry.1)
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let groups: [(String, (MenuBarItem) -> Bool)] = [
                ("Hidden", { $0.visibility(on: self.screen) == .hidden }),
                ("Behind the Notch", { $0.visibility(on: self.screen) == .notch }),
                ("Visible", { $0.visibility(on: self.screen) == .visible && !$0.isApple }),
                ("System", { $0.visibility(on: self.screen) == .visible && $0.isApple }),
            ]
            sections = groups.compactMap { title, belongs in
                let members = titled.filter { belongs($0.0) }
                return members.isEmpty ? nil : Section(id: title, title: title, rows: rows(members))
            }
        } else {
            let ranked = titled
                .compactMap { entry in Fuzzy.score(trimmed, in: entry.1).map { (entry, $0) } }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
            sections = ranked.isEmpty ? [] : [Section(id: "results", title: nil, rows: rows(ranked))]
        }
        selection = 0
    }

    private static func title(for item: MenuBarItem, siblings: Int) -> String {
        let detail = item.detail.map { $0.count > 40 ? $0.prefix(40) + "…" : $0 }
        if item.isApple { return detail ?? item.appName }
        if siblings > 1, let detail, detail != item.appName { return "\(item.appName) — \(detail)" }
        return item.appName
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool
    @AppStorage(Settings.showDurationKey) private var showDuration = Settings.defaultShowDuration
    @AppStorage(Settings.keepSystemItemsVisibleKey) private var keepSystemItemsVisible = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search menu bar items", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 300)
        .onAppear { searchFocused = true }
        .onChange(of: model.presentation) { searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 4)
                                .frame(height: PanelModel.headerHeight, alignment: .bottomLeading)
                        }
                        ForEach(section.rows) { row in
                            rowView(row).id(row.id)
                        }
                    }
                    if model.sections.isEmpty {
                        Text(model.query.isEmpty ? "No menu bar items found" : "No matches")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: PanelModel.rowHeight)
                    }
                }
                .padding(.vertical, PanelModel.listPadding)
            }
            .frame(height: model.listHeight)
            .onChange(of: model.selection) { proxy.scrollTo(model.selection) }
        }
    }

    private func rowView(_ row: PanelModel.Row) -> some View {
        let selected = row.id == model.selection
        return HStack(spacing: 8) {
            Group {
                if let icon = row.item.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable()
                }
            }
            .frame(width: 18, height: 18)
            Text(row.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: PanelModel.rowHeight)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { if $0 { model.selection = row.id } }
        .onTapGesture { model.onActivate(row.item, NSEvent.modifierFlags.contains(.option)) }
    }

    private var footer: some View {
        HStack {
            Button(model.collapsed ? "Show Hidden Items" : "Hide Items") { model.onToggleCollapsed() }
                .buttonStyle(.borderless)
            Spacer()
            Menu {
                Picker("Keep Opened Item on Menu Bar For", selection: $showDuration) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("Until I move it back").tag(0.0)
                }
                Toggle("Keep System Items Visible", isOn: $keepSystemItemsVisible)
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Divider()
                Button("Quit Tuck") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
