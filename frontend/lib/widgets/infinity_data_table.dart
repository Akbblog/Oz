import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';

class InfinityDataColumn {
  final String label;
  final String keyName;
  final bool numeric;
  final Widget Function(Map<String, dynamic> row)? cellBuilder;

  const InfinityDataColumn({
    required this.label,
    required this.keyName,
    this.numeric = false,
    this.cellBuilder,
  });
}

class InfinityDataTable extends StatelessWidget {
  final List<InfinityDataColumn> columns;
  final List<Map<String, dynamic>> rows;
  final bool sortable;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending)? onSort;
  final bool showCheckboxes;
  final Set<int> selectedRows;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final void Function(bool? checked)? onSelectAll;
  final LayoutType layoutType;
  final Widget Function(Map<String, dynamic> row)? mobileCardBuilder;

  const InfinityDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.layoutType,
    this.sortable = false,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.showCheckboxes = false,
    this.selectedRows = const {},
    this.onSelectionChanged,
    this.onSelectAll,
    this.mobileCardBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (layoutType == LayoutType.mobile && mobileCardBuilder != null) {
      return Column(
        children: rows
            .map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: mobileCardBuilder!(row),
                ))
            .toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortAscending: sortAscending,
          sortColumnIndex: sortColumnIndex,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          headingRowHeight: 52,
          showCheckboxColumn: showCheckboxes,
          onSelectAll: showCheckboxes ? _resolveOnSelectAll() : null,
          headingRowColor: WidgetStateProperty.all(
            AppColors.primaryBlue,
          ),
          headingTextStyle: AppTypography.labelLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          dataTextStyle: AppTypography.bodySmall.copyWith(
            color: Colors.white70,
          ),
          dividerThickness: 0.5,
          columns: _buildColumns(),
          rows: _buildRows(),
        ),
      ),
    );
  }

  void Function(bool?)? _resolveOnSelectAll() {
    if (onSelectAll != null) return onSelectAll;
    if (onSelectionChanged == null) return null;

    return (checked) {
      if (checked == true) {
        onSelectionChanged!.call(
          Set<int>.from(List<int>.generate(rows.length, (i) => i)),
        );
      } else {
        onSelectionChanged!.call(<int>{});
      }
    };
  }

  List<DataColumn> _buildColumns() {
    return List.generate(columns.length, (index) {
      final column = columns[index];
      return DataColumn(
        label: Text(column.label),
        numeric: column.numeric,
        onSort: sortable
            ? (columnIndex, ascending) => onSort?.call(columnIndex, ascending)
            : null,
      );
    });
  }

  List<DataRow> _buildRows() {
    return List.generate(rows.length, (index) {
      final row = rows[index];
      final isSelected = selectedRows.contains(index);
      return DataRow(
        selected: isSelected,
        onSelectChanged: showCheckboxes
            ? (selected) {
                final updated = Set<int>.from(selectedRows);
                if (selected == true) {
                  updated.add(index);
                } else {
                  updated.remove(index);
                }
                onSelectionChanged?.call(updated);
              }
            : null,
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryBlue.withValues(alpha: 0.15);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primaryBlue.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        cells: columns.map((column) {
          final cell =
              column.cellBuilder?.call(row) ??
              Text(
                '${row[column.keyName] ?? ''}',
                overflow: TextOverflow.ellipsis,
              );
          return DataCell(cell);
        }).toList(),
      );
    });
  }
}
