import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/server_time.dart';
import '../../services/api_service.dart';

DateTime _parseServerOrThrow(Object? value) {
  final dt = parseServerTimeLocal(value);
  if (dt == null) throw const FormatException('bad time');
  return dt;
}

/// Search event detail: the event, the search it belongs to and a paged
/// preview of its leads. Moved out of the old dashboard screen unchanged.
class JobEventPanel extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> event;
  final VoidCallback onClose;

  const JobEventPanel({
    required this.apiService,
    required this.event,
    required this.onClose,
  });

  @override
  State<JobEventPanel> createState() =>
      _JobEventPanelState();
}

class _JobEventPanelState extends State<JobEventPanel> {
  static const int _pageSize = 25;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int _total = 0;
  int _offset = 0;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadResults(resetOffset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _jobId => (widget.event['job_id'] ?? '').toString();
  String get _jobType =>
      (widget.event['job_type'] ?? widget.event['category'] ?? '').toString();
  String get _eventType => (widget.event['event_type'] ?? '').toString();
  String get _status => (widget.event['job_status'] ?? '').toString();
  String get _createdAt => (widget.event['created_at'] ?? '').toString();
  int get _resultCount =>
      (widget.event['result_count'] as num?)?.toInt() ??
      int.tryParse('${widget.event['result_count'] ?? 0}') ??
      0;

  Future<void> _loadResults({bool resetOffset = false}) async {
    final jobId = _jobId;
    if (jobId.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
        _total = 0;
        _error = 'Missing job id';
      });
      return;
    }

    if (resetOffset) _offset = 0;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.apiService.getJobResultsAdmin(
        jobId,
        limit: _pageSize,
        offset: _offset,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(data['results'] ?? const []);
        _total = (data['total'] as num?)?.toInt() ?? _results.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load job results: $e';
      });
    }
  }

  String _formatTimestamp(String value) {
    if (value.isEmpty) return '-';
    try {
      final dt = _parseServerOrThrow(value);
      return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.successGreen;
      case 'failed':
        return AppColors.dangerRed;
      case 'cancelled':
        return AppColors.warningYellow;
      case 'running':
        return AppColors.infoBlue;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_status);
    final currentPage = (_offset ~/ _pageSize) + 1;
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(
                bottom: BorderSide(color: AppColors.elevatedCardDark),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Job Activity Details',
                        style: AppTypography.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _metaChip('Job', _jobId, Colors.white70),
                    _metaChip('Type', _jobType, Colors.white70),
                    _metaChip('Event', _eventType, AppColors.brandPurple),
                    _metaChip('Status', _status.toUpperCase(), statusColor),
                    _metaChip('Leads', '$_resultCount', AppColors.infoBlue),
                    _metaChip(
                        'At', _formatTimestamp(_createdAt), Colors.white70),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText:
                              'Search leads by business, city, phone, email...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: AppColors.elevatedCardDark,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppSpacing.borderRadiusSm,
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (value) {
                          _search = value.trim();
                          _loadResults(resetOffset: true);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _panelButton(
                      label: 'Search',
                      onTap: () {
                        _search = _searchController.text.trim();
                        _loadResults(resetOffset: true);
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _panelButton(
                      label: 'Refresh',
                      color: AppColors.elevatedCardDark,
                      onTap: () => _loadResults(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.brandPurple,
                      ),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            _error!,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.dangerRed),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'No results found for this job.',
                                style: AppTypography.bodyMedium
                                    .copyWith(color: Colors.white60),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              return Container(
                                margin: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: AppColors.elevatedCardDark,
                                  borderRadius: AppSpacing.borderRadiusSm,
                                  border:
                                      Border.all(color: AppColors.surfaceDark),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (r['business_name'] ?? 'Unknown')
                                          .toString(),
                                      style: AppTypography.labelLarge.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r['city'] ?? '-'}, ${r['state'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white60),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Phone: ${r['phone'] ?? '-'}   Email: ${r['email'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Website: ${r['website'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(
                top: BorderSide(color: AppColors.elevatedCardDark),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Page $currentPage / $totalPages',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _panelButton(
                  label: 'Prev',
                  color: AppColors.elevatedCardDark,
                  onTap: _offset > 0
                      ? () {
                          _offset =
                              ((_offset - _pageSize).clamp(0, _total) as num)
                                  .toInt();
                          _loadResults();
                        }
                      : null,
                ),
                const SizedBox(width: AppSpacing.xs),
                _panelButton(
                  label: 'Next',
                  color: AppColors.elevatedCardDark,
                  onTap: _offset + _pageSize < _total
                      ? () {
                          _offset += _pageSize;
                          _loadResults();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        '$label: $value',
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _panelButton({
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.borderRadiusSm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color ?? AppColors.brandPurple,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
