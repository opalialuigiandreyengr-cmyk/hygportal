part of '../main.dart';

class PositionsHeader extends StatelessWidget {
  const PositionsHeader({required this.onAddPosition, super.key});

  final VoidCallback onAddPosition;

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
            child: const Icon(Icons.badge, color: HygColors.goldStrong),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Positions', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'View employee positions and authority levels already configured in the database.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: HygColors.gold,
                foregroundColor: HygColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              onPressed: onAddPosition,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Position'),
            ),
          ),
        ],
      ),
    );
  }
}

class PositionsPanel extends StatelessWidget {
  const PositionsPanel({
    required this.positions,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditPosition,
    required this.onDeletePosition,
    super.key,
  });

  final List<PositionPreview> positions;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<PositionPreview> onEditPosition;
  final ValueChanged<PositionPreview> onDeletePosition;

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
          Row(
            children: [
              const Expanded(
                flex: 4,
                child: FilterBox(
                  icon: Icons.search,
                  label: 'Search position name',
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const PositionTableHeader(),
          const SizedBox(height: 8),
          if (isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading positions',
              message: 'Getting position records from Supabase.',
            )
          else if (error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load positions',
              message: error!,
              actionLabel: 'Retry',
              onAction: onRefresh,
            )
          else if (positions.isEmpty)
            EmployeesStateMessage(
              icon: Icons.badge_outlined,
              title: 'No positions found',
              message: 'No position records are available yet.',
              actionLabel: 'Refresh',
              onAction: onRefresh,
            )
          else
            ...positions.map(
              (position) => PositionRow(
                position: position,
                onEdit: () => onEditPosition(position),
                onDelete: () => onDeletePosition(position),
              ),
            ),
        ],
      ),
    );
  }
}

class PositionTableHeader extends StatelessWidget {
  const PositionTableHeader({super.key});

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
          Expanded(flex: 4, child: HeaderLabel('POSITION')),
          Expanded(flex: 2, child: HeaderLabel('AUTHORITY LEVEL')),
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

class AddPositionDialog extends StatefulWidget {
  const AddPositionDialog({this.position, super.key});

  final PositionPreview? position;

  @override
  State<AddPositionDialog> createState() => _AddPositionDialogState();
}

class _AddPositionDialogState extends State<AddPositionDialog> {
  final _nameController = TextEditingController();
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final position = widget.position;
    if (position != null) {
      _nameController.text = position.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _savePosition() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Position name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final position = widget.position;
      if (position == null) {
        await PositionDirectoryService.createPosition(name);
      } else {
        await PositionDirectoryService.updatePosition(
          id: position.id,
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
    final isEditing = widget.position != null;

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
                    child: const Icon(Icons.badge, color: HygColors.goldStrong),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Position' : 'Position Details',
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
                label: 'Position Name',
                required: true,
                hint: 'e.g. Department Manager',
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
                    width: 164,
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
                      onPressed: _isSaving ? null : _savePosition,
                      icon: Icon(isEditing ? Icons.check : Icons.add, size: 16),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : (isEditing ? 'Update' : 'Save Position'),
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

class PositionDeleteDialog extends StatelessWidget {
  const PositionDeleteDialog({required this.position, super.key});

  final PositionPreview position;

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
                          'Delete position?',
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
                                text: '"${position.name}"',
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
                        'Positions with employee or request references cannot be deleted.',
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
                'The position will be removed only if it is not in use.',
              ),
              const SizedBox(height: 7),
              const DeleteDialogBullet(
                'Employee profiles and request history will remain unchanged.',
              ),
              const SizedBox(height: 7),
              const DeleteDialogBullet(
                'You can create the position again later if needed.',
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
                      width: 160,
                      height: 40,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete Position'),
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

class PositionRow extends StatelessWidget {
  const PositionRow({
    required this.position,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final PositionPreview position;
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
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.badge,
                    color: Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    position.name,
                    overflow: TextOverflow.ellipsis,
                    style: HygTypography.tablePrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: BodyCell('Level ${position.authorityLevel}'),
          ),
          Expanded(flex: 2, child: BodyCell(position.employeeCount.toString())),
          Expanded(flex: 2, child: BodyCell(position.created)),
          Expanded(flex: 2, child: BodyCell(position.updated)),
          SizedBox(
            width: 86,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit position',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete position',
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
