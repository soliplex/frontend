import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../version.dart';
import '../../../core/routes.dart';

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
    this.maxContentWidth = 400,
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
            _HomeShellHeader(appName: appName, logo: logo),
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

class _HomeShellHeader extends StatelessWidget {
  const _HomeShellHeader({required this.appName, this.logo});

  final String appName;
  final Widget? logo;

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
          Text(appName, style: theme.textTheme.titleSmall),
          const SizedBox(width: SoliplexSpacing.s2),
          Text(
            soliplexVersion,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'About & versions',
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push(AppRoutes.versions),
          ),
        ],
      ),
    );
  }
}
