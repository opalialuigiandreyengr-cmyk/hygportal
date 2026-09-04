part of '../main.dart';

enum _PhotoProofTab {
  recentlyCaptured,
  departments,
}

class HygPhotoProofsScreen extends StatefulWidget {
  const HygPhotoProofsScreen({super.key});

  @override
  State<HygPhotoProofsScreen> createState() => _HygPhotoProofsScreenState();
}

class _HygPhotoProofsScreenState extends State<HygPhotoProofsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<_PhotoProofRecord> _allProofs = [];
  List<EmployeePreview> _allEmployees = [];
  List<DepartmentPreview> _allDepartments = [];
  List<StorePreview> _allStores = [];
  Map<String, String> _employeeAssignedStore = {};
  Map<String, String> _employeeNameAssignedStore = {};
  bool _isLoading = true;
  String? _error;

  // Active top tab: Recently Captured Photo Proofs vs Departments
  _PhotoProofTab _activeTab = _PhotoProofTab.recentlyCaptured;

  // Navigation hierarchy in Departments tab:
  // Level 0: _selectedDepartment == null (Departments list)
  // Level 1: _selectedDepartment != null (Employees list, or Stores list if Operations)
  // Level 2 (Operations only): _selectedStoreInOperations != null (Employees list of store)
  // Final level: _selectedEmployeeName != null (Proofs of selected employee)
  String? _selectedDepartment;
  String? _selectedStoreInOperations;
  String? _selectedEmployeeName;
  String? _selectedEmployeeId;

  // Filters
  String _selectedStore = 'All Stores';
  String _dateFilter = 'All'; // 'All', 'Today', 'Past 7 Days'
  bool _isGridView = true;

  static const List<String> _defaultDepartments = [
    'IT',
    'Marketing',
    'Logistics',
    'Motorpool',
    'Inventory',
    'Audit',
    'Admin',
    'Accounting',
    'HR',
    'Maintenance',
    'Operations',
  ];

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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // 1. Load photo proofs
      final response = await client
          .from('photo_proofs')
          .select('*')
          .order('timestamp', ascending: false)
          .limit(200);

      final List<dynamic> rows = response as List<dynamic>;
      final proofItems = rows
          .map((row) => _PhotoProofRecord.fromMap(row as Map<String, dynamic>))
          .toList(growable: false);

      // 2. Load employees
      List<EmployeePreview> emps = [];
      try {
        emps = await EmployeeDirectoryService.loadEmployees();
      } catch (empErr) {
        debugPrint('Failed loading employees for photo proofs: $empErr');
      }

      // 3. Load departments
      List<DepartmentPreview> depts = [];
      try {
        depts = await DepartmentDirectoryService.loadDepartments();
      } catch (deptErr) {
        debugPrint('Failed loading departments for photo proofs: $deptErr');
      }

      // 4. Load stores
      List<StorePreview> stores = [];
      try {
        stores = await StoreDirectoryService.loadStores();
      } catch (storeErr) {
        debugPrint('Failed loading stores for photo proofs: $storeErr');
      }

      // 5. Scope photo proofs to the allowed stores & employees for this HR admin account
      List<_PhotoProofRecord> scopedProofs = proofItems;
      if (stores.isNotEmpty || emps.isNotEmpty) {
        final allowedStoreNames = stores
            .map((s) => s.name.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
        final allowedEmpIds = emps
            .map((e) => e.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final allowedEmpNames = emps
            .map((e) => _normalizeName(e.name))
            .where((n) => n.isNotEmpty)
            .toSet();

        scopedProofs = proofItems.where((proof) {
          final pStore = proof.storeName.trim().toLowerCase();
          if (pStore.isNotEmpty && allowedStoreNames.contains(pStore)) {
            return true;
          }
          final pEmpId = proof.employeeId.trim();
          if (pEmpId.isNotEmpty && allowedEmpIds.contains(pEmpId)) {
            return true;
          }
          final pEmpName = _normalizeName(proof.employeeName);
          if (pEmpName.isNotEmpty && allowedEmpNames.contains(pEmpName)) {
            return true;
          }
          return false;
        }).toList();
      }

      // 6. Load employee-to-store assignments
      final Map<String, String> empStoreMap = {};
      final Map<String, String> empNameStoreMap = {};

      // A. Try bulk RPC hr_employee_store_assignments
      try {
        final bulkRes = await client.rpc(
          'hr_employee_store_assignments',
          params: {
            'p_username': AppConfig.hrUsername,
            'p_password': AppConfig.hrPassword,
          },
        );
        if (bulkRes is List) {
          for (final row in bulkRes) {
            if (row is Map<String, dynamic>) {
              final empId = (row['employee_id'] ?? '').toString().trim();
              final sName = (row['store_name'] ?? '').toString().trim();
              final eName = (row['employee_name'] ?? '').toString().trim();
              if (sName.isNotEmpty) {
                if (empId.isNotEmpty) empStoreMap[empId] = sName;
                if (eName.isNotEmpty) empNameStoreMap[_normalizeName(eName)] = sName;
              }
            }
          }
        }
      } catch (rpcErr) {
        debugPrint('hr_employee_store_assignments RPC not available: $rpcErr');
      }

      // B. Fallback: Query hr_employee_store_detail for employees if bulk was empty
      if (empStoreMap.isEmpty && emps.isNotEmpty) {
        try {
          final futures = emps.map((emp) async {
            if (emp.id.isEmpty) return null;
            try {
              final res = await client.rpc('hr_employee_store_detail', params: {
                'p_username': AppConfig.hrUsername,
                'p_password': AppConfig.hrPassword,
                'p_employee_id': emp.id,
              });
              if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
                final s = (res.first['store_name'] ?? '').toString().trim();
                if (s.isNotEmpty) {
                  return MapEntry(emp.id, s);
                }
              }
            } catch (_) {}
            return null;
          });
          final results = await Future.wait(futures);
          for (final entry in results) {
            if (entry != null) {
              empStoreMap[entry.key] = entry.value;
              final matchingEmp = emps.where((e) => e.id == entry.key).firstOrNull;
              if (matchingEmp != null) {
                empNameStoreMap[_normalizeName(matchingEmp.name)] = entry.value;
              }
            }
          }
        } catch (detailErr) {
          debugPrint('hr_employee_store_detail fallback error: $detailErr');
        }
      }

      // C. Also associate store from scoped proofs if employee has proofs for an authorized store
      final allowedStoreNames = stores.map((s) => s.name.trim().toLowerCase()).toSet();
      for (final proof in scopedProofs) {
        final pStore = proof.storeName.trim();
        if (pStore.isNotEmpty) {
          if (allowedStoreNames.isNotEmpty && !allowedStoreNames.contains(pStore.toLowerCase())) {
            continue;
          }
          final pEmpId = proof.employeeId.trim();
          final pEmpName = _normalizeName(proof.employeeName);
          if (pEmpId.isNotEmpty && !empStoreMap.containsKey(pEmpId)) {
            empStoreMap[pEmpId] = pStore;
          }
          if (pEmpName.isNotEmpty && !empNameStoreMap.containsKey(pEmpName)) {
            empNameStoreMap[pEmpName] = pStore;
          }
        }
      }

      if (mounted) {
        setState(() {
          _allProofs = scopedProofs;
          _allEmployees = emps;
          _allDepartments = depts;
          _allStores = stores;
          _employeeAssignedStore = empStoreMap;
          _employeeNameAssignedStore = empNameStoreMap;
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

  // ---------------------------------------------------------------------------
  // CANONICAL DEPARTMENT DEDUPLICATION
  // ---------------------------------------------------------------------------
  String _canonicalDepartmentName(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    final lower = clean.toLowerCase();

    if (lower == 'it' ||
        lower == 'information technology' ||
        lower == 'info tech' ||
        lower == 'i.t.' ||
        lower == 'i.t') {
      return 'IT';
    }
    if (lower == 'hr' ||
        lower == 'human resources' ||
        lower == 'human resource' ||
        lower == 'h.r.' ||
        lower == 'h.r') {
      return 'HR';
    }
    if (lower == 'admin' ||
        lower == 'administration' ||
        lower == 'administrative') {
      return 'Admin';
    }
    if (lower == 'accounting' || lower == 'finance' || lower == 'acctg') {
      return 'Accounting';
    }
    if (lower == 'marketing' || lower == 'mktg') {
      return 'Marketing';
    }
    if (lower == 'logistics' ||
        lower == 'warehouse & logistics' ||
        lower == 'logistics & warehouse') {
      return 'Logistics';
    }
    if (lower == 'motorpool' || lower == 'motor pool') {
      return 'Motorpool';
    }
    if (lower == 'inventory') {
      return 'Inventory';
    }
    if (lower == 'audit' || lower == 'internal audit') {
      return 'Audit';
    }
    if (lower == 'maintenance') {
      return 'Maintenance';
    }
    if (lower == 'operations' || lower == 'operation' || lower == 'ops') {
      return 'Operations';
    }

    return clean.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  List<String> _getDepartments() {
    final Map<String, String> deptMap = {};

    // Only include departments that have at least one assigned employee in _allEmployees
    for (final e in _allEmployees) {
      final rawDept = e.departmentName.trim();
      if (rawDept.isNotEmpty) {
        final canon = _canonicalDepartmentName(rawDept);
        if (canon.isNotEmpty) {
          deptMap.putIfAbsent(canon.toLowerCase(), () => canon);
        }
      }
    }

    // Order: standard default departments first, then remaining alphabetically
    final result = <String>[];
    for (final d in _defaultDepartments) {
      final canon = _canonicalDepartmentName(d);
      if (deptMap.containsKey(canon.toLowerCase())) {
        result.add(deptMap.remove(canon.toLowerCase())!);
      }
    }
    final remaining = deptMap.values.toList()..sort();
    result.addAll(remaining);

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty || _selectedDepartment != null) {
      return result;
    }
    return result.where((d) => d.toLowerCase().contains(query)).toList();
  }

  // ---------------------------------------------------------------------------
  // OPERATIONS STORES
  // ---------------------------------------------------------------------------
  List<String> _getStoresForOperations() {
    final storeSet = <String>{};

    // 1. Stores from database (scoped to HR admin account's assigned companies)
    for (final s in _allStores) {
      if (s.name.trim().isNotEmpty) {
        storeSet.add(s.name.trim());
      }
    }

    // 2. Only if database stores are completely empty, fallback to stores from proofs
    if (storeSet.isEmpty) {
      for (final p in _allProofs) {
        if (p.storeName.trim().isNotEmpty) {
          storeSet.add(p.storeName.trim());
        }
      }
    }

    // Exclude IT and any department folders from Operations stores
    final deptNames = <String>{
      ..._defaultDepartments.map((d) => d.toLowerCase()),
      ..._allDepartments.map((d) => d.name.toLowerCase()),
      ..._getDepartments().map((d) => d.toLowerCase()),
    };
    storeSet.removeWhere((s) {
      final lower = s.trim().toLowerCase();
      final canon = _canonicalDepartmentName(s).toLowerCase();
      if (lower == 'it' ||
          canon == 'it' ||
          lower == 'information technology' ||
          lower == 'info tech' ||
          lower == 'i.t.' ||
          lower == 'i.t') {
        return true;
      }
      if (deptNames.contains(lower) || deptNames.contains(canon)) {
        return true;
      }
      return false;
    });

    final query = _searchController.text.trim().toLowerCase();
    final list = storeSet.toList()..sort();
    if (query.isEmpty) return list;
    return list.where((s) => s.toLowerCase().contains(query)).toList();
  }

  String _getCompanyNameForStore(String storeName) {
    final clean = storeName.trim().toLowerCase();
    if (clean.isEmpty) return '';

    // 1. Direct match from _allStores
    for (final s in _allStores) {
      if (s.name.trim().toLowerCase() == clean && s.companyName.trim().isNotEmpty) {
        return s.companyName.trim();
      }
    }

    // 2. Partial match from _allStores
    for (final s in _allStores) {
      final sClean = s.name.trim().toLowerCase();
      if ((sClean.contains(clean) || clean.contains(sClean)) && s.companyName.trim().isNotEmpty) {
        return s.companyName.trim();
      }
    }

    // 3. Fallback: check assigned employees in this store
    final assigned = _getEmployeesForStoreInOperations(storeName);
    for (final emp in assigned) {
      if (emp.companyName.trim().isNotEmpty && emp.companyName.trim().toLowerCase() != clean) {
        return emp.companyName.trim();
      }
      if (emp.company.trim().isNotEmpty && emp.company.trim().toLowerCase() != clean) {
        return emp.company.trim();
      }
    }

    // 4. Fallback: cross-reference proofs
    for (final proof in _allProofs) {
      if (proof.storeName.trim().toLowerCase() == clean) {
        for (final emp in _allEmployees) {
          if (_matchesEmployeeName(emp.name, proof.employeeName)) {
            if (emp.companyName.trim().isNotEmpty) return emp.companyName.trim();
            if (emp.company.trim().isNotEmpty) return emp.company.trim();
          }
        }
      }
    }

    return '';
  }

  // ---------------------------------------------------------------------------
  // EMPLOYEES MATCHING & RESOLUTION
  // ---------------------------------------------------------------------------
  List<EmployeePreview> _getEmployeesForDepartment(String department) {
    final query = _searchController.text.trim().toLowerCase();
    final deptCanon = _canonicalDepartmentName(department).toLowerCase();

    // Find employees from directory
    final list = _allEmployees.where((emp) {
      final empDept = _canonicalDepartmentName(emp.departmentName).toLowerCase();
      return empDept == deptCanon;
    }).toList();

    // Also include any employees found in proofs for this department if not already listed
    for (final proof in _allProofs) {
      final pStore = _canonicalDepartmentName(proof.storeName).toLowerCase();
      if (pStore == deptCanon && proof.employeeName.trim().isNotEmpty) {
        final alreadyPresent = list.any((e) => _matchesEmployeeName(e.name, proof.employeeName));
        if (!alreadyPresent) {
          list.add(
            EmployeePreview(
              id: proof.employeeId.isNotEmpty ? proof.employeeId : proof.id,
              name: proof.employeeName,
              initial: proof.employeeName.isNotEmpty ? proof.employeeName[0] : 'E',
              email: '',
              phone: '',
              photoUrl: proof.photoUrl,
              idNumber: '',
              company: '',
              companyName: '',
              departmentName: department,
              positionName: 'Team Member',
              roleDepartment: department,
              hired: '',
              createdAt: null,
              status: 'active',
              avatarColor: const Color(0xFF0284C7),
              rawHiredDate: null,
            ),
          );
        }
      }
    }

    if (query.isEmpty) {
      return list;
    }
    return list.where((e) => e.name.toLowerCase().contains(query)).toList();
  }

  String _normalizeName(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  bool _matchesEmployeeName(String dirName, String proofName) {
    final c1 = _normalizeName(dirName);
    final c2 = _normalizeName(proofName);
    if (c1.isEmpty || c2.isEmpty) return false;
    if (c1 == c2) return true;

    final w1 = dirName
        .toLowerCase()
        .replaceAll('.', '')
        .replaceAll(',', '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
    final w2 = proofName
        .toLowerCase()
        .replaceAll('.', '')
        .replaceAll(',', '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
    if (w1.length >= 2 && w2.length >= 2) {
      if (w1.first == w2.first && w1.last == w2.last) return true;
    }
    return false;
  }

  List<EmployeePreview> _getEmployeesForStoreInOperations(String storeName) {
    final query = _searchController.text.trim().toLowerCase();
    final cleanStore = storeName.trim().toLowerCase();

    final matchedEmployees = <EmployeePreview>[];
    final addedIds = <String>{};
    final addedNames = <String>{};

    // 1. Check directory employees assigned to this specific store
    for (final emp in _allEmployees) {
      String? assigned = _employeeAssignedStore[emp.id];
      assigned ??= _employeeNameAssignedStore[_normalizeName(emp.name)];

      // If not yet in store mapping, check if employee has proofs exclusively for this store
      if (assigned == null) {
        final empProofs = _allProofs
            .where((p) => _matchesEmployeeName(emp.name, p.employeeName))
            .toList();
        if (empProofs.isNotEmpty) {
          final stores = empProofs
              .map((p) => p.storeName.trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
          if (stores.contains(cleanStore) && stores.length == 1) {
            assigned = storeName;
          }
        }
      }

      // STRICT ASSIGNMENT: Only add if the assigned store matches this folder's store
      if (assigned != null && assigned.trim().toLowerCase() == cleanStore) {
        final norm = _normalizeName(emp.name);
        if (!addedIds.contains(emp.id) && !addedNames.contains(norm)) {
          matchedEmployees.add(emp);
          if (emp.id.isNotEmpty) addedIds.add(emp.id);
          addedNames.add(norm);
        }
      }
    }

    // 2. Include employees from photo proofs captured specifically for this store
    for (final proof in _allProofs) {
      final pStore = proof.storeName.trim().toLowerCase();
      if (pStore == cleanStore && proof.employeeName.trim().isNotEmpty) {
        final norm = _normalizeName(proof.employeeName);
        final alreadyPresent = (proof.employeeId.isNotEmpty && addedIds.contains(proof.employeeId)) ||
            addedNames.contains(norm) ||
            matchedEmployees.any((e) => _matchesEmployeeName(e.name, proof.employeeName));

        if (!alreadyPresent) {
          // Verify that this employee isn't assigned to a DIFFERENT store
          final otherStore = (proof.employeeId.isNotEmpty ? _employeeAssignedStore[proof.employeeId] : null) ??
              _employeeNameAssignedStore[norm];

          if (otherStore == null || otherStore.trim().toLowerCase() == cleanStore) {
            matchedEmployees.add(
              EmployeePreview(
                id: proof.employeeId.isNotEmpty ? proof.employeeId : proof.id,
                name: proof.employeeName,
                initial: proof.employeeName.isNotEmpty ? proof.employeeName[0] : 'E',
                email: '',
                phone: '',
                photoUrl: proof.photoUrl,
                idNumber: '',
                company: '',
                companyName: storeName,
                departmentName: 'Operations',
                positionName: 'Store Staff',
                roleDepartment: 'Operations',
                hired: '',
                createdAt: null,
                status: 'active',
                avatarColor: const Color(0xFF0284C7),
                rawHiredDate: null,
                rawBirthDate: null,
              ),
            );
            if (proof.employeeId.isNotEmpty) addedIds.add(proof.employeeId);
            addedNames.add(norm);
          }
        }
      }
    }

    // STRICT: Only employees assigned to this store are returned. No fallback to all operations staff.

    if (query.isEmpty) return matchedEmployees;
    return matchedEmployees.where((e) => e.name.toLowerCase().contains(query)).toList();
  }

  // ---------------------------------------------------------------------------
  // PROOFS QUERIES
  // ---------------------------------------------------------------------------
  List<_PhotoProofRecord> _getRecentlyCapturedProofs() {
    final now = _phNow();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final query = _searchController.text.trim().toLowerCase();

    return _allProofs.where((item) {
      // Store filter
      if (_selectedStore != 'All Stores' && item.storeName != _selectedStore) {
        return false;
      }

      // Date filter
      if (_dateFilter == 'Today') {
        if (!item.isoDate.startsWith(todayStr)) return false;
      } else if (_dateFilter == 'Past 7 Days') {
        final itemDate = item.parsedDateTime;
        if (itemDate != null && now.difference(itemDate).inDays > 7) {
          return false;
        }
      }

      // Search query
      if (query.isNotEmpty) {
        final matchEmp = item.employeeName.toLowerCase().contains(query);
        final matchStore = item.storeName.toLowerCase().contains(query);
        final matchLoc = item.locationText.toLowerCase().contains(query);
        final matchDate = item.dateFormatted.toLowerCase().contains(query);
        if (!matchEmp && !matchStore && !matchLoc && !matchDate) {
          return false;
        }
      }

      return true;
    }).toList(growable: false);
  }

  List<_PhotoProofRecord> _getFilteredProofsForSelectedEmployee() {
    if (_selectedEmployeeName == null) return const [];

    final now = _phNow();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final query = _searchController.text.trim().toLowerCase();

    return _allProofs.where((item) {
      // Employee match
      final nameMatches = _matchesEmployeeName(_selectedEmployeeName!, item.employeeName);
      final idMatches = _selectedEmployeeId != null &&
          _selectedEmployeeId!.isNotEmpty &&
          item.employeeId.isNotEmpty &&
          _selectedEmployeeId == item.employeeId;

      if (!nameMatches && !idMatches) {
        return false;
      }

      // Store filter
      if (_selectedStore != 'All Stores' && item.storeName != _selectedStore) {
        return false;
      }

      // Operations store drill-down filter
      if (_selectedStoreInOperations != null &&
          item.storeName.trim().isNotEmpty &&
          item.storeName.trim().toLowerCase() != _selectedStoreInOperations!.trim().toLowerCase()) {
        return false;
      }

      // Date filter (inactive when on Departments tab)
      if (_activeTab != _PhotoProofTab.departments) {
        if (_dateFilter == 'Today') {
          if (!item.isoDate.startsWith(todayStr)) return false;
        } else if (_dateFilter == 'Past 7 Days') {
          final itemDate = item.parsedDateTime;
          if (itemDate != null && now.difference(itemDate).inDays > 7) {
            return false;
          }
        }
      }

      // Search query
      if (query.isNotEmpty) {
        final matchStore = item.storeName.toLowerCase().contains(query);
        final matchLoc = item.locationText.toLowerCase().contains(query);
        final matchDate = item.dateFormatted.toLowerCase().contains(query);
        if (!matchStore && !matchLoc && !matchDate) {
          return false;
        }
      }

      return true;
    }).toList(growable: false);
  }

  List<String> _getAvailableStores() {
    final stores = <String>{'All Stores'};
    for (final s in _allStores) {
      if (s.name.trim().isNotEmpty) {
        stores.add(s.name.trim());
      }
    }
    // Only if database stores are completely empty, fallback to stores from proofs
    if (stores.length == 1) {
      for (final proof in _allProofs) {
        final s = proof.storeName.trim();
        if (s.isNotEmpty) {
          stores.add(s);
        }
      }
    }
    return stores.toList()..sort();
  }

  void _handleBackNavigation() {
    if (_activeTab == _PhotoProofTab.departments) {
      if (_selectedEmployeeName != null) {
        setState(() {
          _selectedEmployeeName = null;
          _selectedEmployeeId = null;
        });
        return;
      }
      if (_selectedStoreInOperations != null) {
        setState(() {
          _selectedStoreInOperations = null;
        });
        return;
      }
      if (_selectedDepartment != null) {
        setState(() {
          _selectedDepartment = null;
        });
        return;
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = _phNow();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final totalCount = _allProofs.length;
    final todayCount = _allProofs.where((p) => p.isoDate.startsWith(todayStr)).length;
    final geotaggedCount = _allProofs.where((p) => p.locationText.isNotEmpty || (p.latitude != null && p.longitude != null)).length;

    return Scaffold(
      backgroundColor: HygColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header (White card, blue photo icon, Back button)
              _buildHeader(context),
              const SizedBox(height: 14),

              // 2. Stats Bar (Total Submissions, Today's Proofs, Geotagged Proofs)
              _buildStatsBar(
                totalCount: totalCount,
                todayCount: todayCount,
                geotaggedCount: geotaggedCount,
              ),
              const SizedBox(height: 14),

              // 3. Controls Bar (Search, Store Filter, Date Chips, Grid/List Switch)
              _buildControlsBar(),
              const SizedBox(height: 14),

              // 4. Tab Bar: [ Recently Captured Photo Proofs ] [ Departments ]
              _buildTabBar(),
              const SizedBox(height: 14),

              // 5. Dynamic Tab View Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF0284C7)),
                      )
                    : _error != null
                        ? _buildErrorView()
                        : _activeTab == _PhotoProofTab.recentlyCaptured
                            ? _buildRecentlyCapturedTab()
                            : _buildDepartmentsTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photo Proofs',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Verify employee photo proofs, attendance captures and geolocation audit trail.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0F172A), size: 20),
            onPressed: _loadData,
            tooltip: 'Refresh Photo Proofs',
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _handleBackNavigation,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text(
              'Back',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATS BAR
  // ---------------------------------------------------------------------------
  Widget _buildStatsBar({
    required int totalCount,
    required int todayCount,
    required int geotaggedCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Total Submissions',
            value: totalCount.toString(),
            icon: Icons.collections_outlined,
            iconColor: const Color(0xFF0284C7),
            bgColor: const Color(0xFFE0F2FE),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: "Today's Proofs",
            value: todayCount.toString(),
            icon: Icons.calendar_month_outlined,
            iconColor: const Color(0xFF16A34A),
            bgColor: const Color(0xFFDCFCE7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Geotagged Proofs',
            value: geotaggedCount.toString(),
            icon: Icons.location_on_outlined,
            iconColor: const Color(0xFFDC2626),
            bgColor: const Color(0xFFFEE2E2),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTROLS BAR
  // ---------------------------------------------------------------------------
  Widget _buildControlsBar() {
    final stores = _getAvailableStores();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Search input
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search employee, store, department or location...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
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
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Store Dropdown
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: stores.contains(_selectedStore) ? _selectedStore : 'All Stores',
                items: stores
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStore = val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Date Filter Toggle Buttons
          () {
            final isDepartmentsTab = _activeTab == _PhotoProofTab.departments;
            return Tooltip(
              message: isDepartmentsTab ? 'Date filter is disabled in Departments tab' : '',
              waitDuration: const Duration(milliseconds: 300),
              child: Opacity(
                opacity: isDepartmentsTab ? 0.45 : 1.0,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDepartmentsTab ? const Color(0xFFF1F5F9) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDepartmentsTab ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDateFilterChip('All', disabled: isDepartmentsTab),
                      _buildDateFilterChip('Today', disabled: isDepartmentsTab),
                      _buildDateFilterChip('Past 7 Days', disabled: isDepartmentsTab),
                    ],
                  ),
                ),
              ),
            );
          }(),
          const SizedBox(width: 10),

          // Grid vs List Toggle
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _isGridView = true),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(7),
                    bottomLeft: Radius.circular(7),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: _isGridView ? const Color(0xFFF1F5F9) : Colors.transparent,
                    child: Icon(
                      Icons.grid_view_rounded,
                      size: 18,
                      color: _isGridView ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                InkWell(
                  onTap: () => setState(() => _isGridView = false),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: !_isGridView ? const Color(0xFFF1F5F9) : Colors.transparent,
                    child: Icon(
                      Icons.view_list_rounded,
                      size: 18,
                      color: !_isGridView ? const Color(0xFF0284C7) : const Color(0xFF64748B),
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

  Widget _buildDateFilterChip(String label, {bool disabled = false}) {
    final isSelected = _dateFilter == label;
    return GestureDetector(
      onTap: disabled ? null : () => setState(() => _dateFilter = label),
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: (!disabled && isSelected) ? const Color(0xFFF1F5F9) : Colors.transparent,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (!disabled && isSelected) ? FontWeight.bold : FontWeight.w500,
              color: disabled
                  ? const Color(0xFF94A3B8)
                  : (isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB BAR: [ Recently Captured Photo Proofs ] [ Departments ]
  // ---------------------------------------------------------------------------
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildTabItem(
            tab: _PhotoProofTab.recentlyCaptured,
            title: 'Recently Captured Photo Proofs',
            icon: Icons.history_rounded,
            count: _getRecentlyCapturedProofs().length,
          ),
          const SizedBox(width: 28),
          _buildTabItem(
            tab: _PhotoProofTab.departments,
            title: 'Departments',
            icon: Icons.folder_outlined,
            count: _getDepartments().length,
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required _PhotoProofTab tab,
    required String title,
    required IconData icon,
    required int count,
  }) {
    final isActive = _activeTab == tab;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tab;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF0284C7) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? const Color(0xFF0284C7) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: RECENTLY CAPTURED PHOTO PROOFS (Grid vs List)
  // ---------------------------------------------------------------------------
  Widget _buildRecentlyCapturedTab() {
    final proofs = _getRecentlyCapturedProofs();

    if (proofs.isEmpty) {
      return _buildEmptyState(
        title: 'No Recently Captured Photo Proofs',
        message: 'No photo proofs match your current search, store, or date filter.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Recently Captured Photo Proofs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Text(
              'Showing ${proofs.length} submissions',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isGridView
              ? GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 330,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: proofs.length,
                  itemBuilder: (context, index) {
                    final proof = proofs[index];
                    return _buildProofCard(proof);
                  },
                )
              : _buildProofsTableView(proofs),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: DEPARTMENTS (Hierarchical Folder Navigation)
  // ---------------------------------------------------------------------------
  Widget _buildDepartmentsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb Trail
        _buildBreadcrumbBar(),
        const SizedBox(height: 12),

        // Dynamic Hierarchy Level
        Expanded(
          child: _buildCurrentDepartmentLevel(),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbBar() {
    return Row(
      children: [
        // Root: Departments
        InkWell(
          onTap: () {
            setState(() {
              _selectedDepartment = null;
              _selectedStoreInOperations = null;
              _selectedEmployeeName = null;
              _selectedEmployeeId = null;
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'Departments',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
                decoration: _selectedDepartment != null ? TextDecoration.none : null,
              ),
            ),
          ),
        ),

        // Level 1: Selected Department
        if (_selectedDepartment != null) ...[
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 24, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _selectedStoreInOperations = null;
                _selectedEmployeeName = null;
                _selectedEmployeeId = null;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                _selectedDepartment!,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ],

        // Level 2 (Operations Store): Selected Store under Operations
        if (_selectedDepartment != null &&
            _selectedDepartment!.toLowerCase() == 'operations' &&
            _selectedStoreInOperations != null) ...[
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 24, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _selectedEmployeeName = null;
                _selectedEmployeeId = null;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedStoreInOperations!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  () {
                    final comp = _getCompanyNameForStore(_selectedStoreInOperations!);
                    if (comp.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.business_outlined, size: 13, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(
                              comp,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
                ],
              ),
            ),
          ),
        ],

        // Final level: Selected Employee
        if (_selectedEmployeeName != null) ...[
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 24, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(
            _selectedEmployeeName!,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCurrentDepartmentLevel() {
    if (_selectedDepartment == null) {
      // Level 0: Departments
      return _buildDepartmentsLevel();
    }

    final isOperations = _selectedDepartment!.toLowerCase() == 'operations';

    if (isOperations) {
      if (_selectedStoreInOperations != null) {
        final selLower = _selectedStoreInOperations!.trim().toLowerCase();
        final selCanon = _canonicalDepartmentName(_selectedStoreInOperations!).toLowerCase();
        if (selLower == 'it' || selCanon == 'it' || selLower == 'operations' || selCanon == 'operations') {
          _selectedStoreInOperations = null;
          _selectedEmployeeName = null;
          _selectedEmployeeId = null;
        }
      }

      if (_selectedStoreInOperations == null) {
        // Operations -> Stores Level
        return _buildOperationsStoresLevel();
      } else if (_selectedEmployeeName == null) {
        // Operations -> Store -> Employees Level
        return _buildOperationsStoreEmployeesLevel();
      } else {
        // Operations -> Store -> Employee -> Proofs
        return _buildProofsLevel();
      }
    } else {
      if (_selectedEmployeeName == null) {
        // Department -> Employees Level
        return _buildEmployeesLevel();
      } else {
        // Department -> Employee -> Proofs
        return _buildProofsLevel();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LEVEL 0: DEPARTMENTS (No duplicates guaranteed)
  // ---------------------------------------------------------------------------
  Widget _buildDepartmentsLevel() {
    final depts = _getDepartments();

    if (depts.isEmpty) {
      return _buildEmptyState(
        title: 'No Departments Found',
        message: 'No departments match your current search query.',
      );
    }

    if (_isGridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 78,
          crossAxisSpacing: 16,
          mainAxisSpacing: 14,
        ),
        itemCount: depts.length,
        itemBuilder: (context, index) {
          final dept = depts[index];
          final canon = _canonicalDepartmentName(dept).toLowerCase();
          final empCount = _allEmployees.where((e) => _canonicalDepartmentName(e.departmentName).toLowerCase() == canon).length;

          return _buildFolderCard(
            title: dept,
            subtitle: '$empCount employee${empCount == 1 ? '' : 's'}',
            onTap: () {
              setState(() {
                _selectedDepartment = dept;
                _selectedStoreInOperations = null;
                _selectedEmployeeName = null;
                _selectedEmployeeId = null;
              });
            },
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            itemCount: depts.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (context, index) {
              final dept = depts[index];
              final canon = _canonicalDepartmentName(dept).toLowerCase();
              final empCount = _allEmployees.where((e) => _canonicalDepartmentName(e.departmentName).toLowerCase() == canon).length;
              final proofCount = _allProofs.where((p) => _canonicalDepartmentName(p.storeName).toLowerCase() == canon).length;

              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFF59E0B), size: 30),
                title: Text(
                  dept,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  '$empCount employees • $proofCount submissions',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                onTap: () {
                  setState(() {
                    _selectedDepartment = dept;
                    _selectedStoreInOperations = null;
                    _selectedEmployeeName = null;
                    _selectedEmployeeId = null;
                  });
                },
              );
            },
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // OPERATIONS: STORES LEVEL
  // ---------------------------------------------------------------------------
  Widget _buildOperationsStoresLevel() {
    final stores = _getStoresForOperations();

    if (stores.isEmpty) {
      return _buildEmptyState(
        title: 'No Stores Found',
        message: 'No stores recorded under Operations.',
      );
    }

    if (_isGridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 88,
          crossAxisSpacing: 16,
          mainAxisSpacing: 14,
        ),
        itemCount: stores.length,
        itemBuilder: (context, index) {
          final store = stores[index];
          final companyName = _getCompanyNameForStore(store);
          final assignedEmps = _getEmployeesForStoreInOperations(store);
          final proofCount = _allProofs.where((p) => p.storeName.trim().toLowerCase() == store.trim().toLowerCase()).length;

          return _buildFolderCard(
            title: store,
            tag: companyName.isNotEmpty ? companyName : null,
            subtitle: '${assignedEmps.length} assigned employee${assignedEmps.length == 1 ? '' : 's'} • $proofCount proof${proofCount == 1 ? '' : 's'}',
            onTap: () {
              setState(() {
                _selectedStoreInOperations = store;
                _selectedEmployeeName = null;
                _selectedEmployeeId = null;
              });
            },
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            itemCount: stores.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (context, index) {
              final store = stores[index];
              final companyName = _getCompanyNameForStore(store);
              final assignedEmps = _getEmployeesForStoreInOperations(store);
              final proofCount = _allProofs.where((p) => p.storeName.trim().toLowerCase() == store.trim().toLowerCase()).length;

              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFF59E0B), size: 30),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        store,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (companyName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.business_outlined, size: 12, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(
                              companyName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  '${companyName.isNotEmpty ? "$companyName • " : ""}${assignedEmps.length} assigned employee${assignedEmps.length == 1 ? '' : 's'} • $proofCount photo proof${proofCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                onTap: () {
                  setState(() {
                    _selectedStoreInOperations = store;
                    _selectedEmployeeName = null;
                    _selectedEmployeeId = null;
                  });
                },
              );
            },
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // OPERATIONS: STORE EMPLOYEES LEVEL
  // ---------------------------------------------------------------------------
  Widget _buildOperationsStoreEmployeesLevel() {
    final employees = _getEmployeesForStoreInOperations(_selectedStoreInOperations!);

    if (employees.isEmpty) {
      return _buildEmptyState(
        title: 'No Employees Assigned to $_selectedStoreInOperations',
        message: 'No employees are currently assigned to this store.',
      );
    }

    if (_isGridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 78,
          crossAxisSpacing: 16,
          mainAxisSpacing: 14,
        ),
        itemCount: employees.length,
        itemBuilder: (context, index) {
          final emp = employees[index];
          final proofsCount = _allProofs
              .where((p) =>
                  _matchesEmployeeName(emp.name, p.employeeName) &&
                  (_selectedStoreInOperations == null ||
                      p.storeName.trim().toLowerCase() ==
                          _selectedStoreInOperations!.trim().toLowerCase()))
              .length;

          return _buildFolderCard(
            title: emp.name,
            subtitle: '${emp.positionName.isNotEmpty ? emp.positionName : "Store Staff"} • $proofsCount proof${proofsCount == 1 ? '' : 's'}',
            onTap: () {
              setState(() {
                _selectedEmployeeName = emp.name;
                _selectedEmployeeId = emp.id;
              });
            },
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            itemCount: employees.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (context, index) {
              final emp = employees[index];
              final proofsCount = _allProofs
                  .where((p) =>
                      _matchesEmployeeName(emp.name, p.employeeName) &&
                      (_selectedStoreInOperations == null ||
                          p.storeName.trim().toLowerCase() ==
                              _selectedStoreInOperations!.trim().toLowerCase()))
                  .length;

              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFF59E0B), size: 30),
                title: Text(
                  emp.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  '${emp.positionName.isNotEmpty ? emp.positionName : "Store Staff"} • $proofsCount proof${proofsCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                onTap: () {
                  setState(() {
                    _selectedEmployeeName = emp.name;
                    _selectedEmployeeId = emp.id;
                  });
                },
              );
            },
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // GENERAL DEPARTMENT: EMPLOYEES LEVEL
  // ---------------------------------------------------------------------------
  Widget _buildEmployeesLevel() {
    final employees = _getEmployeesForDepartment(_selectedDepartment!);

    if (employees.isEmpty) {
      return _buildEmptyState(
        title: 'No Employees in $_selectedDepartment',
        message: 'No employees or proof records found under this department.',
      );
    }

    if (_isGridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 78,
          crossAxisSpacing: 16,
          mainAxisSpacing: 14,
        ),
        itemCount: employees.length,
        itemBuilder: (context, index) {
          final emp = employees[index];
          final proofsCount = _allProofs.where((p) => _matchesEmployeeName(emp.name, p.employeeName)).length;

          return _buildFolderCard(
            title: emp.name,
            subtitle: '${emp.positionName.isNotEmpty ? emp.positionName : "Team Member"} • $proofsCount proof${proofsCount == 1 ? '' : 's'}',
            onTap: () {
              setState(() {
                _selectedEmployeeName = emp.name;
                _selectedEmployeeId = emp.id;
              });
            },
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            itemCount: employees.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (context, index) {
              final emp = employees[index];
              final proofsCount = _allProofs.where((p) => _matchesEmployeeName(emp.name, p.employeeName)).length;

              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFF59E0B), size: 30),
                title: Text(
                  emp.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  '${emp.positionName.isNotEmpty ? emp.positionName : "Team Member"} • $proofsCount proof${proofsCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                onTap: () {
                  setState(() {
                    _selectedEmployeeName = emp.name;
                    _selectedEmployeeId = emp.id;
                  });
                },
              );
            },
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PROOFS LEVEL
  // ---------------------------------------------------------------------------
  Widget _buildProofsLevel() {
    final proofs = _getFilteredProofsForSelectedEmployee();

    if (proofs.isEmpty) {
      return _buildEmptyState(
        title: 'No Photo Proofs for $_selectedEmployeeName',
        message: 'No photo proof submissions recorded for this employee with the current filters.',
      );
    }

    if (_isGridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisExtent: 330,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: proofs.length,
        itemBuilder: (context, index) {
          final proof = proofs[index];
          return _buildProofCard(proof);
        },
      );
    } else {
      return _buildProofsTableView(proofs);
    }
  }

  // ---------------------------------------------------------------------------
  // FOLDER CARD (Yellow folder, bold title, 3 dots)
  // ---------------------------------------------------------------------------
  Widget _buildFolderCard({
    required String title,
    String? tag,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Yellow Folder Icon
                const Icon(
                  Icons.folder,
                  color: Color(0xFFF59E0B),
                  size: 36,
                ),
                const SizedBox(width: 14),

                // Folder Title & optional Tag (Company) & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tag != null && tag.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.business_outlined,
                              size: 12,
                              color: Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0284C7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing 3-dots
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF0F172A)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'open') onTap();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 16, color: Color(0xFF64748B)),
                          SizedBox(width: 8),
                          Text('Open Folder', style: TextStyle(fontSize: 13)),
                        ],
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

  // ---------------------------------------------------------------------------
  // PHOTO PROOF CARD (Grid item matching Image 3)
  // ---------------------------------------------------------------------------
  Widget _buildProofCard(_PhotoProofRecord item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showProofDetailModal(item),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo with Timestamp Pill
              Expanded(
                flex: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      child: _buildThumbnailWidget(item),
                    ),

                    // Timestamp Pill (Top right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              item.timeDigits.isNotEmpty
                                  ? '${item.timeDigits} ${item.timePeriod}'
                                  : item.formattedTimeOnly,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Card details
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Employee Name
                      Text(
                        item.employeeName.isNotEmpty
                            ? item.employeeName
                            : 'Employee Submission',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Department / Store
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.storeName.isNotEmpty
                                  ? item.storeName
                                  : (_selectedDepartment ?? 'General'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),

                      // Geolocation text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.locationText.isNotEmpty
                                  ? item.locationText
                                  : (item.latitude != null && item.longitude != null
                                      ? '${item.latitude!.toStringAsFixed(4)}, ${item.longitude!.toStringAsFixed(4)}'
                                      : 'No GPS data'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Date label and "View Details >"
                      Row(
                        children: [
                          Text(
                            item.dateFormatted.isNotEmpty
                                ? item.dateFormatted
                                : item.formattedDateOnly,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'View Details >',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROOFS DATA TABLE VIEW (List view)
  // ---------------------------------------------------------------------------
  Widget _buildProofsTableView(List<_PhotoProofRecord> proofs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            horizontalMargin: 16,
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('Photo', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Department / Store', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: proofs.map((item) {
              return DataRow(
                cells: [
                  DataCell(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: _buildThumbnailWidget(item),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      item.employeeName.isNotEmpty ? item.employeeName : '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      item.storeName.isNotEmpty ? item.storeName : (_selectedDepartment ?? 'General'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      item.formattedTimeLabel,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        item.locationText.isNotEmpty ? item.locationText : '—',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    ElevatedButton(
                      onPressed: () => _showProofDetailModal(item),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1D4ED8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // THUMBNAILS & DETAIL MODAL
  // ---------------------------------------------------------------------------
  Widget _buildThumbnailWidget(_PhotoProofRecord proof) {
    final photoUri = proof.resolvedPhotoUrl;
    if (photoUri.isEmpty) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: Icon(Icons.photo_outlined, size: 32, color: Colors.white38),
        ),
      );
    }

    if (photoUri.startsWith('data:image')) {
      try {
        final commaIndex = photoUri.indexOf(',');
        final base64String = commaIndex != -1 ? photoUri.substring(commaIndex + 1) : photoUri;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    }

    return Image.network(
      photoUri,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: const Color(0xFFF1F5F9),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF94A3B8)),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, size: 28, color: Color(0xFF94A3B8)),
      ),
    );
  }

  void _showProofDetailModal(_PhotoProofRecord proof) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        child: Container(
          width: 780,
          constraints: const BoxConstraints(maxHeight: 720),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: HygColors.panel,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proof.employeeName.isNotEmpty
                                ? proof.employeeName
                                : 'Photo Proof Detail',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${proof.storeName.isNotEmpty ? proof.storeName : (_selectedDepartment ?? "General")} • ${proof.formattedTimeLabel}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Image & details
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo Preview
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 460),
                            color: const Color(0xFF0F172A),
                            child: _buildFullPhotoWidget(proof),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Metadata column
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailItem(
                              icon: Icons.person_outline,
                              title: 'Employee Name',
                              value: proof.employeeName.isNotEmpty
                                  ? proof.employeeName
                                  : '—',
                            ),
                            const SizedBox(height: 14),
                            _buildDetailItem(
                              icon: Icons.storefront_outlined,
                              title: 'Store / Department',
                              value: proof.storeName.isNotEmpty
                                  ? proof.storeName
                                  : (_selectedDepartment ?? '—'),
                            ),
                            const SizedBox(height: 14),
                            _buildDetailItem(
                              icon: Icons.access_time,
                              title: 'Capture Timestamp',
                              value: proof.formattedTimeLabel,
                            ),
                            const SizedBox(height: 14),
                            _buildDetailItem(
                              icon: Icons.location_on_outlined,
                              title: 'Geolocation Address',
                              value: proof.locationText.isNotEmpty
                                  ? proof.locationText
                                  : (proof.latitude != null && proof.longitude != null
                                      ? 'Lat: ${proof.latitude!.toStringAsFixed(5)}, Long: ${proof.longitude!.toStringAsFixed(5)}'
                                      : 'No GPS data recorded'),
                            ),
                            if (proof.latitude != null && proof.longitude != null) ...[
                              const SizedBox(height: 14),
                              _buildDetailItem(
                                icon: Icons.map_outlined,
                                title: 'Coordinates',
                                value: '${proof.latitude!.toStringAsFixed(5)}, ${proof.longitude!.toStringAsFixed(5)}',
                              ),
                            ],
                            if (proof.driveWebViewLink.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: proof.driveWebViewLink));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Google Drive link copied to clipboard!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2563EB),
                                  side: const BorderSide(color: Color(0xFF2563EB)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.cloud_outlined, size: 16),
                                label: const Text(
                                  'Copy Google Drive Link',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HygColors.ink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HygColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullPhotoWidget(_PhotoProofRecord proof) {
    final photoUri = proof.resolvedPhotoUrl;
    if (photoUri.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38),
              SizedBox(height: 10),
              Text('No image available', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (photoUri.startsWith('data:image')) {
      try {
        final commaIndex = photoUri.indexOf(',');
        final base64String = commaIndex != -1 ? photoUri.substring(commaIndex + 1) : photoUri;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildImageErrorWidget(),
        );
      } catch (_) {
        return _buildImageErrorWidget();
      }
    }

    return Image.network(
      photoUri,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _buildImageErrorWidget(),
    );
  }

  Widget _buildImageErrorWidget() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Colors.white38),
            SizedBox(height: 10),
            Text('Failed to load image', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_outlined,
              size: 48,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: HygColors.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: HygColors.ink,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DATA MODEL
// ---------------------------------------------------------------------------
class _PhotoProofRecord {
  const _PhotoProofRecord({
    required this.id,
    required this.photoUrl,
    required this.timestamp,
    required this.timeDigits,
    required this.timePeriod,
    required this.dateFormatted,
    required this.dayFormatted,
    required this.locationText,
    required this.employeeName,
    required this.employeeId,
    required this.storeName,
    required this.driveFileId,
    required this.driveWebViewLink,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String photoUrl;
  final String timestamp;
  final String timeDigits;
  final String timePeriod;
  final String dateFormatted;
  final String dayFormatted;
  final String locationText;
  final String employeeName;
  final String employeeId;
  final String storeName;
  final String driveFileId;
  final String driveWebViewLink;
  final double? latitude;
  final double? longitude;

  factory _PhotoProofRecord.fromMap(Map<String, dynamic> map) {
    return _PhotoProofRecord(
      id: map['id']?.toString() ?? '',
      photoUrl: map['photo_url']?.toString() ?? '',
      timestamp: map['timestamp']?.toString() ?? map['created_at']?.toString() ?? '',
      timeDigits: map['time_digits']?.toString() ?? '',
      timePeriod: map['time_period']?.toString() ?? '',
      dateFormatted: map['date_formatted']?.toString() ?? '',
      dayFormatted: map['day_formatted']?.toString() ?? '',
      locationText: map['location_text']?.toString() ?? '',
      employeeName: map['employee_name']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      storeName: map['store_name']?.toString() ?? '',
      driveFileId: map['drive_file_id']?.toString() ?? '',
      driveWebViewLink: map['drive_web_view_link']?.toString() ?? '',
      latitude: _toDouble(map['latitude']),
      longitude: _toDouble(map['longitude']),
    );
  }

  static double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }

  String get resolvedPhotoUrl {
    if (photoUrl.isNotEmpty) return photoUrl;
    if (driveFileId.isNotEmpty) {
      return 'https://lh3.googleusercontent.com/d/$driveFileId';
    }
    if (driveWebViewLink.isNotEmpty) return driveWebViewLink;
    return '';
  }

  DateTime? get parsedDateTime {
    if (timestamp.isEmpty) return null;
    try {
      return DateTime.parse(timestamp);
    } catch (_) {
      return null;
    }
  }

  String get isoDate {
    final dt = parsedDateTime;
    if (dt == null) return '';
    final ph = dt.toUtc().add(const Duration(hours: 8));
    return '${ph.year}-${ph.month.toString().padLeft(2, '0')}-${ph.day.toString().padLeft(2, '0')}';
  }

  String get formattedTimeLabel {
    if (dateFormatted.isNotEmpty && timeDigits.isNotEmpty) {
      return '$dateFormatted • $timeDigits $timePeriod';
    }
    final dt = parsedDateTime;
    if (dt == null) return timestamp;
    final ph = dt.toUtc().add(const Duration(hours: 8));
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = months[ph.month - 1];
    final d = ph.day.toString().padLeft(2, '0');
    final y = ph.year;
    final hour12 = ph.hour == 0 ? 12 : (ph.hour > 12 ? ph.hour - 12 : ph.hour);
    final min = ph.minute.toString().padLeft(2, '0');
    final ampm = ph.hour >= 12 ? 'PM' : 'AM';
    return '$m $d, $y • $hour12:$min $ampm';
  }

  String get formattedDateOnly {
    final dt = parsedDateTime;
    if (dt == null) return '';
    final ph = dt.toUtc().add(const Duration(hours: 8));
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[ph.month - 1]} ${ph.day}, ${ph.year}';
  }

  String get formattedTimeOnly {
    final dt = parsedDateTime;
    if (dt == null) return '';
    final ph = dt.toUtc().add(const Duration(hours: 8));
    final hour12 = ph.hour == 0 ? 12 : (ph.hour > 12 ? ph.hour - 12 : ph.hour);
    final min = ph.minute.toString().padLeft(2, '0');
    final ampm = ph.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$min $ampm';
  }
}
