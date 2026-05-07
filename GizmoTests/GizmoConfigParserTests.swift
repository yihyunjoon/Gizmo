import XCTest
@testable import Gizmo

final class GizmoConfigParserTests: XCTestCase {
  private let parser = GizmoConfigParser()

  func testParseCustomMenubarWithValidValues() throws {
    let result = parser.parse(
      """
      config-version = 1

      [custom_widgets.battery]
      shell_command = "echo battery"
      refresh_interval = 10
      widget_alignment = "center"

      [custom_menubar]
      enabled = true
      border = false
      height = 32
      widgets = ["battery"]
      background_opacity = 0.6
      horizontal_padding = 12
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try XCTUnwrap(result.config)
    XCTAssertTrue(config.customMenubar.enabled)
    XCTAssertFalse(config.customMenubar.border)
    XCTAssertEqual(config.customMenubar.height, 32)
    XCTAssertEqual(config.customMenubar.widgets, ["battery"])
    XCTAssertEqual(config.customMenubar.backgroundOpacity, 0.6)
    XCTAssertEqual(config.customMenubar.horizontalPadding, 12)
    XCTAssertEqual(
      config.customMenubar.customWidgets["battery"],
      CustomWidgetConfig(
        shellCommand: "echo battery",
        refreshInterval: 10,
        widgetAlignment: .center
      )
    )
  }

  func testUnknownCustomWidgetReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      widgets = ["nope"]
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.widgets") })
  }

  func testFormerBuiltInWidgetNamesRequireCustomDefinitions() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      widgets = ["clock", "front_app"]
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.widgets") })
  }

  func testInvalidBorderTypeReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      border = "nope"
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.border") })
  }

  func testOutOfRangeOpacityReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      background_opacity = 1.4
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.background_opacity") })
  }

  func testUnknownCustomMenubarKeyReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      mystery = true
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.mystery") })
  }

  func testCustomMenubarDefaultsWhenSectionMissing() {
    let result = parser.parse(
      """
      config-version = 1
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try? XCTUnwrap(result.config)
    XCTAssertEqual(config?.customMenubar, .default)
  }

  func testParseGapsWithValidValues() throws {
    let result = parser.parse(
      """
      config-version = 1

      [gaps]
      inner.horizontal = 4
      outer.left = 10
      outer.top = 11
      outer.right = 12
      outer.bottom = 40
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try XCTUnwrap(result.config)
    XCTAssertEqual(config.gaps.inner.horizontal, 4)
    XCTAssertEqual(config.gaps.outer.left, 10)
    XCTAssertEqual(config.gaps.outer.top, 11)
    XCTAssertEqual(config.gaps.outer.right, 12)
    XCTAssertEqual(config.gaps.outer.bottom, 40)
  }

  func testNegativeGapsReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [gaps]
      outer.bottom = -1
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("gaps.outer.bottom") })
  }

  func testUnknownGapsInnerKeyReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [gaps.inner]
      diagonal = 4
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("gaps.inner.diagonal") })
  }

  func testUnknownRootKeyReturnsError() {
    let result = parser.parse(
      """
      config-version = 1
      mystery = true
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("mystery") })
  }

  func testGapsDefaultsWhenSectionMissing() {
    let result = parser.parse(
      """
      config-version = 1
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try? XCTUnwrap(result.config)
    XCTAssertEqual(config?.gaps, .default)
  }

  func testParseWorkspaceNames() throws {
    let result = parser.parse(
      """
      config-version = 1

      [workspace]
      enabled = true
      names = ["q", "w", "e"]
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try XCTUnwrap(result.config)
    XCTAssertEqual(config.workspace.primaryNames, ["q", "w", "e"])
  }

  func testLegacyWorkspaceNamesPopulatePrimaryDisplaySet() throws {
    let result = parser.parse(
      """
      config-version = 1

      [workspace]
      names = ["1", "2"]
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try XCTUnwrap(result.config)
    XCTAssertEqual(config.workspace.primaryNames, ["1", "2"])
  }

  func testLegacyWorkspaceDisplaySetsReturnError() {
    let result = parser.parse(
      """
      config-version = 1

      [workspace.display_sets.primary]
      names = ["q", "w"]

      [workspace.display_sets.secondary]
      names = ["w", "4"]
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("workspace.display_sets") })
  }

}
