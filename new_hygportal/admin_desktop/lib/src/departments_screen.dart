part of '../main.dart';

class DepartmentsHeader extends StatelessWidget {
  const DepartmentsHeader({required this.onAddDepartment, super.key});

  final VoidCallback onAddDepartment;

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
            child: const Icon(Icons.account_tree, color: HygColors.goldStrong),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Departments', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'Create and manage custom departments used in employee profiles.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(150, 44),
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAddDepartment,
            icon: const Icon(Icons.account_tree, size: 18),
            label: const Text('Add Department'),
          ),
        ],
      ),
    );
  }
}

class AddDepartmentDialog extends StatefulWidget {
  const AddDepartmentDialog({this.department, super.key});

  final DepartmentPreview? department;

  @override
  State<AddDepartmentDialog> createState() => _AddDepartmentDialogState();
}

class _AddDepartmentDialogState extends State<AddDepartmentDialog> {
  final _nameController = TextEditingController();
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final department = widget.department;
    if (department != null) {
      _nameController.text = department.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveDepartment() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Department name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final department = widget.department;
      if (department == null) {
        await DepartmentDirectoryService.createDepartment(name);
      } else {
        await DepartmentDirectoryService.updateDepartment(
          id: department.id,
          name: name,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    final isEditing = widget.department != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_tree,
                      color: HygColors.goldStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Department' : 'Department Details',
                      style: HygTypography.pageTitle.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: Color(0xFF475569)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: HygColors.border),
              const SizedBox(height: 18),
              ModalTextField(
                controller: _nameController,
                label: 'Department Name',
                required: true,
                hint: 'e.g. IT',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: HygTypography.body.copyWith(
                    color: const Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 116,
                    height: 42,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: HygColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 176,
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: HygColors.gold,
                        foregroundColor: HygColors.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveDepartment,
                      icon: Icon(isEditing ? Icons.check : Icons.add, size: 16),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : (isEditing ? 'Update' : 'Save Department'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

class DepartmentDeleteDialog extends StatelessWidget {
  const DepartmentDeleteDialog({required this.department, super.key});

  final DepartmentPreview department;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFF97316),
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delete department?',
                                style: TextStyle(
                                  color: HygColors.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'This action cannot be undone.',
                                style: HygTypography.body.copyWith(
                                  color: const Color(0xFF475569),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                text: TextSpan(
                                  style: HygTypography.body.copyWith(
                                    color: HygColors.ink,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: 'Are you sure you want to delete ',
                                    ),
                                    TextSpan(
                                      text: '"${department.name}"',
                                      style: const TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const TextSpan(text: '?'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        border: Border.all(color: const Color(0xFFDCE7F3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(
                              Icons.info_outline,
                              color: Color(0xFF2563EB),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Departments with employee references cannot be deleted.',
                              style: HygTypography.body.copyWith(
                                color: const Color(0xFF475569),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'What happens next?',
                      style: TextStyle(
                        color: HygColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const DeleteDialogBullet(
                      'The department will be removed only if no employees reference it.',
                    ),
                    const SizedBox(height: 7),
                    const DeleteDialogBullet(
                      'Employee profiles and assignments will remain unchanged.',
                    ),
                    const SizedBox(height: 7),
                    const DeleteDialogBullet(
                      'You can create the department again later if needed.',
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 102,
                            height: 40,
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
                            width: 178,
                            height: 40,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(true),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text(
                                'Delete Department',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
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
}

class DeleteDialogBullet extends StatelessWidget {
  const DeleteDialogBullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF65A30D),
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: HygTypography.body.copyWith(color: const Color(0xFF334155)),
          ),
        ),
      ],
    );
  }
}

class DepartmentsPanel extends StatefulWidget {
  const DepartmentsPanel({
    required this.departments,
    required this.departmentPositions,
    required this.positions,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditDepartment,
    required this.onDeleteDepartment,
    required this.onAssignPosition,
    required this.onRemovePosition,
    super.key,
  });

  final List<DepartmentPreview> departments;
  final List<DepartmentPositionCatalogPreview> departmentPositions;
  final List<AdminPositionCatalogPreview> positions;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<DepartmentPreview> onEditDepartment;
  final ValueChanged<DepartmentPreview> onDeleteDepartment;
  final Future<void> Function(
    DepartmentPreview department,
    AdminPositionCatalogPreview position,
  )
  onAssignPosition;
  final Future<void> Function(
    DepartmentPreview department,
    AdminPositionCatalogPreview position,
  )
  onRemovePosition;

  @override
  State<DepartmentsPanel> createState() => _DepartmentsPanelState();
}

class _DepartmentsPanelState extends State<DepartmentsPanel> {
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DepartmentPreview> get _filteredDepartments {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.departments;
    return widget.departments
        .where((department) => department.name.toLowerCase().contains(query))
        .toList();
  }

  List<DepartmentPositionCatalogPreview> _assignedRows(String departmentId) {
    return widget.departmentPositions
        .where(
          (row) => row.departmentId == departmentId && row.positionId != null,
        )
        .toList();
  }

  Future<void> _openAssignmentDialog(DepartmentPreview department) async {
    final currentIds = _assignedRows(
      department.id,
    ).map((row) => row.positionId).whereType<String>().toSet();
    final selectedIds = await showDialog<Set<String>>(
      context: context,
      builder: (context) => DepartmentPositionAssignmentDialog(
        department: department,
        positions: widget.positions,
        selectedPositionIds: currentIds,
      ),
    );

    if (selectedIds == null) return;

    for (final position in widget.positions) {
      final wasAssigned = currentIds.contains(position.positionId);
      final shouldAssign = selectedIds.contains(position.positionId);
      if (!wasAssigned && shouldAssign) {
        await widget.onAssignPosition(department, position);
      } else if (wasAssigned && !shouldAssign) {
        await widget.onRemovePosition(department, position);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = _filteredDepartments;
    final totalEmployees = widget.departments.fold<int>(
      0,
      (sum, department) => sum + department.employeeCount,
    );

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
                child: _DirectorySearchField(
                  controller: _searchController,
                  hint: 'Search department name',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
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
          _DepartmentSummaryStrip(
            totalDepartments: widget.departments.length,
            totalPositions: widget.positions.length,
            totalEmployees: totalEmployees,
          ),
          const SizedBox(height: 14),
          if (widget.isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading departments',
              message: 'Getting department records from Supabase.',
            )
          else if (widget.error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load departments',
              message: widget.error!,
              actionLabel: 'Retry',
              onAction: widget.onRefresh,
            )
          else if (widget.departments.isEmpty)
            EmployeesStateMessage(
              icon: Icons.account_tree_outlined,
              title: 'No departments found',
              message: 'No department records are available yet.',
              actionLabel: 'Refresh',
              onAction: widget.onRefresh,
            )
          else if (departments.isEmpty)
            EmployeesStateMessage(
              icon: Icons.search_off,
              title: 'No matching departments',
              message: 'Try another department name.',
              actionLabel: 'Clear',
              onAction: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                const spacing = 10.0;
                final cardWidth =
                    (constraints.maxWidth - (columns - 1) * spacing) / columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final department in departments)
                      SizedBox(
                        width: cardWidth,
                        child: DepartmentDirectoryCard(
                          department: department,
                          assignedRows: _assignedRows(department.id),
                          onEdit: () => widget.onEditDepartment(department),
                          onDelete: () => widget.onDeleteDepartment(department),
                          onManagePositions: () =>
                              _openAssignmentDialog(department),
                          onRemovePosition: (positionId) {
                            final position = widget.positions.firstWhere(
                              (item) => item.positionId == positionId,
                            );
                            unawaited(
                              widget.onRemovePosition(department, position),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DirectorySearchField extends StatelessWidget {
  const _DirectorySearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
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
          hintText: hint,
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

class _DepartmentSummaryStrip extends StatelessWidget {
  const _DepartmentSummaryStrip({
    required this.totalDepartments,
    required this.totalPositions,
    required this.totalEmployees,
  });

  final int totalDepartments;
  final int totalPositions;
  final int totalEmployees;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DirectoryStatCard(
          icon: Icons.account_tree_outlined,
          label: 'Departments',
          value: totalDepartments.toString(),
        ),
        const SizedBox(width: 10),
        _DirectoryStatCard(
          icon: Icons.badge_outlined,
          label: 'Positions',
          value: totalPositions.toString(),
        ),
        const SizedBox(width: 10),
        _DirectoryStatCard(
          icon: Icons.people_alt_outlined,
          label: 'Employees',
          value: totalEmployees.toString(),
        ),
      ],
    );
  }
}

class _DirectoryStatCard extends StatelessWidget {
  const _DirectoryStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: HygColors.goldStrong, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(value, style: HygTypography.pageTitle.copyWith(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class DepartmentDirectoryCard extends StatelessWidget {
  const DepartmentDirectoryCard({
    required this.department,
    required this.assignedRows,
    required this.onEdit,
    required this.onDelete,
    required this.onManagePositions,
    required this.onRemovePosition,
    super.key,
  });

  final DepartmentPreview department;
  final List<DepartmentPositionCatalogPreview> assignedRows;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManagePositions;
  final ValueChanged<String> onRemovePosition;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.account_tree,
                  color: HygColors.goldStrong,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  department.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: HygColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit department',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Assign positions',
                onPressed: onManagePositions,
                icon: const Icon(
                  Icons.playlist_add_check,
                  color: Color(0xFF854D0E),
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Delete department',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DepartmentAssignedPositions(
            assignedRows: assignedRows,
            onRemovePosition: onRemovePosition,
            onManagePositions: onManagePositions,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DirectoryMiniMetric(
                  label: 'Employees',
                  value: department.employeeCount.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DirectoryMiniMetric(
                  label: 'Positions',
                  value: assignedRows.length.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DepartmentAssignedPositions extends StatelessWidget {
  const _DepartmentAssignedPositions({
    required this.assignedRows,
    required this.onRemovePosition,
    required this.onManagePositions,
  });

  final List<DepartmentPositionCatalogPreview> assignedRows;
  final ValueChanged<String> onRemovePosition;
  final VoidCallback onManagePositions;

  @override
  Widget build(BuildContext context) {
    if (assignedRows.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onManagePositions,
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFFDE68A)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Assign positions',
            style: HygTypography.body.copyWith(
              color: const Color(0xFF854D0E),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final row in assignedRows)
          _AssignedPositionChip(
            row: row,
            onRemove: () => onRemovePosition(row.positionId!),
          ),
      ],
    );
  }
}

class _AssignedPositionChip extends StatelessWidget {
  const _AssignedPositionChip({required this.row, required this.onRemove});

  final DepartmentPositionCatalogPreview row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF854D0E)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              row.positionName ?? 'Unnamed Position',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            row.employeeCount.toString(),
            style: HygTypography.body.copyWith(
              color: const Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          IconButton(
            tooltip: 'Remove position',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: Color(0xFFDC2626), size: 14),
          ),
        ],
      ),
    );
  }
}

class _DirectoryMiniMetric extends StatelessWidget {
  const _DirectoryMiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: HygTypography.body.copyWith(
                color: const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DepartmentPositionAssignmentDialog extends StatefulWidget {
  const DepartmentPositionAssignmentDialog({
    required this.department,
    required this.positions,
    required this.selectedPositionIds,
    super.key,
  });

  final DepartmentPreview department;
  final List<AdminPositionCatalogPreview> positions;
  final Set<String> selectedPositionIds;

  @override
  State<DepartmentPositionAssignmentDialog> createState() =>
      _DepartmentPositionAssignmentDialogState();
}

class _DepartmentPositionAssignmentDialogState
    extends State<DepartmentPositionAssignmentDialog> {
  late final Set<String> _selected = {...widget.selectedPositionIds};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: const Color(0xFFF7EFE1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: HygColors.gold,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_tree,
                      color: HygColors.ink,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.department.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HygTypography.pageTitle.copyWith(fontSize: 24),
                        ),
                        Text(
                          'Assign positions to this department',
                          style: HygTypography.body.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (widget.positions.isEmpty)
                const EmployeesStateMessage(
                  icon: Icons.badge_outlined,
                  title: 'No positions available',
                  message: 'Create positions first, then assign them here.',
                )
              else
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 2 : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        itemCount: widget.positions.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: columns == 2 ? 3.8 : 5.0,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) {
                          final position = widget.positions[index];
                          final selected = _selected.contains(
                            position.positionId,
                          );
                          return _DepartmentPositionToggle(
                            position: position,
                            selected: selected,
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selected.remove(position.positionId);
                                } else {
                                  _selected.add(position.positionId);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF806600),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                      ),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('Save Positions'),
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

class _DepartmentPositionToggle extends StatelessWidget {
  const _DepartmentPositionToggle({
    required this.position,
    required this.selected,
    required this.onTap,
  });

  final AdminPositionCatalogPreview position;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFDE9A7) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFF6C400) : HygColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Icon(
                  selected ? Icons.check : Icons.badge_outlined,
                  color: selected
                      ? const Color(0xFF6B5600)
                      : const Color(0xFF64748B),
                  size: 17,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  position.positionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: HygColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                position.employeeCount.toString(),
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DepartmentTableHeader extends StatelessWidget {
  const DepartmentTableHeader({super.key});

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
          Expanded(flex: 4, child: HeaderLabel('DEPARTMENT')),
          Expanded(flex: 2, child: HeaderLabel('EMPLOYEES')),
          Expanded(flex: 2, child: HeaderLabel('CREATED')),
          Expanded(flex: 2, child: HeaderLabel('UPDATED')),
          SizedBox(
            width: 86,
            child: Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class DepartmentRow extends StatelessWidget {
  const DepartmentRow({
    required this.department,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final DepartmentPreview department;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HygColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF2FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.account_tree,
                    color: Color(0xFF4338CA),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    department.name,
                    overflow: TextOverflow.ellipsis,
                    style: HygTypography.tablePrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: BodyCell(department.employeeCount.toString()),
          ),
          Expanded(flex: 2, child: BodyCell(department.created)),
          Expanded(flex: 2, child: BodyCell(department.updated)),
          SizedBox(
            width: 86,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit department',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete department',
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
}
