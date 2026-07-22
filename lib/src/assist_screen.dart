part of '../main.dart';

class HygAssistScreen extends StatefulWidget {
  const HygAssistScreen({super.key});

  @override
  State<HygAssistScreen> createState() => _HygAssistScreenState();
}

class _HygAssistScreenState extends State<HygAssistScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _useLocalModel = false;
  String? _localModelInfo;
  bool _isCheckingModel = false;
  List<EmployeePreview>? _employeeCache;
  List<_AssistMessage> _messages = const [
    _AssistMessage(
      fromUser: false,
      text:
          'Hi! I am HYG Assist for HR analytics. Ask me about headcount, company mix, department distribution, or payroll-class demographics.',
    ),
  ];

  static const List<String> _suggestedPrompts = <String>[
    'Show total active headcount',
    'Headcount by company',
    'Headcount by department',
    'Payroll class distribution',
    'Gender demographics summary',
    'Civil status demographics summary',
  ];

  @override
  void dispose() {
    _typingTimer?.cancel();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HygColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 14),
              _buildModelToggle(),
              if (_localModelInfo != null) ...[
                const SizedBox(height: 8),
                Text(
                  _localModelInfo!,
                  style: const TextStyle(
                    color: HygColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HygColors.border),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedPrompts
                      .map(
                        (prompt) => FilledButton.tonal(
                          onPressed: _isTyping
                              ? null
                              : () => _sendMessage(prompt),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFEEF2FF),
                            foregroundColor: HygColors.ink,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(prompt),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = _messages[index];
                      return _AssistBubble(
                        isUser: item.fromUser,
                        text: item.text,
                        isTyping: item.isTyping,
                        responseTimeMs: item.responseTimeMs,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HygColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: HygColors.gold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: HygColors.ink),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HYG Assist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'HR data assistant focused on employee demographics and organization insights.',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.memory, size: 18, color: HygColors.ink),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Local AI Mode (offline model)',
              style: TextStyle(
                color: HygColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          Switch(
            value: _useLocalModel,
            onChanged: (value) => setState(() {
              _useLocalModel = value;
              _localModelInfo = null;
            }),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: _isCheckingModel ? null : _checkLocalModel,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 34),
              foregroundColor: HygColors.ink,
              side: const BorderSide(color: HygColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_isCheckingModel ? 'Checking...' : 'Test'),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _sendMessage();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 3,
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      'Ask HYG Assist about employee data, policies, payroll class, or org setup...',
                  hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isTyping ? null : _sendMessage,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send'),
            style: FilledButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  bool get _isTyping => _messages.any((m) => m.isTyping);

  void _sendMessage([String? preset]) {
    final String raw = preset ?? _messageController.text;
    final String text = raw.trim();
    if (text.isEmpty || _isTyping) {
      return;
    }
    _typingTimer?.cancel();
    final startedAt = DateTime.now();
    setState(() {
      _messages = <_AssistMessage>[
        ..._messages,
        _AssistMessage(fromUser: true, text: text),
        const _AssistMessage(fromUser: false, text: '', isTyping: true),
      ];
      if (preset == null) {
        _messageController.clear();
      }
    });
    _scrollToBottom();
    _typingTimer = Timer(const Duration(milliseconds: 1400), () {
      _resolveReply(text, startedAt: startedAt);
    });
  }

  Future<void> _resolveReply(String text, {required DateTime startedAt}) async {
    String reply;
    final bool structuredQuery = _shouldBypassLocalModel(text);
    if (_useLocalModel && !structuredQuery) {
      final local = await _tryLocalModelReply(text, showError: true);
      reply = local ?? await _buildReply(text);
      if (local == null && mounted) {
        setState(() {
          _localModelInfo ??=
              'Local model unavailable. Using HR rules/data mode.';
        });
      } else if (mounted) {
        setState(() {
          _localModelInfo = 'Answered via local model.';
        });
      }
    } else {
      reply = await _buildReply(text);
      if (_useLocalModel && structuredQuery && mounted) {
        setState(() {
          _localModelInfo =
              'Using DB-first analytics mode for faster and accurate HR counts.';
        });
      }
    }
    if (!mounted) {
      return;
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    setState(() {
      final List<_AssistMessage> updated = List<_AssistMessage>.from(_messages);
      final int typingIndex = updated.lastIndexWhere((m) => m.isTyping);
      if (typingIndex >= 0) {
        updated[typingIndex] = _AssistMessage(
          fromUser: false,
          text: reply,
          responseTimeMs: elapsedMs,
        );
      }
      _messages = updated;
    });
    _scrollToBottom();
  }

  bool _shouldBypassLocalModel(String text) {
    final lower = text.toLowerCase();
    final tokens = _tokens(lower);
    return _hasAny(lower, tokens, <String>[
      'headcount',
      'how many',
      'ilan',
      'ilang',
      'count',
      'total',
      'company',
      'department',
      'position',
      'payroll',
      'rank and file',
      'managerial',
      'admin',
      'gender',
      'civil status',
      'age',
      'tenure',
      'missing',
      'audit',
      'breakdown',
      'distribution',
    ]);
  }

  Future<String?> _tryLocalModelReply(
    String text, {
    bool showError = false,
  }) async {
    try {
      final dataset = await _loadAssistDataset();
      final employees = dataset.employees;
      final profiles = employees
          .map((e) => dataset.profileByEmployeeId[e.id])
          .toList(growable: false);
      final context = _buildHrContextSnapshot(employees, profiles);
      return await LocalHrModelService.generateReply(
        userQuestion: text,
        hrContext: context,
      );
    } catch (error) {
      if (showError && mounted) {
        setState(() {
          _localModelInfo =
              'Local model error: ${error.toString().replaceFirst('Exception: ', '')}';
        });
      }
      return null;
    }
  }

  Future<void> _checkLocalModel() async {
    setState(() {
      _isCheckingModel = true;
      _localModelInfo =
          'Checking local model at ${AppConfig.localModelUrl} ...';
    });
    try {
      final msg = await LocalHrModelService.healthCheck();
      if (!mounted) return;
      setState(() => _localModelInfo = msg);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _localModelInfo =
            'Health check failed: ${error.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingModel = false);
      }
    }
  }

  Future<String> _buildReply(String text) async {
    final String lower = text.toLowerCase();
    final Set<String> tokens = _tokens(lower);

    final nameLookup = await _buildEmployeeNameLookupReply(lower);
    if (nameLookup != null) {
      return nameLookup;
    }

    final asksCount = _hasAny(lower, tokens, <String>[
      'headcount',
      'employee count',
      'ilan',
      'ilang',
      'how many',
      'total',
      'dami',
      'count',
      'bilang',
    ]);
    final asksCompany = _hasAny(lower, tokens, <String>[
      'company',
      'companies',
      'kumpanya',
      'subsidiary',
      'business unit',
    ]);
    final asksDepartment = _hasAny(lower, tokens, <String>[
      'department',
      'departments',
      'dept',
      'unit',
      'work unit',
      'departamento',
    ]);
    final asksPosition = _hasAny(lower, tokens, <String>[
      'position',
      'positions',
      'role',
      'job',
      'designation',
      'posisyon',
    ]);
    final asksPayroll = _hasAny(lower, tokens, <String>[
      'payroll',
      'class',
      'classification',
      'rank and file',
      'managerial',
      'admin class',
    ]);
    final asksPositionBreakdown = _hasAny(lower, tokens, <String>[
      'by position',
      'position breakdown',
      'position distribution',
      'per position',
    ]);
    final asksGender = _hasAny(lower, tokens, <String>[
      'gender',
      'sex',
      'male',
      'female',
      'lalaki',
      'babae',
    ]);
    final asksCivil = _hasAny(lower, tokens, <String>[
      'civil',
      'marital',
      'status',
      'single',
      'married',
      'widowed',
      'separated',
    ]);
    final asksAge = _hasAny(lower, tokens, <String>[
      'age',
      'edad',
      'older',
      'younger',
      'bracket',
      'age group',
    ]);
    final asksTenure = _hasAny(lower, tokens, <String>[
      'tenure',
      'service',
      'years in company',
      'tagal',
      'length of stay',
      'hired',
    ]);
    final asksMissing = _hasAny(lower, tokens, <String>[
      'missing',
      'kulang',
      'incomplete',
      'audit',
      'compliance',
      'no tin',
      'no sss',
      'no pagibig',
      'no philhealth',
      'blank',
    ]);
    final asksData =
        asksCount ||
        asksCompany ||
        asksDepartment ||
        asksPosition ||
        asksPayroll ||
        asksGender ||
        asksCivil ||
        asksAge ||
        asksTenure ||
        asksMissing;
    if (!asksData) {
      return 'I can do HR data analysis in Taglish and custom phrasing. Ask like: "ilan sa HYG na managerial", "gender mix ng Sales dept", "top company by headcount", "missing TIN and SSS", or "tenure summary for IT".';
    }

    final dataset = await _loadAssistDataset();
    final employees = dataset.employees;
    final profileByEmployeeId = dataset.profileByEmployeeId;

    final companyMention = _findMention(
      lower,
      employees.map((e) => e.companyName).toSet().toList(growable: false),
    );
    final departmentMention = _findMention(
      lower,
      employees.map((e) => e.departmentName).toSet().toList(growable: false),
    );
    final positionMention = _findMention(
      lower,
      employees.map((e) => e.positionName).toSet().toList(growable: false),
    );
    final payrollClassMention = _findPayrollClassMention(lower);

    final filteredEmployees = employees
        .where((e) {
          final companyOk =
              companyMention == null ||
              e.companyName.toLowerCase() == companyMention.toLowerCase();
          final departmentOk =
              departmentMention == null ||
              e.departmentName.toLowerCase() == departmentMention.toLowerCase();
          final positionOk =
              positionMention == null ||
              e.positionName.toLowerCase() == positionMention.toLowerCase();
          final payrollClassOk =
              payrollClassMention == null ||
              (profileByEmployeeId[e.id]?.payrollClass ?? '')
                      .trim()
                      .toLowerCase() ==
                  payrollClassMention.toLowerCase();
          return companyOk && departmentOk && positionOk && payrollClassOk;
        })
        .toList(growable: false);

    final scopeParts = <String>[];
    if (companyMention != null) scopeParts.add('Company: $companyMention');
    if (departmentMention != null) {
      scopeParts.add('Department: $departmentMention');
    }
    if (positionMention != null) scopeParts.add('Position: $positionMention');
    if (payrollClassMention != null) {
      scopeParts.add('Payroll class: $payrollClassMention');
    }
    final scope = scopeParts.isEmpty
        ? 'All active employees'
        : scopeParts.join(' | ');

    if (filteredEmployees.isEmpty) {
      return 'No matching employees found for: $scope.';
    }

    final sections = <String>['Scope: $scope'];
    final asksTop = _hasAny(lower, tokens, <String>[
      'top',
      'highest',
      'pinakamarami',
      'most',
    ]);

    if (asksCount) {
      sections.add('Total headcount: ${filteredEmployees.length}');
    }

    if (asksCompany) {
      sections.add(
        _summaryByField(
          title: asksTop ? 'Top company by headcount' : 'Headcount by company',
          values: filteredEmployees
              .map((e) => e.companyName)
              .toList(growable: false),
          topOnly: asksTop,
        ),
      );
    }

    if (asksDepartment) {
      sections.add(
        _summaryByField(
          title: asksTop
              ? 'Top department by headcount'
              : 'Headcount by department',
          values: filteredEmployees
              .map((e) => e.departmentName)
              .toList(growable: false),
          topOnly: asksTop,
        ),
      );
    }

    if (asksPosition && (!asksPayroll || asksPositionBreakdown)) {
      sections.add(
        _summaryByField(
          title: asksTop
              ? 'Top position by headcount'
              : 'Headcount by position',
          values: filteredEmployees
              .map((e) => e.positionName)
              .toList(growable: false),
          topOnly: asksTop,
        ),
      );
    }

    final filteredProfiles = filteredEmployees
        .map((e) => profileByEmployeeId[e.id])
        .toList(growable: false);
    if (asksPayroll) {
      sections.add(
        _summaryByField(
          title: 'Payroll class distribution',
          values: filteredProfiles
              .map((p) => p?.payrollClass)
              .toList(growable: false),
          includePercent: true,
        ),
      );
    }

    if (asksGender) {
      final genderValues = filteredProfiles
          .map((p) => p?.gender)
          .toList(growable: false);
      sections.add(
        _summaryByField(
          title: 'Gender demographics',
          values: genderValues,
          includePercent: true,
        ),
      );
      sections.add(_genderCoverageSummary(genderValues, lower));
    }

    if (asksCivil) {
      sections.add(
        _summaryByField(
          title: 'Civil status demographics',
          values: filteredProfiles
              .map((p) => p?.civilStatus)
              .toList(growable: false),
          includePercent: true,
        ),
      );
    }

    if (asksAge) {
      sections.add(_ageBracketSummary(filteredProfiles));
    }

    if (asksTenure) {
      sections.add(_tenureBucketSummary(filteredProfiles));
    }

    if (asksMissing) {
      sections.add(_missingFieldSummary(filteredProfiles));
    }

    return sections.join('\n\n');
  }

  Set<String> _tokens(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ');
    return cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
  }

  bool _hasAny(String lower, Set<String> tokens, List<String> keywords) {
    for (final keyword in keywords) {
      final normalized = keyword.toLowerCase().trim();
      if (normalized.contains(' ')) {
        if (lower.contains(normalized)) {
          return true;
        }
      } else if (tokens.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  Future<List<EmployeePreview>> _loadEmployees() async {
    if (_employeeCache != null) {
      return _employeeCache!;
    }
    final cachedRows = await LocalSyncService.loadCachedRows('employee_cache');
    if (cachedRows.isNotEmpty) {
      final cachedEmployees = cachedRows
          .map(EmployeeDirectoryService._fromRow)
          .toList(growable: false);
      _employeeCache = cachedEmployees;
      unawaited(_refreshEmployeeCacheInBackground());
      return cachedEmployees;
    }
    final employees = await EmployeeDirectoryService.loadEmployees();
    _employeeCache = employees;
    return employees;
  }

  Future<_AssistDataset> _loadAssistDataset() async {
    final employees = await _loadEmployees();
    final cachedProfiles =
        await LocalSyncService.loadCachedProfileDetailsByEmployeeId();
    final profileByEmployeeId = <String, EmployeeProfileDetails?>{};
    for (final employee in employees) {
      profileByEmployeeId[employee.id] = cachedProfiles[employee.id];
    }
    return _AssistDataset(
      employees: employees,
      profileByEmployeeId: profileByEmployeeId,
    );
  }

  Future<void> _refreshEmployeeCacheInBackground() async {
    try {
      final refreshed = await EmployeeDirectoryService.loadEmployees();
      if (!mounted) {
        return;
      }
      _employeeCache = refreshed;
    } catch (_) {}
  }

  Future<String?> _buildEmployeeNameLookupReply(String queryLower) async {
    final nameQuery = _extractEmployeeNameQuery(queryLower);
    if (nameQuery == null) {
      return null;
    }
    final employees = await _loadEmployees();
    final normalizedNeedle = nameQuery.toLowerCase().trim();
    final matches = employees
        .where((employee) {
          final haystack =
              '${employee.name} ${employee.idNumber} ${employee.email ?? ''}'
                  .toLowerCase();
          return haystack.contains(normalizedNeedle);
        })
        .toList(growable: false);

    if (matches.isEmpty) {
      return 'I checked the local SQLite cache and found no employee matching "$nameQuery".';
    }

    final lines = <String>[
      'Yes. I found ${matches.length} employee(s) in local SQLite for "$nameQuery":',
    ];
    for (final employee in matches.take(8)) {
      lines.add(
        '- ${employee.name} | ${employee.companyName} | ${employee.departmentName} | ${employee.positionName}',
      );
    }
    if (matches.length > 8) {
      lines.add('- ...and ${matches.length - 8} more');
    }
    return lines.join('\n');
  }

  String? _extractEmployeeNameQuery(String queryLower) {
    final patterns = <RegExp>[
      RegExp(r'employee named\s+([a-z][a-z\-\s]{1,40})'),
      RegExp(r'employee name\s+([a-z][a-z\-\s]{1,40})'),
      RegExp(r'named\s+([a-z][a-z\-\s]{1,40})'),
      RegExp(r'do you have\s+([a-z][a-z\-\s]{1,40})'),
      RegExp(r'may employee (?:na )?pangalan\s+([a-z][a-z\-\s]{1,40})'),
      RegExp(r'find employee\s+([a-z][a-z\-\s]{1,40})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(queryLower);
      if (match == null) {
        continue;
      }
      final raw = (match.group(1) ?? '').trim();
      final cleaned = raw
          .replaceAll(RegExp(r'[^a-z\-\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length >= 2) {
        return cleaned
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
      }
    }
    return null;
  }

  String _summaryByField({
    required String title,
    required List<String?> values,
    bool topOnly = false,
    bool includePercent = false,
  }) {
    final Map<String, int> counts = <String, int>{};
    for (final raw in values) {
      final key = (raw ?? '').trim().isEmpty || raw == '-'
          ? 'Unspecified'
          : raw!.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) {
          return byCount;
        }
        return a.key.compareTo(b.key);
      });
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final lineEntries = topOnly && entries.isNotEmpty
        ? <MapEntry<String, int>>[entries.first]
        : entries;
    final lines = lineEntries
        .map((e) {
          if (!includePercent || total == 0) {
            return '- ${e.key}: ${e.value}';
          }
          final pct = ((e.value / total) * 100).toStringAsFixed(1);
          return '- ${e.key}: ${e.value} ($pct%)';
        })
        .join('\n');
    return '$title\n$lines';
  }

  String _genderCoverageSummary(List<String?> values, String queryLower) {
    int male = 0;
    int female = 0;
    int unspecified = 0;
    for (final raw in values) {
      final g = (raw ?? '').trim().toLowerCase();
      if (g.isEmpty || g == '-') {
        unspecified++;
      } else if (g == 'male' || g == 'm') {
        male++;
      } else if (g == 'female' || g == 'f') {
        female++;
      } else {
        unspecified++;
      }
    }
    final known = male + female;
    final total = known + unspecified;
    final lines = <String>[
      'Known gender records: $known / $total',
      'Male: $male',
      'Female: $female',
      'Unspecified: $unspecified',
    ];
    if (queryLower.contains('male') || queryLower.contains('lalaki')) {
      lines.insert(
        0,
        'Direct answer: $male male employee(s) in the selected scope.',
      );
    } else if (queryLower.contains('female') || queryLower.contains('babae')) {
      lines.insert(
        0,
        'Direct answer: $female female employee(s) in the selected scope.',
      );
    }
    return lines.join('\n');
  }

  String _buildHrContextSnapshot(
    List<EmployeePreview> employees,
    List<EmployeeProfileDetails?> profiles,
  ) {
    final company = _summaryByField(
      title: 'Company headcount',
      values: employees.map((e) => e.companyName).toList(growable: false),
    );
    final department = _summaryByField(
      title: 'Department headcount',
      values: employees.map((e) => e.departmentName).toList(growable: false),
      topOnly: true,
    );
    final payroll = _summaryByField(
      title: 'Payroll classes',
      values: profiles.map((p) => p?.payrollClass).toList(growable: false),
      includePercent: true,
    );
    return 'Total active employees: ${employees.length}\n\n$company\n\n$department\n\n$payroll';
  }

  String? _findMention(String queryLower, List<String> candidates) {
    String? best;
    int bestLen = 0;
    for (final candidate in candidates) {
      final c = candidate.trim();
      if (c.isEmpty || c == '-') {
        continue;
      }
      final cLower = c.toLowerCase();
      if (queryLower.contains(cLower) && cLower.length > bestLen) {
        best = c;
        bestLen = cLower.length;
      }
    }
    return best;
  }

  String? _findPayrollClassMention(String queryLower) {
    if (queryLower.contains('rank and file') ||
        queryLower.contains('rank & file')) {
      return 'Rank and File';
    }
    if (queryLower.contains('managerial') || queryLower.contains('manager')) {
      return 'Managerial';
    }
    if (queryLower.contains('admin')) {
      return 'Admin';
    }
    return null;
  }

  String _ageBracketSummary(List<EmployeeProfileDetails?> profiles) {
    final Map<String, int> buckets = <String, int>{
      '18-24': 0,
      '25-34': 0,
      '35-44': 0,
      '45-54': 0,
      '55+': 0,
      'Unspecified': 0,
    };
    final now = DateTime.now();
    for (final profile in profiles) {
      final birthDate = _safeDate(profile?.birthDate);
      if (birthDate == null) {
        buckets['Unspecified'] = buckets['Unspecified']! + 1;
        continue;
      }
      final age = _yearsBetween(birthDate, now);
      if (age < 25) {
        buckets['18-24'] = buckets['18-24']! + 1;
      } else if (age < 35) {
        buckets['25-34'] = buckets['25-34']! + 1;
      } else if (age < 45) {
        buckets['35-44'] = buckets['35-44']! + 1;
      } else if (age < 55) {
        buckets['45-54'] = buckets['45-54']! + 1;
      } else {
        buckets['55+'] = buckets['55+']! + 1;
      }
    }
    final lines = buckets.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    return 'Age bracket summary\n$lines';
  }

  String _tenureBucketSummary(List<EmployeeProfileDetails?> profiles) {
    final Map<String, int> buckets = <String, int>{
      '<1 year': 0,
      '1-2 years': 0,
      '3-5 years': 0,
      '6-10 years': 0,
      '10+ years': 0,
      'Unspecified': 0,
    };
    final now = DateTime.now();
    for (final profile in profiles) {
      final hiredDate = _safeDate(profile?.dateHired);
      if (hiredDate == null) {
        buckets['Unspecified'] = buckets['Unspecified']! + 1;
        continue;
      }
      final years = _yearsBetween(hiredDate, now);
      if (years < 1) {
        buckets['<1 year'] = buckets['<1 year']! + 1;
      } else if (years <= 2) {
        buckets['1-2 years'] = buckets['1-2 years']! + 1;
      } else if (years <= 5) {
        buckets['3-5 years'] = buckets['3-5 years']! + 1;
      } else if (years <= 10) {
        buckets['6-10 years'] = buckets['6-10 years']! + 1;
      } else {
        buckets['10+ years'] = buckets['10+ years']! + 1;
      }
    }
    final lines = buckets.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    return 'Tenure bucket summary\n$lines';
  }

  String _missingFieldSummary(List<EmployeeProfileDetails?> profiles) {
    int missingTin = 0;
    int missingSss = 0;
    int missingPagibig = 0;
    int missingPhilhealth = 0;
    int missingBirthDate = 0;
    int missingGender = 0;
    int missingCivilStatus = 0;
    int missingHiredDate = 0;

    bool isBlank(String? value) =>
        value == null || value.trim().isEmpty || value.trim() == '-';

    for (final profile in profiles) {
      if (isBlank(profile?.tin)) missingTin++;
      if (isBlank(profile?.sss)) missingSss++;
      if (isBlank(profile?.pagibig)) missingPagibig++;
      if (isBlank(profile?.philhealth)) missingPhilhealth++;
      if (isBlank(profile?.birthDate)) missingBirthDate++;
      if (isBlank(profile?.gender)) missingGender++;
      if (isBlank(profile?.civilStatus)) missingCivilStatus++;
      if (isBlank(profile?.dateHired)) missingHiredDate++;
    }

    return 'Missing fields audit\n'
        '- TIN missing: $missingTin\n'
        '- SSS missing: $missingSss\n'
        '- Pag-IBIG missing: $missingPagibig\n'
        '- PhilHealth missing: $missingPhilhealth\n'
        '- Birth date missing: $missingBirthDate\n'
        '- Gender missing: $missingGender\n'
        '- Civil status missing: $missingCivilStatus\n'
        '- Hired date missing: $missingHiredDate';
  }

  DateTime? _safeDate(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == '-') {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  int _yearsBetween(DateTime start, DateTime end) {
    int years = end.year - start.year;
    if (end.month < start.month ||
        (end.month == start.month && end.day < start.day)) {
      years -= 1;
    }
    return years < 0 ? 0 : years;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _AssistMessage {
  const _AssistMessage({
    required this.fromUser,
    required this.text,
    this.isTyping = false,
    this.responseTimeMs,
  });

  final bool fromUser;
  final String text;
  final bool isTyping;
  final int? responseTimeMs;
}

class _AssistDataset {
  const _AssistDataset({
    required this.employees,
    required this.profileByEmployeeId,
  });

  final List<EmployeePreview> employees;
  final Map<String, EmployeeProfileDetails?> profileByEmployeeId;
}

class _AssistBubble extends StatelessWidget {
  const _AssistBubble({
    required this.isUser,
    required this.text,
    this.isTyping = false,
    this.responseTimeMs,
  });

  final bool isUser;
  final String text;
  final bool isTyping;
  final int? responseTimeMs;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? HygColors.panel : const Color(0xFFFFF8DB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: isTyping
                  ? const SizedBox(
                      width: 36,
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        color: HygColors.goldStrong,
                        backgroundColor: Color(0xFFE2E8F0),
                      ),
                    )
                  : Text(
                      text,
                      style: TextStyle(
                        color: isUser ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        height: 1.35,
                      ),
                    ),
            ),
            if (!isUser && !isTyping && responseTimeMs != null) ...[
              const SizedBox(height: 4),
              Text(
                'Responded in ${_formatElapsed(responseTimeMs!)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatElapsed(int ms) {
    if (ms < 1000) {
      return '$ms ms';
    }
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(2)} s';
  }
}
