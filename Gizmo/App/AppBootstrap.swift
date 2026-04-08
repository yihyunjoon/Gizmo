import AppKit
import SwiftData

@MainActor
struct AppBootstrap {
  let configStore: ConfigStore
  let hotKeyService: GlobalHotKeyService
  let accessibilityPermissionService: AccessibilityPermissionService
  let windowManagerService: WindowManagerService
  let virtualWorkspaceService: VirtualWorkspaceService
  let workspaceFocusObserverService: WorkspaceFocusObserverService
  let launcherAppCatalogService: LauncherAppCatalogService
  let commandShortcutService: CommandShortcutService
  let launcherPanelService: LauncherPanelService
  let customMenubarRuntimeService: CustomMenubarRuntimeService
  let clipboardHistoryService: ClipboardHistoryService
  let launchAtLoginService: LaunchAtLoginService
  let sharedModelContainer: ModelContainer

  init() {
    let configStore = ConfigStore()
    configStore.bootstrapAndLoad()

    let hotKeyService = GlobalHotKeyService()
    let accessibilityPermissionService = AccessibilityPermissionService()
    let workspaceFocusObserverService = WorkspaceFocusObserverService(
      permissionService: accessibilityPermissionService
    )
    let windowManagerService = WindowManagerService(
      permissionService: accessibilityPermissionService,
      customMenubarConfigProvider: { configStore.active.customMenubar },
      workspaceConfigProvider: { configStore.active.workspace },
      gapsConfigProvider: { configStore.active.gaps },
      fallbackWindowElementProvider: {
        workspaceFocusObserverService.preferredWindowElement()
      }
    )
    let virtualWorkspaceService = VirtualWorkspaceService(
      permissionService: accessibilityPermissionService,
      initialConfig: configStore.active.workspace,
      fallbackWindowElementProvider: {
        workspaceFocusObserverService.preferredWindowElement()
      }
    )
    let launcherAppCatalogService = LauncherAppCatalogService()
    let commandShortcutService = CommandShortcutService(
      windowManagerService: windowManagerService,
      virtualWorkspaceService: virtualWorkspaceService,
      initialWorkspaceNames: virtualWorkspaceService.state.workspaceNames,
      initialApplicationTargets: launcherAppCatalogService.applications
    )
    let launcherPanelService = LauncherPanelService(
      commandShortcutService: commandShortcutService,
      accessibilityPermissionService: accessibilityPermissionService,
      configStore: configStore
    )
    let customMenubarRuntimeService = CustomMenubarRuntimeService()
    let clipboardHistoryService = ClipboardHistoryService()
    let launchAtLoginService = LaunchAtLoginService()

    virtualWorkspaceService.onStateDidChange = {
      [weak customMenubarRuntimeService, weak launcherPanelService, weak commandShortcutService] state in
      customMenubarRuntimeService?.updateWorkspaceState(state)
      commandShortcutService?.updateWorkspaceCommands(workspaceNames: state.workspaceNames)
      launcherPanelService?.refreshCommandList()
    }
    launcherAppCatalogService.onApplicationsDidChange = {
      [weak commandShortcutService, weak launcherPanelService] applications in
      commandShortcutService?.updateApplicationCommands(applications)
      launcherPanelService?.refreshCommandList()
    }
    launcherPanelService.onPanelDidOpen = { [weak launcherAppCatalogService] in
      launcherAppCatalogService?.refreshInBackground()
    }
    customMenubarRuntimeService.setWorkspaceSelectionHandler {
      [weak virtualWorkspaceService] workspaceName in
      _ = virtualWorkspaceService?.focusWorkspace(workspaceName)
    }
    workspaceFocusObserverService.onFocusedWindowChanged = {
      [weak virtualWorkspaceService] in
      virtualWorkspaceService?.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    }
    workspaceFocusObserverService.onObservedWindowDestroyed = {
      [weak virtualWorkspaceService] in
      virtualWorkspaceService?.handleObservedWindowDestroyed()
    }
    workspaceFocusObserverService.start()

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
    customMenubarRuntimeService.updateWorkspaceState(virtualWorkspaceService.state)
    launcherPanelService.refreshCommandList()
    launcherPanelService.preloadPanel()
    launcherAppCatalogService.refreshInBackground()

    self.configStore = configStore
    self.hotKeyService = hotKeyService
    self.accessibilityPermissionService = accessibilityPermissionService
    self.windowManagerService = windowManagerService
    self.virtualWorkspaceService = virtualWorkspaceService
    self.workspaceFocusObserverService = workspaceFocusObserverService
    self.launcherAppCatalogService = launcherAppCatalogService
    self.commandShortcutService = commandShortcutService
    self.launcherPanelService = launcherPanelService
    self.customMenubarRuntimeService = customMenubarRuntimeService
    self.clipboardHistoryService = clipboardHistoryService
    self.launchAtLoginService = launchAtLoginService
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
