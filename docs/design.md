# Design

Gizmo should use design tokens for visual values instead of scattering raw literals across views.

This does not mean building a large design system upfront. Start small. When a view needs a color, font, spacing, radius, opacity, size, or animation value that represents a reusable visual decision, place it behind a named token and use that token from the view.

## Policy

Prefer named design tokens over hard-coded visual values.

For example, use a token such as `theme.customMenubar.workspaceButtonHeight` instead of writing `24` directly in the view, or `theme.sidebar.selectedBackground` instead of repeating a specific color in multiple places.

Small one-off layout values can stay local when they are purely structural and not part of the app's visual language. If the same value appears in multiple places, affects the app's visual identity, or is likely to be adjusted during design work, promote it to a token.

## Migration

Move values gradually. Do not rewrite unrelated screens just to introduce tokens.

When changing a UI file, look for nearby hard-coded visual values and move only the values that are part of the current work. Keep behavior and appearance unchanged unless the task explicitly asks for a visual change.

Good first candidates are:

- colors and opacity values
- font sizes and weights
- control heights and fixed dimensions
- corner radii
- recurring spacing values
- hover, selection, and transition animations

## Naming

Name tokens by intent, not by their current value.

Use names like `selectedBackground`, `secondaryText`, `workspaceButtonHeight`, or `panelSpacing`. Avoid names like `gray12`, `opacity24`, or `height24`, because those names become misleading as the design evolves.

Tokens should describe how the value is used. If two places currently share the same number but have different purposes, keep separate tokens.
