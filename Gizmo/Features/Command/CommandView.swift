import KeyboardShortcuts
import SwiftUI

struct CommandView: View {
  @Environment(CommandShortcutService.self) private var commandShortcutService

  @State private var query: String = ""
  @State private var lastExecutionError: LauncherCommandError?

  private var filteredCommands: [LauncherCommand] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
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

  var body: some View {
    Form {
      Section {
        LabeledContent(
          String(localized: "Total Commands"),
          value: "\(commandShortcutService.commands.count)"
        )

        Text(
          String(
            localized:
              "Assign a shortcut per command. Assigned shortcuts work globally while Gizmo is running."
          )
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      } header: {
        Text(String(localized: "Overview"))
      }

      Section {
        if filteredCommands.isEmpty {
          Text(String(localized: "No commands found."))
            .foregroundStyle(.secondary)
        } else {
          ForEach(filteredCommands) { command in
            commandRow(command)
          }
        }

        if let lastExecutionError {
          Text(lastExecutionError.localizedDescription)
            .font(.caption)
            .foregroundStyle(.red)
        }
      } header: {
        Text(String(localized: "Commands"))
      }
    }
    .formStyle(.grouped)
    .searchable(text: $query, prompt: String(localized: "Search commands and apps"))
  }

  @ViewBuilder
  private func commandRow(_ command: LauncherCommand) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(command.title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
          Text(actionDescription(for: command.action))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        KeyboardShortcuts.Recorder(for: commandShortcutService.shortcutName(for: command))
      }

      HStack(spacing: 8) {
        Button(String(localized: "Run")) {
          execute(command)
        }
        .buttonStyle(.bordered)

        Text(command.id)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.vertical, 2)
  }

  private func execute(_ command: LauncherCommand) {
    switch commandShortcutService.execute(command) {
    case .success:
      lastExecutionError = nil
    case .failure(let error):
      lastExecutionError = error
    }
  }

  private func actionDescription(for action: LauncherAction) -> String {
    switch action {
    case .tile:
      return String(localized: "Window tiling command")
    case .workspaceFocus(let name):
      return String(localized: "Switch to workspace \(name)")
    case .workspaceBackAndForth:
      return String(localized: "Switch between current and previous workspace")
    case .moveFocusedWindowToWorkspace(let name):
      return String(localized: "Move focused window to workspace \(name)")
    case .launchApplication(let target):
      return String(localized: "Launch app \(target.displayName)")
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
        virtualWorkspaceService: VirtualWorkspaceService(
          permissionService: AccessibilityPermissionService(),
          initialConfig: .default
        ),
        initialWorkspaceNames: WorkspaceConfig.defaultNames
      )
    )
}
