part of '../main.dart';

class ClustersHeader extends StatelessWidget {
  const ClustersHeader({
    required this.onAddCluster,
    required this.onAddArea,
    super.key,
  });
  final VoidCallback onAddCluster;
  final VoidCallback onAddArea;

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
          const Icon(Icons.hub_outlined, color: HygColors.goldStrong, size: 42),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cluster / Area', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'Create and manage store clusters and areas for approval routing.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onAddArea,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Area'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: HygColors.gold,
                  foregroundColor: HygColors.ink,
                ),
                onPressed: onAddCluster,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Cluster'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AddAreaDialog extends StatefulWidget {
  const AddAreaDialog({this.area, super.key});
  final AreaPreview? area;

  @override
  State<AddAreaDialog> createState() => _AddAreaDialogState();
}

class _AddAreaDialogState extends State<AddAreaDialog> {
  final _nameController = TextEditingController();
  var _clusters = <ClusterPreview>[];
  final _selectedClusterIds = <String>{};
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    if (area != null) {
      _nameController.text = area.name;
    }
    _loadClusters();
  }

  Future<void> _loadClusters() async {
    try {
      final rows = await ClusterDirectoryService.loadClusters();
      if (!mounted) return;
      setState(() {
        _clusters = [...rows]..sort((a, b) => a.name.compareTo(b.name));
        final area = widget.area;
        if (area != null && _selectedClusterIds.isEmpty) {
          final areaClusterNames = area.clusterNames
              .split(',')
              .map((name) => name.trim().toLowerCase())
              .where((name) => name.isNotEmpty)
              .toSet();
          _selectedClusterIds.addAll(
            _clusters
                .where(
                  (cluster) => areaClusterNames.contains(
                    cluster.name.trim().toLowerCase(),
                  ),
                )
                .map((cluster) => cluster.id),
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedClusterIds.isEmpty) {
      setState(
        () => _error = 'Area name and at least one cluster are required.',
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (widget.area == null) {
        await AreaDirectoryService.createArea(
          name: name,
          clusterIds: _selectedClusterIds.toList(),
        );
      } else {
        await AreaDirectoryService.updateArea(
          id: widget.area!.id,
          name: name,
          clusterIds: _selectedClusterIds.toList(),
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
      title: Text(widget.area == null ? 'Add Area' : 'Edit Area'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModalTextField(
              controller: _nameController,
              label: 'Area Name',
              required: true,
              hint: 'e.g. Area 1',
            ),
            const SizedBox(height: 14),
            _ClusterChecklistField(
              clusters: _clusters,
              selectedClusterIds: _selectedClusterIds,
              onChanged: (clusterId, selected) {
                setState(() {
                  if (selected) {
                    _selectedClusterIds.add(clusterId);
                  } else {
                    _selectedClusterIds.remove(clusterId);
                  }
                });
              },
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
          child: Text(_isSaving ? 'Saving...' : 'Save Area'),
        ),
      ],
    );
  }
}

class AddClusterDialog extends StatefulWidget {
  const AddClusterDialog({this.cluster, super.key});
  final ClusterPreview? cluster;

  @override
  State<AddClusterDialog> createState() => _AddClusterDialogState();
}

class _AddClusterDialogState extends State<AddClusterDialog> {
  final _nameController = TextEditingController();
  var _stores = <StorePreview>[];
  final _selectedStoreIds = <String>{};
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cluster = widget.cluster;
    if (cluster != null) {
      _nameController.text = cluster.name;
    }
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final rows = await StoreDirectoryService.loadStores();
      if (!mounted) return;
      setState(() {
        _stores = [...rows]..sort((a, b) => a.name.compareTo(b.name));
        final cluster = widget.cluster;
        if (cluster != null && _selectedStoreIds.isEmpty) {
          final clusterName = cluster.name.trim().toLowerCase();
          _selectedStoreIds.addAll(
            _stores
                .where(
                  (store) =>
                      store.clusterName.trim().toLowerCase() == clusterName,
                )
                .map((store) => store.id),
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedStoreIds.isEmpty) {
      setState(
        () => _error = 'Cluster name and at least one store are required.',
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (widget.cluster == null) {
        await ClusterDirectoryService.createCluster(
          name: name,
          storeIds: _selectedStoreIds.toList(),
        );
      } else {
        await ClusterDirectoryService.updateCluster(
          id: widget.cluster!.id,
          name: name,
          storeIds: _selectedStoreIds.toList(),
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
      title: Text(widget.cluster == null ? 'Add Cluster' : 'Edit Cluster'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModalTextField(
              controller: _nameController,
              label: 'Cluster Name',
              required: true,
              hint: 'e.g. North Luzon',
            ),
            const SizedBox(height: 14),
            _StoreChecklistField(
              stores: _stores,
              selectedStoreIds: _selectedStoreIds,
              currentClusterName: widget.cluster?.name,
              onChanged: (storeId, selected) {
                setState(() {
                  if (selected) {
                    _selectedStoreIds.add(storeId);
                  } else {
                    _selectedStoreIds.remove(storeId);
                  }
                });
              },
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
          child: Text(_isSaving ? 'Saving...' : 'Save Cluster'),
        ),
      ],
    );
  }
}

class ClustersPanel extends StatelessWidget {
  const ClustersPanel({
    required this.clusters,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditCluster,
    required this.onDeleteCluster,
    super.key,
  });

  final List<ClusterPreview> clusters;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<ClusterPreview> onEditCluster;
  final ValueChanged<ClusterPreview> onDeleteCluster;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: FilterBox(
                  icon: Icons.search,
                  label: 'Search cluster or store',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _ClusterTableHeader(),
          const SizedBox(height: 8),
          if (isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading clusters',
              message: 'Getting cluster records from Supabase.',
            )
          else if (error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load clusters',
              message: error!,
              actionLabel: 'Retry',
              onAction: onRefresh,
            )
          else if (clusters.isEmpty)
            EmployeesStateMessage(
              icon: Icons.hub_outlined,
              title: 'No clusters found',
              message: 'No cluster records are available yet.',
              actionLabel: 'Refresh',
              onAction: onRefresh,
            )
          else
            ...clusters.map(
              (cluster) => _ClusterRow(
                cluster: cluster,
                onEdit: () => onEditCluster(cluster),
                onDelete: () => onDeleteCluster(cluster),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClusterTableHeader extends StatelessWidget {
  const _ClusterTableHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(flex: 3, child: HeaderLabel('CLUSTER')),
      Expanded(flex: 5, child: HeaderLabel('STORES')),
      Expanded(flex: 2, child: HeaderLabel('COUNT')),
      Expanded(flex: 2, child: HeaderLabel('CREATED')),
      SizedBox(width: 88),
    ],
  );
}

class _ClusterRow extends StatelessWidget {
  const _ClusterRow({
    required this.cluster,
    required this.onEdit,
    required this.onDelete,
  });
  final ClusterPreview cluster;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
        Expanded(flex: 3, child: BodyCell(cluster.name)),
        Expanded(flex: 5, child: BodyCell(cluster.storeNames)),
        Expanded(flex: 2, child: BodyCell(cluster.storeCount.toString())),
        Expanded(flex: 2, child: BodyCell(cluster.created)),
        SizedBox(
          width: 88,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Edit cluster',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Delete cluster',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AreasPanel extends StatelessWidget {
  const AreasPanel({
    required this.areas,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditArea,
    required this.onDeleteArea,
    super.key,
  });

  final List<AreaPreview> areas;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<AreaPreview> onEditArea;
  final ValueChanged<AreaPreview> onDeleteArea;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: FilterBox(
                  icon: Icons.search,
                  label: 'Search area or cluster',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AreaTableHeader(),
          const SizedBox(height: 8),
          if (isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading areas',
              message: 'Getting area records from Supabase.',
            )
          else if (error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load areas',
              message: error!,
              actionLabel: 'Retry',
              onAction: onRefresh,
            )
          else if (areas.isEmpty)
            EmployeesStateMessage(
              icon: Icons.account_tree_outlined,
              title: 'No areas found',
              message: 'No area records are available yet.',
              actionLabel: 'Refresh',
              onAction: onRefresh,
            )
          else
            ...areas.map(
              (area) => _AreaRow(
                area: area,
                onEdit: () => onEditArea(area),
                onDelete: () => onDeleteArea(area),
              ),
            ),
        ],
      ),
    );
  }
}

class _AreaTableHeader extends StatelessWidget {
  const _AreaTableHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(flex: 3, child: HeaderLabel('AREA')),
      Expanded(flex: 5, child: HeaderLabel('CLUSTERS')),
      Expanded(flex: 2, child: HeaderLabel('STORES')),
      Expanded(flex: 2, child: HeaderLabel('CREATED')),
      SizedBox(width: 88),
    ],
  );
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.area,
    required this.onEdit,
    required this.onDelete,
  });
  final AreaPreview area;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
        Expanded(flex: 3, child: BodyCell(area.name)),
        Expanded(flex: 5, child: BodyCell(area.clusterNames)),
        Expanded(flex: 2, child: BodyCell(area.storeCount.toString())),
        Expanded(flex: 2, child: BodyCell(area.created)),
        SizedBox(
          width: 88,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Edit area',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Delete area',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StoreChecklistField extends StatelessWidget {
  const _StoreChecklistField({
    required this.stores,
    required this.selectedStoreIds,
    required this.currentClusterName,
    required this.onChanged,
  });

  final List<StorePreview> stores;
  final Set<String> selectedStoreIds;
  final String? currentClusterName;
  final void Function(String storeId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel(label: 'Stores', required: true),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: HygColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: stores.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: BodyCell('No stores available'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: stores.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: HygColors.border),
                  itemBuilder: (context, index) {
                    final store = stores[index];
                    final selected = selectedStoreIds.contains(store.id);
                    final storeCluster = store.clusterName.trim().toLowerCase();
                    final currentCluster = currentClusterName
                        ?.trim()
                        .toLowerCase();
                    final canSelect =
                        selected ||
                        storeCluster == 'unassigned' ||
                        storeCluster == currentCluster;
                    return CheckboxListTile(
                      dense: true,
                      value: selected,
                      enabled: canSelect,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: HygColors.goldStrong,
                      title: Text(
                        store.name,
                        style: HygTypography.body.copyWith(
                          color: canSelect
                              ? HygColors.ink
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: store.clusterName == 'Unassigned'
                          ? null
                          : Text(
                              store.clusterName,
                              overflow: TextOverflow.ellipsis,
                              style: HygTypography.body.copyWith(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                      onChanged: canSelect
                          ? (value) => onChanged(store.id, value ?? false)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ClusterChecklistField extends StatelessWidget {
  const _ClusterChecklistField({
    required this.clusters,
    required this.selectedClusterIds,
    required this.onChanged,
  });

  final List<ClusterPreview> clusters;
  final Set<String> selectedClusterIds;
  final void Function(String clusterId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel(label: 'Clusters', required: true),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: HygColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: clusters.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: BodyCell('No clusters available'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: clusters.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: HygColors.border),
                  itemBuilder: (context, index) {
                    final cluster = clusters[index];
                    final selected = selectedClusterIds.contains(cluster.id);
                    return CheckboxListTile(
                      dense: true,
                      value: selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: HygColors.goldStrong,
                      title: Text(
                        cluster.name,
                        style: HygTypography.body.copyWith(
                          color: HygColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        cluster.storeNames,
                        overflow: TextOverflow.ellipsis,
                        style: HygTypography.body.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      onChanged: (value) =>
                          onChanged(cluster.id, value ?? false),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
