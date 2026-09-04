part of '../main.dart';

// ==========================================
// REDEMPTION REQUESTS SCREEN
// ==========================================

class RedemptionRequestRecord {
  RedemptionRequestRecord({
    required this.id,
    required this.employeeName,
    required this.department,
    required this.itemName,
    required this.category,
    required this.pointsCost,
    required this.dateRequested,
    required this.status,
    this.notes = '',
    this.avatarInitials = 'EM',
    this.avatarBgColor = const Color(0xFFE0F2FE),
    this.avatarTextColor = const Color(0xFF0369A1),
  });

  final String id;
  final String employeeName;
  final String department;
  final String itemName;
  final String category;
  final int pointsCost;
  final String dateRequested;
  String status; // Pending, Approved, Rejected
  final String notes;
  final String avatarInitials;
  final Color avatarBgColor;
  final Color avatarTextColor;
}

class RedemptionRequestsScreen extends StatefulWidget {
  const RedemptionRequestsScreen({
    this.employees = const [],
    super.key,
  });

  final List<EmployeePreview> employees;

  @override
  State<RedemptionRequestsScreen> createState() => _RedemptionRequestsScreenState();
}

class _RedemptionRequestsScreenState extends State<RedemptionRequestsScreen> {
  String _selectedTab = 'All';
  String _searchQuery = '';
  String _selectedCategory = 'All Categories';
  final TextEditingController _searchController = TextEditingController();

  late List<RedemptionRequestRecord> _requests;

  @override
  void initState() {
    super.initState();
    _requests = [
      RedemptionRequestRecord(
        id: 'RED-2026-089',
        employeeName: 'Luigi Andrey',
        department: 'Store Ops - Branch 04',
        itemName: 'SM Gift Pass ₱1,000',
        category: 'Gift Certificates',
        pointsCost: 5000,
        dateRequested: 'Aug 26, 2026 • 2:45 PM',
        status: 'Pending',
        notes: 'Delivery requested at Branch 04 Admin Office.',
        avatarInitials: 'LA',
        avatarBgColor: const Color(0xFFFEF3C7),
        avatarTextColor: const Color(0xFFD97706),
      ),
      RedemptionRequestRecord(
        id: 'RED-2026-088',
        employeeName: 'Ana Reyes',
        department: 'HR & Finance',
        itemName: 'Wireless Noise-Canceling Earbuds',
        category: 'Electronics',
        pointsCost: 8500,
        dateRequested: 'Aug 25, 2026 • 11:10 AM',
        status: 'Approved',
        notes: 'Approved by HR Director. Item ordered via vendor.',
        avatarInitials: 'AR',
        avatarBgColor: const Color(0xFFFEE2E2),
        avatarTextColor: const Color(0xFFDC2626),
      ),
      RedemptionRequestRecord(
        id: 'RED-2026-085',
        employeeName: 'Juan Dela Cruz',
        department: 'Sales Department',
        itemName: 'Starbucks Tumbler & ₱500 Voucher',
        category: 'Vouchers',
        pointsCost: 3200,
        dateRequested: 'Aug 24, 2026 • 4:20 PM',
        status: 'Approved',
        notes: 'Claimed in person by employee at HQ.',
        avatarInitials: 'JD',
        avatarBgColor: const Color(0xFFE0E7FF),
        avatarTextColor: const Color(0xFF4338CA),
      ),
      RedemptionRequestRecord(
        id: 'RED-2026-081',
        employeeName: 'Maria Santos',
        department: 'Logistics & Warehouse',
        itemName: 'Extra Paid Day Off Voucher',
        category: 'Perks & Leaves',
        pointsCost: 10000,
        dateRequested: 'Aug 22, 2026 • 9:15 AM',
        status: 'Pending',
        notes: 'Subject to department head schedule clearance.',
        avatarInitials: 'MS',
        avatarBgColor: const Color(0xFFDCFCE7),
        avatarTextColor: const Color(0xFF15803D),
      ),
      RedemptionRequestRecord(
        id: 'RED-2026-079',
        employeeName: 'Mark Tan',
        department: 'IT Support',
        itemName: 'GrabFood ₱500 E-Voucher',
        category: 'Vouchers',
        pointsCost: 2500,
        dateRequested: 'Aug 20, 2026 • 1:30 PM',
        status: 'Rejected',
        notes: 'Insufficient active point balance at time of review.',
        avatarInitials: 'MT',
        avatarBgColor: const Color(0xFFF3E8FF),
        avatarTextColor: const Color(0xFF7E22CE),
      ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RedemptionRequestRecord> get _filteredRequests {
    return _requests.where((r) {
      if (_selectedTab != 'All' && r.status != _selectedTab) return false;
      if (_selectedCategory != 'All Categories' && r.category != _selectedCategory) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = r.employeeName.toLowerCase().contains(query);
        final matchItem = r.itemName.toLowerCase().contains(query);
        final matchId = r.id.toLowerCase().contains(query);
        final matchDept = r.department.toLowerCase().contains(query);
        return matchName || matchItem || matchId || matchDept;
      }
      return true;
    }).toList();
  }

  void _updateStatus(RedemptionRequestRecord request, String newStatus) {
    setState(() {
      request.status = newStatus;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Request ${request.id} status updated to "$newStatus"'),
        backgroundColor: newStatus == 'Approved'
            ? const Color(0xFF15803D)
            : newStatus == 'Rejected'
                ? const Color(0xFFB91C1C)
                : const Color(0xFF1D4ED8),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmUpdateStatus(RedemptionRequestRecord req, String newStatus) {
    final isApprove = newStatus == 'Approved';
    final actionTitle = isApprove ? 'Approve Redemption Request?' : 'Reject Redemption Request?';
    final actionColor = isApprove ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
    final actionBg = isApprove ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final actionBorder = isApprove ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
    final actionIcon = isApprove ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded;
    final confirmButtonLabel = isApprove ? 'Approve Request' : 'Reject Request';
    final confirmButtonColor = isApprove ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: actionBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: actionBorder),
                ),
                child: Icon(actionIcon, color: actionColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  actionTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to ${isApprove ? 'approve' : 'reject'} this redemption request?',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: req.avatarBgColor,
                            child: Text(
                              req.avatarInitials,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: req.avatarTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req.employeeName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                Text(
                                  req.department,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Request ID:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text(req.id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HygColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Item Requested:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text(req.itemName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HygColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Points Value:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text('${req.pointsCost} Pts', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HygColors.goldStrong)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _updateStatus(req, newStatus);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmButtonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                confirmButtonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _requests.where((r) => r.status == 'Pending').length;
    final approvedCount = _requests.where((r) => r.status == 'Approved').length;
    final totalPointsRedeemed = _requests
        .where((r) => r.status == 'Approved')
        .fold<int>(0, (sum, r) => sum + r.pointsCost);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Screen Header
        RedemptionRequestsHeader(
          onRefresh: _handleRefresh,
        ),
        const SizedBox(height: 14),

        // Stat Cards Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Requests',
                value: '${_requests.length}',
                subtext: '4 new this week',
                icon: Icons.assignment_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Pending Review',
                value: '$pendingCount',
                subtext: 'Action required',
                icon: Icons.hourglass_top_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Approved Requests',
                value: '$approvedCount',
                subtext: 'Approved redemptions',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFF16A34A),
                iconBg: const Color(0xFFDCFCE7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Points Redeemed',
                value: '$totalPointsRedeemed Pts',
                subtext: '₱${(totalPointsRedeemed * 0.5).toStringAsFixed(0)} approx value',
                icon: Icons.monetization_on_outlined,
                iconColor: const Color(0xFF7C3AED),
                iconBg: const Color(0xFFF3E8FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Main Panel with Filters & Table
        Container(
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search & Category Bar
              Row(
                children: [
                  // Search Box
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search by employee, reward item, or request ID...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Category Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCategory,
                        items: [
                          'All Categories',
                          'Gift Certificates',
                          'Electronics',
                          'Vouchers',
                          'Perks & Leaves',
                        ].map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Pending', 'Approved', 'Rejected'].map((tab) {
                    final isSelected = _selectedTab == tab;
                    int count = 0;
                    if (tab == 'All') {
                      count = _requests.length;
                    } else {
                      count = _requests.where((r) => r.status == tab).length;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = tab),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? HygColors.ink : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Text(
                                tab,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? HygColors.gold : const Color(0xFFCBD5E1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? HygColors.ink : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Requests List Table
              if (_filteredRequests.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: Column(
                    children: const [
                      Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF94A3B8)),
                      SizedBox(height: 8),
                      Text(
                        'No redemption requests found matching your filter.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                      ),
                    ],
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          color: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: const [
                              Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: Text('Employee', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                              Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: Text('Redeemed Reward', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                              SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: Text('Points Value', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                              SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Text('Date Requested', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                              SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                              SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))))),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        // Table Rows
                        ..._filteredRequests.map((req) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                            ),
                            child: Row(
                              children: [
                                // Employee
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: req.avatarBgColor,
                                        child: Text(
                                          req.avatarInitials,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: req.avatarTextColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              req.employeeName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: HygColors.ink,
                                              ),
                                            ),
                                            Text(
                                              '${req.department} • ${req.id}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Redeemed Reward
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        req.itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          req.category,
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Points Value
                                SizedBox(
                                  width: 120,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.toll, size: 14, color: HygColors.goldStrong),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${req.pointsCost} Pts',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: HygColors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Date Requested
                                SizedBox(
                                  width: 150,
                                  child: Builder(
                                    builder: (context) {
                                      final parts = req.dateRequested.split(' • ');
                                      final dateStr = parts[0];
                                      final timeStr = parts.length > 1 ? parts[1] : '';
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                          if (timeStr.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                // Status
                                SizedBox(
                                  width: 120,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildStatusBadge(req.status),
                                  ),
                                ),
                                // Actions
                                SizedBox(
                                  width: 150,
                                  child: _buildActionsCell(req),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color border;
    Color fg;
    IconData icon;

    switch (status) {
      case 'Approved':
        bg = const Color(0xFFDCFCE7);
        border = const Color(0xFFBBF7D0);
        fg = const Color(0xFF15803D);
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'Rejected':
        bg = const Color(0xFFFEE2E2);
        border = const Color(0xFFFECACA);
        fg = const Color(0xFFB91C1C);
        icon = Icons.highlight_off_rounded;
        break;
      case 'Pending':
      default:
        bg = const Color(0xFFFEF3C7);
        border = const Color(0xFFFDE68A);
        fg = const Color(0xFFB45309);
        icon = Icons.access_time_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRequest(RedemptionRequestRecord req) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFB91C1C), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Redemption Request?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you sure you want to permanently delete this redemption request? This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: req.avatarBgColor,
                            child: Text(
                              req.avatarInitials,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: req.avatarTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req.employeeName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                Text(
                                  req.department,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Request ID:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text(req.id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HygColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Item Requested:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text(req.itemName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HygColors.ink)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _deleteRequest(req);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Delete Request',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  void _deleteRequest(RedemptionRequestRecord req) {
    setState(() {
      _requests.removeWhere((r) => r.id == req.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Request ${req.id} deleted successfully.'),
        backgroundColor: const Color(0xFFB91C1C),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildActionsCell(RedemptionRequestRecord req) {
    final deleteButton = Tooltip(
      message: 'Delete Request',
      child: InkWell(
        onTap: () => _confirmDeleteRequest(req),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFF64748B),
            size: 18,
          ),
        ),
      ),
    );

    if (req.status == 'Pending') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Green Check Square Button
            Tooltip(
              message: 'Approve Request',
              child: InkWell(
                onTap: () => _confirmUpdateStatus(req, 'Approved'),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF15803D),
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Red Cross Square Button
            Tooltip(
              message: 'Reject Request',
              child: InkWell(
                onTap: () => _confirmUpdateStatus(req, 'Rejected'),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFB91C1C),
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            deleteButton,
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: deleteButton,
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: HygColors.ink)),
                const SizedBox(height: 2),
                Text(subtext, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleRefresh() {
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Redemption requests refreshed.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ==========================================
// REDEMPTION REQUESTS HEADER
// ==========================================
class RedemptionRequestsHeader extends StatelessWidget {
  const RedemptionRequestsHeader({this.onRefresh, super.key});
  final VoidCallback? onRefresh;

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
            Icons.card_giftcard_outlined,
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
                  'Redemption Requests',
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
                  'Review, manage, and approve employee point redemption requests in real time.',
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 19, color: HygColors.ink),
            label: const Text('Refresh', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
