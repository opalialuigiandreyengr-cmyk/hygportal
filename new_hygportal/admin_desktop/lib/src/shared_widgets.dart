part of '../main.dart';

class EmployeesStateMessage extends StatelessWidget {
  const EmployeesStateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: HygColors.muted, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: HygColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HygColors.muted,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class FilterBox extends StatelessWidget {
  const FilterBox({required this.label, this.icon, this.trailing, super.key});

  final String label;
  final IconData? icon;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: const Color(0xFF64748B), size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: HygTypography.body.copyWith(
                color: const Color(0xFF475569),
              ),
            ),
          ),
          if (trailing != null)
            Icon(trailing, color: const Color(0xFF334155), size: 20),
        ],
      ),
    );
  }
}

class YellowActionButton extends StatelessWidget {
  const YellowActionButton({required this.label, this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: HygColors.gold,
        foregroundColor: HygColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({required this.label, this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: HygColors.ink,
        side: const BorderSide(color: HygColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class EmployeeTableHeader extends StatelessWidget {
  const EmployeeTableHeader({super.key});

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
          Expanded(flex: 4, child: HeaderLabel('EMPLOYEE')),
          Expanded(flex: 2, child: HeaderLabel('COMPANY')),
          Expanded(flex: 3, child: HeaderLabel('ROLE & DEPARTMENT')),
          Expanded(flex: 2, child: HeaderLabel('HIRED')),
          Expanded(child: HeaderLabel('STATUS')),
          SizedBox(
            width: 80,
            child: Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class HeaderLabel extends StatelessWidget {
  const HeaderLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: HygTypography.tableHeader,
    );
  }
}

class EmployeeRow extends StatelessWidget {
  const EmployeeRow({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final EmployeePreview employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: employee.avatarColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: EmployeeAvatar(employee: employee),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        overflow: TextOverflow.ellipsis,
                        style: HygTypography.tablePrimary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        employee.email?.trim().isNotEmpty == true
                            ? employee.email!
                            : '-',
                        overflow: TextOverflow.ellipsis,
                        style: HygTypography.tableMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: BodyCell(employee.company)),
          Expanded(flex: 3, child: BodyCell(employee.roleDepartment)),
          Expanded(flex: 2, child: BodyCell(employee.hired)),
          Expanded(child: StatusPill(status: employee.status)),
          SizedBox(
            width: 80,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Edit employee',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete employee',
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

class BodyCell extends StatelessWidget {
  const BodyCell(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: HygTypography.tableBody,
    );
  }
}

class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({required this.employee, super.key});

  final EmployeePreview employee;

  @override
  Widget build(BuildContext context) {
    final photoUrl = employee.photoUrl?.trim() ?? '';

    if (photoUrl.isEmpty) {
      return _InitialAvatar(employee: employee);
    }

    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _InitialAvatar(employee: employee),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return _InitialAvatar(employee: employee);
      },
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.employee});

  final EmployeePreview employee;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        employee.initial,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.trim().isEmpty
        ? 'active'
        : status.trim().toLowerCase();
    final isActive = normalizedStatus == 'active';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          normalizedStatus.toUpperCase(),
          style: HygTypography.tableHeader.copyWith(
            color: isActive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
