part of '../main.dart';

class UsersHeader extends StatelessWidget {
  const UsersHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.manage_accounts_outlined,
            color: HygColors.goldStrong,
            size: 42,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Users', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'Registered login accounts linked from employee profiles.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UsersPanel extends StatefulWidget {
  const UsersPanel({
    required this.users,
    required this.employees,
    required this.companies,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    required this.onSetOffsetBalance,
    required this.onCreateUser,
    required this.onDeleteUser,
    super.key,
  });

  final List<RegisteredUserPreview> users;
  final List<EmployeePreview> employees;
  final List<CompanyPreview> companies;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(
    RegisteredUserPreview user,
    String appRole, {
    List<String>? companyIds,
  }) onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays, [
    LeaveCreditMode mode,
  ])
  onSetLeaveCredits;
  final Future<void> Function(
    RegisteredUserPreview user,
    double balanceHours, [
    OffsetBalanceMode mode,
    String? reason,
  ])
  onSetOffsetBalance;
  final Future<void> Function(AddUserRequest request) onCreateUser;
  final Future<void> Function(RegisteredUserPreview user) onDeleteUser;

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

enum UsersPanelViewMode { accounts, transactions }

class _UsersPanelState extends State<UsersPanel> {
  static const _usersPerPage = 15;
  static const _txPerPage = 20;

  var _viewMode = UsersPanelViewMode.accounts;

  // Accounts state
  final _searchController = TextEditingController();
  var _query = '';
  var _currentPage = 0;

  // Transactions history state
  var _transactions = <BalanceTransactionRecord>[];
  var _isLoadingTransactions = false;
  String? _transactionsError;
  final _txSearchController = TextEditingController();
  var _txQuery = '';
  var _txTypeFilter = 'all'; // 'all', 'leave', 'offset'
  var _txCategoryFilter = 'all'; // 'all', 'earn', 'allocation', 'deduction', 'use', 'refund'
  String? _txEmployeeIdFilter;
  var _txCurrentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadTransactions(silent: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _txSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= _pageCount) {
      _currentPage = _pageCount - 1;
    }
    if (_txCurrentPage >= _txPageCount) {
      _txCurrentPage = _txPageCount - 1;
    }
  }

  int get _pageCount =>
      (_filteredUsers.length / _usersPerPage).ceil().clamp(1, 999999);

  List<RegisteredUserPreview> get _visibleUsers {
    final start = _currentPage * _usersPerPage;
    final end = math.min(start + _usersPerPage, _filteredUsers.length);
    return _filteredUsers.sublist(start, end);
  }

  List<RegisteredUserPreview> get _filteredUsers {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.users;

    return widget.users.where((user) {
      return user.username.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.fullName.toLowerCase().contains(query) ||
          user.employeeNo.toLowerCase().contains(query) ||
          user.appRole.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addUser() async {
    final linkedEmployeeIds = widget.users
        .map((u) => u.employeeId)
        .whereType<String>()
        .toSet();
    final availableEmployees = widget.employees
        .where((e) => !linkedEmployeeIds.contains(e.id))
        .toList();
    final request = await showDialog<AddUserRequest>(
      context: context,
      builder: (context) => AddUserDialog(
        employees: availableEmployees,
        companies: widget.companies,
      ),
    );
    if (request == null) return;
    await widget.onCreateUser(request);
  }

  void _goToPage(int page) {
    final nextPage = page.clamp(0, _pageCount - 1);
    if (nextPage == _currentPage) return;
    setState(() => _currentPage = nextPage);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _currentPage = 0;
    });
  }

  // Transaction History methods
  Future<void> _loadTransactions({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingTransactions = true;
        _transactionsError = null;
      });
    }
    try {
      final records = await RegisteredUsersService.fetchBalanceTransactions(
        registeredUsers: widget.users,
      );
      if (!mounted) return;
      setState(() {
        _transactions = records;
        _isLoadingTransactions = false;
        _transactionsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingTransactions = false;
        _transactionsError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<BalanceTransactionRecord> get _filteredTransactions {
    final query = _txQuery.trim().toLowerCase();
    return _transactions.where((t) {
      if (_txTypeFilter != 'all' && t.balanceType != _txTypeFilter) return false;
      if (_txCategoryFilter != 'all' && t.category != _txCategoryFilter) {
        return false;
      }
      if (_txEmployeeIdFilter != null &&
          _txEmployeeIdFilter != 'all' &&
          t.employeeId != _txEmployeeIdFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final matches = t.fullName.toLowerCase().contains(query) ||
            t.employeeNo.toLowerCase().contains(query) ||
            t.username.toLowerCase().contains(query) ||
            (t.reason?.toLowerCase().contains(query) ?? false) ||
            (t.actorName?.toLowerCase().contains(query) ?? false) ||
            t.title.toLowerCase().contains(query) ||
            t.subtitle.toLowerCase().contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  int get _txPageCount =>
      (_filteredTransactions.length / _txPerPage).ceil().clamp(1, 999999);

  List<BalanceTransactionRecord> get _visibleTransactions {
    final start = _txCurrentPage * _txPerPage;
    final end = math.min(start + _txPerPage, _filteredTransactions.length);
    return _filteredTransactions.sublist(start, end);
  }

  void _goToTxPage(int page) {
    final nextPage = page.clamp(0, _txPageCount - 1);
    if (nextPage == _txCurrentPage) return;
    setState(() => _txCurrentPage = nextPage);
  }

  void _clearTxSearch() {
    _txSearchController.clear();
    setState(() {
      _txQuery = '';
      _txEmployeeIdFilter = null;
      _txCurrentPage = 0;
    });
  }

  double get _totalLeaveAllocated => _transactions
      .where((t) => t.isLeave && t.amount > 0)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get _totalLeaveDeducted => _transactions
      .where((t) => t.isLeave && t.amount < 0)
      .fold<double>(0, (sum, t) => sum + t.amount.abs());

  double get _totalOffsetEarned => _transactions
      .where((t) => t.isOffset && t.amount > 0)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get _totalOffsetDeducted => _transactions
      .where((t) => t.isOffset && t.amount < 0)
      .fold<double>(0, (sum, t) => sum + t.amount.abs());

  static String _formatNum(double val) {
    return val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 2);
  }

  void _exportTransactionsCsv() {
    final list = _filteredTransactions;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transactions to export.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln(
      'Date,Employee No,Employee Name,Username,Balance Type,Category,Amount,Unit,Balance After,Reason,Performed By',
    );
    for (final item in list) {
      final dateStr = item.createdAt
          .toIso8601String()
          .replaceFirst('T', ' ')
          .substring(0, 16);
      final amt =
          '${item.amount >= 0 ? "+" : ""}${item.amount.toStringAsFixed(2)}';
      final after = item.balanceAfter != null
          ? item.balanceAfter!.toStringAsFixed(2)
          : '';
      buffer.writeln(
        '"$dateStr","${item.employeeNo}","${item.fullName}","${item.username}","${item.balanceType}","${item.category}","$amt","${item.unit}","$after","${(item.reason ?? '').replaceAll('"', '""')}","${(item.actorName ?? '').replaceAll('"', '""')}"',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${list.length} transaction records to clipboard as CSV! You can paste into Excel.',
        ),
        backgroundColor: const Color(0xFF15803D),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ViewModeSwitcher(
                currentMode: _viewMode,
                accountsCount: widget.users.length,
                transactionsCount: _transactions.length,
                onModeChanged: (mode) {
                  setState(() {
                    _viewMode = mode;
                  });
                  if (mode == UsersPanelViewMode.transactions &&
                      _transactions.isEmpty &&
                      !_isLoadingTransactions) {
                    _loadTransactions();
                  }
                },
              ),
              const Spacer(),
              if (_viewMode == UsersPanelViewMode.transactions) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: HygColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _exportTransactionsCsv,
                  icon: const Icon(Icons.file_download_outlined, size: 17),
                  label: const Text('Export CSV'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh Transactions',
                  onPressed: () => _loadTransactions(),
                  icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_viewMode == UsersPanelViewMode.accounts)
            _buildAccountsView()
          else
            _buildTransactionsView(),
        ],
      ),
    );
  }

  Widget _buildAccountsView() {
    final users = _filteredUsers;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _UserSearchField(
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _query = value;
                  _currentPage = 0;
                }),
                onClear: _clearSearch,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF6C400),
                  foregroundColor: HygColors.ink,
                  textStyle: HygTypography.button.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _addUser,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Add user'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Refresh',
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const UsersTableHeader(),
        const SizedBox(height: 8),
        if (widget.isLoading)
          const EmployeesStateMessage(
            icon: Icons.sync,
            title: 'Loading users',
            message: 'Getting registered login accounts from Supabase.',
          )
        else if (widget.error != null)
          EmployeesStateMessage(
            icon: Icons.warning_amber_rounded,
            title: 'Could not load users',
            message: widget.error!,
            actionLabel: 'Retry',
            onAction: widget.onRefresh,
          )
        else if (widget.users.isEmpty)
          EmployeesStateMessage(
            icon: Icons.manage_accounts_outlined,
            title: 'No registered users',
            message: 'No employee login accounts have been registered yet.',
            actionLabel: 'Refresh',
            onAction: widget.onRefresh,
          )
        else if (users.isEmpty)
          EmployeesStateMessage(
            icon: Icons.search_off,
            title: 'No matching users',
            message: 'Try another username, employee, or email.',
            actionLabel: 'Clear',
            onAction: _clearSearch,
          )
        else ...[
          ..._visibleUsers.map(
            (user) => UserRow(
              user: user,
              companies: widget.companies,
              onSetBan: widget.onSetBan,
              onSetRole: widget.onSetRole,
              onResetPassword: widget.onResetPassword,
              onSetLeaveCredits: widget.onSetLeaveCredits,
              onSetOffsetBalance: widget.onSetOffsetBalance,
              onDeleteUser: widget.onDeleteUser,
              onViewTransactions: _viewUserTransactions,
            ),
          ),
          const SizedBox(height: 14),
          EmployeePagination(
            currentPage: _currentPage,
            pageCount: _pageCount,
            totalEmployees: users.length,
            employeesPerPage: _usersPerPage,
            itemLabel: 'users',
            onPageSelected: _goToPage,
          ),
        ],
      ],
    );
  }

  Widget _buildTransactionsView() {
    final transactions = _filteredTransactions;

    return Column(
      children: [
        // 1. KPI Summary Cards
        Row(
          children: [
            Expanded(
              child: TransactionsSummaryCard(
                title: 'Leave Credits Allocated',
                value: '${_formatNum(_totalLeaveAllocated)} days',
                subtitle: 'Policy & Admin grants',
                icon: Icons.event_available_outlined,
                accentColor: const Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TransactionsSummaryCard(
                title: 'Paid Leave & Deductions',
                value: '${_formatNum(_totalLeaveDeducted)} days',
                subtitle: 'Used & Admin deducted',
                icon: Icons.event_busy_outlined,
                accentColor: const Color(0xFFE11D48),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TransactionsSummaryCard(
                title: 'Offset Hours Earned',
                value: '${_formatNum(_totalOffsetEarned)} hrs',
                subtitle: 'ESARF & Admin additions',
                icon: Icons.alarm_add_outlined,
                accentColor: const Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TransactionsSummaryCard(
                title: 'Offset Hours Used / Deducted',
                value: '${_formatNum(_totalOffsetDeducted)} hrs',
                subtitle: 'Offset requests & deductions',
                icon: Icons.alarm_off_outlined,
                accentColor: const Color(0xFF4F46E5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Filters Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HygColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _txSearchController,
                    onChanged: (val) => setState(() {
                      _txQuery = val;
                      _txCurrentPage = 0;
                    }),
                    style: HygTypography.body.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search by employee, username, reason...',
                      hintStyle: HygTypography.body.copyWith(
                        color: HygColors.muted,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _txQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: _clearTxSearch,
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: HygColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: HygColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: HygColors.goldStrong),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Type Filter
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HygColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _txTypeFilter,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: HygTypography.body.copyWith(fontSize: 13),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _txTypeFilter = val;
                          _txCurrentPage = 0;
                        });
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Balance Types')),
                      DropdownMenuItem(value: 'leave', child: Text('Leave Credits Only')),
                      DropdownMenuItem(value: 'offset', child: Text('Offset Balance Only')),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Category Filter
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HygColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _txCategoryFilter,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: HygTypography.body.copyWith(fontSize: 13),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _txCategoryFilter = val;
                          _txCurrentPage = 0;
                        });
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Categories')),
                      DropdownMenuItem(value: 'earn', child: Text('Earned (Accruals)')),
                      DropdownMenuItem(value: 'allocation', child: Text('Admin Allocations')),
                      DropdownMenuItem(value: 'deduction', child: Text('Admin Deductions')),
                      DropdownMenuItem(value: 'use', child: Text('Used (Requests)')),
                      DropdownMenuItem(value: 'refund', child: Text('Reimbursed / Refunds')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Table Header & Content
        if (_isLoadingTransactions)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmployeesStateMessage(
                icon: Icons.sync,
                title: 'Loading transaction history',
                message:
                    'Fetching leave credits and offset balance transaction history...',
              ),
            ),
          )
        else if (_transactionsError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmployeesStateMessage(
                icon: Icons.warning_amber_rounded,
                title: 'Could not load transactions',
                message: _transactionsError!,
                actionLabel: 'Retry',
                onAction: _loadTransactions,
              ),
            ),
          )
        else if (_transactions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmployeesStateMessage(
                icon: Icons.receipt_long_outlined,
                title: 'No balance transactions recorded',
                message:
                    'No leave credits or offset balance transactions found yet.',
                actionLabel: 'Refresh',
                onAction: _loadTransactions,
              ),
            ),
          )
        else if (transactions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmployeesStateMessage(
                icon: Icons.search_off,
                title: 'No matching transactions',
                message:
                    'Try clearing or modifying the search and filter options.',
                actionLabel: 'Reset filters',
                onAction: () {
                  setState(() {
                    _txQuery = '';
                    _txSearchController.clear();
                    _txTypeFilter = 'all';
                    _txCategoryFilter = 'all';
                    _txEmployeeIdFilter = null;
                    _txCurrentPage = 0;
                  });
                },
              ),
            ),
          )
        else ...[
          _TransactionsTable(
            items: _visibleTransactions,
            onTapRow: _openTransactionDetail,
          ),
          const SizedBox(height: 14),
          EmployeePagination(
            currentPage: _txCurrentPage,
            pageCount: _txPageCount,
            totalEmployees: transactions.length,
            employeesPerPage: _txPerPage,
            itemLabel: 'transactions',
            onPageSelected: _goToTxPage,
          ),
        ],
      ],
    );
  }

  void _viewUserTransactions(RegisteredUserPreview user) {
    final queryText = user.employeeNo.isNotEmpty ? user.employeeNo : user.fullName;
    setState(() {
      _viewMode = UsersPanelViewMode.transactions;
      _txSearchController.text = queryText;
      _txQuery = queryText;
      _txEmployeeIdFilter = user.employeeId;
      _txCurrentPage = 0;
    });
    if (_transactions.isEmpty && !_isLoadingTransactions) {
      _loadTransactions();
    }
  }

  void _openTransactionDetail(BalanceTransactionRecord record) {
    showDialog<void>(
      context: context,
      builder: (ctx) => TransactionDetailDialog(
        record: record,
        onViewUserHistory: () {
          Navigator.of(ctx).pop();
          setState(() {
            _txSearchController.text = record.employeeNo;
            _txQuery = record.employeeNo;
            _txEmployeeIdFilter = record.employeeId;
            _txCurrentPage = 0;
          });
        },
      ),
    );
  }
}

class _UserSearchField extends StatelessWidget {
  const _UserSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: HygTypography.body.copyWith(color: HygColors.ink),
        decoration: InputDecoration(
          hintText: 'Search username, employee, email',
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF64748B),
            size: 18,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF64748B),
                    size: 17,
                  ),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: HygColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: HygColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: HygColors.goldStrong),
          ),
        ),
      ),
    );
  }
}

class UsersTableHeader extends StatelessWidget {
  const UsersTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: HygColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: HeaderLabel('USER')),
          Expanded(flex: 3, child: HeaderLabel('LINKED EMPLOYEE')),
          Expanded(flex: 2, child: HeaderLabel('ROLE')),
          Expanded(flex: 2, child: HeaderLabel('STATUS')),
          Expanded(flex: 2, child: HeaderLabel('LEAVE')),
          Expanded(flex: 2, child: HeaderLabel('OFFSET')),
          Expanded(flex: 2, child: HeaderLabel('REGISTERED')),
          Expanded(flex: 2, child: HeaderLabel('LAST SIGN IN')),
          SizedBox(
            width: 52,
            child: Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class UserRow extends StatefulWidget {
  const UserRow({
    required this.user,
    required this.companies,
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    required this.onSetOffsetBalance,
    required this.onDeleteUser,
    this.onViewTransactions,
    super.key,
  });

  final RegisteredUserPreview user;
  final List<CompanyPreview> companies;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(
    RegisteredUserPreview user,
    String appRole, {
    List<String>? companyIds,
  }) onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays, [
    LeaveCreditMode mode,
  ])
  onSetLeaveCredits;
  final Future<void> Function(
    RegisteredUserPreview user,
    double balanceHours, [
    OffsetBalanceMode mode,
    String? reason,
  ])
  onSetOffsetBalance;
  final Future<void> Function(RegisteredUserPreview user) onDeleteUser;
  final ValueChanged<RegisteredUserPreview>? onViewTransactions;

  @override
  State<UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<UserRow> {
  var _isHovered = false;
  var _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final rowColor = _isMenuOpen
        ? const Color(0xFFFEF3C7)
        : _isHovered
        ? const Color(0xFFF1F5F9)
        : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 66,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: rowColor,
          border: Border.all(color: HygColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  UserAvatar(user: widget.user),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.user.username,
                          overflow: TextOverflow.ellipsis,
                          style: HygTypography.tablePrimary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.user.email,
                          overflow: TextOverflow.ellipsis,
                          style: HygTypography.body.copyWith(
                            color: HygColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: BodyCell(
                widget.user.employeeId == null
                    ? 'NO LINKED EMPLOYEE'
                    : '${widget.user.fullName} (${widget.user.employeeNo})',
              ),
            ),
            Expanded(flex: 2, child: BodyCell(widget.user.appRole)),
            Expanded(
              flex: 2,
              child: Text(
                widget.user.isBanned
                    ? 'BANNED'
                    : (widget.user.isActive ? 'ACTIVE' : 'INACTIVE'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HygTypography.tableBody.copyWith(
                  color: widget.user.isBanned
                      ? const Color(0xFFDC2626)
                      : widget.user.isActive
                      ? const Color(0xFF15803D)
                      : const Color(0xFFF97316),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: BodyCell(_leaveCreditLabel(widget.user)),
            ),
            Expanded(
              flex: 2,
              child: BodyCell(_offsetBalanceLabel(widget.user)),
            ),
            Expanded(flex: 2, child: BodyCell(widget.user.registeredAt)),
            Expanded(flex: 2, child: BodyCell(widget.user.lastSignInAt)),
            SizedBox(
              width: 52,
              child: UserActionsMenu(
                user: widget.user,
                companies: widget.companies,
                isActive: _isHovered || _isMenuOpen,
                onMenuOpenChanged: (value) {
                  if (mounted) setState(() => _isMenuOpen = value);
                },
                onSetBan: widget.onSetBan,
                onSetRole: widget.onSetRole,
                onResetPassword: widget.onResetPassword,
                onSetLeaveCredits: widget.onSetLeaveCredits,
                onSetOffsetBalance: widget.onSetOffsetBalance,
                onDeleteUser: widget.onDeleteUser,
                onViewTransactions: widget.onViewTransactions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _leaveCreditLabel(RegisteredUserPreview user) {
    if (user.employeeId == null || user.leaveCreditDays == null) return 'N/A';
    return '${_formatDays(user.leaveRemainingDays)} left / ${_formatDays(user.leaveCreditDays)}';
  }

  String _offsetBalanceLabel(RegisteredUserPreview user) {
    if (user.employeeId == null || user.offsetBalanceHours == null) return 'N/A';
    final hours = user.offsetBalanceHours!;
    final fixed = hours.toStringAsFixed(
      hours.truncateToDouble() == hours ? 0 : 2,
    );
    return '$fixed hrs';
  }

  String _formatDays(double? value) {
    if (value == null) return '0d';
    final fixed = value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 2,
    );
    return '${fixed}d';
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoUrl?.trim() ?? '';
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl.isEmpty
          ? _UserInitialAvatar(user: user)
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _UserInitialAvatar(user: user),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _UserInitialAvatar(user: user);
              },
            ),
    );
  }
}

class _UserInitialAvatar extends StatelessWidget {
  const _UserInitialAvatar({required this.user});

  final RegisteredUserPreview user;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        _initial(
          user.fullName == 'NO LINKED EMPLOYEE' ? user.username : user.fullName,
        ),
        style: const TextStyle(
          color: HygColors.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  static String _initial(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '?';
    return clean.substring(0, 1).toUpperCase();
  }
}

class UserActionsMenu extends StatefulWidget {
  const UserActionsMenu({
    required this.user,
    required this.companies,
    required this.isActive,
    required this.onMenuOpenChanged,
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    required this.onSetOffsetBalance,
    required this.onDeleteUser,
    this.onViewTransactions,
    super.key,
  });

  final RegisteredUserPreview user;
  final List<CompanyPreview> companies;
  final bool isActive;
  final ValueChanged<bool> onMenuOpenChanged;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(
    RegisteredUserPreview user,
    String appRole, {
    List<String>? companyIds,
  }) onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays, [
    LeaveCreditMode mode,
  ])
  onSetLeaveCredits;
  final Future<void> Function(
    RegisteredUserPreview user,
    double balanceHours, [
    OffsetBalanceMode mode,
    String? reason,
  ])
  onSetOffsetBalance;
  final Future<void> Function(RegisteredUserPreview user) onDeleteUser;
  final ValueChanged<RegisteredUserPreview>? onViewTransactions;

  @override
  State<UserActionsMenu> createState() => _UserActionsMenuState();
}

class _UserActionsMenuState extends State<UserActionsMenu> {
  Future<void> _openMenu() async {
    widget.onMenuOpenChanged(true);
    final buttonBox = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = buttonBox.localToGlobal(Offset.zero, ancestor: overlay);
    final menuWidth = 300.0;
    final position = RelativeRect.fromLTRB(
      math.max(8, topLeft.dx - menuWidth - 8),
      topLeft.dy - 4,
      overlay.size.width - topLeft.dx + 8,
      overlay.size.height - topLeft.dy,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.white,
      elevation: 8,
      constraints: BoxConstraints.tightFor(width: menuWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          value: 'ban',
          height: 52,
          child: _UserActionMenuItem(
            icon: widget.user.isBanned ? Icons.lock_open_outlined : Icons.block,
            label: widget.user.isBanned ? 'Unban user' : 'Ban user',
          ),
        ),
        const PopupMenuItem(
          value: 'role',
          height: 52,
          child: _UserActionMenuItem(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Change role',
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'password',
          height: 52,
          child: _UserActionMenuItem(
            icon: Icons.password_outlined,
            label: 'Change password',
          ),
        ),
        PopupMenuItem(
          value: 'leave',
          height: 52,
          enabled: widget.user.employeeId != null,
          child: _UserActionMenuItem(
            icon: Icons.event_available_outlined,
            label: widget.user.employeeId == null
                ? 'Allocate leave credits (link employee first)'
                : 'Allocate leave credits',
          ),
        ),
        PopupMenuItem(
          value: 'offset',
          height: 52,
          enabled: widget.user.employeeId != null,
          child: _UserActionMenuItem(
            icon: Icons.timelapse_outlined,
            label: widget.user.employeeId == null
                ? 'Allocate offset balance (link employee first)'
                : 'Allocate offset balance',
          ),
        ),
        PopupMenuItem(
          value: 'history',
          height: 52,
          enabled: widget.user.employeeId != null,
          child: _UserActionMenuItem(
            icon: Icons.history_rounded,
            label: widget.user.employeeId == null
                ? 'View balance history (link employee first)'
                : 'View balance history',
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'delete',
          height: 52,
          child: _UserActionMenuItem(
            icon: Icons.delete_outline,
            label: 'Delete user',
            iconColor: Color(0xFFDC2626),
          ),
        ),
      ],
    );

    widget.onMenuOpenChanged(false);
    if (!mounted || action == null) return;

    if (action == 'ban') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => UserBanDialog(user: widget.user),
      );
      if (confirmed == true) {
        await widget.onSetBan(widget.user, !widget.user.isBanned);
      }
    } else if (action == 'role') {
      final result = await showDialog<UserRoleDialogResult>(
        context: context,
        builder: (context) => UserRoleDialog(
          user: widget.user,
          companies: widget.companies,
        ),
      );
      if (result != null) {
        await widget.onSetRole(
          widget.user,
          result.role,
          companyIds: result.companyIds,
        );
      }
    } else if (action == 'password') {
      final password = await showDialog<String>(
        context: context,
        builder: (context) => UserPasswordDialog(user: widget.user),
      );
      if (password != null) {
        await widget.onResetPassword(widget.user, password);
      }
    } else if (action == 'leave') {
      final result = await showDialog<UserLeaveCreditsResult>(
        context: context,
        builder: (context) => UserLeaveCreditsDialog(user: widget.user),
      );
      if (result != null) {
        await widget.onSetLeaveCredits(widget.user, result.amount, result.mode);
      }
    } else if (action == 'offset') {
      final result = await showDialog<UserOffsetBalanceResult>(
        context: context,
        builder: (context) => UserOffsetBalanceDialog(user: widget.user),
      );
      if (result != null) {
        await widget.onSetOffsetBalance(
          widget.user,
          result.amount,
          result.mode,
          result.reason,
        );
      }
    } else if (action == 'history') {
      if (widget.onViewTransactions != null) {
        widget.onViewTransactions!(widget.user);
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Delete User'),
          content: Text(
            'Are you sure you want to delete "${widget.user.username}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.onDeleteUser(widget.user);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: 'User actions',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _openMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.isActive ? HygColors.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: widget.isActive
                    ? HygColors.goldStrong
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: const Icon(
              Icons.more_vert,
              color: Color(0xFF475569),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserActionMenuItem extends StatelessWidget {
  const _UserActionMenuItem({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Icon(icon, color: iconColor ?? const Color(0xFF475569), size: 22),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HygTypography.body.copyWith(
              color: const Color(0xFF1F2937),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class AddUserRequest {
  const AddUserRequest({
    required this.username,
    required this.email,
    required this.password,
    required this.appRole,
    this.employeeId,
    this.companyIds,
  });

  final String username;
  final String email;
  final String password;
  final String appRole;
  final String? employeeId;
  final List<String>? companyIds;
}

class AddUserDialog extends StatefulWidget {
  const AddUserDialog({
    required this.employees,
    required this.companies,
    super.key,
  });

  final List<EmployeePreview> employees;
  final List<CompanyPreview> companies;

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  var _role = 'employee';
  String? _selectedEmployeeId;
  final List<String> _selectedCompanyIds = [];
  String? _error;

  bool get _hasEmployees => widget.employees.isNotEmpty;

  EmployeePreview? get _selectedEmployee {
    if (_selectedEmployeeId == null) return null;
    for (final e in widget.employees) {
      if (e.id == _selectedEmployeeId) return e;
    }
    return null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onEmployeeSelected(String? value) {
    setState(() {
      _selectedEmployeeId = (value == null || value.isEmpty) ? null : value;
      final emp = _selectedEmployee;
      if (emp != null) {
        _emailController.text = emp.email ?? '';
        final firstName = (emp.firstName ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z]'), '');
        if (firstName.isNotEmpty) {
          _usernameController.text = firstName;
        }
      } else {
        _emailController.clear();
      }
    });
  }

  void _submit() {
    final username = _usernameController.text.trim().toLowerCase();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (username.isEmpty) {
      setState(() => _error = 'Username is required.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    if (_role == 'hr' && _selectedCompanyIds.isEmpty) {
      setState(() => _error = 'Please select at least one company.');
      return;
    }

    Navigator.of(context).pop(
      AddUserRequest(
        username: username,
        email: email,
        password: password,
        appRole: _role,
        employeeId: _role == 'hr' ? null : _selectedEmployee?.id,
        companyIds: _role == 'hr' ? _selectedCompanyIds : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const roles = ['employee', 'hr', 'admin', 'super_admin'];

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (_role != 'hr') ...[
                  _buildEmployeeSection(),
                  const SizedBox(height: 18),
                ],
                _buildAccountSection(roles),
                if (_role == 'hr') ...[
                  const SizedBox(height: 18),
                  _buildCompaniesSection(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _buildErrorBanner(),
                ],
                const SizedBox(height: 20),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDE68A), Color(0xFFFACC15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFACC15).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_add_alt_1_outlined,
            color: Color(0xFF78350F),
            size: 21,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add User',
                style: HygTypography.pageTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                'Create account and optionally link an employee.',
                style: HygTypography.body.copyWith(
                  fontSize: 12.5,
                  color: HygColors.muted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
        ),
      ],
    );
  }

  Widget _buildAccountSection(List<String> roles) {
    return _SectionCard(
      icon: Icons.badge_outlined,
      iconColor: const Color(0xFFD97706),
      title: 'Login Credentials',
      child: Column(
        children: [
          ModalTextField(
            controller: _usernameController,
            label: 'Username',
            required: true,
          ),
          const SizedBox(height: 12),
          ModalTextField(
            controller: _emailController,
            label: _selectedEmployee != null ? 'Email (auto-filled)' : 'Email',
            required: true,
            readOnly: _selectedEmployee != null,
            trailingIcon: _selectedEmployee != null
                ? Icons.link
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ModalTextField(
                  controller: _passwordController,
                  label: 'Password',
                  required: true,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    focusNode: FocusNode(skipTraversal: true),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF64748B),
                      size: 18,
                    ),
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ModalTextField(
                  controller: _confirmController,
                  label: 'Confirm',
                  required: true,
                  obscureText: _obscureConfirm,
                  suffixIcon: IconButton(
                    focusNode: FocusNode(skipTraversal: true),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF64748B),
                      size: 18,
                    ),
                    tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(label: 'Role', required: true),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in roles)
                      _RoleChip(
                        label: role.toUpperCase(),
                        selected: _role == role,
                        onTap: () {
                          setState(() {
                            _role = role;
                            if (role == 'hr') {
                              _selectedEmployeeId = null;
                              _emailController.clear();
                              _usernameController.clear();
                            } else {
                              _selectedCompanyIds.clear();
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeSection() {
    return _SectionCard(
      icon: Icons.work_outline,
      iconColor: const Color(0xFF0369A1),
      title: 'Link Employee',
      subtitle: _hasEmployees
          ? 'Optional — skip to assign later.'
          : 'No unlinked employees available.',
      child: _hasEmployees
          ? SearchableEmployeeDropdown(
              employees: widget.employees,
              selectedEmployeeId: _selectedEmployeeId,
              onSelected: _onEmployeeSelected,
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All employees are already linked. Create the user first, then assign later.',
                      style: HygTypography.body.copyWith(
                        fontSize: 12.5,
                        color: HygColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCompaniesSection() {
    return _SectionCard(
      icon: Icons.business_outlined,
      iconColor: const Color(0xFF0369A1),
      title: 'Link Companies',
      subtitle: widget.companies.isNotEmpty
          ? 'Select the companies this HR can access.'
          : 'No companies available.',
      child: widget.companies.isNotEmpty
          ? Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.companies.length,
                itemBuilder: (context, index) {
                  final company = widget.companies[index];
                  final isSelected = _selectedCompanyIds.contains(company.id);
                  return CheckboxListTile(
                    activeColor: HygColors.gold,
                    checkColor: HygColors.ink,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              company.initials,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: HygColors.goldStrong,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            company.name,
                            style: HygTypography.body.copyWith(
                              fontSize: 14,
                              color: HygColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (bool? checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedCompanyIds.add(company.id);
                        } else {
                          _selectedCompanyIds.remove(company.id);
                        }
                      });
                    },
                  );
                },
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No companies have been added yet.',
                      style: HygTypography.body.copyWith(
                        fontSize: 12.5,
                        color: HygColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }


  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: HygTypography.body.copyWith(
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 40,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF6C400),
              foregroundColor: HygColors.ink,
              textStyle: HygTypography.button.copyWith(fontWeight: FontWeight.w600),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Create User'),
          ),
        ),
      ],
    );
  }
}

class SearchableEmployeeDropdown extends StatefulWidget {
  const SearchableEmployeeDropdown({
    required this.employees,
    required this.selectedEmployeeId,
    required this.onSelected,
    super.key,
  });

  final List<EmployeePreview> employees;
  final String? selectedEmployeeId;
  final ValueChanged<String?> onSelected;

  @override
  State<SearchableEmployeeDropdown> createState() =>
      _SearchableEmployeeDropdownState();
}

class _SearchableEmployeeDropdownState
    extends State<SearchableEmployeeDropdown> {
  final _searchController = TextEditingController();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  EmployeePreview? get _selectedEmployee {
    if (widget.selectedEmployeeId == null || widget.selectedEmployeeId!.isEmpty) {
      return null;
    }
    for (final e in widget.employees) {
      if (e.id == widget.selectedEmployeeId) return e;
    }
    return null;
  }

  @override
  void dispose() {
    _closeDropdown();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (widget.employees.isEmpty) return;
    _searchController.clear();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeDropdown,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: _EmployeeDropdownListContent(
                    employees: widget.employees,
                    selectedEmployeeId: widget.selectedEmployeeId,
                    searchController: _searchController,
                    onSelect: (empId) {
                      widget.onSelected(empId);
                      _closeDropdown();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emp = _selectedEmployee;
    final displayText = emp != null
        ? '${emp.name}  •  ${emp.idNumber}'
        : 'Select an employee...';

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _isOpen ? HygColors.goldStrong : const Color(0xFFD1D5DB),
              width: _isOpen ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              if (emp != null) ...[
                CircleAvatar(
                  radius: 11,
                  backgroundColor: emp.avatarColor.withValues(alpha: 0.18),
                  child: Text(
                    emp.initial,
                    style: TextStyle(
                      color: emp.avatarColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  displayText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 14,
                    color: emp != null
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              if (emp != null)
                InkWell(
                  onTap: () => widget.onSelected(null),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.clear,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                _isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: const Color(0xFF64748B),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeDropdownListContent extends StatefulWidget {
  const _EmployeeDropdownListContent({
    required this.employees,
    required this.selectedEmployeeId,
    required this.searchController,
    required this.onSelect,
  });

  final List<EmployeePreview> employees;
  final String? selectedEmployeeId;
  final TextEditingController searchController;
  final ValueChanged<String?> onSelect;

  @override
  State<_EmployeeDropdownListContent> createState() =>
      _EmployeeDropdownListContentState();
}

class _EmployeeDropdownListContentState
    extends State<_EmployeeDropdownListContent> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.searchController.text;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final filtered = widget.employees.where((emp) {
      if (q.isEmpty) return true;
      final nameMatches = emp.name.toLowerCase().contains(q);
      final idMatches = emp.idNumber.toLowerCase().contains(q);
      final deptMatches = emp.departmentName.toLowerCase().contains(q);
      final posMatches = emp.positionName.toLowerCase().contains(q);
      final emailMatches = (emp.email ?? '').toLowerCase().contains(q);
      return nameMatches || idMatches || deptMatches || posMatches || emailMatches;
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: widget.searchController,
              autofocus: true,
              onChanged: (val) => setState(() => _query = val),
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search employee name or ID...',
                hintStyle: const TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          widget.searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: HygColors.goldStrong, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (q.isEmpty || 'no linked employee'.contains(q) || 'none'.contains(q))
                InkWell(
                  onTap: () => widget.onSelect(null),
                  hoverColor: const Color(0xFFF8FAFC),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.person_off_outlined, size: 18, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'No linked employee',
                            style: TextStyle(
                              fontFamily: HygTypography.bodyFontFamily,
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        if (widget.selectedEmployeeId == null || widget.selectedEmployeeId!.isEmpty)
                          const Icon(Icons.check, size: 16, color: HygColors.goldStrong),
                      ],
                    ),
                  ),
                ),
              for (final emp in filtered)
                InkWell(
                  onTap: () => widget.onSelect(emp.id),
                  hoverColor: const Color(0xFFF8FAFC),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: emp.avatarColor.withValues(alpha: 0.15),
                          child: Text(
                            emp.initial,
                            style: TextStyle(
                              color: emp.avatarColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                emp.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 13,
                                  fontWeight: emp.id == widget.selectedEmployeeId
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${emp.idNumber}${emp.positionName.isNotEmpty ? '  •  ${emp.positionName}' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (emp.id == widget.selectedEmployeeId)
                          const Icon(Icons.check, size: 16, color: HygColors.goldStrong),
                      ],
                    ),
                  ),
                ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Column(
                    children: [
                      const Icon(Icons.person_search_outlined, size: 28, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 6),
                      Text(
                        'No employees matching "$_query"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HygTypography.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HygColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: HygTypography.body.copyWith(
                          fontSize: 11.5,
                          color: HygColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFEF3C7) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF92400E) : const Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class UserBanDialog extends StatelessWidget {
  const UserBanDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  Widget build(BuildContext context) {
    final action = user.isBanned ? 'Unban' : 'Ban';
    final isUnban = user.isBanned;
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isUnban
                          ? const Color(0xFFFFF7D6)
                          : const Color(0xFFFFE7E7),
                      border: Border.all(
                        color: isUnban
                            ? const Color(0xFFF4D77A)
                            : const Color(0xFFF9B4B4),
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isUnban ? Icons.lock_open_outlined : Icons.block,
                      color: isUnban
                          ? const Color(0xFF8A5A00)
                          : const Color(0xFFB91C1C),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm $action',
                      style: HygTypography.pageTitle.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1DFA2)),
              const SizedBox(height: 18),
              Text(
                isUnban
                    ? 'Restore login access for this user?'
                    : 'Block login access for this user?',
                style: HygTypography.body.copyWith(
                  color: HygColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isUnban
                    ? '${user.username} will be able to sign in again.'
                    : '${user.username} will no longer be able to sign in.',
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF7A6320),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  border: Border.all(color: const Color(0xFFF1DFA2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Color(0xFF9A6A00),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.body.copyWith(
                              color: HygColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.body.copyWith(
                              color: const Color(0xFF7A6320),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: HygColors.border),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    width: 104,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: HygColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 40,
                    width: 124,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isUnban
                            ? const Color(0xFFF6C400)
                            : const Color(0xFFDC2626),
                        foregroundColor: isUnban ? HygColors.ink : Colors.white,
                        textStyle: HygTypography.button.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: Icon(isUnban ? Icons.check : Icons.block, size: 16),
                      label: Text(action),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserRoleDialogResult {
  final String role;
  final List<String>? companyIds;

  UserRoleDialogResult({required this.role, this.companyIds});
}

class UserRoleDialog extends StatefulWidget {
  const UserRoleDialog({
    required this.user,
    required this.companies,
    super.key,
  });

  final RegisteredUserPreview user;
  final List<CompanyPreview> companies;

  @override
  State<UserRoleDialog> createState() => _UserRoleDialogState();
}

class _UserRoleDialogState extends State<UserRoleDialog> {
  late String _role = widget.user.appRole.toLowerCase();
  final List<String> _selectedCompanyIds = [];
  bool _isLoadingAssignments = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCompanyAssignments();
  }

  Future<void> _loadCompanyAssignments() async {
    setState(() => _isLoadingAssignments = true);
    final assignments = await RegisteredUsersService.loadUserCompanyAssignments(
      widget.user.userProfileId,
    );
    if (mounted) {
      setState(() {
        _selectedCompanyIds.clear();
        _selectedCompanyIds.addAll(assignments);
        _isLoadingAssignments = false;
      });
    }
  }

  void _submit() {
    if (_role == 'hr' && _selectedCompanyIds.isEmpty) {
      setState(() => _error = 'Please select at least one company.');
      return;
    }
    Navigator.of(context).pop(
      UserRoleDialogResult(
        role: _role,
        companyIds: _selectedCompanyIds,
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: HygTypography.body.copyWith(
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompaniesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Link Companies',
          style: HygTypography.body.copyWith(
            color: HygColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        widget.companies.isNotEmpty
            ? Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.companies.length,
                  itemBuilder: (context, index) {
                    final company = widget.companies[index];
                    final isSelected = _selectedCompanyIds.contains(company.id);
                    return CheckboxListTile(
                      activeColor: HygColors.gold,
                      checkColor: HygColors.ink,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                company.initials,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: HygColors.goldStrong,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              company.name,
                              style: HygTypography.body.copyWith(
                                fontSize: 14,
                                color: HygColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      value: isSelected,
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedCompanyIds.add(company.id);
                          } else {
                            _selectedCompanyIds.remove(company.id);
                          }
                          _error = null;
                        });
                      },
                    );
                  },
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No companies have been added yet.',
                        style: HygTypography.body.copyWith(
                          fontSize: 12.5,
                          color: HygColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const roles = ['employee', 'hr', 'admin', 'super_admin'];
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D6),
                        border: Border.all(color: const Color(0xFFF4D77A)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Color(0xFF8A5A00),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Confirm Role Change',
                        style: HygTypography.pageTitle.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: HygColors.border),
                const SizedBox(height: 18),
                Text(
                  'Choose the access role for this user.',
                  style: HygTypography.body.copyWith(
                    color: HygColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.user.username} currently has the ${widget.user.appRole} role.',
                  style: HygTypography.body.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: HygColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HygTypography.body.copyWith(
                                color: HygColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HygTypography.body.copyWith(
                                color: const Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in roles)
                      ChoiceChip(
                        label: Text(
                          role.toUpperCase(),
                          style: HygTypography.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _role == role
                                ? HygColors.ink
                                : const Color(0xFF7A6320),
                          ),
                        ),
                        selected: _role == role,
                        onSelected: (_) {
                          setState(() {
                            _role = role;
                            _error = null;
                          });
                        },
                        selectedColor: const Color(0xFFFFF3B0),
                        backgroundColor: const Color(0xFFFFFCF2),
                        side: BorderSide(
                          color: _role == role
                              ? const Color(0xFFE4C24D)
                              : const Color(0xFFF1DFA2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _isLoadingAssignments
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: HygColors.gold,
                            ),
                          ),
                        ),
                      )
                    : _buildCompaniesSection(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorBanner(),
                ],
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFF1DFA2)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 40,
                      width: 104,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7A6320),
                          side: const BorderSide(color: Color(0xFFF1DFA2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 40,
                      width: 124,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF6C400),
                          foregroundColor: HygColors.ink,
                          textStyle: HygTypography.button.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _submit,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserPasswordDialog extends StatefulWidget {
  const UserPasswordDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  State<UserPasswordDialog> createState() => _UserPasswordDialogState();
}

class _UserPasswordDialogState extends State<UserPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7D6),
                      border: Border.all(color: const Color(0xFFF4D77A)),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.password_outlined,
                      color: Color(0xFF8A5A00),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm Password Change',
                      style: HygTypography.pageTitle.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1DFA2)),
              const SizedBox(height: 18),
              Text(
                'Set a new login password for this user.',
                style: HygTypography.body.copyWith(
                  color: HygColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The new password must be at least 6 characters.',
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF7A6320),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  border: Border.all(color: const Color(0xFFF1DFA2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Color(0xFF9A6A00),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.body.copyWith(
                              color: HygColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.body.copyWith(
                              color: const Color(0xFF7A6320),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ModalTextField(
                controller: _passwordController,
                label: 'New Password',
                required: true,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  focusNode: FocusNode(skipTraversal: true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF64748B),
                    size: 18,
                  ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              ModalTextField(
                controller: _confirmController,
                label: 'Confirm Password',
                required: true,
                obscureText: _obscureConfirm,
                suffixIcon: IconButton(
                  focusNode: FocusNode(skipTraversal: true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF64748B),
                    size: 18,
                  ),
                  tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: HygTypography.body.copyWith(
                    color: const Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFFF1DFA2)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    width: 104,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7A6320),
                        side: const BorderSide(color: Color(0xFFF1DFA2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 40,
                    width: 142,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF6C400),
                        foregroundColor: HygColors.ink,
                        textStyle: HygTypography.button.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum LeaveCreditMode { set, deduct, reimburse }

class UserLeaveCreditsResult {
  const UserLeaveCreditsResult({
    required this.amount,
    required this.mode,
  });

  final double amount;
  final LeaveCreditMode mode;
}

class UserLeaveCreditsDialog extends StatefulWidget {
  const UserLeaveCreditsDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  State<UserLeaveCreditsDialog> createState() => _UserLeaveCreditsDialogState();
}

class _UserLeaveCreditsDialogState extends State<UserLeaveCreditsDialog> {
  late final TextEditingController _creditsController;
  late final TextEditingController _reimburseController;
  late final TextEditingController _deductController;
  String? _error;
  String? _reimburseError;
  String? _deductError;
  DateTime? _hiredDate;
    String? _employeeType;
  String? _positionName;
  double? _suggestedCredits;

  @override
  void initState() {
    super.initState();
    _creditsController = TextEditingController(
      text: _formatInitialValue(widget.user.leaveCreditDays ?? 0),
    );
    _reimburseController = TextEditingController();
    _deductController = TextEditingController();
    _loadEmployeeHiredDate();
  }

  Future<void> _loadEmployeeHiredDate() async {
    final empId = widget.user.employeeId;
    if (empId == null || empId.trim().isEmpty) {
      return;
    }
        try {
      final details = await EmployeeDirectoryService.loadEmployeeProfile(
        empId,
      );
      if (details != null) {
        _hiredDate = _parseDateString(details.dateHired);
        _employeeType = details.employeeType;
        _positionName = details.positionName;
        final suggested = _calculateSuggestedLeaveCredits();
        setState(() {
          _suggestedCredits = suggested;
        });
        if (widget.user.leaveCreditDays == null) {
          _creditsController.text = _formatInitialValue(suggested);
        }
      }
    } catch (_) {}
  }

  double _calculateSuggestedLeaveCredits() {
    if (_hiredDate == null) {
      return widget.user.leaveCreditDays ?? 0;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oneYearAnniversary = DateTime(
      _hiredDate!.year + 1,
      _hiredDate!.month,
      _hiredDate!.day,
    );
    final hasCompletedOneYear = !today.isBefore(oneYearAnniversary);
    if (!hasCompletedOneYear) {
      return 0;
    }
    final posName = _positionName?.trim().toLowerCase() ?? '';
    final isExcluded = posName.contains('operations director') ||
        posName.contains('finance director') ||
        posName.contains('general manager');
    if (isExcluded) {
      return 0;
    }
    final isManager = posName.contains('manager');
    final empType = _employeeType?.trim().toLowerCase() ?? '';
    final isRegular = empType == 'regular';
    if (!isManager && !isRegular) {
      return 0;
    }

    final annivYear = oneYearAnniversary.year;
    final annivMonth = oneYearAnniversary.month;
    final currentYear = today.year;

    if (currentYear > annivYear) {
      // Subsequent years: full allocation
      return isManager ? 7 : 5;
    } else if (currentYear == annivYear) {
      // 1-Year Tenure Anniversary Year: based on anniversary month
      if (isManager) {
        if (annivMonth <= 2) return 7;
        if (annivMonth <= 4) return 6;
        if (annivMonth <= 6) return 5;
        if (annivMonth <= 8) return 4;
        if (annivMonth <= 10) return 2;
        if (annivMonth == 11) return 1;
        return 0;
      } else {
        // Regular Employees
        if (annivMonth <= 2) return 5;
        if (annivMonth <= 4) return 4;
        if (annivMonth <= 7) return 3;
        if (annivMonth <= 9) return 2;
        if (annivMonth <= 11) return 1;
        return 0;
      }
    }
    return 0;
  }

  double _calculateMonthlyUsableLeaveCredits(double allocated) {
    if (_hiredDate == null || allocated <= 0) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oneYearAnniversary = DateTime(
      _hiredDate!.year + 1,
      _hiredDate!.month,
      _hiredDate!.day,
    );
    if (today.isBefore(oneYearAnniversary)) return 0;
    final posName = _positionName?.trim().toLowerCase() ?? '';
    final isExcluded = posName.contains('operations director') ||
        posName.contains('finance director') ||
        posName.contains('general manager');
    if (isExcluded) return allocated;
    final isManager = posName.contains('manager');
    final month = today.month;
    double usableCap;
    if (isManager) {
      if (month <= 2) {
        usableCap = 1;
      } else if (month <= 4) {
        usableCap = 2;
      } else if (month <= 6) {
        usableCap = 3;
      } else if (month <= 8) {
        usableCap = 4;
      } else if (month <= 10) {
        usableCap = 5;
      } else if (month == 11) {
        usableCap = 6;
      } else {
        usableCap = 7;
      }
    } else {
      if (month <= 2) {
        usableCap = 1;
      } else if (month <= 5) {
        usableCap = 2;
      } else if (month <= 8) {
        usableCap = 3;
      } else if (month <= 10) {
        usableCap = 4;
      } else {
        usableCap = 5;
      }
    }
    return allocated < usableCap ? allocated : usableCap;
  }

  DateTime? _parseDateString(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final s = text.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
      return DateTime.tryParse(s);
    }
    final parts = s.split('/');
    if (parts.length == 3) {
      final m = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (m != null && d != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return DateTime.tryParse(s);
  }

  @override
  void dispose() {
    _creditsController.dispose();
    _reimburseController.dispose();
    _deductController.dispose();
    super.dispose();
  }

  void _submitCredits() {
    final value = double.tryParse(_creditsController.text.trim());
    final usedDays = widget.user.leaveUsedDays ?? 0;

    if (value == null || value < 0) {
      setState(() => _error = 'Enter zero or higher leave credits.');
      return;
    }

    if (value < usedDays) {
      setState(
        () => _error =
            'Credits cannot be lower than used leave (${_formatDays(usedDays)}).',
      );
      return;
    }
    Navigator.of(context).pop(
      UserLeaveCreditsResult(amount: value, mode: LeaveCreditMode.set),
    );
  }

  bool get _isDirectorOrGm {
    final posName = _positionName?.trim().toLowerCase() ?? '';
    return posName.contains('operations director') ||
        posName.contains('finance director') ||
        posName.contains('general manager');
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _getPolicyStatusSubtitle() {
    if (_isDirectorOrGm) {
      return 'Executive / Director: Not bound by tenure policy. Admin can allocate credits freely.';
    }
    if (_hiredDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final anniv = DateTime(
        _hiredDate!.year + 1,
        _hiredDate!.month,
        _hiredDate!.day,
      );
      if (today.isBefore(anniv)) {
        return 'Under 1-year tenure: Automatically receives 0 leave credits until anniversary (${_formatDate(anniv)}).';
      }
    }
    final isManager = (_positionName?.toLowerCase() ?? '').contains('manager');
    return 'Leave credits are automatically allocated based on policy (${isManager ? "Manager quota: 7 days" : "Regular employee quota: 5 days"}).';
  }

  void _submitReimburse() {
    final reimburseDays = double.tryParse(_reimburseController.text.trim());
    if (reimburseDays == null || reimburseDays <= 0) {
      setState(() => _reimburseError = 'Enter a number greater than zero.');
      return;
    }

    // If regular employee or manager (not General Manager, Operations Director, or Finance Director),
    // enforce the leave credit allocation policy!
    if (!_isDirectorOrGm) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_hiredDate != null) {
        final oneYearAnniversary = DateTime(
          _hiredDate!.year + 1,
          _hiredDate!.month,
          _hiredDate!.day,
        );
        if (today.isBefore(oneYearAnniversary)) {
          setState(() => _reimburseError =
              'Cannot reimburse: Employee has not reached 1-year tenure under the policy (Anniversary: ${_formatDate(oneYearAnniversary)}).');
          return;
        }
      } else if (widget.user.employmentStatus.toLowerCase() == 'probationary') {
        setState(() => _reimburseError =
            'Cannot reimburse: Probationary employee has not completed 1-year tenure under the policy.');
        return;
      }

      final posName = _positionName?.trim().toLowerCase() ?? '';
      final isManager = posName.contains('manager');
      final maxQuota = isManager ? 7.0 : 5.0;
      final policyAllocated = _suggestedCredits ?? maxQuota;
      final effectiveAllocatedLimit =
          policyAllocated > 0 ? policyAllocated : maxQuota;

      final currentAnnual = widget.user.leaveCreditDays ?? 0;
      final usedDays = widget.user.leaveUsedDays ?? 0;
      final excess = reimburseDays > usedDays ? reimburseDays - usedDays : 0.0;
      final resultingAnnual = currentAnnual + excess;

      if (resultingAnnual > effectiveAllocatedLimit) {
        setState(() => _reimburseError =
            'Reimbursement would increase annual credits to ${_formatDays(resultingAnnual)}, exceeding the ${_formatDays(effectiveAllocatedLimit)} policy limit for ${isManager ? "managers" : "regular employees"}.');
        return;
      }
    }

    Navigator.of(context).pop(
      UserLeaveCreditsResult(
        amount: reimburseDays,
        mode: LeaveCreditMode.reimburse,
      ),
    );
  }

  void _submitDeduct() {
    final deductDays = double.tryParse(_deductController.text.trim());
    final currentAnnual = widget.user.leaveCreditDays ?? 0;
    final usedDays = widget.user.leaveUsedDays ?? 0;
    final remainingDays = currentAnnual - usedDays;
    if (deductDays == null || deductDays <= 0) {
      setState(() => _deductError = 'Enter a number greater than zero.');
      return;
    }
    if (deductDays > remainingDays) {
      setState(
        () => _deductError =
            'Cannot deduct more than remaining credits (${_formatDays(remainingDays)}).',
      );
      return;
    }
    Navigator.of(context).pop(
      UserLeaveCreditsResult(
        amount: deductDays,
        mode: LeaveCreditMode.deduct,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAnnual = widget.user.leaveCreditDays ?? 0;
    final usedDays = widget.user.leaveUsedDays ?? 0;
    final remainingDays = widget.user.leaveRemainingDays ?? 0;
    final usableNow = _calculateMonthlyUsableLeaveCredits(currentAnnual);
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      color: HygColors.goldStrong,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Allocate Leave Credits',
                        style: HygTypography.pageTitle.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.user.fullName,
                  style: HygTypography.tableBody.copyWith(
                    color: HygColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Annual: ${_formatDays(currentAnnual)}  •  Usable this month: ${_formatDays(usableNow)}  •  Used: ${_formatDays(usedDays)}  •  Remaining: ${_formatDays(remainingDays)}',
                  style: HygTypography.tableBody.copyWith(color: HygColors.muted),
                ),
                const SizedBox(height: 16),
                if (_isDirectorOrGm) ...[
                  TextField(
                    controller: _creditsController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Annual leave credits (Executive / Director)',
                      hintText: 'Enter credits',
                      errorText: _error,
                      suffixText: 'days',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _submitCredits(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Executive / Director role: not bound by standard tenure policy. Admin can allocate regardless of the policy.',
                    style: HygTypography.body.copyWith(
                      color: HygColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HygColors.gold,
                          foregroundColor: HygColors.ink,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _submitCredits,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save Credits'),
                      ),
                    ],
                  ),
                ] else ...[
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Annual leave credits',
                      suffixText: 'days',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _formatInitialValue(currentAnnual),
                      style: HygTypography.body.copyWith(
                        color: HygColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 15,
                        color: HygColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getPolicyStatusSubtitle(),
                          style: HygTypography.body.copyWith(
                            color: HygColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.add_circle_outline,
                                color: Color(0xFF16A34A),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Reimburse Leave Credit',
                                  style: HygTypography.tableBody.copyWith(
                                    color: HygColors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add credit to remaining balance whenever a deduction problem occurs.',
                            style: HygTypography.tableBody.copyWith(
                              color: HygColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _reimburseController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Days to reimburse',
                              hintText: 'Enter days',
                              errorText: _reimburseError,
                              suffixText: 'days',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onSubmitted: (_) => _submitReimburse(),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _submitReimburse,
                              icon: const Icon(Icons.add_outlined, size: 18),
                              label: const Text('Reimburse'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.remove_circle_outline,
                                color: Color(0xFFDC2626),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Manual Deduction',
                                  style: HygTypography.tableBody.copyWith(
                                    color: HygColors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Deduct days from annual credits to match current leave.',
                            style: HygTypography.tableBody.copyWith(
                              color: HygColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deductController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Days to deduct',
                              hintText: 'Enter days',
                              errorText: _deductError,
                              suffixText: 'days',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onSubmitted: (_) => _submitDeduct(),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _submitDeduct,
                              icon: const Icon(Icons.remove_outlined, size: 18),
                              label: const Text('Deduct'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatInitialValue(double value) {
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  static String _formatDays(double value) {
    return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}d';
  }
}

enum OffsetBalanceMode { set, add, deduct }

class UserOffsetBalanceResult {
  const UserOffsetBalanceResult({
    required this.amount,
    required this.mode,
    this.reason,
  });

  final double amount;
  final OffsetBalanceMode mode;
  final String? reason;
}

class UserOffsetBalanceDialog extends StatefulWidget {
  const UserOffsetBalanceDialog({
    required this.user,
    super.key,
  });

  final RegisteredUserPreview user;

  @override
  State<UserOffsetBalanceDialog> createState() =>
      _UserOffsetBalanceDialogState();
}

class _UserOffsetBalanceDialogState extends State<UserOffsetBalanceDialog> {
  final _addController = TextEditingController();
  final _deductController = TextEditingController();

  int _selectedAdjustmentTab = 0;
  String? _addError;
  String? _deductError;

  @override
  void dispose() {
    _addController.dispose();
    _deductController.dispose();
    super.dispose();
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color accentColor,
    required IconData icon,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        title: Row(
          children: [
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: HygTypography.pageTitle.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: HygTypography.body.copyWith(
            color: HygColors.ink,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submitAdd() async {
    final addHours = double.tryParse(_addController.text.trim());
    if (addHours == null || addHours <= 0) {
      setState(() => _addError = 'Enter a number greater than zero.');
      return;
    }
    final currentBalance = widget.user.offsetBalanceHours ?? 0;
    final newBalance = currentBalance + addHours;
    final confirmed = await _confirmAction(
      title: 'Confirm Add Offset Hours',
      message:
          'Are you sure you want to add ${_formatHours(addHours)} to ${widget.user.fullName}?\n\n'
          'Current balance: ${_formatHours(currentBalance)}\n'
          'New balance: ${_formatHours(newBalance)}',
      confirmLabel: 'Confirm & Add',
      accentColor: const Color(0xFF16A34A),
      icon: Icons.add_circle_outline,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(
      UserOffsetBalanceResult(
        amount: addHours,
        mode: OffsetBalanceMode.add,
      ),
    );
  }

  Future<void> _submitDeduct() async {
    final deductHours = double.tryParse(_deductController.text.trim());
    final currentBalance = widget.user.offsetBalanceHours ?? 0;
    if (deductHours == null || deductHours <= 0) {
      setState(() => _deductError = 'Enter a number greater than zero.');
      return;
    }
    if (deductHours > currentBalance) {
      setState(
        () => _deductError =
            'Cannot deduct more than available offset balance (${_formatHours(currentBalance)}).',
      );
      return;
    }
    final newBalance = currentBalance - deductHours;
    final confirmed = await _confirmAction(
      title: 'Confirm Offset Deduction',
      message:
          'Are you sure you want to deduct ${_formatHours(deductHours)} from ${widget.user.fullName}?\n\n'
          'Current balance: ${_formatHours(currentBalance)}\n'
          'New balance: ${_formatHours(newBalance)}',
      confirmLabel: 'Confirm & Deduct',
      accentColor: const Color(0xFFDC2626),
      icon: Icons.remove_circle_outline,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(
      UserOffsetBalanceResult(
        amount: deductHours,
        mode: OffsetBalanceMode.deduct,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentBalance = widget.user.offsetBalanceHours ?? 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.timelapse_outlined,
                      color: HygColors.goldStrong,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Allocate Offset Balance',
                        style: HygTypography.pageTitle.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.user.fullName,
                  style: HygTypography.tableBody.copyWith(
                    color: HygColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.user.employeeNo.isNotEmpty &&
                          widget.user.employeeNo != '-'
                      ? 'Employee No: ${widget.user.employeeNo}'
                      : widget.user.email,
                  style: HygTypography.tableBody.copyWith(
                    color: HygColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Current offset balance',
                    suffixText: 'hrs',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    _formatInitialValue(currentBalance),
                    style: HygTypography.body.copyWith(
                      color: HygColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF16A34A),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Manual additions or deductions directly update the offset balance and do not affect leave credits or annual allocations.',
                          style: HygTypography.body.copyWith(
                            color: const Color(0xFF166534),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedAdjustmentTab = 0),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _selectedAdjustmentTab == 0
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedAdjustmentTab == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  size: 17,
                                  color: _selectedAdjustmentTab == 0
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Add Offset Hours',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedAdjustmentTab == 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedAdjustmentTab == 0
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedAdjustmentTab = 1),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _selectedAdjustmentTab == 1
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedAdjustmentTab == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.remove_circle_outline,
                                  size: 17,
                                  color: _selectedAdjustmentTab == 1
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Manual Deduction',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedAdjustmentTab == 1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedAdjustmentTab == 1
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_selectedAdjustmentTab == 0) ...[
                  Text(
                    'Add hours to current offset balance.',
                    style: HygTypography.tableBody.copyWith(
                      color: HygColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _addController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Hours to add',
                      hintText: 'Enter hours',
                      errorText: _addError,
                      suffixText: 'hrs',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _submitAdd(),
                  ),
                ] else ...[
                  Text(
                    'Deduct hours from available offset balance.',
                    style: HygTypography.tableBody.copyWith(
                      color: HygColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _deductController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Hours to deduct',
                      hintText: 'Enter hours',
                      errorText: _deductError,
                      suffixText: 'hrs',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _submitDeduct(),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HygColors.gold,
                        foregroundColor: HygColors.ink,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _selectedAdjustmentTab == 0
                          ? _submitAdd
                          : _submitDeduct,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatInitialValue(double value) {
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  static String _formatHours(double value) {
    return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)} hrs';
  }
}

class _ViewModeSwitcher extends StatelessWidget {
  const _ViewModeSwitcher({
    required this.currentMode,
    required this.accountsCount,
    required this.transactionsCount,
    required this.onModeChanged,
  });

  final UsersPanelViewMode currentMode;
  final int accountsCount;
  final int transactionsCount;
  final ValueChanged<UsersPanelViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabItem(
            icon: Icons.people_alt_outlined,
            label: 'User Accounts',
            count: accountsCount,
            isSelected: currentMode == UsersPanelViewMode.accounts,
            onTap: () => onModeChanged(UsersPanelViewMode.accounts),
          ),
          const SizedBox(width: 4),
          _TabItem(
            icon: Icons.receipt_long_outlined,
            label: 'Balance Transactions History',
            count: transactionsCount,
            isSelected: currentMode == UsersPanelViewMode.transactions,
            onTap: () => onModeChanged(UsersPanelViewMode.transactions),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionsSummaryCard extends StatelessWidget {
  const TransactionsSummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    super.key,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: HygColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.tablePrimary.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: HygColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsTable extends StatefulWidget {
  const _TransactionsTable({
    required this.items,
    required this.onTapRow,
  });

  final List<BalanceTransactionRecord> items;
  final void Function(BalanceTransactionRecord) onTapRow;

  @override
  State<_TransactionsTable> createState() => _TransactionsTableState();
}

class _TransactionsTableState extends State<_TransactionsTable> {
  static const double _kFloatingBarHeight = 26.0;
  static const double _kBottomDockInset = 4.0;
  static const double _kViewportBottomClearance = 10.0;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _floatingScrollController = ScrollController();
  final ValueNotifier<double> _floatingBarY = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _isFloatingBarVisible = ValueNotifier<bool>(false);

  ScrollPosition? _ancestorPosition;
  ScrollableState? _ancestorScrollable;
  bool _isSyncingScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onTableScroll);
    _floatingScrollController.addListener(_onFloatingScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFloatingPosition();
    });
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
  void didUpdateWidget(_TransactionsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (_floatingScrollController.hasClients) {
        _floatingScrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateFloatingPosition();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onTableScroll);
    _floatingScrollController.removeListener(_onFloatingScroll);
    _ancestorPosition?.removeListener(_onAncestorScroll);
    _scrollController.dispose();
    _floatingScrollController.dispose();
    _floatingBarY.dispose();
    _isFloatingBarVisible.dispose();
    super.dispose();
  }

  void _onTableScroll() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    try {
      if (_floatingScrollController.hasClients && _scrollController.hasClients) {
        final target = _scrollController.offset.clamp(
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
      if (_scrollController.hasClients && _floatingScrollController.hasClients) {
        final target = _floatingScrollController.offset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        if ((_scrollController.offset - target).abs() > 0.5) {
          _scrollController.jumpTo(target);
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

    final tableRenderObject = context.findRenderObject();
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final rowWidth = math.max(availableWidth, 1220.0);
        final needsHorizontalScroll = rowWidth > availableWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateFloatingPosition();
        });

        return Stack(
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
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(bottom: needsHorizontalScroll ? 36 : 8),
                child: SizedBox(
                  width: rowWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TransactionsTableHeader(),
                      const SizedBox(height: 8),
                      ...widget.items.map(
                        (item) => TransactionRow(
                          record: item,
                          onTap: () => widget.onTapRow(item),
                        ),
                      ),
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
                        left: 0,
                        right: 0,
                        child: _buildFloatingScrollbar(availableWidth, rowWidth),
                      );
                    },
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class TransactionsTableHeader extends StatelessWidget {
  const TransactionsTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: HygColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          SizedBox(width: 130, child: HeaderLabel('DATE & TIME')),
          SizedBox(width: 240, child: HeaderLabel('EMPLOYEE')),
          SizedBox(width: 155, child: HeaderLabel('BALANCE TYPE')),
          SizedBox(width: 115, child: HeaderLabel('CATEGORY')),
          SizedBox(width: 120, child: HeaderLabel('AMOUNT')),
          SizedBox(width: 115, child: HeaderLabel('BALANCE AFTER')),
          Expanded(child: HeaderLabel('REASON / ACTOR')),
          SizedBox(
            width: 44,
            child: Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class TransactionRow extends StatefulWidget {
  const TransactionRow({
    required this.record,
    required this.onTap,
    super.key,
  });

  final BalanceTransactionRecord record;
  final VoidCallback onTap;

  @override
  State<TransactionRow> createState() => _TransactionRowState();
}

class _TransactionRowState extends State<TransactionRow> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final rowColor = _isHovered ? const Color(0xFFF8FAFC) : Colors.white;

    final dateStr = record.createdAt.toIso8601String().replaceFirst('T', ' ').substring(0, 16);
    final isPos = record.amount >= 0;
    final amountPrefix = isPos ? '+' : '';
    final amountStr = '$amountPrefix${record.amount.toStringAsFixed(record.amount.truncateToDouble() == record.amount ? 0 : 2)} ${record.unit}';
    final afterStr = record.balanceAfter != null
        ? '${record.balanceAfter!.toStringAsFixed(record.balanceAfter!.truncateToDouble() == record.balanceAfter! ? 0 : 2)} ${record.unit}'
        : '—';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 60,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: rowColor,
            border: Border.all(
              color: _isHovered ? HygColors.goldStrong.withValues(alpha: 0.5) : HygColors.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // 1. Date & Time
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dateStr.split(' ')[0],
                      style: HygTypography.tablePrimary.copyWith(fontSize: 12),
                    ),
                    Text(
                      dateStr.contains(' ') ? dateStr.split(' ')[1] : '',
                      style: HygTypography.body.copyWith(
                        fontSize: 11,
                        color: HygColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              // 2. Employee
              SizedBox(
                width: 240,
                child: Row(
                  children: [
                    _UserInitialAvatarSimple(
                      name: record.fullName.isNotEmpty ? record.fullName : record.username,
                      photoUrl: record.photoUrl,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            record.fullName.isNotEmpty ? record.fullName : record.username,
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.tablePrimary.copyWith(fontSize: 13),
                          ),
                          Text(
                            record.employeeNo.isNotEmpty
                                ? '${record.employeeNo} • @${record.username}'
                                : '@${record.username}',
                            overflow: TextOverflow.ellipsis,
                            style: HygTypography.body.copyWith(
                              fontSize: 11,
                              color: HygColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 3. Balance Type
              SizedBox(
                width: 155,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _BalanceTypeBadge(balanceType: record.balanceType),
                ),
              ),
              // 4. Category
              SizedBox(
                width: 115,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CategoryBadge(
                    category: record.category,
                    isPositive: isPos,
                  ),
                ),
              ),
              // 5. Amount
              SizedBox(
                width: 120,
                child: Text(
                  amountStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isPos
                        ? (record.isLeave ? const Color(0xFFD97706) : const Color(0xFF0D9488))
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
              // 6. Balance After
              SizedBox(
                width: 115,
                child: Text(
                  afterStr,
                  style: HygTypography.tableBody.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),
              // 7. Reason / Actor
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      record.reason?.trim().isNotEmpty == true
                          ? record.reason!
                          : record.title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: HygTypography.tablePrimary.copyWith(fontSize: 12),
                    ),
                    if (record.actorName?.trim().isNotEmpty == true)
                      Text(
                        'by ${record.actorName}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: HygTypography.body.copyWith(
                          fontSize: 11,
                          color: HygColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              // 8. Action button
              SizedBox(
                width: 44,
                child: Center(
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'View details',
                    onPressed: widget.onTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceTypeBadge extends StatelessWidget {
  const _BalanceTypeBadge({required this.balanceType});

  final String balanceType;

  @override
  Widget build(BuildContext context) {
    final isLeave = balanceType.toLowerCase() == 'leave';
    final bgColor = isLeave ? const Color(0xFFFEF3C7) : const Color(0xFFCCFBF1);
    final textColor = isLeave ? const Color(0xFF92400E) : const Color(0xFF0F766E);
    final icon = isLeave ? Icons.event_available_outlined : Icons.timelapse_outlined;
    final label = isLeave ? 'LEAVE CREDIT' : 'OFFSET BALANCE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({
    required this.category,
    required this.isPositive,
  });

  final String category;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    String label = category.toUpperCase();

    switch (category.toLowerCase()) {
      case 'allocation':
      case 'grant':
      case 'policy':
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF15803D);
        label = 'ALLOCATION';
        break;
      case 'deduction':
      case 'deduct':
        bg = const Color(0xFFFFE4E6);
        text = const Color(0xFFBE123C);
        label = 'DEDUCTION';
        break;
      case 'use':
      case 'use_paid':
        bg = const Color(0xFFFEE2E2);
        text = const Color(0xFFB91C1C);
        label = 'USED';
        break;
      case 'earn':
        bg = const Color(0xFFE0F2FE);
        text = const Color(0xFF0369A1);
        label = 'EARNED';
        break;
      case 'refund':
      case 'reimburse':
        bg = const Color(0xFFE0E7FF);
        text = const Color(0xFF4338CA);
        label = 'REIMBURSE';
        break;
      case 'adjustment':
      case 'set':
        bg = const Color(0xFFF3E8FF);
        text = const Color(0xFF6B21A8);
        label = 'MANUAL SET';
        break;
      default:
        bg = isPositive ? const Color(0xFFDCFCE7) : const Color(0xFFFFE4E6);
        text = isPositive ? const Color(0xFF15803D) : const Color(0xFFBE123C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

class _UserInitialAvatarSimple extends StatelessWidget {
  const _UserInitialAvatarSimple({
    required this.name,
    this.photoUrl,
    this.size = 32,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cleanPhoto = photoUrl?.trim() ?? '';
    final initial = name.trim().isNotEmpty ? name.trim().substring(0, 1).toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: cleanPhoto.isEmpty
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: HygColors.ink,
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Image.network(
              cleanPhoto,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: HygColors.ink,
                    fontSize: size * 0.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );
  }
}

class UserTransactionHistoryDialog extends StatefulWidget {
  const UserTransactionHistoryDialog({
    required this.user,
    this.initialTab = 'all',
    this.onSetLeaveCredits,
    this.onSetOffsetBalance,
    super.key,
  });

  final RegisteredUserPreview user;
  final String initialTab;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays, [
    LeaveCreditMode mode,
  ])? onSetLeaveCredits;
  final Future<void> Function(
    RegisteredUserPreview user,
    double balanceHours, [
    OffsetBalanceMode mode,
    String? reason,
  ])? onSetOffsetBalance;

  @override
  State<UserTransactionHistoryDialog> createState() =>
      _UserTransactionHistoryDialogState();
}

class _UserTransactionHistoryDialogState
    extends State<UserTransactionHistoryDialog> {
  late String _activeTab;
  var _isLoading = true;
  String? _error;
  List<BalanceTransactionRecord> _transactions = [];
  final _searchController = TextEditingController();
  var _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _loadUserTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await RegisteredUsersService.fetchBalanceTransactions(
        employeeId: widget.user.employeeId,
        userProfileId: widget.user.userProfileId,
        balanceType: 'all',
        registeredUsers: [widget.user],
      );
      if (!mounted) return;
      setState(() {
        _transactions = records;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<BalanceTransactionRecord> get _filteredList {
    final query = _searchQuery.trim().toLowerCase();
    return _transactions.where((t) {
      if (_activeTab != 'all' && t.balanceType != _activeTab) return false;
      if (query.isNotEmpty) {
        final matches = (t.reason?.toLowerCase().contains(query) ?? false) ||
            t.category.toLowerCase().contains(query) ||
            (t.actorName?.toLowerCase().contains(query) ?? false) ||
            t.title.toLowerCase().contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  int get _leaveCount =>
      _transactions.where((t) => t.balanceType == 'leave').length;
  int get _offsetCount =>
      _transactions.where((t) => t.balanceType == 'offset').length;

  void _exportCsv() {
    final list = _filteredList;
    if (list.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln(
      'Date,Employee,Balance Type,Category,Amount,Unit,Balance After,Reason,Performed By',
    );
    for (final item in list) {
      final dateStr = item.createdAt
          .toIso8601String()
          .replaceFirst('T', ' ')
          .substring(0, 16);
      final amt =
          '${item.amount >= 0 ? "+" : ""}${item.amount.toStringAsFixed(2)}';
      final after = item.balanceAfter != null
          ? item.balanceAfter!.toStringAsFixed(2)
          : '';
      buffer.writeln(
        '"$dateStr","${widget.user.fullName}","${item.balanceType}","${item.category}","$amt","${item.unit}","$after","${(item.reason ?? '').replaceAll('"', '""')}","${(item.actorName ?? '').replaceAll('"', '""')}"',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${list.length} transactions for ${widget.user.fullName} to clipboard as CSV!',
        ),
        backgroundColor: const Color(0xFF15803D),
      ),
    );
  }

  Future<void> _openLeaveAllocationDialog() async {
    if (widget.onSetLeaveCredits == null) return;
    final result = await showDialog<UserLeaveCreditsResult>(
      context: context,
      builder: (context) => UserLeaveCreditsDialog(user: widget.user),
    );
    if (result != null) {
      await widget.onSetLeaveCredits!(widget.user, result.amount, result.mode);
      await _loadUserTransactions();
    }
  }

  Future<void> _openOffsetAllocationDialog() async {
    if (widget.onSetOffsetBalance == null) return;
    final result = await showDialog<UserOffsetBalanceResult>(
      context: context,
      builder: (context) => UserOffsetBalanceDialog(user: widget.user),
    );
    if (result != null) {
      await widget.onSetOffsetBalance!(
        widget.user,
        result.amount,
        result.mode,
        result.reason,
      );
      await _loadUserTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final list = _filteredList;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 960,
          maxHeight: 780,
          minWidth: 700,
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: HygColors.border)),
              ),
              child: Row(
                children: [
                  UserAvatar(user: user),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              user.fullName.isNotEmpty
                                  ? user.fullName
                                  : user.username,
                              style: HygTypography.pageTitle.copyWith(
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (user.employeeNo.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  user.employeeNo,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                user.appRole,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user.username} • ${user.email.isNotEmpty ? user.email : "No email"} • Balance & Transaction History',
                          style: HygTypography.body.copyWith(
                            color: HygColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
                    tooltip: 'Refresh History',
                    onPressed: _loadUserTransactions,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF475569)),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Balances Summary Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  // Leave Credits Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.event_available_outlined,
                              color: Color(0xFFD97706),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Leave Credits',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatDaysVal(user.leaveRemainingDays)} left / ${_formatDaysVal(user.leaveCreditDays)} allocated',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF78350F),
                                  ),
                                ),
                                Text(
                                  'Used: ${_formatDaysVal(user.leaveUsedDays)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onSetLeaveCredits != null &&
                              user.employeeId != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF92400E),
                                side: const BorderSide(
                                  color: Color(0xFFF59E0B),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _openLeaveAllocationDialog,
                              icon: const Icon(Icons.edit_calendar, size: 14),
                              label: const Text(
                                'Allocate',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Offset Balance Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF99F6E4)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.timelapse_outlined,
                              color: Color(0xFF0D9488),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Available Offset Balance',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF115E59),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatHoursVal(user.offsetBalanceHours)} available',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF134E4A),
                                  ),
                                ),
                                const Text(
                                  'Earned via ESARF / Admin',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onSetOffsetBalance != null &&
                              user.employeeId != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F766E),
                                side: const BorderSide(
                                  color: Color(0xFF0D9488),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _openOffsetAllocationDialog,
                              icon: const Icon(Icons.edit_note, size: 15),
                              label: const Text(
                                'Allocate',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Filter Tabs & Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilterTabChip(
                          'all',
                          'All (${_transactions.length})',
                        ),
                        _buildFilterTabChip(
                          'leave',
                          'Leave Credits ($_leaveCount)',
                        ),
                        _buildFilterTabChip(
                          'offset',
                          'Offset Balance ($_offsetCount)',
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 220,
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: HygTypography.body.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Filter transactions...',
                        hintStyle: HygTypography.body.copyWith(
                          color: HygColors.muted,
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: HygColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: HygColors.border),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Export to CSV',
                    icon: const Icon(
                      Icons.file_download_outlined,
                      size: 20,
                      color: Color(0xFF475569),
                    ),
                    onPressed: _exportCsv,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: HygColors.border),

            // Transactions List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text(
                            'Loading employee transaction history...',
                            style: TextStyle(
                              color: HygColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFDC2626),
                                  size: 36,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _loadUserTransactions,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : list.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.receipt_long_outlined,
                                    size: 44,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No matching transactions'
                                        : 'No transactions recorded yet',
                                    style: HygTypography.tablePrimary.copyWith(
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'Try clearing your search term.'
                                        : 'Allocations, grants, earnings, and deductions will appear here.',
                                    style: HygTypography.body.copyWith(
                                      color: HygColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              itemCount: list.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final tx = list[index];
                                return _UserTransactionTile(
                                  record: tx,
                                  onTap: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (ctx) =>
                                          TransactionDetailDialog(
                                        record: tx,
                                        onViewUserHistory: null,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: HygColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    'Showing ${list.length} of ${_transactions.length} recorded transactions',
                    style: HygTypography.body.copyWith(
                      color: HygColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabChip(String value, String label) {
    final isSelected = _activeTab == value;
    return InkWell(
      onTap: () => setState(() => _activeTab = value),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF0F172A)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  static String _formatDaysVal(double? val) {
    if (val == null) return '0d';
    final fixed = val.toStringAsFixed(
      val.truncateToDouble() == val ? 0 : 2,
    );
    return '${fixed}d';
  }

  static String _formatHoursVal(double? val) {
    if (val == null) return '0 hrs';
    final fixed = val.toStringAsFixed(
      val.truncateToDouble() == val ? 0 : 2,
    );
    return '$fixed hrs';
  }
}

class _UserTransactionTile extends StatelessWidget {
  const _UserTransactionTile({
    required this.record,
    required this.onTap,
  });

  final BalanceTransactionRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPos = record.amount >= 0;
    final dateStr = record.createdAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 16);
    final amtPrefix = isPos ? '+' : '';
    final amtStr =
        '$amtPrefix${record.amount.toStringAsFixed(record.amount.truncateToDouble() == record.amount ? 0 : 2)} ${record.unit}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HygColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isPos
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFFE4E6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPos ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                size: 18,
                color: isPos
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _BalanceTypeBadge(balanceType: record.balanceType),
                      const SizedBox(width: 6),
                      _CategoryBadge(
                        category: record.category,
                        isPositive: isPos,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: HygTypography.body.copyWith(
                          fontSize: 11,
                          color: HygColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record.reason?.trim().isNotEmpty == true
                        ? record.reason!
                        : record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HygTypography.tablePrimary.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (record.actorName?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 1),
                    Text(
                      'Action by: ${record.actorName}',
                      style: HygTypography.body.copyWith(
                        fontSize: 11,
                        color: HygColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amtStr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isPos
                        ? (record.isLeave
                            ? const Color(0xFFD97706)
                            : const Color(0xFF0D9488))
                        : const Color(0xFFDC2626),
                  ),
                ),
                if (record.balanceAfter != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Balance: ${record.balanceAfter!.toStringAsFixed(record.balanceAfter!.truncateToDouble() == record.balanceAfter! ? 0 : 2)} ${record.unit}',
                    style: HygTypography.body.copyWith(
                      fontSize: 11,
                      color: HygColors.muted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionDetailDialog extends StatefulWidget {
  const TransactionDetailDialog({
    required this.record,
    this.onViewUserHistory,
    super.key,
  });

  final BalanceTransactionRecord record;
  final VoidCallback? onViewUserHistory;

  @override
  State<TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  final ScrollController _entriesScrollController = ScrollController();

  @override
  void dispose() {
    _entriesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final isPos = record.amount >= 0;
    final dateStr = record.createdAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);
    final amtPrefix = isPos ? '+' : '';
    final amtStr =
        '$amtPrefix${record.amount.toStringAsFixed(record.amount.truncateToDouble() == record.amount ? 0 : 2)} ${record.unit}';

    final hasEntryFormat =
        record.reason != null && record.reason!.contains('[Entry ');
    final entries = hasEntryFormat
        ? EsarfEntryItem.parseEsarfEntriesFromReason({
            'reason': record.reason,
            'request_id': record.requestId,
            'date_from': record.dateFrom,
            'date_to': record.dateTo,
            'total_hours': record.amount.abs(),
            'status': record.requestStatus ?? 'approved',
          })
        : <EsarfEntryItem>[];
    final hasEntries =
        entries.isNotEmpty && (entries.length > 1 || hasEntryFormat);

    final screenHeight = MediaQuery.of(context).size.height;
    final dialogMaxHeight = math.min(780.0, screenHeight * 0.9);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight:
              hasEntries ? dialogMaxHeight : math.min(560.0, dialogMaxHeight),
          minHeight: hasEntries ? math.min(540.0, dialogMaxHeight) : 0,
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: hasEntries ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPos
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPos
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: isPos
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          style: HygTypography.pageTitle.copyWith(
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          dateStr,
                          style: HygTypography.body.copyWith(
                            color: HygColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: HygColors.border),
              const SizedBox(height: 12),

              // Detail Key-Values (Fixed, not scrolling)
              _buildDetailRow(
                  'Employee', '${record.fullName} (${record.employeeNo})'),
              _buildDetailRow('Username', '@${record.username}'),
              _buildDetailRow(
                'Balance Type',
                record.isLeave ? 'Leave Credit Days' : 'Offset Hours',
              ),
              _buildDetailRow('Category', record.category.toUpperCase()),
              _buildDetailRow(
                'Amount',
                amtStr,
                valueColor: isPos
                    ? (record.isLeave
                        ? const Color(0xFFD97706)
                        : const Color(0xFF0D9488))
                    : const Color(0xFFDC2626),
                isBold: true,
              ),
              const SizedBox(height: 12),

              // Request Entries Card (THE ONLY SCROLLABLE AREA) or single Reason card
              if (hasEntries)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Header (Fixed at top of card)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            border: Border(
                                bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.layers_outlined,
                                  size: 16, color: Color(0xFF0F172A)),
                              const SizedBox(width: 8),
                              Text(
                                entries.length > 1
                                    ? 'Request Entries (${entries.length})'
                                    : 'Request Entry Details',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              if (entries.length > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFBFDBFE)),
                                  ),
                                  child: Text(
                                    '${entries.length} Entries',
                                    style: const TextStyle(
                                      color: Color(0xFF1D4ED8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Scrollable Entries Area inside the Card
                        Expanded(
                          child: Scrollbar(
                            controller: _entriesScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _entriesScrollController,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  for (int i = 0; i < entries.length; i++)
                                    _buildMultiEntryCard(
                                      context,
                                      entries[i],
                                      i + 1,
                                      record: record,
                                      isLast: i == entries.length - 1,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HygColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason / Description:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.reason?.trim().isNotEmpty == true
                            ? record.reason!
                            : 'No detailed reason provided.',
                        style: HygTypography.body.copyWith(
                          fontSize: 13,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              const Divider(height: 1, color: HygColors.border),
              const SizedBox(height: 14),

              // Footer Buttons (Fixed)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onViewUserHistory != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: HygColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.onViewUserHistory,
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: const Text('Filter History by Employee'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildMultiEntryCard(
    BuildContext context,
    EsarfEntryItem entry,
    int index, {
    required BalanceTransactionRecord record,
    bool isLast = false,
  }) {
    Color statusBg = const Color(0xFFEFF6FF);
    Color statusText = const Color(0xFF1D4ED8);
    final st = (entry.status ?? 'approved').toLowerCase();
    if (st.contains('reject')) {
      statusBg = const Color(0xFFFFE4E6);
      statusText = const Color(0xFFBE123C);
    } else if (st.contains('approv') || st.contains('valid')) {
      statusBg = const Color(0xFFDCFCE7);
      statusText = const Color(0xFF15803D);
    } else if (st.contains('pend')) {
      statusBg = const Color(0xFFFEF3C7);
      statusText = const Color(0xFFB45309);
    }

    final hrs = entry.totalHours;
    final hrsStr = hrs != null && hrs > 0
        ? '${hrs.toStringAsFixed(hrs.truncateToDouble() == hrs ? 0 : 2)} hrs'
        : null;

    final dateStr = entry.datesText.isNotEmpty
        ? entry.datesText
        : (record.dateFrom ?? 'Date not specified');

    final timeStr = entry.timesText.isNotEmpty
        ? entry.timesText
        : (entry.timeScheduleText.isNotEmpty ? entry.timeScheduleText : null);

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Entry #$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (entry.transactionType != null && entry.transactionType!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      entry.transactionType!,
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                if (hrsStr != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      hrsStr,
                      style: const TextStyle(
                        color: Color(0xFF047857),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (entry.status ?? 'approved').toUpperCase(),
                    style: TextStyle(
                      color: statusText,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Body Details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date & Time row
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (timeStr != null) ...[
                      const SizedBox(width: 14),
                      const Icon(Icons.access_time_outlined, size: 13, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ],
                ),

                // Clean Reason
                if (entry.cleanReasonText.isNotEmpty || (entry.reason != null && entry.reason!.isNotEmpty)) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Reason / Purpose:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.cleanReasonText.isNotEmpty
                        ? entry.cleanReasonText
                        : entry.reason!,
                    style: HygTypography.body.copyWith(
                      fontSize: 12.5,
                      color: const Color(0xFF334155),
                      height: 1.35,
                    ),
                  ),
                ],

                // Proof attachment(s) if any
                if (entry.proofs.isNotEmpty) ...[
                  for (int pIdx = 0; pIdx < entry.proofs.length; pIdx++) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        _RequestDetailModal._showProofPreviewDialog(
                          context,
                          entry.proofs[pIdx].proofUrl,
                          title: entry.proofs.length > 1
                              ? 'Photo Proof #${pIdx + 1} • Entry #$index'
                              : 'Photo Proof • Entry #$index',
                          proofTime: entry.proofs[pIdx].proofTime ?? entry.proofTime,
                          proofLocation: entry.proofs[pIdx].proofLocation ?? entry.proofLocation,
                          proofId: entry.proofs[pIdx].proofId ?? entry.proofId,
                          employeeName: record.fullName,
                          employeeId: record.employeeId,
                          allProofs: entry.proofs,
                          initialIndex: pIdx,
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_outlined, size: 15, color: Color(0xFF2563EB)),
                            const SizedBox(width: 6),
                            Text(
                              entry.proofs.length > 1
                                  ? 'View Attached Photo #${pIdx + 1}'
                                  : 'View Attached Proof Photo',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.open_in_new, size: 12, color: Color(0xFF2563EB)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else if (entry.proofUrl != null && entry.proofUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      _RequestDetailModal._showProofPreviewDialog(
                        context,
                        entry.proofUrl!,
                        title: 'Photo Proof • Entry #$index',
                        proofTime: entry.proofTime,
                        proofLocation: entry.proofLocation,
                        proofId: entry.proofId,
                        employeeName: record.fullName,
                        employeeId: record.employeeId,
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_outlined, size: 15, color: Color(0xFF2563EB)),
                          const SizedBox(width: 6),
                          const Text(
                            'View Attached Proof Photo',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new, size: 12, color: Color(0xFF2563EB)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: HygTypography.body.copyWith(
                color: HygColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: HygTypography.body.copyWith(
                color: valueColor ?? const Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

