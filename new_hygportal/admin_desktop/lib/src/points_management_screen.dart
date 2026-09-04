part of '../main.dart';

class PointsManagementHeader extends StatelessWidget {
  const PointsManagementHeader({
    this.onAwardPointsAll,
    super.key,
  });

  final VoidCallback? onAwardPointsAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.toll_outlined,
            color: HygColors.goldStrong,
            size: 42,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Points Management',
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontFamilyFallback: HygTypography.headingFallbacks,
                    color: HygColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Manage employee reward points, allocations, and points balance.',
                  style: TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontFamilyFallback: HygTypography.fontFallbacks,
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onAwardPointsAll != null) ...[
            const SizedBox(width: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: HygColors.gold,
                foregroundColor: HygColors.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onAwardPointsAll,
              icon: Image.asset(
                'assets/awardpoints.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
              label: const Text(
                'Award Points',
                style: TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: HygColors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PointsManagementSearchBar extends StatelessWidget {
  const PointsManagementSearchBar({
    required this.controller,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: HygTypography.bodyFontFamily,
          fontSize: 14,
          color: Color(0xFF1E293B),
        ),
        decoration: const InputDecoration(
          hintText: 'Search employee name, department, or transaction...',
          hintStyle: TextStyle(
            fontFamily: HygTypography.bodyFontFamily,
            fontSize: 14,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class PointsMemberRecord {
  PointsMemberRecord({
    required this.id,
    this.userProfileId = '',
    this.authUserId = '',
    this.employeeId = '',
    required this.employeeName,
    this.email = '',
    required this.department,
    this.role = '',
    this.company = 'HYG Corporate',
    required this.pointsBalance,
    required this.lastActivity,
    required this.lastActivityDate,
    this.status = 'Active',
  });

  String id;
  final String userProfileId;
  final String authUserId;
  final String employeeId;
  final String employeeName;
  final String email;
  final String department;
  final String role;
  final String company;
  int pointsBalance;
  String lastActivity;
  DateTime lastActivityDate;
  String status;
}

class PointsManagementPanel extends StatefulWidget {
  const PointsManagementPanel({
    required this.onAdjustPoints,
    this.employees,
    super.key,
  });

  final ValueChanged<PointsMemberRecord>? onAdjustPoints;
  final List<EmployeePreview>? employees;

  @override
  State<PointsManagementPanel> createState() => _PointsManagementPanelState();
}

class _PointsManagementPanelState extends State<PointsManagementPanel> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDepartment = 'All Departments';
  String _selectedCompany = 'All Companies';
  int _activeTab = 0; // 0: EMPLOYEE POINTS BALANCES, 1: TRANSACTIONS LOG
  bool _isLoading = false;

  int _employeeCurrentPage = 0;
  int _transactionCurrentPage = 0;
  static const int _itemsPerPage = 15;

  List<PointsMemberRecord> _records = [];
  List<Map<String, dynamic>> _transactionsLog = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadPointsDataFromDb();
  }

  Future<void> refresh() async {
    await _loadPointsDataFromDb();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _employeeCurrentPage = 0;
        _transactionCurrentPage = 0;
      });
    }
  }

  Future<void> _loadPointsDataFromDb() async {
    setState(() {
      _isLoading = true;
    });

    final client = Supabase.instance.client;
    final loadedRecords = <PointsMemberRecord>[];

    // 1. Ensure real employees directory list is loaded
    List<EmployeePreview> emps = widget.employees ?? [];
    if (emps.isEmpty) {
      try {
        emps = await EmployeeDirectoryService.loadEmployees();
      } catch (_) {}
    }

    // 2. Fetch point account database rows
    final dbPointAccountRows = <Map<String, dynamic>>[];

    // Layer 1: Try RPC Function admin_get_point_accounts (Security Definer)
    try {
      final rpcRes = await client.rpc('admin_get_point_accounts');
      if (rpcRes is List) {
        for (final r in rpcRes) {
          if (r is Map) dbPointAccountRows.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (_) {}

    // Layer 2: Direct Table Query user_hyg_point_accounts
    if (dbPointAccountRows.isEmpty) {
      try {
        final response = await client
            .from('user_hyg_point_accounts')
            .select('id, user_profile_id, auth_user_id, employee_id, balance, created_at, updated_at');
        if (response is List) {
          for (final r in response) {
            if (r is Map) dbPointAccountRows.add(Map<String, dynamic>.from(r));
          }
        }
      } catch (_) {}
    }

    // Index DB point account rows by employee_id, user_profile_id, and auth_user_id
    final accountByEmpId = <String, Map<String, dynamic>>{};
    final accountByUserProfId = <String, Map<String, dynamic>>{};
    final accountByAuthUserId = <String, Map<String, dynamic>>{};
    final matchedAccountIds = <String>{};

    for (final row in dbPointAccountRows) {
      final empId = (row['employee_id']?.toString() ?? '').trim().toLowerCase();
      final userProfId = (row['user_profile_id']?.toString() ?? '').trim().toLowerCase();
      final authUserId = (row['auth_user_id']?.toString() ?? '').trim().toLowerCase();

      if (empId.isNotEmpty) accountByEmpId[empId] = row;
      if (userProfId.isNotEmpty) accountByUserProfId[userProfId] = row;
      if (authUserId.isNotEmpty) accountByAuthUserId[authUserId] = row;
    }

    // 3. Match Employee Directory list with DB point accounts
    if (emps.isNotEmpty) {
      for (final emp in emps) {
        final empKey = emp.id.trim().toLowerCase();
        final accRow = accountByEmpId[empKey] ??
            accountByUserProfId[empKey] ??
            accountByAuthUserId[empKey];

        final id = accRow != null ? (accRow['id']?.toString() ?? emp.id) : emp.id;
        final userProfId = accRow?['user_profile_id']?.toString() ?? '';
        final authUserId = accRow?['auth_user_id']?.toString() ?? '';

        if (accRow != null && accRow['id'] != null) {
          matchedAccountIds.add(accRow['id'].toString());
        }

        // EXACT balance column value from user_hyg_point_accounts database table
        final balanceNum = accRow != null && accRow['balance'] != null
            ? (num.tryParse(accRow['balance'].toString()) ?? 0).toInt()
            : 0;

        final updatedAtStr = accRow?['updated_at']?.toString();
        final updatedAt = updatedAtStr != null
            ? (DateTime.tryParse(updatedAtStr) ?? DateTime.now())
            : DateTime.now();

        loadedRecords.add(
          PointsMemberRecord(
            id: id,
            userProfileId: userProfId,
            authUserId: authUserId,
            employeeId: emp.id,
            employeeName: emp.name,
            email: emp.email ?? '',
            department: emp.departmentName.isNotEmpty ? emp.departmentName : 'General',
            role: emp.positionName.isNotEmpty ? emp.positionName : 'STAFF',
            company: emp.companyName.isNotEmpty ? emp.companyName : 'HYG Corporate',
            pointsBalance: balanceNum,
            lastActivity: 'Points Balance: $balanceNum PTS',
            lastActivityDate: updatedAt,
          ),
        );
      }
    }

    // Fallback: If no assigned employee directory was found, add DB point account rows
    if (loadedRecords.isEmpty) {
      for (final row in dbPointAccountRows) {
        final accId = row['id']?.toString() ?? '';
        final userProfId = row['user_profile_id']?.toString() ?? '';
        final authUserId = row['auth_user_id']?.toString() ?? '';
        final empId = row['employee_id']?.toString() ?? '';

        final balanceNum = row['balance'] != null
            ? (num.tryParse(row['balance'].toString()) ?? 0).toInt()
            : 0;

        final updatedAtStr = row['updated_at']?.toString();
        final updatedAt = updatedAtStr != null
            ? (DateTime.tryParse(updatedAtStr) ?? DateTime.now())
            : DateTime.now();

        loadedRecords.add(
          PointsMemberRecord(
            id: accId.isNotEmpty ? accId : 'acc-${loadedRecords.length + 1}',
            userProfileId: userProfId,
            authUserId: authUserId,
            employeeId: empId,
            employeeName: row['employee_name']?.toString() ??
                (empId.isNotEmpty
                    ? 'Employee #$empId'
                    : 'Account #${accId.substring(0, math.min(8, accId.length))}'),
            email: row['employee_email']?.toString() ?? '',
            department: row['department_name']?.toString() ?? 'General',
            role: row['position_name']?.toString() ?? 'STAFF',
            company: row['company_name']?.toString() ?? 'HYG Corporate',
            pointsBalance: balanceNum,
            lastActivity: 'Points Balance: $balanceNum PTS',
            lastActivityDate: updatedAt,
          ),
        );
      }
    }

    // 4. Fetch Transactions Log directly from user_hyg_point_transactions
    final fetchedTx = <Map<String, dynamic>>[];

    // Layer 1: RPC Function admin_get_point_transactions (Security Definer)
    try {
      final txRpcRes = await client.rpc('admin_get_point_transactions');
      if (txRpcRes is List) {
        for (final r in txRpcRes) {
          if (r is Map) fetchedTx.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (_) {}

    // Layer 2: Direct Table Query user_hyg_point_transactions
    if (fetchedTx.isEmpty) {
      try {
        final txResponse = await client
            .from('user_hyg_point_transactions')
            .select('id, account_id, user_profile_id, auth_user_id, employee_id, source, points, status, release_at, note, created_at')
            .order('created_at', ascending: false)
            .limit(100);

        for (final r in txResponse) {
          fetchedTx.add(Map<String, dynamic>.from(r as Map));
        }
      } catch (_) {}
    }

    // Map employee names and build assigned employee sets for scoping
    final empNameMap = <String, String>{};
    final assignedEmpIds = <String>{};
    final assignedEmpNames = <String>{};

    for (final r in loadedRecords) {
      if (r.employeeId.isNotEmpty) {
        empNameMap[r.employeeId.toLowerCase()] = r.employeeName;
        assignedEmpIds.add(r.employeeId.toLowerCase());
      }
      if (r.userProfileId.isNotEmpty) {
        empNameMap[r.userProfileId.toLowerCase()] = r.employeeName;
        assignedEmpIds.add(r.userProfileId.toLowerCase());
      }
      if (r.authUserId.isNotEmpty) {
        empNameMap[r.authUserId.toLowerCase()] = r.employeeName;
        assignedEmpIds.add(r.authUserId.toLowerCase());
      }
      if (r.id.isNotEmpty) {
        empNameMap[r.id.toLowerCase()] = r.employeeName;
        assignedEmpIds.add(r.id.toLowerCase());
      }
      if (r.employeeName.isNotEmpty) {
        assignedEmpNames.add(r.employeeName.trim().toLowerCase());
      }
    }

    if (widget.employees != null) {
      for (final emp in widget.employees!) {
        if (emp.id.isNotEmpty) assignedEmpIds.add(emp.id.toLowerCase());
        if (emp.name.isNotEmpty) assignedEmpNames.add(emp.name.trim().toLowerCase());
      }
    }

    final formattedTxLog = <Map<String, dynamic>>[];
    for (final tx in fetchedTx) {
      final rawId = tx['id']?.toString() ?? '';
      final displayTxId = tx['tx_id']?.toString() ??
          (rawId.length > 8
              ? 'TX-${rawId.substring(0, 8).toUpperCase()}'
              : (rawId.isNotEmpty ? rawId : 'TX-${formattedTxLog.length + 1}'));

      final empId = (tx['employee_id']?.toString() ?? '').toLowerCase();
      final userProfId = (tx['user_profile_id']?.toString() ?? '').toLowerCase();
      final authUserId = (tx['auth_user_id']?.toString() ?? '').toLowerCase();
      final accountId = (tx['account_id']?.toString() ?? '').toLowerCase();

      final empName = tx['employee']?.toString() ??
          tx['employee_name']?.toString() ??
          empNameMap[empId] ??
          empNameMap[userProfId] ??
          empNameMap[authUserId] ??
          '';

      final empNameLower = empName.trim().toLowerCase();

      final sourceStr = (tx['source']?.toString() ?? '').toLowerCase();
      final isBulk = sourceStr.contains('bulk');

      // Scoping Check: For HR accounts, show assigned employees OR bulk HR award summary logs
      final isAssigned = isBulk ||
          (empId.isNotEmpty && assignedEmpIds.contains(empId)) ||
          (userProfId.isNotEmpty && assignedEmpIds.contains(userProfId)) ||
          (authUserId.isNotEmpty && assignedEmpIds.contains(authUserId)) ||
          (accountId.isNotEmpty && assignedEmpIds.contains(accountId)) ||
          (empNameLower.isNotEmpty && assignedEmpNames.contains(empNameLower));

      if (!isAssigned && (assignedEmpIds.isNotEmpty || assignedEmpNames.isNotEmpty)) {
        continue; // Skip transactions for employees outside HR assignment scope
      }

      final displayEmpName = isBulk
          ? 'All Active Employees'
          : (empName.isNotEmpty ? empName : 'Employee');

      final typeStr = tx['type']?.toString() ??
          (sourceStr.contains('deduct') || sourceStr.contains('deduction')
              ? 'Deducted'
              : 'Awarded');

      final rawPts = tx['points'];
      final ptsNum = rawPts != null ? (num.tryParse(rawPts.toString()) ?? 0).abs().toInt() : 0;
      final isDeduct = typeStr.toLowerCase().contains('deduct') || sourceStr.contains('deduct');
      final formattedPts = tx['points_str']?.toString() ??
          '${isDeduct ? '-' : '+'}$ptsNum Pts';

      final reasonStr = tx['reason']?.toString() ??
          tx['note']?.toString() ??
          tx['source']?.toString() ??
          '-';

      final createdAtStr = tx['created_at']?.toString() ?? tx['date']?.toString();
      String formattedDate = '-';
      if (createdAtStr != null && createdAtStr.isNotEmpty) {
        final dt = DateTime.tryParse(createdAtStr);
        if (dt != null) {
          final year = dt.year;
          final month = dt.month.toString().padLeft(2, '0');
          final day = dt.day.toString().padLeft(2, '0');
          final hour = dt.hour.toString().padLeft(2, '0');
          final minute = dt.minute.toString().padLeft(2, '0');
          formattedDate = '$year-$month-$day $hour:$minute';
        } else {
          formattedDate = createdAtStr.length >= 16 ? createdAtStr.substring(0, 16) : createdAtStr;
        }
      }

      final rawStatus = tx['status']?.toString() ?? 'released';
      final statusStr = rawStatus.isEmpty
          ? 'Released'
          : '${rawStatus[0].toUpperCase()}${rawStatus.substring(1).toLowerCase()}';

      formattedTxLog.add({
        'id': displayTxId,
        'raw_id': rawId,
        'employee': displayEmpName,
        'type': typeStr,
        'points': formattedPts,
        'status': statusStr,
        'reason': reasonStr,
        'date': formattedDate,
        'raw_created_at': createdAtStr,
      });
    }

    if (mounted) {
      setState(() {
        _records = loadedRecords;
        _transactionsLog = formattedTxLog;
        _isLoading = false;
      });
    }
  }

  Future<void> _adjustPoints(PointsMemberRecord rec, int addedPoints, String reason) async {
    final newBalance = (rec.pointsBalance + addedPoints).clamp(0, 9999999);
    final client = Supabase.instance.client;
    String insertedTxDbId = '';

    try {
      // 1. Try RPC function admin_adjust_points
      final rpcRes = await client.rpc(
        'admin_adjust_points',
        params: {
          'p_account_id': rec.id,
          'p_points_delta': addedPoints,
          'p_reason': reason,
        },
      );
      if (rpcRes != null) {
        debugPrint('RPC admin_adjust_points result: $rpcRes');
      }
    } catch (_) {
      // 2. Fallback to direct update or insert into user_hyg_point_accounts
      try {
        if (rec.id.length > 10 && rec.id.contains('-')) {
          await client
              .from('user_hyg_point_accounts')
              .update({
                'balance': newBalance,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', rec.id);
        } else {
          final insertData = <String, dynamic>{
            'balance': newBalance,
          };
          if (rec.employeeId.isNotEmpty) insertData['employee_id'] = rec.employeeId;
          if (rec.userProfileId.isNotEmpty) insertData['user_profile_id'] = rec.userProfileId;
          if (rec.authUserId.isNotEmpty) insertData['auth_user_id'] = rec.authUserId;

          final newAcc = await client
              .from('user_hyg_point_accounts')
              .insert(insertData)
              .select('id')
              .maybeSingle();

          if (newAcc != null && newAcc['id'] != null) {
            rec.id = newAcc['id'].toString();
          }
        }

        try {
          final txInsert = <String, dynamic>{
            'account_id': rec.id,
            'source': addedPoints >= 0 ? 'Admin Award' : 'Admin Deduction',
            'points': addedPoints.abs(),
            'status': 'released',
            'note': reason,
          };
          if (rec.userProfileId.isNotEmpty) txInsert['user_profile_id'] = rec.userProfileId;
          if (rec.authUserId.isNotEmpty) txInsert['auth_user_id'] = rec.authUserId;
          if (rec.employeeId.isNotEmpty) txInsert['employee_id'] = rec.employeeId;

          final inserted = await client
              .from('user_hyg_point_transactions')
              .insert(txInsert)
              .select('id')
              .maybeSingle();

          if (inserted != null && inserted['id'] != null) {
            insertedTxDbId = inserted['id'].toString();
          }
        } catch (txErr) {
          debugPrint('Error inserting user_hyg_point_transactions: $txErr');
        }
      } catch (e) {
        debugPrint('Points account update error: $e');
      }
    }

    if (mounted) {
      setState(() {
        rec.pointsBalance = newBalance;
        rec.lastActivity = '${addedPoints >= 0 ? "Adjusted +" : "Deducted "}$addedPoints PTS ($reason)';
        rec.lastActivityDate = DateTime.now();
        _transactionsLog.insert(0, {
          'id': 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          'raw_id': insertedTxDbId,
          'employee': rec.employeeName,
          'type': addedPoints >= 0 ? 'Awarded' : 'Deducted',
          'points': '${addedPoints >= 0 ? "+" : ""}$addedPoints Pts',
          'reason': reason,
          'date': DateTime.now().toString().substring(0, 16),
          'performedBy': 'HR Admin',
        });
      });

      final msg = addedPoints >= 0 ? 'Points Awarded Successfully' : 'Points Deduct Successfully';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 480,
          backgroundColor: addedPoints >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(
                addedPoints >= 0 ? Icons.check_circle_outline : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      // Refresh DB data to ensure state and raw IDs sync
      await _loadPointsDataFromDb();
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final displayId = tx['id']?.toString() ?? 'Transaction';
    final rawDbId = tx['raw_id']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 10),
            Text(
              'Delete Transaction Log',
              style: TextStyle(
                fontFamily: HygTypography.headingFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete transaction $displayId? This action will permanently remove the log entry.',
          style: const TextStyle(
            fontFamily: HygTypography.bodyFontFamily,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = Supabase.instance.client;
    final reasonNote = tx['reason']?.toString() ?? tx['note']?.toString() ?? '';
    bool deleteSuccess = false;

    // Identify target UUID
    final String targetUuid = (rawDbId.isNotEmpty && rawDbId.length > 20 && rawDbId.contains('-'))
        ? rawDbId
        : ((displayId.isNotEmpty && displayId.length > 20 && displayId.contains('-'))
            ? displayId
            : '');

    // Strategy 1: Delete via Security Definer RPC function admin_delete_point_transaction
    if (targetUuid.isNotEmpty) {
      try {
        final rpcRes = await client.rpc(
          'admin_delete_point_transaction',
          params: {'p_tx_id': targetUuid},
        );
        if (rpcRes == true || rpcRes == 'true' || rpcRes == 1) {
          deleteSuccess = true;
        }
      } catch (e) {
        debugPrint('RPC delete error: $e');
      }
    }

    // Strategy 2: Direct UUID delete with .select('id') verification if RPC wasn't used or returned false
    if (!deleteSuccess && targetUuid.isNotEmpty) {
      try {
        final res = await client
            .from('user_hyg_point_transactions')
            .delete()
            .eq('id', targetUuid)
            .select('id');
        if (res is List && res.isNotEmpty) {
          deleteSuccess = true;
        }
      } catch (e) {
        debugPrint('Direct UUID delete error: $e');
      }
    }

    // Strategy 3: Fallback delete by note/reason matching if UUID wasn't found or display ID was passed
    if (!deleteSuccess && reasonNote.isNotEmpty && reasonNote != '-') {
      try {
        final res = await client
            .from('user_hyg_point_transactions')
            .delete()
            .eq('note', reasonNote)
            .select('id');
        if (res is List && res.isNotEmpty) {
          deleteSuccess = true;
        }
      } catch (e) {
        debugPrint('Note fallback delete error: $e');
      }
    }

    if (mounted) {
      if (deleteSuccess) {
        setState(() {
          _transactionsLog.removeWhere((item) =>
              item['id'] == displayId ||
              (rawDbId.isNotEmpty && item['raw_id'] == rawDbId) ||
              (targetUuid.isNotEmpty && (item['raw_id'] == targetUuid || item['id'] == targetUuid)));
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            width: 480,
            backgroundColor: const Color(0xFFDC2626),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Transaction Deleted Successfully',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // Refresh DB data to ensure full state sync
        await _loadPointsDataFromDb();
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            width: 480,
            backgroundColor: const Color(0xFFB91C1C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Failed to delete transaction log from database. Please check permissions.',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  int get _totalDistributedPoints =>
      _records.fold(0, (sum, item) => sum + item.pointsBalance);

  int get _activeAccountsWithBalanceCount =>
      _records.where((item) => item.pointsBalance > 0).length;

  @override
  Widget build(BuildContext context) {
    final departments = [
      'All Departments',
      ...{for (final r in _records) r.department}.toList()..sort(),
    ];
    final companies = [
      'All Companies',
      ...{for (final r in _records) r.company}.toList()..sort(),
    ];

    final filteredRecords = _records.where((r) {
      if (_selectedDepartment != 'All Departments' &&
          r.department != _selectedDepartment) {
        return false;
      }
      if (_selectedCompany != 'All Companies' &&
          r.company != _selectedCompany) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return r.employeeName.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q) ||
          r.company.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q);
    }).toList();

    final empTotal = filteredRecords.length;
    final empPageCount = math.max(1, (empTotal / _itemsPerPage).ceil()).toInt();
    final safeEmpPage = _employeeCurrentPage.clamp(0, math.max(0, empPageCount - 1)).toInt();
    final empStart = safeEmpPage * _itemsPerPage;
    final empEnd = math.min(empStart + _itemsPerPage, empTotal).toInt();
    final pageRecords = (empStart < empTotal)
        ? filteredRecords.sublist(empStart, empEnd)
        : <PointsMemberRecord>[];

    final search = _searchQuery.trim().toLowerCase();
    final filteredTransactions = _transactionsLog.where((tx) {
      if (search.isEmpty) return true;
      final emp = (tx['employee']?.toString() ?? '').toLowerCase();
      final txId = (tx['id']?.toString() ?? '').toLowerCase();
      final reason = (tx['reason']?.toString() ?? '').toLowerCase();
      final type = (tx['type']?.toString() ?? '').toLowerCase();
      final status = (tx['status']?.toString() ?? '').toLowerCase();
      return emp.contains(search) ||
          txId.contains(search) ||
          reason.contains(search) ||
          type.contains(search) ||
          status.contains(search);
    }).toList();

    final txTotal = filteredTransactions.length;
    final txPageCount = math.max(1, (txTotal / _itemsPerPage).ceil()).toInt();
    final safeTxPage = _transactionCurrentPage.clamp(0, math.max(0, txPageCount - 1)).toInt();
    final txStart = safeTxPage * _itemsPerPage;
    final txEnd = math.min(txStart + _itemsPerPage, txTotal).toInt();
    final pageTransactions = (txStart < txTotal)
        ? filteredTransactions.sublist(txStart, txEnd)
        : <Map<String, dynamic>>[];

    final activeCount = _activeAccountsWithBalanceCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // STAT CARDS ROW
        Row(
          children: [
            Expanded(
              child: _PointsStatCard(
                title: 'TOTAL POINTS DISTRIBUTED',
                value: '$_totalDistributedPoints PTS',
                subtitle: 'Across all active accounts',
                assetPath: 'assets/hygcoins.png',
                iconBgColor: const Color(0xFFFEF3C7),
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _PointsStatCard(
                title: 'ACTIVE POINT ACCOUNTS',
                value: '$activeCount ${activeCount == 1 ? 'Employee' : 'Employees'}',
                subtitle: 'Accounts with points balance',
                icon: Icons.people_outline,
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _PointsStatCard(
                title: 'AVG BALANCE PER EMP',
                value: activeCount == 0
                    ? '0 PTS'
                    : '${(_totalDistributedPoints / activeCount).round()} PTS',
                subtitle: 'Average points holding',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFD97706),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // SEARCH & FILTER BAR
        Row(
          children: [
            Expanded(
              child: PointsManagementSearchBar(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _employeeCurrentPage = 0;
                    _transactionCurrentPage = 0;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            _PointsFilterDropdown(
              value: _selectedDepartment,
              items: departments,
              enabled: _activeTab == 0,
              onChanged: _activeTab == 0
                  ? (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDepartment = val;
                          _employeeCurrentPage = 0;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(width: 12),
            _PointsFilterDropdown(
              value: _selectedCompany,
              items: companies,
              enabled: _activeTab == 0,
              onChanged: _activeTab == 0
                  ? (val) {
                      if (val != null) {
                        setState(() {
                          _selectedCompany = val;
                          _employeeCurrentPage = 0;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
              tooltip: 'Refresh DB Data',
              onPressed: _loadPointsDataFromDb,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // TABS & TABLE CONTAINER
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // TAB HEADER BAR
              Container(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 4),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    _PointsTabButton(
                      label: 'EMPLOYEE POINTS BALANCES',
                      count: empTotal,
                      isActive: _activeTab == 0,
                      onTap: () => setState(() => _activeTab = 0),
                    ),
                    const SizedBox(width: 24),
                    _PointsTabButton(
                      label: 'RECENT TRANSACTIONS LOG',
                      count: txTotal,
                      showPlus: true,
                      isActive: _activeTab == 1,
                      onTap: () => setState(() => _activeTab = 1),
                    ),
                  ],
                ),
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_activeTab == 0) ...[
                const _PointsTableHeader(),
                if (filteredRecords.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'No employee points balance found.',
                        style: TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                else
                  ...pageRecords.map(
                    (rec) => _PointsRow(
                      record: rec,
                      onAward: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => GrantPointsDialog(
                            record: rec,
                            isDeduct: false,
                            onSaved: (addedPoints, reason) =>
                                _adjustPoints(rec, addedPoints, reason),
                          ),
                        );
                      },
                      onDeduct: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => GrantPointsDialog(
                            record: rec,
                            isDeduct: true,
                            onSaved: (addedPoints, reason) =>
                                _adjustPoints(rec, addedPoints, reason),
                          ),
                        );
                      },
                    ),
                  ),
                _PointsPaginationControl(
                  currentPage: safeEmpPage,
                  pageCount: empPageCount,
                  totalItems: empTotal,
                  itemsPerPage: _itemsPerPage,
                  itemLabel: 'employees',
                  onPageSelected: (page) =>
                      setState(() => _employeeCurrentPage = page),
                ),
              ] else ...[
                const _TransactionsTableHeader(),
                if (filteredTransactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'No points transactions logged yet.',
                        style: TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                else
                  ...pageTransactions.map(
                    (tx) => _TransactionRow(
                      tx: tx,
                    ),
                  ),
                _PointsPaginationControl(
                  currentPage: safeTxPage,
                  pageCount: txPageCount,
                  totalItems: txTotal,
                  itemsPerPage: _itemsPerPage,
                  itemLabel: 'transactions',
                  onPageSelected: (page) =>
                      setState(() => _transactionCurrentPage = page),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PointsTabButton extends StatelessWidget {
  const _PointsTabButton({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
    this.showPlus = false,
  });

  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    const activeGold = Color(0xFFEAB308); // Bright clean gold matching screenshot

    return InkWell(
      onTap: onTap,
      splashColor: activeGold.withValues(alpha: 0.1),
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeGold : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive ? activeGold : const Color(0xFF94A3B8),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFFEF08A) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                (showPlus && count >= 100) ? '$count+' : '$count',
                style: TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive ? const Color(0xFF854D0E) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsFilterDropdown extends StatelessWidget {
  const _PointsFilterDropdown({
    required this.value,
    required this.items,
    this.onChanged,
    this.enabled = true,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final validValue = items.contains(value) ? value : items.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? const Color(0xFFE2E8F0) : const Color(0xFFE2E8F0).withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validValue,
          style: TextStyle(
            fontFamily: HygTypography.bodyFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: enabled ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
          ),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: enabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
            size: 18,
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _PointsStatCard extends StatelessWidget {
  const _PointsStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.icon,
    this.assetPath,
    required this.color,
    this.iconBgColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData? icon;
  final String? assetPath;
  final Color color;
  final Color? iconBgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor ?? color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: assetPath != null
                ? Image.asset(
                    assetPath!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  )
                : Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
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

class _PointsTableHeader extends StatelessWidget {
  const _PointsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: HeaderLabel('EMPLOYEE NAME')),
          Expanded(flex: 3, child: HeaderLabel('COMPANY')),
          Expanded(flex: 3, child: HeaderLabel('ROLE & DEPARTMENT')),
          Expanded(flex: 2, child: HeaderLabel('POINTS BALANCE')),
          Expanded(flex: 2, child: HeaderLabel('ACTIONS')),
        ],
      ),
    );
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({
    required this.record,
    required this.onAward,
    required this.onDeduct,
  });

  final PointsMemberRecord record;
  final VoidCallback onAward;
  final VoidCallback onDeduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // 1. EMPLOYEE NAME
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.employeeName,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (record.email.isNotEmpty)
                  Text(
                    record.email,
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
              ],
            ),
          ),
          // 2. COMPANY
          Expanded(
            flex: 3,
            child: Text(
              record.company.isNotEmpty ? record.company : 'HYG Corporate',
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
          // 3. ROLE & DEPARTMENT
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.role.isNotEmpty ? record.role : 'STAFF',
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  record.department.isNotEmpty ? record.department : 'General',
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          // 4. POINTS BALANCE
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HygColors.goldStrong),
                  ),
                  child: Text(
                    '${record.pointsBalance} PTS',
                    style: const TextStyle(
                      fontFamily: HygTypography.headingFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: HygColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 5. ACTIONS (Icon Only: Green + and Red -)
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Tooltip(
                  message: 'Award Points',
                  child: InkWell(
                    onTap: onAward,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF16A34A), width: 1.8),
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Color(0xFF16A34A),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Deduct Points',
                  child: InkWell(
                    onTap: onDeduct,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDC2626), width: 1.8),
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.remove,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                    ),
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

class _TransactionsTableHeader extends StatelessWidget {
  const _TransactionsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: HeaderLabel('TX ID')),
          Expanded(flex: 4, child: HeaderLabel('EMPLOYEE')),
          Expanded(flex: 2, child: HeaderLabel('TYPE')),
          Expanded(flex: 2, child: HeaderLabel('POINTS')),
          Expanded(flex: 2, child: HeaderLabel('STATUS')),
          Expanded(flex: 4, child: HeaderLabel('REASON / NOTE')),
          Expanded(flex: 3, child: HeaderLabel('DATE')),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.tx,
  });

  final Map<String, dynamic> tx;

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'released':
        return const Color(0xFFE0F2FE); // Light Sky Blue
      case 'claimed':
        return const Color(0xFFDCFCE7); // Light Emerald Green
      case 'cancelled':
        return const Color(0xFFFEE2E2); // Light Red
      default:
        return const Color(0xFFF1F5F9); // Slate Gray
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'released':
        return const Color(0xFF0369A1); // Deep Blue
      case 'claimed':
        return const Color(0xFF15803D); // Deep Green
      case 'cancelled':
        return const Color(0xFFB91C1C); // Deep Red
      default:
        return const Color(0xFF475569); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    final txId = tx['id']?.toString() ?? '';
    final emp = tx['employee']?.toString() ?? tx['employee_id']?.toString() ?? 'Employee';
    final type = tx['type']?.toString() ?? (tx['source']?.toString() ?? 'Awarded');
    final points = tx['points']?.toString() ?? '${tx['points'] ?? ''} Pts';
    final status = tx['status']?.toString() ?? 'Released';
    final reason = tx['reason']?.toString() ?? tx['note']?.toString() ?? '-';
    final date = tx['date']?.toString() ?? tx['created_at']?.toString().substring(0, 16) ?? '-';

    final isAwarded = !points.startsWith('-');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              txId,
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              emp,
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              type,
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isAwarded ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              points,
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isAwarded ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getStatusBgColor(status),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _getStatusTextColor(status),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              reason,
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              date,
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GrantPointsDialog extends StatefulWidget {
  const GrantPointsDialog({
    this.record,
    this.onSaved,
    this.isDeduct = false,
    super.key,
  });

  final PointsMemberRecord? record;
  final void Function(int points, String reason)? onSaved;
  final bool isDeduct;

  @override
  State<GrantPointsDialog> createState() => _GrantPointsDialogState();
}

class _GrantPointsDialogState extends State<GrantPointsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pointsController = TextEditingController(text: '100');
  final _reasonController = TextEditingController();
  late bool _isDeduct;

  @override
  void initState() {
    super.initState();
    _isDeduct = widget.isDeduct;
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.toll_outlined, color: HygColors.goldStrong, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.record != null
                        ? 'Adjust Points: ${widget.record!.employeeName}'
                        : (_isDeduct ? 'Deduct Employee Points' : 'Award Employee Points'),
                    style: const TextStyle(
                      fontFamily: HygTypography.headingFontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: HygColors.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _isDeduct = false),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isDeduct ? const Color(0xFF16A34A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !_isDeduct ? const Color(0xFF15803D) : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: !_isDeduct
                          ? const [
                              BoxShadow(
                                color: Color(0x3316A34A),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_circle,
                          size: 18,
                          color: !_isDeduct ? Colors.white : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Grant / Award Points',
                          style: TextStyle(
                            fontFamily: HygTypography.bodyFontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: !_isDeduct ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => setState(() => _isDeduct = true),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isDeduct ? const Color(0xFFDC2626) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isDeduct ? const Color(0xFFB91C1C) : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: _isDeduct
                          ? const [
                              BoxShadow(
                                color: Color(0x33DC2626),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.remove_circle,
                          size: 18,
                          color: _isDeduct ? Colors.white : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deduct Points',
                          style: TextStyle(
                            fontFamily: HygTypography.bodyFontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _isDeduct ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Points Amount',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      final p = int.tryParse(val?.trim() ?? '');
                      if (p == null || p <= 0) {
                        return 'Please enter a valid positive points amount.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason / Note',
                      hintText: 'e.g. Monthly Award',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Reason / Note is required.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDeduct ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;

                    final pts = int.tryParse(_pointsController.text.trim()) ?? 0;
                    final reason = _reasonController.text.trim();
                    final finalPts = _isDeduct ? -pts : pts;
                    widget.onSaved?.call(finalPts, reason);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    _isDeduct ? 'Confirm Deduction' : 'Confirm Award Points',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AwardAllPointsDialog extends StatefulWidget {
  const AwardAllPointsDialog({
    required this.employeeCount,
    required this.onConfirmed,
    super.key,
  });

  final int employeeCount;
  final Future<void> Function(int points, String reason) onConfirmed;

  @override
  State<AwardAllPointsDialog> createState() => _AwardAllPointsDialogState();
}

class _AwardAllPointsDialogState extends State<AwardAllPointsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pointsController = TextEditingController(text: '100');
  final _reasonController = TextEditingController(text: 'Company Monthly Award');
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pointsController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pts = int.tryParse(_pointsController.text.trim()) ?? 0;
    final reason = _reasonController.text.trim();
    if (pts <= 0) return;

    setState(() {
      _isSubmitting = true;
    });

    await widget.onConfirmed(pts, reason);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.asset(
                      'assets/hygcoins.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Award Points to All Employees',
                          style: TextStyle(
                            fontFamily: HygTypography.headingFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Award bonus reward points to all active employee accounts at once.',
                          style: TextStyle(
                            fontFamily: HygTypography.bodyFontFamily,
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Summary Info Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Color(0xFF2563EB), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This action will award points to all ${widget.employeeCount} employee accounts.',
                        style: const TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Points Amount Input
              const Text(
                'Points Amount per Employee *',
                style: TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _pointsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 500',
                  suffixText: 'PTS',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) {
                  final numVal = int.tryParse(val ?? '');
                  if (numVal == null || numVal <= 0) {
                    return 'Please enter a valid points amount greater than 0.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Reason / Note Input
              const Text(
                'Award Reason / Note *',
                style: TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  hintText: 'e.g. Company Performance Bonus',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason or note for awarding points.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Actions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSubmitting
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: HygColors.ink),
                              ),
                              SizedBox(width: 8),
                              Text('Awarding Points...', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          )
                        : const Text(
                            'Confirm Award Points to All',
                            style: TextStyle(fontWeight: FontWeight.w700),
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

class _PointsPaginationControl extends StatelessWidget {
  const _PointsPaginationControl({
    required this.currentPage,
    required this.pageCount,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onPageSelected,
    this.itemLabel = 'records',
  });

  final int currentPage;
  final int pageCount;
  final int totalItems;
  final int itemsPerPage;
  final ValueChanged<int> onPageSelected;
  final String itemLabel;

  List<int> get _visiblePages {
    final firstPage = math.max(
      0,
      math.min(currentPage - 2, math.max(0, pageCount - 5)),
    ).toInt();
    return List.generate(math.min(5, pageCount).toInt(), (index) => firstPage + index);
  }

  @override
  Widget build(BuildContext context) {
    if (totalItems == 0) return const SizedBox.shrink();

    final firstItem = currentPage * itemsPerPage + 1;
    final lastItem = math.min(firstItem + itemsPerPage - 1, totalItems).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $firstItem-$lastItem of $totalItems $itemLabel',
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
          _PaginationButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed: currentPage == 0
                ? null
                : () => onPageSelected(currentPage - 1),
          ),
          const SizedBox(width: 6),
          ..._visiblePages.expand(
            (page) => [
              _PaginationButton(
                label: '${page + 1}',
                isSelected: page == currentPage,
                onPressed: () => onPageSelected(page),
              ),
              const SizedBox(width: 6),
            ],
          ),
          _PaginationButton(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed: currentPage == pageCount - 1
                ? null
                : () => onPageSelected(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PaginationButton extends StatelessWidget {
  const _PaginationButton({
    this.label,
    this.icon,
    this.isSelected = false,
    this.onPressed,
    this.tooltip,
  });

  final String? label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    Widget buttonChild;
    if (label != null) {
      buttonChild = Text(
        label!,
        style: TextStyle(
          fontFamily: HygTypography.bodyFontFamily,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected
              ? HygColors.ink
              : (enabled ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
        ),
      );
    } else {
      buttonChild = Icon(
        icon,
        size: 18,
        color: enabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
      );
    }

    final btn = Material(
      color: isSelected
          ? HygColors.gold
          : (enabled ? Colors.white : const Color(0xFFF1F5F9)),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 34),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? HygColors.gold
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: buttonChild,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

