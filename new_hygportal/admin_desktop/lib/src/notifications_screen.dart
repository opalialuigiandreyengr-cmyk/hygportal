part of '../main.dart';

// =============================================================================
// ADMIN NOTIFICATIONS & ACTIVITY CENTER
// =============================================================================

enum NotificationCategory {
  all,
  esarf,
  leave,
  perk,
  user,
  photoProof,
  system,
}

class AdminNotificationItem {
  AdminNotificationItem({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.actorName,
    this.actorPhoto,
    this.actorDepartment,
    this.actorCompany,
    required this.referenceId,
    required this.referenceType,
    required this.status,
    required this.createdAt,
    this.isRead = false,
    this.metadata = const {},
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String message;
  final String actorName;
  final String? actorPhoto;
  final String? actorDepartment;
  final String? actorCompany;
  final String referenceId;
  final String referenceType; // 'request', 'perk', 'user', 'proof', 'system'
  final String status;
  final DateTime createdAt;
  bool isRead;
  final Map<String, dynamic> metadata;

  String get categoryLabel {
    switch (category) {
      case NotificationCategory.esarf:
        return 'ESARF';
      case NotificationCategory.leave:
        return 'Leave';
      case NotificationCategory.perk:
        return 'Perks';
      case NotificationCategory.user:
        return 'User';
      case NotificationCategory.photoProof:
        return 'Photo Proof';
      case NotificationCategory.system:
        return 'System';
      case NotificationCategory.all:
        return 'All';
    }
  }

  Color get categoryColor {
    switch (category) {
      case NotificationCategory.esarf:
        return const Color(0xFFF97316); // Vibrant Orange
      case NotificationCategory.leave:
        return const Color(0xFF0284C7); // Sky Blue
      case NotificationCategory.perk:
        return const Color(0xFF9333EA); // Purple
      case NotificationCategory.user:
        return const Color(0xFF0D9488); // Teal
      case NotificationCategory.photoProof:
        return const Color(0xFF10B981); // Emerald Green
      case NotificationCategory.system:
        return const Color(0xFF6366F1); // Indigo
      case NotificationCategory.all:
        return const Color(0xFF64748B); // Slate
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case NotificationCategory.esarf:
        return Icons.access_time_filled_rounded;
      case NotificationCategory.leave:
        return Icons.event_available_rounded;
      case NotificationCategory.perk:
        return Icons.card_giftcard_rounded;
      case NotificationCategory.user:
        return Icons.person_add_alt_1_rounded;
      case NotificationCategory.photoProof:
        return Icons.photo_camera_rounded;
      case NotificationCategory.system:
        return Icons.info_outline_rounded;
      case NotificationCategory.all:
        return Icons.notifications_rounded;
    }
  }

  String timeAgo() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays >= 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays >= 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays >= 1) {
      return difference.inDays == 1 ? 'Yesterday' : '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class AdminNotificationsService {
  static final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<List<AdminNotificationItem>> notificationsNotifier =
      ValueNotifier<List<AdminNotificationItem>>([]);

  static final Set<String> _readIds = {};
  static Timer? _pollingTimer;
  static bool _isInitialized = false;
  static bool _isLoading = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _initReadDb();
    await loadNotifications();

    // Auto-refresh notifications every 15 seconds to keep the admin up to date
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(loadNotifications(silent: true));
    });
  }

  static void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  static Future<void> _initReadDb() async {
    try {
      final db = await LocalSyncService._database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS admin_notification_reads (
          notification_id TEXT PRIMARY KEY,
          read_at TEXT NOT NULL
        )
      ''');

      final rows = await db.query('admin_notification_reads');
      for (final r in rows) {
        final id = r['notification_id']?.toString();
        if (id != null && id.isNotEmpty) {
          _readIds.add(id);
        }
      }
    } catch (e) {
      debugPrint('AdminNotificationsService: Error initializing read DB: $e');
    }
  }

  static Future<List<AdminNotificationItem>> loadNotifications({
    bool silent = false,
  }) async {
    if (_isLoading) return notificationsNotifier.value;
    _isLoading = true;

    final items = <AdminNotificationItem>[];

    try {
      // 1. Fetch Requests (ESARF, Leave, Perks)
      try {
        final requests = await AdminRequestsService.loadAllRequests();
        for (final req in requests) {
          final isLeave = req.category == AdminRequestCategory.leave;
          final isPerk = req.category == AdminRequestCategory.perk;
          final isEsarf = req.category == AdminRequestCategory.esarf;

          DateTime? submittedDate;
          if (req.submittedAt != null && req.submittedAt!.isNotEmpty) {
            submittedDate = DateTime.tryParse(req.submittedAt!);
          }
          submittedDate ??= DateTime.now();

          NotificationCategory category = NotificationCategory.esarf;
          String title = 'ESARF Request';
          String message = '';

          if (isLeave) {
            category = NotificationCategory.leave;
            final isBday = req.isAutoApprovedBirthdayGrant;
            final leaveName = req.leaveType ?? 'Leave';
            title = isBday
                ? 'Birthday Leave (Auto-Approved)'
                : 'Leave Request: $leaveName';

            final daysStr = req.totalDays != null ? '${req.totalDays} day(s)' : '';
            final datesStr = req.startDate != null
                ? (req.endDate != null && req.endDate != req.startDate
                    ? '(${req.startDate} to ${req.endDate})'
                    : '(${req.startDate})')
                : '';
            final who = req.employeeName ?? 'An employee';
            message = '$who requested $daysStr $leaveName $datesStr'.trim();
            if (req.reason != null && req.reason!.trim().isNotEmpty) {
              message += ' • "${req.reason!.trim()}"';
            }
          } else if (isPerk) {
            category = NotificationCategory.perk;
            final prodName = req.perkProductName ?? 'Employee Perk';
            title = 'Perk Request: $prodName';

            final who = req.employeeName ?? 'An employee';
            final qtyStr = req.perkQuantity != null ? 'Qty: ${req.perkQuantity}' : '';
            final amountStr = req.perkFinalAmount != null
                ? '₱${req.perkFinalAmount!.toStringAsFixed(2)}'
                : (req.perkAmount != null ? '₱${req.perkAmount!.toStringAsFixed(2)}' : '');
            final extra = [qtyStr, amountStr].where((s) => s.isNotEmpty).join(' • ');
            message = '$who requested $prodName${extra.isNotEmpty ? ' ($extra)' : ''}';
          } else if (isEsarf) {
            category = NotificationCategory.esarf;
            final txName = req.transactionType ?? req.requestTypeName;
            title = 'ESARF: $txName';

            final who = req.employeeName ?? 'An employee';
            final hrsStr = req.totalHours != null && req.totalHours! > 0
                ? '${req.totalHours} hrs'
                : '';
            final dateStr = req.dateFrom != null ? req.dateFrom! : '';
            final extra = [hrsStr, dateStr].where((s) => s.isNotEmpty).join(' • ');
            message = '$who submitted $txName${extra.isNotEmpty ? ' ($extra)' : ''}';
            if (req.reason != null && req.reason!.trim().isNotEmpty) {
              message += ' • "${req.reason!.trim()}"';
            }
          }

          final notifId = 'req_${req.requestId}';
          final isRead = _readIds.contains(notifId);

          items.add(
            AdminNotificationItem(
              id: notifId,
              category: category,
              title: title,
              message: message,
              actorName: req.employeeName ?? 'Employee',
              actorPhoto: req.employeePhoto,
              actorDepartment: req.departmentName,
              actorCompany: req.companyName,
              referenceId: req.requestId,
              referenceType: isPerk ? 'perk' : 'request',
              status: req.status,
              createdAt: submittedDate,
              isRead: isRead,
              metadata: {
                'request': req,
                'category': req.category.name,
                'requestTypeCode': req.requestTypeCode,
                'storeName': req.storeName,
              },
            ),
          );
        }
      } catch (reqErr) {
        debugPrint('AdminNotificationsService: Error loading requests: $reqErr');
      }

      // 2. Fetch User Account Activities (Registered Users)
      try {
        final users = await RegisteredUsersService.loadUsers();
        final now = DateTime.now();
        for (final u in users) {
          DateTime? regDate;
          if (u.registeredAt.isNotEmpty) {
            regDate = DateTime.tryParse(u.registeredAt);
          }
          regDate ??= now;

          // Only include recent users (past 60 days) to keep activity relevant
          if (now.difference(regDate).inDays <= 60) {
            final notifId = 'user_${u.userProfileId}';
            final isRead = _readIds.contains(notifId);

            final who = u.fullName.isNotEmpty
                ? u.fullName
                : (u.username.isNotEmpty ? u.username : 'New User');
            final emailStr = u.email.isNotEmpty ? ' (${u.email})' : '';
            final roleStr = u.appRole.toUpperCase();

            items.add(
              AdminNotificationItem(
                id: notifId,
                category: NotificationCategory.user,
                title: 'User Account Created',
                message: '$who$emailStr registered with role $roleStr.',
                actorName: who,
                actorPhoto: u.photoUrl,
                actorDepartment: null,
                actorCompany: null,
                referenceId: u.userProfileId,
                referenceType: 'user',
                status: u.isActive ? 'Active' : 'Inactive',
                createdAt: regDate,
                isRead: isRead,
                metadata: {
                  'username': u.username,
                  'email': u.email,
                  'appRole': u.appRole,
                  'employeeNo': u.employeeNo,
                },
              ),
            );
          }
        }
      } catch (userErr) {
        debugPrint('AdminNotificationsService: Error loading users: $userErr');
      }

      // 3. Fetch Recent Photo Proofs (Past 50 uploads)
      try {
        final client = Supabase.instance.client;
        final response = await client
            .from('photo_proofs')
            .select('*')
            .order('timestamp', ascending: false)
            .limit(40);

        for (final row in response) {
          final proofId = row['id']?.toString() ?? '';
          if (proofId.isEmpty) continue;

            final notifId = 'proof_$proofId';
            final isRead = _readIds.contains(notifId);

            DateTime? proofDate;
            final rawTime = row['timestamp'] ?? row['created_at'];
            if (rawTime != null) {
              proofDate = DateTime.tryParse(rawTime.toString());
            }
            proofDate ??= DateTime.now();

            final empName = row['employee_name']?.toString() ??
                row['name']?.toString() ??
                'Employee';
            final storeName = row['store_name']?.toString() ??
                row['store']?.toString() ??
                'Store';
            final categoryName = row['category']?.toString() ?? 'Proof';

            items.add(
              AdminNotificationItem(
                id: notifId,
                category: NotificationCategory.photoProof,
                title: 'Photo Proof Uploaded: $categoryName',
                message: '$empName uploaded a proof at $storeName.',
                actorName: empName,
                actorPhoto: row['photo_url']?.toString(),
                actorDepartment: row['department_name']?.toString(),
                actorCompany: row['company_name']?.toString(),
                referenceId: proofId,
                referenceType: 'proof',
                status: 'submitted',
                createdAt: proofDate,
                isRead: isRead,
                metadata: row,
              ),
            );
          }
      } catch (proofErr) {
        debugPrint('AdminNotificationsService: Photo proofs fetch note: $proofErr');
      }

      // 4. Try RPC admin_get_notifications if available
      try {
        final client = Supabase.instance.client;
        final rpcResp = await client.rpc('admin_get_notifications', params: {'p_limit': 50});
        if (rpcResp is List) {
          for (final row in rpcResp.whereType<Map<String, dynamic>>()) {
            final sysId = row['id']?.toString() ?? '';
            if (sysId.isEmpty) continue;

            final notifId = 'sys_$sysId';
            final isRead = _readIds.contains(notifId);

            DateTime? notifDate;
            if (row['created_at'] != null) {
              notifDate = DateTime.tryParse(row['created_at'].toString());
            }
            notifDate ??= DateTime.now();

            items.add(
              AdminNotificationItem(
                id: notifId,
                category: NotificationCategory.system,
                title: row['title']?.toString() ?? 'System Notification',
                message: row['message']?.toString() ?? '',
                actorName: row['employee_name']?.toString() ?? 'HYG System',
                actorPhoto: row['employee_photo']?.toString(),
                actorDepartment: row['department_name']?.toString(),
                referenceId: row['link_id']?.toString() ?? sysId,
                referenceType: row['link_type']?.toString() ?? 'system',
                status: 'active',
                createdAt: notifDate,
                isRead: isRead,
                metadata: row,
              ),
            );
          }
        }
      } catch (_) {
        // RPC might not be present or needed yet; handled gracefully
      }

      // Sort all items newest first
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final unreadCount = items.where((i) => !i.isRead).length;

      notificationsNotifier.value = items;
      unreadCountNotifier.value = unreadCount;
    } catch (e) {
      debugPrint('AdminNotificationsService: General error in loadNotifications: $e');
    } finally {
      _isLoading = false;
    }

    return notificationsNotifier.value;
  }

  static Future<void> markAsRead(String id) async {
    if (_readIds.contains(id)) return;
    _readIds.add(id);

    try {
      final db = await LocalSyncService._database;
      await db.insert(
        'admin_notification_reads',
        {
          'notification_id': id,
          'read_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('AdminNotificationsService: Error saving read state: $e');
    }

    // Update in-memory list
    final current = notificationsNotifier.value;
    for (final item in current) {
      if (item.id == id) {
        item.isRead = true;
      }
    }
    notificationsNotifier.value = List.of(current);
    unreadCountNotifier.value = current.where((i) => !i.isRead).length;
  }

  static Future<void> markAllAsRead() async {
    final current = notificationsNotifier.value;
    final nowStr = DateTime.now().toIso8601String();

    try {
      final db = await LocalSyncService._database;
      final batch = db.batch();
      for (final item in current) {
        _readIds.add(item.id);
        item.isRead = true;
        batch.insert(
          'admin_notification_reads',
          {
            'notification_id': item.id,
            'read_at': nowStr,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('AdminNotificationsService: Error in markAllAsRead: $e');
      for (final item in current) {
        _readIds.add(item.id);
        item.isRead = true;
      }
    }

    notificationsNotifier.value = List.of(current);
    unreadCountNotifier.value = 0;
  }
}

// =============================================================================
// ADMIN NOTIFICATIONS DROPDOWN POPOVER
// =============================================================================

class AdminNotificationsPopover extends StatefulWidget {
  const AdminNotificationsPopover({
    required this.onClose,
    required this.onSelectNotification,
    required this.onOpenFullScreen,
    super.key,
  });

  final VoidCallback onClose;
  final void Function(AdminNotificationItem notification) onSelectNotification;
  final VoidCallback onOpenFullScreen;

  @override
  State<AdminNotificationsPopover> createState() => _AdminNotificationsPopoverState();
}

class _AdminNotificationsPopoverState extends State<AdminNotificationsPopover> {
  NotificationCategory _selectedCategory = NotificationCategory.all;
  bool _unreadOnly = false;
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await AdminNotificationsService.loadNotifications();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ValueListenableBuilder<List<AdminNotificationItem>>(
        valueListenable: AdminNotificationsService.notificationsNotifier,
        builder: (context, allNotifications, _) {
          // Compute category counts
          final esarfCount = allNotifications
              .where((n) => n.category == NotificationCategory.esarf)
              .length;
          final leaveCount = allNotifications
              .where((n) => n.category == NotificationCategory.leave)
              .length;
          final perkCount = allNotifications
              .where((n) => n.category == NotificationCategory.perk)
              .length;
          final activityCount = allNotifications
              .where((n) =>
                  n.category == NotificationCategory.user ||
                  n.category == NotificationCategory.photoProof ||
                  n.category == NotificationCategory.system)
              .length;

          // Filter notifications
          var filtered = allNotifications.where((n) {
            if (_unreadOnly && n.isRead) return false;
            if (_selectedCategory == NotificationCategory.all) return true;
            if (_selectedCategory == NotificationCategory.esarf) {
              return n.category == NotificationCategory.esarf;
            }
            if (_selectedCategory == NotificationCategory.leave) {
              return n.category == NotificationCategory.leave;
            }
            if (_selectedCategory == NotificationCategory.perk) {
              return n.category == NotificationCategory.perk;
            }
            if (_selectedCategory == NotificationCategory.system ||
                _selectedCategory == NotificationCategory.user ||
                _selectedCategory == NotificationCategory.photoProof) {
              return n.category == NotificationCategory.user ||
                  n.category == NotificationCategory.photoProof ||
                  n.category == NotificationCategory.system;
            }
            return true;
          }).toList();

          final unreadTotal = allNotifications.where((n) => !n.isRead).length;

          return Container(
            width: 440,
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- HEADER ---
                  _buildHeader(context, unreadTotal),

                  // --- CATEGORY TABS ---
                  _buildTabs(
                    allCount: allNotifications.length,
                    esarfCount: esarfCount,
                    leaveCount: leaveCount,
                    perkCount: perkCount,
                    activityCount: activityCount,
                  ),

                  // --- SUBHEADER / QUICK FILTER ---
                  _buildSubheader(unreadTotal),

                  // --- NOTIFICATIONS LIST ---
                  Expanded(
                    child: _isRefreshing
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Color(0xFFF1F5F9),
                                ),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return _buildNotificationTile(context, item);
                                },
                              ),
                  ),

                  // --- FOOTER ACTION ---
                  _buildFooter(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int unreadTotal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFFD97706),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          if (unreadTotal > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$unreadTotal new',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (unreadTotal > 0)
            Tooltip(
              message: 'Mark all as read',
              child: IconButton(
                icon: const Icon(Icons.done_all_rounded, size: 19),
                color: const Color(0xFF64748B),
                onPressed: () => AdminNotificationsService.markAllAsRead(),
                splashRadius: 18,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 19),
              color: const Color(0xFF64748B),
              onPressed: _refresh,
              splashRadius: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ),
          Tooltip(
            message: 'Open Activity Center (Full Screen)',
            child: IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              color: const Color(0xFF64748B),
              onPressed: () {
                widget.onClose();
                widget.onOpenFullScreen();
              },
              splashRadius: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 19),
            color: const Color(0xFF94A3B8),
            onPressed: widget.onClose,
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs({
    required int allCount,
    required int esarfCount,
    required int leaveCount,
    required int perkCount,
    required int activityCount,
  }) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTabChip('All', NotificationCategory.all, allCount),
            const SizedBox(width: 6),
            _buildTabChip('ESARF', NotificationCategory.esarf, esarfCount),
            const SizedBox(width: 6),
            _buildTabChip('Leave', NotificationCategory.leave, leaveCount),
            const SizedBox(width: 6),
            _buildTabChip('Perks', NotificationCategory.perk, perkCount),
            const SizedBox(width: 6),
            _buildTabChip('Activity', NotificationCategory.user, activityCount),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(
    String label,
    NotificationCategory category,
    int count,
  ) {
    final isSelected = _selectedCategory == category;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFCBD5E1) : Colors.transparent,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubheader(int unreadTotal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _unreadOnly ? 'Showing unread only' : 'Recent activity & requests',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _unreadOnly = !_unreadOnly),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _unreadOnly
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 15,
                    color: _unreadOnly
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Unread only',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          _unreadOnly ? FontWeight.w600 : FontWeight.w500,
                      color: _unreadOnly
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.done_all_rounded,
                size: 26,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'All Caught Up!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _unreadOnly
                  ? 'No unread notifications in this category.'
                  : 'No activity found in this category.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(BuildContext context, AdminNotificationItem item) {
    final statusColor = _statusColor(item.status);
    final statusBg = _statusBgColor(item.status);

    return InkWell(
      onTap: () {
        AdminNotificationsService.markAsRead(item.id);
        widget.onSelectNotification(item);
      },
      hoverColor: const Color(0xFFF8FAFC),
      child: Container(
        color: item.isRead ? Colors.white : const Color(0xFFF0F7FF),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar or Category Icon
            _buildAvatarOrIcon(item),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Category Tag
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: item.categoryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.categoryLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: item.categoryColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Time Ago
                      Text(
                        item.timeAgo(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const Spacer(),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatStatus(item.status),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (!item.isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Title
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          item.isRead ? FontWeight.w600 : FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Message
                  Text(
                    item.message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.actorDepartment != null &&
                      item.actorDepartment!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.domain_rounded,
                          size: 11,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.actorDepartment!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.actorCompany != null &&
                            item.actorCompany!.isNotEmpty) ...[
                          const Text(' • ',
                              style: TextStyle(
                                  color: Color(0xFFCBD5E1), fontSize: 10)),
                          Text(
                            item.actorCompany!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarOrIcon(AdminNotificationItem item) {
    if (item.actorPhoto != null && item.actorPhoto!.trim().isNotEmpty) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE2E8F0),
            backgroundImage: NetworkImage(item.actorPhoto!),
            onBackgroundImageError: (_, _) {},
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: item.categoryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(item.categoryIcon, size: 9, color: Colors.white),
            ),
          ),
        ],
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: item.categoryColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Icon(
          item.categoryIcon,
          size: 18,
          color: item.categoryColor,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: InkWell(
        onTap: () {
          widget.onClose();
          widget.onOpenFullScreen();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, size: 16, color: Color(0xFF334155)),
              SizedBox(width: 8),
              Text(
                'View All Activity & History',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatStatus(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'validated':
        return 'Validated';
      case 'needs_admin_review':
        return 'Needs Review';
      default:
        if (s.isEmpty) return 'Active';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  static Color _statusColor(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'pending':
      case 'needs_admin_review':
        return const Color(0xFFD97706);
      case 'approved':
      case 'validated':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  static Color _statusBgColor(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'pending':
      case 'needs_admin_review':
        return const Color(0xFFFEF3C7);
      case 'approved':
      case 'validated':
        return const Color(0xFFD1FAE5);
      case 'rejected':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF1F5F9);
    }
  }
}

// =============================================================================
// FULL-SCREEN NOTIFICATIONS & ACTIVITY CENTER
// =============================================================================

class HygNotificationsScreen extends StatefulWidget {
  const HygNotificationsScreen({
    this.onNavigateToRequests,
    this.onNavigateToUsers,
    this.onNavigateToProofs,
    super.key,
  });

  final void Function(int tabIndex)? onNavigateToRequests;
  final VoidCallback? onNavigateToUsers;
  final VoidCallback? onNavigateToProofs;

  @override
  State<HygNotificationsScreen> createState() => _HygNotificationsScreenState();
}

class _HygNotificationsScreenState extends State<HygNotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  NotificationCategory _activeCategory = NotificationCategory.all;
  String _selectedStatus = 'All';
  String _selectedDateRange = 'All Time';
  bool _unreadOnly = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    AdminNotificationsService.loadNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await AdminNotificationsService.loadNotifications();
    if (mounted) setState(() => _isLoading = false);
  }

  List<AdminNotificationItem> _applyFilters(List<AdminNotificationItem> all) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();

    return all.where((item) {
      // Category filter
      if (_activeCategory != NotificationCategory.all) {
        if (_activeCategory == NotificationCategory.user) {
          if (item.category != NotificationCategory.user &&
              item.category != NotificationCategory.photoProof &&
              item.category != NotificationCategory.system) {
            return false;
          }
        } else if (item.category != _activeCategory) {
          return false;
        }
      }

      // Unread only
      if (_unreadOnly && item.isRead) return false;

      // Status filter
      if (_selectedStatus != 'All') {
        final st = item.status.toLowerCase();
        if (_selectedStatus == 'Pending' && st != 'pending' && st != 'needs_admin_review') {
          return false;
        }
        if (_selectedStatus == 'Approved' && st != 'approved' && st != 'validated') {
          return false;
        }
        if (_selectedStatus == 'Rejected' && st != 'rejected') {
          return false;
        }
      }

      // Date range filter
      if (_selectedDateRange == 'Today') {
        if (item.createdAt.year != now.year ||
            item.createdAt.month != now.month ||
            item.createdAt.day != now.day) {
          return false;
        }
      } else if (_selectedDateRange == 'Last 7 Days') {
        if (now.difference(item.createdAt).inDays > 7) {
          return false;
        }
      } else if (_selectedDateRange == 'This Month') {
        if (item.createdAt.year != now.year ||
            item.createdAt.month != now.month) {
          return false;
        }
      }

      // Search query
      if (query.isNotEmpty) {
        final matchesTitle = item.title.toLowerCase().contains(query);
        final matchesMsg = item.message.toLowerCase().contains(query);
        final matchesActor = item.actorName.toLowerCase().contains(query);
        final matchesDept =
            item.actorDepartment?.toLowerCase().contains(query) ?? false;
        final matchesComp =
            item.actorCompany?.toLowerCase().contains(query) ?? false;
        if (!matchesTitle &&
            !matchesMsg &&
            !matchesActor &&
            !matchesDept &&
            !matchesComp) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _handleItemClick(AdminNotificationItem item) {
    AdminNotificationsService.markAsRead(item.id);

    Navigator.of(context).pop();

    if (item.category == NotificationCategory.esarf) {
      widget.onNavigateToRequests?.call(0);
    } else if (item.category == NotificationCategory.leave) {
      widget.onNavigateToRequests?.call(1);
    } else if (item.category == NotificationCategory.perk) {
      widget.onNavigateToRequests?.call(2);
    } else if (item.category == NotificationCategory.user) {
      widget.onNavigateToUsers?.call();
    } else if (item.category == NotificationCategory.photoProof) {
      widget.onNavigateToProofs?.call();
    } else {
      widget.onNavigateToRequests?.call(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: ValueListenableBuilder<List<AdminNotificationItem>>(
          valueListenable: AdminNotificationsService.notificationsNotifier,
          builder: (context, allNotifications, _) {
            final filtered = _applyFilters(allNotifications);

            // Compute statistics
            final totalCount = allNotifications.length;
            final pendingEsarf = allNotifications
                .where((n) =>
                    n.category == NotificationCategory.esarf &&
                    (n.status.toLowerCase() == 'pending' ||
                        n.status.toLowerCase() == 'needs_admin_review'))
                .length;
            final pendingLeave = allNotifications
                .where((n) =>
                    n.category == NotificationCategory.leave &&
                    (n.status.toLowerCase() == 'pending' ||
                        n.status.toLowerCase() == 'needs_admin_review'))
                .length;
            final pendingPerks = allNotifications
                .where((n) =>
                    n.category == NotificationCategory.perk &&
                    (n.status.toLowerCase() == 'pending' ||
                        n.status.toLowerCase() == 'needs_admin_review'))
                .length;
            final registeredUsers = allNotifications
                .where((n) => n.category == NotificationCategory.user)
                .length;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- HEADER ---
                  _buildHeader(context),
                  const SizedBox(height: 16),

                  // --- METRIC CARDS ---
                  _buildMetricCards(
                    total: totalCount,
                    pendingEsarf: pendingEsarf,
                    pendingLeave: pendingLeave,
                    pendingPerks: pendingPerks,
                    users: registeredUsers,
                  ),
                  const SizedBox(height: 16),

                  // --- SEARCH & FILTER BAR ---
                  _buildFilterBar(),
                  const SizedBox(height: 16),

                  // --- NOTIFICATION FEED LIST ---
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF2563EB),
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  return _buildActivityCard(filtered[index]);
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF334155),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFFD97706),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications & Activity Center',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Real-time feed of employee requests, account activities, and approvals',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => AdminNotificationsService.markAllAsRead(),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text('Mark All Read'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCards({
    required int total,
    required int pendingEsarf,
    required int pendingLeave,
    required int pendingPerks,
    required int users,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            label: 'Total Activity',
            count: total,
            color: const Color(0xFF475569),
            bgColor: const Color(0xFFF1F5F9),
            icon: Icons.notifications_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Pending ESARF',
            count: pendingEsarf,
            color: const Color(0xFFEA580C),
            bgColor: const Color(0xFFFFEDD5),
            icon: Icons.access_time_filled_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Pending Leaves',
            count: pendingLeave,
            color: const Color(0xFF0284C7),
            bgColor: const Color(0xFFE0F2FE),
            icon: Icons.event_available_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Pending Perks',
            count: pendingPerks,
            color: const Color(0xFF9333EA),
            bgColor: const Color(0xFFF3E8FF),
            icon: Icons.card_giftcard_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'New Users',
            count: users,
            color: const Color(0xFF0D9488),
            bgColor: const Color(0xFFCCFBF1),
            icon: Icons.person_add_alt_1_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
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

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search field
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by employee, department, keyword...',
                      hintStyle:
                          const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
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
              ),
              const SizedBox(width: 12),

              // Status Dropdown
              _buildDropdown(
                label: 'Status',
                value: _selectedStatus,
                items: const ['All', 'Pending', 'Approved', 'Rejected'],
                onChanged: (val) => setState(() => _selectedStatus = val!),
              ),
              const SizedBox(width: 10),

              // Date Range Dropdown
              _buildDropdown(
                label: 'Date',
                value: _selectedDateRange,
                items: const ['All Time', 'Today', 'Last 7 Days', 'This Month'],
                onChanged: (val) => setState(() => _selectedDateRange = val!),
              ),
              const SizedBox(width: 12),

              // Unread Only Checkbox
              InkWell(
                onTap: () => setState(() => _unreadOnly = !_unreadOnly),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _unreadOnly
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: _unreadOnly
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Unread only',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              _unreadOnly ? FontWeight.w700 : FontWeight.w500,
                          color: _unreadOnly
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // Category Tabs Row
          Row(
            children: [
              _buildCategoryPill('All Activity', NotificationCategory.all),
              const SizedBox(width: 8),
              _buildCategoryPill('ESARF Requests', NotificationCategory.esarf),
              const SizedBox(width: 8),
              _buildCategoryPill('Leave Requests', NotificationCategory.leave),
              const SizedBox(width: 8),
              _buildCategoryPill('Perks Requests', NotificationCategory.perk),
              const SizedBox(width: 8),
              _buildCategoryPill('Users & Accounts', NotificationCategory.user),
              const SizedBox(width: 8),
              _buildCategoryPill('Photo Proofs', NotificationCategory.photoProof),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: Color(0xFF64748B)),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
          items: items.map((e) {
            return DropdownMenuItem<String>(
              value: e,
              child: Text('$label: $e'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCategoryPill(String label, NotificationCategory cat) {
    final isSelected = _activeCategory == cat;
    return InkWell(
      onTap: () => setState(() => _activeCategory = cat),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard(AdminNotificationItem item) {
    final statusColor = _AdminNotificationsPopoverState._statusColor(item.status);
    final statusBg = _AdminNotificationsPopoverState._statusBgColor(item.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isRead ? HygColors.border : const Color(0xFFBFDBFE),
          width: item.isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: item.isRead ? 0.02 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar / Icon
          if (item.actorPhoto != null && item.actorPhoto!.isNotEmpty)
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE2E8F0),
              backgroundImage: NetworkImage(item.actorPhoto!),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.categoryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(item.categoryIcon, color: item.categoryColor, size: 22),
              ),
            ),
          const SizedBox(width: 16),

          // Main Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.categoryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.categoryLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: item.categoryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.actorName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (item.actorDepartment != null &&
                        item.actorDepartment!.isNotEmpty) ...[
                      const Text(' • ',
                          style: TextStyle(color: Color(0xFFCBD5E1))),
                      Text(
                        item.actorDepartment!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _AdminNotificationsPopoverState._formatStatus(item.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.timeAgo(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Action Button
          ElevatedButton.icon(
            onPressed: () => _handleItemClick(item),
            icon: const Icon(Icons.arrow_outward_rounded, size: 14),
            label: Text(_actionButtonLabel(item)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
              foregroundColor: const Color(0xFF0F172A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No notifications match your filter',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try resetting your search query, status, or date range filters.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  static String _actionButtonLabel(AdminNotificationItem item) {
    switch (item.category) {
      case NotificationCategory.esarf:
        return 'View ESARF';
      case NotificationCategory.leave:
        return 'View Leave';
      case NotificationCategory.perk:
        return 'View Perk';
      case NotificationCategory.user:
        return 'View User';
      case NotificationCategory.photoProof:
        return 'View Proof';
      default:
        return 'View Details';
    }
  }
}
