import Foundation

struct ConfigPathResolver {
  private let fileManager: FileManager
  private let environment: [String: String]

  init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.fileManager = fileManager
    self.environment = environment
  }

  func resolveConfigURL() -> URL {
    let baseDirectoryURL: URL

    if
      let xdgConfigHome = environment["XDG_CONFIG_HOME"],
      !xdgConfigHome.isEmpty
    {
      let xdgURL = URL(filePath: xdgConfigHome)
      if xdgURL.path.hasPrefix("/") {
        baseDirectoryURL = xdgURL
      } else {
        baseDirectoryURL = fileManager.homeDirectoryForCurrentUser
          .appending(path: ".config", directoryHint: .isDirectory)
      }
    } else {
      baseDirectoryURL = fileManager.homeDirectoryForCurrentUser
        .appending(path: ".config", directoryHint: .isDirectory)
    }

    return baseDirectoryURL
      .appending(path: "gizmo", directoryHint: .isDirectory)
      .appending(path: "config.toml", directoryHint: .notDirectory)
  }

  func resolveWorkspaceMappingURL() -> URL {
    resolveConfigURL()
      .deletingLastPathComponent()
      .appending(path: "workspace-mapping.json", directoryHint: .notDirectory)
  }

  func ensureConfigFileExists(at configURL: URL) throws {
    let directoryURL = configURL.deletingLastPathComponent()

    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    guard !fileManager.fileExists(atPath: configURL.path()) else {
      return
    }

    let defaultConfigData =
      (Bundle.main.url(forResource: "default-config", withExtension: "toml"))
      .flatMap { try? Data(contentsOf: $0) }
      ?? Data(Self.fallbackDefaultConfig.utf8)

    try defaultConfigData.write(to: configURL, options: .atomic)
  }

  private static let fallbackDefaultConfig = """
    config-version = 1

    [launcher]
    display = "active_window"
    force_english_input_source = false

    [launcher.global_hotkey]
    key = "space"
    modifiers = ["command"]

    [custom_menubar]
    enabled = false
    border = true
    display_scope = "all"
    position = "bottom"
    height = 30
    widgets = ["front_app", "clock"]
    background_opacity = 0.75
    horizontal_padding = 8
    clock_24h = true

    [workspace]
    enabled = true
    mode = "primary_only"
    hide_strategy = "corner_offscreen"

    [workspace.display_sets.primary]
    names = ["q", "w", "e", "r", "t"]

    [workspace.display_sets.secondary]
    names = ["3", "4"]

    [gaps]
    inner.horizontal = 4
    inner.vertical = 4
    outer.left = 4
    outer.top = 4
    outer.right = 4
    outer.bottom = 4

    [keystats]
    auto_start_monitoring = true
    """
}
