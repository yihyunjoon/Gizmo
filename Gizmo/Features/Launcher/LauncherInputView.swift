import AppKit
import SwiftUI

struct LauncherInputView: View {
  private enum Layout {
    static let maxVisibleRows = 5
    static let maxVisibleRowsWhenError = 3
    static let rowHeight: CGFloat = 33
    static let rowSpacing: CGFloat = 6
    static let listVerticalPadding: CGFloat = 2
  }

  // MARK: - Properties

  let commands: [LauncherCommand]
  let onClose: () -> Void
  let onExecuteCommand: (LauncherCommand) -> Result<Void, LauncherCommandError>
  let onOpenAccessibilitySettings: () -> Void
  let onOpenMainWindow: () -> Void
  let matcher: LauncherFuzzyMatcher = LauncherFuzzyMatcher()
  let usageStore: LauncherUsageStore = LauncherUsageStore()

  @State private var query: String = ""
  @State private var selectedCommandIndex: Int = 0
  @State private var executionError: LauncherCommandError?

  @FocusState private var isInputFocused: Bool

  private var rankedCommands: [LauncherMatchResult] {
    matcher.rank(
      commands: commands,
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
      ? Layout.maxVisibleRows
      : Layout.maxVisibleRowsWhenError
    return min(displayedCommands.count, maxRows)
  }

  private var commandListHeight: CGFloat {
    guard visibleRows > 0 else { return 0 }

    let rowCount = CGFloat(visibleRows)
    let rowHeights = rowCount * Layout.rowHeight
    let rowSpacings = CGFloat(max(0, visibleRows - 1)) * Layout.rowSpacing
    let verticalPadding = Layout.listVerticalPadding * 2
    return rowHeights + rowSpacings + verticalPadding
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.system(size: 18, weight: .medium))

        TextField(
          String(localized: "Search apps and commands"),
          text: $query
        )
        .textFieldStyle(.plain)
        .font(.system(size: 24, weight: .medium, design: .rounded))
        .focused($isInputFocused)
        .onSubmit {
          executeSelectedCommand()
        }
      }

      Divider()

      if displayedCommands.isEmpty {
        Text(String(localized: "No matching results."))
          .font(.system(size: 13, weight: .regular, design: .rounded))
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: Layout.rowSpacing) {
            ForEach(Array(displayedCommands.enumerated()), id: \.element.id) {
              index, command in
              commandRow(command: command, isSelected: index == selectedCommandIndex)
              .onTapGesture {
                selectedCommandIndex = index
                executeSelectedCommand()
              }
            }
          }
          .padding(.vertical, Layout.listVerticalPadding)
        }
        .frame(height: commandListHeight, alignment: .top)
      }

      if let executionError {
        VStack(alignment: .leading, spacing: 8) {
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
    .padding(16)
    .frame(width: 640)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
    }
    .padding(12)
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
    HStack {
      if case .launchApplication(let target) = command.action {
        appIcon(for: target)
      }

      Text(command.title)
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? .blue.opacity(0.22) : .clear)
    )
  }

  private func appIcon(for target: LauncherApplicationTarget) -> some View {
    Image(nsImage: NSWorkspace.shared.icon(forFile: target.bundleURL.path()))
      .resizable()
      .interpolation(.high)
      .frame(width: 18, height: 18)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
    commands: LauncherCommand.makeAll(workspaceNames: WorkspaceConfig.defaultNames),
    onClose: {},
    onExecuteCommand: { _ in .success(()) },
    onOpenAccessibilitySettings: {},
    onOpenMainWindow: {}
  )
}
