import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/crm/crm_format.dart';
import '../../providers/crm_provider.dart';
import '../../services/crm_api.dart';
import '../app_shell.dart';
import '../search_actions.dart';

export '../search_actions.dart'
    show
        SearchCard,
        SearchNotice,
        showSearchSnack,
        searchPrimaryButtonStyle,
        searchSecondaryButtonStyle,
        searchDangerTextButtonStyle,
        copyWithSnack;

/// The CRM API of the app (from [CrmProvider]), or a fresh client.
CrmApi crmApiOf(BuildContext context, [CrmApi? override]) =>
    override ?? context.read<CrmProvider?>()?.api ?? CrmApi();

/// Replaces the browser URL with [route] without navigating (filters in
/// the query string survive a refresh). No-op outside the web.
void crmReplaceUrl(String route) {
  if (!kIsWeb) return;
  try {
    SystemNavigator.routeInformationUpdated(
        uri: Uri.parse(route), replace: true);
  } catch (_) {}
}

/// Snack that replaces the one showing (results of quick actions must
/// not queue behind an older message).
void crmSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  showSearchSnack(context, message, error: error);
}

/// [crmSnack] on a messenger captured before an async action, for actions
/// whose triggering widget may be gone when they finish (e.g. a button that
/// is swapped for a progress indicator while the action runs).
void crmSnackOn(ScaffoldMessengerState? messenger, String message,
    {bool error = false}) {
  if (messenger == null || !messenger.mounted) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? const Color(0xFF8C2F2A) : const Color(0xFF2A2E33),
  ));
}

/// Whether animations should be skipped (reduced motion).
bool crmReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ------------------------------------------------------------------ frame

/// CRM sections (one strip under the top bar, not a second sidebar).
enum CrmTab { pipeline, leads, activities, contacts, reports }

extension CrmTabX on CrmTab {
  String get label {
    switch (this) {
      case CrmTab.pipeline:
        return 'Pipeline';
      case CrmTab.leads:
        return 'All leads';
      case CrmTab.activities:
        return 'Activities';
      case CrmTab.contacts:
        return 'Contacts';
      case CrmTab.reports:
        return 'Reports';
    }
  }

  String get route {
    switch (this) {
      case CrmTab.pipeline:
        return '/crm';
      case CrmTab.leads:
        return '/crm/leads';
      case CrmTab.activities:
        return '/crm/activities';
      case CrmTab.contacts:
        return '/crm/contacts';
      case CrmTab.reports:
        return '/crm/reports';
    }
  }
}

/// Tab strip of the CRM pages.
class CrmSubNav extends StatelessWidget {
  final CrmTab? current;

  const CrmSubNav({super.key, this.current});

  @override
  Widget build(BuildContext context) {
    final due = context.watch<CrmProvider?>()?.dueCount ?? 0;
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: UiTokens.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in CrmTab.values)
              _SubNavItem(
                label: t.label,
                badge: t == CrmTab.activities && due > 0 ? '$due due' : null,
                selected: t == current,
                onTap: () => AppNav.go(context, t.route),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _SubNavItem(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: selected ? UiTokens.accent : Colors.transparent,
                  width: 3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? UiTokens.text : UiTokens.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                CrmBadge(
                    label: badge!,
                    fg: UiTokens.partialFg,
                    bg: UiTokens.partialBg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Page body of a CRM screen: tab strip + content, and the "CRM is off"
/// state when the server says CRM is not enabled.
class CrmPageBody extends StatelessWidget {
  final CrmTab? tab;
  final Widget child;

  const CrmPageBody({super.key, this.tab, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<CrmProvider?>()?.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (enabled != false) CrmSubNav(current: tab),
        Expanded(child: enabled == false ? const CrmDisabledView() : child),
      ],
    );
  }
}

/// Horizontal padding of CRM page content.
EdgeInsets crmPagePadding(double width) =>
    EdgeInsets.symmetric(horizontal: width < 600 ? 16 : 24, vertical: 16);

/// Centered max-width column.
class CrmContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CrmContent({super.key, required this.child, this.maxWidth = 1200});

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

// ----------------------------------------------------------------- states

class CrmDisabledView extends StatelessWidget {
  const CrmDisabledView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        CrmContent(
          maxWidth: 640,
          child: SearchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("CRM isn't available on your account yet",
                    style: TextStyle(
                        color: UiTokens.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Your searches and leads are unaffected. CRM appears in the menu once it is turned on.',
                    style: TextStyle(
                        color: UiTokens.textSecondary,
                        fontSize: 14,
                        height: 1.4)),
                const SizedBox(height: 14),
                OutlinedButton(
                  style: searchSecondaryButtonStyle(),
                  onPressed: () => AppNav.go(context, '/searches'),
                  child: const Text('Go to My searches'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CrmLoading extends StatelessWidget {
  final String label;

  const CrmLoading({super.key, this.label = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: UiTokens.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Error card with the right words per failure and a way forward.
class CrmErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  /// "your pipeline", "this record", ...
  final String what;

  /// Shown for a 404 (e.g. a record of another workspace).
  final String? notFoundTitle;
  final String? notFoundBody;

  const CrmErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.what = 'this page',
    this.notFoundTitle,
    this.notFoundBody,
  });

  @override
  Widget build(BuildContext context) {
    final kind = crmErrorKind(error);
    String title;
    String? body;
    var retry = true;
    Widget? extra;
    switch (kind) {
      case CrmErrorKind.offline:
        title = "We couldn't reach the server";
        body = 'Check your connection and try again. Your CRM data is safe.';
        break;
      case CrmErrorKind.signedOut:
        title = "You've been signed out";
        body = 'Sign in again to see $what.';
        retry = false;
        extra = FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: () => AppNav.signIn(context),
          child: const Text('Sign in'),
        );
        break;
      case CrmErrorKind.disabled:
        return const CrmDisabledView();
      case CrmErrorKind.notFound:
        title = notFoundTitle ?? 'Not found';
        body = notFoundBody ??
            'It may have been removed, or the link is not for your account.';
        retry = false;
        extra = OutlinedButton(
          style: searchSecondaryButtonStyle(),
          onPressed: () => AppNav.go(context, '/crm'),
          child: const Text('Go to the pipeline'),
        );
        break;
      case CrmErrorKind.rateLimited:
        title = 'Too many requests';
        body = 'Please wait a minute and try again.';
        break;
      case CrmErrorKind.conflict:
      case CrmErrorKind.other:
        title = "We couldn't load $what";
        body = crmErrorText(error);
        break;
    }
    return Semantics(
      liveRegion: true,
      child: SearchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: UiTokens.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                style: const TextStyle(
                    color: UiTokens.textSecondary, fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (retry && onRetry != null)
                OutlinedButton(
                    style: searchSecondaryButtonStyle(),
                    onPressed: onRetry,
                    child: const Text('Try again')),
              if (extra != null) extra,
            ]),
          ],
        ),
      ),
    );
  }
}

/// Empty state card (no fake data).
class CrmEmptyView extends StatelessWidget {
  final String title;
  final String? body;
  final List<Widget> actions;
  final IconData icon;

  const CrmEmptyView({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return SearchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: UiTokens.accent, size: 28)),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  color: UiTokens.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                style: const TextStyle(
                    color: UiTokens.textSecondary, fontSize: 14, height: 1.4)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- pieces

/// Small pill: icon (optional) + text, never colour alone.
class CrmBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final String? tooltip;

  const CrmBadge({
    super.key,
    required this.label,
    this.icon,
    this.fg = UiTokens.textSecondary,
    this.bg = UiTokens.background,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, size: 14, color: fg)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 12, height: 1,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (tooltip != null) {
      pill = Tooltip(message: tooltip!, child: pill);
    }
    return pill;
  }
}

class CrmOutcomeBadge extends StatelessWidget {
  final Map<String, dynamic> record;

  const CrmOutcomeBadge({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final s = crmOutcomeStyle(record['outcome'],
        archived: record['archived'] == true ||
            crmStr(record['archived_at']).isNotEmpty);
    return CrmBadge(label: s.label, icon: s.icon, fg: s.fg, bg: s.bg);
  }
}

/// Due state of an activity: icon + words + local time.
class CrmDueBadge extends StatelessWidget {
  final Map<String, dynamic> activity;
  final bool showTime;

  const CrmDueBadge({super.key, required this.activity, this.showTime = true});

  @override
  Widget build(BuildContext context) {
    final kind = crmDueKind(activity);
    final s = crmDueStyle(kind);
    final due = crmWhen(kind == CrmDueKind.done
        ? (activity['completed_at'] ?? activity['due_at'])
        : activity['due_at']);
    final label = showTime && due != '—' ? '${s.label} · $due' : s.label;
    final parsed = DateTime.tryParse(crmStr(activity['due_at']));
    return CrmBadge(
      label: label,
      icon: s.icon,
      fg: s.fg,
      bg: s.bg,
      tooltip: parsed == null ? null : 'Due ${crmFullLocal(parsed)}',
    );
  }
}

/// Section header inside a card.
class CrmSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const CrmSectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title,
                  style: const TextStyle(
                      color: UiTokens.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Dropdown-like menu face used by the filter bars.
class CrmMenu<T> extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  const CrmMenu({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      color: UiTokens.card,
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<T>(
              value: v, checked: v == value, child: Text(labelOf(v))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: UiTokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: UiTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: UiTokens.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: UiTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                color: UiTokens.textSecondary),
          ],
        ),
      ),
    );
  }
}

InputDecoration crmInputDecoration(String label,
        {String? hint,
        String? helper,
        Widget? prefix,
        Widget? suffix,
        String? error}) =>
    InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: const TextStyle(color: UiTokens.textSecondary),
      hintText: hint,
      hintStyle: const TextStyle(color: UiTokens.textMuted),
      helperText: helper,
      helperMaxLines: 3,
      helperStyle: const TextStyle(color: UiTokens.textSecondary, fontSize: 12),
      errorText: error,
      errorMaxLines: 3,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: UiTokens.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: UiTokens.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: UiTokens.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: UiTokens.accent, width: 2)),
    );

/// Dark dialog with consistent buttons.
Future<T?> showCrmDialog<T>(BuildContext context,
        {required WidgetBuilder builder}) =>
    showDialog<T>(context: context, builder: builder);

/// Simple confirm dialog.
Future<bool> crmConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(title, style: const TextStyle(color: UiTokens.text)),
      content: Text(body,
          style: const TextStyle(color: UiTokens.textSecondary, height: 1.4)),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
              foregroundColor: UiTokens.accent,
              minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: UiTokens.failedFg,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(48, 48))
              : searchPrimaryButtonStyle(),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Readable message of a failed CRM action ("Moving X didn't work: detail").
String crmActionError(String what, Object error) {
  switch (crmErrorKind(error)) {
    case CrmErrorKind.offline:
      return "$what didn't work: we couldn't reach the server. Check your connection and try again.";
    case CrmErrorKind.signedOut:
      return "You've been signed out. Sign in again, then try again.";
    case CrmErrorKind.conflict:
      return 'This record was changed in another tab or by another action. We reloaded the latest version; please check it and try again.';
    case CrmErrorKind.disabled:
      return "CRM isn't available on your account.";
    default:
      return "$what didn't work: ${crmErrorText(error)}";
  }
}
