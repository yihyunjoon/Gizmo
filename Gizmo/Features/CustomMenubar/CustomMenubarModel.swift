import AppKit
import Foundation
import Observation

protocol CustomMenubarPresenting {
  func start()
  func stop()
  func apply(config: CustomMenubarConfig)
  func reconfigureForDisplayChanges()
}

enum CustomMenubarRuntimeError: Error, LocalizedError {
  case bridgeUnavailable
  case symbolNotFound(String)
  case windowBindFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "Could not open SkyLight framework handle."
    case .symbolNotFound(let symbol):
      return "SkyLight symbol not found: \(symbol)."
    case .windowBindFailed(let code):
      return "Failed to bind custom menubar window into SkyLight managed space (code: \(code))."
    }
  }
}

@MainActor
@Observable
final class CustomMenubarModel {
  static let defaultWorkspaceNames: [String] = WorkspaceConfig.defaultNames

  private(set) var customWidgetTexts: [String: String] = [:]
  private(set) var workspaceNames: [String] = defaultWorkspaceNames
  private(set) var focusedWorkspaceName: String = defaultWorkspaceNames.first ?? "1"
  private(set) var config: CustomMenubarConfig = .default

  private var customWidgetTimers: [String: Timer] = [:]
  private var customWidgetRefreshInFlight: Set<String> = []

  func start() {
    configureCustomWidgetTimers()
  }

  func stop() {
    invalidateCustomWidgetTimers()
    customWidgetTexts.removeAll()
  }

  func apply(config: CustomMenubarConfig) {
    self.config = config
    configureCustomWidgetTimers()
  }

  func hasWidget(named widgetName: String) -> Bool {
    config.widgets.contains(widgetName)
  }

  func isFocusedWorkspace(_ workspaceName: String) -> Bool {
    focusedWorkspaceName == workspaceName
  }

  func widgetNames(alignedTo alignment: CustomWidgetAlignment) -> [String] {
    config.widgets.filter { widgetName in
      config.customWidgets[widgetName]?.widgetAlignment == alignment
    }
  }

  func customWidgetText(named widgetName: String) -> String {
    customWidgetTexts[widgetName] ?? ""
  }

  func focusWorkspace(_ workspaceName: String) {
    guard workspaceNames.contains(workspaceName) else { return }
    focusedWorkspaceName = workspaceName
  }

  func updateWorkspaceState(
    names: [String],
    focusedWorkspaceName: String
  ) {
    workspaceNames = names.isEmpty ? Self.defaultWorkspaceNames : names
    self.focusedWorkspaceName = workspaceNames.contains(focusedWorkspaceName)
      ? focusedWorkspaceName
      : (workspaceNames.first ?? Self.defaultWorkspaceNames[0])
  }

  private func configureCustomWidgetTimers() {
    invalidateCustomWidgetTimers()

    let activeCustomWidgetNames = config.widgets.filter { config.customWidgets[$0] != nil }
    let activeCustomWidgetNameSet = Set(activeCustomWidgetNames)

    customWidgetTexts = customWidgetTexts.filter { activeCustomWidgetNameSet.contains($0.key) }

    for widgetName in activeCustomWidgetNames {
      guard let widgetConfig = config.customWidgets[widgetName] else {
        continue
      }

      refreshCustomWidget(named: widgetName, using: widgetConfig)

      let timer = Timer(timeInterval: widgetConfig.refreshInterval, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshCustomWidget(named: widgetName, using: widgetConfig)
        }
      }

      RunLoop.main.add(timer, forMode: .common)
      customWidgetTimers[widgetName] = timer
    }
  }

  private func invalidateCustomWidgetTimers() {
    for timer in customWidgetTimers.values {
      timer.invalidate()
    }

    customWidgetTimers.removeAll()
    customWidgetRefreshInFlight.removeAll()
  }

  private func refreshCustomWidget(
    named widgetName: String,
    using widgetConfig: CustomWidgetConfig
  ) {
    guard !customWidgetRefreshInFlight.contains(widgetName) else { return }

    customWidgetRefreshInFlight.insert(widgetName)

    let shellCommand = widgetConfig.shellCommand

    DispatchQueue.global(qos: .utility).async { [shellCommand] in
      let output = Self.runShellCommand(shellCommand)

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }

        self.customWidgetRefreshInFlight.remove(widgetName)

        guard
          self.hasWidget(named: widgetName),
          self.config.customWidgets[widgetName]?.shellCommand == shellCommand
        else {
          return
        }

        self.customWidgetTexts[widgetName] = output
      }
    }
  }

  private nonisolated static func runShellCommand(_ shellCommand: String) -> String {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-lc", shellCommand]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
      try process.run()
      process.waitUntilExit()

      let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

      let output = String(decoding: outputData, as: UTF8.self)
      let errorOutput = String(decoding: errorData, as: UTF8.self)

      if process.terminationStatus == 0 {
        return normalizedShellOutput(output)
      }

      let normalizedErrorOutput = normalizedShellOutput(errorOutput)
      return normalizedErrorOutput == "-" ? "Command failed (\(process.terminationStatus))" : normalizedErrorOutput
    } catch {
      return "Command failed"
    }
  }

  private nonisolated static func normalizedShellOutput(_ output: String) -> String {
    let singleLineOutput = output
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return singleLineOutput.isEmpty ? "-" : singleLineOutput
  }
}
