part of '../main.dart';

class StoresHeader extends StatelessWidget {
  const StoresHeader({required this.onAddStore, super.key});
  final VoidCallback onAddStore;

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
          const Icon(
            Icons.storefront_outlined,
            color: HygColors.goldStrong,
            size: 42,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stores', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'Create and manage company stores used in employee profiles.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
            ),
            onPressed: onAddStore,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Store'),
          ),
        ],
      ),
    );
  }
}

class AddStoreDialog extends StatefulWidget {
  const AddStoreDialog({this.store, super.key});
  final StorePreview? store;

  @override
  State<AddStoreDialog> createState() => _AddStoreDialogState();
}

class _AddStoreDialogState extends State<AddStoreDialog> {
  final _nameController = TextEditingController();
  var _company = 'Select';
  var _cluster = 'Unassigned';
  var _companies = <String>[];
  var _clusters = <ClusterPreview>[];
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store != null) {
      _nameController.text = store.name;
      _company = store.companyName;
      _cluster = store.clusterName.isEmpty ? 'Unassigned' : store.clusterName;
    }
    _loadFormOptions();
  }

  Future<void> _loadFormOptions() async {
    try {
      final companies = await CompanyDirectoryService.loadCompanies();
      final clusters = await ClusterDirectoryService.loadClusters();
      if (!mounted) return;
      setState(() {
        _companies =
            companies
                .where((company) => company.status == 'active')
                .map((company) => company.name)
                .toList()
              ..sort();
        _clusters = clusters;
        if (widget.store == null && _companies.length == 1 && (_company == 'Select' || _company.isEmpty)) {
          _company = _companies.first;
        }
        _normalizeClusterSelection();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<String> get _clusterOptions {
    final companyClusters =
        _clusters
            .where((cluster) => cluster.companyName == _company)
            .map((cluster) => cluster.name)
            .toList()
          ..sort();
    return ['Unassigned', ...companyClusters];
  }

  void _normalizeClusterSelection() {
    if (!_clusterOptions.contains(_cluster)) {
      _cluster = 'Unassigned';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _company == 'Select') {
      setState(() => _error = 'Store name and company are required.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (widget.store == null) {
        await StoreDirectoryService.createStore(
          name: name,
          companyName: _company,
          clusterName: _cluster,
        );
      } else {
        await StoreDirectoryService.updateStore(
          id: widget.store!.id,
          name: name,
          companyName: _company,
          clusterName: _cluster,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.store == null ? 'Add Store' : 'Edit Store'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModalTextField(
              controller: _nameController,
              label: 'Store Name',
              required: true,
              hint: 'e.g. Main Branch',
            ),
            const SizedBox(height: 14),
            ModalSelectField(
              label: 'Company',
              required: true,
              value: _company,
              options: ['Select', ..._companies],
              onChanged: (value) => setState(() {
                _company = value;
                _normalizeClusterSelection();
              }),
            ),
            const SizedBox(height: 14),
            ModalSelectField(
              label: 'Cluster',
              value: _cluster,
              options: _clusterOptions,
              onChanged: (value) => setState(() => _cluster = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: HygTypography.body.copyWith(
                  color: const Color(0xFFDC2626),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Save Store'),
        ),
      ],
    );
  }
}

class StoresPanel extends StatefulWidget {
  const StoresPanel({
    required this.stores,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditStore,
    required this.onDeleteStore,
    this.canEditAndDelete = true,
    super.key,
  });

  final List<StorePreview> stores;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<StorePreview> onEditStore;
  final ValueChanged<StorePreview> onDeleteStore;
  final bool canEditAndDelete;

  @override
  State<StoresPanel> createState() => _StoresPanelState();
}

class _StoresPanelState extends State<StoresPanel> {
  static const _allCompanies = 'All Companies';

  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCompany = _allCompanies;
  List<String> _dbCompanies = [];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    try {
      final rows = await CompanyDirectoryService.loadCompanies();
      if (!mounted) return;
      setState(() {
        _dbCompanies = rows
            .where((c) => c.status == 'active')
            .map((c) => c.name.trim())
            .where((n) => n.isNotEmpty)
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _companyOptions {
    final set = <String>{};
    for (final c in _dbCompanies) {
      set.add(c);
    }
    for (final s in widget.stores) {
      final name = s.companyName.trim();
      if (name.isNotEmpty && name != '-') {
        set.add(name);
      }
    }
    final sorted = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...sorted];
  }

  List<StorePreview> get _filteredStores {
    final q = _query.trim().toLowerCase();
    return widget.stores.where((store) {
      if (_selectedCompany != _allCompanies) {
        if (store.companyName.trim().toLowerCase() !=
            _selectedCompany.trim().toLowerCase()) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        final matches = store.name.toLowerCase().contains(q) ||
            store.companyName.toLowerCase().contains(q) ||
            store.clusterName.toLowerCase().contains(q);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStores;

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
                flex: 5,
                child: TableSearchField(
                  controller: _searchController,
                  hint: 'Search store name or cluster',
                  onChanged: (val) => setState(() => _query = val),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TableFilterDropdown(
                  value: _selectedCompany,
                  options: _companyOptions,
                  prefixIcon: Icons.business_outlined,
                  onChanged: (val) => setState(() {
                    _selectedCompany = val ?? _allCompanies;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  _loadCompanies();
                  widget.onRefresh();
                },
                icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _StoreTableHeader(),
          const SizedBox(height: 8),
          if (widget.isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading stores',
              message: 'Getting store records from Supabase.',
            )
          else if (widget.error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load stores',
              message: widget.error!,
              actionLabel: 'Retry',
              onAction: widget.onRefresh,
            )
          else if (widget.stores.isEmpty)
            EmployeesStateMessage(
              icon: Icons.storefront_outlined,
              title: 'No stores found',
              message: 'No store records are available yet.',
              actionLabel: 'Refresh',
              onAction: widget.onRefresh,
            )
          else if (filtered.isEmpty)
            EmployeesStateMessage(
              icon: Icons.search_off,
              title: 'No matching stores',
              message: _selectedCompany != _allCompanies
                  ? 'No stores found for "$_selectedCompany"${_query.isNotEmpty ? ' matching "$_query"' : ''}.'
                  : 'Try another store name or filter.',
              actionLabel: 'Reset filters',
              onAction: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedCompany = _allCompanies;
                });
              },
            )
          else
            ...filtered.map(
              (store) => _StoreRow(
                store: store,
                onEdit: () => widget.onEditStore(store),
                onDelete: () => widget.onDeleteStore(store),
                canEditAndDelete: widget.canEditAndDelete,
              ),
            ),
        ],
      ),
    );
  }
}

class _StoreTableHeader extends StatelessWidget {
  const _StoreTableHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(flex: 3, child: HeaderLabel('STORE')),
      Expanded(flex: 3, child: HeaderLabel('COMPANY')),
      Expanded(flex: 3, child: HeaderLabel('CLUSTER')),
      Expanded(flex: 2, child: HeaderLabel('EMPLOYEES')),
      Expanded(flex: 2, child: HeaderLabel('CREATED')),
      SizedBox(width: 88),
    ],
  );
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.store,
    required this.onEdit,
    required this.onDelete,
    this.canEditAndDelete = true,
  });
  final StorePreview store;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canEditAndDelete;

  @override
  Widget build(BuildContext context) => Container(
    height: 58,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border.all(color: HygColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(flex: 3, child: BodyCell(store.name)),
        Expanded(flex: 3, child: BodyCell(store.companyName)),
        Expanded(flex: 3, child: BodyCell(store.clusterName)),
        Expanded(flex: 2, child: BodyCell(store.employeeCount.toString())),
        Expanded(flex: 2, child: BodyCell(store.created)),
        SizedBox(
          width: 88,
          child: canEditAndDelete
              ? Row(
                  children: [
                    IconButton(
                      tooltip: 'Edit store',
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete store',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                    ),
                  ],
                )
              : const SizedBox(),
        ),
      ],
    ),
  );
}
