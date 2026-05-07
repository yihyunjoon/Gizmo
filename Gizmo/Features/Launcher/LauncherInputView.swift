import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class LauncherInputModel {
  var commands: [LauncherCommand]

  init(commands: [LauncherCommand]) {
    self.commands = commands
  }
}

struct LauncherInputView: View {
  // MARK: - Properties

  let model: LauncherInputModel
  let onClose: () -> Void
  let onExecuteCommand: (LauncherCommand) -> Result<Void, LauncherCommandError>
  let onOpenAccessibilitySettings: () -> Void
  let onOpenMainWindow: () -> Void
  let matcher: LauncherFuzzyMatcher = LauncherFuzzyMatcher()
  let usageStore: LauncherUsageStore = LauncherUsageStore()
  private let theme = GizmoTheme.current

  @State private var query: String = ""
  @State private var selectedCommandIndex: Int = 0
  @State private var executionError: LauncherCommandError?

  @FocusState private var isInputFocused: Bool

  private var rankedCommands: [LauncherMatchResult] {
    matcher.rank(
      commands: model.commands,
      query: query,
      usageStore: usageStore
    )
  }

  private var displayedCommands: [LauncherCommand] {
    rankedCommands.map(\.command)
  }

  private var visibleRows: Int {
    let maxRows =
      executionError == nil
      ? theme.launcher.maxVisibleRows
      : theme.launcher.maxVisibleRowsWhenError
    return min(displayedCommands.count, maxRows)
  }

  private var commandListHeight: CGFloat {
    guard visibleRows > 0 else { return 0 }

    let rowCount = CGFloat(visibleRows)
    let rowHeights = rowCount * theme.launcher.rowHeight
    let rowSpacings = CGFloat(max(0, visibleRows - 1)) * theme.launcher.rowSpacing
    let verticalPadding = theme.launcher.listVerticalPadding * 2
    return rowHeights + rowSpacings + verticalPadding
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: theme.launcher.contentSpacing) {
      HStack(spacing: theme.launcher.searchFieldSpacing) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(theme.launcher.searchIconFont)

        TextField(
          String(localized: "Search apps and commands"),
          text: $query
        )
        .textFieldStyle(.plain)
        .font(theme.launcher.searchInputFont)
        .focused($isInputFocused)
        .onSubmit {
          executeSelectedCommand()
        }
      }

      Divider()

      if displayedCommands.isEmpty {
        Text(String(localized: "No matching results."))
          .font(theme.launcher.emptyResultFont)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: theme.launcher.rowSpacing) {
            ForEach(Array(displayedCommands.enumerated()), id: \.element.id) {
              index, command in
              commandRow(command: command, isSelected: index == selectedCommandIndex)
              .onTapGesture {
                selectedCommandIndex = index
                executeSelectedCommand()
              }
            }
          }
          .padding(.vertical, theme.launcher.listVerticalPadding)
        }
        .frame(height: commandListHeight, alignment: .top)
      }

      if let executionError {
        VStack(alignment: .leading, spacing: theme.launcher.errorContentSpacing) {
          Text(executionError.localizedDescription)
            .font(.footnote)
            .foregroundStyle(.red)

          if executionError.isAccessibilityPermissionError {
            Button(String(localized: "Open System Settings")) {
              onOpenAccessibilitySettings()
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .padding(theme.launcher.panelPadding)
    .frame(width: theme.launcher.panelWidth)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: theme.launcher.panelCornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.launcher.panelCornerRadius, style: .continuous)
        .strokeBorder(theme.launcher.panelBorderColor, lineWidth: theme.launcher.panelBorderWidth)
    }
    .padding(theme.launcher.panelOuterPadding)
    .onAppear {
      focusInput()
    }
    .onChange(of: query) { _, _ in
      selectedCommandIndex = 0
      executionError = nil
    }
    .onReceive(NotificationCenter.default.publisher(for: .launcherPanelDidOpen)) { _ in
      query = ""
      executionError = nil
      selectedCommandIndex = 0
      focusInput()
    }
    .onExitCommand {
      onClose()
    }
    .onKeyPress(phases: [.down]) { keyPress in
      guard keyPress.modifiers.contains(.command), keyPress.characters == "," else {
        return .ignored
      }

      onOpenMainWindow()
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress(.return) {
      executeSelectedCommand()
      return .handled
    }
    .onKeyPress(.escape) {
      onClose()
      return .handled
    }
  }

  // MARK: - Private

  @ViewBuilder
  private func commandRow(command: LauncherCommand, isSelected: Bool) -> some View {
    HStack(spacing: theme.launcher.rowContentSpacing) {
      leadingAccessory(for: command)

      Text(command.title)
        .font(theme.launcher.commandTitleFont)
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, theme.launcher.rowHorizontalPadding)
    .padding(.vertical, theme.launcher.rowVerticalPadding)
    .background(
      RoundedRectangle(cornerRadius: theme.launcher.rowCornerRadius, style: .continuous)
        .fill(theme.launcher.rowBackgroundColor(isSelected: isSelected))
    )
  }

  @ViewBuilder
  private func leadingAccessory(for command: LauncherCommand) -> some View {
    Group {
      if case .launchApplication(let target) = command.action {
        appIcon(for: target)
      } else {
        Color.clear
      }
    }
    .frame(width: theme.launcher.leadingSlotSize, height: theme.launcher.leadingSlotSize)
  }

  private func appIcon(for target: LauncherApplicationTarget) -> some View {
    let iconPath = target.bundleURL.resolvingSymlinksInPath().path

    return Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
      .resizable()
      .interpolation(.high)
      .frame(width: theme.launcher.leadingSlotSize, height: theme.launcher.leadingSlotSize)
      .clipShape(RoundedRectangle(cornerRadius: theme.launcher.iconCornerRadius, style: .continuous))
  }

  private func executeSelectedCommand() {
    guard !displayedCommands.isEmpty else { return }

    let index = max(0, min(selectedCommandIndex, displayedCommands.count - 1))
    let command = displayedCommands[index]

    switch onExecuteCommand(command) {
    case .success:
      usageStore.recordExecution(commandID: command.id)
      executionError = nil
      onClose()
    case .failure(let error):
      executionError = error
    }
  }

  private func moveSelection(by delta: Int) {
    guard !displayedCommands.isEmpty else { return }

    let count = displayedCommands.count
    let nextIndex = (selectedCommandIndex + delta + count) % count
    selectedCommandIndex = nextIndex
  }

  private func focusInput() {
    DispatchQueue.main.async {
      isInputFocused = true
    }
  }
}

#Preview {
  LauncherInputView(
    model: LauncherInputModel(
      commands: LauncherCommand.makeAll(workspaceNames: WorkspaceConfig.defaultNames)
    ),
    onClose: {},
    onExecuteCommand: { _ in .success(()) },
    onOpenAccessibilitySettings: {},
    onOpenMainWindow: {}
  )
}
