import AppKit
import SwiftData

@MainActor
struct AppBootstrap {
  let configStore: ConfigStore
  let hotKeyService: GlobalHotKeyService
  let accessibilityPermissionService: AccessibilityPermissionService
  let windowManagerService: WindowManagerService
  let virtualWorkspaceService: VirtualWorkspaceService
  let launcherPanelService: LauncherPanelService
  let customMenubarRuntimeService: CustomMenubarRuntimeService
  let sharedModelContainer: ModelContainer

  init() {
    let configStore = ConfigStore()
    configStore.bootstrapAndLoad()

    let hotKeyService = GlobalHotKeyService()
    let accessibilityPermissionService = AccessibilityPermissionService()
    let windowManagerService = WindowManagerService(
      permissionService: accessibilityPermissionService,
      customMenubarConfigProvider: { configStore.active.customMenubar },
      gapsConfigProvider: { configStore.active.gaps }
    )
    let virtualWorkspaceService = VirtualWorkspaceService(
      permissionService: accessibilityPermissionService,
      initialConfig: configStore.active.workspace
    )
    let launcherPanelService = LauncherPanelService(
      windowManagerService: windowManagerService,
      virtualWorkspaceService: virtualWorkspaceService,
      accessibilityPermissionService: accessibilityPermissionService,
      configStore: configStore
    )
    let customMenubarRuntimeService = CustomMenubarRuntimeService()

    virtualWorkspaceService.onStateDidChange = {
      [weak customMenubarRuntimeService, weak launcherPanelService] state in
      customMenubarRuntimeService?.updateWorkspaceState(
        names: state.workspaceNames,
        focusedWorkspaceName: state.activeWorkspaceName
      )
      launcherPanelService?.updateWorkspaceCommands(workspaceNames: state.workspaceNames)
    }
    customMenubarRuntimeService.setWorkspaceSelectionHandler {
      [weak virtualWorkspaceService] workspaceName in
      _ = virtualWorkspaceService?.focusWorkspace(workspaceName)
    }

    hotKeyService.onHotKeyPressed = {
      Task { @MainActor in
        launcherPanelService.togglePanel()
      }
    }
    hotKeyService.configure(
      shortcut: configStore.active.launcher.globalHotkey.keyboardShortcut
    )
    configStore.onConfigDidLoad = { config in
      hotKeyService.configure(
        shortcut: config.launcher.globalHotkey.keyboardShortcut
      )
      customMenubarRuntimeService.apply(config: config.customMenubar)
      virtualWorkspaceService.apply(config: config.workspace)
    }
    customMenubarRuntimeService.apply(config: configStore.active.customMenubar)
    customMenubarRuntimeService.updateWorkspaceState(
      names: virtualWorkspaceService.state.workspaceNames,
      focusedWorkspaceName: virtualWorkspaceService.state.activeWorkspaceName
    )
    launcherPanelService.updateWorkspaceCommands(
      workspaceNames: virtualWorkspaceService.state.workspaceNames
    )

    self.configStore = configStore
    self.hotKeyService = hotKeyService
    self.accessibilityPermissionService = accessibilityPermissionService
    self.windowManagerService = windowManagerService
    self.virtualWorkspaceService = virtualWorkspaceService
    self.launcherPanelService = launcherPanelService
    self.customMenubarRuntimeService = customMenubarRuntimeService
    self.sharedModelContainer = Self.makeSharedModelContainer()
  }

  private static func makeSharedModelContainer() -> ModelContainer {
    let schema = Schema([KeyPressRecord.self])
    let modelConfiguration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false
    )

    do {
      return try ModelContainer(
        for: schema,
        configurations: [modelConfiguration]
      )
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }
}
