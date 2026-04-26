import 'package:flutter/widgets.dart';

/// Below this width the persistent sidebar is replaced by a hamburger-opened
/// `Drawer` (Material 3 "compact" device class).
const double kCompactWidth = 600;

/// Below this width the sidebar is rendered as an icon-and-label rail; at or
/// above it the user can choose between rail and the full extended sidebar.
const double kMediumWidth = 900;

/// Width of the extended sidebar (icons + full-width labels).
const double kExtendedSidebarWidth = 250;

/// Width of the icon-only navigation rail.
const double kRailWidth = 76;

/// Three layout modes the top-level navigation can take, picked from the
/// available width and the user's manual collapse preference.
enum NavMode {
  /// Hidden persistent nav; AppBar exposes a hamburger that opens a `Drawer`.
  drawer,

  /// Permanent narrow column with icons and short labels.
  rail,

  /// Permanent wider column with icons and full labels.
  extended,
}

/// Resolve the navigation mode for a given viewport width.
///
/// * `< kCompactWidth` → [NavMode.drawer]
/// * `< kMediumWidth`  → [NavMode.rail] (forced — extended would crowd content)
/// * `>= kMediumWidth` → [NavMode.extended] unless the user has collapsed it,
///   in which case [NavMode.rail] is used.
NavMode resolveNavMode(double width, {bool userCollapsed = false}) {
  if (width < kCompactWidth) return NavMode.drawer;
  if (width < kMediumWidth) return NavMode.rail;
  return userCollapsed ? NavMode.rail : NavMode.extended;
}

/// True when the viewport is at "compact" width — useful for hiding non-
/// essential trailing controls in list rows.
bool isCompactWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kCompactWidth;
