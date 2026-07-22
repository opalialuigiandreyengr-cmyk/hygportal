part of '../main.dart';

class CompaniesHeader extends StatelessWidget {
  const CompaniesHeader({required this.onAddCompany, super.key});

  final VoidCallback onAddCompany;

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
            child: const Icon(Icons.business, color: HygColors.goldStrong),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Companies', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'View and manage partner companies and subsidiaries.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(136, 44),
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAddCompany,
            icon: const Icon(Icons.business, size: 18),
            label: const Text('Add Company'),
          ),
        ],
      ),
    );
  }
}

class AddCompanyDialog extends StatefulWidget {
  const AddCompanyDialog({super.key});

  @override
  State<AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<AddCompanyDialog> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  String? _logoPath;
  String? _logoFileName;
  var _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );

    final file = result?.files.single;
    if (file?.path == null) {
      return;
    }

    setState(() {
      _logoPath = file!.path;
      _logoFileName = file.name;
    });
  }

  Future<void> _saveCompany() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Company name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await CompanyDirectoryService.createCompany(
        name: name,
        contactNumber: _contactController.text,
        address: _addressController.text,
        logoUrl: '',
      );

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
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: HygColors.background,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
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
                      Icons.business,
                      color: HygColors.goldStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Company Details',
                      style: HygTypography.pageTitle.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: HygColors.border),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CompanyLogoBox(
                    logoPath: _logoPath,
                    logoFileName: _logoFileName,
                    onPickLogo: _pickLogo,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ModalTextField(
                                controller: _nameController,
                                label: 'Company Name',
                                required: true,
                                hint: 'e.g. CFI',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: ModalTextField(
                                controller: _contactController,
                                label: 'Contact Number',
                                hint: '09xx xxx xxxx',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ModalTextField(
                          controller: _addressController,
                          label: 'Company Address',
                          hint: 'Full street, building name, city/municipality',
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ],
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
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 150,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7280),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
                    width: 170,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveCompany,
                      child: Text(_isSaving ? 'Saving...' : 'Save Company'),
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

class CompanyLogoBox extends StatelessWidget {
  const CompanyLogoBox({
    required this.onPickLogo,
    this.logoPath,
    this.logoFileName,
    super.key,
  });

  final VoidCallback onPickLogo;
  final String? logoPath;
  final String? logoFileName;

  @override
  Widget build(BuildContext context) {
    final selectedLogoPath = logoPath;
    final selectedLogoName = logoFileName;

    return SizedBox(
      width: 150,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPickLogo,
            child: Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: selectedLogoPath == null
                  ? const Center(
                      child: Icon(
                        Icons.business,
                        color: Color(0xFF94A3B8),
                        size: 46,
                      ),
                    )
                  : Image.file(
                      File(selectedLogoPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.business,
                            color: Color(0xFF94A3B8),
                            size: 46,
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: onPickLogo,
            child: const Text('Upload Logo'),
          ),
          const SizedBox(height: 6),
          Text(
            selectedLogoName ?? 'JPG, PNG.',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HygTypography.tableMuted.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class CompaniesPanel extends StatelessWidget {
  const CompaniesPanel({
    required this.companies,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onDeleteCompany,
    super.key,
  });

  final List<CompanyPreview> companies;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<CompanyPreview> onDeleteCompany;

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
                  label:
                      'Search company name, code, contact number, or address',
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                flex: 2,
                child: FilterBox(
                  label: 'All Contacts',
                  trailing: Icons.keyboard_arrow_down,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: YellowActionButton(
                  label: 'Filter',
                  onPressed: onRefresh,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: OutlineActionButton(
                  label: 'Reset',
                  onPressed: onRefresh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const CompanyTableHeader(),
          const SizedBox(height: 8),
          if (isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading companies',
              message: 'Getting company records from Supabase.',
            )
          else if (error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load companies',
              message: error!,
              actionLabel: 'Retry',
              onAction: onRefresh,
            )
          else if (companies.isEmpty)
            EmployeesStateMessage(
              icon: Icons.business_outlined,
              title: 'No companies found',
              message: 'No company records are available yet.',
              actionLabel: 'Refresh',
              onAction: onRefresh,
            )
          else
            ...companies.map(
              (company) => CompanyRow(
                company: company,
                onDelete: () => onDeleteCompany(company),
              ),
            ),
        ],
      ),
    );
  }
}

class CompanyTableHeader extends StatelessWidget {
  const CompanyTableHeader({super.key});

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
          Expanded(flex: 3, child: HeaderLabel('COMPANY')),
          Expanded(flex: 2, child: HeaderLabel('CONTACT NUMBER')),
          Expanded(flex: 3, child: HeaderLabel('ADDRESS')),
          Expanded(child: HeaderLabel('STATUS')),
          SizedBox(
            width: 46,
            child: Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class CompanyRow extends StatelessWidget {
  const CompanyRow({required this.company, required this.onDelete, super.key});

  final CompanyPreview company;
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
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      company.initials,
                      textAlign: TextAlign.center,
                      style: HygTypography.tablePrimary.copyWith(
                        color: HygColors.goldStrong,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    company.name,
                    overflow: TextOverflow.ellipsis,
                    style: HygTypography.tablePrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: BodyCell(company.contactNumber)),
          Expanded(flex: 3, child: BodyCell(company.address)),
          Expanded(child: StatusPill(status: company.status)),
          SizedBox(
            width: 86,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit company',
                  onPressed: () {},
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete company',
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

class CompanyDeleteDialog extends StatelessWidget {
  const CompanyDeleteDialog({required this.company, super.key});

  final CompanyPreview company;

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
                          'Delete company?',
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
                                text: '"${company.name}"',
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
                        'Companies with employee assignments cannot be deleted.',
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
                'The company will be removed only if it is not in use.',
              ),
              const SizedBox(height: 7),
              const DeleteDialogBullet(
                'Existing employee profiles and history remain unchanged.',
              ),
              const SizedBox(height: 7),
              const DeleteDialogBullet(
                'You can create the company again later if needed.',
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
                      width: 184,
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
                        label: const Text(
                          'Delete Company',
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
      ),
    );
  }
}
