part of '../main.dart';

// ==========================================
// BADGES & ACHIEVEMENTS SCREEN
// ==========================================

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({
    this.employees = const [],
    super.key,
  });

  final List<EmployeePreview> employees;

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  int _activeTabIndex = 0; // 0: Catalog, 1: Employee Badges, 2: Awarded History, 3: Auto-Grant Rules
  String _searchQuery = '';
  String _selectedCategory = 'All Categories';
  String _selectedCompanyFilter = 'All Companies';
  String _selectedDepartmentFilter = 'All Departments';
  int _employeeBadgesCurrentPage = 0;
  static const int _employeeBadgesPerPage = 15;
  final TextEditingController _searchController = TextEditingController();
  String? _hoveredEmployeeRowId;

  // Badge list state
  List<BadgeItem> _badges = [];
  List<AwardedBadgeRecord> _awardedHistory = [];
  List<EmployeePreview> _allEmployees = [];
  bool _isLoadingDb = true;

  final List<String> _categories = [
    'All Categories',
    'Milestones',
    'Performance',
    'Learning & Skills',
    'Values & Culture',
    'Attendance',
  ];

  @override
  void initState() {
    super.initState();
    _loadDatabaseData();
  }

  Future<void> _loadDatabaseData() async {
    setState(() => _isLoadingDb = true);
    try {
      final badges = await BadgesDatabaseService.loadBadges();
      final history = await BadgesDatabaseService.loadAwardedHistory();
      List<EmployeePreview> emps = widget.employees;
      if (emps.isEmpty) {
        emps = await EmployeeDirectoryService.loadEmployees();
      }
      if (mounted) {
        setState(() {
          _badges = badges;
          _awardedHistory = history;
          _allEmployees = emps;
          _isLoadingDb = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _badges = [];
          _awardedHistory = [];
          _allEmployees = widget.employees;
          _isLoadingDb = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BadgeItem> get _filteredBadges {
    return _badges.where((b) {
      final matchesSearch = b.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          b.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          b.category.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = _selectedCategory == 'All Categories' || b.category == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();
  }

  List<AwardedBadgeRecord> get _filteredHistory {
    return _awardedHistory.where((h) {
      final matchesSearch = h.employeeName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          h.badgeTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          h.employeeDepartment.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();
  }

  List<_EmployeeBadgeGroup> get _employeeBadgeGroups {
    final Map<String, _EmployeeBadgeGroup> map = {};

    for (final record in _awardedHistory) {
      final key = record.employeeId.isNotEmpty ? record.employeeId : record.employeeName;
      final empMatch = _allEmployees.firstWhere(
        (e) => e.id == record.employeeId || e.name.toLowerCase() == record.employeeName.toLowerCase(),
        orElse: () => EmployeePreview(
          id: record.employeeId,
          name: record.employeeName,
          initial: record.employeeName.isNotEmpty ? record.employeeName[0] : 'E',
          email: '',
          phone: '',
          photoUrl: record.employeePhotoUrl,
          idNumber: '',
          company: '',
          companyName: 'HYG Group',
          departmentName: record.employeeDepartment,
          positionName: '',
          roleDepartment: '',
          hired: '',
          rawHiredDate: '',
          createdAt: DateTime.now(),
          status: 'Active',
          avatarColor: record.employeeAvatarColor,
        ),
      );

      if (map.containsKey(key)) {
        map[key]!.records.add(record);
      } else {
        map[key] = _EmployeeBadgeGroup(
          employeeId: record.employeeId,
          employeeName: record.employeeName,
          employeeDepartment: record.employeeDepartment,
          employeeCompany: empMatch.companyName.isNotEmpty ? empMatch.companyName : 'HYG Group',
          employeeAvatarColor: record.employeeAvatarColor,
          employeePhotoUrl: record.employeePhotoUrl,
          records: [record],
        );
      }
    }

    for (final emp in _allEmployees) {
      final key = emp.id;
      if (!map.containsKey(key) && !map.values.any((g) => g.employeeName.toLowerCase() == emp.name.toLowerCase())) {
        map[key] = _EmployeeBadgeGroup(
          employeeId: emp.id,
          employeeName: emp.name,
          employeeDepartment: emp.departmentName,
          employeeCompany: emp.companyName.isNotEmpty ? emp.companyName : 'HYG Group',
          employeeAvatarColor: emp.avatarColor,
          employeePhotoUrl: emp.photoUrl,
          records: [],
        );
      }
    }

    return map.values.toList();
  }

  List<String> get _availableCompanies {
    final set = <String>{'All Companies'};
    for (final g in _employeeBadgeGroups) {
      if (g.employeeCompany.isNotEmpty) set.add(g.employeeCompany);
    }
    return set.toList();
  }

  List<String> get _availableDepartments {
    final set = <String>{'All Departments'};
    for (final g in _employeeBadgeGroups) {
      if (g.employeeDepartment.isNotEmpty) set.add(g.employeeDepartment);
    }
    return set.toList();
  }

  List<_EmployeeBadgeGroup> get _filteredEmployeeBadgeGroups {
    final query = _searchQuery.trim().toLowerCase();

    return _employeeBadgeGroups.where((g) {
      final matchesSearch = query.isEmpty ||
          g.employeeName.toLowerCase().contains(query) ||
          g.employeeDepartment.toLowerCase().contains(query) ||
          g.employeeCompany.toLowerCase().contains(query) ||
          g.records.any((r) => r.badgeTitle.toLowerCase().contains(query));

      final matchesCompany = _selectedCompanyFilter == 'All Companies' ||
          g.employeeCompany.toLowerCase() == _selectedCompanyFilter.toLowerCase();

      final matchesDept = _selectedDepartmentFilter == 'All Departments' ||
          g.employeeDepartment.toLowerCase() == _selectedDepartmentFilter.toLowerCase();

      return matchesSearch && matchesCompany && matchesDept;
    }).toList();
  }

  List<_EmployeeBadgeGroup> get _paginatedEmployeeBadgeGroups {
    final allFiltered = _filteredEmployeeBadgeGroups;
    final start = _employeeBadgesCurrentPage * _employeeBadgesPerPage;
    if (start >= allFiltered.length) return [];
    final end = math.min(start + _employeeBadgesPerPage, allFiltered.length);
    return allFiltered.sublist(start, end);
  }

  int get _totalBadgesCount => _badges.length;

  int get _totalIssuedCount => _awardedHistory.length;

  int get _totalPointsDistributed =>
      _awardedHistory.fold(0, (sum, h) => sum + h.pointsAwarded);

  BadgeItem? get _topBadge {
    if (_awardedHistory.isEmpty) return null;
    final counts = <String, int>{};
    for (final h in _awardedHistory) {
      counts[h.badgeTitle] = (counts[h.badgeTitle] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final topEntry = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final topTitle = topEntry.key;
    final topCount = topEntry.value;

    try {
      final matching = _badges.firstWhere((b) => b.title == topTitle);
      return BadgeItem(
        id: matching.id,
        title: matching.title,
        description: matching.description,
        category: matching.category,
        iconData: matching.iconData,
        customImagePath: matching.customImagePath,
        iconBgColor: matching.iconBgColor,
        iconColor: matching.iconColor,
        points: matching.points,
        awardedCount: topCount,
        status: matching.status,
      );
    } catch (_) {
      return BadgeItem(
        id: '',
        title: topTitle,
        description: '',
        category: '',
        iconData: Icons.star,
        iconBgColor: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFD97706),
        points: 0,
        awardedCount: topCount,
      );
    }
  }

  String _getBadgeDescription(String badgeId, String badgeTitle, [String? recDesc]) {
    if (recDesc != null && recDesc.trim().isNotEmpty) return recDesc;
    try {
      final matching = _badges.firstWhere(
        (b) => b.id == badgeId || b.title.toLowerCase() == badgeTitle.toLowerCase(),
      );
      return matching.description;
    } catch (_) {
      return '';
    }
  }

  void _openCreateBadgeModal([BadgeItem? badgeToEdit]) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateEditBadgeModal(
        badge: badgeToEdit,
        categories: _categories.where((c) => c != 'All Categories').toList(),
        onSave: (newBadge) async {
          setState(() {
            if (badgeToEdit != null) {
              final idx = _badges.indexWhere((b) => b.id == badgeToEdit.id);
              if (idx != -1) {
                _badges[idx] = newBadge;
              }
            } else {
              _badges.insert(0, newBadge);
            }
          });
          await BadgesDatabaseService.saveBadge(newBadge);
        },
      ),
    );
  }

  void _openAwardBadgeModal({BadgeItem? preselectedBadge, EmployeePreview? preselectedEmployee}) {
    showDialog(
      context: context,
      builder: (ctx) => _AwardBadgeModal(
        badges: _badges,
        employees: _allEmployees.isNotEmpty ? _allEmployees : widget.employees,
        preselectedBadge: preselectedBadge,
        preselectedEmployee: preselectedEmployee,
        onAwardMultiple: (records, selectedBadges) async {
          setState(() {
            _awardedHistory.insertAll(0, records);

            final empIds = records.map((r) => r.employeeId).toSet();
            final empCount = empIds.length;
            for (final sb in selectedBadges) {
              final idx = _badges.indexWhere((b) => b.id == sb.id);
              if (idx != -1) {
                _badges[idx].awardedCount += empCount;
              }
            }
          });

          if (records.isNotEmpty) {
            for (final rec in records) {
              await BadgesDatabaseService.saveAwardedRecord(rec);
            }

            if (mounted) {
              final empNames = records.map((r) => r.employeeName).toSet();
              final empCount = empNames.length;
              final badgeCount = selectedBadges.length;
              final totalPts = selectedBadges.fold(0, (sum, b) => sum + b.points) * empCount;
              final recipientLabel = empCount == 1 ? records.first.employeeName : '$empCount Employees';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$badgeCount Badge${badgeCount > 1 ? "s" : ""} (+$totalPts pts) successfully awarded to $recipientLabel!',
                  ),
                  backgroundColor: const Color(0xFF059669),
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _deleteBadge(BadgeItem badge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Badge'),
        content: Text('Are you sure you want to delete "${badge.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () async {
              setState(() {
                _badges.removeWhere((b) => b.id == badge.id);
              });
              Navigator.pop(ctx);
              await BadgesDatabaseService.deleteBadge(badge.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDb) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: HygColors.gold),
            SizedBox(height: 12),
            Text(
              'Loading Badges Database...',
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HEADER
        BadgesHeader(
          onCreateBadge: () => _openCreateBadgeModal(),
          onAwardBadge: () => _openAwardBadgeModal(),
        ),
        const SizedBox(height: 14),

        // METRICS DASHBOARD ROW
        _buildMetricsRow(),
        const SizedBox(height: 16),

        // SEARCH & FILTER ROW (TOP)
        _buildSearchBarAndFilters(),
        const SizedBox(height: 12),

        // FOUR TABS BAR (BELOW SEARCH & FILTER)
        _buildTabBar(),
        const SizedBox(height: 16),

        // TAB CONTENT AREA
        if (_activeTabIndex == 0)
          _buildBadgeCatalogGrid()
        else if (_activeTabIndex == 1)
          _buildEmployeeBadgesTable()
        else if (_activeTabIndex == 2)
          _buildAwardedHistoryTable()
        else
          _buildAutoGrantRulesPanel(),
      ],
    );
  }

  Widget _buildMetricsRow() {
    final topBadge = _topBadge;
    final topTitle = topBadge?.title ?? 'None';
    final topCount = topBadge?.awardedCount ?? 0;

    return Row(
      children: [
        Expanded(
          child: _MetricStatCard(
            label: 'TOTAL BADGES',
            value: '$_totalBadgesCount',
            subtext: 'Active badges catalog ',
            icon: Icons.verified_outlined,
            iconBgColor: const Color(0xFFFEF3C7),
            iconColor: HygColors.goldStrong,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricStatCard(
            label: 'BADGES ISSUED',
            value: '$_totalIssuedCount',
            subtext: 'Granted across all employees',
            icon: Icons.military_tech_outlined,
            iconBgColor: const Color(0xFFEFF6FF),
            iconColor: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricStatCard(
            label: 'TOP AWARDED BADGE',
            value: topTitle,
            valueFontSize: topTitle.length > 12 ? 14.0 : 16.5,
            subtext: '$topCount awarded total',
            icon: Icons.star_outline,
            iconBgColor: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricStatCard(
            label: 'POINTS DISTRIBUTED',
            value: '+${_totalPointsDistributed.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} pts',
            subtext: 'Total points awarded',
            icon: Icons.monetization_on_outlined,
            iconBgColor: const Color(0xFFFAF5FF),
            iconColor: const Color(0xFF9333EA),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBarAndFilters() {
    return Row(
      children: [
        // SEARCH INPUT
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() {
                _searchQuery = val;
                _employeeBadgesCurrentPage = 0;
              }),
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13.5,
                color: Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: _activeTabIndex == 1
                    ? 'Search employee name, department, or earned badge...'
                    : (_activeTabIndex == 2 ? 'Search employee name or badge...' : 'Search badge title, description, or category...'),
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
        ),

        // COMPANY & DEPARTMENT FILTERS (Shown on Employee Badges tab)
        if (_activeTabIndex == 1) ...[
          const SizedBox(width: 12),
          // COMPANY FILTER
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business_outlined, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _availableCompanies.contains(_selectedCompanyFilter) ? _selectedCompanyFilter : 'All Companies',
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF64748B)),
                    items: _availableCompanies.map((comp) {
                      return DropdownMenuItem<String>(
                        value: comp,
                        child: Text(comp),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedCompanyFilter = val;
                          _employeeBadgesCurrentPage = 0;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // DEPARTMENT FILTER
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _availableDepartments.contains(_selectedDepartmentFilter) ? _selectedDepartmentFilter : 'All Departments',
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF64748B)),
                    items: _availableDepartments.map((dept) {
                      return DropdownMenuItem<String>(
                        value: dept,
                        child: Text(dept),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDepartmentFilter = val;
                          _employeeBadgesCurrentPage = 0;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],

        // CATEGORY FILTER DROPDOWN (Shown on Catalog tab)
        if (_activeTabIndex == 0) ...[
          const SizedBox(width: 12),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF64748B)),
                    items: _categories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat,
                        child: Text(cat),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCategory = val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          _buildTabButton(0, 'BADGE CATALOG', _badges.length),
          const SizedBox(width: 24),
          _buildTabButton(1, 'EMPLOYEE BADGES', _employeeBadgeGroups.length),
          const SizedBox(width: 24),
          _buildTabButton(2, 'AWARDED HISTORY', _awardedHistory.length),
          const SizedBox(width: 24),
          _buildTabButton(3, 'AUTO-GRANT RULES', 3),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isActive = _activeTabIndex == index;
    const activeGold = Color(0xFFEAB308); // Bright clean gold matching Points Management tab style

    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
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
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
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
                '$count',
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

  Widget _buildBadgeCatalogGrid() {
    final list = _filteredBadges;
    if (list.isEmpty) {
      return _buildEmptyState('No badges found matching your search or category filter.');
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 200,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final badge = list[index];
        final realAwardedCount = _awardedHistory.where((h) => h.badgeId == badge.id || h.badgeTitle.toLowerCase() == badge.title.toLowerCase()).length;
        return _BadgeCardWidget(
          badge: badge,
          awardedCount: realAwardedCount,
          onAward: () => _openAwardBadgeModal(preselectedBadge: badge),
          onEdit: () => _openCreateBadgeModal(badge),
          onDelete: () => _deleteBadge(badge),
        );
      },
    );
  }

  Widget _buildTableHeaderCell(String title, {Alignment align = Alignment.centerLeft}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Align(
          alignment: align,
          child: Text(
            title,
            style: HygTypography.tableHeader,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeBadgesTable() {
    final allFiltered = _filteredEmployeeBadgeGroups;
    final totalCount = allFiltered.length;
    final paginatedList = _paginatedEmployeeBadgeGroups;

    if (allFiltered.isEmpty) {
      return _buildEmptyState('No employee badge records match your search or selected filters.');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TABLE CONTENT AREA
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3.0), // Employee
              1: FlexColumnWidth(2.2), // Company
              2: FlexColumnWidth(2.2), // Department
              3: FlexColumnWidth(1.8), // Badges Earned
              4: FlexColumnWidth(1.8), // Total Points
            },
            children: [
                  // TABLE HEADER ROW
                  TableRow(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    children: [
                      _buildTableHeaderCell('EMPLOYEE'),
                      _buildTableHeaderCell('COMPANY'),
                      _buildTableHeaderCell('DEPARTMENT'),
                      _buildTableHeaderCell('BADGES EARNED'),
                      _buildTableHeaderCell('TOTAL POINTS'),
                    ],
                  ),

                  // TABLE DATA ROWS
                  ...paginatedList.map((group) {
                    void onViewDetails() {
                      if (group.records.isNotEmpty) {
                        _openEmployeeBadgesDetailModal(group);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${group.employeeName} has not been awarded any badges yet.'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }

                    final isRowHovered = _hoveredEmployeeRowId == group.employeeId;

                    return TableRow(
                      decoration: BoxDecoration(
                        color: isRowHovered ? const Color(0xFFF1F5F9) : Colors.white,
                        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      children: [
                        // 1. EMPLOYEE (Avatar + Name)
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredEmployeeRowId = group.employeeId),
                            onExit: (_) => setState(() => _hoveredEmployeeRowId = null),
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: onViewDetails,
                              hoverColor: Colors.transparent,
                              splashColor: const Color(0xFFE2E8F0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    _buildEmployeeAvatar(group.employeeName, group.employeeAvatarColor, radius: 16, photoUrl: group.employeePhotoUrl),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        group.employeeName,
                                        style: const TextStyle(
                                          fontFamily: HygTypography.bodyFontFamily,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 2. COMPANY
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredEmployeeRowId = group.employeeId),
                            onExit: (_) => setState(() => _hoveredEmployeeRowId = null),
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: onViewDetails,
                              hoverColor: Colors.transparent,
                              splashColor: const Color(0xFFE2E8F0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(
                                  group.employeeCompany,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF475569),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 3. DEPARTMENT
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredEmployeeRowId = group.employeeId),
                            onExit: (_) => setState(() => _hoveredEmployeeRowId = null),
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: onViewDetails,
                              hoverColor: Colors.transparent,
                              splashColor: const Color(0xFFE2E8F0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(
                                  group.employeeDepartment,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF475569),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 4. BADGES EARNED (Clean Badge Count Pill Only)
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredEmployeeRowId = group.employeeId),
                            onExit: (_) => setState(() => _hoveredEmployeeRowId = null),
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: onViewDetails,
                              hoverColor: Colors.transparent,
                              splashColor: const Color(0xFFE2E8F0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: group.badgeCount > 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${group.badgeCount} Badge${group.badgeCount == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: group.badgeCount > 0 ? const Color(0xFF1E40AF) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 5. TOTAL POINTS
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredEmployeeRowId = group.employeeId),
                            onExit: (_) => setState(() => _hoveredEmployeeRowId = null),
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: onViewDetails,
                              hoverColor: Colors.transparent,
                              splashColor: const Color(0xFFE2E8F0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(
                                  '+${group.totalPoints} pts',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),

          // PAGINATION CONTROL BAR AT BOTTOM (BY 15 ITEMS)
          _buildEmployeeBadgesPaginationBar(totalCount),
        ],
      ),
    );
  }

  Widget _buildEmployeeBadgesPaginationBar(int totalItems) {
    if (totalItems == 0) return const SizedBox.shrink();

    final pageCount = (totalItems / _employeeBadgesPerPage).ceil();
    final firstItem = _employeeBadgesCurrentPage * _employeeBadgesPerPage + 1;
    final lastItem = math.min(firstItem + _employeeBadgesPerPage - 1, totalItems);

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
              'Showing $firstItem-$lastItem of $totalItems employees',
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _employeeBadgesCurrentPage == 0
                ? null
                : () => setState(() => _employeeBadgesCurrentPage--),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
          Text(
            'Page ${_employeeBadgesCurrentPage + 1} of $pageCount',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _employeeBadgesCurrentPage >= pageCount - 1
                ? null
                : () => setState(() => _employeeBadgesCurrentPage++),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  void _openEmployeeBadgesDetailModal(_EmployeeBadgeGroup group) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 540,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildEmployeeAvatar(group.employeeName, group.employeeAvatarColor, radius: 18, photoUrl: group.employeePhotoUrl),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.employeeName,
                                  style: const TextStyle(
                                    fontFamily: HygTypography.headingFontFamily,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: HygColors.ink,
                                  ),
                                ),
                                Text(
                                  group.employeeDepartment,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 16),

                    // SUMMARY PILLS
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                          child: Text('${group.badgeCount} Total Badges', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                          child: Text('+${group.totalPoints} Total Bonus Points', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // BADGES TIMELINE LIST WITH REMOVE BUTTON
                    const Text('BADGES EARNED', style: HygTypography.fieldLabel),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: group.records.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No awarded badges remaining.', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(8),
                              itemCount: group.records.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              itemBuilder: (context, idx) {
                                final rec = group.records[idx];
                                final dateStr = '${rec.awardedAt.month}/${rec.awardedAt.day}/${rec.awardedAt.year}';
                                final badgeDesc = _getBadgeDescription(rec.badgeId, rec.badgeTitle, rec.badgeDescription);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: rec.badgeIconBgColor, borderRadius: BorderRadius.circular(8)),
                                        child: (rec.customImagePath != null && rec.customImagePath!.isNotEmpty && File(rec.customImagePath!).existsSync())
                                            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(File(rec.customImagePath!), width: 20, height: 20, fit: BoxFit.cover))
                                            : Icon(rec.badgeIcon, size: 20, color: rec.badgeIconColor),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(rec.badgeTitle, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: HygColors.ink)),
                                                const SizedBox(width: 6),
                                                Text('+${rec.pointsAwarded} pts', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                                              ],
                                            ),
                                            if (badgeDesc.isNotEmpty)
                                              Text(badgeDesc, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                                            if (rec.note.isNotEmpty)
                                              Text(rec.note, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                                            Text('Awarded on $dateStr by ${rec.awardedBy}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                        tooltip: 'Remove / Revoke Badge',
                                        onPressed: () => _confirmRemoveAwardedBadge(group, rec, setModalState, ctx),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmRemoveAwardedBadge(_EmployeeBadgeGroup group, AwardedBadgeRecord rec, StateSetter setModalState, BuildContext modalCtx) {
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('Revoke Awarded Badge'),
        content: Text('Are you sure you want to remove the "${rec.badgeTitle}" badge awarded to ${group.employeeName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(confirmCtx);

              await BadgesDatabaseService.deleteAwardedRecord(rec.id);

              setState(() {
                _awardedHistory.removeWhere((r) => r.id == rec.id);
                group.records.removeWhere((r) => r.id == rec.id);

                final idx = _badges.indexWhere((b) => b.id == rec.badgeId);
                if (idx != -1 && _badges[idx].awardedCount > 0) {
                  _badges[idx].awardedCount -= 1;
                }
              });

              setModalState(() {});

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Badge "${rec.badgeTitle}" revoked from ${group.employeeName}.'),
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                );
              }
            },
            child: const Text('Revoke Badge', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildAwardedHistoryTable() {
    final history = _filteredHistory;
    if (history.isEmpty) {
      return _buildEmptyState('No awarded badge records match your search query.');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // TABLE HEADER ROW
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('RECIPIENT', style: HygTypography.tableHeader)),
                Expanded(flex: 3, child: Text('BADGE', style: HygTypography.tableHeader)),
                Expanded(flex: 2, child: Text('BONUS POINTS', style: HygTypography.tableHeader)),
                Expanded(flex: 2, child: Text('AWARDED BY', style: HygTypography.tableHeader)),
                Expanded(flex: 2, child: Text('DATE & TIME', style: HygTypography.tableHeader)),
                Expanded(flex: 3, child: Text('REASON / NOTE', style: HygTypography.tableHeader)),
              ],
            ),
          ),

          // TABLE BODY ROWS
          ...history.asMap().entries.map((entry) {
            final isLast = entry.key == history.length - 1;
            final record = entry.value;
            final dateFormatted = '${record.awardedAt.year}-${record.awardedAt.month.toString().padLeft(2, '0')}-${record.awardedAt.day.toString().padLeft(2, '0')}';
            final timeFormatted = '${record.awardedAt.hour.toString().padLeft(2, '0')}:${record.awardedAt.minute.toString().padLeft(2, '0')}';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  // 1. RECIPIENT
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _buildEmployeeAvatar(record.employeeName, record.employeeAvatarColor, radius: 15, photoUrl: record.employeePhotoUrl),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.employeeName,
                                style: const TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                record.employeeDepartment,
                                style: const TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. BADGE
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: record.badgeIconBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: (record.customImagePath != null && record.customImagePath!.isNotEmpty && File(record.customImagePath!).existsSync())
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(record.customImagePath!),
                                    width: 16,
                                    height: 16,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(record.badgeIcon, size: 16, color: record.badgeIconColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                record.badgeTitle,
                                style: const TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_getBadgeDescription(record.badgeId, record.badgeTitle, record.badgeDescription).isNotEmpty)
                                Text(
                                  _getBadgeDescription(record.badgeId, record.badgeTitle, record.badgeDescription),
                                  style: const TextStyle(
                                    fontFamily: HygTypography.bodyFontFamily,
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. BONUS POINTS
                  Expanded(
                    flex: 2,
                    child: Text(
                      '+${record.pointsAwarded} pts',
                      style: const TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),

                  // 4. AWARDED BY
                  Expanded(
                    flex: 2,
                    child: Text(
                      record.awardedBy,
                      style: const TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 12.5,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // 5. DATE & TIME
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormatted,
                          style: const TextStyle(
                            fontFamily: HygTypography.bodyFontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          timeFormatted,
                          style: const TextStyle(
                            fontFamily: HygTypography.bodyFontFamily,
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 6. REASON / NOTE
                  Expanded(
                    flex: 3,
                    child: Text(
                      record.note.isNotEmpty ? record.note : '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.25,
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

  Widget _buildAutoGrantRulesPanel() {
    return Column(
      children: [
        _buildAutoRuleCard(
          title: 'Work Anniversary Auto-Badge',
          description: 'Automatically awards tenure badges (e.g. 1-Year, 5-Year Veteran) on employee hiring anniversaries.',
          trigger: 'On Hired Date Milestone',
          status: 'Active',
          icon: Icons.cake_outlined,
          iconBgColor: const Color(0xFFEFF6FF),
          iconColor: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 12),
        _buildAutoRuleCard(
          title: 'Birthday Celebration Badge',
          description: 'Awards birthday badge + 100 bonus points to employees on their birthday.',
          trigger: 'On Employee Birth Date',
          status: 'Active',
          icon: Icons.card_giftcard,
          iconBgColor: const Color(0xFFFFE4E6),
          iconColor: const Color(0xFFE11D48),
        ),
        const SizedBox(height: 12),
        _buildAutoRuleCard(
          title: 'Points Milestone Collector',
          description: 'Grants "Point Master" badge when an employee accumulates 5,000 lifetime points.',
          trigger: 'On Total Points Threshold (5,000 pts)',
          status: 'Draft',
          icon: Icons.stars,
          iconBgColor: const Color(0xFFFEF3C7),
          iconColor: const Color(0xFFD97706),
        ),
      ],
    );
  }

  Widget _buildAutoRuleCard({
    required String title,
    required String description,
    required String trigger,
    required String status,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    final isActive = status == 'Active';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: HygTypography.headingFontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: HygColors.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive ? const Color(0xFF15803D) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trigger: $trigger',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
          Switch(
            value: isActive,
            activeThumbColor: HygColors.goldStrong,
            onChanged: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Rule "$title" updated.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_outlined, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// BADGES HEADER
// ==========================================
class BadgesHeader extends StatelessWidget {
  const BadgesHeader({
    required this.onCreateBadge,
    required this.onAwardBadge,
    super.key,
  });

  final VoidCallback onCreateBadge;
  final VoidCallback onAwardBadge;

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
            Icons.verified_outlined,
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
                  'Badges & Achievements',
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
                  'Create and award achievement badges for employee milestones and accomplishments.',
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
          const SizedBox(width: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onAwardBadge,
            icon: const Icon(Icons.verified_outlined, size: 20, color: HygColors.ink),
            label: const Text('Award Badge', style: TextStyle(fontWeight: FontWeight.w700, color: HygColors.ink)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onCreateBadge,
            icon: const Icon(Icons.add, size: 19, color: HygColors.ink),
            label: const Text('Create Badge', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// EMPLOYEE BADGES GROUP DATA MODEL
// ==========================================
class _EmployeeBadgeGroup {
  _EmployeeBadgeGroup({
    required this.employeeId,
    required this.employeeName,
    required this.employeeDepartment,
    this.employeeCompany = 'HYG Group',
    required this.employeeAvatarColor,
    this.employeePhotoUrl,
    required this.records,
  });

  final String employeeId;
  final String employeeName;
  final String employeeDepartment;
  final String employeeCompany;
  final Color employeeAvatarColor;
  final String? employeePhotoUrl;
  final List<AwardedBadgeRecord> records;

  int get totalPoints => records.fold<int>(0, (sum, r) => sum + r.pointsAwarded);
  int get badgeCount => records.length;
}

// ==========================================
// BADGE CARD WIDGET (Clean White Theme from Inspiration Structure)
// ==========================================
class _BadgeCardWidget extends StatelessWidget {
  const _BadgeCardWidget({
    required this.badge,
    required this.awardedCount,
    required this.onAward,
    required this.onEdit,
    required this.onDelete,
  });

  final BadgeItem badge;
  final int awardedCount;
  final VoidCallback onAward;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TOP ROW: ICON CONTAINER + OPTIONS MENU
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ICON BOX (Top-left rounded container with background tint)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: badge.iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: (badge.customImagePath != null && badge.customImagePath!.isNotEmpty && File(badge.customImagePath!).existsSync())
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(badge.customImagePath!),
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          badge.iconData,
                          color: badge.iconColor,
                          size: 21,
                        ),
                ),
              ),

              // OPTIONS MENU (...)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Color(0xFF94A3B8), size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 130),
                onSelected: (val) {
                  if (val == 'award') onAward();
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'award',
                    child: Row(
                      children: [
                        Icon(Icons.verified_outlined, size: 16, color: HygColors.goldStrong),
                        SizedBox(width: 8),
                        Text('Award Badge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Text('Edit Badge', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(fontSize: 13, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // BADGE TITLE
          Text(
            badge.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: HygTypography.headingFontFamily,
              fontFamilyFallback: HygTypography.headingFallbacks,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: HygColors.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),

          // DESCRIPTION / CRITERIA SUBTITLE
          Text(
            badge.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: HygTypography.bodyFontFamily,
              fontFamilyFallback: HygTypography.fontFallbacks,
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.25,
            ),
          ),

          const Spacer(),

          // DIVIDER LINE
          const Divider(height: 12, thickness: 1, color: Color(0xFFF1F5F9)),

          // FOOTER: BONUS POINTS (LEFT) & AWARDED COUNT (RIGHT)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '+${badge.points} pts',
                style: const TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD97706),
                ),
              ),
              Text(
                '$awardedCount awarded',
                style: const TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// METRIC STAT CARD WIDGET
// ==========================================
class _MetricStatCard extends StatelessWidget {
  const _MetricStatCard({
    required this.label,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    this.valueFontSize,
  });

  final String label;
  final String value;
  final String subtext;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final double? valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
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
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: valueFontSize ?? 18,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtext,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 11,
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

// ==========================================
// CREATE / EDIT BADGE MODAL DIALOG
// ==========================================
class _CreateEditBadgeModal extends StatefulWidget {
  const _CreateEditBadgeModal({
    this.badge,
    required this.categories,
    required this.onSave,
  });

  final BadgeItem? badge;
  final List<String> categories;
  final ValueChanged<BadgeItem> onSave;

  @override
  State<_CreateEditBadgeModal> createState() => _CreateEditBadgeModalState();
}

class _CreateEditBadgeModalState extends State<_CreateEditBadgeModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _pointsController;
  late String _selectedCategory;
  bool _isUploadHovered = false;

  final List<String> _uploadedCustomIcons = [];
  String? _selectedCustomImagePath;

  final List<Map<String, dynamic>> _iconPresets = [
    {'icon': Icons.emoji_events, 'label': 'Trophy', 'bg': const Color(0xFFFEF3C7), 'color': const Color(0xFFD97706)},
    {'icon': Icons.rocket_launch, 'label': 'Rocket', 'bg': const Color(0xFFFFF7ED), 'color': const Color(0xFFEA580C)},
    {'icon': Icons.menu_book, 'label': 'Book', 'bg': const Color(0xFFEFF6FF), 'color': const Color(0xFF2563EB)},
    {'icon': Icons.workspace_premium, 'label': 'Premium', 'bg': const Color(0xFFFAF5FF), 'color': const Color(0xFF9333EA)},
    {'icon': Icons.favorite, 'label': 'Heart', 'bg': const Color(0xFFFFE4E6), 'color': const Color(0xFFE11D48)},
    {'icon': Icons.verified, 'label': 'Check', 'bg': const Color(0xFFECFDF5), 'color': const Color(0xFF059669)},
    {'icon': Icons.lightbulb_outline, 'label': 'Bulb', 'bg': const Color(0xFFFEF9C3), 'color': const Color(0xFFCA8A04)},
    {'icon': Icons.star, 'label': 'Star', 'bg': const Color(0xFFFEF3C7), 'color': const Color(0xFFD97706)},
  ];

  late int _selectedIconIndex;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.badge?.title ?? '');
    _descController = TextEditingController(text: widget.badge?.description ?? '');
    _pointsController = TextEditingController(text: widget.badge?.points.toString() ?? '100');
    _selectedCategory = widget.badge?.category ?? (widget.categories.isNotEmpty ? widget.categories.first : 'Milestones');

    _selectedIconIndex = 0;
    if (widget.badge != null) {
      if (widget.badge!.customImagePath != null && widget.badge!.customImagePath!.isNotEmpty) {
        _uploadedCustomIcons.add(widget.badge!.customImagePath!);
        _selectedCustomImagePath = widget.badge!.customImagePath;
        _selectedIconIndex = -1;
      } else {
        final idx = _iconPresets.indexWhere((p) => p['icon'] == widget.badge!.iconData);
        if (idx != -1) _selectedIconIndex = idx;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _pointsController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomIconImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'svg'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          if (!_uploadedCustomIcons.contains(path)) {
            _uploadedCustomIcons.insert(0, path);
          }
          _selectedCustomImagePath = path;
          _selectedIconIndex = -1;
        });
      }
    } catch (_) {}
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      IconData iconData = Icons.verified;
      Color iconBg = const Color(0xFFFEF3C7);
      Color iconColor = const Color(0xFFD97706);
      String? customPath = _selectedCustomImagePath;

      if (customPath != null) {
        iconData = Icons.image;
        iconBg = const Color(0xFFECFDF5);
        iconColor = const Color(0xFF059669);
      } else if (_selectedIconIndex >= 0 && _selectedIconIndex < _iconPresets.length) {
        final selectedPreset = _iconPresets[_selectedIconIndex];
        iconData = selectedPreset['icon'] as IconData;
        iconBg = selectedPreset['bg'] as Color;
        iconColor = selectedPreset['color'] as Color;
      }

      final newBadge = BadgeItem(
        id: widget.badge?.id ?? 'bdg_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _selectedCategory,
        iconData: iconData,
        customImagePath: customPath,
        iconBgColor: iconBg,
        iconColor: iconColor,
        points: int.tryParse(_pointsController.text) ?? 100,
        awardedCount: widget.badge?.awardedCount ?? 0,
      );

      widget.onSave(newBadge);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.badge != null;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TITLE BAR
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Badge' : 'Create New Badge',
                    style: const TextStyle(
                      fontFamily: HygTypography.headingFontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: HygColors.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ICON SELECTOR
              const Text('BADGE ICON & STYLE', style: HygTypography.fieldLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 1. FIXED PLUS (+) UPLOAD BUTTON ON LEFT (With Hover Effect!)
                  MouseRegion(
                    onEnter: (_) => setState(() => _isUploadHovered = true),
                    onExit: (_) => setState(() => _isUploadHovered = false),
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: _pickCustomIconImage,
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isUploadHovered ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isUploadHovered ? HygColors.ink : const Color(0xFFCBD5E1),
                            width: _isUploadHovered ? 1.8 : 1.2,
                          ),
                          boxShadow: _isUploadHovered
                              ? const [
                                  BoxShadow(
                                    color: Color(0x0F000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add,
                              size: 20,
                              color: _isUploadHovered ? HygColors.ink : const Color(0xFF64748B),
                            ),
                            Text(
                              'Upload',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: _isUploadHovered ? HygColors.ink : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // VERTICAL SEPARATOR LINE
                  Container(
                    height: 32,
                    width: 1.2,
                    color: const Color(0xFFCBD5E1),
                  ),

                  const SizedBox(width: 12),

                  // 2. SCROLLABLE ICON LIST (Only this scrolls)
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // A) UPLOADED CUSTOM ICONS (with 'x' remove badge)
                          ..._uploadedCustomIcons.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final path = entry.value;
                            final isSelected = _selectedCustomImagePath == path;

                            return Padding(
                              padding: const EdgeInsets.only(right: 10, top: 4),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  InkWell(
                                    onTap: () => setState(() {
                                      _selectedCustomImagePath = path;
                                      _selectedIconIndex = -1;
                                    }),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(10),
                                        border: isSelected
                                            ? Border.all(color: HygColors.ink, width: 2.5)
                                            : Border.all(color: const Color(0xFF059669), width: 1.2),
                                      ),
                                      child: Center(
                                        child: File(path).existsSync()
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: Image.file(
                                                  File(path),
                                                  width: 32,
                                                  height: 32,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : const Icon(Icons.image, size: 22, color: Color(0xFF059669)),
                                      ),
                                    ),
                                  ),

                                  // REMOVE ICON (X) BADGE AT TOP RIGHT
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _uploadedCustomIcons.removeAt(idx);
                                          if (isSelected) {
                                            _selectedCustomImagePath = null;
                                            _selectedIconIndex = 0;
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 11, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          // B) PRESET ICONS
                          ..._iconPresets.asMap().entries.map((entry) {
                            final i = entry.key;
                            final preset = entry.value;
                            final isSelected = _selectedIconIndex == i && _selectedCustomImagePath == null;
                            return Padding(
                              padding: const EdgeInsets.only(right: 10, top: 4),
                              child: InkWell(
                                onTap: () => setState(() {
                                  _selectedIconIndex = i;
                                  _selectedCustomImagePath = null;
                                }),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: preset['bg'] as Color,
                                    borderRadius: BorderRadius.circular(10),
                                    border: isSelected
                                        ? Border.all(color: HygColors.ink, width: 2.5)
                                        : Border.all(color: Colors.transparent),
                                  ),
                                  child: Icon(
                                    preset['icon'] as IconData,
                                    color: preset['color'] as Color,
                                    size: 22,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // TITLE INPUT
              const Text('BADGE TITLE', style: HygTypography.fieldLabel),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter badge title' : null,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Early Adopter, Top Performer',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // CATEGORY & POINTS ROW
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CATEGORY', style: HygTypography.fieldLabel),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          items: widget.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BONUS POINTS (+PTS)', style: HygTypography.fieldLabel),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _pointsController,
                          keyboardType: TextInputType.number,
                          validator: (val) => val == null || int.tryParse(val) == null ? 'Enter valid number' : null,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                          decoration: InputDecoration(
                            hintText: '100',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // DESCRIPTION INPUT
              const Text('DESCRIPTION / CRITERIA', style: HygTypography.fieldLabel),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Describe how an employee earns this badge...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),

              // ACTIONS
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _submitForm,
                    child: Text(
                      isEditing ? 'Save Changes' : 'Create Badge',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

// ==========================================
// AWARD BADGE TO EMPLOYEE MODAL DIALOG (MULTI-BADGE ENABLED)
// ==========================================
class _AwardBadgeModal extends StatefulWidget {
  const _AwardBadgeModal({
    required this.badges,
    required this.employees,
    this.preselectedBadge,
    this.preselectedEmployee,
    required this.onAwardMultiple,
  });

  final List<BadgeItem> badges;
  final List<EmployeePreview> employees;
  final BadgeItem? preselectedBadge;
  final EmployeePreview? preselectedEmployee;
  final Function(List<AwardedBadgeRecord> records, List<BadgeItem> selectedBadges) onAwardMultiple;

  @override
  State<_AwardBadgeModal> createState() => _AwardBadgeModalState();
}

class _AwardBadgeModalState extends State<_AwardBadgeModal> {
  final _formKey = GlobalKey<FormState>();
  final List<BadgeItem> _selectedBadges = [];
  final List<EmployeePreview> _selectedEmployees = [];
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _badgeSearchController = TextEditingController();
  String _badgeSearchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.preselectedBadge != null) {
      _selectedBadges.add(widget.preselectedBadge!);
    } else if (widget.badges.isNotEmpty) {
      _selectedBadges.add(widget.badges.first);
    }
    if (widget.preselectedEmployee != null) {
      _selectedEmployees.add(widget.preselectedEmployee!);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _badgeSearchController.dispose();
    super.dispose();
  }

  List<BadgeItem> get _filteredBadges {
    if (_badgeSearchQuery.trim().isEmpty) {
      return widget.badges;
    }
    final q = _badgeSearchQuery.trim().toLowerCase();
    return widget.badges.where((b) {
      return b.title.toLowerCase().contains(q) ||
          b.description.toLowerCase().contains(q) ||
          b.category.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleBadgeSelection(BadgeItem badge) {
    setState(() {
      if (_selectedBadges.any((b) => b.id == badge.id)) {
        if (_selectedBadges.length > 1) {
          _selectedBadges.removeWhere((b) => b.id == badge.id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('At least 1 badge must be selected.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        _selectedBadges.add(badge);
      }
    });
  }

  void _submitAward() {
    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 recipient employee.')),
      );
      return;
    }

    if (_selectedBadges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 badge to award.')),
      );
      return;
    }

    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    final noteText = _noteController.text.trim();
    if (noteText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recognition note / reason for awarding.')),
      );
      return;
    }
    final now = DateTime.now();
    final List<AwardedBadgeRecord> records = [];

    for (final emp in _selectedEmployees) {
      for (final badge in _selectedBadges) {
        records.add(
          AwardedBadgeRecord(
            id: 'awd_${now.millisecondsSinceEpoch}_${emp.id.hashCode}_${badge.id.hashCode}',
            badgeId: badge.id,
            badgeTitle: badge.title,
            badgeDescription: badge.description,
            badgeIcon: badge.iconData,
            customImagePath: badge.customImagePath,
            badgeIconBgColor: badge.iconBgColor,
            badgeIconColor: badge.iconColor,
            employeeId: emp.id,
            employeeName: emp.name,
            employeeDepartment: emp.departmentName,
            employeeAvatarColor: emp.avatarColor,
            employeePhotoUrl: emp.photoUrl,
            awardedBy: 'Super Admin',
            awardedAt: now,
            note: noteText,
            pointsAwarded: badge.points,
          ),
        );
      }
    }

    widget.onAwardMultiple(records, List.from(_selectedBadges));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final totalPoints = _selectedBadges.fold<int>(0, (sum, b) => sum + b.points);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_outlined, color: HygColors.goldStrong, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Award Badges to Employee',
                        style: TextStyle(
                          fontFamily: HygTypography.headingFontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: HygColors.ink,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // SELECT RECIPIENT EMPLOYEES (MULTI-SELECT PICKER)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('RECIPIENT EMPLOYEES', style: HygTypography.fieldLabel),
                  if (_selectedEmployees.isNotEmpty)
                    Text(
                      '${_selectedEmployees.length} employee${_selectedEmployees.length > 1 ? "s" : ""} selected',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _SearchableEmployeeSelectorButton(
                employees: widget.employees,
                selectedEmployees: _selectedEmployees,
                onSelected: (list) => setState(() {
                  _selectedEmployees.clear();
                  _selectedEmployees.addAll(list);
                }),
              ),
              const SizedBox(height: 16),

              // SELECT BADGES (MULTI-SELECT LIST WITH SEARCH)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SELECT BADGES TO AWARD', style: HygTypography.fieldLabel),
                  Text(
                    '${_selectedBadges.length} selected (+$totalPoints pts)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // SEARCH FIELD FOR FAST BADGE FINDING
              SizedBox(
                height: 38,
                child: TextField(
                  controller: _badgeSearchController,
                  style: const TextStyle(fontSize: 13),
                  onChanged: (val) => setState(() => _badgeSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Type to search badge title, criteria, or category...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                    suffixIcon: _badgeSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: Color(0xFF64748B)),
                            onPressed: () {
                              _badgeSearchController.clear();
                              setState(() => _badgeSearchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _filteredBadges.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'No matching badges found',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _filteredBadges.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, idx) {
                          final badge = _filteredBadges[idx];
                          final isSelected = _selectedBadges.any((b) => b.id == badge.id);

                    return InkWell(
                      onTap: () => _toggleBadgeSelection(badge),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: isSelected,
                                activeColor: HygColors.goldStrong,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (_) => _toggleBadgeSelection(badge),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: badge.iconBgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: (badge.customImagePath != null &&
                                        badge.customImagePath!.isNotEmpty &&
                                        File(badge.customImagePath!).existsSync())
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: Image.file(
                                          File(badge.customImagePath!),
                                          width: 22,
                                          height: 22,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Icon(
                                        badge.iconData,
                                        color: badge.iconColor,
                                        size: 16,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    badge.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? HygColors.ink : const Color(0xFF475569),
                                    ),
                                  ),
                                  if (badge.description.trim().isNotEmpty)
                                    Text(
                                      badge.description,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    badge.category,
                                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${badge.points} pts',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // RECOGNITION NOTE (REQUIRED FIELD)
              const Row(
                children: [
                  Text('RECOGNITION NOTE / REASON', style: HygTypography.fieldLabel),
                  SizedBox(width: 4),
                  Text('*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Recognition note / reason is required.';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'e.g. Outstanding teamwork and performance in Q3!',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),

              // ACTIONS
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _submitAward,
                    icon: const Icon(Icons.verified, size: 18, color: HygColors.ink),
                    label: Text(
                      _selectedEmployees.length > 1
                          ? 'Award ${_selectedBadges.length} Badge${_selectedBadges.length > 1 ? "s" : ""} to ${_selectedEmployees.length} Employees'
                          : (_selectedBadges.length > 1
                              ? 'Award ${_selectedBadges.length} Badges'
                              : 'Award Badge'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

// ==========================================
// HIGH-VISIBILITY EMPLOYEE AVATAR HELPER
// ==========================================
Widget _buildEmployeeAvatar(
  String name,
  Color bg, {
  double radius = 13,
  String? photoUrl,
}) {
  final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
  final luminance = bg.computeLuminance();
  final textColor = luminance > 0.35 ? const Color(0xFF0F172A) : Colors.white;
  final fontSize = radius * 0.85;

  final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

  return Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      color: bg,
      shape: BoxShape.circle,
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
      border: Border.all(
        color: luminance > 0.35 ? const Color(0x40000000) : const Color(0x40FFFFFF),
        width: 1.2,
      ),
    ),
    child: ClipOval(
      child: hasPhoto
          ? (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')
              ? Image.network(
                  photoUrl,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildAvatarInitial(initial, textColor, fontSize),
                )
              : (File(photoUrl).existsSync()
                  ? Image.file(
                      File(photoUrl),
                      width: radius * 2,
                      height: radius * 2,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildAvatarInitial(initial, textColor, fontSize),
                    )
                  : _buildAvatarInitial(initial, textColor, fontSize)))
          : _buildAvatarInitial(initial, textColor, fontSize),
    ),
  );
}

Widget _buildAvatarInitial(String initial, Color textColor, double fontSize) {
  return Center(
    child: Text(
      initial,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

// ==========================================
// SEARCHABLE EMPLOYEE SELECTOR BUTTON & PICKER DIALOG (MULTI-SELECT)
// ==========================================
class _SearchableEmployeeSelectorButton extends StatelessWidget {
  const _SearchableEmployeeSelectorButton({
    required this.employees,
    required this.selectedEmployees,
    required this.onSelected,
  });

  final List<EmployeePreview> employees;
  final List<EmployeePreview> selectedEmployees;
  final ValueChanged<List<EmployeePreview>> onSelected;

  void _openPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _EmployeePickerDialog(
        employees: employees,
        initialSelected: selectedEmployees,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = selectedEmployees.length;

    return InkWell(
      onTap: employees.isNotEmpty ? () => _openPicker(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            if (count == 0) ...[
              const Expanded(
                child: Text(
                  'Select Recipient Employees',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ),
            ] else if (count == 1) ...[
              _buildEmployeeAvatar(selectedEmployees.first.name, selectedEmployees.first.avatarColor, radius: 12, photoUrl: selectedEmployees.first.photoUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      selectedEmployees.first.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HygColors.ink),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${selectedEmployees.first.departmentName}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              SizedBox(
                width: 18.0 * (count > 3 ? 3 : count) + 12,
                height: 24,
                child: Stack(
                  children: List.generate(count > 3 ? 3 : count, (idx) {
                    final emp = selectedEmployees[idx];
                    return Positioned(
                      left: idx * 14.0,
                      child: _buildEmployeeAvatar(emp.name, emp.avatarColor, radius: 11, photoUrl: emp.photoUrl),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${selectedEmployees.first.name} + ${count - 1} other employee${count - 1 == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HygColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count selected',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _EmployeePickerDialog extends StatefulWidget {
  const _EmployeePickerDialog({
    required this.employees,
    required this.initialSelected,
    required this.onSelected,
  });

  final List<EmployeePreview> employees;
  final List<EmployeePreview> initialSelected;
  final ValueChanged<List<EmployeePreview>> onSelected;

  @override
  State<_EmployeePickerDialog> createState() => _EmployeePickerDialogState();
}

class _EmployeePickerDialogState extends State<_EmployeePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late List<EmployeePreview> _selectedList;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedList = List.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeePreview> get _filteredEmployees {
    if (_searchQuery.trim().isEmpty) return widget.employees;
    final q = _searchQuery.trim().toLowerCase();
    return widget.employees.where((e) {
      return e.name.toLowerCase().contains(q) || e.departmentName.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleEmployee(EmployeePreview emp) {
    setState(() {
      if (_selectedList.any((e) => e.id == emp.id)) {
        _selectedList.removeWhere((e) => e.id == emp.id);
      } else {
        _selectedList.add(emp);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedList.length == widget.employees.length) {
        _selectedList.clear();
      } else {
        _selectedList = List.from(widget.employees);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selectedList.length == widget.employees.length && widget.employees.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // DIALOG HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Recipient Employees',
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // SEARCH BAR AT TOP OF DROPDOWN PICKER
            SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Type to search employee name or department...',
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Color(0xFF64748B)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // SELECT ALL / COUNT BAR
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedList.length} of ${widget.employees.length} employees selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                TextButton(
                  onPressed: widget.employees.isNotEmpty ? _toggleSelectAll : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    allSelected ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HygColors.goldStrong),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // EMPLOYEE LIST WITH CHECKBOXES
            Expanded(
              child: _filteredEmployees.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching employees found',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredEmployees.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (ctx, idx) {
                        final emp = _filteredEmployees[idx];
                        final isSelected = _selectedList.any((e) => e.id == emp.id);

                        return InkWell(
                          onTap: () => _toggleEmployee(emp),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0x80FEF3C7) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: isSelected,
                                    activeColor: HygColors.goldStrong,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (_) => _toggleEmployee(emp),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildEmployeeAvatar(emp.name, emp.avatarColor, radius: 14, photoUrl: emp.photoUrl),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        emp.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                          color: isSelected ? HygColors.ink : const Color(0xFF334155),
                                        ),
                                      ),
                                      Text(
                                        emp.departmentName,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // ACTIONS BAR
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HygColors.gold,
                    foregroundColor: HygColors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    widget.onSelected(_selectedList);
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Confirm Selection (${_selectedList.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
