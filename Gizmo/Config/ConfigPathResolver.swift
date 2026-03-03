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
    modifiers = ["command", "shift"]

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

    [gaps]
    inner.horizontal = 0
    inner.vertical = 0
    outer.left = 0
    outer.top = 0
    outer.right = 0
    outer.bottom = 0

    [keystats]
    auto_start_monitoring = true
    """
}
