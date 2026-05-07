import AppKit
import SwiftData

@MainActor
struct AppBootstrap {
  let configStore: ConfigStore
  let hotKeyService: GlobalHotKeyService
  let accessibilityPermissionService: AccessibilityPermissionService
  let windowManagerService: WindowManagerService
  let workspaceService: WorkspaceService
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
      gapsConfigProvider: { configStore.active.gaps },
      fallbackWindowElementProvider: {
        workspaceFocusObserverService.preferredWindowElement()
      }
    )
    let workspaceService = WorkspaceService(
      permissionService: accessibilityPermissionService,
      initialConfig: configStore.active.workspace,
      fallbackWindowElementProvider: {
        workspaceFocusObserverService.preferredWindowElement()
      }
    )
    let launcherAppCatalogService = LauncherAppCatalogService()
    let commandShortcutService = CommandShortcutService(
      windowManagerService: windowManagerService,
      workspaceService: workspaceService,
      initialWorkspaceNames: workspaceService.state.workspaceNames,
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

    workspaceService.onStateDidChange = {
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
      [weak workspaceService] workspaceName in
      _ = workspaceService?.focusWorkspace(workspaceName)
    }
    workspaceFocusObserverService.onFocusedWindowChanged = {
      [weak workspaceService] in
      workspaceService?.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    }
    workspaceFocusObserverService.onActiveApplicationChanged = {
      [weak workspaceService] processIdentifier in
      workspaceService?.synchronizeActiveWorkspaceToApplicationIfNeeded(
        processIdentifier: processIdentifier
      )
    }
    workspaceFocusObserverService.onObservedWindowDestroyed = {
      [weak workspaceService] in
      workspaceService?.handleObservedWindowDestroyed()
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
      workspaceService.apply(config: config.workspace)
    }
    customMenubarRuntimeService.apply(config: configStore.active.customMenubar)
    customMenubarRuntimeService.updateWorkspaceState(workspaceService.state)
    launcherPanelService.refreshCommandList()
    launcherPanelService.preloadPanel()
    InputSourceService.preloadEnglishInputSource()
    launcherAppCatalogService.refreshInBackground()

    self.configStore = configStore
    self.hotKeyService = hotKeyService
    self.accessibilityPermissionService = accessibilityPermissionService
    self.windowManagerService = windowManagerService
    self.workspaceService = workspaceService
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
