part of '../main.dart';

class EventsAndActivitiesScreen extends StatefulWidget {
  const EventsAndActivitiesScreen({super.key});

  @override
  State<EventsAndActivitiesScreen> createState() => _EventsAndActivitiesScreenState();
}

class _EventsAndActivitiesScreenState extends State<EventsAndActivitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<PortalEventActivityItem> _events = [];
  bool _isLoading = true;
  String? _error;
  String _activeTypeFilter = 'All'; // 'All', 'Event', 'Activity'
  String _activeStatusFilter = 'All'; // 'All', 'Active', 'Inactive'

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await PortalEventActivityService.getEvents();
      if (mounted) {
        setState(() {
          _events = items;
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

  List<PortalEventActivityItem> get _filteredEvents {
    final query = _searchController.text.trim().toLowerCase();
    return _events.where((item) {
      if (_activeTypeFilter == 'Event' && !item.isEvent) return false;
      if (_activeTypeFilter == 'Activity' && !item.isActivity) return false;

      if (_activeStatusFilter == 'Active' && !item.isActive) return false;
      if (_activeStatusFilter == 'Inactive' && item.isActive) return false;

      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.location.toLowerCase().contains(query);
    }).toList();
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTimeDisplay(String timeStr) {
    if (timeStr.isEmpty) return '--:--';
    // If it's already in 12hr format, return as is
    if (timeStr.contains('AM') || timeStr.contains('PM') ||
        timeStr.contains('am') || timeStr.contains('pm')) {
      return timeStr;
    }
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final period = hour >= 12 ? 'PM' : 'AM';
      final formattedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final formattedMinute = minute.toString().padLeft(2, '0');
      return '$formattedHour:$formattedMinute $period';
    }
    return timeStr;
  }

  double _calculateHoursFromTimes(String timeFrom, String timeTo) {
    int toMinutes(String t) {
      final parts = t.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
      return 0;
    }

    final startMin = toMinutes(timeFrom);
    final endMin = toMinutes(timeTo);
    if (endMin <= startMin) {
      return 8.0;
    }
    final diffMinutes = endMin - startMin;
    final hrs = diffMinutes / 60.0;
    return double.parse(hrs.toStringAsFixed(2));
  }

  Future<void> _openAddEditModal([PortalEventActivityItem? existing]) async {
    final isEditing = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final locationController = TextEditingController(text: existing?.location ?? '');
    String selectedType = existing?.type ?? 'Event';
    DateTime selectedDate = existing?.eventDate ?? DateTime.now();
    DateTime? selectedEndDate = existing?.endDate;
    String timeFrom = existing?.timeFrom ?? '08:00';
    String timeTo = existing?.timeTo ?? '17:00';
    final hoursController = TextEditingController(
      text: existing != null
          ? existing.totalHours.toStringAsFixed(2)
          : _calculateHoursFromTimes(timeFrom, timeTo).toStringAsFixed(2),
    );
    bool isActive = existing?.isActive ?? true;
    bool isSubmitting = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 620,
                padding: const EdgeInsets.all(26),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: HygColors.gold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isEditing ? Icons.edit_calendar : Icons.event_available,
                              color: HygColors.ink,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing ? 'Edit Event or Activity' : 'Add New Event or Activity',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'This event will be selectable by employees when filing an ESARF.',
                                  style: HygTypography.body.copyWith(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(false),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: HygColors.border),
                      const SizedBox(height: 18),

                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dialogError!,
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Type Selector (Event vs Activity)
                      const Text(
                        'Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HygColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => selectedType = 'Event'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: selectedType == 'Event'
                                      ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selectedType == 'Event'
                                        ? const Color(0xFF2563EB)
                                        : HygColors.border,
                                    width: selectedType == 'Event' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.campaign_outlined,
                                      size: 18,
                                      color: selectedType == 'Event'
                                          ? const Color(0xFF2563EB)
                                          : HygColors.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Event',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selectedType == 'Event'
                                          ? const Color(0xFF2563EB)
                                          : HygColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => selectedType = 'Activity'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: selectedType == 'Activity'
                                      ? const Color(0xFF0D9488).withValues(alpha: 0.1)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selectedType == 'Activity'
                                        ? const Color(0xFF0D9488)
                                        : HygColors.border,
                                    width: selectedType == 'Activity' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.volunteer_activism_outlined,
                                      size: 18,
                                      color: selectedType == 'Activity'
                                          ? const Color(0xFF0D9488)
                                          : HygColors.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Activity',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selectedType == 'Activity'
                                          ? const Color(0xFF0D9488)
                                          : HygColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Title
                      const Text(
                        'Title *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HygColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Annual General Assembly, Team Building, Inventory Audit',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: HygColors.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Date & Location in a Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Event Date *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2035),
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedDate = picked;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: HygColors.border),
                                      color: Colors.white,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today_outlined, size: 16, color: HygColors.muted),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDate(selectedDate),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
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
                                  'Location',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: locationController,
                                  decoration: InputDecoration(
                                    hintText: 'e.g., HQ Main Hall, SM Megamall',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: HygColors.border),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Time From, Time To, and Total Hours in a Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Time From *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final parts = timeFrom.split(':');
                                    final initial = TimeOfDay(
                                      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8,
                                      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                                    );
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: initial,
                                    );
                                    if (picked != null) {
                                      final formatted =
                                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                      setDialogState(() {
                                        timeFrom = formatted;
                                        hoursController.text =
                                            _calculateHoursFromTimes(timeFrom, timeTo).toStringAsFixed(2);
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: HygColors.border),
                                      color: Colors.white,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 16, color: HygColors.muted),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatTimeDisplay(timeFrom),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
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
                                  'Time To *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final parts = timeTo.split(':');
                                    final initial = TimeOfDay(
                                      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 17 : 17,
                                      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                                    );
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: initial,
                                    );
                                    if (picked != null) {
                                      final formatted =
                                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                      setDialogState(() {
                                        timeTo = formatted;
                                        hoursController.text =
                                            _calculateHoursFromTimes(timeFrom, timeTo).toStringAsFixed(2);
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: HygColors.border),
                                      color: Colors.white,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time_filled, size: 16, color: HygColors.muted),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatTimeDisplay(timeTo),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
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
                                  'Credited Hours *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: hoursController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    hintText: '8.00',
                                    suffixText: 'hrs',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: HygColors.border),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HygColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Provide details, objectives, or instructions for this event/activity...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: HygColors.border),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Active Switch
                      Row(
                        children: [
                          Switch(
                            value: isActive,
                            activeThumbColor: const Color(0xFF0D9488),
                            onChanged: (val) {
                              setDialogState(() => isActive = val);
                            },
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Active (Visible in ESARF applications)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: HygColors.ink,
                                ),
                              ),
                              Text(
                                'When active, employees will be able to select this event upon applying for an ESARF.',
                                style: HygTypography.body.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final title = titleController.text.trim();
                                    if (title.isEmpty) {
                                      setDialogState(() {
                                        dialogError = 'Please enter a title for the event or activity.';
                                      });
                                      return;
                                    }
                                    final parsedHours = double.tryParse(hoursController.text.trim()) ?? 0.0;
                                    if (parsedHours <= 0) {
                                      setDialogState(() {
                                        dialogError = 'Please enter valid credited hours greater than 0.';
                                      });
                                      return;
                                    }

                                    setDialogState(() {
                                      isSubmitting = true;
                                      dialogError = null;
                                    });

                                    try {
                                      if (isEditing) {
                                        await PortalEventActivityService.updateEvent(
                                          id: existing.id,
                                          title: title,
                                          type: selectedType,
                                          description: descController.text.trim(),
                                          location: locationController.text.trim(),
                                          eventDate: selectedDate,
                                          endDate: selectedEndDate ?? selectedDate,
                                          timeFrom: timeFrom,
                                          timeTo: timeTo,
                                          totalHours: parsedHours,
                                          isActive: isActive,
                                        );
                                      } else {
                                        await PortalEventActivityService.createEvent(
                                          title: title,
                                          type: selectedType,
                                          description: descController.text.trim(),
                                          location: locationController.text.trim(),
                                          eventDate: selectedDate,
                                          endDate: selectedEndDate ?? selectedDate,
                                          timeFrom: timeFrom,
                                          timeTo: timeTo,
                                          totalHours: parsedHours,
                                          isActive: isActive,
                                        );
                                      }
                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop(true);
                                      }
                                    } catch (err) {
                                      setDialogState(() {
                                        dialogError = err.toString().replaceFirst('Exception: ', '');
                                        isSubmitting = false;
                                      });
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: HygColors.gold,
                              foregroundColor: HygColors.ink,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: HygColors.ink),
                                  )
                                : Text(
                                    isEditing ? 'Save Changes' : 'Create Event / Activity',
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
          },
        );
      },
    );

    if (saved == true) {
      _loadEvents();
    }
  }

  Future<void> _confirmDelete(PortalEventActivityItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Delete Event or Activity'),
          content: Text(
            'Are you sure you want to permanently delete "${item.title}"? Employees will no longer be able to select it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await PortalEventActivityService.deleteEvent(item.id);
        _loadEvents();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting event: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleActiveStatus(PortalEventActivityItem item) async {
    final nextStatus = !item.isActive;
    try {
      await PortalEventActivityService.toggleActive(item.id, nextStatus);
      setState(() {
        final idx = _events.indexWhere((e) => e.id == item.id);
        if (idx != -1) {
          _events[idx] = item.copyWith(isActive: nextStatus);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEvents;
    final totalCount = _events.length;
    final eventCount = _events.where((e) => e.isEvent).length;
    final activityCount = _events.where((e) => e.isActivity).length;
    final activeCount = _events.where((e) => e.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Card
        Container(
          padding: const EdgeInsets.all(20),
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
                Icons.event_available_outlined,
                color: HygColors.goldStrong,
                size: 42,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Events and Activities', style: HygTypography.pageTitle),
                    SizedBox(height: 3),
                    Text(
                      'Manage company events and official activities.',
                      style: HygTypography.body,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(160, 44),
                  backgroundColor: HygColors.gold,
                  foregroundColor: HygColors.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _openAddEditModal(),
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add Event or Activity',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Summary Stat Cards
        Row(
          children: [
            _buildStatCard(
              title: 'Total Items',
              value: totalCount.toString(),
              icon: Icons.calendar_month,
              iconColor: const Color(0xFF475569),
              bgColor: Colors.white,
            ),
            const SizedBox(width: 14),
            _buildStatCard(
              title: 'Company Events',
              value: eventCount.toString(),
              icon: Icons.campaign_rounded,
              iconColor: const Color(0xFF2563EB),
              bgColor: Colors.white,
            ),
            const SizedBox(width: 14),
            _buildStatCard(
              title: 'Activities',
              value: activityCount.toString(),
              icon: Icons.volunteer_activism_rounded,
              iconColor: const Color(0xFF0D9488),
              bgColor: Colors.white,
            ),
            const SizedBox(width: 14),
            _buildStatCard(
              title: 'Active in ESARF',
              value: activeCount.toString(),
              icon: Icons.check_circle_outline,
              iconColor: const Color(0xFF16A34A),
              bgColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Search & Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HygColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by title, location, description...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: HygColors.border),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Type Filter Chips
              _buildFilterChip('All Types', _activeTypeFilter == 'All', () {
                setState(() => _activeTypeFilter = 'All');
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Events Only', _activeTypeFilter == 'Event', () {
                setState(() => _activeTypeFilter = 'Event');
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Activities Only', _activeTypeFilter == 'Activity', () {
                setState(() => _activeTypeFilter = 'Activity');
              }),
              const SizedBox(width: 14),

              // Status Filter Chips
              _buildFilterChip('Active', _activeStatusFilter == 'Active', () {
                setState(() => _activeStatusFilter = _activeStatusFilter == 'Active' ? 'All' : 'Active');
              }),
              const SizedBox(width: 12),

              // Refresh Button
              IconButton(
                onPressed: _loadEvents,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, color: HygColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Content Area: Loading, Error, Empty, or List
        if (_isLoading) ...[
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HygColors.border),
            ),
            child: const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: HygColors.gold),
                  SizedBox(height: 12),
                  Text('Loading Events and Activities...', style: TextStyle(color: HygColors.muted)),
                ],
              ),
            ),
          ),
        ] else if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber_rounded, size: 40, color: Colors.red.shade600),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 14),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadEvents,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ] else if (filtered.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HygColors.border),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: HygColors.gold.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event_busy, size: 42, color: HygColors.ink),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Events or Activities Found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: HygColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchController.text.isNotEmpty || _activeTypeFilter != 'All'
                        ? 'Try adjusting your search or filters to find what you are looking for.'
                        : 'Get started by creating your first company event or activity.',
                    style: const TextStyle(color: HygColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                    ),
                    onPressed: () => _openAddEditModal(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Event or Activity', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = filtered[index];
              return _buildEventCard(item);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
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
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: HygColors.ink,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: HygColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? HygColors.ink : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF475569),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(PortalEventActivityItem item) {
    final isEvent = item.isEvent;
    final badgeColor = isEvent ? const Color(0xFF2563EB) : const Color(0xFF0D9488);
    final badgeBg = isEvent
        ? const Color(0xFF2563EB).withValues(alpha: 0.1)
        : const Color(0xFF0D9488).withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isActive ? HygColors.border : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Icon / Type Badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEvent ? Icons.campaign_rounded : Icons.volunteer_activism_rounded,
              color: badgeColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Main Event Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Type Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Active / Inactive Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.isActive
                            ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.isActive ? const Color(0xFF16A34A) : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            item.isActive ? 'Active in ESARF' : 'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: item.isActive ? const Color(0xFF16A34A) : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Title
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HygColors.ink,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: HygTypography.body.copyWith(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),

                // Metadata Chips: Date, Time, Credited Hours, Location
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _buildMetaChip(
                      icon: Icons.calendar_today_outlined,
                      label: _formatDate(item.eventDate),
                    ),
                    _buildMetaChip(
                      icon: Icons.schedule_outlined,
                      label: '${_formatTimeDisplay(item.timeFrom)} - ${_formatTimeDisplay(item.timeTo)}',
                    ),
                    _buildMetaChip(
                      icon: Icons.timelapse_outlined,
                      label: '${item.totalHours.toStringAsFixed(1)} hrs',
                      isHighlight: true,
                    ),
                    if (item.location.isNotEmpty)
                      _buildMetaChip(
                        icon: Icons.location_on_outlined,
                        label: item.location,
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Action Buttons: Edit, Delete, Toggle Active
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  item.isActive ? Icons.toggle_on : Icons.toggle_off,
                  size: 32,
                  color: item.isActive ? const Color(0xFF16A34A) : Colors.grey.shade400,
                ),
                tooltip: item.isActive ? 'Deactivate for ESARF' : 'Activate for ESARF',
                onPressed: () => _toggleActiveStatus(item),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: HygColors.muted),
                tooltip: 'Edit Event/Activity',
                onPressed: () => _openAddEditModal(item),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                tooltip: 'Delete Event/Activity',
                onPressed: () => _confirmDelete(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight
            ? HygColors.gold.withValues(alpha: 0.15)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight
              ? HygColors.goldStrong.withValues(alpha: 0.4)
              : HygColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isHighlight ? HygColors.ink : HygColors.muted,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
              color: isHighlight ? HygColors.ink : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
