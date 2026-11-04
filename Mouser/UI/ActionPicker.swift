import SwiftUI

/// Compact replacement for a 33-item menu: a button showing the current action
/// that opens a searchable, categorized two-column grid.
struct ActionPickerButton: View {
    @Binding var selection: MouseAction
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.symbolName)
                    .frame(width: 16)
                    .foregroundStyle(selection == .default ? Color.secondary : Color.accentColor)
                Text(selection.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            ActionPickerList(selection: $selection) {
                isPresented = false
            }
        }
    }
}

/// Search field plus categorized grid. Used inside the picker popover and
/// directly in the mouse-diagram popover.
struct ActionPickerList: View {
    @Binding var selection: MouseAction
    var onPick: () -> Void = {}
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search actions"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = matches.first?.actions.first { pick(first) }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    if matches.isEmpty {
                        Text(String(localized: "No matching actions"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                        ForEach(matches, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.category.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                LazyVGrid(columns: columns, spacing: 6) {
                                    ForEach(group.actions) { action in
                                        ActionTile(action: action, isSelected: action == selection) {
                                            pick(action)
                                        }
                                        .id(action)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
        .frame(width: 340, height: 420)
        .onAppear { searchFocused = true }
    }

    private struct Group {
        let category: MouseAction.Category
        let actions: [MouseAction]
    }

    private var matches: [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return MouseAction.Category.allCases.compactMap { category in
            let actions = MouseAction.allCases.filter { action in
                guard action.category == category else { return false }
                guard !needle.isEmpty else { return true }
                return action.title.lowercased().contains(needle)
                    || action.rawValue.lowercased().contains(needle)
                    || category.title.lowercased().contains(needle)
            }
            return actions.isEmpty ? nil : Group(category: category, actions: actions)
        }
    }

    private func pick(_ action: MouseAction) {
        selection = action
        onPick()
    }
}

private struct ActionTile: View {
    let action: MouseAction
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(action.title)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 2)
                if let hint = action.shortcutHint {
                    Text(hint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.08 : 0.04))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.title)
    }
}

extension MouseAction {
    var symbolName: String {
        switch self {
        case .default: "arrow.uturn.backward.circle"
        case .none: "nosign"
        case .leftClick: "cursorarrow.click"
        case .rightClick: "cursorarrow.click.2"
        case .middleClick: "computermouse"
        case .backClick: "chevron.backward.circle"
        case .forwardClick: "chevron.forward.circle"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .cut: "scissors"
        case .undo: "arrow.uturn.backward"
        case .selectAll: "checklist"
        case .save: "square.and.arrow.down"
        case .find: "magnifyingglass"
        case .browserBack: "arrow.backward"
        case .browserForward: "arrow.forward"
        case .newTab: "plus.square.on.square"
        case .closeTab: "xmark.square"
        case .nextTab: "arrow.right.square"
        case .prevTab: "arrow.left.square"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.stack"
        case .launchpad: "square.grid.3x3"
        case .spotlight: "magnifyingglass.circle"
        case .spaceLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .spaceRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .screenshot: "camera.viewfinder"
        case .volumeUp: "speaker.wave.3"
        case .volumeDown: "speaker.wave.1"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .nextTrack: "forward.end"
        case .prevTrack: "backward.end"
        }
    }

    /// The keyboard shortcut this action sends, e.g. "⌘C", for display.
    var shortcutHint: String? {
        guard let combo = keyCombo else { return nil }
        let keys: [CGKeyCode: String] = [
            0x00: "A", 0x01: "S", 0x03: "F", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0D: "W", 0x11: "T", 0x1E: "]", 0x21: "[", 0x30: "⇥",
        ]
        guard let key = keys[combo.key] else { return nil }
        var text = ""
        if combo.flags.contains(.maskControl) { text += "⌃" }
        if combo.flags.contains(.maskAlternate) { text += "⌥" }
        if combo.flags.contains(.maskShift) { text += "⇧" }
        if combo.flags.contains(.maskCommand) { text += "⌘" }
        return text + key
    }
}
