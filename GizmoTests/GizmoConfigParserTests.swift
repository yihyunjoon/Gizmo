import XCTest
@testable import Gizmo

final class GizmoConfigParserTests: XCTestCase {
  private let parser = GizmoConfigParser()

  func testParseCustomMenubarWithValidValues() throws {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      enabled = true
      border = false
      display_scope = "active"
      height = 32
      widgets = ["clock", "front_app"]
      background_opacity = 0.6
      horizontal_padding = 12
      clock_24h = false
      """
    )

    XCTAssertNotNil(result.config)
    XCTAssertTrue(result.errors.isEmpty)

    let config = try XCTUnwrap(result.config)
    XCTAssertTrue(config.customMenubar.enabled)
    XCTAssertFalse(config.customMenubar.border)
    XCTAssertEqual(config.customMenubar.displayScope, .active)
    XCTAssertEqual(config.customMenubar.height, 32)
    XCTAssertEqual(config.customMenubar.widgets, [.clock, .frontApp])
    XCTAssertEqual(config.customMenubar.backgroundOpacity, 0.6)
    XCTAssertEqual(config.customMenubar.horizontalPadding, 12)
    XCTAssertFalse(config.customMenubar.clock24h)
  }

  func testInvalidDisplayScopeReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      display_scope = "invalid"
      """
    )

    XCTAssertNil(result.config)
    XCTAssertTrue(result.errors.contains { $0.contains("custom_menubar.display_scope") })
  }

  func testInvalidWidgetsReturnsError() {
    let result = parser.parse(
      """
      config-version = 1

      [custom_menubar]
      widgets = ["clock", "nope"]
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
      inner.vertical = 6
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
    XCTAssertEqual(config.gaps.inner.vertical, 6)
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
}
