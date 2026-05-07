import AppKit
import KeyboardShortcuts
import SwiftUI

struct CommandView: View {
  private enum CommandGroup: String, CaseIterable, Hashable {
    case window
    case workspace
    case applications

    var localizedTitle: LocalizedStringResource {
      switch self {
      case .window:
        return "Window"
      case .workspace:
        return "Workspace"
      case .applications:
        return "Applications"
      }
    }

    var systemImageName: String {
      switch self {
      case .window:
        return "macwindow"
      case .workspace:
        return "square.grid.2x2.fill"
      case .applications:
        return "folder.fill"
      }
    }

    var tint: Color {
      switch self {
      case .window:
        return .orange
      case .workspace:
        return .green
      case .applications:
        return .blue
      }
    }
  }

  private struct CommandTableRow: Identifiable {
    enum Kind {
      case command(LauncherCommand)
      case group(CommandGroup)
    }

    let id: String
    let kind: Kind
    let indentationLevel: Int

    var command: LauncherCommand? {
      if case .command(let command) = kind {
        return command
      }

      return nil
    }

  }

  @Environment(CommandShortcutService.self) private var commandShortcutService

  @State private var query: String = ""
  @State private var expandedGroups: Set<CommandGroup> = []
  @State private var lastExecutionError: LauncherCommandError?

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isSearching: Bool {
    !trimmedQuery.isEmpty
  }

  private var filteredCommands: [LauncherCommand] {
    guard !trimmedQuery.isEmpty else {
      return commandShortcutService.commands
    }

    let normalizedQuery = trimmedQuery.lowercased()
    return commandShortcutService.commands.filter { command in
      command.title.lowercased().contains(normalizedQuery)
        || command.id.lowercased().contains(normalizedQuery)
        || command.keywords.contains(where: { $0.lowercased().contains(normalizedQuery) })
    }
  }

  private var ungroupedCommands: [LauncherCommand] {
    filteredCommands.filter { commandGroup(for: $0) == nil }
  }

  private var displayRows: [CommandTableRow] {
    var rows = ungroupedCommands.map {
      CommandTableRow(id: $0.id, kind: .command($0), indentationLevel: 0)
    }

    for group in CommandGroup.allCases {
      let commands = commands(in: group)
      guard !commands.isEmpty else { continue }

      rows.append(
        CommandTableRow(
          id: "group-\(group.rawValue)",
          kind: .group(group),
          indentationLevel: 0
        )
      )

      if isGroupExpanded(group) {
        rows.append(
          contentsOf: commands.map {
            CommandTableRow(
              id: "group-\(group.rawValue)-\($0.id)",
              kind: .command($0),
              indentationLevel: 1
            )
          }
        )
      }
    }

    return rows
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if displayRows.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          Text(String(localized: "No commands found."))
            .foregroundStyle(.secondary)
        }
      }
      else {
        Table(displayRows) {
          TableColumn(String(localized: "Name")) { row in
            nameCell(for: row)
          }

          TableColumn(String(localized: "Shortcut")) { row in
            shortcutCell(for: row)
          }
          .width(min: 170, ideal: 190)

          TableColumn(String(localized: "Run")) { row in
            runCell(for: row)
          }
          .width(56)
        }
        .font(.system(size: 13))
      }

      if let lastExecutionError {
        Text(lastExecutionError.localizedDescription)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .searchable(text: $query, prompt: String(localized: "Search commands and apps"))
  }

  @ViewBuilder
  private func nameCell(for row: CommandTableRow) -> some View {
    switch row.kind {
    case .group(let group):
      Button {
        guard !isSearching else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
          toggleGroup(group)
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isGroupExpanded(group) ? 90 : 0))

          Image(systemName: group.systemImageName)
            .foregroundStyle(group.tint)

          Text(group.localizedTitle)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

    case .command(let command):
      HStack(spacing: 8) {
        Color.clear
          .frame(width: row.indentationLevel == 0 ? 0 : 16, height: 1)

        if case .launchApplication(let target) = command.action {
          appIcon(for: target)
        }

        Text(command.title)
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func shortcutCell(for row: CommandTableRow) -> some View {
    if let command = row.command {
      HStack {
        KeyboardShortcuts.Recorder(for: commandShortcutService.shortcutName(for: command))
      }
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private func runCell(for row: CommandTableRow) -> some View {
    if let command = row.command {
      Button(String(localized: "Run")) {
        execute(command)
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    } else {
      EmptyView()
    }
  }

  private func commands(in group: CommandGroup) -> [LauncherCommand] {
    filteredCommands.filter { commandGroup(for: $0) == group }
  }

  private func isGroupExpanded(_ group: CommandGroup) -> Bool {
    isSearching ? !commands(in: group).isEmpty : expandedGroups.contains(group)
  }

  private func toggleGroup(_ group: CommandGroup) {
    if expandedGroups.contains(group) {
      expandedGroups.remove(group)
    } else {
      expandedGroups.insert(group)
    }
  }

  private func appIcon(for target: LauncherApplicationTarget) -> some View {
    let iconPath = target.bundleURL.resolvingSymlinksInPath().path

    return Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
      .resizable()
      .interpolation(.high)
      .frame(width: 16, height: 16)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }

  private func commandGroup(for command: LauncherCommand) -> CommandGroup? {
    switch command.action {
    case .tile:
      return .window
    case .workspaceFocus, .workspaceBackAndForth, .moveFocusedWindowToWorkspace:
      return .workspace
    case .launchApplication:
      return .applications
    }
  }

  private func execute(_ command: LauncherCommand) {
    switch commandShortcutService.execute(command) {
    case .success:
      lastExecutionError = nil
    case .failure(let error):
      lastExecutionError = error
    }
  }
}

#Preview {
  CommandView()
    .environment(
      CommandShortcutService(
        windowManagerService: WindowManagerService(
          permissionService: AccessibilityPermissionService()
        ),
        workspaceService: WorkspaceService(
          permissionService: AccessibilityPermissionService(),
          initialConfig: .default
        ),
        initialWorkspaceNames: WorkspaceConfig.defaultNames
      )
    )
}
