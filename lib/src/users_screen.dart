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
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.manage_accounts,
              color: HygColors.goldStrong,
            ),
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
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    required this.onCreateUser,
    super.key,
  });

  final List<RegisteredUserPreview> users;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(RegisteredUserPreview user, String appRole)
  onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays,
  )
  onSetLeaveCredits;
  final Future<void> Function(AddUserRequest request) onCreateUser;

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  static const _usersPerPage = 15;

  final _searchController = TextEditingController();
  var _query = '';
  var _currentPage = 0;

  int get _pageCount =>
      (_filteredUsers.length / _usersPerPage).ceil().clamp(1, 999999);

  List<RegisteredUserPreview> get _visibleUsers {
    final start = _currentPage * _usersPerPage;
    final end = math.min(start + _usersPerPage, _filteredUsers.length);
    return _filteredUsers.sublist(start, end);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= _pageCount) {
      _currentPage = _pageCount - 1;
    }
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
    final request = await showDialog<AddUserRequest>(
      context: context,
      builder: (context) => const AddUserDialog(),
    );
    if (request == null) return;
    await widget.onCreateUser(request);
  }

  void _goToPage(int page) {
    final nextPage = page.clamp(0, _pageCount - 1);
    if (nextPage == _currentPage) {
      return;
    }
    setState(() => _currentPage = nextPage);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _currentPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
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
                onSetBan: widget.onSetBan,
                onSetRole: widget.onSetRole,
                onResetPassword: widget.onResetPassword,
                onSetLeaveCredits: widget.onSetLeaveCredits,
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
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    super.key,
  });

  final RegisteredUserPreview user;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(RegisteredUserPreview user, String appRole)
  onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays,
  )
  onSetLeaveCredits;

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
        constraints: const BoxConstraints(minHeight: 76),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: rowColor,
          border: const Border(bottom: BorderSide(color: HygColors.border)),
          borderRadius: BorderRadius.circular(8),
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
            Expanded(flex: 2, child: BodyCell(_leaveCreditLabel(widget.user))),
            Expanded(flex: 2, child: BodyCell(widget.user.registeredAt)),
            Expanded(flex: 2, child: BodyCell(widget.user.lastSignInAt)),
            SizedBox(
              width: 52,
              child: UserActionsMenu(
                user: widget.user,
                isActive: _isHovered || _isMenuOpen,
                onMenuOpenChanged: (value) {
                  if (mounted) setState(() => _isMenuOpen = value);
                },
                onSetBan: widget.onSetBan,
                onSetRole: widget.onSetRole,
                onResetPassword: widget.onResetPassword,
                onSetLeaveCredits: widget.onSetLeaveCredits,
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
    return ClipOval(
      child: Container(
        width: 40,
        height: 40,
        color: const Color(0xFFFEF3C7),
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
    required this.isActive,
    required this.onMenuOpenChanged,
    required this.onSetBan,
    required this.onSetRole,
    required this.onResetPassword,
    required this.onSetLeaveCredits,
    super.key,
  });

  final RegisteredUserPreview user;
  final bool isActive;
  final ValueChanged<bool> onMenuOpenChanged;
  final Future<void> Function(RegisteredUserPreview user, bool isBanned)
  onSetBan;
  final Future<void> Function(RegisteredUserPreview user, String appRole)
  onSetRole;
  final Future<void> Function(RegisteredUserPreview user, String newPassword)
  onResetPassword;
  final Future<void> Function(
    RegisteredUserPreview user,
    double annualCreditDays,
  )
  onSetLeaveCredits;

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
      final role = await showDialog<String>(
        context: context,
        builder: (context) => UserRoleDialog(user: widget.user),
      );
      if (role != null) {
        await widget.onSetRole(widget.user, role);
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
      final credits = await showDialog<double>(
        context: context,
        builder: (context) => UserLeaveCreditsDialog(user: widget.user),
      );
      if (credits != null) {
        await widget.onSetLeaveCredits(widget.user, credits);
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
  const _UserActionMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Icon(icon, color: const Color(0xFF475569), size: 22),
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
  });

  final String username;
  final String email;
  final String password;
  final String appRole;
}

class AddUserDialog extends StatefulWidget {
  const AddUserDialog({super.key});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  var _role = 'employee';
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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

    Navigator.of(context).pop(
      AddUserRequest(
        username: username,
        email: email,
        password: password,
        appRole: _role,
      ),
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
        constraints: const BoxConstraints(maxWidth: 520),
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
                        Icons.person_add_alt_1_outlined,
                        color: Color(0xFF8A5A00),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add User',
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
                  'Create a login account without linking an employee profile.',
                  style: HygTypography.body.copyWith(
                    color: HygColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This user will appear as no linked employee until assigned later.',
                  style: HygTypography.body.copyWith(
                    color: const Color(0xFF7A6320),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 16),
                ModalTextField(
                  controller: _usernameController,
                  label: 'Username',
                  required: true,
                ),
                const SizedBox(height: 12),
                ModalTextField(
                  controller: _emailController,
                  label: 'Email',
                  required: true,
                ),
                const SizedBox(height: 12),
                ModalTextField(
                  controller: _passwordController,
                  label: 'Password',
                  required: true,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                ModalTextField(
                  controller: _confirmController,
                  label: 'Confirm Password',
                  required: true,
                  obscureText: true,
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
                        onSelected: (_) => setState(() => _role = role),
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
                        label: const Text('Add'),
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

class UserRoleDialog extends StatefulWidget {
  const UserRoleDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  State<UserRoleDialog> createState() => _UserRoleDialogState();
}

class _UserRoleDialogState extends State<UserRoleDialog> {
  late String _role = widget.user.appRole.toLowerCase();

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
                      onSelected: (_) => setState(() => _role = role),
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
                      onPressed: () => Navigator.of(context).pop(_role),
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

class UserPasswordDialog extends StatefulWidget {
  const UserPasswordDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  State<UserPasswordDialog> createState() => _UserPasswordDialogState();
}

class _UserPasswordDialogState extends State<UserPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
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
                obscureText: true,
              ),
              const SizedBox(height: 12),
              ModalTextField(
                controller: _confirmController,
                label: 'Confirm Password',
                required: true,
                obscureText: true,
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

class UserLeaveCreditsDialog extends StatefulWidget {
  const UserLeaveCreditsDialog({required this.user, super.key});

  final RegisteredUserPreview user;

  @override
  State<UserLeaveCreditsDialog> createState() => _UserLeaveCreditsDialogState();
}

class _UserLeaveCreditsDialogState extends State<UserLeaveCreditsDialog> {
  late final TextEditingController _creditsController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _creditsController = TextEditingController(
      text: _formatInitialValue(widget.user.leaveCreditDays ?? 7),
    );
  }

  @override
  void dispose() {
    _creditsController.dispose();
    super.dispose();
  }

  void _submit() {
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
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final usedDays = widget.user.leaveUsedDays ?? 0;
    final remainingDays = widget.user.leaveRemainingDays ?? 0;
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
                'Used: ${_formatDays(usedDays)}  •  Remaining: ${_formatDays(remainingDays)}',
                style: HygTypography.tableBody.copyWith(color: HygColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _creditsController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Annual leave credits',
                  hintText: 'Example: 7',
                  errorText: _error,
                  suffixText: 'days',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HygColors.gold,
                      foregroundColor: HygColors.ink,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Credits'),
                  ),
                ],
              ),
            ],
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
