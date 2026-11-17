part of '../main.dart';

// ==========================================
// TRAININGS SCREEN (REWARDS SYSTEM)
// ==========================================

class TrainingsScreen extends StatefulWidget {
  const TrainingsScreen({
    this.employees = const [],
    super.key,
  });

  final List<EmployeePreview> employees;

  @override
  State<TrainingsScreen> createState() => _TrainingsScreenState();
}

class _TrainingsScreenState extends State<TrainingsScreen> {
  int _activeTabIndex = 0; // 0: Upcoming, 1: Concluded
  String _searchQuery = '';
  String _selectedBadgeFilter = 'All Badges';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<TrainingItem> _trainings = [];
  List<BadgeItem> _availableBadges = [];
  List<EmployeePreview> _allEmployees = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      List<EmployeePreview> emps = widget.employees;
      if (emps.isEmpty) {
        emps = await EmployeeDirectoryService.loadEmployees(forceRefresh: forceRefresh);
      }

      final results = await Future.wait([
        TrainingsDatabaseService.loadTrainings(forceRefresh: forceRefresh),
        BadgesDatabaseService.loadBadges(forceRefresh: forceRefresh),
      ]);

      if (mounted) {
        setState(() {
          _trainings = results[0] as List<TrainingItem>;
          _availableBadges = results[1] as List<BadgeItem>;
          _allEmployees = emps;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading trainings data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Segregation: Upcoming vs Concluded
  List<TrainingItem> get _upcomingTrainings {
    return _trainings.where((t) => t.isUpcoming).toList()
      ..sort((a, b) => a.trainingDate.compareTo(b.trainingDate));
  }

  List<TrainingItem> get _concludedTrainings {
    return _trainings.where((t) => t.isConcluded).toList()
      ..sort((a, b) => b.trainingDate.compareTo(a.trainingDate));
  }

  List<TrainingItem> get _filteredTrainings {
    final list = _activeTabIndex == 0 ? _upcomingTrainings : _concludedTrainings;
    final q = _searchQuery.trim().toLowerCase();

    return list.where((item) {
      if (_selectedBadgeFilter != 'All Badges') {
        if (item.badgeTitle != _selectedBadgeFilter) return false;
      }

      if (q.isEmpty) return true;

      final matchTitle = item.title.toLowerCase().contains(q);
      final matchTrainer = item.trainer.toLowerCase().contains(q);
      final matchLocation = item.location.toLowerCase().contains(q);
      final matchBadge = (item.badgeTitle ?? '').toLowerCase().contains(q);
      final matchAttendee = item.attendees.any(
        (a) => a.name.toLowerCase().contains(q) || a.department.toLowerCase().contains(q),
      );

      return matchTitle || matchTrainer || matchLocation || matchBadge || matchAttendee;
    }).toList();
  }

  // Metrics
  int get _totalTrainingsCount => _trainings.length;
  int get _upcomingCount => _upcomingTrainings.length;
  int get _concludedCount => _concludedTrainings.length;
  int get _totalAttendeesTrained {
    final ids = <String>{};
    for (final t in _concludedTrainings) {
      for (final a in t.attendees) {
        ids.add(a.id);
      }
    }
    return ids.length;
  }

  // Actions
  void _openCreateTrainingModal([TrainingItem? trainingToEdit]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CreateEditTrainingModal(
        training: trainingToEdit,
        badges: _availableBadges,
        employees: _allEmployees.isNotEmpty ? _allEmployees : widget.employees,
        onSave: (savedItem) async {
          setState(() {
            final idx = _trainings.indexWhere((t) => t.id == savedItem.id);
            if (idx >= 0) {
              _trainings[idx] = savedItem;
            } else {
              _trainings.insert(0, savedItem);
            }
          });
          await TrainingsDatabaseService.saveTraining(savedItem);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  trainingToEdit != null
                      ? 'Training updated successfully.'
                      : 'Training scheduled successfully.',
                ),
                backgroundColor: const Color(0xFF0F172A),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _openTrainingDetails(TrainingItem item) {
    showDialog(
      context: context,
      builder: (ctx) => _TrainingDetailsDialog(
        training: item,
        onEdit: () {
          Navigator.pop(ctx);
          _openCreateTrainingModal(item);
        },
        onConclude: item.isUpcoming
            ? () {
                Navigator.pop(ctx);
                _concludeTrainingWithAward(item);
              }
            : null,
      ),
    );
  }

  void _confirmDeleteTraining(TrainingItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Training Session?'),
        content: Text(
          'Are you sure you want to delete "${item.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              setState(() {
                _trainings.removeWhere((t) => t.id == item.id);
              });
              Navigator.pop(ctx);
              await TrainingsDatabaseService.deleteTraining(item.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Training deleted successfully.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _concludeTrainingWithAward(TrainingItem item) {
    final hasBadge = item.hasBadge && item.attendees.isNotEmpty;
    bool awardBadges = hasBadge;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle_outline, color: HygColors.goldStrong, size: 24),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Conclude Training',
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mark "${item.title}" as concluded?',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: HygColors.ink),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This training session will be moved to the Concluded tab.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  if (hasBadge) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
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
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: item.badgeIconBgColor ?? const Color(0xFFFEF3C7),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item.badgeIcon ?? Icons.verified,
                                  size: 16,
                                  color: item.badgeIconColor ?? const Color(0xFFD97706),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Linked Badge: ${item.badgeTitle}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${item.badgePoints} pts',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: awardBadges,
                            activeColor: HygColors.goldStrong,
                            title: Text(
                              'Award "${item.badgeTitle}" to all ${item.attendees.length} attendees now',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Each attendee will receive points and have the badge added to their achievement history.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                            onChanged: (val) => setDialogState(() => awardBadges = val ?? false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HygColors.gold,
                  foregroundColor: HygColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() {
                    final idx = _trainings.indexWhere((t) => t.id == item.id);
                    if (idx >= 0) {
                      _trainings[idx] = item.copyWith(
                        status: 'Concluded',
                        isBadgesAwarded: awardBadges && item.hasBadge,
                      );
                    }
                  });
                  await TrainingsDatabaseService.concludeTraining(item, awardBadges: awardBadges);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          awardBadges && hasBadge
                              ? 'Training concluded! Badge awarded to ${item.attendees.length} attendees.'
                              : 'Training marked as concluded.',
                        ),
                        backgroundColor: const Color(0xFF0F172A),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
                child: const Text('Confirm & Conclude', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reopenTraining(TrainingItem item) async {
    setState(() {
      final idx = _trainings.indexWhere((t) => t.id == item.id);
      if (idx >= 0) {
        _trainings[idx] = item.copyWith(status: 'Upcoming');
      }
    });
    await TrainingsDatabaseService.reopenTraining(item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Training moved back to Upcoming.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: HygColors.gold),
            SizedBox(height: 12),
            Text(
              'Loading Trainings Program...',
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
        // 1. HEADER WITH "CREATE TRAINING" BUTTON
        _TrainingsHeader(
          onCreateTraining: () => _openCreateTrainingModal(),
          onRefresh: () => _loadData(forceRefresh: true),
        ),
        const SizedBox(height: 14),

        // 2. METRICS ROW
        _buildMetricsRow(),
        const SizedBox(height: 16),

        // 3. SEARCH & BADGE FILTER ROW
        _buildSearchBarAndFilters(),
        const SizedBox(height: 12),

        // 4. TWO TABS: UPCOMING & CONCLUDED
        _buildTabBar(),
        const SizedBox(height: 16),

        // 5. TAB CONTENT
        _buildTabContent(),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - (3 * 12)) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildMetricCard(
              title: 'Total Sessions',
              value: '$_totalTrainingsCount',
              subtitle: 'Scheduled all-time',
              icon: Icons.school_outlined,
              color: const Color(0xFF2563EB),
              bgColor: const Color(0xFFEFF6FF),
              width: cardWidth,
            ),
            _buildMetricCard(
              title: 'Upcoming',
              value: '$_upcomingCount',
              subtitle: 'Pending & yet to start',
              icon: Icons.calendar_today_outlined,
              color: const Color(0xFF0D9488),
              bgColor: const Color(0xFFF0FDFA),
              width: cardWidth,
            ),
            _buildMetricCard(
              title: 'Concluded',
              value: '$_concludedCount',
              subtitle: 'Completed trainings',
              icon: Icons.task_alt_outlined,
              color: const Color(0xFF7C3AED),
              bgColor: const Color(0xFFF5F3FF),
              width: cardWidth,
            ),
            _buildMetricCard(
              title: 'Attendees Trained',
              value: '$_totalAttendeesTrained',
              subtitle: 'Unique employees certified',
              icon: Icons.workspace_premium_outlined,
              color: const Color(0xFFD97706),
              bgColor: const Color(0xFFFEF3C7),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required double width,
  }) {
    return Container(
      width: width.clamp(180, 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBarAndFilters() {
    final badgeOptions = ['All Badges', ..._availableBadges.map((b) => b.title)];

    return Row(
      children: [
        // Search Input
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HygColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: _activeTabIndex == 0
                    ? 'Search upcoming trainings by name, attendee, trainer, or badge...'
                    : 'Search concluded trainings by name, attendee, or certification...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 19, color: Color(0xFF94A3B8)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Filter by Badge Dropdown
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: HygColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: badgeOptions.contains(_selectedBadgeFilter) ? _selectedBadgeFilter : 'All Badges',
              icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF64748B)),
              style: const TextStyle(fontSize: 13, color: HygColors.ink, fontWeight: FontWeight.w500),
              onChanged: (newVal) {
                if (newVal != null) {
                  setState(() => _selectedBadgeFilter = newVal);
                }
              },
              items: badgeOptions.map((title) {
                return DropdownMenuItem<String>(
                  value: title,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        title == 'All Badges' ? Icons.filter_list : Icons.verified_outlined,
                        size: 16,
                        color: title == 'All Badges' ? const Color(0xFF64748B) : HygColors.goldStrong,
                      ),
                      const SizedBox(width: 8),
                      Text(title),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // The 2 Tabs: Upcoming & Concluded
  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5)),
      ),
      child: Row(
        children: [
          _buildTabButton(0, 'Upcoming Trainings', _upcomingCount, Icons.schedule_outlined),
          const SizedBox(width: 28),
          _buildTabButton(1, 'Concluded Trainings', _concludedCount, Icons.task_alt_outlined),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count, IconData icon) {
    final isActive = _activeTabIndex == index;
    const activeGold = HygColors.goldStrong;

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
            Icon(
              icon,
              size: 16,
              color: isActive ? activeGold : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? HygColors.ink : const Color(0xFF64748B),
                letterSpacing: 0.2,
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

  Widget _buildTabContent() {
    final list = _filteredTrainings;

    if (list.isEmpty) {
      final isUpcomingTab = _activeTabIndex == 0;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HygColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isUpcomingTab ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUpcomingTab ? Icons.event_available_outlined : Icons.history_edu_outlined,
                size: 32,
                color: isUpcomingTab ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isUpcomingTab ? 'No Upcoming Trainings' : 'No Concluded Trainings',
              style: const TextStyle(
                fontFamily: HygTypography.headingFontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HygColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isUpcomingTab
                  ? 'There are no upcoming training sessions scheduled. Click "Create Training" above to schedule a new session.'
                  : 'No training sessions have been concluded yet. Once a training is marked as done, it will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            if (isUpcomingTab) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HygColors.gold,
                  foregroundColor: HygColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openCreateTrainingModal(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Training', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1100 ? 3 : (constraints.maxWidth > 700 ? 2 : 1);
        final itemWidth = (constraints.maxWidth - ((crossAxisCount - 1) * 16)) / crossAxisCount;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: list.map((training) {
            return SizedBox(
              width: itemWidth,
              child: _TrainingCard(
                training: training,
                onViewDetails: () => _openTrainingDetails(training),
                onEdit: () => _openCreateTrainingModal(training),
                onDelete: () => _confirmDeleteTraining(training),
                onConclude: training.isUpcoming ? () => _concludeTrainingWithAward(training) : null,
                onReopen: training.isConcluded ? () => _reopenTraining(training) : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ==========================================
// TRAININGS HEADER COMPONENT
// ==========================================
class _TrainingsHeader extends StatelessWidget {
  const _TrainingsHeader({
    required this.onCreateTraining,
    required this.onRefresh,
  });

  final VoidCallback onCreateTraining;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.school_outlined,
              color: HygColors.goldStrong,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trainings & Certifications',
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Organize and track upcoming and concluded employee training programs with reward badges.',
                  style: TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B), size: 20),
            tooltip: 'Refresh Trainings',
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onCreateTraining,
            icon: const Icon(Icons.add, size: 20),
            label: const Text(
              'Create Training',
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TRAINING CARD COMPONENT
// ==========================================
class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.training,
    required this.onViewDetails,
    required this.onEdit,
    required this.onDelete,
    this.onConclude,
    this.onReopen,
  });

  final TrainingItem training;
  final VoidCallback onViewDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onConclude;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = training.isUpcoming;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
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
          // CARD TOP BANNER / STATUS
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUpcoming ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isUpcoming ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isUpcoming ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isUpcoming ? 'Upcoming' : 'Concluded',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isUpcoming ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                // Awarded badge indicator (if concluded)
                if (training.isConcluded && training.isBadgesAwarded && training.hasBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, size: 13, color: Color(0xFFD97706)),
                        SizedBox(width: 4),
                        Text(
                          'Badges Awarded',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                // Popup menu for quick actions
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF94A3B8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'details') onViewDetails();
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                    if (val == 'conclude' && onConclude != null) onConclude!();
                    if (val == 'reopen' && onReopen != null) onReopen!();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('View Details & Roster', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Edit Training', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (isUpcoming && onConclude != null)
                      const PopupMenuItem(
                        value: 'conclude',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                            SizedBox(width: 8),
                            Text('Mark as Concluded', style: TextStyle(fontSize: 12.5, color: Color(0xFF16A34A))),
                          ],
                        ),
                      ),
                    if (!isUpcoming && onReopen != null)
                      const PopupMenuItem(
                        value: 'reopen',
                        child: Row(
                          children: [
                            Icon(Icons.replay, size: 16, color: Color(0xFF2563EB)),
                            SizedBox(width: 8),
                            Text('Reopen to Upcoming', style: TextStyle(fontSize: 12.5, color: Color(0xFF2563EB))),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(fontSize: 12.5, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // TITLE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: onViewDetails,
              child: Text(
                training.title,
                style: const TextStyle(
                  fontFamily: HygTypography.headingFontFamily,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: HygColors.ink,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // DATE & TIME
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  training.formattedDate,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.access_time_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    training.timeDisplay,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          if (training.location.isNotEmpty || training.trainer.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (training.location.isNotEmpty) ...[
                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        training.location,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (training.trainer.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.person_outline, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      training.trainer,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // LINKED BADGE CHIP
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: training.hasBadge
                ? Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: training.badgeIconBgColor ?? const Color(0xFFFEF3C7),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            training.badgeIcon ?? Icons.verified,
                            size: 15,
                            color: training.badgeIconColor ?? const Color(0xFFD97706),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CERTIFICATION BADGE',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
                              ),
                              Text(
                                training.badgeTitle!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HygColors.ink),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (training.badgePoints > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${training.badgePoints} pts',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                            ),
                          ),
                      ],
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
                        SizedBox(width: 6),
                        Text('No badge linked to this training', style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // ATTENDEES STACK & COUNT
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (training.attendees.isNotEmpty) ...[
                  SizedBox(
                    width: math.min(training.attendees.length, 3) * 16.0 + 12,
                    height: 24,
                    child: Stack(
                      children: List.generate(
                        math.min(training.attendees.length, 3),
                        (idx) {
                          final att = training.attendees[idx];
                          return Positioned(
                            left: idx * 14.0,
                            child: _buildAttendeeAvatar(att.name, att.avatarColor, radius: 11, photoUrl: att.photoUrl),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    training.attendees.isEmpty
                        ? 'No attendees assigned'
                        : '${training.attendees.length} attendee${training.attendees.length > 1 ? "s" : ""} enrolled',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: training.attendees.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ACTIONS FOOTER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: onViewDetails,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                  ),
                ),
                const Spacer(),
                if (isUpcoming && onConclude != null)
                  ElevatedButton(
                    onPressed: onConclude,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Conclude', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
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
// CREATE & EDIT TRAINING MODAL (SIMPLE & COMPLETE LIKE ADD REWARD)
// ==========================================
class _CreateEditTrainingModal extends StatefulWidget {
  const _CreateEditTrainingModal({
    this.training,
    required this.badges,
    required this.employees,
    required this.onSave,
  });

  final TrainingItem? training;
  final List<BadgeItem> badges;
  final List<EmployeePreview> employees;
  final ValueChanged<TrainingItem> onSave;

  @override
  State<_CreateEditTrainingModal> createState() => _CreateEditTrainingModalState();
}

class _CreateEditTrainingModalState extends State<_CreateEditTrainingModal> {
  final _titleController = TextEditingController();
  final _timeController = TextEditingController();
  final _locationController = TextEditingController();
  final _trainerController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _selectedDate;
  BadgeItem? _selectedBadge;
  final List<EmployeePreview> _selectedAttendees = [];
  List<EmployeePreview> _cachedEmployees = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _cachedEmployees = List.from(widget.employees);
    if (_cachedEmployees.isEmpty) {
      EmployeeDirectoryService.loadLocalEmployees().then((localList) {
        if (!mounted) return;
        if (localList.isNotEmpty) {
          setState(() => _cachedEmployees = localList);
        } else {
          EmployeeDirectoryService.loadEmployees().then((fetched) {
            if (!mounted) return;
            setState(() => _cachedEmployees = fetched);
          });
        }
      });
    }

    final t = widget.training;
    if (t != null) {
      _titleController.text = t.title;
      _timeController.text = t.timeDisplay;
      _locationController.text = t.location;
      _trainerController.text = t.trainer;
      _descriptionController.text = t.description;
      _selectedDate = t.trainingDate;
    } else {
      _timeController.text = '09:00 AM - 12:00 PM';
      _selectedDate = DateTime.now().add(const Duration(days: 3));
    }

    // Prepopulate badge
    if (t?.badgeId != null && widget.badges.isNotEmpty) {
      final match = widget.badges.where((b) => b.id == t!.badgeId).toList();
      if (match.isNotEmpty) {
        _selectedBadge = match.first;
      }
    }

    // Prepopulate attendees from existing training
    if (t != null && t.attendees.isNotEmpty) {
      final empPool = widget.employees.isNotEmpty ? widget.employees : _cachedEmployees;
      for (final att in t.attendees) {
        final match = empPool.where((e) => e.id == att.id).toList();
        if (match.isNotEmpty) {
          _selectedAttendees.add(match.first);
        } else {
          _selectedAttendees.add(
            EmployeePreview(
              id: att.id,
              name: att.name,
              initial: att.name.isNotEmpty ? att.name[0] : 'E',
              email: '',
              phone: '',
              photoUrl: att.photoUrl,
              idNumber: '',
              company: '',
              companyName: '',
              departmentName: att.department,
              positionName: att.position,
              roleDepartment: att.department,
              hired: '',
              rawHiredDate: '',
              createdAt: null,
              status: 'Active',
              avatarColor: att.avatarColor,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    _locationController.dispose();
    _trainerController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: HygColors.goldStrong,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: HygColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _openAttendeePicker() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchableEmployeeSelectorDialog(
        employees: _cachedEmployees.isNotEmpty ? _cachedEmployees : widget.employees,
        initialSelected: _selectedAttendees,
        onSelected: (list) {
          setState(() {
            _selectedAttendees.clear();
            _selectedAttendees.addAll(list);
            if (_selectedAttendees.isNotEmpty && _error == 'Please select at least 1 attendee.') {
              _error = null;
            }
          });
        },
      ),
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a training name.');
      return;
    }

    if (_selectedAttendees.isEmpty) {
      setState(() => _error = 'Please select at least 1 attendee.');
      return;
    }

    setState(() => _error = null);

    String startTime = '09:00 AM';
    String endTime = '12:00 PM';
    final timeText = _timeController.text.trim();
    if (timeText.contains('-')) {
      final parts = timeText.split('-');
      startTime = parts[0].trim();
      endTime = parts[1].trim();
    } else if (timeText.isNotEmpty) {
      startTime = timeText;
      endTime = '';
    }

    final attendeesList = _selectedAttendees.map((e) {
      return TrainingAttendee(
        id: e.id,
        name: e.name,
        department: e.departmentName,
        position: e.positionName,
        avatarColor: e.avatarColor,
        photoUrl: e.photoUrl,
        status: 'Enrolled',
      );
    }).toList();

    final item = TrainingItem(
      id: widget.training?.id ?? 'trn_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}',
      title: title,
      description: _descriptionController.text.trim(),
      trainingDate: _selectedDate,
      startTime: startTime,
      endTime: endTime,
      location: _locationController.text.trim(),
      trainer: _trainerController.text.trim(),
      badgeId: _selectedBadge?.id,
      badgeTitle: _selectedBadge?.title,
      badgeIcon: _selectedBadge?.iconData,
      badgeIconBgColor: _selectedBadge?.iconBgColor,
      badgeIconColor: _selectedBadge?.iconColor,
      badgePoints: _selectedBadge?.points ?? 0,
      attendees: attendeesList,
      status: widget.training?.status ?? 'Upcoming',
      isBadgesAwarded: widget.training?.isBadgesAwarded ?? false,
      createdBy: widget.training?.createdBy ?? 'Super Admin',
      createdAt: widget.training?.createdAt,
    );

    widget.onSave(item);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final formattedDateStr = '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.school_outlined,
                    color: HygColors.goldStrong,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.training != null ? 'Edit Training' : 'Create Training',
                  style: const TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF334155),
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 18),

            // ERROR BANNER
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // FORM BODY (SCROLLABLE)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. TRAINING NAME
                    const Text(
                      'Training Name',
                      style: TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'e.g., Customer Service Excellence',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: HygColors.goldStrong),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. DATE & TIME ROW (2 COLUMNS)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Date',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          formattedDateStr,
                                          style: const TextStyle(
                                            fontFamily: HygTypography.bodyFontFamily,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF0F172A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Time',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _timeController,
                                decoration: InputDecoration(
                                  hintText: '09:00 AM - 12:00 PM',
                                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                                  prefixIcon: const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: HygColors.goldStrong),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. LOCATION & TRAINER ROW (2 COLUMNS)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Location / Venue',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _locationController,
                                decoration: InputDecoration(
                                  hintText: 'e.g., Training Room B / Zoom',
                                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                                  prefixIcon: const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: HygColors.goldStrong),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Trainer / Facilitator',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _trainerController,
                                decoration: InputDecoration(
                                  hintText: 'e.g., Maria Garcia',
                                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                                  prefixIcon: const Icon(Icons.person_outline, size: 16, color: Color(0xFF64748B)),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: HygColors.goldStrong),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. ATTENDEES
                    const Text(
                      'Attendees',
                      style: TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _openAttendeePicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.people_outline, size: 18, color: Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedAttendees.isEmpty
                                    ? 'Select participating employees...'
                                    : '${_selectedAttendees.length} employee${_selectedAttendees.length > 1 ? "s" : ""} selected',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  color: _selectedAttendees.isEmpty
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF0F172A),
                                  fontWeight: _selectedAttendees.isEmpty
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. BADGE
                    const Text(
                      'Certification Badge',
                      style: TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBadge?.id,
                          isExpanded: true,
                          hint: const Text(
                            'None (No badge linked)',
                            style: TextStyle(
                              fontFamily: HygTypography.bodyFontFamily,
                              fontSize: 14,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'None (No badge linked)',
                                style: TextStyle(
                                  fontFamily: HygTypography.bodyFontFamily,
                                  fontSize: 14,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            ...widget.badges.map((b) {
                              return DropdownMenuItem<String>(
                                value: b.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: b.iconBgColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(b.iconData, size: 13, color: b.iconColor),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        b.title,
                                        style: const TextStyle(
                                          fontFamily: HygTypography.bodyFontFamily,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF0F172A),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '+${b.points} pts',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          onChanged: (id) {
                            setState(() {
                              if (id == null) {
                                _selectedBadge = null;
                              } else {
                                _selectedBadge = widget.badges.firstWhere((b) => b.id == id);
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 6. DESCRIPTION / OBJECTIVES
                    const Text(
                      'Description & Objectives',
                      style: TextStyle(
                        fontFamily: HygTypography.bodyFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Enter brief training overview, objectives, or instructions...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: HygColors.goldStrong),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 16),

            // FOOTER ACTIONS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFE2E8F0),
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HygColors.gold,
                    foregroundColor: HygColors.ink,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _submit,
                  child: Text(
                    widget.training != null ? 'Update Training' : 'Create Training',
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: HygColors.ink,
                    ),
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

// ==========================================
// TRAINING DETAILS & ROSTER DIALOG
// ==========================================
class _TrainingDetailsDialog extends StatelessWidget {
  const _TrainingDetailsDialog({
    required this.training,
    required this.onEdit,
    this.onConclude,
  });

  final TrainingItem training;
  final VoidCallback onEdit;
  final VoidCallback? onConclude;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: training.isUpcoming ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              training.isUpcoming ? 'UPCOMING SESSION' : 'CONCLUDED SESSION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: training.isUpcoming ? const Color(0xFF2563EB) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                          if (training.isBadgesAwarded && training.hasBadge) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'BADGES AWARDED',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        training.title,
                        style: const TextStyle(
                          fontFamily: HygTypography.headingFontFamily,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: HygColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // DETAILS BODY
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Schedule & Location Info Grid
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              const Text('Date: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(training.formattedDate, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                              const Spacer(),
                              const Icon(Icons.access_time, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              const Text('Time: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(training.timeDisplay, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                            ],
                          ),
                          if (training.location.isNotEmpty || training.trainer.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (training.location.isNotEmpty) ...[
                                  const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text('Venue: ${training.location}', style: const TextStyle(fontSize: 12.5)),
                                  ),
                                ],
                                if (training.trainer.isNotEmpty) ...[
                                  const Icon(Icons.person_outline, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text('Trainer: ${training.trainer}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // LINKED BADGE SHOWCASE
                    if (training.hasBadge) ...[
                      const Text('LINKED CERTIFICATION BADGE', style: HygTypography.fieldLabel),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: training.badgeIconBgColor ?? const Color(0xFFFEF3C7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                training.badgeIcon ?? Icons.verified,
                                color: training.badgeIconColor ?? const Color(0xFFD97706),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    training.badgeTitle!,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: HygColors.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Granted to attendees upon completing this session',
                                    style: TextStyle(fontSize: 11.5, color: Color(0xFF854D0E)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${training.badgePoints} pts',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // DESCRIPTION / OBJECTIVES
                    if (training.description.isNotEmpty) ...[
                      const Text('OBJECTIVES & OUTLINE', style: HygTypography.fieldLabel),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          training.description,
                          style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ATTENDEES ROSTER LIST
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('ATTENDEES ROSTER', style: HygTypography.fieldLabel),
                        Text(
                          '${training.attendees.length} Employees Enrolled',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: training.attendees.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: Text('No attendees enrolled yet.', style: TextStyle(color: Color(0xFF94A3B8))),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: training.attendees.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (ctx, idx) {
                                final att = training.attendees[idx];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      _buildAttendeeAvatar(att.name, att.avatarColor, radius: 14, photoUrl: att.photoUrl),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              att.name,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HygColors.ink),
                                            ),
                                            Text(
                                              '${att.department} ${att.position.isNotEmpty ? "• " + att.position : ""}',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: training.isConcluded ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          training.isConcluded ? 'Completed' : 'Enrolled',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: training.isConcluded ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                                          ),
                                        ),
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
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // FOOTER ACTIONS
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Training'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),
                if (training.isUpcoming && onConclude != null) ...[
                  ElevatedButton.icon(
                    onPressed: onConclude,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Conclude & Award Badges'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SEARCHABLE EMPLOYEE PICKER DIALOG
// ==========================================
class _SearchableEmployeeSelectorDialog extends StatefulWidget {
  const _SearchableEmployeeSelectorDialog({
    required this.employees,
    required this.initialSelected,
    required this.onSelected,
  });

  final List<EmployeePreview> employees;
  final List<EmployeePreview> initialSelected;
  final ValueChanged<List<EmployeePreview>> onSelected;

  @override
  State<_SearchableEmployeeSelectorDialog> createState() => _SearchableEmployeeSelectorDialogState();
}

class _SearchableEmployeeSelectorDialogState extends State<_SearchableEmployeeSelectorDialog> {
  final TextEditingController _searchController = TextEditingController();
  late List<EmployeePreview> _selectedList;
  late Set<String> _selectedIds;
  List<EmployeePreview> _cachedEmployees = [];
  List<String> _departments = ['All Departments'];
  String _searchQuery = '';
  String _selectedDeptFilter = 'All Departments';
  bool _isLoadingEmployees = false;

  @override
  void initState() {
    super.initState();
    _selectedList = List.from(widget.initialSelected);
    _selectedIds = _selectedList.map((e) => e.id).toSet();
    _cachedEmployees = List.from(widget.employees);
    _computeDepartments();

    // If passed list was empty (e.g. initial launch), fetch from memory or SQLite cache immediately
    if (_cachedEmployees.isEmpty) {
      _isLoadingEmployees = true;
      EmployeeDirectoryService.loadLocalEmployees().then((localList) {
        if (!mounted) return;
        if (localList.isNotEmpty) {
          setState(() {
            _cachedEmployees = localList;
            _isLoadingEmployees = false;
            _computeDepartments();
          });
        } else {
          EmployeeDirectoryService.loadEmployees().then((fetchedList) {
            if (!mounted) return;
            setState(() {
              _cachedEmployees = fetchedList;
              _isLoadingEmployees = false;
              _computeDepartments();
            });
          });
        }
      });
    }
  }

  void _computeDepartments() {
    final depts = <String>{'All Departments'};
    for (final e in _cachedEmployees) {
      if (e.departmentName.trim().isNotEmpty) {
        depts.add(e.departmentName.trim());
      }
    }
    _departments = depts.toList()..sort();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeePreview> get _filteredEmployees {
    return _cachedEmployees.where((e) {
      if (_selectedDeptFilter != 'All Departments' && e.departmentName.trim() != _selectedDeptFilter) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return e.name.toLowerCase().contains(q) ||
          e.departmentName.toLowerCase().contains(q) ||
          e.positionName.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleEmployee(EmployeePreview emp) {
    setState(() {
      if (_selectedIds.contains(emp.id)) {
        _selectedIds.remove(emp.id);
        _selectedList.removeWhere((e) => e.id == emp.id);
      } else {
        _selectedIds.add(emp.id);
        _selectedList.add(emp);
      }
    });
  }

  void _toggleSelectAllFiltered() {
    final filtered = _filteredEmployees;
    final allFilteredSelected = filtered.isNotEmpty && filtered.every((e) => _selectedIds.contains(e.id));

    setState(() {
      if (allFilteredSelected) {
        final idsToRemove = filtered.map((e) => e.id).toSet();
        _selectedIds.removeAll(idsToRemove);
        _selectedList.removeWhere((e) => idsToRemove.contains(e.id));
      } else {
        for (final emp in filtered) {
          if (_selectedIds.add(emp.id)) {
            _selectedList.add(emp);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEmployees;
    final allFilteredSelected = filtered.isNotEmpty && filtered.every((e) => _selectedIds.contains(e.id));

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 520,
        height: 580,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.person_add_alt_1_outlined, color: HygColors.goldStrong, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Select Training Attendees',
                      style: TextStyle(
                        fontFamily: HygTypography.headingFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: HygColors.ink,
                      ),
                    ),
                  ],
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

            // SEARCH BAR & DEPARTMENT FILTER
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 13),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search employee name or position...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
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
                ),
                const SizedBox(width: 8),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDeptFilter,
                      style: const TextStyle(fontSize: 12.5, color: HygColors.ink),
                      items: _departments.map((d) {
                        return DropdownMenuItem<String>(
                          value: d,
                          child: Text(d, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDeptFilter = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // SELECTION COUNT & SELECT ALL BUTTON
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedList.length} of ${_cachedEmployees.length} employees selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                TextButton(
                  onPressed: filtered.isNotEmpty ? _toggleSelectAllFiltered : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    allFilteredSelected ? 'Deselect All Filtered' : 'Select All Filtered',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HygColors.goldStrong),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // EMPLOYEES LIST
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _isLoadingEmployees
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: HygColors.goldStrong),
                        ),
                      )
                    : filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching employees found',
                              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (ctx, idx) {
                              final emp = filtered[idx];
                              final isSelected = _selectedIds.contains(emp.id);

                              return InkWell(
                                onTap: () => _toggleEmployee(emp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  color: isSelected ? const Color(0xFFFEF3C7).withValues(alpha: 0.4) : Colors.transparent,
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
                                  _buildAttendeeAvatar(emp.name, emp.avatarColor, radius: 14, photoUrl: emp.photoUrl),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          emp.name,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HygColors.ink),
                                        ),
                                        Text(
                                          '${emp.departmentName} • ${emp.positionName}',
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
            ),
            const SizedBox(height: 14),

            // FOOTER CONFIRMATION
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    widget.onSelected(_selectedList);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HygColors.gold,
                    foregroundColor: HygColors.ink,
                  ),
                  child: Text('Done (${_selectedList.length} Selected)', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// ATTENDEE AVATAR HELPER
// ==========================================
Widget _buildAttendeeAvatar(
  String name,
  Color bg, {
  double radius = 12,
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
      border: Border.all(
        color: luminance > 0.35 ? const Color(0x30000000) : const Color(0x30FFFFFF),
        width: 1.0,
      ),
    ),
    alignment: Alignment.center,
    child: hasPhoto
        ? ClipOval(
            child: Image.network(
              photoUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(
                initial,
                style: TextStyle(
                  fontFamily: HygTypography.headingFontFamily,
                  color: textColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        : Text(
            initial,
            style: TextStyle(
              fontFamily: HygTypography.headingFontFamily,
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
  );
}
