part of '../main.dart';

class EmployeesHeader extends StatelessWidget {
  const EmployeesHeader({required this.onAddEmployee, super.key});

  final VoidCallback onAddEmployee;

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
            child: const Icon(Icons.group, color: HygColors.goldStrong),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Employees', style: HygTypography.pageTitle),
                SizedBox(height: 3),
                Text(
                  'Manage employee records and quickly find team members.',
                  style: HygTypography.body,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(150, 44),
              foregroundColor: HygColors.ink,
              side: const BorderSide(color: HygColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {},
            icon: const Icon(Icons.cloud_upload, size: 17),
            label: const Text('Import Employees'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(136, 44),
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAddEmployee,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Employee'),
          ),
        ],
      ),
    );
  }
}

class AddEmployeeProfileModal extends StatefulWidget {
  const AddEmployeeProfileModal({this.employee, super.key});

  final EmployeePreview? employee;

  @override
  State<AddEmployeeProfileModal> createState() =>
      _AddEmployeeProfileModalState();
}

class _AddEmployeeProfileModalState extends State<AddEmployeeProfileModal> {
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _suffixController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _ageController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otherPhoneController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _socialMediaTypeController = TextEditingController();
  final _socialMediaDetailController = TextEditingController();
  final _presentAddressController = TextEditingController();
  final _permanentAddressController = TextEditingController();
  final _dateHiredController = TextEditingController();
  final _religionController = TextEditingController();
  final _heightController = TextEditingController();
  final _heightCmController = TextEditingController();
  final _weightController = TextEditingController();
  final _weightKgController = TextEditingController();
  final _bmiController = TextEditingController();
  final _bmiClassificationController = TextEditingController();
  final _tinController = TextEditingController();
  final _sssController = TextEditingController();
  final _pagibigController = TextEditingController();
  final _philhealthController = TextEditingController();
  final _accountNoController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyContactNoController = TextEditingController();
  final _elementarySchoolController = TextEditingController();
  final _elementaryYearController = TextEditingController();
  final _secondarySchoolController = TextEditingController();
  final _secondaryYearController = TextEditingController();
  final _collegeSchoolController = TextEditingController();
  final _collegeYearController = TextEditingController();
  final _collegeCourseController = TextEditingController();
  final _yearGraduatedController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _fatherOccupationController = TextEditingController();
  final _motherMaidenNameController = TextEditingController();
  final _motherOccupationController = TextEditingController();
  final _numberOfSiblingsController = TextEditingController();
  final _birthOrderController = TextEditingController();
  final _spouseNameController = TextEditingController();
  final _spouseOccupationController = TextEditingController();
  final _spouseContactController = TextEditingController();
  final _childrenNamesController = TextEditingController();
  final _childrenCountController = TextEditingController();
  late final List<TextEditingController> _childNameControllers;
  late final List<TextEditingController> _childBirthdayControllers;
  late final List<TextEditingController> _childAgeControllers;
  Uint8List? _photoBytes;
  String? _photoFileName;
  String? _existingPhotoUrl;
  String _gender = 'Select';
  String _civilStatus = 'Select';
  String _company = 'Select';
  String _department = 'Select';
  String _store = 'N/A';
  String _position = 'Select';
  String _employeeType = 'Probationary';
  String _employmentStatus = 'pending';
  String _payrollClass = 'Rank and File';
  String _bankType = 'BDO';
  String _scheduleStart = '09:00 AM';
  String _scheduleEnd = '06:00 PM';
  String _dayOffDay = 'Sunday';
  static const _maxChildRows = 6;
  var _companyOptions = <String>[];
  var _departmentOptions = <String>[];
  var _stores = <StorePreview>[];
  var _positionOptions = <String>[];
  String? _companyLoadError;
  String? _departmentLoadError;
  String? _storeLoadError;
  String? _positionLoadError;
  bool _isLoadingCompanyOptions = true;
  bool _isLoadingDepartmentOptions = true;
  bool _isLoadingStoreOptions = true;
  bool _isLoadingPositionOptions = true;
  bool _isSaving = false;
  bool _isSeedingBodyMetrics = false;
  String? _formError;

  static final List<String> _timeOptions = List<String>.generate(48, (index) {
    final hour24 = index ~/ 2;
    final minute = index.isEven ? 0 : 30;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12Raw = hour24 % 12;
    final hour12 = hour12Raw == 0 ? 12 : hour12Raw;
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  });

  @override
  void initState() {
    super.initState();
    _childNameControllers = List.generate(
      _maxChildRows,
      (_) => TextEditingController(),
    );
    _childBirthdayControllers = List.generate(
      _maxChildRows,
      (_) => TextEditingController(),
    );
    _childAgeControllers = List.generate(
      _maxChildRows,
      (_) => TextEditingController(),
    );
    _heightCmController.addListener(_syncBodyMetrics);
    _weightKgController.addListener(_syncBodyMetrics);
    for (final controller in _childNameControllers) {
      controller.addListener(_syncChildrenFields);
    }
    for (var i = 0; i < _childBirthdayControllers.length; i += 1) {
      _childBirthdayControllers[i].addListener(() {
        _updateChildAge(i);
        _syncChildrenFields();
      });
    }
    _seedEmployeeFields();
    _seedBodyMetricFields();
    _seedChildFields();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadCompanyOptions();
      _loadDepartmentOptions();
      _loadStoreOptions();
      _loadPositionOptions();
      _loadEmployeeProfileForEdit();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _suffixController.dispose();
    _idNumberController.dispose();
    _birthDateController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otherPhoneController.dispose();
    _zipCodeController.dispose();
    _socialMediaTypeController.dispose();
    _socialMediaDetailController.dispose();
    _presentAddressController.dispose();
    _permanentAddressController.dispose();
    _dateHiredController.dispose();
    _religionController.dispose();
    _heightController.dispose();
    _heightCmController.dispose();
    _weightController.dispose();
    _weightKgController.dispose();
    _bmiController.dispose();
    _bmiClassificationController.dispose();
    _tinController.dispose();
    _sssController.dispose();
    _pagibigController.dispose();
    _philhealthController.dispose();
    _accountNoController.dispose();
    _emergencyContactController.dispose();
    _emergencyContactNoController.dispose();
    _elementarySchoolController.dispose();
    _elementaryYearController.dispose();
    _secondarySchoolController.dispose();
    _secondaryYearController.dispose();
    _collegeSchoolController.dispose();
    _collegeYearController.dispose();
    _collegeCourseController.dispose();
    _yearGraduatedController.dispose();
    _fatherNameController.dispose();
    _fatherOccupationController.dispose();
    _motherMaidenNameController.dispose();
    _motherOccupationController.dispose();
    _numberOfSiblingsController.dispose();
    _birthOrderController.dispose();
    _spouseNameController.dispose();
    _spouseOccupationController.dispose();
    _spouseContactController.dispose();
    _childrenNamesController.dispose();
    _childrenCountController.dispose();
    for (final controller in _childNameControllers) {
      controller.dispose();
    }
    for (final controller in _childBirthdayControllers) {
      controller.dispose();
    }
    for (final controller in _childAgeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedEmployeeFields() {
    final employee = widget.employee;
    if (employee == null) {
      return;
    }

    final nameParts = employee.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (nameParts.isNotEmpty) {
      _firstNameController.text = nameParts.first;
    }
    if (nameParts.length > 2) {
      _middleNameController.text = nameParts
          .sublist(1, nameParts.length - 1)
          .join(' ');
    }
    if (nameParts.length > 1) {
      _lastNameController.text = nameParts.last;
    }

    _emailController.text = employee.email?.trim() ?? '';
    _phoneController.text = employee.phone?.trim() ?? '';
    _idNumberController.text = employee.idNumber == 'None'
        ? ''
        : employee.idNumber;
    _dateHiredController.text =
        employee.rawHiredDate ?? (employee.hired == '-' ? '' : employee.hired);
    _existingPhotoUrl = employee.photoUrl?.trim();
    _updateAgeFromBirthDate(_birthDateController.text);

    if (employee.companyName.trim().isNotEmpty && employee.companyName != '-') {
      _company = employee.companyName.trim();
    }
    if (employee.positionName.trim().isNotEmpty &&
        employee.positionName != '-') {
      _position = employee.positionName.trim();
    }
    if (employee.departmentName.trim().isNotEmpty &&
        employee.departmentName != '-') {
      _department = employee.departmentName.trim();
    }
    if (employee.status.trim().isNotEmpty) {
      _employmentStatus = employee.status.trim().toLowerCase();
    }
  }

  Future<void> _pickEmployeePhoto() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );

    final file = result?.files.single;
    if (file == null) {
      return;
    }

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      return;
    }

    setState(() {
      _photoBytes = bytes;
      _photoFileName = file.name;
      _existingPhotoUrl = null;
    });
  }

  Future<void> _loadEmployeeProfileForEdit() async {
    final employee = widget.employee;
    if (employee == null) {
      return;
    }

    try {
      final details = await EmployeeDirectoryService.loadEmployeeProfile(
        employee.id,
      );
      if (!mounted || details == null) {
        return;
      }
      _applyProfileDetails(details);
    } catch (_) {
      // Keep modal usable even if detailed profile fetch is unavailable.
    }
  }

  void _applyProfileDetails(EmployeeProfileDetails details) {
    setState(() {
      _firstNameController.text =
          details.firstName ?? _firstNameController.text;
      _middleNameController.text =
          details.middleName ?? _middleNameController.text;
      _lastNameController.text = details.lastName ?? _lastNameController.text;
      _suffixController.text = details.suffix ?? _suffixController.text;
      _idNumberController.text = details.idNumber ?? _idNumberController.text;
      _birthDateController.text =
          details.birthDate ?? _birthDateController.text;
      _emailController.text = details.email ?? _emailController.text;
      _phoneController.text = details.phone ?? _phoneController.text;
      _otherPhoneController.text =
          details.otherPhone ?? _otherPhoneController.text;
      _zipCodeController.text = details.zipCode ?? _zipCodeController.text;
      _socialMediaTypeController.text =
          details.socialMediaType ?? _socialMediaTypeController.text;
      _socialMediaDetailController.text =
          details.socialMediaDetail ?? _socialMediaDetailController.text;
      _presentAddressController.text =
          details.presentAddress ?? _presentAddressController.text;
      _permanentAddressController.text =
          details.permanentAddress ?? _permanentAddressController.text;
      _dateHiredController.text =
          details.dateHired ?? _dateHiredController.text;
      _religionController.text = details.religion ?? _religionController.text;
      _heightController.text = details.height ?? _heightController.text;
      _weightController.text = details.weight ?? _weightController.text;
      _tinController.text = details.tin ?? _tinController.text;
      _sssController.text = details.sss ?? _sssController.text;
      _pagibigController.text = details.pagibig ?? _pagibigController.text;
      _philhealthController.text =
          details.philhealth ?? _philhealthController.text;
      _accountNoController.text =
          details.accountNo ?? _accountNoController.text;
      _emergencyContactController.text =
          details.emergencyContact ?? _emergencyContactController.text;
      _emergencyContactNoController.text =
          details.emergencyContactNo ?? _emergencyContactNoController.text;
      _elementarySchoolController.text =
          details.elementarySchool ?? _elementarySchoolController.text;
      _elementaryYearController.text =
          details.elementaryYear ?? _elementaryYearController.text;
      _secondarySchoolController.text =
          details.secondarySchool ?? _secondarySchoolController.text;
      _secondaryYearController.text =
          details.secondaryYear ?? _secondaryYearController.text;
      _collegeSchoolController.text =
          details.collegeSchool ?? _collegeSchoolController.text;
      _collegeYearController.text =
          details.collegeYear ?? _collegeYearController.text;
      _collegeCourseController.text =
          details.collegeCourse ?? _collegeCourseController.text;
      _yearGraduatedController.text =
          details.yearGraduated ?? _yearGraduatedController.text;
      _fatherNameController.text =
          details.fatherName ?? _fatherNameController.text;
      _fatherOccupationController.text =
          details.fatherOccupation ?? _fatherOccupationController.text;
      _motherMaidenNameController.text =
          details.motherMaidenName ?? _motherMaidenNameController.text;
      _motherOccupationController.text =
          details.motherOccupation ?? _motherOccupationController.text;
      _numberOfSiblingsController.text =
          details.numberOfSiblings ?? _numberOfSiblingsController.text;
      _birthOrderController.text =
          details.birthOrder ?? _birthOrderController.text;
      _spouseNameController.text =
          details.spouseName ?? _spouseNameController.text;
      _spouseOccupationController.text =
          details.spouseOccupation ?? _spouseOccupationController.text;
      _spouseContactController.text =
          details.spouseContact ?? _spouseContactController.text;
      _childrenNamesController.text =
          details.childrenNames ?? _childrenNamesController.text;
      _childrenCountController.text =
          details.childrenCount ?? _childrenCountController.text;
      _seedBodyMetricFields();
      _seedChildFields();

      if (details.gender != null && details.gender!.isNotEmpty) {
        _gender = details.gender!;
      }
      if (details.civilStatus != null && details.civilStatus!.isNotEmpty) {
        _civilStatus = details.civilStatus!;
      }
      if (details.companyName != null && details.companyName!.isNotEmpty) {
        _company = details.companyName!;
      }
      if (details.departmentName != null &&
          details.departmentName!.isNotEmpty) {
        _department = details.departmentName!;
      }
      if (details.storeName != null && details.storeName!.isNotEmpty) {
        _store = details.storeName!;
      }
      if (details.positionName != null && details.positionName!.isNotEmpty) {
        _position = details.positionName!;
      }
      if (details.employeeType != null && details.employeeType!.isNotEmpty) {
        _employeeType = details.employeeType!;
      }
      if (details.payrollClass != null && details.payrollClass!.isNotEmpty) {
        _payrollClass = details.payrollClass!;
      }
      if (details.bankType != null && details.bankType!.isNotEmpty) {
        _bankType = details.bankType!;
      }
      if (details.dayOffDay != null && details.dayOffDay!.isNotEmpty) {
        _dayOffDay = details.dayOffDay!;
      }
      if (details.schedule != null && details.schedule!.isNotEmpty) {
        final parsed = _parseScheduleRange(details.schedule!);
        _scheduleStart = parsed.$1;
        _scheduleEnd = parsed.$2;
      }
    });

    _updateAgeFromBirthDate(_birthDateController.text);
  }

  void _updateAgeFromBirthDate(String dateText) {
    final parsed = _parseDate(dateText, required: false);
    if (parsed == null) {
      _ageController.text = '';
      return;
    }
    final birthDate = DateTime.tryParse(parsed);
    if (birthDate == null) {
      _ageController.text = '';
      return;
    }
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hasBirthdayPassed =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasBirthdayPassed) {
      age -= 1;
    }
    _ageController.text = age < 0 ? '' : age.toString();
  }

  void _seedBodyMetricFields() {
    _isSeedingBodyMetrics = true;
    try {
      final height = _parseHeightCm(_heightController.text);
      final weight = _parseWeightKg(_weightController.text);
      _heightCmController.text = height;
      _weightKgController.text = weight;
    } finally {
      _isSeedingBodyMetrics = false;
    }
    _syncBodyMetrics();
  }

  void _syncBodyMetrics() {
    if (_isSeedingBodyMetrics) {
      return;
    }
    final heightCm = double.tryParse(_heightCmController.text.trim()) ?? 0;
    final weightKg = double.tryParse(_weightKgController.text.trim()) ?? 0;
    _heightController.text = heightCm > 0
        ? '${heightCm.toStringAsFixed(heightCm.truncateToDouble() == heightCm ? 0 : 1)} cm'
        : '';
    _weightController.text = weightKg > 0
        ? '${weightKg.toStringAsFixed(weightKg.truncateToDouble() == weightKg ? 0 : 1)} kg'
        : '';
    if (heightCm <= 0 || weightKg <= 0) {
      _bmiController.text = '';
      _bmiClassificationController.text = '';
      return;
    }
    final meters = heightCm / 100;
    final bmi = weightKg / (meters * meters);
    _bmiController.text = bmi.toStringAsFixed(1);
    _bmiClassificationController.text = _bmiClassification(bmi);
  }

  void _seedChildFields() {
    final children = _parseChildren(_childrenNamesController.text);
    for (var i = 0; i < _maxChildRows; i += 1) {
      _childNameControllers[i].text = i < children.length ? children[i].$1 : '';
      _childBirthdayControllers[i].text = i < children.length
          ? children[i].$2
          : '';
      _updateChildAge(i);
    }
    _syncChildrenFields();
  }

  void _updateChildAge(int index) {
    final parsed = _parseDate(
      _childBirthdayControllers[index].text,
      required: false,
    );
    if (parsed == null) {
      _childAgeControllers[index].text = '';
      return;
    }
    final date = DateTime.tryParse(parsed);
    if (date == null) {
      _childAgeControllers[index].text = '';
      return;
    }
    final now = DateTime.now();
    var age = now.year - date.year;
    final passed =
        now.month > date.month ||
        (now.month == date.month && now.day >= date.day);
    if (!passed) age -= 1;
    _childAgeControllers[index].text = age < 0 ? '' : age.toString();
  }

  void _syncChildrenFields() {
    final lines = <String>[];
    for (var i = 0; i < _maxChildRows; i += 1) {
      final name = _childNameControllers[i].text.trim();
      final birthday = _childBirthdayControllers[i].text.trim();
      final age = _childAgeControllers[i].text.trim();
      if (name.isEmpty && birthday.isEmpty) continue;
      lines.add('$name | $birthday | Age $age'.trim());
    }
    _childrenNamesController.text = lines.join('\n');
    _childrenCountController.text = lines.length.toString();
  }

  String _parseHeightCm(String value) {
    final lower = value.toLowerCase();
    final cmMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:cm|centimeter|centimeters)',
    ).firstMatch(lower);
    if (cmMatch != null) {
      final heightCm = double.tryParse(cmMatch.group(1) ?? '') ?? 0;
      return heightCm > 0
          ? heightCm.toStringAsFixed(
              heightCm.truncateToDouble() == heightCm ? 0 : 1,
            )
          : '';
    }
    final feetMatch = RegExp(
      r"(\d+(?:\.\d+)?)\s*(?:ft|feet|'|f)",
    ).firstMatch(lower);
    final inchMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:in|inch|inches|")',
    ).firstMatch(lower);
    if (feetMatch != null || inchMatch != null) {
      final feet = double.tryParse(feetMatch?.group(1) ?? '') ?? 0;
      final inches = double.tryParse(inchMatch?.group(1) ?? '') ?? 0;
      final totalInches = (feet * 12) + inches;
      final heightCm = totalInches * 2.54;
      return heightCm > 0
          ? heightCm.toStringAsFixed(
              heightCm.truncateToDouble() == heightCm ? 0 : 1,
            )
          : '';
    }
    final numeric = double.tryParse(lower.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (numeric == null || numeric <= 0) return '';
    return numeric.toStringAsFixed(
      numeric.truncateToDouble() == numeric ? 0 : 1,
    );
  }

  String _parseWeightKg(String value) {
    final numeric = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (numeric == null || numeric <= 0) return '';
    return numeric.toStringAsFixed(
      numeric.truncateToDouble() == numeric ? 0 : 1,
    );
  }

  List<(String, String)> _parseChildren(String value) {
    return value
        .split(RegExp(r'[\n,;]+'))
        .map((line) {
          final parts = line.split('|').map((part) => part.trim()).toList();
          if (parts.isEmpty || parts.first.isEmpty) return null;
          final birthday = parts.length > 1 ? parts[1] : '';
          return (parts.first, birthday);
        })
        .whereType<(String, String)>()
        .take(_maxChildRows)
        .toList();
  }

  String _bmiClassification(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  Future<void> _loadCompanyOptions() async {
    setState(() {
      _isLoadingCompanyOptions = true;
      _companyLoadError = null;
    });

    try {
      final companies = await CompanyDirectoryService.loadCompanies();
      if (!mounted) return;

      final names =
          companies
              .where((company) => company.status.toLowerCase() == 'active')
              .map((company) => company.name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      setState(() {
        _companyOptions = names;
        _company = _resolveLoadedOption(_company, names);
        _isLoadingCompanyOptions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _companyLoadError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingCompanyOptions = false;
      });
    }
  }

  Future<void> _loadDepartmentOptions() async {
    setState(() {
      _isLoadingDepartmentOptions = true;
      _departmentLoadError = null;
    });

    try {
      final departments = await DepartmentDirectoryService.loadDepartments();
      if (!mounted) return;

      final names =
          departments
              .map((department) => department.name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      setState(() {
        _departmentOptions = names;
        _department = _resolveLoadedOption(_department, names);
        _isLoadingDepartmentOptions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _departmentLoadError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingDepartmentOptions = false;
      });
    }
  }

  Future<void> _loadPositionOptions() async {
    setState(() {
      _isLoadingPositionOptions = true;
      _positionLoadError = null;
    });

    try {
      final positions = await PositionDirectoryService.loadPositions();
      if (!mounted) return;

      final names =
          positions
              .map((position) => position.name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      setState(() {
        _positionOptions = names;
        _position = _resolveLoadedOption(_position, names);
        _isLoadingPositionOptions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _positionLoadError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingPositionOptions = false;
      });
    }
  }

  Future<void> _loadStoreOptions() async {
    setState(() {
      _isLoadingStoreOptions = true;
      _storeLoadError = null;
    });
    try {
      final stores = await StoreDirectoryService.loadStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _store = _resolveLoadedOption(_store, _storeOptions);
        _isLoadingStoreOptions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storeLoadError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingStoreOptions = false;
      });
    }
  }

  List<String> get _storeOptions {
    if (_company == 'Select') return const ['N/A'];
    final names =
        _stores
            .where(
              (store) =>
                  _normalizeOption(store.companyName) ==
                  _normalizeOption(_company),
            )
            .map((store) => store.name)
            .toSet()
            .toList()
          ..sort();
    return ['N/A', ...names];
  }

  void _selectCompany(String value) {
    setState(() {
      _company = value;
      if (!_storeOptions.any(
        (store) => _normalizeOption(store) == _normalizeOption(_store),
      )) {
        _store = 'N/A';
      }
    });
  }

  String _resolveLoadedOption(String currentValue, List<String> options) {
    final normalizedCurrent = _normalizeOption(currentValue);
    if (normalizedCurrent.isEmpty ||
        normalizedCurrent == _normalizeOption('Select')) {
      return 'Select';
    }

    for (final option in options) {
      if (_normalizeOption(option) == normalizedCurrent) {
        return option;
      }
    }

    return currentValue;
  }

  String _normalizeOption(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  Future<void> _saveEmployee() async {
    final payload = _employeePayload();
    if (payload == null) {
      return;
    }

    if (widget.employee != null) {
      final confirmed = await _confirmEmployeeUpdate();
      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      String? employeeId;
      if (widget.employee == null) {
        final createdId = await EmployeeDirectoryService.createEmployee(
          payload,
        );
        employeeId = createdId.trim();
      } else {
        await EmployeeDirectoryService.updateEmployee(
          id: widget.employee!.id,
          payload: payload,
        );
        employeeId = widget.employee!.id;
      }

      if (_photoBytes != null && _looksLikeUuid(employeeId)) {
        final uploadedPhotoUrl =
            await EmployeeDirectoryService.uploadEmployeePhoto(
              employeeId: employeeId,
              bytes: _photoBytes!,
              fileName: _photoFileName ?? 'employee_photo.jpg',
            );
        await EmployeeDirectoryService.setEmployeePhotoUrl(
          employeeId: employeeId,
          photoUrl: uploadedPhotoUrl,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = _employeeSaveErrorMessage(error);
        _isSaving = false;
      });
    }
  }

  String _employeeSaveErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');

    if (message.contains('hr_set_employee_status')) {
      return 'Employee status update function is missing. Apply migration 0058_hr_set_employee_status.sql, then retry.';
    }

    if (message.contains('create_employee_profile_with_store') ||
        message.contains('create_employee_profile')) {
      return 'Employee create function is missing or outdated. Apply the latest employee profile migrations, then retry.';
    }

    if (message.contains('hr_update_employee_profile')) {
      return 'Employee update function is outdated. Apply migration 0059_hr_profile_schedule_dayoff.sql, then retry.';
    }

    if (message.contains('time_schedule') || message.contains('day_off')) {
      return 'Employee profile schedule/day-off columns are missing. Apply migration 0060_fix_employee_profile_schedule_columns.sql, then retry.';
    }

    if (message.contains('PGRST202')) {
      return 'A required Supabase RPC function is missing or outdated. Re-apply migrations 0058, 0059, and 0060, then retry.';
    }

    return message;
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }

  Future<bool?> _confirmEmployeeUpdate() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Update employee?'),
        content: Text(
          'Are you sure you want to update ${_firstNameController.text.trim()} ${_lastNameController.text.trim()}?',
          style: HygTypography.tableBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Update'),
          ),
        ],
      ),
    );
  }

  EmployeeProfilePayload? _employeePayload() {
    _syncBodyMetrics();
    _syncChildrenFields();
    final isEditing = widget.employee != null;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final dateHired = _parseDate(
      _dateHiredController.text,
      required: !isEditing,
    );
    final birthDate = _parseDate(_birthDateController.text, required: false);

    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() => _formError = 'First name and last name are required.');
      return null;
    }
    if (!isEditing && phone.isEmpty) {
      setState(() => _formError = 'Phone number is required.');
      return null;
    }
    if (!isEditing &&
        (_company == 'Select' ||
            _department == 'Select' ||
            _position == 'Select')) {
      setState(
        () => _formError = 'Company, department, and position are required.',
      );
      return null;
    }
    if (!isEditing && dateHired == null) {
      setState(() => _formError = 'Date hired must be a valid date.');
      return null;
    }

    return EmployeeProfilePayload(
      firstName: firstName,
      middleName: _middleNameController.text.trim(),
      lastName: lastName,
      suffix: _suffixController.text.trim(),
      birthDate: birthDate,
      gender: _selectedValue(_gender),
      civilStatus: _selectedValue(_civilStatus),
      phone: phone.isEmpty ? null : phone,
      email: _emailController.text.trim(),
      company: _selectedValue(_company),
      department: _selectedValue(_department),
      store: _selectedValue(_store),
      position: _selectedValue(_position),
      dateHired: dateHired,
      employeeType: _employeeType,
      employmentStatus: _employmentStatus,
      schedule: '$_scheduleStart - $_scheduleEnd',
      dayOffDay: _dayOffDay,
      payrollClass: _payrollClass,
      tin: _tinController.text.trim(),
      sss: _sssController.text.trim(),
      pagibig: _pagibigController.text.trim(),
      philhealth: _philhealthController.text.trim(),
      bankType: _bankType,
      accountNo: _accountNoController.text.trim(),
      presentAddress: _presentAddressController.text.trim(),
      emergencyContact: _emergencyContactController.text.trim(),
      emergencyContactNo: _emergencyContactNoController.text.trim(),
      zipCode: _zipCodeController.text.trim(),
      socialMediaType: _socialMediaTypeController.text.trim(),
      socialMediaDetail: _socialMediaDetailController.text.trim(),
      otherPhone: _otherPhoneController.text.trim(),
      permanentAddress: _permanentAddressController.text.trim(),
      religion: _religionController.text.trim(),
      height: _heightController.text.trim(),
      weight: _weightController.text.trim(),
      elementarySchool: _elementarySchoolController.text.trim(),
      elementaryYear: _elementaryYearController.text.trim(),
      secondarySchool: _secondarySchoolController.text.trim(),
      secondaryYear: _secondaryYearController.text.trim(),
      collegeSchool: _collegeSchoolController.text.trim(),
      collegeYear: _collegeYearController.text.trim(),
      collegeCourse: _collegeCourseController.text.trim(),
      yearGraduated: _yearGraduatedController.text.trim(),
      fatherName: _fatherNameController.text.trim(),
      fatherOccupation: _fatherOccupationController.text.trim(),
      motherMaidenName: _motherMaidenNameController.text.trim(),
      motherOccupation: _motherOccupationController.text.trim(),
      numberOfSiblings: _numberOfSiblingsController.text.trim(),
      birthOrder: _birthOrderController.text.trim(),
      spouseName: _spouseNameController.text.trim(),
      spouseOccupation: _spouseOccupationController.text.trim(),
      spouseContact: _spouseContactController.text.trim(),
      childrenNames: _childrenNamesController.text.trim(),
      childrenCount: _childrenCountController.text.trim(),
    );
  }

  String? _selectedValue(String value) {
    return value == 'Select' ? null : value;
  }

  String? _parseDate(String value, {bool required = true}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required ? null : null;
    }

    final directDate = DateTime.tryParse(trimmed);
    if (directDate != null) {
      return _dateOnly(directDate);
    }

    final slashParts = trimmed.split('/');
    if (slashParts.length == 3) {
      final month = int.tryParse(slashParts[0]);
      final day = int.tryParse(slashParts[1]);
      final year = int.tryParse(slashParts[2]);
      if (month != null && day != null && year != null) {
        final parsed = DateTime.tryParse(
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        );
        if (parsed != null &&
            parsed.month == month &&
            parsed.day == day &&
            parsed.year == year) {
          return _dateOnly(parsed);
        }
      }
    }

    return null;
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  (String, String) _parseScheduleRange(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return (_scheduleStart, _scheduleEnd);
    }

    final parts = normalized.split('-');
    if (parts.length < 2) {
      return (_scheduleStart, _scheduleEnd);
    }

    final start = parts.first.trim().toUpperCase();
    final end = parts.sublist(1).join('-').trim().toUpperCase();
    final startOption = _timeOptions.firstWhere(
      (option) => option.toUpperCase() == start,
      orElse: () => _scheduleStart,
    );
    final endOption = _timeOptions.firstWhere(
      (option) => option.toUpperCase() == end,
      orElse: () => _scheduleEnd,
    );
    return (startOption, endOption);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HygColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: HygColors.ink),
        ),
        title: Text(
          widget.employee == null ? 'Add Employee' : 'Edit Employee',
          style: HygTypography.pageTitle,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isSaving ? null : _saveEmployee,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(
              _isSaving
                  ? 'Saving...'
                  : widget.employee == null
                  ? 'Save Employee'
                  : 'Update Employee',
            ),
          ),
          const SizedBox(width: 18),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: HygColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(
              children: [
                if (_formError != null) ...[
                  FormErrorBanner(message: _formError!),
                  const FormSectionGap(),
                ],
                ProfileFormSection(
                  title: 'Personal Information',
                  icon: Icons.person_outline,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 900;
                      final fields = ModalFieldGrid(
                        children: [
                          ModalTextField(
                            label: 'First Name',
                            required: true,
                            controller: _firstNameController,
                          ),
                          ModalTextField(
                            label: 'Middle Name',
                            controller: _middleNameController,
                          ),
                          ModalTextField(
                            label: 'Last Name',
                            required: true,
                            controller: _lastNameController,
                          ),
                          ModalTextField(
                            label: 'Suffix',
                            hint: 'E.G. JR, SR',
                            controller: _suffixController,
                          ),
                          ModalTextField(
                            label: 'Birth Date',
                            required: true,
                            hint: 'mm/dd/yyyy',
                            trailingIcon: Icons.calendar_today,
                            controller: _birthDateController,
                          ),
                          ModalTextField(
                            label: 'Age',
                            hint: 'Auto',
                            controller: _ageController,
                          ),
                          ModalSelectField(
                            label: 'Gender',
                            required: true,
                            value: _gender,
                            options: const [
                              'Select',
                              'Male',
                              'Female',
                              'Other',
                            ],
                            onChanged: (value) =>
                                setState(() => _gender = value),
                          ),
                          ModalSelectField(
                            label: 'Civil Status',
                            required: true,
                            value: _civilStatus,
                            options: const [
                              'Select',
                              'Single',
                              'Married',
                              'Separated',
                              'Widowed',
                            ],
                            onChanged: (value) =>
                                setState(() => _civilStatus = value),
                          ),
                          ModalTextField(
                            label: 'Religion',
                            required: true,
                            hint: 'e.g. Catholic',
                            controller: _religionController,
                          ),
                          ModalTextField(
                            label: 'Height CM',
                            controller: _heightCmController,
                          ),
                          ModalTextField(
                            label: 'Weight KG',
                            controller: _weightKgController,
                          ),
                          ModalTextField(
                            label: 'BMI',
                            hint: 'Auto',
                            controller: _bmiController,
                            readOnly: true,
                          ),
                          ModalTextField(
                            label: 'BMI Classification',
                            hint: 'Auto',
                            controller: _bmiClassificationController,
                            readOnly: true,
                          ),
                          ModalTextField(
                            label: 'ID Number',
                            controller: _idNumberController,
                            readOnly: true,
                          ),
                        ],
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PhotoUploadBox(
                              photoBytes: _photoBytes,
                              existingPhotoUrl: _existingPhotoUrl,
                              selectedFileName: _photoFileName,
                              onPickPhoto: _pickEmployeePhoto,
                            ),
                            const SizedBox(height: 18),
                            fields,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PhotoUploadBox(
                            photoBytes: _photoBytes,
                            existingPhotoUrl: _existingPhotoUrl,
                            selectedFileName: _photoFileName,
                            onPickPhoto: _pickEmployeePhoto,
                          ),
                          const SizedBox(width: 22),
                          Expanded(child: fields),
                        ],
                      );
                    },
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Contact & Address',
                  icon: Icons.contact_mail_outlined,
                  child: Column(
                    children: [
                      ModalFieldGrid(
                        columns: 3,
                        children: [
                          ModalTextField(
                            label: 'Email Address',
                            required: true,
                            hint: 'employee@company.com',
                            controller: _emailController,
                          ),
                          ModalTextField(
                            label: 'Phone Number',
                            required: true,
                            hint: '+63 900 000 0000',
                            controller: _phoneController,
                          ),
                          ModalTextField(
                            label: 'Other Phone No.',
                            hint: '+63 900 000 0000',
                            controller: _otherPhoneController,
                          ),
                          ModalTextField(
                            label: 'Zip Code',
                            controller: _zipCodeController,
                          ),
                          ModalTextField(
                            label: 'Social Media Type',
                            hint: 'Facebook, Instagram, LinkedIn',
                            controller: _socialMediaTypeController,
                          ),
                          ModalTextField(
                            label: 'Social Media Detail',
                            hint: 'Profile link or username',
                            controller: _socialMediaDetailController,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ModalFieldGrid(
                        columns: 2,
                        children: [
                          ModalTextField(
                            label: 'Present Address',
                            required: true,
                            maxLines: 3,
                            controller: _presentAddressController,
                          ),
                          ModalTextField(
                            label: 'Permanent Address',
                            maxLines: 3,
                            controller: _permanentAddressController,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Employment Details',
                  icon: Icons.badge_outlined,
                  highlight:
                      widget.employee != null &&
                      _employmentStatus.toLowerCase() == 'pending',
                  highlightColor: const Color(0xFFDC2626),
                  highlightBackground: const Color(0xFFFEF2F2),
                  child: Column(
                    children: [
                      if (widget.employee != null &&
                          _employmentStatus.toLowerCase() == 'pending') ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            border: Border.all(color: const Color(0xFFEF4444)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'HR review section: verify and update employment status before finalizing profile details.',
                            style: HygTypography.tableBody.copyWith(
                              color: const Color(0xFF991B1B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      ModalFieldGrid(
                        columns: 4,
                        children: [
                          ModalSelectField(
                            label: 'Company',
                            required: true,
                            value: _company,
                            options: ['Select', ..._companyOptions],
                            supportingText: _isLoadingCompanyOptions
                                ? 'Loading companies from database...'
                                : _companyLoadError,
                            supportingColor: _companyLoadError == null
                                ? HygColors.muted
                                : const Color(0xFFDC2626),
                            onChanged: _selectCompany,
                          ),
                          ModalSelectField(
                            label: 'Department',
                            required: true,
                            value: _department,
                            options: ['Select', ..._departmentOptions],
                            supportingText: _isLoadingDepartmentOptions
                                ? 'Loading departments from database...'
                                : _departmentLoadError,
                            supportingColor: _departmentLoadError == null
                                ? HygColors.muted
                                : const Color(0xFFDC2626),
                            onChanged: (value) =>
                                setState(() => _department = value),
                          ),
                          ModalSelectField(
                            label: 'Store',
                            value: _store,
                            options: _storeOptions,
                            supportingText: _isLoadingStoreOptions
                                ? 'Loading stores from database...'
                                : _storeLoadError,
                            supportingColor: _storeLoadError == null
                                ? HygColors.muted
                                : const Color(0xFFDC2626),
                            onChanged: (value) =>
                                setState(() => _store = value),
                          ),
                          ModalSelectField(
                            label: 'Position',
                            required: true,
                            value: _position,
                            options: ['Select', ..._positionOptions],
                            supportingText: _isLoadingPositionOptions
                                ? 'Loading positions from database...'
                                : _positionLoadError,
                            supportingColor: _positionLoadError == null
                                ? HygColors.muted
                                : const Color(0xFFDC2626),
                            onChanged: (value) =>
                                setState(() => _position = value),
                          ),
                          ModalTextField(
                            label: 'Date Hired',
                            required: true,
                            hint: 'mm/dd/yyyy',
                            trailingIcon: Icons.calendar_today,
                            controller: _dateHiredController,
                          ),
                          ModalSelectField(
                            label: 'Employee Type',
                            value: _employeeType,
                            options: const [
                              'Regular',
                              'Part-Time',
                              'Probationary',
                              'Trainee',
                            ],
                            onChanged: (value) =>
                                setState(() => _employeeType = value),
                          ),
                          ModalSelectField(
                            label: 'Status',
                            value: _employmentStatus,
                            options: const ['pending', 'active', 'inactive'],
                            onChanged: (value) =>
                                setState(() => _employmentStatus = value),
                          ),
                          ModalSelectField(
                            label: 'Payroll Class',
                            value: _payrollClass,
                            options: const [
                              'Rank and File',
                              'Admin',
                              'Managerial',
                            ],
                            onChanged: (value) =>
                                setState(() => _payrollClass = value),
                          ),
                          ScheduleRangeField(
                            label: 'Schedule',
                            startTime: _scheduleStart,
                            endTime: _scheduleEnd,
                            options: _timeOptions,
                            onStartChanged: (value) =>
                                setState(() => _scheduleStart = value),
                            onEndChanged: (value) =>
                                setState(() => _scheduleEnd = value),
                          ),
                          ModalSelectField(
                            label: 'Day Off Day',
                            value: _dayOffDay,
                            options: const [
                              'Monday',
                              'Tuesday',
                              'Wednesday',
                              'Thursday',
                              'Friday',
                              'Saturday',
                              'Sunday',
                            ],
                            onChanged: (value) =>
                                setState(() => _dayOffDay = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Government & Bank Information',
                  icon: Icons.account_balance_outlined,
                  child: Column(
                    children: [
                      ModalFieldGrid(
                        columns: 4,
                        children: [
                          ModalTextField(
                            label: 'TIN No.',
                            controller: _tinController,
                          ),
                          ModalTextField(
                            label: 'SSS No.',
                            controller: _sssController,
                          ),
                          ModalTextField(
                            label: 'Pag-IBIG No.',
                            controller: _pagibigController,
                          ),
                          ModalTextField(
                            label: 'PhilHealth No.',
                            controller: _philhealthController,
                          ),
                          ModalSelectField(
                            label: 'Bank Type',
                            value: _bankType,
                            options: const [
                              'BDO',
                              'BPI',
                              'Metrobank',
                              'LandBank',
                              'Security Bank',
                              'UnionBank',
                              'Other',
                            ],
                            onChanged: (value) =>
                                setState(() => _bankType = value),
                          ),
                          ModalTextField(
                            label: 'Account No.',
                            controller: _accountNoController,
                          ),
                          ModalTextField(
                            label: 'Emergency Contact',
                            controller: _emergencyContactController,
                          ),
                          ModalTextField(
                            label: 'Emergency Contact No.',
                            controller: _emergencyContactNoController,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Education History',
                  icon: Icons.school_outlined,
                  child: Column(
                    children: [
                      ModalFieldGrid(
                        columns: 4,
                        children: [
                          ModalTextField(
                            label: 'Elementary School',
                            controller: _elementarySchoolController,
                          ),
                          ModalTextField(
                            label: 'Elementary Year',
                            controller: _elementaryYearController,
                          ),
                          ModalTextField(
                            label: 'Secondary School',
                            controller: _secondarySchoolController,
                          ),
                          ModalTextField(
                            label: 'Secondary Year',
                            controller: _secondaryYearController,
                          ),
                          ModalTextField(
                            label: 'College School',
                            controller: _collegeSchoolController,
                          ),
                          ModalTextField(
                            label: 'College Year',
                            controller: _collegeYearController,
                          ),
                          ModalTextField(
                            label: 'College Course',
                            controller: _collegeCourseController,
                          ),
                          ModalTextField(
                            label: 'Year Graduated',
                            controller: _yearGraduatedController,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Family Background',
                  icon: Icons.family_restroom_outlined,
                  child: Column(
                    children: [
                      ModalFieldGrid(
                        columns: 4,
                        children: [
                          ModalTextField(
                            label: 'Father Name',
                            controller: _fatherNameController,
                          ),
                          ModalTextField(
                            label: 'Father Occupation',
                            controller: _fatherOccupationController,
                          ),
                          ModalTextField(
                            label: 'Mother Maiden Name',
                            controller: _motherMaidenNameController,
                          ),
                          ModalTextField(
                            label: 'Mother Occupation',
                            controller: _motherOccupationController,
                          ),
                          ModalTextField(
                            label: 'Number of Siblings',
                            controller: _numberOfSiblingsController,
                          ),
                          ModalTextField(
                            label: 'Birth Order',
                            controller: _birthOrderController,
                          ),
                          ModalTextField(
                            label: 'Spouse Name',
                            controller: _spouseNameController,
                          ),
                          ModalTextField(
                            label: 'Spouse Occupation',
                            controller: _spouseOccupationController,
                          ),
                          ModalTextField(
                            label: 'Spouse Contact',
                            controller: _spouseContactController,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const FormSectionGap(),
                ProfileFormSection(
                  title: 'Children',
                  icon: Icons.child_care_outlined,
                  child: ChildrenProfileRows(
                    nameControllers: _childNameControllers,
                    birthdayControllers: _childBirthdayControllers,
                    ageControllers: _childAgeControllers,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FormSectionGap extends StatelessWidget {
  const FormSectionGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 14);
}

class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        border: Border.all(color: const Color(0xFFFCA5A5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: HygTypography.tableBody.copyWith(
                color: const Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileFormSection extends StatelessWidget {
  const ProfileFormSection({
    required this.title,
    required this.child,
    required this.icon,
    this.highlight = false,
    this.highlightColor = const Color(0xFFDC2626),
    this.highlightBackground = Colors.white,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData icon;
  final bool highlight;
  final Color highlightColor;
  final Color highlightBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlight ? highlightBackground : Colors.white,
        border: Border.all(
          color: highlight ? highlightColor : HygColors.border,
          width: highlight ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
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
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: HygColors.goldStrong, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: HygTypography.pageTitle.copyWith(fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: HygColors.border),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class PhotoUploadBox extends StatelessWidget {
  const PhotoUploadBox({
    required this.onPickPhoto,
    this.photoBytes,
    this.existingPhotoUrl,
    this.selectedFileName,
    super.key,
  });

  final VoidCallback onPickPhoto;
  final Uint8List? photoBytes;
  final String? existingPhotoUrl;
  final String? selectedFileName;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = existingPhotoUrl?.trim();
    return SizedBox(
      width: 138,
      child: Column(
        children: [
          Container(
            height: 138,
            decoration: BoxDecoration(
              color: HygColors.background,
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoBytes != null
                ? Image.memory(photoBytes!, fit: BoxFit.cover)
                : (normalizedUrl != null && normalizedUrl.isNotEmpty
                      ? Image.network(
                          normalizedUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: Color(0xFF94A3B8),
                                size: 36,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: Color(0xFF94A3B8),
                            size: 36,
                          ),
                        )),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(38),
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: onPickPhoto,
            child: const Text('Choose Photo'),
          ),
          const SizedBox(height: 5),
          Text(
            selectedFileName ?? 'JPG, PNG. Max 10MB.',
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

class ModalFieldGrid extends StatelessWidget {
  const ModalFieldGrid({required this.children, this.columns = 4, super.key});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveColumns = constraints.maxWidth < 720 ? 2 : columns;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (effectiveColumns - 1))) /
            effectiveColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class ChildrenProfileRows extends StatelessWidget {
  const ChildrenProfileRows({
    required this.nameControllers,
    required this.birthdayControllers,
    required this.ageControllers,
    super.key,
  });

  final List<TextEditingController> nameControllers;
  final List<TextEditingController> birthdayControllers;
  final List<TextEditingController> ageControllers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        return Column(
          children: List.generate(nameControllers.length, (index) {
            final nameField = ModalTextField(
              label: 'Child ${index + 1} Name',
              controller: nameControllers[index],
            );
            final birthdayField = ModalTextField(
              label: 'Birthday',
              hint: 'mm/dd/yyyy',
              trailingIcon: Icons.calendar_today,
              controller: birthdayControllers[index],
            );
            final ageField = ModalTextField(
              label: 'Age',
              hint: 'Auto',
              controller: ageControllers[index],
              readOnly: true,
            );
            final row = [
              Expanded(flex: 3, child: nameField),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: birthdayField),
              const SizedBox(width: 12),
              Expanded(child: ageField),
            ];
            final compactRow = [
              nameField,
              const SizedBox(height: 10),
              birthdayField,
              const SizedBox(height: 10),
              ageField,
            ];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == nameControllers.length - 1 ? 0 : 14,
              ),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: compactRow,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: row,
                    ),
            );
          }),
        );
      },
    );
  }
}

class ModalTextField extends StatelessWidget {
  const ModalTextField({
    required this.label,
    this.controller,
    this.hint = '',
    this.required = false,
    this.maxLines = 1,
    this.trailingIcon,
    this.readOnly = false,
    this.obscureText = false,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String hint;
  final bool required;
  final int maxLines;
  final IconData? trailingIcon;
  final bool readOnly;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, required: required),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          obscureText: obscureText,
          maxLines: maxLines,
          minLines: maxLines > 1 ? maxLines : null,
          style: HygTypography.input,
          decoration: modalInputDecoration(
            hint: hint,
            trailingIcon: trailingIcon,
          ),
        ),
      ],
    );
  }
}

class ModalSelectField extends StatelessWidget {
  const ModalSelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.required = false,
    this.supportingText,
    this.supportingColor,
    super.key,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool required;
  final String? supportingText;
  final Color? supportingColor;

  @override
  Widget build(BuildContext context) {
    final effectiveOptions = <String>[];
    for (final option in options) {
      final alreadyAdded = effectiveOptions.any(
        (existingOption) =>
            _normalizeSelectOption(existingOption) ==
            _normalizeSelectOption(option),
      );
      if (!alreadyAdded) {
        effectiveOptions.add(option);
      }
    }
    final matchingValue = effectiveOptions.where(
      (option) =>
          _normalizeSelectOption(option) == _normalizeSelectOption(value),
    );
    final selectedValue = matchingValue.isEmpty ? value : matchingValue.first;

    if (value.trim().isNotEmpty && matchingValue.isEmpty) {
      final selectIndex = effectiveOptions.indexOf('Select');
      effectiveOptions.insert(selectIndex == -1 ? 0 : selectIndex + 1, value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, required: required),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: selectedValue,
          isExpanded: true,
          decoration: modalInputDecoration(),
          style: HygTypography.input,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF334155)),
          items: effectiveOptions
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
        if (supportingText != null && supportingText!.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            supportingText!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HygTypography.tableMuted.copyWith(
              color: supportingColor ?? HygColors.muted,
            ),
          ),
        ],
      ],
    );
  }

  String _normalizeSelectOption(String option) {
    return option.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class ScheduleRangeField extends StatelessWidget {
  const ScheduleRangeField({
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.options,
    required this.onStartChanged,
    required this.onEndChanged,
    super.key,
  });

  final String label;
  final String startTime;
  final String endTime;
  final List<String> options;
  final ValueChanged<String> onStartChanged;
  final ValueChanged<String> onEndChanged;

  @override
  Widget build(BuildContext context) {
    final schedulePreview = '$startTime - $endTime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: startTime,
                isExpanded: true,
                decoration: modalInputDecoration(hint: 'Start time'),
                style: HygTypography.input,
                dropdownColor: Colors.white,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF334155),
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option,
                        child: Text(option, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onStartChanged(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            const Text('to', style: HygTypography.tableMuted),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: endTime,
                isExpanded: true,
                decoration: modalInputDecoration(hint: 'End time'),
                style: HygTypography.input,
                dropdownColor: Colors.white,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF334155),
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option,
                        child: Text(option, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onEndChanged(value);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Saved format: $schedulePreview',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HygTypography.tableMuted.copyWith(color: HygColors.muted),
        ),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel({required this.label, this.required = false, super.key});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: HygTypography.fieldLabel,
        children: [
          TextSpan(text: label),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
        ],
      ),
    );
  }
}

InputDecoration modalInputDecoration({
  String hint = '',
  IconData? trailingIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: HygTypography.input.copyWith(color: const Color(0xFF6B7280)),
    suffixIcon: trailingIcon == null
        ? null
        : Icon(trailingIcon, size: 18, color: HygColors.ink),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: HygColors.goldStrong, width: 1.5),
    ),
  );
}

class EmployeesPanel extends StatefulWidget {
  const EmployeesPanel({
    required this.employees,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEditEmployee,
    required this.onDeleteEmployee,
    super.key,
  });

  final List<EmployeePreview> employees;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<EmployeePreview> onEditEmployee;
  final ValueChanged<EmployeePreview> onDeleteEmployee;

  @override
  State<EmployeesPanel> createState() => _EmployeesPanelState();
}

class _EmployeesPanelState extends State<EmployeesPanel> {
  static const _employeesPerPage = 15;
  static const _allStatuses = 'All Statuses';
  static const _allCompanies = 'All Companies';

  var _currentPage = 0;
  var _statusFilter = _allStatuses;
  var _companyFilter = _allCompanies;
  late final TextEditingController _searchController;

  int get _pageCount =>
      (_filteredEmployees.length / _employeesPerPage).ceil().clamp(1, 999999);

  List<EmployeePreview> get _visibleEmployees {
    final start = _currentPage * _employeesPerPage;
    final end = math.min(start + _employeesPerPage, _filteredEmployees.length);
    return _filteredEmployees.sublist(start, end);
  }

  List<EmployeePreview> get _filteredEmployees {
    final query = _normalize(_searchController.text);
    final status = _normalize(_statusFilter);
    final company = _normalize(_companyFilter);

    return widget.employees
        .where((employee) {
          final matchesSearch =
              query.isEmpty ||
              [
                employee.name,
                employee.email ?? '',
                employee.phone ?? '',
                employee.idNumber,
                employee.companyName,
                employee.departmentName,
                employee.positionName,
                employee.roleDepartment,
                employee.status,
              ].any((value) => _normalize(value).contains(query));

          final matchesStatus =
              _statusFilter == _allStatuses ||
              _normalize(employee.status) == status;

          final matchesCompany =
              _companyFilter == _allCompanies ||
              _normalize(employee.companyName) == company;

          return matchesSearch && matchesStatus && matchesCompany;
        })
        .toList(growable: false);
  }

  List<String> get _statusOptions {
    final statuses =
        widget.employees
            .map((employee) => employee.status.trim())
            .where((status) => status.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allStatuses, ...statuses];
  }

  List<String> get _companyOptions {
    final companies =
        widget.employees
            .map((employee) => employee.companyName.trim())
            .where((company) => company.isNotEmpty && company != '-')
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...companies];
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_handleFilterChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleFilterChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFilterChanged() {
    setState(() => _currentPage = 0);
  }

  @override
  void didUpdateWidget(covariant EmployeesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_statusOptions.contains(_statusFilter)) {
      _statusFilter = _allStatuses;
    }
    if (!_companyOptions.contains(_companyFilter)) {
      _companyFilter = _allCompanies;
    }
    if (_currentPage >= _pageCount) {
      _currentPage = _pageCount - 1;
    }
  }

  void _goToPage(int page) {
    final nextPage = page.clamp(0, _pageCount - 1);
    if (nextPage == _currentPage) {
      return;
    }
    setState(() => _currentPage = nextPage);
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = _allStatuses;
      _companyFilter = _allCompanies;
      _currentPage = 0;
    });
    _searchController.clear();
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final filteredEmployees = _filteredEmployees;

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
                flex: 3,
                child: _EmployeeSearchField(
                  controller: _searchController,
                  icon: Icons.search_rounded,
                  hint: 'Search name, email, department, or position',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _EmployeeFilterDropdown(
                  value: _statusFilter,
                  options: _statusOptions,
                  onChanged: (value) => setState(() {
                    _statusFilter = value ?? _allStatuses;
                    _currentPage = 0;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _EmployeeFilterDropdown(
                  value: _companyFilter,
                  options: _companyOptions,
                  onChanged: (value) => setState(() {
                    _companyFilter = value ?? _allCompanies;
                    _currentPage = 0;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: _EmployeeFilterIconButton(
                  icon: Icons.filter_alt_outlined,
                  tooltip: 'Apply filter',
                  filled: true,
                  onPressed: () => FocusScope.of(context).unfocus(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: _EmployeeFilterIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Reset filters',
                  onPressed: _resetFilters,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const EmployeeTableHeader(),
          const SizedBox(height: 8),
          if (widget.isLoading)
            const EmployeesStateMessage(
              icon: Icons.sync,
              title: 'Loading employees',
              message: 'Getting employee records from Supabase.',
            )
          else if (widget.error != null)
            EmployeesStateMessage(
              icon: Icons.warning_amber_rounded,
              title: 'Could not load employees',
              message: widget.error!,
              actionLabel: 'Retry',
              onAction: widget.onRefresh,
            )
          else if (filteredEmployees.isEmpty)
            EmployeesStateMessage(
              icon: Icons.group_off_outlined,
              title: 'No employees found',
              message: widget.employees.isEmpty
                  ? 'No employee records are available for this HR view yet.'
                  : 'No employees match the selected filters.',
              actionLabel: widget.employees.isEmpty ? 'Refresh' : 'Reset',
              onAction: widget.employees.isEmpty
                  ? widget.onRefresh
                  : _resetFilters,
            )
          else ...[
            ..._visibleEmployees.map(
              (employee) => EmployeeRow(
                employee: employee,
                onEdit: () => widget.onEditEmployee(employee),
                onDelete: () => widget.onDeleteEmployee(employee),
              ),
            ),
            const SizedBox(height: 14),
            EmployeePagination(
              currentPage: _currentPage,
              pageCount: _pageCount,
              totalEmployees: filteredEmployees.length,
              employeesPerPage: _employeesPerPage,
              onPageSelected: _goToPage,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeeSearchField extends StatelessWidget {
  const _EmployeeSearchField({
    required this.controller,
    required this.hint,
    this.icon,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        style: HygTypography.body.copyWith(color: HygColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: HygTypography.body.copyWith(
            color: const Color(0xFF475569),
          ),
          prefixIcon: icon == null
              ? null
              : Icon(icon, color: const Color(0xFF64748B), size: 18),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
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

class _EmployeeFilterDropdown extends StatelessWidget {
  const _EmployeeFilterDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        isExpanded: true,
        dropdownColor: Colors.white,
        icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF334155)),
        style: HygTypography.body.copyWith(color: Colors.black),
        decoration: InputDecoration(
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
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }
}

class _EmployeeFilterIconButton extends StatelessWidget {
  const _EmployeeFilterIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: filled ? HygColors.gold : Colors.white,
          foregroundColor: HygColors.ink,
          side: BorderSide(color: filled ? HygColors.gold : Colors.black),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class EmployeePagination extends StatelessWidget {
  const EmployeePagination({
    required this.currentPage,
    required this.pageCount,
    required this.totalEmployees,
    required this.employeesPerPage,
    required this.onPageSelected,
    this.itemLabel = 'employees',
    super.key,
  });

  final int currentPage;
  final int pageCount;
  final int totalEmployees;
  final int employeesPerPage;
  final ValueChanged<int> onPageSelected;
  final String itemLabel;

  List<int> get _visiblePages {
    final firstPage = math.max(
      0,
      math.min(currentPage - 2, math.max(0, pageCount - 5)),
    );
    return List.generate(math.min(5, pageCount), (index) => firstPage + index);
  }

  @override
  Widget build(BuildContext context) {
    final firstEmployee = currentPage * employeesPerPage + 1;
    final lastEmployee = math.min(
      firstEmployee + employeesPerPage - 1,
      totalEmployees,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DB),
        border: Border.all(color: HygColors.gold),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $firstEmployee-$lastEmployee of $totalEmployees $itemLabel',
              style: HygTypography.body.copyWith(
                color: HygColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _YellowPageButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed: currentPage == 0
                ? null
                : () => onPageSelected(currentPage - 1),
          ),
          const SizedBox(width: 6),
          ..._visiblePages.expand(
            (page) => [
              _YellowPageButton(
                label: '${page + 1}',
                isSelected: page == currentPage,
                onPressed: () => onPageSelected(page),
              ),
              const SizedBox(width: 6),
            ],
          ),
          _YellowPageButton(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed: currentPage == pageCount - 1
                ? null
                : () => onPageSelected(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _YellowPageButton extends StatelessWidget {
  const _YellowPageButton({
    this.label,
    this.icon,
    this.tooltip,
    this.isSelected = false,
    this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool isSelected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: isSelected ? HygColors.goldStrong : Colors.white,
          disabledBackgroundColor: const Color(0xFFF8FAFC),
          foregroundColor: HygColors.ink,
          disabledForegroundColor: const Color(0xFF94A3B8),
          side: BorderSide(
            color: isSelected ? HygColors.goldStrong : HygColors.border,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: icon == null
            ? Text(label!, style: const TextStyle(fontWeight: FontWeight.w800))
            : Tooltip(message: tooltip!, child: Icon(icon, size: 19)),
      ),
    );
  }
}

class EmployeeDeleteDialog extends StatefulWidget {
  const EmployeeDeleteDialog({required this.employee, super.key});

  final EmployeePreview employee;

  @override
  State<EmployeeDeleteDialog> createState() => _EmployeeDeleteDialogState();
}

class _EmployeeDeleteDialogState extends State<EmployeeDeleteDialog> {
  var _mode = EmployeeDeleteMode.soft;

  @override
  Widget build(BuildContext context) {
    final isHardDelete = _mode == EmployeeDeleteMode.hard;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Delete employee?'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to remove "${widget.employee.name}".',
              style: HygTypography.tableBody,
            ),
            const SizedBox(height: 14),
            RadioGroup<EmployeeDeleteMode>(
              groupValue: _mode,
              onChanged: (value) => setState(() => _mode = value!),
              child: const Column(
                children: [
                  RadioListTile<EmployeeDeleteMode>(
                    value: EmployeeDeleteMode.soft,
                    title: Text('Soft delete'),
                    subtitle: Text(
                      'Set the employee to inactive and disable portal access. Records remain available for HR history.',
                    ),
                  ),
                  RadioListTile<EmployeeDeleteMode>(
                    value: EmployeeDeleteMode.hard,
                    title: Text('Hard delete'),
                    subtitle: Text(
                      'Permanently delete the login, profile, ESARF, leave, discount, and related employee data.',
                    ),
                  ),
                ],
              ),
            ),
            if (isHardDelete) ...[
              const SizedBox(height: 8),
              Text(
                'Hard delete cannot be undone.',
                style: HygTypography.tableBody.copyWith(
                  color: const Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: isHardDelete
                ? const Color(0xFFDC2626)
                : const Color(0xFFF59E0B),
            foregroundColor: isHardDelete ? Colors.white : HygColors.ink,
          ),
          onPressed: () => Navigator.of(context).pop(_mode),
          icon: const Icon(Icons.delete_outline, size: 17),
          label: Text(isHardDelete ? 'Permanently Delete' : 'Set Inactive'),
        ),
      ],
    );
  }
}
