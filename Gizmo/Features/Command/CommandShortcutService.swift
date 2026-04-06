import AppKit
import Foundation
import KeyboardShortcuts
import Observation

@Observable
@MainActor
final class CommandShortcutService {
  private let windowManagerService: WindowManagerService
  private let virtualWorkspaceService: VirtualWorkspaceService
  private let fileManager: FileManager

  private(set) var commands: [LauncherCommand]
  private var shortcutEventTasks: [String: Task<Void, Never>] = [:]
  private var workspaceNames: [String]
  private var applicationTargets: [LauncherApplicationTarget]

  init(
    windowManagerService: WindowManagerService,
    virtualWorkspaceService: VirtualWorkspaceService,
    initialWorkspaceNames: [String],
    initialApplicationTargets: [LauncherApplicationTarget] = [],
    fileManager: FileManager = .default
  ) {
    self.windowManagerService = windowManagerService
    self.virtualWorkspaceService = virtualWorkspaceService
    self.workspaceNames = initialWorkspaceNames
    self.applicationTargets = initialApplicationTargets
    self.fileManager = fileManager
    self.commands = LauncherCommand.makeAll(
      workspaceNames: initialWorkspaceNames,
      applicationTargets: initialApplicationTargets
    )
    rebuildShortcutEventStreams()
  }

  func stop() {
    for task in shortcutEventTasks.values {
      task.cancel()
    }
    shortcutEventTasks.removeAll()
  }

  func updateWorkspaceCommands(workspaceNames: [String]) {
    guard workspaceNames != self.workspaceNames else { return }
    self.workspaceNames = workspaceNames
    rebuildCommands()
  }

  func updateApplicationCommands(_ applicationTargets: [LauncherApplicationTarget]) {
    guard applicationTargets != self.applicationTargets else { return }
    self.applicationTargets = applicationTargets
    rebuildCommands()
  }

  func shortcutName(for command: LauncherCommand) -> KeyboardShortcuts.Name {
    KeyboardShortcuts.Name(shortcutNameRawValue(for: command.id))
  }

  func execute(
    _ command: LauncherCommand,
    preferredWindowElement: AXUIElement? = nil
  ) -> Result<Void, LauncherCommandError> {
    switch command.action {
    case .tile(let tileAction):
      return mapWindowManagerResult(
        windowManagerService.execute(
          tileAction,
          preferredWindowElement: preferredWindowElement
        )
      )
    case .workspaceFocus(let workspaceName):
      return mapWorkspaceResult(
        virtualWorkspaceService.focusWorkspace(workspaceName)
      )
    case .workspaceBackAndForth:
      return mapWorkspaceResult(
        virtualWorkspaceService.focusPreviousWorkspace()
      )
    case .moveFocusedWindowToWorkspace(let workspaceName):
      return mapWorkspaceResult(
        virtualWorkspaceService.moveFocusedWindowToWorkspace(
          workspaceName,
          preferredWindowElement: preferredWindowElement
        )
      )
    case .launchApplication(let target):
      return executeAppLaunch(target)
    }
  }

  private func mapWindowManagerResult(
    _ result: Result<Void, WindowManagerError>
  ) -> Result<Void, LauncherCommandError> {
    switch result {
    case .success:
      return .success(())
    case .failure(let error):
      return .failure(.windowManager(error))
    }
  }

  private func mapWorkspaceResult(
    _ result: Result<Void, WorkspaceError>
  ) -> Result<Void, LauncherCommandError> {
    switch result {
    case .success:
      return .success(())
    case .failure(let error):
      return .failure(.workspace(error))
    }
  }

  private func executeAppLaunch(
    _ target: LauncherApplicationTarget
  ) -> Result<Void, LauncherCommandError> {
    let validationResult = validateAppLaunch(target)
    guard case .success = validationResult else {
      return validationResult
    }

    guard NSWorkspace.shared.open(target.bundleURL) else {
      return .failure(.appLaunch(.openFailed))
    }

    return .success(())
  }

  func validateAppLaunch(
    _ target: LauncherApplicationTarget
  ) -> Result<Void, LauncherCommandError> {
    // Use decoded file-system path; URL.path() may keep percent-encoding like `%20`.
    let bundlePath = target.bundleURL.path

    guard fileManager.fileExists(atPath: bundlePath) else {
      return .failure(.appLaunch(.appNotFound))
    }

    return .success(())
  }

  private func rebuildCommands() {
    let nextCommands = LauncherCommand.makeAll(
      workspaceNames: workspaceNames,
      applicationTargets: applicationTargets
    )
    guard nextCommands != commands else { return }

    commands = nextCommands
    rebuildShortcutEventStreams()
  }

  private func rebuildShortcutEventStreams() {
    for task in shortcutEventTasks.values {
      task.cancel()
    }
    shortcutEventTasks.removeAll()

    for command in commands {
      let shortcutName = shortcutName(for: command)
      let commandID = command.id

      shortcutEventTasks[commandID] = Task { @MainActor [weak self] in
        for await _ in KeyboardShortcuts.events(.keyUp, for: shortcutName) {
          guard let self else { return }
          guard let command = self.commands.first(where: { $0.id == commandID }) else { continue }
          _ = self.execute(command)
        }
      }
    }
  }

  private func shortcutNameRawValue(for commandID: String) -> String {
    let encoded = Data(commandID.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")

    return "command.\(encoded)"
  }
}
