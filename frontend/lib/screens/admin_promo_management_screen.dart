import 'package:flutter/material.dart';
import 'dart:math';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';

class AdminPromoManagementScreen extends StatefulWidget {
  const AdminPromoManagementScreen({super.key});

  @override
  State<AdminPromoManagementScreen> createState() =>
      _AdminPromoManagementScreenState();
}

class _AdminPromoManagementScreenState extends State<AdminPromoManagementScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _promos = [];
  final TextEditingController _searchController = TextEditingController();
  bool _activeOnly = false;
  String _sortKey = 'created_at_desc';
  final Set<int> _selectedPromoIds = {};
  Map<String, dynamic>? _selectedPromo;
  int? _analyticsPromoId;
  Map<String, dynamic>? _analyticsUsage;
  bool _analyticsLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getAdminPromos();
      if (!mounted) return;
      setState(() {
        _promos = List<Map<String, dynamic>>.from(res['promos'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load promos: $e';
      });
      _snack('Failed to load promos: $e', AppColors.dangerRed);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.isAdmin) {
      return Scaffold(
        body: GradientBackground(
          child: Center(
            child: Text(
              'Admin access required',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          title: Text(
            'Promo Management',
            style: AppTypography.titleLarge.copyWith(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            const SizedBox(width: AppSpacing.sm),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: 'List'),
              Tab(text: 'Create'),
              Tab(text: 'Edit'),
              Tab(text: 'Analytics'),
            ],
          ),
        ),
        body: GradientBackground(
          child: SafeArea(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        backgroundColor: AppColors.surfaceDark,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryBlue),
                      ),
                    ),
                  )
                : _error != null
                    ? _buildErrorState()
                    : TabBarView(
                        children: [
                          _buildListTab(),
                          _buildCreateTab(),
                          _buildEditTab(),
                          _buildAnalyticsTab(),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredPromos() {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _promos.where((p) {
      if (_activeOnly && p['is_active'] != true) return false;
      if (q.isEmpty) return true;
      final code = (p['code'] ?? '').toString().toLowerCase();
      return code.contains(q);
    }).toList();

    int cmpNumDesc(dynamic a, dynamic b) {
      final na = (a as num?)?.toDouble() ?? 0;
      final nb = (b as num?)?.toDouble() ?? 0;
      return nb.compareTo(na);
    }

    int cmpStringDesc(dynamic a, dynamic b) {
      final sa = (a ?? '').toString();
      final sb = (b ?? '').toString();
      return sb.compareTo(sa);
    }

    filtered.sort((a, b) {
      switch (_sortKey) {
        case 'uses_desc':
          return cmpNumDesc(a['uses_count'], b['uses_count']);
        case 'code_asc':
          return (a['code'] ?? '').toString().compareTo((b['code'] ?? '').toString());
        case 'created_at_desc':
        default:
          return cmpStringDesc(a['created_at'], b['created_at']);
      }
    });
    return filtered;
  }

  String _promoValueLabel(Map<String, dynamic> promo) {
    final type = (promo['type'] ?? '').toString();
    if (type == 'percentage_off') {
      final pct = (promo['discount_percentage'] as num? ?? 0).toDouble();
      return '${pct.toStringAsFixed(0)}%';
    }
    if (type == 'fixed_amount_off') {
      final cents = (promo['discount_amount_cents'] as num? ?? 0).toInt();
      return '\$${(cents / 100.0).toStringAsFixed(2)}';
    }
    if (type == 'bonus_credits') {
      final bonus = (promo['bonus_credits'] as num? ?? 0).toInt();
      return '+$bonus';
    }
    return '-';
  }

  Future<void> _bulkSetActive(bool isActive) async {
    final ids = _selectedPromoIds.toList(growable: false);
    if (ids.isEmpty) return;

    try {
      for (final id in ids) {
        if (isActive) {
          await _api.updatePromo(id, isActive: true);
        } else {
          await _api.deactivatePromo(id);
        }
      }
      _selectedPromoIds.clear();
      await _load();
      _snack(
        isActive ? 'Activated promos' : 'Deactivated promos',
        AppColors.successGreen,
      );
    } catch (e) {
      _snack('Bulk action failed: $e', AppColors.dangerRed);
    }
  }

  void _selectForEdit(Map<String, dynamic> promo) {
    setState(() {
      _selectedPromo = promo;
    });
    DefaultTabController.of(context).animateTo(2);
  }

  Future<void> _loadAnalyticsUsage(int promoId) async {
    setState(() {
      _analyticsLoading = true;
      _analyticsUsage = null;
    });
    try {
      final usage = await _api.getAdminPromoUsage(promoId);
      if (!mounted) return;
      setState(() {
        _analyticsUsage = usage;
        _analyticsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyticsLoading = false;
      });
      _snack('Failed to load usage: $e', AppColors.dangerRed);
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.dangerRed, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: AppColors.elevatedCardDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_offer_rounded,
                color: AppColors.primaryBlueLight,
                size: 44,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No promos yet',
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Create a promo code to offer discounts or bonus credits.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton.icon(
                onPressed: () => DefaultTabController.of(context).animateTo(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create promo'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTab() {
    final promos = _filteredPromos();
    final allVisibleIds = promos.map((p) => (p['id'] as num).toInt()).toSet();
    final allVisibleSelected =
        allVisibleIds.isNotEmpty && _selectedPromoIds.containsAll(allVisibleIds);
    final someVisibleSelected =
        allVisibleIds.any((id) => _selectedPromoIds.contains(id));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search code…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.white54, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilterChip(
                label: const Text('Active only'),
                selected: _activeOnly,
                onSelected: (v) => setState(() => _activeOnly = v),
                selectedColor: AppColors.primaryBlue.withValues(alpha: 0.25),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: _activeOnly ? Colors.white : Colors.white70,
                ),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.35),
              ),
              const SizedBox(width: AppSpacing.md),
              DropdownButton<String>(
                value: _sortKey,
                dropdownColor: AppColors.surfaceDark,
                style: const TextStyle(color: Colors.white),
                underline: Container(),
                items: const [
                  DropdownMenuItem(
                      value: 'created_at_desc', child: Text('Newest')),
                  DropdownMenuItem(value: 'uses_desc', child: Text('Most used')),
                  DropdownMenuItem(value: 'code_asc', child: Text('Code A–Z')),
                ],
                onChanged: (v) => setState(() => _sortKey = v ?? _sortKey),
              ),
              const SizedBox(width: AppSpacing.md),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => DefaultTabController.of(context).animateTo(1),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create'),
              ),
            ],
          ),
          if (_selectedPromoIds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  '${_selectedPromoIds.length} selected',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _bulkSetActive(true),
                  icon: const Icon(Icons.play_circle_outline_rounded,
                      color: AppColors.successGreen),
                  label: const Text('Activate'),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton.icon(
                  onPressed: () => _bulkSetActive(false),
                  icon: const Icon(Icons.pause_circle_outline_rounded,
                      color: AppColors.dangerRed),
                  label: const Text('Deactivate'),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () => setState(() => _selectedPromoIds.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: promos.isEmpty
                ? _buildEmptyState()
                : DarkGlassCard(
                    padding: AppSpacing.paddingMd,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingTextStyle: AppTypography.labelSmall.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                        dataTextStyle: AppTypography.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        columns: [
                          DataColumn(
                            label: Checkbox(
                              value: allVisibleSelected
                                  ? true
                                  : (someVisibleSelected ? null : false),
                              tristate: true,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedPromoIds.addAll(allVisibleIds);
                                  } else {
                                    _selectedPromoIds
                                        .removeAll(allVisibleIds.toList());
                                  }
                                });
                              },
                            ),
                          ),
                          const DataColumn(label: Text('Code')),
                          const DataColumn(label: Text('Type')),
                          const DataColumn(label: Text('Discount')),
                          const DataColumn(label: Text('Max Uses')),
                          const DataColumn(label: Text('Used')),
                          const DataColumn(label: Text('Status')),
                          const DataColumn(label: Text('Actions')),
                        ],
                        rows: promos.map((promo) {
                          final id = (promo['id'] as num).toInt();
                          final code = (promo['code'] ?? '').toString();
                          final type = (promo['type'] ?? '').toString();
                          final maxUses = promo['max_uses'];
                          final uses = (promo['uses_count'] as num? ?? 0).toInt();
                          final active = promo['is_active'] == true;
                          final selected = _selectedPromoIds.contains(id);
                          return DataRow(
                            selected: selected,
                            onSelectChanged: (_) => setState(() {
                              if (selected) {
                                _selectedPromoIds.remove(id);
                              } else {
                                _selectedPromoIds.add(id);
                              }
                            }),
                            cells: [
                              DataCell(Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selectedPromoIds.add(id);
                                  } else {
                                    _selectedPromoIds.remove(id);
                                  }
                                }),
                              )),
                              DataCell(Text(code)),
                              DataCell(Text(type)),
                              DataCell(Text(_promoValueLabel(promo))),
                              DataCell(Text(maxUses == null ? '∞' : '$maxUses')),
                              DataCell(Text('$uses')),
                              DataCell(Text(active ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    color: active
                                        ? AppColors.successGreen
                                        : Colors.white60,
                                  ))),
                              DataCell(Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => _selectForEdit(promo),
                                    icon: const Icon(Icons.edit_rounded,
                                        color: Colors.white70),
                                  ),
                                  IconButton(
                                    tooltip: active ? 'Deactivate' : 'Activate',
                                    onPressed: () async {
                                      if (active) {
                                        await _api.deactivatePromo(id);
                                      } else {
                                        await _api.updatePromo(id, isActive: true);
                                      }
                                      _load();
                                    },
                                    icon: Icon(
                                      active
                                          ? Icons.pause_circle_outline_rounded
                                          : Icons.play_circle_outline_rounded,
                                      color: active
                                          ? AppColors.dangerRed
                                          : AppColors.successGreen,
                                    ),
                                  ),
                                ],
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _PromoFormCard(
        title: 'Create Promo',
        onSubmit: (values) async {
          await _api.createPromo(
            code: values.code,
            type: values.type,
            discountPercentage: values.discountPercentage,
            discountAmountCents: values.discountAmountCents,
            bonusCredits: values.bonusCredits,
            maxUses: values.maxUses,
            maxUsesPerUser: values.maxUsesPerUser,
            minPurchaseCents: values.minPurchaseCents,
            validFrom: values.validFrom,
            validUntil: values.validUntil,
            appliesTo: values.appliesTo,
            isActive: values.isActive,
          );
          await _load();
          if (!mounted) return;
          _snack('Promo created', AppColors.successGreen);
          DefaultTabController.of(context).animateTo(0);
        },
      ),
    );
  }

  Widget _buildEditTab() {
    final promo = _selectedPromo;
    if (promo == null) {
      return Center(
        child: Text(
          'Select a promo from the list to edit.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
      );
    }

    final id = (promo['id'] as num).toInt();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _PromoFormCard(
        title: 'Edit Promo',
        initial: promo,
        onSubmit: (values) async {
          await _api.updatePromo(
            id,
            code: values.code,
            type: values.type,
            discountPercentage: values.discountPercentage,
            discountAmountCents: values.discountAmountCents,
            bonusCredits: values.bonusCredits,
            maxUses: values.maxUses,
            maxUsesPerUser: values.maxUsesPerUser,
            minPurchaseCents: values.minPurchaseCents,
            validFrom: values.validFrom,
            validUntil: values.validUntil,
            appliesTo: values.appliesTo,
            isActive: values.isActive,
          );
          await _load();
          if (!mounted) return;
          _snack('Promo updated', AppColors.successGreen);
        },
        footer: Row(
          children: [
            TextButton.icon(
              onPressed: () async {
                await _api.deactivatePromo(id);
                await _load();
                if (!mounted) return;
                _snack('Promo deactivated', AppColors.warningYellow);
              },
              icon: const Icon(Icons.pause_circle_outline_rounded,
                  color: AppColors.dangerRed),
              label: const Text('Deactivate'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final total = _promos.length;
    final active = _promos.where((p) => p['is_active'] == true).length;
    final totalUses = _promos.fold<int>(
        0, (acc, p) => acc + ((p['uses_count'] as num? ?? 0).toInt()));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DarkGlassCard(
                  padding: AppSpacing.paddingMd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total promos',
                          style: AppTypography.labelSmall
                              .copyWith(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text('$total',
                          style: AppTypography.titleLarge
                              .copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DarkGlassCard(
                  padding: AppSpacing.paddingMd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active promos',
                          style: AppTypography.labelSmall
                              .copyWith(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text('$active',
                          style: AppTypography.titleLarge.copyWith(
                              color: AppColors.successGreen,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DarkGlassCard(
                  padding: AppSpacing.paddingMd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total uses',
                          style: AppTypography.labelSmall
                              .copyWith(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text('$totalUses',
                          style: AppTypography.titleLarge
                              .copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DarkGlassCard(
            padding: AppSpacing.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promo usage',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _analyticsPromoId,
                      dropdownColor: AppColors.surfaceDark,
                      hint: const Text('Select promo',
                          style: TextStyle(color: Colors.white70)),
                      items: _promos.map((p) {
                        final id = (p['id'] as num).toInt();
                        final code = (p['code'] ?? '').toString();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(code, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() => _analyticsPromoId = id);
                        _loadAnalyticsUsage(id);
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _analyticsPromoId == null
                          ? null
                          : () => _loadAnalyticsUsage(_analyticsPromoId!),
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_analyticsLoading)
                  const LinearProgressIndicator(
                    backgroundColor: AppColors.surfaceDark,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                  )
                else if (_analyticsUsage != null)
                  Row(
                    children: [
                      Expanded(
                        child: _metricTile(
                          label: 'Uses',
                          value: '${_analyticsUsage!['uses'] ?? 0}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _metricTile(
                          label: 'Discount total',
                          value:
                              '\$${((( _analyticsUsage!['discount_amount_cents'] ?? 0) as num).toInt() / 100.0).toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _metricTile(
                          label: 'Credits awarded',
                          value: '${_analyticsUsage!['credits_awarded'] ?? 0}',
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Select a promo to view usage stats.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({required String label, required String value}) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.35),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  AppTypography.labelSmall.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(value,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
    );
  }

  Widget _promoTile(Map<String, dynamic> promo) {
    final id = (promo['id'] as num).toInt();
    final code = promo['code'] ?? '';
    final type = promo['type'] ?? '';
    final active = promo['is_active'] == true;
    final uses = promo['uses_count'] ?? 0;

    return DarkGlassCard(
      child: Row(
        children: [
          Icon(
            Icons.confirmation_number_rounded,
            color: active ? AppColors.amber : Colors.white38,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.toString(),
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$type • uses: $uses',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _showPromoDialog(existing: promo),
            icon: const Icon(Icons.edit_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: active ? 'Deactivate' : 'Activate',
            onPressed: () async {
              if (active) {
                await _api.deactivatePromo(id);
              } else {
                await _api.updatePromo(id, isActive: true);
              }
              _load();
            },
            icon: Icon(
              active
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              color: active ? AppColors.dangerRed : AppColors.successGreen,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromoDialog({Map<String, dynamic>? existing}) async {
    final code = TextEditingController(text: existing?['code']?.toString() ?? '');
    final type = ValueNotifier<String>(existing?['type']?.toString() ?? 'percentage_off');
    final pct = TextEditingController(text: (existing?['discount_percentage'] ?? 0).toString());
    final amount = TextEditingController(text: (existing?['discount_amount_cents'] ?? 0).toString());
    final bonus = TextEditingController(text: (existing?['bonus_credits'] ?? 0).toString());
    final active = ValueNotifier<bool>(existing?['is_active'] == true || existing == null);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          existing == null ? 'Create Promo' : 'Edit Promo',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(code, 'Code (e.g. SAVE20)'),
              const SizedBox(height: AppSpacing.sm),
              ValueListenableBuilder<String>(
                valueListenable: type,
                builder: (_, v, __) => DropdownButtonFormField<String>(
                  initialValue: v,
                  dropdownColor: AppColors.surfaceDark,
                  decoration: _inputDecoration('Type'),
                  items: const [
                    DropdownMenuItem(value: 'percentage_off', child: Text('percentage_off')),
                    DropdownMenuItem(value: 'fixed_amount_off', child: Text('fixed_amount_off')),
                    DropdownMenuItem(value: 'bonus_credits', child: Text('bonus_credits')),
                  ],
                  onChanged: (nv) => type.value = nv ?? 'percentage_off',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _field(pct, 'Discount % (percentage_off)', keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.sm),
              _field(amount, 'Discount amount (cents) (fixed_amount_off)', keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.sm),
              _field(bonus, 'Bonus credits (bonus_credits)', keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.sm),
              ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, v, __) => SwitchListTile(
                  value: v,
                  onChanged: (nv) => active.value = nv,
                  title: Text('Active', style: AppTypography.bodySmall.copyWith(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final codeVal = code.text.trim();
    if (codeVal.isEmpty) {
      _snack('Code is required', AppColors.dangerRed);
      return;
    }

    if (existing == null) {
      await _api.createPromo(
        code: codeVal,
        type: type.value,
        discountPercentage: double.tryParse(pct.text) ?? 0,
        discountAmountCents: int.tryParse(amount.text) ?? 0,
        bonusCredits: int.tryParse(bonus.text) ?? 0,
        isActive: active.value,
      );
    } else {
      final id = (existing['id'] as num).toInt();
      await _api.updatePromo(
        id,
        code: codeVal,
        type: type.value,
        discountPercentage: double.tryParse(pct.text) ?? 0,
        discountAmountCents: int.tryParse(amount.text) ?? 0,
        bonusCredits: int.tryParse(bonus.text) ?? 0,
        isActive: active.value,
      );
    }
    _load();
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: AppSpacing.borderRadiusMd,
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _PromoFormValues {
  final String code;
  final String type;
  final double discountPercentage;
  final int discountAmountCents;
  final int bonusCredits;
  final int? maxUses;
  final int maxUsesPerUser;
  final int minPurchaseCents;
  final String? validFrom;
  final String? validUntil;
  final String appliesTo;
  final bool isActive;

  const _PromoFormValues({
    required this.code,
    required this.type,
    required this.discountPercentage,
    required this.discountAmountCents,
    required this.bonusCredits,
    required this.maxUses,
    required this.maxUsesPerUser,
    required this.minPurchaseCents,
    required this.validFrom,
    required this.validUntil,
    required this.appliesTo,
    required this.isActive,
  });
}

class _PromoFormCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic>? initial;
  final Future<void> Function(_PromoFormValues values) onSubmit;
  final Widget? footer;

  const _PromoFormCard({
    required this.title,
    required this.onSubmit,
    this.initial,
    this.footer,
  });

  @override
  State<_PromoFormCard> createState() => _PromoFormCardState();
}

class _PromoFormCardState extends State<_PromoFormCard> {
  final _code = TextEditingController();
  final _pct = TextEditingController(text: '0');
  final _amount = TextEditingController(text: '0');
  final _bonus = TextEditingController(text: '0');
  final _maxUses = TextEditingController();
  final _maxUsesPerUser = TextEditingController(text: '1');
  final _minPurchaseCents = TextEditingController(text: '0');
  final _validFrom = TextEditingController();
  final _validUntil = TextEditingController();

  String _type = 'percentage_off';
  String _appliesTo = 'all';
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _code.text = (initial['code'] ?? '').toString();
      _type = (initial['type'] ?? 'percentage_off').toString();
      _pct.text = (initial['discount_percentage'] ?? 0).toString();
      _amount.text = (initial['discount_amount_cents'] ?? 0).toString();
      _bonus.text = (initial['bonus_credits'] ?? 0).toString();
      _maxUses.text = (initial['max_uses'] ?? '').toString();
      _maxUsesPerUser.text = (initial['max_uses_per_user'] ?? 1).toString();
      _minPurchaseCents.text = (initial['min_purchase_cents'] ?? 0).toString();
      _validFrom.text = (initial['valid_from'] ?? '').toString();
      _validUntil.text = (initial['valid_until'] ?? '').toString();
      _appliesTo = (initial['applies_to'] ?? 'all').toString();
      _isActive = initial['is_active'] == true;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _pct.dispose();
    _amount.dispose();
    _bonus.dispose();
    _maxUses.dispose();
    _maxUsesPerUser.dispose();
    _minPurchaseCents.dispose();
    _validFrom.dispose();
    _validUntil.dispose();
    super.dispose();
  }

  String _previewText() {
    if (_type == 'percentage_off') {
      final pct = double.tryParse(_pct.text) ?? 0;
      return '${pct.toStringAsFixed(0)}% off';
    }
    if (_type == 'fixed_amount_off') {
      final cents = int.tryParse(_amount.text) ?? 0;
      return '\$${(cents / 100.0).toStringAsFixed(2)} off';
    }
    if (_type == 'bonus_credits') {
      final bonus = int.tryParse(_bonus.text) ?? 0;
      return '+$bonus credits';
    }
    return '';
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primaryBlue,
              surface: AppColors.surfaceDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    controller.text = picked.toIso8601String();
  }

  void _generateCode() {
    final r = Random();
    final suffix = (1000 + r.nextInt(9000)).toString();
    _code.text = 'SAVE$suffix';
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Code is required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = _PromoFormValues(
        code: code,
        type: _type,
        discountPercentage: double.tryParse(_pct.text) ?? 0,
        discountAmountCents: int.tryParse(_amount.text) ?? 0,
        bonusCredits: int.tryParse(_bonus.text) ?? 0,
        maxUses: _maxUses.text.trim().isEmpty
            ? null
            : int.tryParse(_maxUses.text.trim()),
        maxUsesPerUser: int.tryParse(_maxUsesPerUser.text) ?? 1,
        minPurchaseCents: int.tryParse(_minPurchaseCents.text) ?? 0,
        validFrom: _validFrom.text.trim().isEmpty ? null : _validFrom.text.trim(),
        validUntil:
            _validUntil.text.trim().isEmpty ? null : _validUntil.text.trim(),
        appliesTo: _appliesTo,
        isActive: _isActive,
      );
      await widget.onSubmit(values);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DarkGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Code',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Generate',
                onPressed: _generateCode,
                icon: const Icon(Icons.autorenew_rounded, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _type,
            dropdownColor: AppColors.surfaceDark,
            decoration: InputDecoration(
              labelText: 'Type',
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: AppSpacing.borderRadiusMd,
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'percentage_off', child: Text('percentage_off')),
              DropdownMenuItem(value: 'fixed_amount_off', child: Text('fixed_amount_off')),
              DropdownMenuItem(value: 'bonus_credits', child: Text('bonus_credits')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pct,
                  keyboardType: TextInputType.number,
                  enabled: _type == 'percentage_off',
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Discount %'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  enabled: _type == 'fixed_amount_off',
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Amount (cents)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _bonus,
                  keyboardType: TextInputType.number,
                  enabled: _type == 'bonus_credits',
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Bonus credits'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxUses,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Max uses (blank = unlimited)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _maxUsesPerUser,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Uses per user'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _minPurchaseCents,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _numDecoration('Min purchase (cents)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _validFrom,
                  readOnly: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dateDecoration('Valid from', onTap: () => _pickDate(_validFrom)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _validUntil,
                  readOnly: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dateDecoration('Valid until', onTap: () => _pickDate(_validUntil)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _appliesTo,
                  dropdownColor: AppColors.surfaceDark,
                  decoration: InputDecoration(
                    labelText: 'Applies to',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('all')),
                    DropdownMenuItem(value: 'packages', child: Text('packages')),
                    DropdownMenuItem(value: 'subscriptions', child: Text('subscriptions')),
                  ],
                  onChanged: (v) => setState(() => _appliesTo = v ?? _appliesTo),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Active',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Preview: ${_previewText()}',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.dangerRed),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (widget.footer != null) widget.footer!,
              const Spacer(),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _numDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
      );

  InputDecoration _dateDecoration(String label, {required VoidCallback onTap}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
        suffixIcon: IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_month_rounded, color: Colors.white70),
        ),
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide.none,
        ),
      );
}
