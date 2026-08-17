part of '../main.dart';

class HygBirthdaysScreen extends StatefulWidget {
  const HygBirthdaysScreen({super.key});

  @override
  State<HygBirthdaysScreen> createState() => _HygBirthdaysScreenState();
}

class _HygBirthdaysScreenState extends State<HygBirthdaysScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<EmployeePreview> _allEmployees = [];
  bool _isLoading = true;
  String? _error;
  String _activeFilter = 'All'; // 'All', 'Passed', 'Today', 'Upcoming'

  @override
  void initState() {
    super.initState();
    _loadBirthdays();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBirthdays() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final employees = await EmployeeDirectoryService.loadEmployees();
      if (mounted) {
        setState(() {
          _allEmployees = employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  DateTime _phNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  DateTime? _parseBirthDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final str = raw.trim();

    try {
      return DateTime.parse(str);
    } catch (_) {}

    final parts = str.split(RegExp(r'[\s\-/,\._]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      int? year;
      int? month;
      int? day;

      const months = {
        'jan': 1, 'january': 1,
        'feb': 2, 'february': 2,
        'mar': 3, 'march': 3,
        'apr': 4, 'april': 4,
        'may': 5,
        'jun': 6, 'june': 6,
        'jul': 7, 'july': 7,
        'aug': 8, 'august': 8,
        'sep': 9, 'september': 9,
        'oct': 10, 'october': 10,
        'nov': 11, 'november': 11,
        'dec': 12, 'december': 12,
      };

      for (final p in parts) {
        final lower = p.toLowerCase();
        if (months.containsKey(lower)) {
          month = months[lower];
          break;
        }
      }

      final nums = parts.map((p) => int.tryParse(p)).whereType<int>().toList();

      if (month != null) {
        for (final n in nums) {
          if (n > 31) {
            year = n;
          } else if (day == null && n >= 1 && n <= 31) {
            day = n;
          }
        }
        year ??= DateTime.now().year;
        day ??= 1;
        return DateTime(year, month, day);
      }

      if (nums.length == 3) {
        if (nums[0] > 1000) {
          year = nums[0];
          if (nums[1] <= 12 && nums[2] <= 31) {
            month = nums[1];
            day = nums[2];
          } else if (nums[2] <= 12 && nums[1] <= 31) {
            month = nums[2];
            day = nums[1];
          }
        } else if (nums[2] > 1000) {
          year = nums[2];
          if (nums[0] <= 12 && nums[1] <= 31) {
            month = nums[0];
            day = nums[1];
          } else if (nums[1] <= 12 && nums[0] <= 31) {
            month = nums[1];
            day = nums[0];
          }
        } else {
          if (nums[0] <= 12) {
            month = nums[0];
            day = nums[1];
            year = nums[2] < 100 ? (nums[2] > 30 ? 1900 + nums[2] : 2000 + nums[2]) : nums[2];
          }
        }

        if (year != null && month != null && day != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime(year, month, day);
        }
      } else if (nums.length == 2) {
        if (nums[0] <= 12 && nums[1] <= 31) {
          month = nums[0];
          day = nums[1];
          year = DateTime.now().year;
          return DateTime(year, month, day);
        }
      }
    }

    return null;
  }

  List<_BirthdayItem> _getAllMonthBirthdays() {
    final now = _phNow();
    final currentMonth = now.month;
    final query = _searchController.text.trim().toLowerCase();

    final items = <_BirthdayItem>[];

    for (final emp in _allEmployees) {
      final bdate = _parseBirthDate(emp.rawBirthDate);
      if (bdate == null) continue;

      if (bdate.month != currentMonth) continue;

      if (query.isNotEmpty) {
        final nameMatch = emp.name.toLowerCase().contains(query);
        final deptMatch = emp.departmentName.toLowerCase().contains(query);
        final compMatch = emp.companyName.toLowerCase().contains(query);
        if (!nameMatch && !deptMatch && !compMatch) continue;
      }

      final isToday = bdate.day == now.day;
      final isUpcoming = bdate.day > now.day;
      final isPassed = bdate.day < now.day;

      items.add(_BirthdayItem(
        employee: emp,
        birthDate: bdate,
        dayOfMonth: bdate.day,
        isToday: isToday,
        isUpcoming: isUpcoming,
        isPassed: isPassed,
        daysDifference: bdate.day - now.day,
      ));
    }

    // Sort: Today first, then ascending by day of month
    items.sort((a, b) {
      if (a.isToday && !b.isToday) return -1;
      if (!a.isToday && b.isToday) return 1;
      return a.dayOfMonth.compareTo(b.dayOfMonth);
    });

    return items;
  }

  List<_BirthdayItem> _filterItems(List<_BirthdayItem> allItems) {
    if (_activeFilter == 'Passed') {
      return allItems.where((item) => item.isPassed).toList();
    } else if (_activeFilter == 'Today') {
      return allItems.where((item) => item.isToday).toList();
    } else if (_activeFilter == 'Upcoming') {
      return allItems.where((item) => item.isUpcoming || item.isToday).toList();
    }
    return allItems;
  }

  @override
  Widget build(BuildContext context) {
    final now = _phNow();
    const monthNames = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final currentMonthName = monthNames[now.month - 1];

    final allMonthItems = _getAllMonthBirthdays();
    final filtered = _filterItems(allMonthItems);

    final passedCount = allMonthItems.where((e) => e.isPassed).length;
    final todayCount = allMonthItems.where((e) => e.isToday).length;
    final upcomingCount = allMonthItems.where((e) => e.isUpcoming).length;

    return Scaffold(
      backgroundColor: HygColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, currentMonthName, now.year),
              const SizedBox(height: 14),
              _buildStatsBar(passedCount, todayCount, upcomingCount),
              const SizedBox(height: 14),
              _buildFilterAndSearchRow(),
              const SizedBox(height: 14),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                                const SizedBox(height: 10),
                                Text(_error!, style: const TextStyle(color: HygColors.ink)),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  onPressed: _loadBirthdays,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState(currentMonthName)
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  return _buildBirthdayCard(filtered[index], currentMonthName);
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String monthName, int year) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HygColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cake, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upcoming Birthdays',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Employee celebrations and birthdays for $monthName $year.',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(int passed, int today, int upcoming) {
    return Row(
      children: [
        Expanded(
          child: _buildStatChip(
            icon: Icons.history,
            iconColor: const Color(0xFF64748B),
            label: 'Passed Birthdays',
            count: '$passed',
            bgColor: const Color(0xFFF1F5F9),
            filterKey: 'Passed',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatChip(
            icon: Icons.celebration,
            iconColor: const Color(0xFFEC4899),
            label: "Today's Birthdays",
            count: '$today',
            bgColor: const Color(0xFFFDF2F8),
            filterKey: 'Today',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatChip(
            icon: Icons.auto_awesome,
            iconColor: const Color(0xFF8B5CF6),
            label: 'Upcoming Later',
            count: '$upcoming',
            bgColor: const Color(0xFFF5F3FF),
            filterKey: 'Upcoming',
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String count,
    required Color bgColor,
    required String filterKey,
  }) {
    final isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filterKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : HygColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF1E40AF) : HygColors.muted,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    count,
                    style: const TextStyle(
                      color: HygColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterAndSearchRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by employee name, department, or company...',
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: HygColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: HygColors.border),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 6,
          children: ['All', 'Upcoming', 'Today', 'Passed'].map((filter) {
            final isSelected = _activeFilter == filter;
            return ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _activeFilter = filter);
              },
              selectedColor: const Color(0xFF2563EB),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : HygColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF2563EB) : HygColors.border,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBirthdayCard(_BirthdayItem item, String monthName) {
    final emp = item.employee;

    Color cardBorderColor = const Color(0xFFE2E8F0);
    Color cardBgColor = Colors.white;

    if (item.isToday) {
      cardBorderColor = const Color(0xFFF472B6);
      cardBgColor = const Color(0xFFFFF1F2);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: item.isToday ? 1.5 : 1.0),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: EmployeeAvatar(employee: emp),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      emp.name,
                      style: const TextStyle(
                        color: HygColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cake, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'TODAY! 🎉',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${emp.positionName} • ${emp.departmentName}',
                  style: const TextStyle(
                    color: HygColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  emp.companyName,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: item.isToday
                  ? const Color(0xFFFCE7F3)
                  : item.isUpcoming
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: item.isToday
                    ? const Color(0xFFF472B6)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$monthName ${item.dayOfMonth}',
                  style: TextStyle(
                    color: item.isToday ? const Color(0xFFBE185D) : HygColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.isToday
                      ? 'Celebrating Today'
                      : item.isUpcoming
                          ? (item.daysDifference == 1 ? 'Tomorrow' : 'In ${item.daysDifference} days')
                          : 'Passed',
                  style: TextStyle(
                    color: item.isToday
                        ? const Color(0xFFDB2777)
                        : item.isUpcoming
                            ? const Color(0xFF2563EB)
                            : HygColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String monthName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFDF2F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cake_outlined, size: 48, color: Color(0xFFEC4899)),
          ),
          const SizedBox(height: 16),
          Text(
            'No birthdays found for $monthName',
            style: const TextStyle(
              color: HygColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try clearing your search or switching filters to view all employees.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HygColors.muted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayItem {
  const _BirthdayItem({
    required this.employee,
    required this.birthDate,
    required this.dayOfMonth,
    required this.isToday,
    required this.isUpcoming,
    required this.isPassed,
    required this.daysDifference,
  });

  final EmployeePreview employee;
  final DateTime birthDate;
  final int dayOfMonth;
  final bool isToday;
  final bool isUpcoming;
  final bool isPassed;
  final int daysDifference;
}
