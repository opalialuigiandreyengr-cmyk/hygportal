part of '../main.dart';

// =============================================================================
// AUDIT TRAIL SCREEN (SUPER ADMIN & SYSTEM MONITORING)
// =============================================================================

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({
    required this.session,
    super.key,
  });

  final AdminLoginSession session;

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  static const int _pageSize = 25;
  static const double _kFloatingBarHeight = 26.0;
  static const double _kBottomDockInset = 4.0;
  static const double _kViewportBottomClearance = 10.0;

  List<AuditLogRecord> _logs = [];
  AuditStats _stats = const AuditStats(
    totalLogs: 0,
    passwordResets: 0,
    userUpdates: 0,
    todayActions: 0,
  );

  bool _isLoading = true;
  String? _error;

  int _currentPage = 0;
  int _totalCount = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _floatingScrollController = ScrollController();
  final ValueNotifier<double> _floatingBarY = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _isFloatingBarVisible = ValueNotifier<bool>(false);
  final GlobalKey _tableKey = GlobalKey();

  ScrollPosition? _ancestorPosition;
  ScrollableState? _ancestorScrollable;
  bool _isSyncingScroll = false;

  String _searchQuery = '';
  String _selectedCategory = 'all'; // all, password, user_info, employee_info, ban, balances
  String _selectedTimeframe = 'all'; // all, today, 7days, 30days

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController.addListener(_onTableScroll);
    _floatingScrollController.addListener(_onFloatingScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFloatingPosition();
    });
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (_ancestorScrollable != scrollable) {
      _ancestorPosition?.removeListener(_onAncestorScroll);
      _ancestorScrollable = scrollable;
      _ancestorPosition = scrollable?.position;
      _ancestorPosition?.addListener(_onAncestorScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFloatingPosition();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _horizontalScrollController.removeListener(_onTableScroll);
    _floatingScrollController.removeListener(_onFloatingScroll);
    _ancestorPosition?.removeListener(_onAncestorScroll);
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _floatingScrollController.dispose();
    _floatingBarY.dispose();
    _isFloatingBarVisible.dispose();
    super.dispose();
  }

  void _onTableScroll() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    try {
      if (_floatingScrollController.hasClients && _horizontalScrollController.hasClients) {
        final target = _horizontalScrollController.offset.clamp(
          0.0,
          _floatingScrollController.position.maxScrollExtent,
        );
        if ((_floatingScrollController.offset - target).abs() > 0.5) {
          _floatingScrollController.jumpTo(target);
        }
      }
    } finally {
      _isSyncingScroll = false;
    }
  }

  void _onFloatingScroll() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    try {
      if (_horizontalScrollController.hasClients && _floatingScrollController.hasClients) {
        final target = _floatingScrollController.offset.clamp(
          0.0,
          _horizontalScrollController.position.maxScrollExtent,
        );
        if ((_horizontalScrollController.offset - target).abs() > 0.5) {
          _horizontalScrollController.jumpTo(target);
        }
      }
    } finally {
      _isSyncingScroll = false;
    }
  }

  void _onAncestorScroll() {
    _updateFloatingPosition();
  }

  void _updateFloatingPosition() {
    if (!mounted) return;

    final tableRenderObject = _tableKey.currentContext?.findRenderObject();
    if (tableRenderObject is! RenderBox || !tableRenderObject.hasSize || !tableRenderObject.attached) {
      return;
    }

    final scrollable = _ancestorScrollable ?? Scrollable.maybeOf(context);
    final viewportRenderObject = scrollable?.context.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize || !viewportRenderObject.attached) {
      final double fallbackY = math.max(0.0, tableRenderObject.size.height - _kFloatingBarHeight - _kBottomDockInset);
      if (_floatingBarY.value != fallbackY) {
        _floatingBarY.value = fallbackY;
      }
      if (!_isFloatingBarVisible.value) {
        _isFloatingBarVisible.value = true;
      }
      return;
    }

    final tableGlobal = tableRenderObject.localToGlobal(Offset.zero);
    final viewportGlobal = viewportRenderObject.localToGlobal(Offset.zero);

    final double topInViewport = tableGlobal.dy - viewportGlobal.dy;
    final double tableHeight = tableRenderObject.size.height;
    final double bottomInViewport = topInViewport + tableHeight;
    final double viewportHeight = viewportRenderObject.size.height;

    final bool isTableVisible = topInViewport < (viewportHeight - _kFloatingBarHeight) &&
        bottomInViewport > (_kFloatingBarHeight + 20.0);

    if (!isTableVisible) {
      if (_isFloatingBarVisible.value) {
        _isFloatingBarVisible.value = false;
      }
      return;
    }

    final double visibleBottom = math.min(bottomInViewport, viewportHeight - _kViewportBottomClearance);
    double localY = visibleBottom - topInViewport - _kFloatingBarHeight;

    final double maxLocalY = math.max(0.0, tableHeight - _kFloatingBarHeight - _kBottomDockInset);
    localY = localY.clamp(0.0, maxLocalY);

    if ((_floatingBarY.value - localY).abs() > 0.5) {
      _floatingBarY.value = localY;
    }
    if (!_isFloatingBarVisible.value) {
      _isFloatingBarVisible.value = true;
    }
  }

  Widget _buildFloatingScrollbar(double availableWidth, double rowWidth) {
    return Tooltip(
      message: 'Drag or click to scroll table horizontally',
      waitDuration: const Duration(milliseconds: 700),
      child: Container(
        width: availableWidth,
        height: _kFloatingBarHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(_kFloatingBarHeight / 2),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: HygColors.ink.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular((_kFloatingBarHeight - 6) / 2),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: RawScrollbar(
              controller: _floatingScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 9,
              radius: const Radius.circular(5),
              thumbColor: const Color(0xFF64748B),
              trackColor: const Color(0xFFF1F5F9),
              trackBorderColor: Colors.transparent,
              interactive: true,
              child: SingleChildScrollView(
                controller: _floatingScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: rowWidth,
                  height: _kFloatingBarHeight - 6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resetHorizontalScroll() {
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.jumpTo(0);
    }
    if (_floatingScrollController.hasClients) {
      _floatingScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFloatingPosition();
    });
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = val.trim();
        _currentPage = 0;
      });
      _resetHorizontalScroll();
      _loadData();
    });
  }

  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_selectedTimeframe) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case '7days':
        return now.subtract(const Duration(days: 7));
      case '30days':
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  String? get _actionFilter {
    switch (_selectedCategory) {
      case 'password':
        return 'password_reset';
      case 'ban':
        return 'user_banned';
      default:
        return null;
    }
  }

  String? get _entityTypeFilter {
    switch (_selectedCategory) {
      case 'user_info':
        return 'user';
      case 'employee_info':
        return 'employee';
      case 'balances':
        return 'balance';
      case 'workflow':
        return 'workflow';
      case 'requests':
        return 'requests';
      default:
        return null;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final statsFuture = AuditTrailService.fetchAuditStats();
      final logsFuture = AuditTrailService.fetchAuditLogs(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        action: _actionFilter,
        entityType: _entityTypeFilter,
        startDate: _startDate,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      final results = await Future.wait([statsFuture, logsFuture]);
      final stats = results[0] as AuditStats;
      final logsData = results[1] as ({List<AuditLogRecord> records, int totalCount});

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _logs = logsData.records;
        _totalCount = logsData.totalCount;
        _isLoading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateFloatingPosition();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateFloatingPosition();
      });
    }
  }

  int get _maxPages => (_totalCount / _pageSize).ceil().clamp(1, 99999);

  void _exportCsv() {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audit logs to export.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Date & Time,Actor Username,Actor Role,Action,Target Name,Target Identifier,Description,Metadata JSON');
    for (final item in _logs) {
      final dateStr = item.createdAt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
      final metaClean = jsonEncode(item.metadata).replaceAll('"', '""');
      buffer.writeln(
        '"$dateStr","${item.actorUsername}","${item.actorRole}","${item.actionLabel}","${item.targetName}","${item.targetIdentifier}","${item.description.replaceAll('"', '""')}","$metaClean"',
      );
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${_logs.length} audit logs to clipboard as CSV!'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showAuditDetailDialog(AuditLogRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => _AuditDetailDialog(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildStatsCards(),
        const SizedBox(height: 16),
        _buildFilterBar(),
        const SizedBox(height: 16),
        _buildTableContainer(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.manage_search_rounded,
            color: HygColors.goldStrong,
            size: 48,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audit Trail & System Logs',
                  style: HygTypography.pageTitle,
                ),
                SizedBox(height: 3),
                Text(
                  'Comprehensive audit ledger tracking password resets, employee information updates, role changes, and system modifications.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('Export CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF334155),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _loadData,
            icon: _isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL ACTIVITIES',
            value: _stats.totalLogs.toString(),
            icon: Icons.list_alt_rounded,
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMetricCard(
            title: 'PASSWORD RESETS',
            value: _stats.passwordResets.toString(),
            icon: Icons.lock_reset_rounded,
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFFFBEB),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMetricCard(
            title: 'USER & EMPLOYEE UPDATES',
            value: _stats.userUpdates.toString(),
            icon: Icons.manage_accounts_rounded,
            color: const Color(0xFF7C3AED),
            bgColor: const Color(0xFFF5F3FF),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMetricCard(
            title: 'ACTIVITIES TODAY',
            value: _stats.todayActions.toString(),
            icon: Icons.today_rounded,
            color: const Color(0xFF16A34A),
            bgColor: const Color(0xFFF0FDF4),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by username, employee, action, or details...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Category filter dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Activity Types')),
                  DropdownMenuItem(value: 'password', child: Text('Password Resets')),
                  DropdownMenuItem(value: 'user_info', child: Text('User Profile & Roles')),
                  DropdownMenuItem(value: 'employee_info', child: Text('Employee Updates')),
                  DropdownMenuItem(value: 'balances', child: Text('Leave & Offset Balances')),
                  DropdownMenuItem(value: 'workflow', child: Text('Authority & Workflow')),
                  DropdownMenuItem(value: 'requests', child: Text('Request Validations & Steps')),
                  DropdownMenuItem(value: 'ban', child: Text('Bans & Status')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedCategory = val;
                    _currentPage = 0;
                  });
                  _resetHorizontalScroll();
                  _loadData();
                },
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Timeframe filter dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTimeframe,
                isDense: true,
                icon: const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Time')),
                  DropdownMenuItem(value: 'today', child: Text('Today')),
                  DropdownMenuItem(value: '7days', child: Text('Past 7 Days')),
                  DropdownMenuItem(value: '30days', child: Text('Past 30 Days')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedTimeframe = val;
                    _currentPage = 0;
                  });
                  _resetHorizontalScroll();
                  _loadData();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableContainer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minTableWidth = 1280.0;
          final double tableWidth = math.max(constraints.maxWidth, minTableWidth);
          final bool needsHorizontalScroll = tableWidth > constraints.maxWidth;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateFloatingPosition();
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                key: _tableKey,
                clipBehavior: Clip.none,
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.only(bottom: needsHorizontalScroll ? 36 : 0),
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTableHeader(),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            if (_isLoading)
                              const Padding(
                                padding: EdgeInsets.all(48),
                                child: Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(strokeWidth: 2.5),
                                  ),
                                ),
                              )
                            else if (_error != null)
                              Padding(
                                padding: const EdgeInsets.all(48),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 36),
                                      const SizedBox(height: 10),
                                      Text(
                                        _error!,
                                        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 14),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton(
                                        onPressed: _loadData,
                                        child: const Text('Try Again'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (_logs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(56),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.history_toggle_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
                                      SizedBox(height: 12),
                                      Text(
                                        'No audit logs found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Activities matching your filter criteria will appear here.',
                                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else ...[
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _logs.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                itemBuilder: (context, index) {
                                  final log = _logs[index];
                                  return _buildTableRow(log, index % 2 == 1);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (needsHorizontalScroll)
                    ValueListenableBuilder<bool>(
                      valueListenable: _isFloatingBarVisible,
                      builder: (context, isVisible, _) {
                        if (!isVisible) return const SizedBox.shrink();
                        return ValueListenableBuilder<double>(
                          valueListenable: _floatingBarY,
                          builder: (context, yOffset, _) {
                            return Positioned(
                              top: yOffset,
                              left: 12,
                              right: 12,
                              child: _buildFloatingScrollbar(constraints.maxWidth - 24, tableWidth),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
              if (_totalCount > 0 && _logs.isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildPaginationFooter(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              'DATE & TIME',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(
              'PERFORMED BY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
          SizedBox(
            width: 270,
            child: Text(
              'ACTION',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
          SizedBox(
            width: 190,
            child: Text(
              'TARGET',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
          Expanded(
            child: Text(
              'SUMMARY / DESCRIPTION',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              'DETAILS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(AuditLogRecord log, bool isStripe) {
    return InkWell(
      onTap: () => _showAuditDetailDialog(log),
      hoverColor: const Color(0xFFF1F5F9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isStripe ? const Color(0xFFFAFAFA) : Colors.white,
        child: Row(
          children: [
            // Date & time
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDateTime(log.createdAt),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatRelativeTime(log.createdAt),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),

            // Performed By (Actor)
            SizedBox(
              width: 170,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _getRoleColor(log.actorRole).withValues(alpha: 0.15),
                    child: Text(
                      log.actorUsername.isNotEmpty ? log.actorUsername.substring(0, 1).toUpperCase() : 'S',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _getRoleColor(log.actorRole),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          log.actorUsername,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        _buildRoleBadge(log.actorRole),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Action
            SizedBox(
              width: 270,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildActionPill(log),
              ),
            ),

            // Target
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    log.targetName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.targetIdentifier.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      log.targetIdentifier,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Summary description
            Expanded(
              child: Text(
                log.description.isNotEmpty ? log.description : _buildFallbackSummary(log),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),

            // Details Action Button
            SizedBox(
              width: 70,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF64748B)),
                  splashRadius: 18,
                  onPressed: () => _showAuditDetailDialog(log),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final lower = role.toLowerCase();
    Color bg;
    Color fg;
    if (lower == 'super_admin') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
    } else if (lower == 'admin') {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1D4ED8);
    } else if (lower == 'hr') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
    }

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'super_admin':
        return const Color(0xFFD97706);
      case 'admin':
        return const Color(0xFF2563EB);
      case 'hr':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildActionPill(AuditLogRecord log) {
    Color bg;
    Color fg;
    IconData icon;

    final action = log.action.toLowerCase();
    if (action == 'password_reset') {
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFD97706);
      icon = Icons.lock_reset_rounded;
    } else if (action.contains('role') || action.contains('authority') || action.contains('ladder')) {
      bg = const Color(0xFFF5F3FF);
      fg = const Color(0xFF7C3AED);
      icon = Icons.verified_user_rounded;
    } else if (action.contains('validate')) {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
      icon = Icons.fact_check_rounded;
    } else if (action.contains('reassign')) {
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFEA580C);
      icon = Icons.swap_horiz_rounded;
    } else if (action.contains('banned')) {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      icon = Icons.block_rounded;
    } else if (action.contains('create')) {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
      icon = Icons.person_add_rounded;
    } else if (action.contains('delete')) {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      icon = Icons.delete_forever_rounded;
    } else if (action.contains('leave') || action.contains('offset') || action.contains('balance')) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF059669);
      icon = Icons.account_balance_wallet_rounded;
    } else {
      bg = const Color(0xFFEFF6FF);
      fg = const Color(0xFF2563EB);
      icon = Icons.edit_note_rounded;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              log.actionLabel,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _buildFallbackSummary(AuditLogRecord log) {
    if (log.metadata.containsKey('changes')) {
      final changes = log.metadata['changes'];
      if (changes is Map) {
        return 'Updated ${changes.keys.join(', ')}';
      }
    }
    return '${log.actionLabel} performed on ${log.entityType}';
  }

  Widget _buildPaginationFooter() {
    if (_totalCount == 0 || _logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: EmployeePagination(
        currentPage: _currentPage,
        pageCount: _maxPages,
        totalEmployees: _totalCount,
        employeesPerPage: _pageSize,
        itemLabel: 'logs',
        borderColor: const Color(0xFFE2E8F0),
        onPageSelected: (page) {
          if (page == _currentPage) return;
          setState(() => _currentPage = page);
          _resetHorizontalScroll();
          _loadData();
        },
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    return '$month $day, $year • $hour:$minute $period';
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// =============================================================================
// AUDIT LOG DETAIL & DIFF INSPECTOR MODAL
// =============================================================================

class _AuditDetailDialog extends StatelessWidget {
  const _AuditDetailDialog({required this.record});

  final AuditLogRecord record;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0F172A), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.actionLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Event Log ID: ${record.id}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Metadata overview cards (Actor & Target)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              title: 'ACTOR / PERFORMED BY',
                              icon: Icons.person_outline_rounded,
                              children: [
                                _buildDetailRow('Username', record.actorUsername),
                                _buildDetailRow('Full Name', record.actorFullName),
                                _buildDetailRow('Role', record.actorRole.toUpperCase()),
                                if (record.actorUserProfileId != null)
                                  _buildDetailRow('Profile ID', record.actorUserProfileId!),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildInfoCard(
                              title: 'TARGET ENTITY',
                              icon: Icons.track_changes_rounded,
                              children: [
                                _buildDetailRow('Target Name', record.targetName),
                                if (record.targetIdentifier.isNotEmpty)
                                  _buildDetailRow('Identifier', record.targetIdentifier),
                                _buildDetailRow('Entity Type', record.entityType),
                                if (record.entityId != null)
                                  _buildDetailRow('Entity ID', record.entityId!),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description / Summary
                      if (record.description.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DESCRIPTION',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                record.description,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Changes / Diff Section
                      if (record.metadata.containsKey('changes') && record.metadata['changes'] is Map) ...[
                        _buildChangesDiffTable(record.metadata['changes'] as Map),
                        const SizedBox(height: 16),
                      ],

                      // Raw Metadata Section
                      _buildRawJsonSection(context),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),

              // Footer Action
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangesDiffTable(Map changes) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: const Row(
              children: [
                Icon(Icons.compare_arrows_rounded, size: 16, color: Color(0xFF475569)),
                SizedBox(width: 8),
                Text(
                  'MODIFIED ATTRIBUTES (BEFORE & AFTER)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ...changes.entries.map((entry) {
            final field = entry.key.toString();
            dynamic oldVal = '';
            dynamic newVal = '';
            if (entry.value is Map) {
              final map = entry.value as Map;
              oldVal = map['old']?.toString() ?? 'null';
              newVal = map['new']?.toString() ?? 'null';
            } else {
              newVal = entry.value.toString();
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      _formatFieldName(field),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        oldVal.isEmpty ? '(empty)' : oldVal,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFDC2626),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF94A3B8)),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        newVal.isEmpty ? '(empty)' : newVal,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatFieldName(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  Widget _buildRawJsonSection(BuildContext context) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(record.metadata);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.code_rounded, size: 15, color: Color(0xFF94A3B8)),
                const SizedBox(width: 8),
                const Text(
                  'METADATA PAYLOAD (JSON)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied metadata JSON to clipboard!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFFF8FAFC)),
                  label: const Text(
                    'Copy JSON',
                    style: TextStyle(fontSize: 11, color: Color(0xFFF8FAFC)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          Container(
            padding: const EdgeInsets.all(14),
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                jsonStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: Color(0xFFE2E8F0),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

