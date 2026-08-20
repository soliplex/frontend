import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../version.dart';
import '../../../core/layout.dart';
import '../../../core/routes.dart';
import '../../../core/ui/menu_row.dart';

/// Shared chrome for the unauthenticated onboarding surfaces (home /
/// connect flow, the OAuth callback, and the server list).
///
/// Renders a persistent branded top bar — logo, app name, library version,
/// and an about/versions affordance — above a centered, width-capped content
/// column. Individual surfaces supply only their [child] body; the framing
/// stays identical across the whole flow so it reads as one product.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.appName,
    required this.child,
    this.logo,
    this.maxContentWidth = formColumnMaxWidth,
  });

  final String appName;
  final Widget child;
  final Widget? logo;

  /// Max width of the centered content column so forms and cards don't
  /// stretch edge-to-edge on desktop/web.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            HomeShellHeader(appName: appName, logo: logo),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SoliplexSpacing.s6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The branded top bar shared across the onboarding surfaces (home / connect
/// flow, the OAuth callback, and the server list) and the versions screens:
/// logo, app name, library version, and trailing [actions] — followed by the
/// ⋮ menu of utility destinations so the bar reads the same everywhere.
class HomeShellHeader extends StatelessWidget {
  const HomeShellHeader({
    super.key,
    required this.appName,
    this.logo,
    this.leading,
    this.actions,
    this.showUtilityMenu = true,
  });

  final String appName;
  final Widget? logo;

  /// Optional leading widget shown before the logo — e.g. a back button on
  /// pushed sub-pages like the versions screens.
  final Widget? leading;

  /// Trailing actions shown before the ⋮ menu. Screens like the server list
  /// slot their navigation here.
  final List<Widget>? actions;

  /// Shows the ⋮ menu of utility destinations. On by default, and off for
  /// screens that bring their own trailing chrome — the destinations
  /// themselves, and the room info screen.
  final bool showUtilityMenu;

  static const _logoSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: SoliplexSpacing.s2),
          ],
          SizedBox(
            width: _logoSize,
            height: _logoSize,
            child: logo ??
                Icon(
                  Icons.dns_outlined,
                  size: _logoSize,
                  color: colors.primary,
                ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          // Expanded so the name/version group consumes the free space and
          // the trailing actions sit flush at the end. The app name is
          // Flexible within the group so it ellipsizes (rather than
          // overflowing) when the bar also carries a leading back button and
          // a trailing action on a narrow viewport.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    appName,
                    style: context.brandNameOn(theme.textTheme.titleSmall),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Text(
                  soliplexVersion,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...?actions,
          if (showUtilityMenu) const _UtilityMenu(),
        ],
      ),
    );
  }
}

/// Utility destinations reachable before a server is connected.
///
/// The same pair the room rail and lobby sidebar offer in their ⋮ menus, put
/// where a user who cannot sign in can reach them: the rail and the sidebar
/// both need a connected server, and a failed sign-in is exactly when the
/// diagnostics are worth reading.
enum _UtilityAction { diagnostics, versions }

class _UtilityMenu extends StatelessWidget {
  const _UtilityMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_UtilityAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Diagnostics & versions',
      onSelected: (action) {
        switch (action) {
          case _UtilityAction.diagnostics:
            context.push(AppRoutes.diagnostics);
          case _UtilityAction.versions:
            context.push(AppRoutes.versions);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _UtilityAction.diagnostics,
          child: MenuRow(icon: Icons.troubleshoot, label: 'Diagnostics'),
        ),
        PopupMenuItem(
          value: _UtilityAction.versions,
          child: MenuRow(icon: Icons.info_outline, label: 'Versions'),
        ),
      ],
    );
  }
}
