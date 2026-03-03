import AppKit
import SwiftData

@MainActor
struct AppBootstrap {
  let configStore: ConfigStore
  let hotKeyService: GlobalHotKeyService
  let accessibilityPermissionService: AccessibilityPermissionService
  let windowManagerService: WindowManagerService
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
    let launcherPanelService = LauncherPanelService(
      windowManagerService: windowManagerService,
      accessibilityPermissionService: accessibilityPermissionService,
      configStore: configStore
    )
    let customMenubarRuntimeService = CustomMenubarRuntimeService()
    customMenubarRuntimeService.setReloadConfigHandler {
      _ = configStore.reload()
    }
    customMenubarRuntimeService.setQuitHandler {
      NSApplication.shared.terminate(nil)
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
    }
    customMenubarRuntimeService.apply(config: configStore.active.customMenubar)

    self.configStore = configStore
    self.hotKeyService = hotKeyService
    self.accessibilityPermissionService = accessibilityPermissionService
    self.windowManagerService = windowManagerService
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
