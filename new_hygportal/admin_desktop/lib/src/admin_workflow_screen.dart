part of '../main.dart';

class AdminWorkflowHeader extends StatelessWidget {
  const AdminWorkflowHeader({
    required this.title,
    required this.subtitle,
    this.icon = Icons.admin_panel_settings,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;

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
          Icon(icon, color: HygColors.goldStrong, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HygTypography.pageTitle),
                const SizedBox(height: 3),
                Text(subtitle, style: HygTypography.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminWorkflowPanel extends StatefulWidget {
  const AdminWorkflowPanel({
    required this.view,
    required this.candidates,
    required this.storeRouteScopes,
    required this.clusters,
    required this.areas,
    required this.positions,
    required this.departmentPositions,
    required this.ladders,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onSetAuthority,
    required this.onSetPositionLevel,
    required this.onClearPositionLevel,
    required this.onSetDepartmentLadder,
    super.key,
  });

  final AdminWorkflowView view;
  final List<AuthorityCandidatePreview> candidates;
  final List<StoreRouteScopePreview> storeRouteScopes;
  final List<ClusterPreview> clusters;
  final List<AreaPreview> areas;
  final List<AdminPositionAuthorityPreview> positions;
  final List<DepartmentPositionCatalogPreview> departmentPositions;
  final List<DepartmentLadderPreview> ladders;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function(
    AuthorityCandidatePreview candidate,
    int level, {
    String? clusterId,
    String? areaId,
  })
  onSetAuthority;
  final Future<void> Function(AdminPositionAuthorityPreview position, int level)
  onSetPositionLevel;
  final Future<void> Function(AdminPositionAuthorityPreview position)
  onClearPositionLevel;
  final Future<void> Function(
    DepartmentLadderPreview ladder,
    DepartmentLadderUpdate update,
  )
  onSetDepartmentLadder;

  @override
  State<AdminWorkflowPanel> createState() => _AdminWorkflowPanelState();
}

class _AdminWorkflowPanelState extends State<AdminWorkflowPanel> {
  final _searchController = TextEditingController();
  var _query = '';
  var _departmentFilter = '';
  var _positionFilter = '';
  var _storeFilter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _authorityLevelFor(AuthorityCandidatePreview candidate) {
    var level = candidate.currentAuthorityLevel ?? candidate.positionLevel;

    if (level == null) {
      for (final position in widget.positions) {
        if (position.positionId == candidate.positionId) {
          level = position.authorityLevel;
          break;
        }
      }
    }

    return level ?? 1;
  }

  String _scopeLabelFor(AuthorityCandidatePreview candidate) {
    final level = _authorityLevelFor(candidate);
    if (level == 4) {
      return candidate.clusterName.trim().toUpperCase() == 'N/A'
          ? 'Choose cluster'
          : candidate.clusterName;
    }
    if (level == 5) {
      return candidate.areaName.trim().toUpperCase() == 'N/A'
          ? 'Choose area'
          : candidate.areaName;
    }
    return candidate.storeName;
  }

  String _dateTag(DateTime value) {
    return '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
  }

  List<int> _postProcessExcelBytes(List<int> encodedBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(encodedBytes);
      final outArchive = Archive();

      for (final file in archive.files) {
        if (file.name == '[Content_Types].xml') {
          final contentBytes = file.content as List<int>;
          final xmlContent = utf8.decode(contentBytes);
          final fixedXml = xmlContent.replaceAll(
            RegExp(r'<Override[^>]*drawing1\.xml[^>]*/>'),
            '',
          );
          final fixedBytes = utf8.encode(fixedXml);
          outArchive.addFile(
            ArchiveFile(file.name, fixedBytes.length, fixedBytes),
          );
        } else if (file.name.startsWith('xl/worksheets/_rels/') ||
            file.name.startsWith('xl/drawings/')) {
          continue;
        } else {
          outArchive.addFile(file);
        }
      }

      final fixed = ZipEncoder().encode(outArchive);
      return fixed ?? encodedBytes;
    } catch (_) {
      return encodedBytes;
    }
  }

  Future<void> _downloadApproverAssignmentsExcel(
    List<AuthorityCandidatePreview> candidates,
  ) async {
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No approver assignments to export.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    const sheetName = 'Approver Assignments';
    excel.rename(defaultSheet, sheetName);
    final sheet = excel.sheets[sheetName]!;

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#071426'),
      fontFamily: 'Segoe UI',
      fontSize: 11,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final dataStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );
    final dataStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );
    final centerStyle = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final centerStyleStripe = CellStyle(
      fontFamily: 'Segoe UI',
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1E293B'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    const headers = [
      'Employee No',
      'Employee',
      'Position',
      'Company',
      'Store',
      'Scope',
      'Department',
      'Function',
      'Position Level',
      'Assigned Level',
    ];
    final widths = <int>[15, 28, 26, 24, 22, 22, 24, 22, 16, 16];

    for (var c = 0; c < headers.length; c++) {
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
      sheet.setColumnWidth(c, widths[c].toDouble());
    }
    sheet.setRowHeight(0, 24);

    for (var r = 0; r < candidates.length; r++) {
      final candidate = candidates[r];
      final positionLevel = candidate.positionLevel;
      final assignedLevel = candidate.currentAuthorityLevel;
      final values = [
        candidate.employeeNo,
        candidate.fullName,
        candidate.positionName,
        candidate.companyName,
        candidate.storeName,
        _scopeLabelFor(candidate),
        candidate.departmentName,
        candidate.functionName,
        positionLevel == null ? 'Not set' : 'Level $positionLevel',
        assignedLevel == null ? 'Not assigned' : 'Level $assignedLevel',
      ];
      final isStripe = r.isOdd;

      for (var c = 0; c < values.length; c++) {
        final isCentered = c == 0 || c >= 8;
        excel.updateCell(
          sheetName,
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          TextCellValue(values[c]),
          cellStyle: isCentered
              ? (isStripe ? centerStyleStripe : centerStyle)
              : (isStripe ? dataStyleStripe : dataStyle),
        );
      }
      sheet.setRowHeight(r + 1, 21);
    }

    final encodedBytes = excel.encode();
    if (encodedBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to generate Excel file.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final fileBytes = Uint8List.fromList(_postProcessExcelBytes(encodedBytes));
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save approver assignments Excel file',
      fileName: 'Approver_Assignments_${_dateTag(DateTime.now())}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: fileBytes,
    );

    if (!mounted || savePath == null) return;

    try {
      if (!await File(savePath).exists()) {
        await File(savePath).writeAsBytes(fileBytes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to: $savePath'),
          backgroundColor: const Color(0xFF166534),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Open folder',
            textColor: Colors.white,
            onPressed: () {
              Process.run('explorer', ['/select,', savePath]);
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $error'),
          backgroundColor: const Color(0xFFB91C1C),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  List<AuthorityCandidatePreview> get _filteredCandidates {
    final query = _query.trim().toLowerCase();
    final departmentFilter = _departmentFilter.trim().toLowerCase();
    final positionFilter = _positionFilter.trim().toLowerCase();
    final storeFilter = _storeFilter.trim().toLowerCase();

    return widget.candidates.where((candidate) {
      final matchesDepartment =
          departmentFilter.isEmpty ||
          candidate.departmentName.toLowerCase() == departmentFilter;
      final matchesPosition =
          positionFilter.isEmpty ||
          candidate.positionName.toLowerCase() == positionFilter;
      final matchesStore =
          storeFilter.isEmpty ||
          candidate.storeName.toLowerCase() == storeFilter;
      final matchesSearch =
          query.isEmpty ||
          candidate.fullName.toLowerCase().contains(query) ||
          candidate.employeeNo.toLowerCase().contains(query) ||
          candidate.positionName.toLowerCase().contains(query) ||
          candidate.functionName.toLowerCase().contains(query) ||
          candidate.storeName.toLowerCase().contains(query) ||
          candidate.departmentName.toLowerCase().contains(query);

      return matchesDepartment &&
          matchesPosition &&
          matchesStore &&
          matchesSearch;
    }).toList();
  }

  List<String> get _departmentOptions {
    final options =
        widget.candidates
            .map((candidate) => candidate.departmentName.trim())
            .where((name) => name.isNotEmpty && name != 'N/A')
            .toSet()
            .toList()
          ..sort();
    return options;
  }

  List<String> get _storeOptions {
    final options =
        widget.candidates
            .map((candidate) => candidate.storeName.trim())
            .where((name) => name.isNotEmpty && name != 'N/A')
            .toSet()
            .toList()
          ..sort();
    return options;
  }

  List<String> get _positionOptions {
    final options =
        widget.candidates
            .map((candidate) => candidate.positionName.trim())
            .where((name) => name.isNotEmpty && name != 'N/A')
            .toSet()
            .toList()
          ..sort();
    return options;
  }

  List<AdminPositionAuthorityPreview> get _filteredPositions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.positions;

    return widget.positions
        .where(
          (position) => position.positionName.toLowerCase().contains(query),
        )
        .toList();
  }

  List<DepartmentLadderPreview> get _filteredLadders {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.ladders;

    return widget.ladders
        .where((ladder) => ladder.departmentName.toLowerCase().contains(query))
        .toList();
  }

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
          if (widget.view == AdminWorkflowView.approverAssignments) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_filteredCandidates.length} visible approver assignment${_filteredCandidates.length == 1 ? '' : 's'}',
                    style: HygTypography.body.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _filteredCandidates.isEmpty
                      ? null
                      : () => _downloadApproverAssignmentsExcel(
                          _filteredCandidates,
                        ),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download Excel'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF806600),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _WorkflowSearchField(
                  controller: _searchController,
                  hint: widget.view == AdminWorkflowView.approverAssignments
                      ? 'Search employee, position, department, store'
                      : 'Search records',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
              if (widget.view == AdminWorkflowView.approverAssignments) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 220,
                  child: _WorkflowDropdownFilter(
                    value: _departmentOptions.contains(_departmentFilter)
                        ? _departmentFilter
                        : '',
                    options: _departmentOptions,
                    allLabel: 'All departments',
                    onChanged: (value) =>
                        setState(() => _departmentFilter = value),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: _WorkflowDropdownFilter(
                    value: _positionOptions.contains(_positionFilter)
                        ? _positionFilter
                        : '',
                    options: _positionOptions,
                    allLabel: 'All positions',
                    onChanged: (value) =>
                        setState(() => _positionFilter = value),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 180,
                  child: _WorkflowDropdownFilter(
                    value: _storeOptions.contains(_storeFilter)
                        ? _storeFilter
                        : '',
                    options: _storeOptions,
                    allLabel: 'All stores',
                    onChanged: (value) => setState(() => _storeFilter = value),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh, color: Color(0xFF475569)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (widget.isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading admin settings',
              message: 'Getting workflow settings from Supabase.',
            )
          else if (widget.error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load admin settings',
              message: widget.error!,
              actionLabel: 'Retry',
              onAction: widget.onRefresh,
            )
          else if (widget.view == AdminWorkflowView.approverAssignments)
            _AuthorityCandidatesTable(
              candidates: _filteredCandidates,
              clusters: widget.clusters,
              areas: widget.areas,
              positions: widget.positions,
              onSetAuthority: widget.onSetAuthority,
            )
          else if (widget.view == AdminWorkflowView.authorityLevels)
            _AuthorityLevelsBoard(
              positions: _filteredPositions,
              onSetLevel: widget.onSetPositionLevel,
              onClearLevel: widget.onClearPositionLevel,
            )
          else
            _DepartmentLaddersTable(
              ladders: _filteredLadders,
              candidates: widget.candidates,
              storeRouteScopes: widget.storeRouteScopes,
              positions: widget.positions,
              departmentPositions: widget.departmentPositions,
              onSetLadder: widget.onSetDepartmentLadder,
            ),
        ],
      ),
    );
  }
}

class _WorkflowSearchField extends StatelessWidget {
  const _WorkflowSearchField({
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

class _WorkflowDropdownFilter extends StatelessWidget {
  const _WorkflowDropdownFilter({
    required this.value,
    required this.options,
    required this.allLabel,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final String allLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Color(0xFF64748B),
          size: 18,
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.filter_list,
            color: Color(0xFF64748B),
            size: 18,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
        style: HygTypography.body.copyWith(color: HygColors.ink),
        items: [
          DropdownMenuItem(value: '', child: Text(allLabel)),
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => onChanged(value ?? ''),
      ),
    );
  }
}

enum AdminWorkflowView { approverAssignments, authorityLevels, approvalRoutes }

class _AuthorityCandidatesTable extends StatelessWidget {
  const _AuthorityCandidatesTable({
    required this.candidates,
    required this.clusters,
    required this.areas,
    required this.positions,
    required this.onSetAuthority,
  });

  final List<AuthorityCandidatePreview> candidates;
  final List<ClusterPreview> clusters;
  final List<AreaPreview> areas;
  final List<AdminPositionAuthorityPreview> positions;
  final Future<void> Function(
    AuthorityCandidatePreview candidate,
    int level, {
    String? clusterId,
    String? areaId,
  })
  onSetAuthority;

  List<int> _allowedLevelsFor(AuthorityCandidatePreview candidate) {
    var level = candidate.positionLevel;

    if (level == null) {
      for (final position in positions) {
        if (position.positionId == candidate.positionId) {
          level = position.authorityLevel;
          break;
        }
      }
    }

    return [level ?? 1];
  }

  int _effectiveLevelFor(AuthorityCandidatePreview candidate) {
    return candidate.currentAuthorityLevel ??
        candidate.positionLevel ??
        _allowedLevelsFor(candidate).first;
  }

  String _scopeLabelFor(AuthorityCandidatePreview candidate) {
    final level = _effectiveLevelFor(candidate);
    if (level == 4) {
      return candidate.clusterName.trim().toUpperCase() == 'N/A'
          ? 'Choose cluster'
          : candidate.clusterName;
    }
    if (level == 5) {
      return candidate.areaName.trim().toUpperCase() == 'N/A'
          ? 'Choose area'
          : candidate.areaName;
    }
    return candidate.storeName;
  }

  Future<void> _handleSetAuthority(
    BuildContext context,
    AuthorityCandidatePreview candidate,
    int level,
  ) async {
    if (level == 4) {
      final clusterId = await showDialog<String>(
        context: context,
        builder: (context) => _AuthorityScopeDialog(
          title: 'Choose cluster scope',
          subtitle: candidate.fullName,
          options: [
            for (final cluster in clusters)
              _AuthorityScopeOption(id: cluster.id, name: cluster.name),
          ],
          currentId: candidate.clusterId,
        ),
      );
      if (clusterId == null) return;
      await onSetAuthority(candidate, level, clusterId: clusterId);
      return;
    }

    if (level == 5) {
      final areaId = await showDialog<String>(
        context: context,
        builder: (context) => _AuthorityScopeDialog(
          title: 'Choose area scope',
          subtitle: candidate.fullName,
          options: [
            for (final area in areas)
              _AuthorityScopeOption(id: area.id, name: area.name),
          ],
          currentId: candidate.areaId,
        ),
      );
      if (areaId == null) return;
      await onSetAuthority(candidate, level, areaId: areaId);
      return;
    }

    await onSetAuthority(candidate, level);
  }

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const EmployeesStateMessage(
        icon: Icons.verified_user_outlined,
        title: 'No approver candidates',
        message: 'No active employees with assignments were found.',
      );
    }

    return Column(
      children: [
        const Row(
          children: [
            Expanded(flex: 3, child: HeaderLabel('EMPLOYEE')),
            Expanded(flex: 2, child: HeaderLabel('POSITION')),
            Expanded(flex: 2, child: HeaderLabel('STORE')),
            Expanded(flex: 2, child: HeaderLabel('SCOPE')),
            Expanded(flex: 2, child: HeaderLabel('DEPARTMENT')),
            Expanded(flex: 2, child: HeaderLabel('LEVEL')),
            SizedBox(width: 94),
          ],
        ),
        const SizedBox(height: 8),
        ...candidates.map(
          (candidate) => _AdminDataRow(
            children: [
              Expanded(flex: 3, child: BodyCell(candidate.fullName)),
              Expanded(flex: 2, child: BodyCell(candidate.positionName)),
              Expanded(flex: 2, child: BodyCell(candidate.storeName)),
              Expanded(flex: 2, child: BodyCell(_scopeLabelFor(candidate))),
              Expanded(flex: 2, child: BodyCell(candidate.departmentName)),
              Expanded(
                flex: 2,
                child: BodyCell(_levelLabel(_effectiveLevelFor(candidate))),
              ),
              SizedBox(
                width: 94,
                child: _LevelPopupButton(
                  tooltip: 'Set approver level',
                  levels: _allowedLevelsFor(candidate),
                  onSelect: (level) =>
                      _handleSetAuthority(context, candidate, level),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthorityLevelsBoard extends StatelessWidget {
  const _AuthorityLevelsBoard({
    required this.positions,
    required this.onSetLevel,
    required this.onClearLevel,
  });

  final List<AdminPositionAuthorityPreview> positions;
  final Future<void> Function(AdminPositionAuthorityPreview position, int level)
  onSetLevel;
  final Future<void> Function(AdminPositionAuthorityPreview position)
  onClearLevel;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const EmployeesStateMessage(
        icon: Icons.badge_outlined,
        title: 'No positions',
        message: 'No active positions were found.',
      );
    }

    final normalizedPositions = positions
        .map(
          (position) => position.authorityLevel == null
              ? position.copyWith(authorityLevel: 1)
              : position,
        )
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        const spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var level = 1; level <= 8; level++)
                  SizedBox(
                    width: cardWidth,
                    child: _AuthorityLevelCard(
                      level: level,
                      positions: normalizedPositions
                          .where((position) => position.authorityLevel == level)
                          .toList(),
                      onEdit: () async {
                        final selected = await showDialog<Set<String>>(
                          context: context,
                          builder: (context) => AuthorityLevelDialog(
                            level: level,
                            positions: normalizedPositions,
                          ),
                        );
                        if (selected == null) return;

                        for (final position in normalizedPositions) {
                          final shouldBeLevel = selected.contains(
                            position.positionId,
                          );
                          if (shouldBeLevel &&
                              position.authorityLevel != level) {
                            await onSetLevel(position, level);
                          } else if (!shouldBeLevel &&
                              position.authorityLevel == level) {
                            await onClearLevel(position);
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AuthorityScopeOption {
  const _AuthorityScopeOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _AuthorityScopeDialog extends StatelessWidget {
  const _AuthorityScopeDialog({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.currentId,
  });

  final String title;
  final String subtitle;
  final List<_AuthorityScopeOption> options;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: HygTypography.pageTitle.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (options.isEmpty)
                const EmployeesStateMessage(
                  icon: Icons.account_tree_outlined,
                  title: 'No scope options',
                  message: 'Create clusters or areas first, then try again.',
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option.id == currentId;
                      return Material(
                        color: selected
                            ? const Color(0xFFFFF7CC)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(context).pop(option.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected
                                    ? HygColors.goldStrong
                                    : HygColors.border,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: selected
                                      ? HygColors.goldStrong
                                      : const Color(0xFF94A3B8),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    option.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: HygTypography.body.copyWith(
                                      color: HygColors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorityLevelCard extends StatelessWidget {
  const _AuthorityLevelCard({
    required this.level,
    required this.positions,
    required this.onEdit,
  });

  final int level;
  final List<AdminPositionAuthorityPreview> positions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final employeeTotal = positions.fold<int>(
      0,
      (sum, position) => sum + position.employeeCount,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 166),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AuthorityLevelBadge(level: level),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LEVEL $level',
                      style: HygTypography.body.copyWith(
                        color: HygColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${positions.length} positions',
                      style: HygTypography.body.copyWith(
                        color: const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit level positions',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.tune,
                  color: Color(0xFF854D0E),
                  size: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (positions.isEmpty)
            Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: HygColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'No positions assigned',
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final position in positions.take(6))
                  _AuthorityPositionPill(position: position),
                if (positions.length > 6)
                  _OverflowPill(count: positions.length - 6),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RouteStat(
                label: 'Positions',
                value: positions.length.toString(),
              ),
              const SizedBox(width: 8),
              _RouteStat(label: 'Employees', value: employeeTotal.toString()),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthorityLevelBadge extends StatelessWidget {
  const _AuthorityLevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: HygColors.gold,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(
        child: Text(
          'L$level',
          style: HygTypography.pageTitle.copyWith(
            color: HygColors.ink,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}

class _AuthorityPositionPill extends StatelessWidget {
  const _AuthorityPositionPill({required this.position});

  final AdminPositionAuthorityPreview position;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF64748B)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              position.positionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverflowPill extends StatelessWidget {
  const _OverflowPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE9A7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '+$count more',
        style: HygTypography.body.copyWith(
          color: const Color(0xFF6B5600),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DepartmentLaddersTable extends StatelessWidget {
  const _DepartmentLaddersTable({
    required this.ladders,
    required this.candidates,
    required this.storeRouteScopes,
    required this.positions,
    required this.departmentPositions,
    required this.onSetLadder,
  });

  final List<DepartmentLadderPreview> ladders;
  final List<AuthorityCandidatePreview> candidates;
  final List<StoreRouteScopePreview> storeRouteScopes;
  final List<AdminPositionAuthorityPreview> positions;
  final List<DepartmentPositionCatalogPreview> departmentPositions;
  final Future<void> Function(
    DepartmentLadderPreview ladder,
    DepartmentLadderUpdate update,
  )
  onSetLadder;

  @override
  Widget build(BuildContext context) {
    if (ladders.isEmpty) {
      return const EmployeesStateMessage(
        icon: Icons.route_outlined,
        title: 'No departments',
        message: 'No active departments were found.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        const spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: ladders.map((ladder) {
            final hasStoreMap = _storeCountFor(ladder) > 0;
            return SizedBox(
              width: hasStoreMap ? constraints.maxWidth : cardWidth,
              child: _DepartmentRouteCard(
                ladder: ladder,
                candidates: candidates,
                storeRouteScopes: storeRouteScopes,
                onEdit: () async {
                  final update = await showDialog<DepartmentLadderUpdate>(
                    context: context,
                    builder: (context) => DepartmentLadderDialog(
                      ladder: ladder,
                      candidates: candidates,
                      positions: positions,
                      departmentPositions: departmentPositions,
                    ),
                  );
                  if (update != null) {
                    await onSetLadder(ladder, update);
                  }
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  int _storeCountFor(DepartmentLadderPreview ladder) {
    final department = ladder.departmentName.trim().toLowerCase();
    return storeRouteScopes
        .where(
          (scope) =>
              scope.departmentName.trim().toLowerCase() == department &&
              scope.storeName.trim().isNotEmpty &&
              scope.storeName.trim().toUpperCase() != 'N/A',
        )
        .map((scope) => scope.storeId)
        .toSet()
        .length;
  }
}

class _DepartmentRouteCard extends StatelessWidget {
  const _DepartmentRouteCard({
    required this.ladder,
    required this.candidates,
    required this.storeRouteScopes,
    required this.onEdit,
  });

  final DepartmentLadderPreview ladder;
  final List<AuthorityCandidatePreview> candidates;
  final List<StoreRouteScopePreview> storeRouteScopes;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final levels = [...ladder.routeLevels]..sort();
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: HygColors.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.route_outlined,
                  color: HygColors.ink,
                  size: 17,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ladder.departmentName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: HygColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit route levels',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.tune,
                  color: Color(0xFF854D0E),
                  size: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (levels.isEmpty)
            Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: HygColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'No route configured',
                style: HygTypography.body.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            _RouteFlow(levels: levels, roles: ladder.routeRoles),
          const SizedBox(height: 8),
          Row(
            children: [
              _RouteStat(label: 'Steps', value: levels.length.toString()),
              const SizedBox(width: 8),
              _RouteStat(
                label: 'Highest',
                value: levels.isEmpty ? '-' : 'L${levels.last}',
              ),
            ],
          ),
          _StoreRouteOverview(
            ladder: ladder,
            candidates: candidates,
            storeRouteScopes: storeRouteScopes,
            levels: levels,
          ),
        ],
      ),
    );
  }
}

class _StoreRouteOverview extends StatelessWidget {
  const _StoreRouteOverview({
    required this.ladder,
    required this.candidates,
    required this.storeRouteScopes,
    required this.levels,
  });

  final DepartmentLadderPreview ladder;
  final List<AuthorityCandidatePreview> candidates;
  final List<StoreRouteScopePreview> storeRouteScopes;
  final List<int> levels;

  @override
  Widget build(BuildContext context) {
    final departmentName = ladder.departmentName.trim().toLowerCase();
    final scopes =
        storeRouteScopes
            .where(
              (scope) =>
                  scope.departmentName.trim().toLowerCase() == departmentName &&
                  scope.storeName.trim().isNotEmpty &&
                  scope.storeName.trim().toUpperCase() != 'N/A',
            )
            .toList()
          ..sort((a, b) => a.storeName.compareTo(b.storeName));

    if (scopes.isEmpty || levels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFFDE68A)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: Color(0xFF854D0E),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Store route map',
                    style: HygTypography.body.copyWith(
                      color: const Color(0xFF854D0E),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${scopes.length} stores',
                    style: HygTypography.body.copyWith(
                      color: const Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final scope in scopes) ...[
                _StoreRouteRow(
                  departmentName: ladder.departmentName,
                  scope: scope,
                  candidates: candidates,
                  levels: levels,
                  roles: ladder.routeRoles,
                ),
                if (scope != scopes.last) const SizedBox(height: 7),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StoreRouteRow extends StatelessWidget {
  const _StoreRouteRow({
    required this.departmentName,
    required this.scope,
    required this.candidates,
    required this.levels,
    required this.roles,
  });

  final String departmentName;
  final StoreRouteScopePreview scope;
  final List<AuthorityCandidatePreview> candidates;
  final List<int> levels;
  final Map<int, DepartmentRouteRole> roles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$departmentName > ${scope.storeName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HygTypography.body.copyWith(
              color: HygColors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final level in levels)
                _StoreRouteLevelChip(
                  level: level,
                  roleName: roles[level]?.positionName,
                  approverNames: _approversForLevel(level),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _approversForLevel(int level) {
    final mappedApprovers = scope.routeApprovers[level] ?? const <String>[];
    if (mappedApprovers.isNotEmpty) {
      return mappedApprovers;
    }

    final targetRole = roles[level];
    final department = departmentName.trim().toLowerCase();
    final store = scope.storeName.trim().toLowerCase();
    final scopeAreaId = scope.areaId;
    final scopeClusterId = scope.clusterId;
    if (targetRole != null) {
      final roleName = targetRole.positionName.toLowerCase();
      final isStoreSpecificRole =
          level == 2 || roleName.contains('store manager');
      final isClusterSpecificRole =
          level == 4 || roleName.contains('cluster manager');
      final isAreaSpecificRole =
          level == 5 || roleName.contains('area manager');
      final names =
          candidates
              .where(
                (candidate) =>
                    candidate.currentAuthorityLevel == level &&
                    candidate.positionId == targetRole.positionId &&
                    (!isStoreSpecificRole ||
                        candidate.storeName.trim().toLowerCase() == store) &&
                    (!isClusterSpecificRole ||
                        (scopeClusterId != null &&
                            candidate.clusterId == scopeClusterId)) &&
                    (!isAreaSpecificRole ||
                        (scopeAreaId != null &&
                            candidate.areaId == scopeAreaId)),
              )
              .map((candidate) => candidate.fullName)
              .toSet()
              .toList()
            ..sort();
      return names;
    }

    final names =
        candidates
            .where(
              (candidate) =>
                  candidate.departmentName.trim().toLowerCase() == department &&
                  candidate.storeName.trim().toLowerCase() == store &&
                  candidate.currentAuthorityLevel == level,
            )
            .map((candidate) => candidate.fullName)
            .toSet()
            .toList()
          ..sort();
    return names;
  }
}

class _StoreRouteLevelChip extends StatelessWidget {
  const _StoreRouteLevelChip({
    required this.level,
    required this.roleName,
    required this.approverNames,
  });

  final int level;
  final String? roleName;
  final List<String> approverNames;

  @override
  Widget build(BuildContext context) {
    final hasApprover = approverNames.isNotEmpty;
    final label = roleName == null ? 'L$level' : 'L$level $roleName';
    final tooltip = hasApprover
        ? 'Approver: ${approverNames.join(', ')}'
        : 'No approver tagged yet';

    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: hasApprover ? const Color(0xFFECFDF5) : Colors.white,
          border: Border.all(
            color: hasApprover
                ? const Color(0xFF86EFAC)
                : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasApprover ? Icons.check_circle : Icons.schedule,
              size: 12,
              color: hasApprover
                  ? const Color(0xFF15803D)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HygTypography.body.copyWith(
                  color: hasApprover
                      ? const Color(0xFF166534)
                      : const Color(0xFF475569),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteFlow extends StatelessWidget {
  const _RouteFlow({required this.levels, required this.roles});

  final List<int> levels;
  final Map<int, DepartmentRouteRole> roles;

  @override
  Widget build(BuildContext context) {
    final rows = <List<int>>[];
    for (var index = 0; index < levels.length; index += 4) {
      rows.add(levels.sublist(index, math.min(index + 4, levels.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          if (rowIndex > 0) const SizedBox(height: 8),
          _RouteFlowRow(
            startStep: rowIndex * 4 + 1,
            levels: rows[rowIndex],
            roles: roles,
            reversed: rowIndex.isOdd,
            showTurnDown: rowIndex < rows.length - 1,
          ),
        ],
      ],
    );
  }
}

class _RouteFlowRow extends StatelessWidget {
  const _RouteFlowRow({
    required this.startStep,
    required this.levels,
    required this.roles,
    required this.reversed,
    required this.showTurnDown,
  });

  final int startStep;
  final List<int> levels;
  final Map<int, DepartmentRouteRole> roles;
  final bool reversed;
  final bool showTurnDown;

  @override
  Widget build(BuildContext context) {
    final rowItems = [
      for (var index = 0; index < levels.length; index++)
        (step: startStep + index, level: levels[index]),
    ];
    final visibleItems = reversed ? rowItems.reversed.toList() : rowItems;

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        for (var index = 0; index < visibleItems.length; index++) ...[
          if (index > 0) _RouteConnector(reversed: reversed),
          _RouteLevelNode(
            level: visibleItems[index].level,
            step: visibleItems[index].step,
            roleName: roles[visibleItems[index].level]?.positionName,
          ),
        ],
        if (showTurnDown) ...[
          if (!reversed) const _RouteDownConnector(),
          if (reversed) const Spacer(),
          if (reversed) const _RouteDownConnector(),
        ],
      ],
    );
  }
}

class _RouteLevelNode extends StatelessWidget {
  const _RouteLevelNode({
    required this.level,
    required this.step,
    this.roleName,
  });

  final int level;
  final int step;
  final String? roleName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.goldStrong, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'STEP $step',
            style: HygTypography.body.copyWith(
              color: const Color(0xFF64748B),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'L$level',
            style: HygTypography.pageTitle.copyWith(
              color: HygColors.ink,
              fontSize: 18,
            ),
          ),
          if (roleName != null) ...[
            const SizedBox(height: 1),
            Text(
              roleName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HygTypography.body.copyWith(
                color: const Color(0xFF854D0E),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteConnector extends StatelessWidget {
  const _RouteConnector({this.reversed = false});

  final bool reversed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Center(
        child: Icon(
          reversed ? Icons.arrow_back : Icons.arrow_forward,
          size: 15,
          color: const Color(0xFFB45309),
        ),
      ),
    );
  }
}

class _RouteDownConnector extends StatelessWidget {
  const _RouteDownConnector();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 28,
      child: Center(
        child: Icon(Icons.arrow_downward, size: 16, color: Color(0xFFB45309)),
      ),
    );
  }
}

class _RouteStat extends StatelessWidget {
  const _RouteStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: HygTypography.body.copyWith(
                color: const Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDataRow extends StatelessWidget {
  const _AdminDataRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: children),
    );
  }
}

class _LevelPopupButton extends StatelessWidget {
  const _LevelPopupButton({
    required this.tooltip,
    required this.onSelect,
    this.levels,
  });

  final String tooltip;
  final List<int>? levels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final levelOptions = levels ?? List.generate(8, (index) => index + 1);

    return PopupMenuButton<int>(
      tooltip: tooltip,
      onSelected: onSelect,
      itemBuilder: (context) => levelOptions.isEmpty
          ? [
              const PopupMenuItem(
                enabled: false,
                child: Text('No department levels'),
              ),
            ]
          : [
              for (final level in levelOptions)
                PopupMenuItem(value: level, child: Text('Level $level')),
            ],
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.tune, color: Color(0xFF2563EB), size: 18),
      ),
    );
  }
}

class AuthorityLevelDialog extends StatefulWidget {
  const AuthorityLevelDialog({
    required this.level,
    required this.positions,
    super.key,
  });

  final int level;
  final List<AdminPositionAuthorityPreview> positions;

  @override
  State<AuthorityLevelDialog> createState() => _AuthorityLevelDialogState();
}

class _AuthorityLevelDialogState extends State<AuthorityLevelDialog> {
  late final Set<String> _selected = widget.positions
      .where((position) => position.authorityLevel == widget.level)
      .map((position) => position.positionId)
      .toSet();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: const Color(0xFFF7EFE1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _AuthorityLevelBadge(level: widget.level),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Level ${widget.level}',
                          style: HygTypography.pageTitle.copyWith(fontSize: 24),
                        ),
                        Text(
                          'Assign positions to this authority level',
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
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 520 ? 2 : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      itemCount: widget.positions.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: columns == 2 ? 3.8 : 5.2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final position = widget.positions[index];
                        final selected = _selected.contains(
                          position.positionId,
                        );
                        return _PositionLevelToggle(
                          position: position,
                          targetLevel: widget.level,
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
                      child: const Text('Save Level'),
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

class _PositionLevelToggle extends StatelessWidget {
  const _PositionLevelToggle({
    required this.position,
    required this.targetLevel,
    required this.selected,
    required this.onTap,
  });

  final AdminPositionAuthorityPreview position;
  final int targetLevel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherLevel =
        position.authorityLevel != null &&
            position.authorityLevel != targetLevel
        ? 'L${position.authorityLevel}'
        : null;

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
                child: selected
                    ? const Icon(
                        Icons.check,
                        color: Color(0xFF6B5600),
                        size: 17,
                      )
                    : const Icon(
                        Icons.badge_outlined,
                        color: Color(0xFF64748B),
                        size: 17,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.positionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HygTypography.body.copyWith(
                        color: HygColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${position.employeeCount} employees',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HygTypography.body.copyWith(
                        color: const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (otherLevel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    otherLevel,
                    style: HygTypography.body.copyWith(
                      color: const Color(0xFF475569),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DepartmentLadderDialog extends StatefulWidget {
  const DepartmentLadderDialog({
    required this.ladder,
    required this.candidates,
    required this.positions,
    required this.departmentPositions,
    super.key,
  });

  final DepartmentLadderPreview ladder;
  final List<AuthorityCandidatePreview> candidates;
  final List<AdminPositionAuthorityPreview> positions;
  final List<DepartmentPositionCatalogPreview> departmentPositions;

  @override
  State<DepartmentLadderDialog> createState() => _DepartmentLadderDialogState();
}

class _DepartmentLadderDialogState extends State<DepartmentLadderDialog> {
  late final Set<int> _levels = widget.ladder.routeLevels
      .where((level) => level > 1)
      .toSet();
  late final Map<int, String> _roles = {
    for (final entry in widget.ladder.routeRoles.entries)
      entry.key: entry.value.positionId,
  };

  List<DepartmentPositionCatalogPreview> _positionsForLevel(int level) {
    return widget.departmentPositions
        .where(
          (position) =>
              position.departmentId == widget.ladder.departmentId &&
              position.positionId != null &&
              position.authorityLevel == level,
        )
        .toList()
      ..sort((a, b) => (a.positionName ?? '').compareTo(b.positionName ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: const Color(0xFFF7EFE1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: HygColors.gold,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.route_outlined,
                      color: HygColors.ink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.ladder.departmentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HygTypography.pageTitle.copyWith(fontSize: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                itemCount: 7,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 2.45,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final level = index + 2;
                  final selected = _levels.contains(level);
                  return _RouteLevelToggle(
                    level: level,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _levels.remove(level);
                          _roles.remove(level);
                        } else {
                          _levels.add(level);
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final level in (_levels.toList()..sort())) ...[
                      _RouteRolePicker(
                        level: level,
                        selectedPositionId: _roles[level],
                        positions: _positionsForLevel(level),
                        candidates: widget.candidates,
                        onChanged: (positionId) {
                          setState(() {
                            if (positionId == null) {
                              _roles.remove(level);
                            } else {
                              _roles[level] = positionId;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                      onPressed: () {
                        final levels = _levels.toList()..sort();
                        Navigator.of(context).pop(
                          DepartmentLadderUpdate(
                            levels: levels,
                            roles: {
                              for (final level in levels)
                                if (_roles[level] != null)
                                  level: _roles[level]!,
                            },
                          ),
                        );
                      },
                      child: const Text('Save Route'),
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

class _RouteRolePicker extends StatelessWidget {
  const _RouteRolePicker({
    required this.level,
    required this.positions,
    required this.candidates,
    required this.selectedPositionId,
    required this.onChanged,
  });

  final int level;
  final List<DepartmentPositionCatalogPreview> positions;
  final List<AuthorityCandidatePreview> candidates;
  final String? selectedPositionId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected =
        positions.any((position) => position.positionId == selectedPositionId)
        ? selectedPositionId
        : null;
    final approverNames =
        selected == null
              ? <String>[]
              : candidates
                    .where(
                      (candidate) =>
                          candidate.positionId == selected &&
                          candidate.currentAuthorityLevel == level,
                    )
                    .map((candidate) => candidate.fullName)
                    .toSet()
                    .toList()
          ..sort();
    final approverLabel = selected == null
        ? 'Approver: any tagged Level $level approver'
        : approverNames.isEmpty
        ? 'Approver: not tagged yet, will auto-resolve once assigned'
        : 'Approver: ${approverNames.join(', ')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'Level $level',
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Specific role',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Any role in this level'),
                    ),
                    for (final position in positions)
                      DropdownMenuItem<String?>(
                        value: position.positionId,
                        child: Text(position.positionName ?? 'Unnamed Role'),
                      ),
                  ],
                  onChanged: positions.isEmpty ? null : onChanged,
                ),
                const SizedBox(height: 6),
                Text(
                  approverLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: selected != null && approverNames.isEmpty
                        ? const Color(0xFF92400E)
                        : const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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

class _RouteLevelToggle extends StatelessWidget {
  const _RouteLevelToggle({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final int level;
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFF6C400) : HygColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                child: selected
                    ? const Icon(
                        Icons.check,
                        color: Color(0xFF6B5600),
                        size: 16,
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Level $level',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HygTypography.body.copyWith(
                    color: selected ? const Color(0xFF4A3B00) : HygColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _levelLabel(int? level) => level == null ? 'NOT SET' : 'LEVEL $level';
