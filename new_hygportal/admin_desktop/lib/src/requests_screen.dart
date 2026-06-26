part of '../main.dart';

// ── Header ──────────────────────────────────────────────────────────────────

class RequestsHeader extends StatelessWidget {
  const RequestsHeader({required this.onRefresh, super.key});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kicker('Admin Control Center'),
              const SizedBox(height: 4),
              Text(
                'All Employee Requests',
                style: HygTypography.pageTitle,
              ),
              const SizedBox(height: 2),
              Text(
                'View and monitor ESARF, Leave, and Perk requests across the organisation.',
                style: HygTypography.body,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
        ),
      ],
    );
  }
}

// ── Tabbed Panel ────────────────────────────────────────────────────────────

class RequestsPanel extends StatefulWidget {
  const RequestsPanel({
    required this.requests,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    this.onDeleteRequest,
    this.showDeleteAction = true,
    super.key,
  });

  final List<AdminRequestItem> requests;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<String> Function(String requestId, bool isPerk)? onDeleteRequest;
  final bool showDeleteAction;

  @override
  State<RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<RequestsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _searchQuery = '';
  String _statusFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const _tabs = ['ESARF / Time', 'Leave', 'Perks'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<AdminRequestItem> _itemsForTab(int tabIndex) {
    final category = switch (tabIndex) {
      0 => AdminRequestCategory.esarf,
      1 => AdminRequestCategory.leave,
      _ => AdminRequestCategory.perk,
    };

    var items = widget.requests
        .where((r) => r.category == category)
        .toList(growable: false);

    if (_statusFilter != 'all') {
      items = items
          .where((r) => r.status.toLowerCase() == _statusFilter)
          .toList(growable: false);
    }

    if (_dateFrom != null || _dateTo != null) {
      items = items.where((r) {
        if (r.submittedAt == null || r.submittedAt!.isEmpty) return false;
        try {
          final dt = DateTime.parse(r.submittedAt!).toUtc();
          final submitted = DateTime(dt.year, dt.month, dt.day);
          if (_dateFrom != null && submitted.isBefore(_dateFrom!)) return false;
          if (_dateTo != null && submitted.isAfter(_dateTo!)) return false;
          return true;
        } catch (_) {
          return false;
        }
      }).toList(growable: false);
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((r) {
        return (r.employeeName ?? '').toLowerCase().contains(q) ||
            (r.employeeNo ?? '').toLowerCase().contains(q) ||
            (r.departmentName ?? '').toLowerCase().contains(q) ||
            (r.storeName ?? '').toLowerCase().contains(q) ||
            r.requestTypeName.toLowerCase().contains(q) ||
            (r.leaveCategory ?? '').toLowerCase().contains(q) ||
            (r.perkProductName ?? '').toLowerCase().contains(q) ||
            (r.reason ?? '').toLowerCase().contains(q);
      }).toList(growable: false);
    }

    return items;
  }

  int _countForTab(int tabIndex) {
    final category = switch (tabIndex) {
      0 => AdminRequestCategory.esarf,
      1 => AdminRequestCategory.leave,
      _ => AdminRequestCategory.perk,
    };
    return widget.requests.where((r) => r.category == category).length;
  }

  // ── Action helpers ──────────────────────────────────────────────────────

  bool _isPerk(AdminRequestItem item) =>
      item.category == AdminRequestCategory.perk;

  Future<void> _confirmDelete(AdminRequestItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFF97316),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Delete request?',
                            style: TextStyle(
                              color: HygColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'This action cannot be undone.',
                            style: HygTypography.body.copyWith(
                              color: const Color(0xFF475569),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          RichText(
                            text: TextSpan(
                              style: HygTypography.body.copyWith(
                                color: HygColors.ink,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Are you sure you want to delete the request from ',
                                ),
                                TextSpan(
                                  text: '"${item.employeeName ?? 'Unknown'}"',
                                  style: const TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const TextSpan(text: '?'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    border: Border.all(color: const Color(0xFFDCE7F3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: Color(0xFF2563EB),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.requestTypeName,
                          style: HygTypography.body.copyWith(
                            color: const Color(0xFF475569),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'What happens next?',
                  style: TextStyle(
                    color: HygColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                const _DeleteBullet(
                  'The request and its details will be permanently removed.',
                ),
                const SizedBox(height: 7),
                const _DeleteBullet(
                  'Employee profiles and history remain unchanged.',
                ),
                const SizedBox(height: 7),
                const _DeleteBullet(
                  'Approval records linked to this request will also be deleted.',
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 102,
                        height: 40,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: HygColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 184,
                        height: 40,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text(
                            'Delete Request',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    final msg = widget.onDeleteRequest != null
        ? await widget.onDeleteRequest!(item.requestId, _isPerk(item))
        : 'Delete not configured.';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          msg.toLowerCase().contains('fail') ? const Color(0xFFB91C1C) : null,
      duration: const Duration(seconds: 3),
    ));
    widget.onRefresh();
  }

  // ── Excel export ──────────────────────────────────────────────────────

  Future<void> _downloadExcel() async {
    final tabIndex = _tabController.index;
    final items = _itemsForTab(tabIndex);

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export for the current filters.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final tabLabel = _tabs[tabIndex];
    final now = DateTime.now();
    final dateTag =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final defaultFileName =
        'Requests_${tabLabel.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_$dateTag.xlsx';

    // Rename sheet to tab name (sanitized to meet Excel worksheet name constraints)
    String sanitizedSheetName = tabLabel.replaceAll(RegExp(r'[\\/?*\[\]:]'), '_');
    if (sanitizedSheetName.length > 31) {
      sanitizedSheetName = sanitizedSheetName.substring(0, 31);
    }

    // ── build workbook ──────────────────────────────────────────────────
    final excel = Excel.createExcel();
    final sheet = excel.getDefaultSheet()!;
    excel.rename(sheet, sanitizedSheetName);
    final sheetObj = excel.sheets[sanitizedSheetName]!;

    // Styles
    final stripeBg = ExcelColor.fromHexString('#F8FAFC');

    // Header styling: Sleek dark navy matching HygColors.ink
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#071426'),
      fontFamily: 'Segoe UI',
      fontSize: 11,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Standard alignments (Segoe UI for premium feel)
    final dataStyleLeft = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );
    final dataStyleLeftStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      backgroundColorHex: stripeBg,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );

    final dataStyleCenter = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final dataStyleCenterStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      backgroundColorHex: stripeBg,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final dataStyleRight = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );
    final dataStyleRightStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      backgroundColorHex: stripeBg,
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );

    // Numeric formats
    final dataStyleDecimal = dataStyleRight.copyWith(numberFormat: NumFormat.standard_2);
    final dataStyleDecimalStripe = dataStyleRightStripe.copyWith(numberFormat: NumFormat.standard_2);

    final dataStyleCurrency = dataStyleRight.copyWith(numberFormat: NumFormat.standard_4);
    final dataStyleCurrencyStripe = dataStyleRightStripe.copyWith(numberFormat: NumFormat.standard_4);

    final dataStyleInteger = dataStyleRight.copyWith(numberFormat: NumFormat.standard_3);
    final dataStyleIntegerStripe = dataStyleRightStripe.copyWith(numberFormat: NumFormat.standard_3);

    // Bold numeric formats
    final dataStyleDecimalBold = dataStyleRight.copyWith(boldVal: true, numberFormat: NumFormat.standard_2);
    final dataStyleDecimalStripeBold = dataStyleRightStripe.copyWith(boldVal: true, numberFormat: NumFormat.standard_2);

    final dataStyleCurrencyBold = dataStyleRight.copyWith(boldVal: true, numberFormat: NumFormat.standard_4);
    final dataStyleCurrencyStripeBold = dataStyleRightStripe.copyWith(boldVal: true, numberFormat: NumFormat.standard_4);

    // Status styles: soft background colors with dark text
    final approvedStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#166534'),
      backgroundColorHex: ExcelColor.fromHexString('#DCFCE7'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final approvedStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#166534'),
      backgroundColorHex: ExcelColor.fromHexString('#D1FAE5'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final pendingStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#9A3412'),
      backgroundColorHex: ExcelColor.fromHexString('#FEF3C7'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final pendingStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#9A3412'),
      backgroundColorHex: ExcelColor.fromHexString('#FDE68A'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final rejectedStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#991B1B'),
      backgroundColorHex: ExcelColor.fromHexString('#FEE2E2'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final rejectedStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#991B1B'),
      backgroundColorHex: ExcelColor.fromHexString('#FCA5A5'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final defaultStatusStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#374151'),
      backgroundColorHex: ExcelColor.fromHexString('#F3F4F6'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final defaultStatusStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#374151'),
      backgroundColorHex: ExcelColor.fromHexString('#E5E7EB'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    CellStyle getStatusStyle(String status, bool isStripe) {
      final s = status.toLowerCase();
      if (s.contains('approved')) {
        return isStripe ? approvedStyleStripe : approvedStyle;
      } else if (s.contains('pending') || s.contains('needs review')) {
        return isStripe ? pendingStyleStripe : pendingStyle;
      } else if (s.contains('rejected')) {
        return isStripe ? rejectedStyleStripe : rejectedStyle;
      } else {
        return isStripe ? defaultStatusStyleStripe : defaultStatusStyle;
      }
    }

    String getStatusWithEmoji(String status) {
      final s = status.toLowerCase();
      if (s.contains('approved')) {
        return '🟢 Approved';
      } else if (s.contains('pending') || s.contains('needs review')) {
        return '🟡 Pending';
      } else if (s.contains('rejected')) {
        return '🔴 Rejected';
      } else if (s.contains('cancelled') || s.contains('canceled')) {
        return '⚪ Cancelled';
      } else {
        return '⚪ $status';
      }
    }

    // Column headers by category (Reason is removed, it will be a sub-row)
    final List<String> headers;
    switch (tabIndex) {
      case 0: // ESARF
        headers = [
          'Employee No', 'Employee Name', 'Department', 'Store',
          'Request Type', 'Status', 'Date', 'Time',
          'Total Hours', 'Submitted',
        ];
        break;
      case 1: // Leave
        headers = [
          'Employee No', 'Employee Name', 'Department', 'Store',
          'Leave Type', 'Leave Category', 'Date', 'Total Days',
          'Paid Days', 'Unpaid Days', 'Status', 'Submitted',
        ];
        break;
      default: // Perk
        headers = [
          'Employee No', 'Employee Name', 'Department', 'Store',
          'Product', 'Quantity', 'Amount', 'Discount', 'Final Amount',
          'Benefit', 'Status', 'Submitted',
        ];
    }

    // Local helper to style and merge a range of cells
    void styleRange({
      required int startCol,
      required int startRow,
      required int endCol,
      required int endRow,
      required CellStyle cellStyle,
      bool merge = false,
      CellValue? value,
    }) {
      for (int r = startRow; r <= endRow; r++) {
        for (int c = startCol; c <= endCol; c++) {
          excel.updateCell(
            sanitizedSheetName,
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
            (r == startRow && c == startCol) ? (value ?? TextCellValue('')) : TextCellValue(''),
            cellStyle: cellStyle,
          );
        }
      }
      if (merge && (startCol != endCol || startRow != endRow)) {
        excel.merge(
          sanitizedSheetName,
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: startRow),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: endRow),
        );
      }
    }

    // Helper functions for date formatting
    String formatDateStr(DateTime dt) {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }

    String getDateSubtitle(DateTime dt) {
      if (_dateFrom != null && _dateTo != null) {
        return '${formatDateStr(_dateFrom!)} - ${formatDateStr(_dateTo!)}';
      } else if (_dateFrom != null) {
        return 'From ${formatDateStr(_dateFrom!)} onwards';
      } else if (_dateTo != null) {
        return 'Until ${formatDateStr(_dateTo!)}';
      } else {
        // Current month date range as default
        final start = DateTime(dt.year, dt.month, 1);
        final end = DateTime(dt.year, dt.month + 1, 0);
        return '${formatDateStr(start)} - ${formatDateStr(end)}';
      }
    }

    String formatRange(String? from, String? to) {
      if ((from == null || from.isEmpty) && (to == null || to.isEmpty)) return '';
      if (from != null && from.isNotEmpty && to != null && to.isNotEmpty) {
        if (from == to) return from;
        return '$from - $to';
      }
      final val = (from != null && from.isNotEmpty) ? from : to;
      return val ?? '';
    }

    String format12HourTime(String? timeStr) {
      if (timeStr == null || timeStr.trim().isEmpty) return '';
      try {
        final parts = timeStr.trim().split(':');
        if (parts.isEmpty) return timeStr;
        int hour = int.parse(parts[0]);
        int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
        
        String period = 'AM';
        if (hour >= 12) {
          period = 'PM';
          if (hour > 12) {
            hour -= 12;
          }
        } else if (hour == 0) {
          hour = 12;
        }
        
        final minStr = minute.toString().padLeft(2, '0');
        return '$hour:$minStr $period';
      } catch (_) {
        return timeStr;
      }
    }

    // ── 1. Write Title Block (Rows 0 & 1) ───────────────────────────────────
    final titleStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 16,
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#071426'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final subtitleStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 11,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#E2B93B'), // Elegant gold
      backgroundColorHex: ExcelColor.fromHexString('#071426'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    styleRange(
      startCol: 0,
      startRow: 0,
      endCol: headers.length - 1,
      endRow: 0,
      cellStyle: titleStyle,
      merge: true,
      value: TextCellValue('EMPLOYEE SALARY ADJUSTMENT REQUEST FORM (ESARF)'),
    );
    sheetObj.setRowHeight(0, 35.0);

    styleRange(
      startCol: 0,
      startRow: 1,
      endCol: headers.length - 1,
      endRow: 1,
      cellStyle: subtitleStyle,
      merge: true,
      value: TextCellValue(getDateSubtitle(now)),
    );
    sheetObj.setRowHeight(1, 24.0);

    // Empty Spacer Row 2
    sheetObj.setRowHeight(2, 15.0);

    // ── 4. Write Table Headers (Row 3) ──────────────────────────────────────
    for (var c = 0; c < headers.length; c++) {
      excel.updateCell(
        sanitizedSheetName,
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 3),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
    }
    sheetObj.setRowHeight(3, 22.0);

    // Helper to extract values
    List<CellValue?> getRowValues(int tIndex, AdminRequestItem item) {
      switch (tIndex) {
        case 0: // ESARF
          final dateFromStr = _formatDateString(item.dateFrom);
          final dateToStr = _formatDateString(item.dateTo);
          final dateRange = formatRange(dateFromStr, dateToStr);
          final timeFromStr = format12HourTime(item.timeFrom);
          final timeToStr = format12HourTime(item.timeTo);
          final timeRange = formatRange(timeFromStr, timeToStr);
          return [
            item.employeeNo != null ? TextCellValue(item.employeeNo!) : null,
            item.employeeName != null ? TextCellValue(item.employeeName!) : null,
            item.departmentName != null ? TextCellValue(item.departmentName!) : null,
            item.storeName != null ? TextCellValue(item.storeName!) : null,
            TextCellValue(item.requestTypeName),
            TextCellValue(item.statusLabel),
            TextCellValue(dateRange),
            TextCellValue(timeRange),
            item.totalHours != null ? DoubleCellValue(item.totalHours!) : null,
            item.submittedAt != null ? TextCellValue(_formatDateString(item.submittedAt, includeTime: true)!) : null,
          ];
        case 1: // Leave
          final dateRange = formatRange(_formatDateString(item.startDate), _formatDateString(item.endDate));
          return [
            item.employeeNo != null ? TextCellValue(item.employeeNo!) : null,
            item.employeeName != null ? TextCellValue(item.employeeName!) : null,
            item.departmentName != null ? TextCellValue(item.departmentName!) : null,
            item.storeName != null ? TextCellValue(item.storeName!) : null,
            item.leaveType != null ? TextCellValue(item.leaveType!) : null,
            item.leaveCategory != null ? TextCellValue(item.leaveCategory!) : null,
            TextCellValue(dateRange),
            item.totalDays != null ? DoubleCellValue(item.totalDays!) : null,
            item.paidDays != null ? DoubleCellValue(item.paidDays!) : null,
            item.unpaidDays != null ? DoubleCellValue(item.unpaidDays!) : null,
            TextCellValue(item.statusLabel),
            item.submittedAt != null ? TextCellValue(_formatDateString(item.submittedAt, includeTime: true)!) : null,
          ];
        default: // Perk
          return [
            item.employeeNo != null ? TextCellValue(item.employeeNo!) : null,
            item.employeeName != null ? TextCellValue(item.employeeName!) : null,
            item.departmentName != null ? TextCellValue(item.departmentName!) : null,
            item.storeName != null ? TextCellValue(item.storeName!) : null,
            item.perkProductName != null ? TextCellValue(item.perkProductName!) : null,
            item.perkQuantity != null ? IntCellValue(item.perkQuantity!) : null,
            item.perkAmount != null ? DoubleCellValue(item.perkAmount!) : null,
            item.perkDiscountAmount != null ? DoubleCellValue(item.perkDiscountAmount!) : null,
            item.perkFinalAmount != null ? DoubleCellValue(item.perkFinalAmount!) : null,
            item.perkBenefit != null ? TextCellValue(item.perkBenefit!) : null,
            TextCellValue(item.statusLabel),
            item.submittedAt != null ? TextCellValue(_formatDateString(item.submittedAt, includeTime: true)!) : null,
          ];
      }
    }

    final centerCols = {'Employee No', 'Status', 'Date', 'Time', 'Submitted'};
    final currencyCols = {'Amount', 'Discount', 'Final Amount'};
    final decimalCols = {'Total Hours', 'Total Days', 'Paid Days', 'Unpaid Days'};
    final integerCols = {'Quantity'};

    // ── 5. Write Data Rows (Row 4+) ─────────────────────────────────────────
    int currentRow = 4;
    for (var r = 0; r < items.length; r++) {
      final item = items[r];
      final isStripe = r % 2 == 1;
      final values = getRowValues(tabIndex, item);

      // A. Write Main Request Row
      for (var c = 0; c < values.length; c++) {
        final colName = headers[c];
        
        CellStyle cellStyle;
        if (colName == 'Status') {
          cellStyle = getStatusStyle(item.statusLabel, isStripe);
        } else if (colName == 'Total Hours' || colName == 'Total Days') {
          cellStyle = isStripe ? dataStyleDecimalStripeBold : dataStyleDecimalBold;
        } else if (colName == 'Final Amount') {
          cellStyle = isStripe ? dataStyleCurrencyStripeBold : dataStyleCurrencyBold;
        } else if (currencyCols.contains(colName)) {
          cellStyle = isStripe ? dataStyleCurrencyStripe : dataStyleCurrency;
        } else if (decimalCols.contains(colName)) {
          cellStyle = isStripe ? dataStyleDecimalStripe : dataStyleDecimal;
        } else if (integerCols.contains(colName)) {
          cellStyle = isStripe ? dataStyleIntegerStripe : dataStyleInteger;
        } else if (centerCols.contains(colName)) {
          cellStyle = isStripe ? dataStyleCenterStripe : dataStyleCenter;
        } else {
          cellStyle = isStripe ? dataStyleLeftStripe : dataStyleLeft;
        }

        CellValue cellValue = values[c] ?? TextCellValue('');
        if (colName == 'Status') {
          cellValue = TextCellValue(getStatusWithEmoji(item.statusLabel));
        }

        excel.updateCell(
          sanitizedSheetName,
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: currentRow),
          cellValue,
          cellStyle: cellStyle,
        );
      }
      sheetObj.setRowHeight(currentRow, 20.0);
      currentRow++;

      // B. Write Detail Reason Row
      final reasonBg = isStripe ? stripeBg : ExcelColor.white;
      final reasonStyle = CellStyle(
        fontFamily: 'Segoe UI',
        fontSize: 9,
        italic: true,
        fontColorHex: ExcelColor.fromHexString('#64748B'),
        backgroundColorHex: reasonBg,
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );

      final String reasonVal = item.reason != null && item.reason!.isNotEmpty
          ? 'Reason: ${item.reason}'
          : 'Reason: No reason provided';

      styleRange(
        startCol: 0,
        startRow: currentRow,
        endCol: headers.length - 1,
        endRow: currentRow,
        cellStyle: reasonStyle,
        merge: true,
        value: TextCellValue(reasonVal),
      );
      sheetObj.setRowHeight(currentRow, 18.0);
      currentRow++;
    }

    // ── 6. Dynamic Column widths calculation ────────────────────────────────
    final maxColWidths = List<int>.generate(headers.length, (c) => headers[c].length + 4);

    for (var r = 0; r < items.length; r++) {
      final item = items[r];
      final values = getRowValues(tabIndex, item);
      for (var c = 0; c < values.length; c++) {
        final colName = headers[c];
        String valStr = '';
        if (colName == 'Status') {
          valStr = getStatusWithEmoji(item.statusLabel);
        } else {
          valStr = values[c]?.toString() ?? '';
        }
        final valLen = valStr.length;
        if (valLen + 3 > maxColWidths[c]) {
          maxColWidths[c] = valLen + 3;
        }
      }
    }

    for (var c = 0; c < headers.length; c++) {
      double width = maxColWidths[c].toDouble();
      if (width < 12.0) width = 12.0;
      if (width > 45.0) width = 45.0; // clamp overly long text to keep layout neat
      sheetObj.setColumnWidth(c, width);
    }

    final encodedBytes = excel.encode();
    if (encodedBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to generate Excel file.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Post-process ZIP bytes to remove unused drawing definitions and prevent corruption warning in MS Excel
    final fixedBytesList = _postProcessExcelBytes(encodedBytes);
    final fileBytes = Uint8List.fromList(fixedBytesList);

    // ── save via file picker ──────────────────────────────────────────
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save Excel file',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: fileBytes,
    );

    if (!mounted) return;
    if (savePath == null) return; // user cancelled

    try {
      // On desktop, bytes are already written by file_picker.
      // Verify the file exists.
      final fileExists = await File(savePath).exists();
      if (!fileExists) {
        await File(savePath).writeAsBytes(fileBytes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to: $savePath'),
          backgroundColor: const Color(0xFF166534),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Open folder',
            textColor: Colors.white,
            onPressed: () {
              Process.run('explorer', ['/select,', savePath]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: const Color(0xFFB91C1C),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String? _formatDateString(String? dateStr, {bool includeTime = false}) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      if (includeTime) {
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return '$y-$m-$d $hh:$mm';
      }
      return '$y-$m-$d';
    } catch (_) {
      return dateStr;
    }
  }

  List<int> _postProcessExcelBytes(List<int> encodedBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(encodedBytes);
      final outArchive = Archive();
      
      for (final file in archive.files) {
        if (file.name == '[Content_Types].xml') {
          final contentBytes = file.content as List<int>;
          final xmlContent = utf8.decode(contentBytes);
          final fixedXml = xmlContent.replaceAll(
            RegExp(r'<Override[^>]*drawing1\.xml[^>]*/>'),
            '',
          );
          final fixedBytes = utf8.encode(fixedXml);
          outArchive.addFile(ArchiveFile(file.name, fixedBytes.length, fixedBytes));
        } else if (file.name.startsWith('xl/worksheets/_rels/') ||
                   file.name.startsWith('xl/drawings/')) {
          continue;
        } else {
          outArchive.addFile(file);
        }
      }
      
      final fixed = ZipEncoder().encode(outArchive);
      return fixed ?? encodedBytes;
    } catch (_) {
      return encodedBytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const _RequestsLoadingCard();
    }

    if (widget.error != null) {
      return _RequestsErrorCard(
        message: widget.error!,
        onRetry: widget.onRefresh,
      );
    }

    final tabIndex = _tabController.index;
    final items = _itemsForTab(tabIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: HygColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: HygColors.gold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: HygColors.ink,
                      unselectedLabelColor: HygColors.muted,
                      labelStyle: HygTypography.tableHeader.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: HygTypography.tableHeader.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: [
                        for (int i = 0; i < _tabs.length; i++)
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(_tabs[i]),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _tabController.index == i
                                        ? HygColors.ink.withValues(alpha: 0.12)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '${_countForTab(i)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _tabController.index == i
                                          ? HygColors.ink
                                          : HygColors.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: HygTypography.input.copyWith(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search employee, department, store, type…',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                        filled: true,
                        fillColor: HygColors.background,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                          borderSide:
                              const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    onChanged: (v) =>
                        setState(() => _statusFilter = v ?? 'all'),
                    style: HygTypography.tableBody,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: HygColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide:
                            const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(
                          value: 'approved', child: Text('Approved')),
                      DropdownMenuItem(
                          value: 'rejected', child: Text('Rejected')),
                      DropdownMenuItem(
                          value: 'cancelled', child: Text('Cancelled')),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Date submitted filter + Download Excel ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(
              children: [
                const Icon(Icons.date_range, size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('Submitted:',
                    style: HygTypography.tableHeader
                        .copyWith(color: const Color(0xFF64748B))),
                const SizedBox(width: 8),
                _DateRangePill(
                  dateFrom: _dateFrom,
                  dateTo: _dateTo,
                  onPick: () async {
                    final result = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: _dateFrom != null && _dateTo != null
                          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
                          : null,
                      initialEntryMode: DatePickerEntryMode.calendar,
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF1E40AF),
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: HygColors.ink,
                            ),
                          ),
                          child: UnconstrainedBox(
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: 400,
                              height: 520,
                              child: child,
                            ),
                          ),
                        );
                      },
                    );
                    if (result != null) {
                      setState(() {
                        _dateFrom = result.start;
                        _dateTo = result.end;
                      });
                    }
                  },
                ),
                if (_dateFrom != null || _dateTo != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Clear dates',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: _downloadExcel,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF166534),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
              child: EmployeesStateMessage(
                icon: Icons.inbox_outlined,
                title: 'No requests found',
                message: _searchQuery.isNotEmpty ||
                        _statusFilter != 'all' ||
                        _dateFrom != null ||
                        _dateTo != null
                    ? 'Try adjusting your filters.'
                    : 'No requests in this category yet.',
              ),
            )
          else
            _RequestsTable(
              items: items,
              category: switch (tabIndex) {
                0 => AdminRequestCategory.esarf,
                1 => AdminRequestCategory.leave,
                _ => AdminRequestCategory.perk,
              },
              showDelete: widget.showDeleteAction,
              onDelete: _confirmDelete,
            ),
        ],
      ),
    );
  }
}

// ── Loading ─────────────────────────────────────────────────────────────────

class _RequestsLoadingCard extends StatelessWidget {
  const _RequestsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: HygColors.gold),
      ),
    );
  }
}

// ── Error ───────────────────────────────────────────────────────────────────

class _RequestsErrorCard extends StatelessWidget {
  const _RequestsErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: EmployeesStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load requests',
        message: message,
        actionLabel: 'Retry',
        onAction: onRetry,
      ),
    );
  }
}

// ── Date-range pill ─────────────────────────────────────────────────────────

class _DateRangePill extends StatelessWidget {
  const _DateRangePill({
    required this.dateFrom,
    required this.dateTo,
    required this.onPick,
  });
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final VoidCallback onPick;

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final isActive = dateFrom != null && dateTo != null;
    final label = isActive
        ? '${_fmt(dateFrom!)}  –  ${_fmt(dateTo!)}'
        : 'Pick date range';

    return GestureDetector(
      onTap: onPick,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFDBEAFE) : HygColors.background,
          border: Border.all(
            color: isActive ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range,
              size: 15,
              color: isActive ? const Color(0xFF1E40AF) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF1E40AF) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Table ───────────────────────────────────────────────────────────────────

class _RequestsTable extends StatelessWidget {
  const _RequestsTable({
    required this.items,
    required this.category,
    required this.onDelete,
    required this.showDelete,
  });

  final List<AdminRequestItem> items;
  final AdminRequestCategory category;
  final void Function(AdminRequestItem) onDelete;
  final bool showDelete;

  static const double _storeWidth = 92;
  static const double _reasonWidth = 180;
  static const double _productWidth = 160;

  String _storeLabel(String? storeName) {
    final value = storeName?.trim();
    if (value == null || value.isEmpty) return 'N/A';
    return value;
  }

  Widget _limitedText(
    String value, {
    double width = 120,
    int maxLines = 1,
    bool wrap = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: wrap,
      ),
    );
  }

  DataCell _storeCell(AdminRequestItem item) {
    final store = _storeLabel(item.storeName);

    return DataCell(
      Tooltip(
        message: store,
        child: _limitedText(
          store,
          width: _storeWidth,
          maxLines: 2,
          wrap: true,
        ),
      ),
    );
  }
  
  DataCell _reasonCell(String value) {
    return DataCell(
      Tooltip(
        message: value,
        child: _limitedText(
          value,
          width: _reasonWidth,
          maxLines: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: DataTable(
        headingRowHeight: 42,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 72,
        horizontalMargin: 12,
        columnSpacing: 12,
        headingTextStyle: HygTypography.tableHeader,
        dataTextStyle: HygTypography.tableBody,
        border: TableBorder.all(color: const Color(0xFFE2E8F0)),
        columns: _buildColumns(),
        rows: items.map((item) => _buildRow(item)).toList(),
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    switch (category) {
      case AdminRequestCategory.esarf:
        return [
          const DataColumn(label: Text('Employee')),
          const DataColumn(label: Text('Department')),
          const DataColumn(label: Text('Store')),
          const DataColumn(label: Text('Type')),
          const DataColumn(label: Text('Date From')),
          const DataColumn(label: Text('Date To')),
          const DataColumn(label: Text('Hours')),
          const DataColumn(label: Text('Reason')),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('Submitted')),
          if (showDelete) const DataColumn(label: Text('Actions')),
        ];
      case AdminRequestCategory.leave:
        return [
          const DataColumn(label: Text('Employee')),
          const DataColumn(label: Text('Department')),
          const DataColumn(label: Text('Store')),
          const DataColumn(label: Text('Leave Category')),
          const DataColumn(label: Text('Start')),
          const DataColumn(label: Text('End')),
          const DataColumn(label: Text('Days')),
          const DataColumn(label: Text('Type')),
          const DataColumn(label: Text('Reason')),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('Submitted')),
          if (showDelete) const DataColumn(label: Text('Actions')),
        ];
      case AdminRequestCategory.perk:
        return [
          const DataColumn(label: Text('Employee')),
          const DataColumn(label: Text('Department')),
          const DataColumn(label: Text('Store')),
          const DataColumn(label: Text('Type')),
          const DataColumn(label: Text('Product')),
          const DataColumn(label: Text('Qty')),
          const DataColumn(label: Text('Amount')),
          const DataColumn(label: Text('Final')),
          const DataColumn(label: Text('Txn Date')),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('Submitted')),
          if (showDelete) const DataColumn(label: Text('Actions')),
        ];
    }
  }

  DataRow _buildRow(AdminRequestItem item) {
    switch (category) {
      case AdminRequestCategory.esarf:
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? '—')),
          _storeCell(item),
          DataCell(Text(item.requestTypeName)),
          DataCell(Text(item.dateFrom ?? '—')),
          DataCell(Text(item.dateTo ?? '—')),
          DataCell(Text(item.totalHours != null ? '${item.totalHours}h' : '—')),
          _reasonCell(item.reason ?? item.timeSchedule ?? '—'),
          _statusCell(item),
          _submittedCell(item),
          if (showDelete) _actionsCell(item),
        ]);

      case AdminRequestCategory.leave:
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? '—')),
          _storeCell(item),
          DataCell(Text(item.leaveCategory ?? '—')),
          DataCell(Text(item.startDate ?? '—')),
          DataCell(Text(item.endDate ?? '—')),
          DataCell(Text(item.totalDays != null ? '${item.totalDays}d' : '—')),
          DataCell(Text(item.leaveType ?? '—')),
          _reasonCell(item.reason ?? '—'),
          _statusCell(item),
          _submittedCell(item),
          if (showDelete) _actionsCell(item),
        ]);

      case AdminRequestCategory.perk:
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? '—')),
          _storeCell(item),
          DataCell(Text(
            item.requestTypeCode == 'discount' ? 'Discount' : 'Charge',
          )),
          DataCell(
            Tooltip(
              message: item.perkProductName ?? '—',
              child: _limitedText(
                item.perkProductName ?? '—',
                width: _productWidth,
                maxLines: 2,
              ),
            ),
          ),
          DataCell(Text('${item.perkQuantity ?? 0}')),
          DataCell(Text(
            item.perkAmount != null
                ? '₱${item.perkAmount!.toStringAsFixed(2)}'
                : '—',
          )),
          DataCell(Text(
            item.perkFinalAmount != null
                ? '₱${item.perkFinalAmount!.toStringAsFixed(2)}'
                : '—',
          )),
          DataCell(Text(item.dateFrom ?? '—')),
          _statusCell(item),
          _submittedCell(item),
          if (showDelete) _actionsCell(item),
        ]);
    }
  }

  DataCell _employeeCell(AdminRequestItem item) {
    return DataCell(
      SizedBox(
        width: 180,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFE2E8F0),
              child: Text(
                (item.employeeName ?? '?').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: HygColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.employeeName ?? 'Unknown',
                    style: HygTypography.tablePrimary,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.employeeNo != null)
                    Text(
                      item.employeeNo!,
                      style: HygTypography.tableMuted,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataCell _statusCell(AdminRequestItem item) {
    final color = switch (item.status.toLowerCase()) {
      'approved' => const Color(0xFF166534),
      'rejected' => const Color(0xFFB91C1C),
      'cancelled' => const Color(0xFF64748B),
      'needs_admin_review' => const Color(0xFFB45309),
      _ => const Color(0xFF1E40AF),
    };

    final bgColor = switch (item.status.toLowerCase()) {
      'approved' => const Color(0xFFDCFCE7),
      'rejected' => const Color(0xFFFEE2E2),
      'cancelled' => const Color(0xFFF1F5F9),
      'needs_admin_review' => const Color(0xFFFEF3C7),
      _ => const Color(0xFFDBEAFE),
    };

    return DataCell(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          item.statusLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  DataCell _submittedCell(AdminRequestItem item) {
    final raw = item.submittedAt;

    if (raw == null || raw.isEmpty) {
      return const DataCell(Text('—'));
    }

    try {
      final dt = DateTime.parse(raw);
      final ph = dt.toUtc().add(const Duration(hours: 8));
      final label =
          '${ph.month}/${ph.day}/${ph.year} ${ph.hour.toString().padLeft(2, '0')}:${ph.minute.toString().padLeft(2, '0')}';

      return DataCell(Text(label, style: HygTypography.tableMuted));
    } catch (_) {
      return DataCell(Text(raw, style: HygTypography.tableMuted));
    }
  }

  DataCell _actionsCell(AdminRequestItem item) {
    return DataCell(
      Tooltip(
        message: 'Delete request',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onDelete(item),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.delete_outline,
              size: 16,
              color: Color(0xFFB91C1C),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteBullet extends StatelessWidget {
  const _DeleteBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF65A30D),
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}