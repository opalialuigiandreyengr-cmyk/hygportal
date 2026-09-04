part of '../main.dart';

// ==========================================
// REWARDS & POINTS REPORTS SCREEN
// ==========================================

class ReportCategoryItem {
  const ReportCategoryItem({
    required this.title,
    required this.description,
    required this.fileFormat,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final String fileFormat;
  final IconData icon;
  final Color color;
}

class TransactionAuditRecord {
  const TransactionAuditRecord({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.employeeName,
    required this.department,
    required this.pointsDelta,
    required this.details,
  });

  final String id;
  final String timestamp;
  final String type; // Award, Redemption, Adjustment, Expiry
  final String employeeName;
  final String department;
  final int pointsDelta;
  final String details;
}

class RewardsReportsScreen extends StatefulWidget {
  const RewardsReportsScreen({super.key});

  @override
  State<RewardsReportsScreen> createState() => _RewardsReportsScreenState();
}

class _RewardsReportsScreenState extends State<RewardsReportsScreen> {
  String _selectedTimeframe = 'This Month';
  String _selectedDeptFilter = 'All Departments';

  final List<ReportCategoryItem> _reportCategories = const [
    ReportCategoryItem(
      title: 'Points Issuance & Distribution',
      description: 'Complete breakdown of points granted by managers, automatic rules, and kudos awards.',
      fileFormat: 'CSV / Excel',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFF2563EB),
    ),
    ReportCategoryItem(
      title: 'Redemption & Fulfillment Audit',
      description: 'Audit log of items redeemed, fulfillment status, points cost, and vendor costs.',
      fileFormat: 'CSV / PDF',
      icon: Icons.shopping_bag_outlined,
      color: Color(0xFFD97706),
    ),
    ReportCategoryItem(
      title: 'Recognition & Kudos Summary',
      description: 'Analytics on peer shoutouts, top recognized employees, and company core values.',
      fileFormat: 'CSV / PDF',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFF16A34A),
    ),
    ReportCategoryItem(
      title: 'Departmental Engagement Leaderboard',
      description: 'Engagement rates, active users count, and average points earned per department.',
      fileFormat: 'Excel / CSV',
      icon: Icons.bar_chart_rounded,
      color: Color(0xFF7C3AED),
    ),
  ];

  final List<TransactionAuditRecord> _auditLog = const [
    TransactionAuditRecord(
      id: 'TXN-9021',
      timestamp: 'Today, 2:45 PM',
      type: 'Redemption',
      employeeName: 'Luigi Andrey',
      department: 'Store Operations',
      pointsDelta: -5000,
      details: 'Redeemed SM Gift Pass ₱1,000 (#RED-2026-089)',
    ),
    TransactionAuditRecord(
      id: 'TXN-9020',
      timestamp: 'Today, 11:30 AM',
      type: 'Award',
      employeeName: 'Ana Reyes',
      department: 'HR & Finance',
      pointsDelta: 500,
      details: 'Manager Spot Award: Above & Beyond',
    ),
    TransactionAuditRecord(
      id: 'TXN-9019',
      timestamp: 'Yesterday, 4:15 PM',
      type: 'Adjustment',
      employeeName: 'Juan Dela Cruz',
      department: 'Sales Department',
      pointsDelta: 250,
      details: 'Manual Admin Adjustment: Q3 Milestone Bonus',
    ),
    TransactionAuditRecord(
      id: 'TXN-9018',
      timestamp: 'Aug 24, 2026',
      type: 'Redemption',
      employeeName: 'Maria Santos',
      department: 'Logistics',
      pointsDelta: -3200,
      details: 'Redeemed Starbucks Tumbler Voucher (#RED-2026-085)',
    ),
  ];

  void _triggerDownload(String reportName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting "$reportName" report as CSV... Download starting.'),
        backgroundColor: const Color(0xFF15803D),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        RewardsReportsHeader(
          onExport: () => _triggerDownload('Full Rewards Executive Summary'),
        ),
        const SizedBox(height: 14),

        // Stat Cards Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total System Liability',
                value: '450,000 Pts',
                subtext: 'Active in employee wallets',
                icon: Icons.account_balance_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Monthly Redemptions',
                value: '68,400 Pts',
                subtext: '+18.4% vs last month',
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFF16A34A),
                iconBg: const Color(0xFFDCFCE7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Employee Engagement',
                value: '92.4%',
                subtext: '186 / 201 employees active',
                icon: Icons.people_outline_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: 'Avg. Claim Resolution',
                value: '1.2 Days',
                subtext: 'Processing turnaround time',
                icon: Icons.timer_outlined,
                iconColor: const Color(0xFF7C3AED),
                iconBg: const Color(0xFFF3E8FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Downloadable Quick Reports Cards Section
        Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Exportable Report Modules',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HygColors.ink),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTimeframe,
                            items: ['This Month', 'Last Quarter', 'Year to Date'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedTimeframe = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Report Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.8,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: _reportCategories.length,
                itemBuilder: (ctx, index) {
                  final cat = _reportCategories[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cat.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(cat.icon, color: cat.color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cat.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: HygColors.ink),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                cat.description,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.2),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            side: BorderSide(color: cat.color),
                          ),
                          onPressed: () => _triggerDownload(cat.title),
                          icon: Icon(Icons.download, size: 14, color: cat.color),
                          label: Text(cat.fileFormat, style: TextStyle(fontSize: 11, color: cat.color, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Visual Analytics & Audit Log Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Departmental Points Bar Chart
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Department Points Distribution', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HygColors.ink)),
                    const SizedBox(height: 4),
                    const Text('Active points held by employees by department', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(height: 16),
                    _buildDeptBar('Store Operations', 42500, 0.38, const Color(0xFF2563EB)),
                    const SizedBox(height: 12),
                    _buildDeptBar('Sales & Distribution', 32000, 0.29, const Color(0xFF16A34A)),
                    const SizedBox(height: 12),
                    _buildDeptBar('Logistics & Warehouse', 22500, 0.20, const Color(0xFFD97706)),
                    const SizedBox(height: 12),
                    _buildDeptBar('HR, IT & Corporate Admin', 14500, 0.13, const Color(0xFF7C3AED)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Right: Recent Transaction Audit Log Table
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recent Points Audit Trail', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HygColors.ink)),
                    const SizedBox(height: 4),
                    const Text('Real-time transaction log of points earned and spent', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(height: 14),

                    // Audit Table
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              color: const Color(0xFFF8FAFC),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: const [
                                  SizedBox(width: 90, child: Text('TXN ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)))),
                                  Expanded(flex: 2, child: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)))),
                                  SizedBox(width: 90, child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)))),
                                  SizedBox(width: 80, child: Text('Delta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569)))),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            ..._auditLog.map((txn) {
                              final isNegative = txn.pointsDelta < 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      child: Text(txn.id, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(txn.employeeName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: HygColors.ink)),
                                          Text(txn.department, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: Text(txn.type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        '${isNegative ? "" : "+"}${txn.pointsDelta} Pts',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isNegative ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                        ),
                                      ),
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
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeptBar(String deptName, int points, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(deptName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HygColors.ink)),
            Text('$points Pts (${(pct * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
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
}

// ==========================================
// REWARDS REPORTS HEADER
// ==========================================
class RewardsReportsHeader extends StatelessWidget {
  const RewardsReportsHeader({this.onExport, super.key});
  final VoidCallback? onExport;

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
            Icons.bar_chart_outlined,
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
                  'Rewards & Points Reports',
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
                  'Analytics and exportable reports on points activity, redemptions, and engagement.',
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
            onPressed: onExport,
            icon: const Icon(Icons.download, size: 19, color: HygColors.ink),
            label: const Text('Export Report', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
