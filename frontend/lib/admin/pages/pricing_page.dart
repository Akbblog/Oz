import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

enum _Tab { packages, plans, tiers }

/// Pricing: one-off credit packages, subscription plans and volume tiers.
class AdminPricingPage extends StatefulWidget {
  const AdminPricingPage({super.key});

  @override
  State<AdminPricingPage> createState() => _AdminPricingPageState();
}

class _AdminPricingPageState extends State<AdminPricingPage> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  bool _loaded = false;
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _tiers = [];
  _Tab _tab = _Tab.packages;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<Map<String, dynamic>> _rows(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
  static int _id(Map<String, dynamic> r) => _n(r['id']).toInt();
  static bool _active(Map<String, dynamic> r) =>
      r['is_active'] == true || r['is_active'] == 1;

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getAdminCreditPackages(),
        _api.getAdminSubscriptionPlans(),
        _api.getPricingTiers(),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _packages = _rows((results[0] as Map)['packages']);
        _plans = _rows((results[1] as Map)['plans']);
        _tiers = _rows(results[2]);
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  /// Cents per credit, or null when it cannot be computed.
  static double? _perCredit(Object? priceCents, Object? credits) {
    final c = _n(credits);
    final p = _n(priceCents);
    if (c <= 0 || p <= 0) return null;
    return p / c;
  }

  static String _fmtPerCredit(double? v) =>
      v == null ? '–' : '${v.toStringAsFixed(3)}¢';

  static String _fmtNum(Object? v) {
    final n = _n(v);
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
  }

  Set<String> _duplicateNames(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final dup = <String>{};
    for (final r in rows) {
      final k = '${r['name'] ?? ''}'.trim().toLowerCase();
      if (k.isEmpty) continue;
      if (!seen.add(k)) dup.add(k);
    }
    return dup;
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      section: AdminSection.pricing,
      title: 'Pricing',
      subtitle: 'Credit packages, subscription plans and volume tiers',
      actions: [
        AIconButton(Icons.refresh, 'Refresh', onPressed: _loading ? null : _load),
      ],
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading && !_loaded) return const ALoading(height: 320);
    if (!_loaded) {
      return AErrorBox(
          'Pricing could not be loaded: ${_error ?? 'unknown error'}',
          onRetry: _load);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AErrorBox('Showing the last loaded data. Refresh failed: $_error',
              onRetry: _load),
          const SizedBox(height: 12),
        ],
        _kpis(),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: ASegmented<_Tab>(
            options: const {
              _Tab.packages: 'Credit packages',
              _Tab.plans: 'Subscription plans',
              _Tab.tiers: 'Pricing tiers',
            },
            counts: {
              _Tab.packages: _packages.length,
              _Tab.plans: _plans.length,
              _Tab.tiers: _tiers.length,
            },
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          _Tab.packages => _packagesPanel(),
          _Tab.plans => _plansPanel(),
          _Tab.tiers => _tiersPanel(),
        },
      ],
    );
  }

  Widget _kpis() {
    final activePkgs = _packages.where(_active).toList();
    Map<String, dynamic>? best;
    double? bestPpc;
    for (final p in activePkgs) {
      final v = _perCredit(p['display_price_cents'], p['credits']);
      if (v != null && (bestPpc == null || v < bestPpc)) {
        bestPpc = v;
        best = p;
      }
    }
    return AGrid(
      minTileWidth: 190,
      children: [
        AKpi(
          label: 'Active packages',
          value: '${activePkgs.length}',
          icon: Icons.sell_outlined,
          color: AC.green,
          hint: '${_packages.length} in total, ${_packages.length - activePkgs.length} hidden',
        ),
        AKpi(
          label: 'Cheapest price per credit',
          value: _fmtPerCredit(bestPpc),
          icon: Icons.south_east,
          color: AC.accent,
          hint: 'US cents per credit, active packages',
        ),
        AKpi(
          label: 'Best-value package',
          value: best == null ? '–' : '${best['name'] ?? '–'}',
          icon: Icons.workspace_premium_outlined,
          color: AC.amber,
          hint: best == null
              ? 'No active package with a price'
              : '${fmtInt(best['credits'])} credits for ${fmtMoney(best['display_price_cents'])}',
        ),
        AKpi(
          label: 'Active plans',
          value: '${_plans.where(_active).length}',
          icon: Icons.subscriptions_outlined,
          color: AC.blue,
          hint: '${_plans.length} subscription plans in total',
        ),
        AKpi(
          label: 'Pricing tiers',
          value: '${_tiers.length}',
          icon: Icons.stacked_line_chart,
          color: AC.purple,
          hint: '${_tiers.where(_active).length} active',
        ),
      ],
    );
  }

  Widget _nameCell(Map<String, dynamic> r, Set<String> dups) {
    final name = '${r['name'] ?? ''}'.trim();
    final dup = dups.contains(name.toLowerCase());
    return Row(
      children: [
        Flexible(
          child: Text(name.isEmpty ? '(no name)' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AT.body.copyWith(fontWeight: FontWeight.w600)),
        ),
        if (dup) ...[
          const SizedBox(width: 8),
          const Tooltip(
            message:
                'Another entry has the same name. Customers cannot tell them apart.',
            child: APill('Duplicate name', AC.amber),
          ),
        ],
      ],
    );
  }

  Widget _statusCell(Map<String, dynamic> r) => _active(r)
      ? const APill('Active', AC.green, dot: true)
      : const APill('Hidden', AC.grey, dot: true);

  Widget _actions({required VoidCallback onEdit, VoidCallback? onDelete}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AIconButton(Icons.edit_outlined, 'Edit', onPressed: onEdit),
        if (onDelete != null)
          AIconButton(Icons.delete_outline, 'Delete',
              color: AC.red, onPressed: onDelete),
      ],
    );
  }

  Widget _addButton(String label, VoidCallback onTap) => AButton(label,
      icon: Icons.add, kind: AButtonKind.primary, onPressed: onTap);

  // ---------------------------------------------------------------- packages

  Widget _packagesPanel() {
    final dups = _duplicateNames(_packages);
    return APanel(
      title: 'Credit packages',
      subtitle: 'One-off purchases shown to users on the pricing page',
      trailing: _addButton('Add package', () => _editPackage()),
      padding: const EdgeInsets.only(top: 12),
      child: ATable<Map<String, dynamic>>(
        minWidth: 760,
        rows: _packages,
        onRowTap: (r) => _editPackage(existing: r),
        empty: AEmpty(
          icon: Icons.sell_outlined,
          title: 'No credit packages yet',
          message: 'Add a package so users can buy credits.',
          action: _addButton('Add package', () => _editPackage()),
        ),
        columns: [
          ACol('Name', flex: 3, (r) => _nameCell(r, dups)),
          ACol('Credits', width: 110, numeric: true,
              (r) => Text(fmtInt(r['credits']))),
          ACol('Price', width: 120, numeric: true,
              (r) => Text(fmtMoney(r['display_price_cents']))),
          ACol('Per credit', width: 120, numeric: true, (r) => Text(
              _fmtPerCredit(_perCredit(r['display_price_cents'], r['credits'])))),
          ACol('Status', width: 110, _statusCell),
          ACol('', width: 96, (r) => _actions(
                onEdit: () => _editPackage(existing: r),
                onDelete: () => _delete(
                  kind: 'package',
                  row: r,
                  call: _api.deleteCreditPackage,
                  list: _packages,
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _editPackage({Map<String, dynamic>? existing}) async {
    final saved = await _showForm(
      title: existing == null ? 'Add credit package' : 'Edit credit package',
      subtitle: 'Prices are entered in US cents (2500 = \$25.00).',
      fields: [
        _F.text('name', 'Name', initial: existing?['name']),
        _F.integer('credits', 'Credits', initial: existing?['credits']),
        _F.integer('price', 'Display price (cents)',
            initial: existing?['display_price_cents'], money: true),
        _F.toggle('active', 'Active',
            help: 'Hidden packages are not offered to users.',
            initial: existing == null || _active(existing)),
      ],
      preview: (v) {
        final ppc = _perCredit(v['price'], v['credits']);
        return ppc == null ? null : 'Price per credit: ${_fmtPerCredit(ppc)}';
      },
      onSave: (v) async {
        final name = v['name'] as String;
        final credits = v['credits'] as int;
        final price = v['price'] as int;
        final active = v['active'] as bool;
        if (existing == null) {
          await _api.createCreditPackage(
            name: name,
            credits: credits,
            basePriceCents: price,
            displayPriceCents: price,
            isActive: active,
          );
        } else {
          await _api.updateCreditPackage(
            _id(existing),
            name: name,
            credits: credits,
            basePriceCents: price,
            displayPriceCents: price,
            isActive: active,
          );
        }
      },
    );
    _afterSave(saved, existing == null ? 'Package created' : 'Package updated');
  }

  // ------------------------------------------------------------------- plans

  Widget _plansPanel() {
    final dups = _duplicateNames(_plans);
    return APanel(
      title: 'Subscription plans',
      subtitle: 'Recurring credits, billed monthly or yearly',
      trailing: _addButton('Add plan', () => _editPlan()),
      padding: const EdgeInsets.only(top: 12),
      child: ATable<Map<String, dynamic>>(
        minWidth: 860,
        rows: _plans,
        onRowTap: (r) => _editPlan(existing: r),
        empty: AEmpty(
          icon: Icons.subscriptions_outlined,
          title: 'No plans yet',
          message: 'Create a subscription plan to offer recurring credits.',
          action: _addButton('Add plan', () => _editPlan()),
        ),
        columns: [
          ACol('Name', flex: 3, (r) => _nameCell(r, dups)),
          ACol('Billing', width: 100, (r) {
            final i = '${r['billing_interval'] ?? 'monthly'}';
            return Text(i.isEmpty ? '–' : '${i[0].toUpperCase()}${i.substring(1)}');
          }),
          ACol('Credits / period', width: 140, numeric: true,
              (r) => Text(fmtInt(r['credits_per_period']))),
          ACol('Price', width: 110, numeric: true,
              (r) => Text(fmtMoney(r['base_price_cents']))),
          ACol('Per credit', width: 110, numeric: true, (r) => Text(_fmtPerCredit(
              _perCredit(r['base_price_cents'], r['credits_per_period'])))),
          ACol('Stripe price', flex: 2, (r) {
            final s = '${r['stripe_price_id'] ?? ''}'.trim();
            return Text(s.isEmpty ? '–' : s, style: AT.mono);
          }),
          ACol('Status', width: 110, _statusCell),
          ACol('', width: 96, (r) => _actions(
                onEdit: () => _editPlan(existing: r),
                onDelete: () => _delete(
                  kind: 'plan',
                  row: r,
                  call: _api.deleteSubscriptionPlan,
                  list: _plans,
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _editPlan({Map<String, dynamic>? existing}) async {
    final saved = await _showForm(
      title: existing == null ? 'Add subscription plan' : 'Edit subscription plan',
      subtitle: 'Prices are entered in US cents (2500 = \$25.00).',
      fields: [
        _F.text('name', 'Name', initial: existing?['name']),
        _F.choice('interval', 'Billing interval',
            options: const {'monthly': 'Monthly', 'yearly': 'Yearly'},
            initial: '${existing?['billing_interval'] ?? 'monthly'}'),
        _F.integer('credits', 'Credits per period',
            initial: existing?['credits_per_period']),
        _F.integer('price', 'Price (cents)',
            initial: existing?['base_price_cents'], money: true),
        _F.text('stripe', 'Stripe price ID (optional)',
            initial: existing?['stripe_price_id'], required: false),
        _F.toggle('active', 'Active',
            help: 'Hidden plans cannot be subscribed to.',
            initial: existing == null || _active(existing)),
      ],
      preview: (v) {
        final ppc = _perCredit(v['price'], v['credits']);
        return ppc == null ? null : 'Price per credit: ${_fmtPerCredit(ppc)}';
      },
      onSave: (v) async {
        final stripe = (v['stripe'] as String).isEmpty ? null : v['stripe'] as String;
        if (existing == null) {
          await _api.createSubscriptionPlan(
            name: v['name'] as String,
            billingInterval: v['interval'] as String,
            creditsPerPeriod: v['credits'] as int,
            basePriceCents: v['price'] as int,
            stripePriceId: stripe,
            isActive: v['active'] as bool,
          );
        } else {
          await _api.updateSubscriptionPlan(
            _id(existing),
            name: v['name'] as String,
            billingInterval: v['interval'] as String,
            creditsPerPeriod: v['credits'] as int,
            basePriceCents: v['price'] as int,
            stripePriceId: stripe,
            isActive: v['active'] as bool,
          );
        }
      },
    );
    _afterSave(saved, existing == null ? 'Plan created' : 'Plan updated');
  }

  // ------------------------------------------------------------------- tiers

  Widget _tiersPanel() {
    final dups = _duplicateNames(_tiers);
    return APanel(
      title: 'Pricing tiers',
      subtitle: 'Price per credit by monthly volume, for subscription pricing',
      trailing: _addButton('Add tier', () => _editTier()),
      padding: const EdgeInsets.only(top: 12),
      child: ATable<Map<String, dynamic>>(
        minWidth: 720,
        rows: _tiers,
        onRowTap: (r) => _editTier(existing: r),
        empty: AEmpty(
          icon: Icons.stacked_line_chart,
          title: 'No tiers yet',
          message: 'Create pricing tiers for subscription credit pricing.',
          action: _addButton('Add tier', () => _editTier()),
        ),
        columns: [
          ACol('Name', flex: 3, (r) => _nameCell(r, dups)),
          ACol('Monthly credits', flex: 2, (r) {
            final max = r['max_monthly_credits'];
            return Text(
                '${fmtInt(r['min_monthly_credits'] ?? 0)} – ${max == null ? 'unlimited' : fmtInt(max)}');
          }),
          ACol('Per credit', width: 120, numeric: true,
              (r) => Text('${_fmtNum(r['price_per_credit_cents'])}¢')),
          ACol('Status', width: 110, _statusCell),
          ACol('', width: 60,
              (r) => _actions(onEdit: () => _editTier(existing: r))),
        ],
      ),
    );
  }

  Future<void> _editTier({Map<String, dynamic>? existing}) async {
    final saved = await _showForm(
      title: existing == null ? 'Add pricing tier' : 'Edit pricing tier',
      subtitle: 'Price per credit is in US cents and may have decimals.',
      fields: [
        _F.text('name', 'Name', initial: existing?['name']),
        _F.integer('min', 'Min monthly credits',
            initial: existing?['min_monthly_credits'] ?? 0, allowZero: true),
        _F.integer('max', 'Max monthly credits (blank = unlimited)',
            initial: existing?['max_monthly_credits'], required: false),
        _F.decimal('ppc', 'Price per credit (cents)',
            initial: existing?['price_per_credit_cents']),
        _F.toggle('active', 'Active',
            initial: existing == null || _active(existing)),
      ],
      crossCheck: (v) {
        final min = v['min'] as int?;
        final max = v['max'] as int?;
        if (min != null && max != null && max < min) {
          return {'max': 'Must be at least the minimum (${fmtInt(min)})'};
        }
        return const {};
      },
      onSave: (v) async {
        if (existing == null) {
          await _api.createPricingTier(
            name: v['name'] as String,
            minMonthlyCredits: v['min'] as int,
            maxMonthlyCredits: v['max'] as int?,
            pricePerCreditCents: v['ppc'] as double,
            isActive: v['active'] as bool,
          );
        } else {
          await _api.updatePricingTier(
            _id(existing),
            name: v['name'] as String,
            minMonthlyCredits: v['min'] as int,
            maxMonthlyCredits: v['max'] as int?,
            pricePerCreditCents: v['ppc'] as double,
            isActive: v['active'] as bool,
          );
        }
      },
    );
    _afterSave(saved, existing == null ? 'Tier created' : 'Tier updated');
  }

  // ------------------------------------------------------------------ shared

  void _afterSave(bool? saved, String message) {
    if (saved != true || !mounted) return;
    aToast(context, message);
    _load();
  }

  Future<void> _delete({
    required String kind,
    required Map<String, dynamic> row,
    required Future<void> Function(int id) call,
    required List<Map<String, dynamic>> list,
  }) async {
    final name = '${row['name'] ?? ''}';
    final ok = await aConfirm(
      context,
      title: 'Delete $kind?',
      message: 'Delete "$name"? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok == null) return;
    final id = _id(row);
    try {
      await call(id);
      if (!mounted) return;
      setState(() => list.removeWhere((p) => _id(p) == id));
      aToast(context, '"$name" deleted');
    } catch (e) {
      if (!mounted) return;
      aToast(context, 'Could not delete $kind: ${cleanError(e)}', error: true);
    }
  }

  Future<bool?> _showForm({
    required String title,
    String? subtitle,
    required List<_F> fields,
    required Future<void> Function(Map<String, dynamic> values) onSave,
    String? Function(Map<String, dynamic> values)? preview,
    Map<String, String> Function(Map<String, dynamic> values)? crossCheck,
  }) {
    return showADialog<bool>(
      context,
      title: title,
      subtitle: subtitle,
      builder: (ctx) => _RecordForm(
        fields: fields,
        onSave: onSave,
        preview: preview,
        crossCheck: crossCheck,
      ),
    );
  }
}

// -------------------------------------------------------------------- form

enum _FKind { text, integer, decimal, choice, toggle }

class _F {
  final String key;
  final String label;
  final _FKind kind;
  final Object? initial;
  final bool required;
  final bool allowZero;
  final bool money;
  final String? help;
  final Map<String, String> options;

  const _F._(this.key, this.label, this.kind,
      {this.initial,
      this.required = true,
      this.allowZero = false,
      this.money = false,
      this.help,
      this.options = const {}});

  factory _F.text(String key, String label,
          {Object? initial, bool required = true}) =>
      _F._(key, label, _FKind.text, initial: initial, required: required);

  factory _F.integer(String key, String label,
          {Object? initial,
          bool required = true,
          bool allowZero = false,
          bool money = false}) =>
      _F._(key, label, _FKind.integer,
          initial: initial,
          required: required,
          allowZero: allowZero,
          money: money);

  factory _F.decimal(String key, String label, {Object? initial}) =>
      _F._(key, label, _FKind.decimal, initial: initial);

  factory _F.choice(String key, String label,
          {required Map<String, String> options, required String initial}) =>
      _F._(key, label, _FKind.choice, initial: initial, options: options);

  factory _F.toggle(String key, String label,
          {required bool initial, String? help}) =>
      _F._(key, label, _FKind.toggle, initial: initial, help: help);
}

class _RecordForm extends StatefulWidget {
  final List<_F> fields;
  final Future<void> Function(Map<String, dynamic> values) onSave;
  final String? Function(Map<String, dynamic> values)? preview;
  final Map<String, String> Function(Map<String, dynamic> values)? crossCheck;

  const _RecordForm({
    required this.fields,
    required this.onSave,
    this.preview,
    this.crossCheck,
  });

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, Object?> _other = {};
  Map<String, String> _errors = {};
  String? _saveError;
  bool _busy = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.kind) {
        case _FKind.toggle:
          _other[f.key] = f.initial == true;
        case _FKind.choice:
          _other[f.key] = f.options.containsKey(f.initial)
              ? f.initial
              : f.options.keys.first;
        default:
          final init = f.initial;
          var text = init == null ? '' : '$init';
          // 5.0 → "5" so integer-looking decimals stay readable.
          if (init is double && init == init.roundToDouble()) {
            text = '${init.round()}';
          }
          _ctrl[f.key] = TextEditingController(text: text);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parsed values; unparsable numbers are null. Used for the live preview
  /// (lenient) and for saving (after [_validate] passes).
  Map<String, dynamic> _values() {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.kind) {
        case _FKind.toggle:
        case _FKind.choice:
          out[f.key] = _other[f.key];
        case _FKind.text:
          out[f.key] = _ctrl[f.key]!.text.trim();
        case _FKind.integer:
          out[f.key] = int.tryParse(_ctrl[f.key]!.text.trim());
        case _FKind.decimal:
          out[f.key] = double.tryParse(_ctrl[f.key]!.text.trim());
      }
    }
    return out;
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    final values = _values();
    for (final f in widget.fields) {
      if (f.kind == _FKind.toggle || f.kind == _FKind.choice) continue;
      final raw = _ctrl[f.key]!.text.trim();
      if (raw.isEmpty) {
        if (f.required) errors[f.key] = 'Required';
        continue;
      }
      if (f.kind == _FKind.integer) {
        final v = values[f.key] as int?;
        if (v == null) {
          errors[f.key] = 'Enter a whole number';
        } else if (v < 0 || (v == 0 && !f.allowZero)) {
          errors[f.key] =
              f.allowZero ? 'Cannot be negative' : 'Must be greater than 0';
        }
      } else if (f.kind == _FKind.decimal) {
        final v = values[f.key] as double?;
        if (v == null) {
          errors[f.key] = 'Enter a number';
        } else if (v <= 0) {
          errors[f.key] = 'Must be greater than 0';
        }
      }
    }
    if (errors.isEmpty && widget.crossCheck != null) {
      errors.addAll(widget.crossCheck!(values));
    }
    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    setState(() {
      _submitted = true;
      _errors = errors;
      _saveError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(_values());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = cleanError(e);
      });
      aToast(context, 'Not saved: ${cleanError(e)}', error: true);
    }
  }

  void _changed() {
    setState(() {
      if (_submitted) _errors = _validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview?.call(_values());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in widget.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _field(f),
          ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(preview, style: AT.small.copyWith(color: AC.accent)),
          ),
        if (_saveError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AErrorBox(_saveError!),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AButton('Cancel',
                kind: AButtonKind.ghost,
                onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
            const SizedBox(width: 8),
            AButton(_busy ? 'Saving…' : 'Save',
                kind: AButtonKind.primary, busy: _busy, onPressed: _save),
          ],
        ),
      ],
    );
  }

  Widget _field(_F f) {
    switch (f.kind) {
      case _FKind.toggle:
        final on = _other[f.key] == true;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.label, style: AT.body),
                  if (f.help != null) Text(f.help!, style: AT.mute),
                ],
              ),
            ),
            Switch(
              value: on,
              activeThumbColor: AC.accent,
              onChanged:
                  _busy ? null : (v) => setState(() => _other[f.key] = v),
            ),
          ],
        );
      case _FKind.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: AT.small),
            const SizedBox(height: 6),
            ASegmented<String>(
              options: f.options,
              value: _other[f.key] as String,
              onChanged: (v) => setState(() => _other[f.key] = v),
            ),
          ],
        );
      default:
        final err = _errors[f.key];
        String? helper;
        if (f.money) {
          final cents = int.tryParse(_ctrl[f.key]!.text.trim());
          if (cents != null && cents > 0) helper = '= ${fmtMoney(cents)}';
        }
        return TextField(
          controller: _ctrl[f.key],
          enabled: !_busy,
          onChanged: (_) => _changed(),
          onSubmitted: (_) => _save(),
          style: AT.body,
          cursorColor: AC.accent,
          keyboardType: f.kind == _FKind.text
              ? TextInputType.text
              : TextInputType.numberWithOptions(
                  decimal: f.kind == _FKind.decimal),
          inputFormatters: f.kind == _FKind.integer
              ? [FilteringTextInputFormatter.digitsOnly]
              : f.kind == _FKind.decimal
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                  : null,
          decoration: aInput(label: f.label).copyWith(
            errorText: err,
            errorStyle: const TextStyle(color: AC.red, fontSize: 12),
            helperText: helper,
            helperStyle: const TextStyle(color: AC.textMute, fontSize: 12),
          ),
        );
    }
  }
}
