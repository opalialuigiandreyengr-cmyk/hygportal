part of '../main.dart';

/// Formats a 24-hour time string (e.g. "14:30:00" or "08:00") into 12-hour format ("2:30 PM", "8:00 AM").
/// Used by both the UI Data Table and Excel Export to display human-readable time bounds.
String _format12HourTime(String? timeStr) {
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

/// Normalizes ESARF transaction type strings into standardized short abbreviations for UI uniformity.
/// Examples: "Overtime" -> "OT", "Official Business" -> "OB", "Failure to Punch In/Out" -> "FIO".
String _formatEsarfTransactionAbbr(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Ã¢â‚¬â€';
  final text = raw.trim();
  final lower = text.toLowerCase();

  if (lower == 'ot' || lower.contains('overtime')) return 'OT';
  if (lower == 'ut' || lower.contains('undertime')) return 'UT';
  if (lower == 'ob' || lower.contains('official business')) return 'OB';
  if (lower == 'fio' || lower.contains('failure to punch')) return 'FIO';
  if (lower == 'cs' || lower.contains('change schedule') || lower.contains('schedule change')) return 'CS';
  if (lower == 'use offset' || lower.contains('use offset') || lower == 'uo') return 'Use Offset';
  if (lower == 'offset') return 'Offset';
  if (lower == 'adjustment' || lower.contains('adjustment')) return 'Adj';
  
  if (text.length <= 4) return text.toUpperCase();

  return text;
}

/// Formats a numeric days value (e.g. 1.0 -> "1d", 1.5 -> "1.5d", 0 -> "0d").
String _formatDaysNum(double? d) {
  if (d == null) return '0d';
  if (d == d.roundToDouble()) {
    return '${d.toInt()}d';
  }
  return '${d}d';
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

// Ã¢â€â‚¬Ã¢â€â‚¬ Tabbed Panel Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
  bool _isRefreshingApprovers = false;

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
            (r.reason ?? '').toLowerCase().contains(q) ||
            r.approverNames.toLowerCase().contains(q);
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

  // Ã¢â€â‚¬Ã¢â€â‚¬ Action helpers Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  bool _isPerk(AdminRequestItem item) =>
      item.category == AdminRequestCategory.perk;

  Future<void> _validateLeave(AdminRequestItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ValidateLeaveDialogContent(
        item: item,
        onConfirm: (paid, unpaid) async {
          await AdminRequestsService.validateLeaveRequest(
            requestId: item.requestId,
            newPaidDays: paid,
            newUnpaidDays: unpaid,
            oldPaidDays: item.paidDays ?? 0.0,
            userProfileId: item.userProfileId,
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request validated and credits adjusted successfully!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      widget.onRefresh();
    }
  }

  Future<void> _openReassignApproverDialog(
    AdminRequestItem item, {
    String? stepId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReassignApproverDialog(
        item: item,
        stepId: stepId,
      ),
    );
    if (result == true) {
      widget.onRefresh();
    }
  }

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

  Future<void> _refreshAssignedApprovers() async {
    setState(() => _isRefreshingApprovers = true);
    try {
      final msg = await AdminRequestsService.refreshAssignedApprovers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor:
            msg.toLowerCase().contains('fail') ? const Color(0xFFB91C1C) : const Color(0xFF166534),
        duration: const Duration(seconds: 4),
      ));
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to refresh approver assignments: $e'),
        backgroundColor: const Color(0xFFB91C1C),
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) {
        setState(() => _isRefreshingApprovers = false);
      }
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Excel export Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

    // Ã¢â€â‚¬Ã¢â€â‚¬ build workbook Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
        return 'Ã°Å¸Å¸Â¢ Approved';
      } else if (s.contains('pending') || s.contains('needs review')) {
        return 'Ã°Å¸Å¸Â¡ Pending';
      } else if (s.contains('rejected')) {
        return 'Ã°Å¸â€Â´ Rejected';
      } else if (s.contains('cancelled') || s.contains('canceled')) {
        return 'Ã¢Å¡Âª Cancelled';
      } else {
        return 'Ã¢Å¡Âª $status';
      }
    }

    // Column headers by category (Reason is removed, it will be a sub-row)
    final List<String> headers;
    switch (tabIndex) {
      case 0: // ESARF
        headers = [
          'Employee No', 'Employee Name', 'Department', 'Store',
          'Request Type', 'Status', 'Date', 'Time From', 'Time To',
          'Total Hours', 'Submitted',
        ];
        break;
      case 1: // Leave
        headers = [
          'Employee No', 'Employee Name', 'Department', 'Store',
          'Leave Type', 'Leave Category', 'Leave Credits', 'Date', 'Total Days',
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

    // Ã¢â€â‚¬Ã¢â€â‚¬ 1. Write Title Block (Rows 0 & 1) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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

    // Ã¢â€â‚¬Ã¢â€â‚¬ 4. Write Table Headers (Row 3) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
          // Format times for Excel export
          final timeFromStr = _format12HourTime(item.timeFrom);
          final timeToStr = _format12HourTime(item.timeTo);
          return [
            item.employeeNo != null ? TextCellValue(item.employeeNo!) : null,
            item.employeeName != null ? TextCellValue(item.employeeName!) : null,
            item.departmentName != null ? TextCellValue(item.departmentName!) : null,
            item.storeName != null ? TextCellValue(item.storeName!) : null,
            // Export abbreviated ESARF transaction type (OT, OB, FIO, CS, etc.)
            TextCellValue(
              _formatEsarfTransactionAbbr(
                (item.transactionType != null && item.transactionType!.isNotEmpty)
                    ? item.transactionType!
                    : item.requestTypeName,
              ),
            ),
            TextCellValue(item.statusLabel),
            TextCellValue(dateRange),
            // Export Time From and Time To in separate Excel columns
            TextCellValue(timeFromStr.isNotEmpty ? timeFromStr : 'Ã¢â‚¬â€'),
            TextCellValue(timeToStr.isNotEmpty ? timeToStr : 'Ã¢â‚¬â€'),
            item.totalHours != null ? DoubleCellValue(item.totalHours!) : null,
            item.submittedAt != null ? TextCellValue(_formatDateString(item.submittedAt, includeTime: true)!) : null,
          ];
        case 1: // Leave
          final dateRange = formatRange(_formatDateString(item.startDate), _formatDateString(item.endDate));
          final leaveTypeDisplay = (item.leaveType?.trim().toLowerCase() == 'both' || item.leaveType?.trim().toLowerCase() == 'with and without pay')
              ? 'Both (${_formatDaysNum(item.paidDays)} Paid, ${_formatDaysNum(item.unpaidDays)} Unpaid)'
              : (item.leaveType ?? 'Ã¢â‚¬â€');
          return [
            item.employeeNo != null ? TextCellValue(item.employeeNo!) : null,
            item.employeeName != null ? TextCellValue(item.employeeName!) : null,
            item.departmentName != null ? TextCellValue(item.departmentName!) : null,
            item.storeName != null ? TextCellValue(item.storeName!) : null,
            TextCellValue(leaveTypeDisplay),
            item.leaveCategory != null ? TextCellValue(item.leaveCategory!) : null,
            item.leaveCredits != null ? DoubleCellValue(item.leaveCredits!) : null,
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
    final decimalCols = {'Total Hours', 'Total Days', 'Paid Days', 'Unpaid Days', 'Leave Credits'};
    final integerCols = {'Quantity'};

    // Ã¢â€â‚¬Ã¢â€â‚¬ 5. Write Data Rows (Row 4+) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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

    // Ã¢â€â‚¬Ã¢â€â‚¬ 6. Dynamic Column widths calculation Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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

    // Ã¢â€â‚¬Ã¢â€â‚¬ save via file picker Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
                        hintText: 'Search employee, department, store, type...',
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

          // Ã¢â€â‚¬Ã¢â€â‚¬ Date submitted filter + Download Excel Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
                if (_tabController.index < _tabs.length && _tabs[_tabController.index] != 'Perks') ...[
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: _isRefreshingApprovers ? null : _refreshAssignedApprovers,
                      icon: _isRefreshingApprovers
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync, size: 16),
                      label: const Text('Refresh Assigned Approver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E40AF),
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
                  const SizedBox(width: 8),
                ],
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
              onReassign: (item, stepId) => _openReassignApproverDialog(item, stepId: stepId),
              onValidate: _validateLeave,
            ),

        ],
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Loading Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

// Ã¢â€â‚¬Ã¢â€â‚¬ Error Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

// Ã¢â€â‚¬Ã¢â€â‚¬ Date-range pill Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
        ? '${_fmt(dateFrom!)}  -  ${_fmt(dateTo!)}'
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

class _ApproverEntry {
  const _ApproverEntry({
    required this.name,
    required this.status,
    required this.level,
    this.stepId,
  });
  final String name;
  final String status;
  final String? level;
  final String? stepId;
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Table Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _RequestsTable extends StatelessWidget {
  const _RequestsTable({
    required this.items,
    required this.category,
    required this.onDelete,
    required this.showDelete,
    required this.onReassign,
    this.onValidate,
  });

  final List<AdminRequestItem> items;
  final AdminRequestCategory category;
  final void Function(AdminRequestItem) onDelete;
  final bool showDelete;
  final void Function(AdminRequestItem item, String? stepId) onReassign;
  final void Function(AdminRequestItem)? onValidate;

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

  DataCell _leaveTypeCell(AdminRequestItem item) {
    final leaveType = item.leaveType?.trim() ?? '';
    if (leaveType.isEmpty) {
      return const DataCell(Text('Ã¢â‚¬â€'));
    }

    if (leaveType.toLowerCase() == 'both' || leaveType.toLowerCase() == 'with and without pay') {
      final paidStr = _formatDaysNum(item.paidDays);
      final unpaidStr = _formatDaysNum(item.unpaidDays);
      final detail = '$paidStr Paid, $unpaidStr Unpaid';

      return DataCell(
        Tooltip(
          message: 'Both ($detail)',
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Both',
                style: HygTypography.tableBody.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$paidStr Paid • $unpaidStr Unpaid',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DataCell(Text(leaveType));
  }

  DataCell _approverCell(AdminRequestItem item) {
    final isBirthdayLeave = item.isAutoApprovedBirthdayGrant;

    if (isBirthdayLeave) {
      return DataCell(
        Tooltip(
          message: 'HYG Portal System (Auto-Approved)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF166534).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check, size: 16, color: Color(0xFF166534)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'HYG Portal System',
                    style: TextStyle(
                      color: Color(0xFF166534),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (item.approvalSummary.isEmpty) {
      final isPerk = item.category == AdminRequestCategory.perk;
      final isUnknownOrFallback = !isPerk &&
          (item.status.toLowerCase() == 'admin_fallback' ||
          item.status.toLowerCase() == 'needs_admin_review' ||
          item.approverNames.toLowerCase().contains('unknown'));

      if (isUnknownOrFallback) {
        return DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _limitedText('Ã¢â‚¬â€', width: 20, maxLines: 1),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => onReassign(item, null),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E40AF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF1E40AF).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.swap_horiz, size: 12, color: Color(0xFF1E40AF)),
                      SizedBox(width: 3),
                      Text(
                        'Reassign',
                        style: TextStyle(
                          color: Color(0xFF1E40AF),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return DataCell(
        Tooltip(
          message: 'Ã¢â‚¬â€',
          child: _limitedText('Ã¢â‚¬â€', width: 140, maxLines: 2),
        ),
      );
    }

    final entries = item.approvalSummary.map((entry) {
          final rawName = (entry['approver_name'] ?? entry['name'] ?? 'Unknown').toString().trim();
          final name = rawName.isEmpty ? 'Unknown' : rawName;
          final status = (entry['status'] ?? 'pending').toString().toLowerCase();
          final level = entry['level']?.toString();
          final stepId = (entry['step_id'] ?? entry['id'])?.toString();
          return _ApproverEntry(name: name, status: status, level: level, stepId: stepId);
        }).toList(growable: false);
    final highlights = _resolveHighlights(entries);

    return DataCell(
      Tooltip(
        message: item.approverDetail,
        child: SizedBox(
          width: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.map((entry) {
              final (icon, color) = _iconForStatus(entry.status);
              final isHighlighted = highlights.contains(entry);
              final isPerk = item.category == AdminRequestCategory.perk;
              final isEditableStatus = !isPerk &&
                  entry.status != 'approved' &&
                  entry.status != 'rejected' &&
                  entry.status != 'cancelled' &&
                  item.status.toLowerCase() != 'approved' &&
                  item.status.toLowerCase() != 'rejected' &&
                  item.status.toLowerCase() != 'cancelled';


              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: isHighlighted ? color.withValues(alpha: 0.12) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        entry.name,
                        style: HygTypography.tableBody.copyWith(
                          color: color,
                          fontSize: 11,
                          fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (isEditableStatus) ...[


                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => onReassign(item, entry.stepId),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E40AF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF1E40AF).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.swap_horiz, size: 12, color: Color(0xFF1E40AF)),
                              SizedBox(width: 3),
                              Text(
                                'Reassign',
                                style: TextStyle(
                                  color: Color(0xFF1E40AF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }


  (IconData icon, Color color) _iconForStatus(String status) {
    switch (status) {
      case 'approved':
      case 'validated':
        return (Icons.check, const Color(0xFF166534));
      case 'rejected':
      case 'cancelled':
        return (Icons.error_outline, const Color(0xFFB91C1C));
      case 'needs_admin_review':
        return (Icons.warning_amber_rounded, const Color(0xFFB45309));
      case 'pending':
      case 'waiting':
        return (Icons.access_time_rounded, const Color(0xFF1E40AF));
      default:
        return (Icons.warning_amber_rounded, const Color(0xFF1E40AF));
    }
  }


  Set<_ApproverEntry> _resolveHighlights(List<_ApproverEntry> entries) {
    if (entries.isEmpty) return const {};

    final sorted = entries.toList(growable: false);
    sorted.sort(
      (a, b) => _levelValue(a.level).compareTo(_levelValue(b.level)),
    );

    final result = <_ApproverEntry>{};

    final first = sorted.first;
    final firstMatch = entries.firstWhere(
        (e) => e.name == first.name && _levelValue(e.level) == _levelValue(first.level) && e.status == first.status,
    orElse: () => first);
    result.add(firstMatch);

    if (sorted.length > 1) {
      final last = sorted.last;
      final lastMatch = entries.firstWhere(
          (e) => e.name == last.name && _levelValue(e.level) == _levelValue(last.level) && e.status == last.status,
      orElse: () => last);
      result.add(lastMatch);
    }

    return result;
  }

  int _levelValue(String? level) {
    if (level == null) return 999999;
    final parsed = int.tryParse(level);
    if (parsed != null) return parsed;
    final normalized = level.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return -normalized;
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
          // Display uniform transaction abbreviation (OT, OB, FIO, UT, etc.)
          const DataColumn(label: Text('Type')),
          const DataColumn(label: Text('Date From')),
          const DataColumn(label: Text('Date To')),
          // Added explicit start and end time columns for admin duration visibility
          const DataColumn(label: Text('Time From')),
          const DataColumn(label: Text('Time To')),
          const DataColumn(label: Text('Hours')),
          const DataColumn(label: Text('Reason')),
          const DataColumn(label: Text('Approver')),
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
          const DataColumn(label: Text('Leave Credits')),
          const DataColumn(label: Text('Start')),
          const DataColumn(label: Text('End')),
          const DataColumn(label: Text('Days')),
          const DataColumn(label: Text('Type')),
          const DataColumn(label: Text('Reason')),
          const DataColumn(label: Text('Approver')),
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
          const DataColumn(label: Text('Approver')),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('Submitted')),
          if (showDelete) const DataColumn(label: Text('Actions')),
        ];
    }
  }

  DataRow _buildRow(AdminRequestItem item) {
    switch (category) {
      case AdminRequestCategory.esarf:
        // Format 24-hour time strings into 12-hour AM/PM format
        final timeFromFormatted = _format12HourTime(item.timeFrom);
        final timeToFormatted = _format12HourTime(item.timeTo);
        final timeFromDisplay = timeFromFormatted.isNotEmpty ? timeFromFormatted : (item.timeFrom ?? 'Ã¢â‚¬â€');
        final timeToDisplay = timeToFormatted.isNotEmpty ? timeToFormatted : (item.timeTo ?? 'Ã¢â‚¬â€');
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? 'Ã¢â‚¬â€')),
          _storeCell(item),
          // Render standardized transaction abbreviation (OT, OB, FIO, etc.)
          DataCell(
            Text(
              _formatEsarfTransactionAbbr(
                (item.transactionType != null && item.transactionType!.isNotEmpty)
                    ? item.transactionType!
                    : item.requestTypeName,
              ),
            ),
          ),
          DataCell(Text(item.dateFrom ?? 'Ã¢â‚¬â€')),
          DataCell(Text(item.dateTo ?? 'Ã¢â‚¬â€')),
          // Render start and end time cells
          DataCell(Text(timeFromDisplay)),
          DataCell(Text(timeToDisplay)),
          DataCell(Text(item.totalHours != null ? '${item.totalHours}h' : 'Ã¢â‚¬â€')),
          _reasonCell(item.reason ?? item.timeSchedule ?? 'Ã¢â‚¬â€'),
          _approverCell(item),
          _statusCell(item),
          _submittedCell(item),
          if (showDelete) _actionsCell(item),
        ]);

      case AdminRequestCategory.leave:
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? 'Ã¢â‚¬â€')),
          _storeCell(item),
          DataCell(Text(item.leaveCategory ?? 'Ã¢â‚¬â€')),
          DataCell(Text(item.leaveCredits != null ? _formatDaysNum(item.leaveCredits) : 'Ã¢â‚¬â€')),
          DataCell(Text(item.startDate ?? 'Ã¢â‚¬â€')),
          DataCell(Text(item.endDate ?? 'Ã¢â‚¬â€')),
          DataCell(Text(item.totalDays != null ? _formatDaysNum(item.totalDays) : 'Ã¢â‚¬â€')),
          _leaveTypeCell(item),
          _reasonCell(item.reason ?? 'Ã¢â‚¬â€'),
          _approverCell(item),
          _statusCell(item),
          _submittedCell(item),
          if (showDelete) _actionsCell(item),
        ]);

      case AdminRequestCategory.perk:
        return DataRow(cells: [
          _employeeCell(item),
          DataCell(Text(item.departmentName ?? 'Ã¢â‚¬â€')),
          _storeCell(item),
          DataCell(Text(
            item.requestTypeCode == 'discount' ? 'Discount' : 'Charge',
          )),
          DataCell(
            Tooltip(
              message: item.perkProductName ?? 'Ã¢â‚¬â€',
              child: _limitedText(
                item.perkProductName ?? 'Ã¢â‚¬â€',
                width: _productWidth,
                maxLines: 2,
              ),
            ),
          ),
          DataCell(Text('${item.perkQuantity ?? 0}')),
          DataCell(Text(
            item.perkAmount != null
                ? '₱${item.perkAmount!.toStringAsFixed(2)}'
                : 'Ã¢â‚¬â€',
          )),
          DataCell(Text(
            item.perkFinalAmount != null
                ? '₱${item.perkFinalAmount!.toStringAsFixed(2)}'
                : 'Ã¢â‚¬â€',
          )),
          DataCell(Text(item.dateFrom ?? 'Ã¢â‚¬â€')),
          _approverCell(item),
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
    final isBirthdayLeave = item.isAutoApprovedBirthdayGrant;
    final statusKey = isBirthdayLeave ? 'approved' : item.status.toLowerCase();

    final color = switch (statusKey) {
      'approved' => const Color(0xFF166534),
      'rejected' => const Color(0xFFB91C1C),
      'cancelled' => const Color(0xFF64748B),
      'needs_admin_review' => const Color(0xFFB45309),
      _ => const Color(0xFF1E40AF),
    };

    final bgColor = switch (statusKey) {
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
      return const DataCell(Text('Ã¢â‚¬â€'));
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
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (category == AdminRequestCategory.leave && onValidate != null) ...[
            Tooltip(
              message: 'Validate request',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onValidate!(item),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
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
        ],
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

// Ã¢â€â‚¬Ã¢â€â‚¬ Reassign Approver Dialog Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _ReassignApproverDialog extends StatefulWidget {
  const _ReassignApproverDialog({
    required this.item,
    this.stepId,
  });

  final AdminRequestItem item;
  final String? stepId;

  @override
  State<_ReassignApproverDialog> createState() => _ReassignApproverDialogState();
}

class _ReassignApproverDialogState extends State<_ReassignApproverDialog> {
  List<EmployeePreview> _allEmployees = [];
  bool _isLoadingEmployees = true;
  String _searchQuery = '';
  EmployeePreview? _selectedEmployee;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final employees = await EmployeeDirectoryService.loadEmployees();
      if (mounted) {
        setState(() {
          _allEmployees = employees;
          _isLoadingEmployees = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load employee list: $e';
          _isLoadingEmployees = false;
        });
      }
    }
  }

  List<EmployeePreview> get _filteredEmployees {
    if (_searchQuery.trim().isEmpty) {
      return _allEmployees;
    }
    final q = _searchQuery.trim().toLowerCase();
    return _allEmployees.where((emp) {
      final name = emp.name.toLowerCase();
      final empNo = emp.idNumber.toLowerCase();
      final dept = emp.departmentName.toLowerCase();
      final pos = emp.positionName.toLowerCase();
      final store = emp.companyName.toLowerCase();
      return name.contains(q) ||
          empNo.contains(q) ||
          dept.contains(q) ||
          pos.contains(q) ||
          store.contains(q);
    }).toList(growable: false);
  }

  Future<void> _confirmReassign() async {
    if (_selectedEmployee == null || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final message = await AdminRequestsService.reassignApprover(
      requestId: widget.item.requestId,
      newApproverEmployeeId: _selectedEmployee!.id,
      stepId: widget.stepId,
    );

    if (!mounted) return;

    if (message.toLowerCase().contains('failed') || message.toLowerCase().contains('error')) {
      setState(() {
        _error = message;
        _isSubmitting = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approver reassigned to ${_selectedEmployee!.name}'),
          backgroundColor: const Color(0xFF166534),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Color(0xFF1E40AF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reassign Approver',
                          style: TextStyle(
                            color: HygColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select an approver for ${widget.item.employeeName ?? "Request"}\'s ${widget.item.requestTypeName}',
                          style: HygTypography.body.copyWith(
                            color: const Color(0xFF64748B),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),

              // Search bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search by employee name, ID, position, department...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 12),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: Color(0xFFB91C1C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Employee candidates list
              Expanded(
                child: _isLoadingEmployees
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredEmployees.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching employees found.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredEmployees.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final emp = _filteredEmployees[index];
                              final isSelected = _selectedEmployee?.id == emp.id;

                              return InkWell(
                                onTap: () => setState(() => _selectedEmployee = emp),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isSelected
                                        ? Border.all(color: const Color(0xFF2563EB), width: 1.5)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      _buildEmployeeAvatar(emp),
                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              emp.name,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                                color: HygColors.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${emp.positionName} • ${emp.departmentName} (${emp.idNumber})',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: Color(0xFF2563EB),
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF475569))),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: (_selectedEmployee == null || _isSubmitting)
                        ? null
                        : _confirmReassign,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirm Reassign'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeAvatar(EmployeePreview emp) {
    final photoUrl = emp.photoUrl?.trim() ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    final (bg, fg) = _getAvatarColors(emp);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitialFallback(emp, bg, fg),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildInitialFallback(emp, bg, fg);
                },
              )
            : _buildInitialFallback(emp, bg, fg),
      ),
    );
  }

  Widget _buildInitialFallback(EmployeePreview emp, Color bg, Color fg) {
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        emp.initial.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  (Color bg, Color fg) _getAvatarColors(EmployeePreview emp) {
    const solidColors = [
      Color(0xFF1E40AF), // Royal Blue
      Color(0xFF6D28D9), // Deep Violet
      Color(0xFF047857), // Forest Emerald
      Color(0xFFC2410C), // Deep Burnt Orange
      Color(0xFFBE185D), // Dark Rose
      Color(0xFF0369A1), // Deep Ocean Sky
    ];
    final hash = emp.name.codeUnits.fold<int>(0, (sum, c) => sum + c);
    final bg = solidColors[hash % solidColors.length];
    return (bg, Colors.white);
  }
}


class _ValidateLeaveDialogContent extends StatefulWidget {
  const _ValidateLeaveDialogContent({required this.item, required this.onConfirm, super.key});
  final AdminRequestItem item;
  final Future<void> Function(double paid, double unpaid) onConfirm;

  @override
  State<_ValidateLeaveDialogContent> createState() => _ValidateLeaveDialogContentState();
}

class _ValidateLeaveDialogContentState extends State<_ValidateLeaveDialogContent> {
  late TextEditingController _paidCtrl;
  late TextEditingController _unpaidCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _paidCtrl = TextEditingController(text: widget.item.paidDays?.toString() ?? '0');
    _unpaidCtrl = TextEditingController(text: widget.item.unpaidDays?.toString() ?? '0');
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _unpaidCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final paid = double.tryParse(_paidCtrl.text) ?? 0.0;
    final unpaid = double.tryParse(_unpaidCtrl.text) ?? 0.0;
    setState(() => _isLoading = true);
    try {
      await widget.onConfirm(paid, unpaid);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Validate Leave Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Are you sure you want to validate this request?', style: TextStyle(color: Colors.black87)),
              const SizedBox(height: 16),
              _buildRow('Category', widget.item.leaveCategory ?? 'Ã¢â‚¬â€'),
              _buildRow('Credits Available', widget.item.leaveCredits?.toString() ?? 'Ã¢â‚¬â€'),
              _buildRow('Leave Type', widget.item.leaveType ?? 'Ã¢â‚¬â€'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _paidCtrl,
                      decoration: const InputDecoration(labelText: 'With Pay (Days)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _unpaidCtrl,
                      decoration: const InputDecoration(labelText: 'Without Pay (Days)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                    child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Validate & Save', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}



