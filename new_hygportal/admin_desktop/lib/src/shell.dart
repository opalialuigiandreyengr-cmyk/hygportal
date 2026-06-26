part of '../main.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({required this.session, required this.onSignOut, super.key});

  final AdminLoginSession session;
  final VoidCallback onSignOut;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with WidgetsBindingObserver {
  static const Duration _directoryAutoRefreshInterval = Duration(seconds: 10);
  late HrSection _activeSection;
  var _allRequests = <AdminRequestItem>[];
  String? _requestsError;
  bool _isLoadingRequests = false;
  var _employees = <EmployeePreview>[];
  var _companies = <CompanyPreview>[];
  var _departments = <DepartmentPreview>[];
  var _stores = <StorePreview>[];
  var _clusters = <ClusterPreview>[];
  var _areas = <AreaPreview>[];
  var _authorityCandidates = <AuthorityCandidatePreview>[];
  var _storeRouteScopes = <StoreRouteScopePreview>[];
  var _adminPositionLevels = <AdminPositionAuthorityPreview>[];
  var _departmentLadders = <DepartmentLadderPreview>[];
  var _positions = <PositionPreview>[];
  var _departmentPositionCatalog = <DepartmentPositionCatalogPreview>[];
  var _positionCatalog = <AdminPositionCatalogPreview>[];
  var _registeredUsers = <RegisteredUserPreview>[];
  String? _employeeError;
  String? _companyError;
  String? _departmentError;
  String? _storeError;
  String? _clusterError;
  String? _areaError;
  String? _adminWorkflowError;
  String? _positionError;
  String? _usersError;
  bool _isLoadingEmployees = false;
  bool _isLoadingCompanies = false;
  bool _isLoadingDepartments = false;
  bool _isLoadingStores = false;
  bool _isLoadingClusters = false;
  bool _isLoadingAreas = false;
  bool _isLoadingAdminWorkflow = false;
  bool _isLoadingPositions = false;
  bool _isLoadingUsers = false;
  Timer? _directoryRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final canAccessRequests = widget.session.canManageAdminSettings ||
        widget.session.appRole.toLowerCase() == 'hr';
    _activeSection = canAccessRequests
        ? HrSection.requests
        : HrSection.employees;
    if (canAccessRequests) {
      _loadAllRequests();
    } else {
      _loadEmployees();
    }
    _directoryRefreshTimer = Timer.periodic(_directoryAutoRefreshInterval, (_) {
      if (!mounted) {
        return;
      }
      if (_activeSection == HrSection.employees && !_isLoadingEmployees) {
        unawaited(_loadEmployees(silent: true));
      } else if (_activeSection == HrSection.users && !_isLoadingUsers) {
        unawaited(_loadUsers(silent: true));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _directoryRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (_activeSection == HrSection.employees ||
            _activeSection == HrSection.users)) {
      if (_activeSection == HrSection.employees) {
        unawaited(_loadEmployees(silent: true));
      } else {
        unawaited(_loadUsers(silent: true));
      }
    }
  }

  Future<void> _loadAllRequests() async {
    setState(() {
      _isLoadingRequests = _allRequests.isEmpty;
      _requestsError = null;
    });
    try {
      final items = await AdminRequestsService.loadAllRequests();
      if (!mounted) return;
      setState(() {
        _allRequests = items;
        _isLoadingRequests = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requestsError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingRequests = false;
      });
    }
  }

  Future<void> _loadEmployees({bool silent = false}) async {
    setState(() {
      if (!silent) {
        _isLoadingEmployees = _employees.isEmpty;
      }
      _employeeError = null;
    });

    try {
      final employees = await EmployeeDirectoryService.loadEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        if (!silent) {
          _isLoadingEmployees = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _employeeError = error.toString().replaceFirst('Exception: ', '');
        if (!silent) {
          _isLoadingEmployees = false;
        }
      });
    }
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _isLoadingCompanies = _companies.isEmpty;
      _companyError = null;
    });

    try {
      final companies = await CompanyDirectoryService.loadCompanies();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _isLoadingCompanies = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _companyError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingCompanies = false;
      });
    }
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _isLoadingDepartments = _departments.isEmpty;
      _departmentError = null;
    });

    try {
      final results = await Future.wait([
        DepartmentDirectoryService.loadDepartments(),
        DepartmentPositionCatalogService.loadDepartmentPositionCatalog(),
        DepartmentPositionCatalogService.loadPositionCatalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _departments = results[0] as List<DepartmentPreview>;
        _departmentPositionCatalog =
            results[1] as List<DepartmentPositionCatalogPreview>;
        _positionCatalog = results[2] as List<AdminPositionCatalogPreview>;
        _isLoadingDepartments = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _departmentError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingDepartments = false;
      });
    }
  }

  Future<void> _loadPositions() async {
    setState(() {
      _isLoadingPositions = _positions.isEmpty;
      _positionError = null;
    });

    try {
      final positions = await PositionDirectoryService.loadPositions();
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _isLoadingPositions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _positionError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingPositions = false;
      });
    }
  }

  Future<void> _loadUsers({bool silent = false}) async {
    setState(() {
      if (!silent) {
        _isLoadingUsers = _registeredUsers.isEmpty;
      }
      _usersError = null;
    });

    try {
      final users = await RegisteredUsersService.loadUsers();
      if (!mounted) return;
      setState(() {
        _registeredUsers = users;
        if (!silent) {
          _isLoadingUsers = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _usersError = error.toString().replaceFirst('Exception: ', '');
        if (!silent) {
          _isLoadingUsers = false;
        }
      });
    }
  }

  Future<void> _setUserBan(RegisteredUserPreview user, bool isBanned) async {
    try {
      await RegisteredUsersService.setUserBan(
        userProfileId: user.userProfileId,
        isBanned: isBanned,
      );
      await _loadUsers();
      _showDepartmentMessage(
        isBanned ? 'User banned successfully.' : 'User unbanned successfully.',
      );
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _setUserRole(RegisteredUserPreview user, String appRole) async {
    try {
      await RegisteredUsersService.setUserRole(
        userProfileId: user.userProfileId,
        appRole: appRole,
      );
      await _loadUsers();
      _showDepartmentMessage('User role updated successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _resetUserPassword(
    RegisteredUserPreview user,
    String newPassword,
  ) async {
    try {
      await RegisteredUsersService.resetUserPassword(
        userProfileId: user.userProfileId,
        newPassword: newPassword,
      );
      await _loadUsers();
      _showDepartmentMessage('User password updated successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _setUserLeaveCredits(
    RegisteredUserPreview user,
    double annualCreditDays,
  ) async {
    try {
      await RegisteredUsersService.setLeaveCredits(
        userProfileId: user.userProfileId,
        annualCreditDays: annualCreditDays,
      );
      await _loadUsers();
      _showDepartmentMessage('Leave credits updated successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _createUnlinkedUser(AddUserRequest request) async {
    try {
      await RegisteredUsersService.createUnlinkedUser(
        username: request.username,
        email: request.email,
        password: request.password,
        appRole: request.appRole,
      );
      await _loadUsers();
      _showDepartmentMessage('User created successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _assignDepartmentPosition(
    DepartmentPreview department,
    AdminPositionCatalogPreview position,
  ) async {
    try {
      await DepartmentPositionCatalogService.assignDepartmentPosition(
        departmentId: department.id,
        positionId: position.positionId,
      );
      if (!mounted) return;
      final authorityLevel = _adminPositionLevels
          .where((item) => item.positionId == position.positionId)
          .map((item) => item.authorityLevel)
          .whereType<int>()
          .firstOrNull;
      setState(() {
        final exists = _departmentPositionCatalog.any(
          (item) =>
              item.departmentId == department.id &&
              item.positionId == position.positionId,
        );
        if (!exists) {
          _departmentPositionCatalog =
              [
                ..._departmentPositionCatalog,
                DepartmentPositionCatalogPreview(
                  departmentId: department.id,
                  departmentName: department.name,
                  positionId: position.positionId,
                  positionName: position.positionName,
                  authorityLevel: authorityLevel,
                  employeeCount: 0,
                ),
              ]..sort((a, b) {
                final departmentCompare = a.departmentName.compareTo(
                  b.departmentName,
                );
                if (departmentCompare != 0) return departmentCompare;
                return (a.positionName ?? '').compareTo(b.positionName ?? '');
              });
        }
      });
      _showDepartmentMessage('Position assigned successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _removeDepartmentPosition(
    DepartmentPreview department,
    AdminPositionCatalogPreview position,
  ) async {
    try {
      await DepartmentPositionCatalogService.removeDepartmentPosition(
        departmentId: department.id,
        positionId: position.positionId,
      );
      if (!mounted) return;
      setState(() {
        _departmentPositionCatalog = _departmentPositionCatalog
            .where(
              (item) =>
                  item.departmentId != department.id ||
                  item.positionId != position.positionId,
            )
            .toList();
      });
      _showDepartmentMessage('Position removed successfully.');
    } catch (error) {
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _loadStores() async {
    setState(() {
      _isLoadingStores = _stores.isEmpty;
      _storeError = null;
    });
    try {
      final stores = await StoreDirectoryService.loadStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _isLoadingStores = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storeError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingStores = false;
      });
    }
  }

  Future<void> _loadClusters() async {
    setState(() {
      _isLoadingClusters = _clusters.isEmpty;
      _clusterError = null;
    });
    try {
      final clusters = await ClusterDirectoryService.loadClusters();
      if (!mounted) return;
      setState(() {
        _clusters = clusters;
        _isLoadingClusters = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clusterError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingClusters = false;
      });
    }
  }

  Future<void> _loadAreas() async {
    setState(() {
      _isLoadingAreas = _areas.isEmpty;
      _areaError = null;
    });
    try {
      final areas = await AreaDirectoryService.loadAreas();
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _isLoadingAreas = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _areaError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingAreas = false;
      });
    }
  }

  Future<void> _loadAdminWorkflow() async {
    setState(() {
      _isLoadingAdminWorkflow =
          _authorityCandidates.isEmpty &&
          _adminPositionLevels.isEmpty &&
          _departmentLadders.isEmpty;
      _adminWorkflowError = null;
    });
    try {
      final candidates = await AdminWorkflowService.loadAuthorityCandidates();
      final storeRouteScopes =
          await AdminWorkflowService.loadStoreRouteScopes();
      final positions =
          await AdminWorkflowService.loadPositionAuthorityLevels();
      final ladders =
          await AdminWorkflowService.loadDepartmentApprovalLadders();
      final departmentPositions =
          await DepartmentPositionCatalogService.loadDepartmentPositionCatalog();
      final clusters = await ClusterDirectoryService.loadClusters();
      final areas = await AreaDirectoryService.loadAreas();
      if (!mounted) return;
      setState(() {
        _authorityCandidates = candidates;
        _storeRouteScopes = storeRouteScopes;
        _adminPositionLevels = positions;
        _departmentLadders = ladders;
        _departmentPositionCatalog = departmentPositions;
        _clusters = clusters;
        _areas = areas;
        _isLoadingAdminWorkflow = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminWorkflowError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingAdminWorkflow = false;
      });
    }
  }

  void _selectSection(HrSection section) {
    if (!widget.session.canManageAdminSettings &&
        {
          HrSection.approvalRoutes,
          HrSection.authorityLevels,
          HrSection.approverAssignments,
          HrSection.users,
          HrSection.departments,
        }.contains(section)) {
      section = HrSection.employees;
    }

    setState(() => _activeSection = section);
    if (section == HrSection.requests) {
      unawaited(_loadAllRequests());
    }
    if (section == HrSection.employees) {
      unawaited(_loadEmployees(silent: true));
    }
    if (section == HrSection.users) {
      unawaited(_loadUsers(silent: true));
    }
    if ({
          HrSection.approverAssignments,
          HrSection.authorityLevels,
          HrSection.approvalRoutes,
        }.contains(section) &&
        !_isLoadingAdminWorkflow &&
        _authorityCandidates.isEmpty &&
        _adminWorkflowError == null) {
      _loadAdminWorkflow();
    }
    if (section == HrSection.companies &&
        !_isLoadingCompanies &&
        _companies.isEmpty &&
        _companyError == null) {
      _loadCompanies();
    }
    if (section == HrSection.departments &&
        !_isLoadingDepartments &&
        _departments.isEmpty &&
        _departmentError == null) {
      _loadDepartments();
    }
    if (section == HrSection.positions &&
        !_isLoadingPositions &&
        _positions.isEmpty &&
        _positionError == null) {
      _loadPositions();
    }
    if (section == HrSection.stores && !_isLoadingStores) {
      _loadStores();
    }
    if (section == HrSection.clusters &&
        !_isLoadingClusters &&
        _clusters.isEmpty &&
        _clusterError == null) {
      _loadClusters();
    }
    if (section == HrSection.clusters &&
        !_isLoadingAreas &&
        _areas.isEmpty &&
        _areaError == null) {
      _loadAreas();
    }
  }

  Future<void> _openAddEmployeeModal() async {
    final created = await _openEmployeeProfileModal(
      const AddEmployeeProfileModal(),
    );
    if (created == true) {
      await _loadEmployees();
      _showDepartmentMessage('Employee created successfully.');
    }
  }

  Future<void> _openEditEmployeeModal(EmployeePreview employee) async {
    final updated = await _openEmployeeProfileModal(
      AddEmployeeProfileModal(employee: employee),
    );
    if (updated == true) {
      await _loadEmployees();
      _showDepartmentMessage('Employee updated successfully.');
    }
  }

  Future<void> _confirmDeleteEmployee(EmployeePreview employee) async {
    final mode = await showDialog<EmployeeDeleteMode>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmployeeDeleteDialog(employee: employee),
    );

    if (mode == null) {
      return;
    }

    try {
      await EmployeeDirectoryService.deleteEmployee(
        id: employee.id,
        mode: mode,
      );
      await _loadEmployees();
      _showDepartmentMessage(
        mode == EmployeeDeleteMode.soft
            ? 'Employee set to inactive successfully.'
            : 'Employee and related data deleted permanently.',
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      _showDepartmentMessage(
        message.contains('hr_delete_employee') || message.contains('PGRST202')
            ? 'Employee delete function is missing. Apply migration 0069_hr_employee_delete.sql, then retry.'
            : message,
        isError: true,
      );
    }
  }

  Future<bool?> _openEmployeeProfileModal(Widget modal) {
    return Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        fullscreenDialog: true,
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) => modal,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 170),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAddCompanyModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddCompanyDialog(),
    );

    if (created == true) {
      await _loadCompanies();
    }
  }

  Future<void> _confirmDeleteCompany(CompanyPreview company) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CompanyDeleteDialog(company: company),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await CompanyDirectoryService.deleteCompany(company.id);
      await _loadCompanies();
      _showDepartmentMessage('Company deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(_companyErrorMessage(error), isError: true);
    }
  }

  Future<void> _openAddDepartmentModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddDepartmentDialog(),
    );

    if (created == true) {
      await _loadDepartments();
      _showDepartmentMessage('Department created successfully.');
    }
  }

  Future<void> _openAddPositionModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddPositionDialog(),
    );

    if (created == true) {
      await _loadPositions();
      _showDepartmentMessage('Position created successfully.');
    }
  }

  Future<void> _openAddStoreModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddStoreDialog(),
    );
    if (created == true) {
      await _loadStores();
      _showDepartmentMessage('Store created successfully.');
    }
  }

  Future<void> _openAddClusterModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddClusterDialog(),
    );
    if (created == true) {
      await _loadClusters();
      await _loadAreas();
      await _loadStores();
      _showDepartmentMessage('Cluster created successfully.');
    }
  }

  Future<void> _openAddAreaModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddAreaDialog(),
    );
    if (created == true) {
      await _loadAreas();
      await _loadClusters();
      await _loadStores();
      _showDepartmentMessage('Area created successfully.');
    }
  }

  Future<void> _openEditClusterModal(ClusterPreview cluster) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddClusterDialog(cluster: cluster),
    );
    if (updated == true) {
      await _loadClusters();
      await _loadAreas();
      await _loadStores();
      _showDepartmentMessage('Cluster updated successfully.');
    }
  }

  Future<void> _openEditAreaModal(AreaPreview area) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddAreaDialog(area: area),
    );
    if (updated == true) {
      await _loadAreas();
      await _loadClusters();
      await _loadStores();
      _showDepartmentMessage('Area updated successfully.');
    }
  }

  Future<void> _confirmDeleteCluster(ClusterPreview cluster) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete cluster?'),
        content: Text(
          'Delete "${cluster.name}"? Clusters referenced by stores or approvals cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Cluster'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ClusterDirectoryService.deleteCluster(cluster.id);
      await _loadClusters();
      await _loadAreas();
      await _loadStores();
      _showDepartmentMessage('Cluster deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _confirmDeleteArea(AreaPreview area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete area?'),
        content: Text(
          'Delete "${area.name}"? Its clusters will move back to the default area.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Area'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AreaDirectoryService.deleteArea(area.id);
      await _loadAreas();
      await _loadClusters();
      await _loadStores();
      _showDepartmentMessage('Area deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _openEditStoreModal(StorePreview store) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddStoreDialog(store: store),
    );
    if (updated == true) {
      await _loadStores();
      _showDepartmentMessage('Store updated successfully.');
    }
  }

  Future<void> _confirmDeleteStore(StorePreview store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete store?'),
        content: Text(
          'Delete "${store.name}"? Stores referenced by employees or requests cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Store'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StoreDirectoryService.deleteStore(store.id);
      await _loadStores();
      _showDepartmentMessage('Store deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _openEditDepartmentModal(DepartmentPreview department) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddDepartmentDialog(department: department),
    );

    if (updated == true) {
      await _loadDepartments();
      _showDepartmentMessage('Department updated successfully.');
    }
  }

  Future<void> _confirmDeleteDepartment(DepartmentPreview department) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DepartmentDeleteDialog(department: department),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await DepartmentDirectoryService.deleteDepartment(department.id);
      await _loadDepartments();
      _showDepartmentMessage('Department deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(_departmentErrorMessage(error), isError: true);
    }
  }

  Future<void> _openEditPositionModal(PositionPreview position) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddPositionDialog(position: position),
    );

    if (updated == true) {
      await _loadPositions();
      _showDepartmentMessage('Position updated successfully.');
    }
  }

  Future<void> _confirmDeletePosition(PositionPreview position) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PositionDeleteDialog(position: position),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await PositionDirectoryService.deletePosition(position.id);
      await _loadPositions();
      _showDepartmentMessage('Position deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(_positionErrorMessage(error), isError: true);
    }
  }

  Future<void> _setAuthorityLevel(
    AuthorityCandidatePreview candidate,
    int level, {
    String? clusterId,
    String? areaId,
  }) async {
    try {
      await AdminWorkflowService.setAuthorityAssignment(
        employeeId: candidate.employeeId,
        functionId: candidate.functionId,
        authorityLevel: level,
        clusterId: clusterId,
        areaId: areaId,
      );
      if (!mounted) return;
      final selectedClusterName = clusterId == null
          ? null
          : _clusters
                .where((cluster) => cluster.id == clusterId)
                .map((cluster) => cluster.name)
                .firstOrNull;
      final selectedAreaName = areaId == null
          ? null
          : _areas
                .where((area) => area.id == areaId)
                .map((area) => area.name)
                .firstOrNull;
      setState(() {
        _authorityCandidates = _authorityCandidates.map((item) {
          if (item.employeeId != candidate.employeeId ||
              item.functionId != candidate.functionId) {
            return item;
          }
          return AuthorityCandidatePreview(
            employeeId: item.employeeId,
            employeeNo: item.employeeNo,
            fullName: item.fullName,
            positionId: item.positionId,
            positionName: item.positionName,
            positionLevel: item.positionLevel,
            functionId: item.functionId,
            functionName: item.functionName,
            areaId: areaId ?? item.areaId,
            areaName: selectedAreaName ?? item.areaName,
            clusterId: clusterId ?? item.clusterId,
            clusterName: selectedClusterName ?? item.clusterName,
            storeId: item.storeId,
            storeName: item.storeName,
            companyName: item.companyName,
            departmentId: item.departmentId,
            departmentName: item.departmentName,
            currentAuthorityLevel: level,
          );
        }).toList();
      });
      _showDepartmentMessage('Approver level updated successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _setPositionAuthorityLevel(
    AdminPositionAuthorityPreview position,
    int level,
  ) async {
    try {
      await AdminWorkflowService.setPositionAuthorityLevel(
        positionId: position.positionId,
        authorityLevel: level,
      );
      if (!mounted) return;
      setState(() {
        _adminPositionLevels = _adminPositionLevels.map((item) {
          if (item.positionId != position.positionId) return item;
          return AdminPositionAuthorityPreview(
            positionId: item.positionId,
            positionName: item.positionName,
            authorityLevel: level,
            employeeCount: item.employeeCount,
          );
        }).toList();
        _departmentPositionCatalog = _departmentPositionCatalog.map((item) {
          if (item.positionId != position.positionId) return item;
          return DepartmentPositionCatalogPreview(
            departmentId: item.departmentId,
            departmentName: item.departmentName,
            positionId: item.positionId,
            positionName: item.positionName,
            authorityLevel: level,
            employeeCount: item.employeeCount,
          );
        }).toList();
      });
      _showDepartmentMessage('Position level updated successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _clearPositionAuthorityLevel(
    AdminPositionAuthorityPreview position,
  ) async {
    try {
      await AdminWorkflowService.clearPositionAuthorityLevel(
        position.positionId,
      );
      if (!mounted) return;
      setState(() {
        _adminPositionLevels = _adminPositionLevels.map((item) {
          if (item.positionId != position.positionId) return item;
          return AdminPositionAuthorityPreview(
            positionId: item.positionId,
            positionName: item.positionName,
            authorityLevel: 1,
            employeeCount: item.employeeCount,
          );
        }).toList();
        _departmentPositionCatalog = _departmentPositionCatalog.map((item) {
          if (item.positionId != position.positionId) return item;
          return DepartmentPositionCatalogPreview(
            departmentId: item.departmentId,
            departmentName: item.departmentName,
            positionId: item.positionId,
            positionName: item.positionName,
            authorityLevel: 1,
            employeeCount: item.employeeCount,
          );
        }).toList();
      });
      _showDepartmentMessage('Position level cleared successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _setDepartmentApprovalLadder(
    DepartmentLadderPreview ladder,
    DepartmentLadderUpdate update,
  ) async {
    try {
      await AdminWorkflowService.setDepartmentApprovalLadder(
        departmentId: ladder.departmentId,
        levels: update.levels,
        roles: update.roles,
      );
      if (!mounted) return;
      setState(() {
        _departmentLadders = _departmentLadders.map((item) {
          if (item.departmentId != ladder.departmentId) return item;
          return DepartmentLadderPreview(
            departmentId: item.departmentId,
            departmentName: item.departmentName,
            routeLevels: update.levels,
            routeRoles: {
              for (final entry in update.roles.entries)
                entry.key: DepartmentRouteRole(
                  positionId: entry.value,
                  positionName:
                      _departmentPositionCatalog
                          .where(
                            (position) =>
                                position.departmentId == item.departmentId &&
                                position.positionId == entry.value,
                          )
                          .map((position) => position.positionName)
                          .whereType<String>()
                          .firstOrNull ??
                      item.routeRoles[entry.key]?.positionName ??
                      'SELECTED ROLE',
                ),
            },
          );
        }).toList();
      });
      _showDepartmentMessage('Department route updated successfully.');
    } catch (error) {
      if (!mounted) return;
      _showDepartmentMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _showDepartmentMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 620,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: isError
              ? const Color(0xFFB91C1C)
              : const Color(0xFF166534),
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  String _departmentErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');

    if (message.contains('PGRST202') ||
        message.contains('hr_delete_department')) {
      return 'Department delete is not installed yet. Run the latest 0049 SQL, then retry.';
    }

    if (message.contains('employee references') ||
        message.contains('23503') ||
        message.contains('foreign key constraint')) {
      return 'This department is still in use and cannot be deleted.';
    }

    return message;
  }

  String _positionErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');

    if (message.contains('PGRST202') ||
        message.contains('hr_delete_position')) {
      return 'Position delete is not installed yet. Run the latest position SQL, then retry.';
    }

    if (message.contains('references') ||
        message.contains('23503') ||
        message.contains('foreign key constraint')) {
      return 'This position is still in use and cannot be deleted.';
    }

    return message;
  }

  String _companyErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');

    if (message.contains('PGRST202') || message.contains('hr_delete_company')) {
      return 'Company delete is not installed yet. Run the latest company SQL, then retry.';
    }

    if (message.contains('references') ||
        message.contains('23503') ||
        message.contains('foreign key constraint')) {
      return 'This company is still in use and cannot be deleted.';
    }

    return message;
  }

  void _openHygAssistScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HygAssistScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HygColors.background,
      body: Row(
        children: [
          HrSidebar(
            activeSection: _activeSection,
            session: widget.session,
            onSelectSection: _selectSection,
            onSignOut: widget.onSignOut,
          ),
          Expanded(
            child: Column(
              children: [
                HrTopBar(onOpenAssist: _openHygAssistScreen),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_activeSection == HrSection.requests) ...[
                          RequestsHeader(onRefresh: _loadAllRequests),
                          const SizedBox(height: 14),
                          RequestsPanel(
                            requests: _allRequests,
                            isLoading: _isLoadingRequests,
                            error: _requestsError,
                            onRefresh: _loadAllRequests,
                            showDeleteAction: widget.session.appRole.toLowerCase() != 'hr',
                            onDeleteRequest: (String id, bool isPerk) async =>
                                await AdminRequestsService.deleteRequest(
                                    requestId: id, isPerk: isPerk),
                          ),
                        ] else if (_activeSection ==
                            HrSection.approverAssignments) ...[
                          const AdminWorkflowHeader(
                            title: 'Approver Assignments',
                            subtitle:
                                'Assign employees to approval authority levels.',
                            icon: Icons.verified_user_outlined,
                          ),
                          const SizedBox(height: 14),
                          AdminWorkflowPanel(
                            view: AdminWorkflowView.approverAssignments,
                            candidates: _authorityCandidates,
                            storeRouteScopes: _storeRouteScopes,
                            clusters: _clusters,
                            areas: _areas,
                            positions: _adminPositionLevels,
                            departmentPositions: _departmentPositionCatalog,
                            ladders: _departmentLadders,
                            isLoading: _isLoadingAdminWorkflow,
                            error: _adminWorkflowError,
                            onRefresh: _loadAdminWorkflow,
                            onSetAuthority: _setAuthorityLevel,
                            onSetPositionLevel: _setPositionAuthorityLevel,
                            onClearPositionLevel: _clearPositionAuthorityLevel,
                            onSetDepartmentLadder: _setDepartmentApprovalLadder,
                          ),
                        ] else if (_activeSection ==
                            HrSection.authorityLevels) ...[
                          const AdminWorkflowHeader(
                            title: 'Authority Levels',
                            subtitle:
                                'Set the authority level for each position.',
                            icon: Icons.badge_outlined,
                          ),
                          const SizedBox(height: 14),
                          AdminWorkflowPanel(
                            view: AdminWorkflowView.authorityLevels,
                            candidates: _authorityCandidates,
                            storeRouteScopes: _storeRouteScopes,
                            clusters: _clusters,
                            areas: _areas,
                            positions: _adminPositionLevels,
                            departmentPositions: _departmentPositionCatalog,
                            ladders: _departmentLadders,
                            isLoading: _isLoadingAdminWorkflow,
                            error: _adminWorkflowError,
                            onRefresh: _loadAdminWorkflow,
                            onSetAuthority: _setAuthorityLevel,
                            onSetPositionLevel: _setPositionAuthorityLevel,
                            onClearPositionLevel: _clearPositionAuthorityLevel,
                            onSetDepartmentLadder: _setDepartmentApprovalLadder,
                          ),
                        ] else if (_activeSection ==
                            HrSection.approvalRoutes) ...[
                          const AdminWorkflowHeader(
                            title: 'Approval Routes',
                            subtitle:
                                'Configure department approval ladders by level.',
                            icon: Icons.route_outlined,
                          ),
                          const SizedBox(height: 14),
                          AdminWorkflowPanel(
                            view: AdminWorkflowView.approvalRoutes,
                            candidates: _authorityCandidates,
                            storeRouteScopes: _storeRouteScopes,
                            clusters: _clusters,
                            areas: _areas,
                            positions: _adminPositionLevels,
                            departmentPositions: _departmentPositionCatalog,
                            ladders: _departmentLadders,
                            isLoading: _isLoadingAdminWorkflow,
                            error: _adminWorkflowError,
                            onRefresh: _loadAdminWorkflow,
                            onSetAuthority: _setAuthorityLevel,
                            onSetPositionLevel: _setPositionAuthorityLevel,
                            onClearPositionLevel: _clearPositionAuthorityLevel,
                            onSetDepartmentLadder: _setDepartmentApprovalLadder,
                          ),
                        ] else if (_activeSection == HrSection.employees) ...[
                          EmployeesHeader(onAddEmployee: _openAddEmployeeModal),
                          const SizedBox(height: 14),
                          EmployeesPanel(
                            employees: _employees,
                            isLoading: _isLoadingEmployees,
                            error: _employeeError,
                            onRefresh: _loadEmployees,
                            onEditEmployee: _openEditEmployeeModal,
                            onDeleteEmployee: _confirmDeleteEmployee,
                          ),
                        ] else if (_activeSection == HrSection.companies) ...[
                          CompaniesHeader(onAddCompany: _openAddCompanyModal),
                          const SizedBox(height: 14),
                          CompaniesPanel(
                            companies: _companies,
                            isLoading: _isLoadingCompanies,
                            error: _companyError,
                            onRefresh: _loadCompanies,
                            onDeleteCompany: _confirmDeleteCompany,
                          ),
                        ] else if (_activeSection == HrSection.users) ...[
                          const UsersHeader(),
                          const SizedBox(height: 14),
                          UsersPanel(
                            users: _registeredUsers,
                            isLoading: _isLoadingUsers,
                            error: _usersError,
                            onRefresh: _loadUsers,
                            onSetBan: _setUserBan,
                            onSetRole: _setUserRole,
                            onResetPassword: _resetUserPassword,
                            onSetLeaveCredits: _setUserLeaveCredits,
                            onCreateUser: _createUnlinkedUser,
                          ),
                        ] else if (_activeSection == HrSection.departments) ...[
                          DepartmentsHeader(
                            onAddDepartment: _openAddDepartmentModal,
                          ),
                          const SizedBox(height: 14),
                          DepartmentsPanel(
                            departments: _departments,
                            departmentPositions: _departmentPositionCatalog,
                            positions: _positionCatalog,
                            isLoading: _isLoadingDepartments,
                            error: _departmentError,
                            onRefresh: _loadDepartments,
                            onEditDepartment: _openEditDepartmentModal,
                            onDeleteDepartment: _confirmDeleteDepartment,
                            onAssignPosition: _assignDepartmentPosition,
                            onRemovePosition: _removeDepartmentPosition,
                          ),
                        ] else if (_activeSection == HrSection.positions) ...[
                          PositionsHeader(onAddPosition: _openAddPositionModal),
                          const SizedBox(height: 14),
                          PositionsPanel(
                            positions: _positions,
                            isLoading: _isLoadingPositions,
                            error: _positionError,
                            onRefresh: _loadPositions,
                            onEditPosition: _openEditPositionModal,
                            onDeletePosition: _confirmDeletePosition,
                          ),
                        ] else if (_activeSection == HrSection.clusters) ...[
                          ClustersHeader(
                            onAddCluster: _openAddClusterModal,
                            onAddArea: _openAddAreaModal,
                          ),
                          const SizedBox(height: 14),
                          AreasPanel(
                            areas: _areas,
                            isLoading: _isLoadingAreas,
                            error: _areaError,
                            onRefresh: _loadAreas,
                            onEditArea: _openEditAreaModal,
                            onDeleteArea: _confirmDeleteArea,
                          ),
                          const SizedBox(height: 14),
                          ClustersPanel(
                            clusters: _clusters,
                            isLoading: _isLoadingClusters,
                            error: _clusterError,
                            onRefresh: _loadClusters,
                            onEditCluster: _openEditClusterModal,
                            onDeleteCluster: _confirmDeleteCluster,
                          ),
                        ] else if (_activeSection == HrSection.stores) ...[
                          StoresHeader(onAddStore: _openAddStoreModal),
                          const SizedBox(height: 14),
                          StoresPanel(
                            stores: _stores,
                            isLoading: _isLoadingStores,
                            error: _storeError,
                            onRefresh: _loadStores,
                            onEditStore: _openEditStoreModal,
                            onDeleteStore: _confirmDeleteStore,
                          ),
                        ],
                      ],
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

class HrSidebar extends StatelessWidget {
  const HrSidebar({
    required this.activeSection,
    required this.session,
    required this.onSelectSection,
    required this.onSignOut,
    super.key,
  });

  final HrSection activeSection;
  final AdminLoginSession session;
  final ValueChanged<HrSection> onSelectSection;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: HygColors.ink,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: HygColors.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset('assets/hyg_icon.png'),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'HYG Employee Portal',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.canManageAdminSettings ||
                      session.appRole.toLowerCase() == 'hr')
                    HrNavItem(
                      icon: Icons.inbox_outlined,
                      label: 'All Requests',
                      active: activeSection == HrSection.requests,
                      onTap: () => onSelectSection(HrSection.requests),
                    ),
                  HrNavItem(
                    icon: Icons.group_outlined,
                    label: 'Employees',
                    active: activeSection == HrSection.employees,
                    onTap: () => onSelectSection(HrSection.employees),
                  ),
                  HrNavItem(
                    icon: Icons.business_outlined,
                    label: 'Companies',
                    active: activeSection == HrSection.companies,
                    onTap: () => onSelectSection(HrSection.companies),
                  ),
                  if (session.canManageAdminSettings) ...[
                    HrNavItem(
                      icon: Icons.route_outlined,
                      label: 'Approval Routes',
                      active: activeSection == HrSection.approvalRoutes,
                      onTap: () => onSelectSection(HrSection.approvalRoutes),
                    ),
                    HrNavItem(
                      icon: Icons.badge_outlined,
                      label: 'Authority Levels',
                      active: activeSection == HrSection.authorityLevels,
                      onTap: () => onSelectSection(HrSection.authorityLevels),
                    ),
                    HrNavItem(
                      icon: Icons.verified_user_outlined,
                      label: 'Approver Assignments',
                      active: activeSection == HrSection.approverAssignments,
                      onTap: () =>
                          onSelectSection(HrSection.approverAssignments),
                    ),
                    HrNavItem(
                      icon: Icons.manage_accounts_outlined,
                      label: 'Users',
                      active: activeSection == HrSection.users,
                      onTap: () => onSelectSection(HrSection.users),
                    ),
                  ],
                  HrNavDropdown(
                    icon: Icons.inventory_2_outlined,
                    label: 'Master Data',
                    active: {
                      if (session.canManageAdminSettings) HrSection.departments,
                      HrSection.positions,
                      HrSection.stores,
                      HrSection.clusters,
                    }.contains(activeSection),
                    items: [
                      if (session.canManageAdminSettings)
                        HrDropdownItem(
                          icon: Icons.account_tree_outlined,
                          label: 'Departments',
                          active: activeSection == HrSection.departments,
                          onTap: () => onSelectSection(HrSection.departments),
                        ),
                      HrDropdownItem(
                        icon: Icons.badge_outlined,
                        label: 'Positions',
                        active: activeSection == HrSection.positions,
                        onTap: () => onSelectSection(HrSection.positions),
                      ),
                      HrDropdownItem(
                        icon: Icons.store_mall_directory_outlined,
                        label: 'Stores',
                        active: activeSection == HrSection.stores,
                        onTap: () => onSelectSection(HrSection.stores),
                      ),
                      HrDropdownItem(
                        icon: Icons.hub_outlined,
                        label: 'Cluster / Area',
                        active: activeSection == HrSection.clusters,
                        onTap: () => onSelectSection(HrSection.clusters),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF475569),
                child: Text(
                  session.username.isEmpty
                      ? 'H'
                      : session.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.appRole.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, color: Colors.white, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HrNavItem extends StatelessWidget {
  const HrNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _SidebarHoverItem(
        active: active,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: active ? HygColors.ink : Colors.white, size: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HygTypography.nav.copyWith(
                  color: active ? HygColors.ink : Colors.white,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HrDropdownItem {
  const HrDropdownItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.active,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
}

class HrNavDropdown extends StatefulWidget {
  const HrNavDropdown({
    required this.icon,
    required this.label,
    required this.items,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final List<HrDropdownItem> items;
  final bool active;

  @override
  State<HrNavDropdown> createState() => _HrNavDropdownState();
}

class _HrNavDropdownState extends State<HrNavDropdown> {
  late bool _expanded = widget.active;

  @override
  void didUpdateWidget(covariant HrNavDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        children: [
          _SidebarHoverItem(
            active: widget.active,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: widget.active ? HygColors.ink : Colors.white,
                  size: 19,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    style: HygTypography.nav.copyWith(
                      color: widget.active ? HygColors.ink : Colors.white,
                      fontWeight: widget.active
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: widget.active ? HygColors.ink : Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Column(
                children: widget.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _SidebarHoverItem(
                          active: item.active,
                          onTap: item.onTap,
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                color: item.active
                                    ? HygColors.ink
                                    : const Color(0xFFCBD5E1),
                                size: 17,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: HygTypography.nav.copyWith(
                                    color: item.active
                                        ? HygColors.ink
                                        : const Color(0xFFCBD5E1),
                                    fontSize: 12,
                                    fontWeight: item.active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 140),
          ),
        ],
      ),
    );
  }
}

class _SidebarHoverItem extends StatefulWidget {
  const _SidebarHoverItem({
    required this.active,
    required this.onTap,
    required this.child,
  });

  final bool active;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_SidebarHoverItem> createState() => _SidebarHoverItemState();
}

class _SidebarHoverItemState extends State<_SidebarHoverItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.active
        ? HygColors.gold
        : _hovered
        ? const Color(0xFF1E293B)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: !widget.active && _hovered
                ? const Color(0xFF334155)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            splashColor: widget.active ? Colors.black12 : Colors.white10,
            highlightColor: Colors.transparent,
            onTap: widget.onTap,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 130),
                padding: EdgeInsets.only(
                  left: !widget.active && _hovered ? 3 : 0,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum HrSection {
  requests,
  approvalRoutes,
  authorityLevels,
  approverAssignments,
  users,
  employees,
  companies,
  departments,
  positions,
  clusters,
  stores,
}

class HrTopBar extends StatelessWidget {
  const HrTopBar({required this.onOpenAssist, super.key});

  final VoidCallback onOpenAssist;

  String _philippineDateLabel() {
    const monthNames = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final phNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${monthNames[phNow.month - 1]} ${phNow.day}, ${phNow.year}';
  }

  @override
  Widget build(BuildContext context) {
    final phDateLabel = _philippineDateLabel();
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: HygColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 520,
            height: 44,
            child: TextField(
              style: HygTypography.input.copyWith(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: HygColors.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ),
          const Spacer(),
          const TopIconButton(icon: Icons.notifications_none),
          const SizedBox(width: 10),
          const TopIconButton(icon: Icons.chat_bubble_outline),
          const SizedBox(width: 10),
          TopIconButton(
            icon: Icons.auto_awesome,
            filled: true,
            onTap: onOpenAssist,
          ),
          const SizedBox(width: 10),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Color(0xFF334155),
                ),
                const SizedBox(width: 8),
                Text(
                  phDateLabel,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
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

class TopIconButton extends StatelessWidget {
  const TopIconButton({
    required this.icon,
    this.filled = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: filled ? HygColors.gold : Colors.white,
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: HygColors.ink),
        ),
      ),
    );
  }
}
