import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/download_helper.dart';
import '../core/utils/server_time.dart';
import 'app_shell_common.dart';

/// One line of a search's technical log.
class JobLogEntry {
  final String message;

  /// Local time of the line (from `log_entries[].created_at`), when known.
  final DateTime? time;

  const JobLogEntry(this.message, {this.time});

  /// `log_entries` of GET /api/jobs/{id}: `[{id, message, created_at}]`.
  static List<JobLogEntry> fromPayload(Object? raw) {
    if (raw is! List) return const <JobLogEntry>[];
    return raw.whereType<Map>().map((e) {
      return JobLogEntry(
        '${e['message'] ?? ''}',
        time: parseServerTimeLocal(e['created_at']),
      );
    }).toList();
  }

  /// Plain log lines (no timestamps).
  static List<JobLogEntry> fromLines(Iterable<String> lines) =>
      lines.map((l) => JobLogEntry(l)).toList();

  String get timeLabel {
    final t = time;
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// "13:04:05  message" (or just the message).
  String get asText => time == null ? message : '$timeLabel  $message';
}

enum JobLogFilter { all, errors, warnings, info }

bool isErrorLogLine(String line) {
  final l = line.toLowerCase();
  return l.contains('error') || l.contains('failed') || l.contains('timeout') || l.contains('timed out');
}

bool isWarningLogLine(String line) {
  if (isErrorLogLine(line)) return false;
  final l = line.toLowerCase();
  return l.contains('warn') || l.contains('retry') || l.contains('skipping') || l.contains('cancel');
}

bool isInfoLogLine(String line) => !isErrorLogLine(line) && !isWarningLogLine(line);

/// Entries matching [filter] and the search [query] (case-insensitive).
List<JobLogEntry> filterJobLog(List<JobLogEntry> entries, JobLogFilter filter, String query) {
  Iterable<JobLogEntry> out = entries;
  switch (filter) {
    case JobLogFilter.errors:
      out = out.where((e) => isErrorLogLine(e.message));
      break;
    case JobLogFilter.warnings:
      out = out.where((e) => isWarningLogLine(e.message));
      break;
    case JobLogFilter.info:
      out = out.where((e) => isInfoLogLine(e.message));
      break;
    case JobLogFilter.all:
      break;
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) out = out.where((e) => e.asText.toLowerCase().contains(q));
  return out.toList();
}

/// The technical log of a search, with every tool of the old activity panel:
/// search, filters (All / Errors / Warnings / Info), auto-scroll on/off,
/// copy, export (.txt) and a taller "expanded" view. Times are local.
class JobLogPanel extends StatefulWidget {
  final List<JobLogEntry> entries;
  final bool isRunning;

  /// Used for the export file name.
  final String jobId;
  final String? category;

  const JobLogPanel({
    super.key,
    required this.entries,
    required this.jobId,
    this.isRunning = false,
    this.category,
  });

  @override
  State<JobLogPanel> createState() => _JobLogPanelState();
}

class _JobLogPanelState extends State<JobLogPanel> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  JobLogFilter _filter = JobLogFilter.all;
  bool _autoScroll = true;
  bool _expanded = false;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    _scrollToEnd(animated: false);
  }

  @override
  void didUpdateWidget(covariant JobLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length != _lastCount && _autoScroll) _scrollToEnd();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  String _countLabel(int n) {
    switch (_filter) {
      case JobLogFilter.errors:
        return plural(n, 'error', 'errors');
      case JobLogFilter.warnings:
        return plural(n, 'warning', 'warnings');
      case JobLogFilter.info:
        return plural(n, 'info line', 'info lines');
      case JobLogFilter.all:
        return plural(n, 'line', 'lines');
    }
  }

  String? _emptyMessage(List<JobLogEntry> filtered) {
    if (widget.entries.isEmpty) {
      return widget.isRunning ? 'Waiting for the first log line…' : 'This search has no log lines.';
    }
    if (filtered.isEmpty && _search.text.trim().isNotEmpty) {
      return 'No log lines match "${_search.text.trim()}".';
    }
    if (filtered.isEmpty) return 'No ${_filterLabel(_filter).toLowerCase()} in this log.';
    return null;
  }

  static String _filterLabel(JobLogFilter f) {
    switch (f) {
      case JobLogFilter.all:
        return 'All';
      case JobLogFilter.errors:
        return 'Errors';
      case JobLogFilter.warnings:
        return 'Warnings';
      case JobLogFilter.info:
        return 'Info';
    }
  }

  Future<void> _copy(List<JobLogEntry> lines) async {
    if (lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: lines.map((e) => e.asText).join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('Copied ${plural(lines.length, 'log line', 'log lines')}'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _export(List<JobLogEntry> lines) async {
    if (lines.isEmpty) return;
    final id = widget.jobId.length > 8 ? widget.jobId.substring(0, 8) : widget.jobId;
    final cat = safeFileNamePart(widget.category ?? 'search', maxLength: 24);
    await saveTextFile(
      lines.map((e) => e.asText).join('\n'),
      'search_log_${cat}_${id}_${fileTimestamp()}',
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterJobLog(widget.entries, _filter, _search.text);
    if (_lastCount != widget.entries.length) {
      _lastCount = widget.entries.length;
    }
    final empty = _emptyMessage(filtered);
    final height = _expanded ? 520.0 : 260.0;

    final iconStyle = IconButton.styleFrom(
      foregroundColor: UiTokens.textSecondary,
      minimumSize: const Size(44, 44),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => setState(() {}),
                style: const TextStyle(color: UiTokens.text, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search the log',
                  hintStyle: const TextStyle(color: UiTokens.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: UiTokens.textMuted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear log search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: UiTokens.textMuted,
                          onPressed: () => setState(_search.clear),
                        ),
                  filled: true,
                  fillColor: UiTokens.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: UiTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: UiTokens.border),
                  ),
                ),
              ),
            ),
            for (final f in JobLogFilter.values)
              ChoiceChip(
                label: Text(_filterLabel(f)),
                selected: _filter == f,
                showCheckmark: true,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                labelStyle: TextStyle(
                  color: _filter == f ? UiTokens.text : UiTokens.textSecondary,
                  fontWeight: _filter == f ? FontWeight.w700 : FontWeight.w500,
                ),
                selectedColor: UiTokens.selectedSurface,
                backgroundColor: UiTokens.card,
                checkmarkColor: UiTokens.accent,
                side: BorderSide(color: _filter == f ? UiTokens.accent : UiTokens.border),
                onSelected: (_) {
                  setState(() => _filter = f);
                  if (_autoScroll) _scrollToEnd();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _countLabel(filtered.length),
                style: const TextStyle(color: UiTokens.textMuted, fontSize: 13),
              ),
            ),
            Semantics(
              toggled: _autoScroll,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: _autoScroll ? UiTokens.accent : UiTokens.textSecondary,
                  minimumSize: const Size(44, 44),
                ),
                onPressed: () {
                  setState(() => _autoScroll = !_autoScroll);
                  if (_autoScroll) _scrollToEnd();
                },
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom_rounded : Icons.pause_circle_outline_rounded,
                  size: 18,
                ),
                label: Text(_autoScroll ? 'Auto-scroll on' : 'Auto-scroll off'),
              ),
            ),
            IconButton(
              style: iconStyle,
              tooltip: 'Copy log',
              onPressed: filtered.isEmpty ? null : () => _copy(filtered),
              icon: const Icon(Icons.copy_all_rounded, size: 20),
            ),
            IconButton(
              style: iconStyle,
              tooltip: 'Export log (.txt)',
              onPressed: filtered.isEmpty ? null : () => _export(filtered),
              icon: const Icon(Icons.download_rounded, size: 20),
            ),
            IconButton(
              style: iconStyle,
              tooltip: _expanded ? 'Make log smaller' : 'Make log taller',
              onPressed: () {
                setState(() => _expanded = !_expanded);
                if (_autoScroll) _scrollToEnd(animated: false);
              },
              icon: Icon(_expanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111113),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: UiTokens.border),
          ),
          child: empty != null
              ? Center(
                  child: Text(
                    empty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: UiTokens.textMuted, fontSize: 13),
                  ),
                )
              : Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _LogLine(entry: filtered[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  final JobLogEntry entry;

  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final error = isErrorLogLine(entry.message);
    final warning = !error && isWarningLogLine(entry.message);
    final color = error
        ? UiTokens.failedFg
        : warning
            ? UiTokens.partialFg
            : UiTokens.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: error || warning
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      error ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                      size: 13,
                      color: color,
                      semanticLabel: error ? 'Error' : 'Warning',
                    ),
                  )
                : null,
          ),
          if (entry.time != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                entry.timeLabel,
                style: const TextStyle(
                  color: UiTokens.accent,
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
