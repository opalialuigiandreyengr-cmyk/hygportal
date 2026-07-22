part of '../main.dart';

class AdminAuthService {
  static final _client = Supabase.instance.client;

  static Future<AdminLoginSession> signInAdmin({
    required String username,
    required String password,
  }) async {
    final loginName = username.trim();
    if (loginName.isEmpty || password.isEmpty) {
      throw Exception('Enter username and password.');
    }

    final resolvedEmail = await _client.rpc(
      'resolve_login_email',
      params: {'p_username': loginName},
    );
    final email = resolvedEmail?.toString().trim() ?? '';
    if (email.isEmpty) {
      throw Exception('No login account found for this username.');
    }

    final authResponse = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final userId = authResponse.user?.id;
    if (userId == null) {
      throw Exception('Invalid admin credential.');
    }

    final checkResponse = await _client.rpc('admin_desktop_login_check');
    if (checkResponse is! List || checkResponse.isEmpty) {
      await _client.auth.signOut();
      throw Exception('Admin access is required.');
    }

    final row = checkResponse.first;
    if (row is! Map<String, dynamic>) {
      await _client.auth.signOut();
      throw Exception('Admin access is required.');
    }

    return AdminLoginSession(
      username: row['username']?.toString() ?? loginName,
      appRole: row['app_role']?.toString() ?? 'hr',
    );
  }

  static Future<void> signOut() => _client.auth.signOut();
}

class AdminLoginSession {
  const AdminLoginSession({required this.username, required this.appRole});

  final String username;
  final String appRole;

  bool get canManageAdminSettings {
    final role = appRole.toLowerCase();
    return role == 'admin' || role == 'super_admin';
  }
}

class EmployeeDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<EmployeePreview>> loadEmployees() async {
    try {
      final response = await _client.rpc(
        'hr_employee_directory',
        params: {
          'p_username': AppConfig.hrUsername,
          'p_password': AppConfig.hrPassword,
        },
      );
      if (response is List) {
        final rows = response.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
        await LocalSyncService.cacheRows('employee_cache', rows);
        unawaited(LocalSyncService.syncNow());
        return _sortNewestFirst(
          rows.map(EmployeeDirectoryService._fromRow).toList(growable: false),
        );
      }
    } catch (_) {}
    final cached = await LocalSyncService.loadCachedRows('employee_cache');
    return _sortNewestFirst(
      cached.map(EmployeeDirectoryService._fromRow).toList(growable: false),
    );
  }

  static Future<EmployeeProfileDetails?> loadEmployeeProfile(
    String employeeId,
  ) async {
    if (employeeId.trim().isEmpty) {
      return null;
    }

    try {
      final response = await _client.rpc(
        'hr_employee_profile_detail',
        params: {
          'p_username': AppConfig.hrUsername,
          'p_password': AppConfig.hrPassword,
          'p_employee_id': employeeId,
        },
      );
      if (response is List &&
          response.isNotEmpty &&
          response.first is Map<String, dynamic>) {
        final row = response.first as Map<String, dynamic>;
        final mergedRow = await _mergeSupplementalProfileDetails(
          employeeId,
          row,
        );
        await LocalSyncService.cacheProfile(employeeId, mergedRow);
        return _profileFromRow(
          mergedRow,
          storeName: await _loadEmployeeStoreName(employeeId),
        );
      }
    } catch (_) {}
    final cached = await LocalSyncService.loadCachedProfile(employeeId);
    if (cached == null) {
      return null;
    }
    final mergedCached = await _mergeSupplementalProfileDetails(
      employeeId,
      cached,
    );
    return _profileFromRow(
      mergedCached,
      storeName: await _loadEmployeeStoreName(employeeId),
    );
  }

  static Future<Map<String, dynamic>> _mergeSupplementalProfileDetails(
    String employeeId,
    Map<String, dynamic> baseRow,
  ) async {
    try {
      final row = await _client
          .from('employee_profile_details')
          .select('''
            zip_code,
            social_media_type,
            social_media_detail,
            other_phone,
            permanent_address,
            religion,
            height,
            weight,
            elementary_school,
            elementary_year,
            secondary_school,
            secondary_year,
            college_school,
            college_year,
            college_course,
            year_graduated,
            father_name,
            father_occupation,
            mother_maiden_name,
            mother_occupation,
            number_of_siblings,
            birth_order,
            spouse_name,
            spouse_occupation,
            spouse_contact,
            children_names,
            children_count,
            emergency_contact_no
            ''')
          .eq('employee_id', employeeId)
          .maybeSingle();
      if (row == null) {
        return baseRow;
      }

      final merged = Map<String, dynamic>.of(baseRow);
      for (final entry in row.entries) {
        final value = _nullableString(entry.value);
        if (value != null) {
          merged[entry.key] = value;
        }
      }
      return merged;
    } catch (_) {
      return baseRow;
    }
  }

  static Future<String> createEmployee(EmployeeProfilePayload payload) async {
    if (await LocalSyncService.isOnline()) {
      return _createEmployeeRemote(payload);
    }
    await LocalSyncService.enqueue(
      entity: 'employee',
      action: 'create',
      payload: _payloadToMap(payload),
    );
    return 'Saved locally (offline). Will sync when internet is available.';
  }

  static Future<String> _createEmployeeRemote(
    EmployeeProfilePayload payload,
  ) async {
    final response = await _client.rpc(
      'create_employee_profile_with_store',
      params: {
        'p_last_name': payload.lastName,
        'p_first_name': payload.firstName,
        'p_middle_name': payload.middleName,
        'p_suffix': payload.suffix,
        'p_birth_date': payload.birthDate,
        'p_gender': payload.gender,
        'p_civil_status': payload.civilStatus,
        'p_cellphone': payload.phone ?? '',
        'p_email': payload.email,
        'p_company': payload.company ?? '',
        'p_work_unit': payload.department ?? '',
        'p_store': payload.store == null || payload.store!.trim().isEmpty
            ? 'N/A'
            : payload.store,
        'p_position': payload.position ?? '',
        'p_date_hired': payload.dateHired,
        'p_employee_type': payload.employeeType,
        'p_tin': payload.tin,
        'p_sss': payload.sss,
        'p_pagibig': payload.pagibig,
        'p_philhealth': payload.philhealth,
        'p_bank_type': payload.bankType,
        'p_account_no': payload.accountNo,
        'p_education': '',
        'p_present_address': payload.presentAddress,
        'p_emergency_contact': payload.emergencyContact,
        'p_document_refs': null,
        'p_emergency_contact_no': payload.emergencyContactNo,
      },
    );

    final employeeId = response.toString();
    await _updateEmployeeSupplementalDetails(
      employeeId: employeeId,
      payload: payload,
    );
    return employeeId;
  }

  static Future<String> updateEmployee({
    required String id,
    required EmployeeProfilePayload payload,
  }) async {
    await _updateEmployeeRemote(id: id, payload: payload);
    return 'Employee updated successfully.';
  }

  static Future<String> _updateEmployeeRemote({
    required String id,
    required EmployeeProfilePayload payload,
  }) async {
    final response = await _client.rpc(
      'hr_update_employee_profile',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_employee_id': id,
        'p_last_name': payload.lastName,
        'p_first_name': payload.firstName,
        'p_middle_name': payload.middleName,
        'p_suffix': payload.suffix,
        'p_birth_date': payload.birthDate,
        'p_gender': payload.gender,
        'p_civil_status': payload.civilStatus,
        'p_cellphone': payload.phone,
        'p_email': payload.email,
        'p_company': payload.company,
        'p_work_unit': payload.department,
        'p_position': payload.position,
        'p_date_hired': payload.dateHired,
        'p_employee_type': payload.employeeType,
        'p_time_schedule': payload.schedule,
        'p_day_off_day': payload.dayOffDay,
        'p_payroll_class': payload.payrollClass,
        'p_tin': payload.tin,
        'p_sss': payload.sss,
        'p_pagibig': payload.pagibig,
        'p_philhealth': payload.philhealth,
        'p_bank_type': payload.bankType,
        'p_account_no': payload.accountNo,
        'p_present_address': payload.presentAddress,
        'p_emergency_contact': payload.emergencyContact,
      },
    );

    try {
      await _client.rpc(
        'hr_set_employee_status',
        params: {
          'p_username': AppConfig.hrUsername,
          'p_password': AppConfig.hrPassword,
          'p_employee_id': id,
          'p_employment_status': payload.employmentStatus,
        },
      );
    } catch (error) {
      final message = error.toString();
      final missingStatusFunction =
          message.contains('hr_set_employee_status') ||
          message.contains('PGRST202');
      if (!missingStatusFunction) {
        rethrow;
      }
    }

    await _updateEmployeeSupplementalDetails(employeeId: id, payload: payload);
    await _setEmployeeStore(employeeId: id, payload: payload);
    return response.toString();
  }

  static Future<void> _updateEmployeeSupplementalDetails({
    required String employeeId,
    required EmployeeProfilePayload payload,
  }) async {
    await _client.rpc(
      'hr_update_employee_supplemental_details',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_employee_id': employeeId,
        'p_profile': _supplementalProfileToMap(payload),
      },
    );
  }

  static Future<void> _setEmployeeStore({
    required String employeeId,
    required EmployeeProfilePayload payload,
  }) async {
    await _client.rpc(
      'hr_set_employee_store',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_employee_id': employeeId,
        'p_company_name': payload.company,
        'p_store_name': payload.store,
      },
    );
  }

  static Future<String?> _loadEmployeeStoreName(String employeeId) async {
    try {
      final response = await _client.rpc(
        'hr_employee_store_detail',
        params: {
          'p_username': AppConfig.hrUsername,
          'p_password': AppConfig.hrPassword,
          'p_employee_id': employeeId,
        },
      );
      if (response is List &&
          response.isNotEmpty &&
          response.first is Map<String, dynamic>) {
        return _nullableString(
          (response.first as Map<String, dynamic>)['store_name'],
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteEmployee({
    required String id,
    required EmployeeDeleteMode mode,
  }) async {
    await _client.rpc(
      'hr_delete_employee',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_employee_id': id,
        'p_delete_mode': mode.name,
      },
    );
  }

  static Map<String, dynamic> _payloadToMap(EmployeeProfilePayload payload) {
    return <String, dynamic>{
      'firstName': payload.firstName,
      'middleName': payload.middleName,
      'lastName': payload.lastName,
      'suffix': payload.suffix,
      'birthDate': payload.birthDate,
      'gender': payload.gender,
      'civilStatus': payload.civilStatus,
      'phone': payload.phone,
      'email': payload.email,
      'company': payload.company,
      'department': payload.department,
      'store': payload.store,
      'position': payload.position,
      'dateHired': payload.dateHired,
      'employeeType': payload.employeeType,
      'employmentStatus': payload.employmentStatus,
      'schedule': payload.schedule,
      'dayOffDay': payload.dayOffDay,
      'payrollClass': payload.payrollClass,
      'tin': payload.tin,
      'sss': payload.sss,
      'pagibig': payload.pagibig,
      'philhealth': payload.philhealth,
      'bankType': payload.bankType,
      'accountNo': payload.accountNo,
      'presentAddress': payload.presentAddress,
      'emergencyContact': payload.emergencyContact,
      'emergencyContactNo': payload.emergencyContactNo,
      ..._supplementalProfileToMap(payload),
    };
  }

  static Map<String, dynamic> _supplementalProfileToMap(
    EmployeeProfilePayload payload,
  ) {
    return <String, dynamic>{
      'zipCode': payload.zipCode,
      'socialMediaType': payload.socialMediaType,
      'socialMediaDetail': payload.socialMediaDetail,
      'otherPhone': payload.otherPhone,
      'permanentAddress': payload.permanentAddress,
      'religion': payload.religion,
      'height': payload.height,
      'weight': payload.weight,
      'elementarySchool': payload.elementarySchool,
      'elementaryYear': payload.elementaryYear,
      'secondarySchool': payload.secondarySchool,
      'secondaryYear': payload.secondaryYear,
      'collegeSchool': payload.collegeSchool,
      'collegeYear': payload.collegeYear,
      'collegeCourse': payload.collegeCourse,
      'yearGraduated': payload.yearGraduated,
      'fatherName': payload.fatherName,
      'fatherOccupation': payload.fatherOccupation,
      'motherMaidenName': payload.motherMaidenName,
      'motherOccupation': payload.motherOccupation,
      'numberOfSiblings': payload.numberOfSiblings,
      'birthOrder': payload.birthOrder,
      'spouseName': payload.spouseName,
      'spouseOccupation': payload.spouseOccupation,
      'spouseContact': payload.spouseContact,
      'childrenNames': payload.childrenNames,
      'childrenCount': payload.childrenCount,
      'emergencyContactNo': payload.emergencyContactNo,
    };
  }

  static EmployeeProfileDetails _profileFromRow(
    Map<String, dynamic> row, {
    String? storeName,
  }) {
    return EmployeeProfileDetails(
      idNumber: _nullableString(row['employee_no']),
      firstName: _nullableString(row['first_name']),
      middleName: _nullableString(row['middle_name']),
      lastName: _nullableString(row['last_name']),
      suffix: _nullableString(row['suffix']),
      birthDate: _nullableString(row['birth_date']),
      gender: _nullableString(row['gender']),
      civilStatus: _nullableString(row['civil_status']),
      email: _nullableString(row['email']),
      phone: _nullableString(row['phone']),
      zipCode: _nullableString(row['zip_code']),
      socialMediaType: _nullableString(row['social_media_type']),
      socialMediaDetail: _nullableString(row['social_media_detail']),
      otherPhone: _nullableString(row['other_phone'] ?? row['otherPhone']),
      presentAddress: _nullableString(row['present_address']),
      permanentAddress: _nullableString(row['permanent_address']),
      dateHired: _nullableString(row['hired_date']),
      religion: _nullableString(row['religion']),
      height: _nullableString(row['height']),
      weight: _nullableString(row['weight']),
      employeeType: _nullableString(row['employee_type']),
      schedule: _nullableString(row['time_schedule']),
      dayOffDay: _nullableString(row['day_off_day']),
      payrollClass: _nullableString(row['payroll_class']),
      bankType: _nullableString(row['bank_type']),
      companyName: _nullableString(row['company_name']),
      departmentName: _nullableString(row['department_name']),
      storeName: storeName,
      positionName: _nullableString(row['position_name']),
      tin: _nullableString(row['tin']),
      sss: _nullableString(row['sss']),
      pagibig: _nullableString(row['pagibig']),
      philhealth: _nullableString(row['philhealth']),
      accountNo: _nullableString(row['account_no']),
      emergencyContact: _nullableString(row['emergency_contact']),
      emergencyContactNo: _nullableString(row['emergency_contact_no']),
      elementarySchool: _nullableString(row['elementary_school']),
      elementaryYear: _nullableString(row['elementary_year']),
      secondarySchool: _nullableString(row['secondary_school']),
      secondaryYear: _nullableString(row['secondary_year']),
      collegeSchool: _nullableString(row['college_school']),
      collegeYear: _nullableString(row['college_year']),
      collegeCourse: _nullableString(row['college_course']),
      yearGraduated: _nullableString(row['year_graduated']),
      fatherName: _nullableString(row['father_name']),
      fatherOccupation: _nullableString(row['father_occupation']),
      motherMaidenName: _nullableString(row['mother_maiden_name']),
      motherOccupation: _nullableString(row['mother_occupation']),
      numberOfSiblings: _nullableString(row['number_of_siblings']),
      birthOrder: _nullableString(row['birth_order']),
      spouseName: _nullableString(row['spouse_name']),
      spouseOccupation: _nullableString(row['spouse_occupation']),
      spouseContact: _nullableString(row['spouse_contact']),
      childrenNames: _nullableString(row['children_names']),
      childrenCount: _nullableString(row['children_count']),
    );
  }

  static Future<String> uploadEmployeePhoto({
    required String employeeId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final extension = _fileExtension(fileName);
    final path =
        'employees/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    final contentType = _contentTypeForExtension(extension);

    await _client.storage
        .from(AppConfig.employeePhotoBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
            cacheControl: '3600',
          ),
        );

    return _client.storage
        .from(AppConfig.employeePhotoBucket)
        .getPublicUrl(path);
  }

  static Future<void> setEmployeePhotoUrl({
    required String employeeId,
    required String photoUrl,
  }) async {
    await _client.rpc(
      'hr_set_employee_photo_url',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_employee_id': employeeId,
        'p_photo_url': photoUrl,
      },
    );
  }

  static EmployeePreview _fromRow(Map<String, dynamic> row) {
    final fullName = _employeeDisplayName(row);
    final position = _stringValue(row['position_name']);
    final department = _stringValue(row['department_name']);
    final company = _stringValue(row['company_name'], fallback: '-');
    final hiredDate = _nullableString(row['hired_date']);
    final createdAt = _dateTimeValue(row['created_at']);

    return EmployeePreview(
      id: _stringValue(row['employee_id'], fallback: ''),
      name: fullName,
      initial: _initial(fullName),
      email: _nullableString(row['email']),
      phone: _nullableString(row['phone']),
      photoUrl: _nullableString(row['photo_url']),
      idNumber: _stringValue(row['employee_no'], fallback: 'None'),
      company: _ellipsize(company, 24),
      companyName: company,
      departmentName: department,
      positionName: position,
      roleDepartment: _roleDepartment(position, department),
      hired: _formatDate(_stringValue(row['hired_date'])),
      rawHiredDate: hiredDate,
      createdAt: createdAt,
      status: _stringValue(row['employment_status'], fallback: 'active'),
      avatarColor: _avatarColor(fullName),
    );
  }

  static List<EmployeePreview> _sortNewestFirst(
    List<EmployeePreview> employees,
  ) {
    return employees.toList(growable: false)..sort((a, b) {
      final aDate = a.createdAt ?? _dateTimeValue(a.rawHiredDate);
      final bDate = b.createdAt ?? _dateTimeValue(b.rawHiredDate);
      if (aDate != null && bDate != null) {
        return bDate.compareTo(aDate);
      }
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  static String _stringValue(dynamic value, {String fallback = '-'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateTimeValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  static String _displayName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => _cleanNamePart(part) != null)
        .toList();

    return parts.isEmpty ? 'UNNAMED EMPLOYEE' : parts.join(' ').toUpperCase();
  }

  static String _employeeDisplayName(Map<String, dynamic> row) {
    final firstName = _cleanNamePart(row['first_name']);
    final middleName = _cleanNamePart(row['middle_name']);
    final lastName = _cleanNamePart(row['last_name']);
    final suffix = _cleanNamePart(row['suffix']);
    final parts = <String>[
      ?firstName,
      if (middleName != null) '${middleName[0].toUpperCase()}.',
      ?lastName,
      ?suffix,
    ];

    if (parts.isNotEmpty) {
      return parts.join(' ').toUpperCase();
    }

    return _displayName(
      _stringValue(row['full_name'], fallback: 'Unnamed Employee'),
    );
  }

  static String? _cleanNamePart(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final normalized = text
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (text.isEmpty || normalized == 'na') {
      return null;
    }
    return text;
  }

  static String _roleDepartment(String position, String department) {
    if (position == '-' && department == '-') {
      return '-\n-';
    }

    return '$position\n$department';
  }

  static String _formatDate(String value) {
    if (value == '-') {
      return '-';
    }

    final date = DateTime.tryParse(value);
    if (date == null) {
      return value;
    }

    const months = [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May',
      'Jun.',
      'Jul.',
      'Aug.',
      'Sep.',
      'Oct.',
      'Nov.',
      'Dec.',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  static String _fileExtension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index == -1 || index == fileName.length - 1) {
      return 'jpg';
    }
    return fileName.substring(index + 1).toLowerCase();
  }

  static String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  static String _ellipsize(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }

    return '${value.substring(0, maxLength - 3)}...';
  }

  static Color _avatarColor(String value) {
    const colors = [
      Color(0xFFDBEAFE),
      Color(0xFFEDE9FE),
      Color(0xFFD1FAE5),
      Color(0xFFFFEDD5),
      Color(0xFFE0F2FE),
    ];
    final index =
        value.codeUnits.fold<int>(0, (sum, codeUnit) => sum + codeUnit) %
        colors.length;
    return colors[index];
  }
}

class CompanyDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<CompanyPreview>> loadCompanies() async {
    if (await LocalSyncService.isOnline()) {
      try {
        final response = await _client.rpc(
          'hr_company_directory',
          params: {
            'p_username': AppConfig.hrUsername,
            'p_password': AppConfig.hrPassword,
          },
        );
        if (response is List) {
          final rows = response.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
          await LocalSyncService.cacheRows('company_cache', rows);
          unawaited(LocalSyncService.syncNow());
          return rows
              .map(CompanyDirectoryService._fromRow)
              .toList(growable: false);
        }
      } catch (_) {}
    }
    final cached = await LocalSyncService.loadCachedRows('company_cache');
    return cached.map(CompanyDirectoryService._fromRow).toList(growable: false);
  }

  static Future<String> createCompany({
    required String name,
    required String contactNumber,
    required String address,
    required String logoUrl,
  }) async {
    await LocalSyncService.enqueue(
      entity: 'company',
      action: 'create',
      payload: {
        'name': name,
        'contactNumber': contactNumber,
        'address': address,
        'logoUrl': logoUrl,
      },
    );
    if (await LocalSyncService.isOnline()) {
      unawaited(LocalSyncService.syncNow());
      return 'Queued locally and syncing to Supabase...';
    }
    return 'Saved locally (offline). Will sync when internet is available.';
  }

  static Future<String> _createCompanyRemote({
    required String name,
    required String contactNumber,
    required String address,
    required String logoUrl,
  }) async {
    final response = await _client.rpc(
      'hr_create_company',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_name': name.trim(),
        'p_contact_number': contactNumber.trim(),
        'p_address': address.trim(),
        'p_logo_url': logoUrl.trim(),
      },
    );

    return response.toString();
  }

  static Future<String> deleteCompany(String id) async {
    await LocalSyncService.enqueue(
      entity: 'company',
      action: 'delete',
      payload: {'id': id},
    );
    if (await LocalSyncService.isOnline()) {
      unawaited(LocalSyncService.syncNow());
      return 'Delete queued locally and syncing to Supabase...';
    }
    return 'Delete queued offline. Will sync when internet is available.';
  }

  static Future<String> _deleteCompanyRemote(String id) async {
    final response = await _client.rpc(
      'hr_delete_company',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_company_id': id,
      },
    );

    return response.toString();
  }

  static CompanyPreview _fromRow(Map<String, dynamic> row) {
    final name = EmployeeDirectoryService._stringValue(
      row['company_name'],
      fallback: 'Unnamed Company',
    );
    final code = EmployeeDirectoryService._stringValue(
      row['company_code'],
      fallback: '',
    );
    final isActive = row['is_active'] == true;

    return CompanyPreview(
      id: EmployeeDirectoryService._stringValue(row['company_id']),
      name: name,
      initials: _initials(code.isEmpty ? name : code),
      contactNumber: EmployeeDirectoryService._stringValue(
        row['contact_number'],
      ),
      address: EmployeeDirectoryService._stringValue(row['address']),
      status: isActive ? 'active' : 'inactive',
    );
  }

  static String _initials(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      return '?';
    }

    final words = clean
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length == 1) {
      return words.first
          .substring(0, words.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }

    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

class DepartmentDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<DepartmentPreview>> loadDepartments() async {
    final response = await _client.rpc(
      'hr_department_directory',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
      },
    );

    if (response is! List) {
      return const [];
    }

    return response
        .whereType<Map<String, dynamic>>()
        .map(DepartmentDirectoryService._fromRow)
        .toList();
  }

  static Future<String> createDepartment(String name) async {
    final response = await _client.rpc(
      'hr_create_department',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_name': name.trim(),
      },
    );

    return response.toString();
  }

  static Future<String> updateDepartment({
    required String id,
    required String name,
  }) async {
    final response = await _client.rpc(
      'hr_update_department',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_department_id': id,
        'p_name': name.trim(),
      },
    );

    return response.toString();
  }

  static Future<String> deleteDepartment(String id) async {
    final response = await _client.rpc(
      'hr_delete_department',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_department_id': id,
      },
    );

    return response.toString();
  }

  static DepartmentPreview _fromRow(Map<String, dynamic> row) {
    final createdAt = EmployeeDirectoryService._stringValue(row['created_at']);
    final updatedAt = EmployeeDirectoryService._stringValue(
      row['updated_at'],
      fallback: createdAt,
    );

    return DepartmentPreview(
      id: EmployeeDirectoryService._stringValue(row['department_id']),
      name: EmployeeDirectoryService._stringValue(
        row['department_name'],
        fallback: 'Unnamed Department',
      ).toUpperCase(),
      employeeCount: _intValue(row['employee_count']),
      created: _formatDate(createdAt),
      updated: _formatDate(updatedAt),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatDate(String value) {
    if (value == '-') {
      return '-';
    }

    final date = DateTime.tryParse(value);
    if (date == null) {
      return value;
    }

    const months = [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May',
      'Jun.',
      'Jul.',
      'Aug.',
      'Sep.',
      'Oct.',
      'Nov.',
      'Dec.',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class PositionDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<PositionPreview>> loadPositions() async {
    final response = await _client.rpc(
      'hr_position_directory',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
      },
    );

    if (response is! List) {
      return const [];
    }

    return response
        .whereType<Map<String, dynamic>>()
        .map(PositionDirectoryService._fromRow)
        .toList();
  }

  static Future<String> createPosition(String name) async {
    final response = await _client.rpc(
      'hr_create_position',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_name': name.trim(),
      },
    );

    return response.toString();
  }

  static Future<String> updatePosition({
    required String id,
    required String name,
  }) async {
    final response = await _client.rpc(
      'hr_update_position',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_position_id': id,
        'p_name': name.trim(),
      },
    );

    return response.toString();
  }

  static Future<String> deletePosition(String id) async {
    final response = await _client.rpc(
      'hr_delete_position',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_position_id': id,
      },
    );

    return response.toString();
  }

  static PositionPreview _fromRow(Map<String, dynamic> row) {
    final createdAt = EmployeeDirectoryService._stringValue(row['created_at']);
    final updatedAt = EmployeeDirectoryService._stringValue(
      row['updated_at'],
      fallback: createdAt,
    );

    return PositionPreview(
      id: EmployeeDirectoryService._stringValue(row['position_id']),
      name: EmployeeDirectoryService._stringValue(
        row['position_name'],
        fallback: 'Unnamed Position',
      ).toUpperCase(),
      authorityLevel: DepartmentDirectoryService._intValue(
        row['authority_level'],
      ),
      employeeCount: DepartmentDirectoryService._intValue(
        row['employee_count'],
      ),
      created: DepartmentDirectoryService._formatDate(createdAt),
      updated: DepartmentDirectoryService._formatDate(updatedAt),
    );
  }
}

class DepartmentPositionCatalogService {
  static final _client = Supabase.instance.client;

  static Future<List<DepartmentPositionCatalogPreview>>
  loadDepartmentPositionCatalog() async {
    final response = await _client.rpc('admin_department_position_catalog');

    if (response is! List) {
      return const [];
    }

    return response
        .whereType<Map<String, dynamic>>()
        .map(_departmentPositionFromRow)
        .toList();
  }

  static Future<List<AdminPositionCatalogPreview>> loadPositionCatalog() async {
    final response = await _client.rpc('admin_position_catalog');

    if (response is! List) {
      return const [];
    }

    return response
        .whereType<Map<String, dynamic>>()
        .map(_positionCatalogFromRow)
        .toList();
  }

  static Future<String> assignDepartmentPosition({
    required String departmentId,
    required String positionId,
  }) async {
    final response = await _client.rpc(
      'admin_assign_department_position',
      params: {'p_department_id': departmentId, 'p_position_id': positionId},
    );

    return response.toString();
  }

  static Future<String> removeDepartmentPosition({
    required String departmentId,
    required String positionId,
  }) async {
    final response = await _client.rpc(
      'admin_remove_department_position',
      params: {'p_department_id': departmentId, 'p_position_id': positionId},
    );

    return response.toString();
  }

  static DepartmentPositionCatalogPreview _departmentPositionFromRow(
    Map<String, dynamic> row,
  ) {
    final positionId = EmployeeDirectoryService._stringValue(
      row['position_id'],
      fallback: '',
    );
    final positionName = EmployeeDirectoryService._stringValue(
      row['position_name'],
      fallback: '',
    );

    return DepartmentPositionCatalogPreview(
      departmentId: EmployeeDirectoryService._stringValue(row['department_id']),
      departmentName: EmployeeDirectoryService._stringValue(
        row['department_name'],
        fallback: 'Unnamed Department',
      ).toUpperCase(),
      positionId: positionId.isEmpty ? null : positionId,
      positionName: positionName.isEmpty ? null : positionName.toUpperCase(),
      authorityLevel: int.tryParse(row['authority_level']?.toString() ?? ''),
      employeeCount: DepartmentDirectoryService._intValue(
        row['employee_count'],
      ),
    );
  }

  static AdminPositionCatalogPreview _positionCatalogFromRow(
    Map<String, dynamic> row,
  ) {
    return AdminPositionCatalogPreview(
      positionId: EmployeeDirectoryService._stringValue(row['position_id']),
      positionName: EmployeeDirectoryService._stringValue(
        row['position_name'],
        fallback: 'Unnamed Position',
      ).toUpperCase(),
      employeeCount: DepartmentDirectoryService._intValue(
        row['employee_count'],
      ),
    );
  }
}

class RegisteredUsersService {
  static final _client = Supabase.instance.client;

  static Future<List<RegisteredUserPreview>> loadUsers() async {
    final response = await _client.rpc('admin_registered_users');

    if (response is! List) {
      return const [];
    }

    return response.whereType<Map<String, dynamic>>().map(_fromRow).toList();
  }

  static Future<String> setUserBan({
    required String userProfileId,
    required bool isBanned,
  }) async {
    final response = await _client.rpc(
      'admin_set_user_ban',
      params: {'p_user_profile_id': userProfileId, 'p_is_banned': isBanned},
    );

    return response.toString();
  }

  static Future<String> setUserRole({
    required String userProfileId,
    required String appRole,
  }) async {
    final response = await _client.rpc(
      'admin_set_user_role',
      params: {'p_user_profile_id': userProfileId, 'p_app_role': appRole},
    );

    return response.toString();
  }

  static Future<String> resetUserPassword({
    required String userProfileId,
    required String newPassword,
  }) async {
    final response = await _client.rpc(
      'admin_reset_user_password',
      params: {
        'p_user_profile_id': userProfileId,
        'p_new_password': newPassword,
      },
    );

    return response.toString();
  }

  static Future<String> setLeaveCredits({
    required String userProfileId,
    required double annualCreditDays,
  }) async {
    final response = await _client.rpc(
      'admin_set_employee_leave_credits',
      params: {
        'p_user_profile_id': userProfileId,
        'p_annual_credit_days': annualCreditDays,
      },
    );

    return response.toString();
  }

  static Future<String> createUnlinkedUser({
    required String username,
    required String email,
    required String password,
    required String appRole,
  }) async {
    final response = await _client.rpc(
      'admin_create_unlinked_user',
      params: {
        'p_username': username,
        'p_email': email,
        'p_password': password,
        'p_app_role': appRole,
      },
    );

    return response.toString();
  }

  static RegisteredUserPreview _fromRow(Map<String, dynamic> row) {
    final registeredAt = EmployeeDirectoryService._stringValue(
      row['registered_at'],
    );
    final emailConfirmedAt = EmployeeDirectoryService._stringValue(
      row['email_confirmed_at'],
    );
    final lastSignInAt = EmployeeDirectoryService._stringValue(
      row['last_sign_in_at'],
    );
    final employeeId = EmployeeDirectoryService._stringValue(
      row['employee_id'],
      fallback: '',
    );

    return RegisteredUserPreview(
      userProfileId: EmployeeDirectoryService._stringValue(
        row['user_profile_id'],
      ),
      authUserId: EmployeeDirectoryService._stringValue(row['auth_user_id']),
      username: EmployeeDirectoryService._stringValue(
        row['username'],
        fallback: 'NO USERNAME',
      ),
      email: EmployeeDirectoryService._stringValue(
        row['email'],
        fallback: 'NO EMAIL',
      ),
      appRole: EmployeeDirectoryService._stringValue(
        row['app_role'],
        fallback: 'employee',
      ).toUpperCase(),
      isActive: row['is_active'] == true,
      isBanned: row['is_banned'] == true,
      employeeId: employeeId.isEmpty ? null : employeeId,
      employeeNo: EmployeeDirectoryService._stringValue(
        row['employee_no'],
        fallback: '-',
      ),
      fullName: EmployeeDirectoryService._stringValue(
        row['full_name'],
        fallback: 'No linked employee',
      ).toUpperCase(),
      photoUrl: _nullableString(row['photo_url']),
      employmentStatus: EmployeeDirectoryService._stringValue(
        row['employment_status'],
        fallback: 'N/A',
      ).toUpperCase(),
      leaveCreditDays: _nullableDouble(row['leave_credit_days']),
      leaveUsedDays: _nullableDouble(row['leave_used_days']),
      leaveRemainingDays: _nullableDouble(row['leave_remaining_days']),
      registeredAt: DepartmentDirectoryService._formatDate(registeredAt),
      emailConfirmedAt: DepartmentDirectoryService._formatDate(
        emailConfirmedAt,
      ),
      lastSignInAt: DepartmentDirectoryService._formatDate(lastSignInAt),
    );
  }

  static String? _nullableString(dynamic value) {
    final text = EmployeeDirectoryService._stringValue(value, fallback: '');
    return text.isEmpty ? null : text;
  }

  static double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class StoreDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<StorePreview>> loadStores() async {
    final response = await _client.rpc(
      'hr_store_directory',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
      },
    );
    if (response is! List) return const [];
    return response.whereType<Map<String, dynamic>>().map(_fromRow).toList();
  }

  static Future<String> createStore({
    required String name,
    required String companyName,
    required String clusterName,
  }) async {
    return (await _client.rpc(
      'hr_create_store',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_company_name': companyName,
        'p_name': name.trim(),
        'p_cluster_name': clusterName == 'Unassigned' ? null : clusterName,
      },
    )).toString();
  }

  static Future<String> updateStore({
    required String id,
    required String name,
    required String companyName,
    required String clusterName,
  }) async {
    return (await _client.rpc(
      'hr_update_store',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_store_id': id,
        'p_company_name': companyName,
        'p_name': name.trim(),
        'p_cluster_name': clusterName == 'Unassigned' ? null : clusterName,
      },
    )).toString();
  }

  static Future<String> deleteStore(String id) async {
    return (await _client.rpc(
      'hr_delete_store',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_store_id': id,
      },
    )).toString();
  }

  static StorePreview _fromRow(Map<String, dynamic> row) {
    final createdAt = EmployeeDirectoryService._stringValue(row['created_at']);
    final updatedAt = EmployeeDirectoryService._stringValue(
      row['updated_at'],
      fallback: createdAt,
    );
    return StorePreview(
      id: EmployeeDirectoryService._stringValue(row['store_id']),
      name: EmployeeDirectoryService._stringValue(
        row['store_name'],
        fallback: 'Unnamed Store',
      ).toUpperCase(),
      companyName: EmployeeDirectoryService._stringValue(row['company_name']),
      clusterName: EmployeeDirectoryService._stringValue(
        row['cluster_name'],
        fallback: 'Unassigned',
      ).toUpperCase(),
      employeeCount: DepartmentDirectoryService._intValue(
        row['employee_count'],
      ),
      created: DepartmentDirectoryService._formatDate(createdAt),
      updated: DepartmentDirectoryService._formatDate(updatedAt),
    );
  }
}

class ClusterDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<ClusterPreview>> loadClusters() async {
    final response = await _client.rpc(
      'hr_cluster_directory',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
      },
    );
    if (response is! List) return const [];
    return response.whereType<Map<String, dynamic>>().map(_fromRow).toList();
  }

  static Future<String> createCluster({
    required String name,
    required List<String> storeIds,
  }) async {
    return (await _client.rpc(
      'hr_create_cluster_with_stores',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_name': name.trim(),
        'p_store_ids': storeIds,
      },
    )).toString();
  }

  static Future<String> updateCluster({
    required String id,
    required String name,
    required List<String> storeIds,
  }) async {
    return (await _client.rpc(
      'hr_update_cluster_with_stores',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_cluster_id': id,
        'p_name': name.trim(),
        'p_store_ids': storeIds,
      },
    )).toString();
  }

  static Future<String> deleteCluster(String id) async {
    return (await _client.rpc(
      'hr_delete_cluster',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_cluster_id': id,
      },
    )).toString();
  }

  static ClusterPreview _fromRow(Map<String, dynamic> row) {
    final createdAt = EmployeeDirectoryService._stringValue(row['created_at']);
    final updatedAt = EmployeeDirectoryService._stringValue(
      row['updated_at'],
      fallback: createdAt,
    );
    return ClusterPreview(
      id: EmployeeDirectoryService._stringValue(row['cluster_id']),
      name: EmployeeDirectoryService._stringValue(
        row['cluster_name'],
        fallback: 'Unnamed Cluster',
      ).toUpperCase(),
      companyName: EmployeeDirectoryService._stringValue(row['company_name']),
      storeCount: DepartmentDirectoryService._intValue(row['store_count']),
      storeNames: EmployeeDirectoryService._stringValue(
        row['store_names'],
        fallback: 'No stores',
      ).toUpperCase(),
      created: DepartmentDirectoryService._formatDate(createdAt),
      updated: DepartmentDirectoryService._formatDate(updatedAt),
    );
  }
}

class AreaDirectoryService {
  static final _client = Supabase.instance.client;

  static Future<List<AreaPreview>> loadAreas() async {
    final response = await _client.rpc(
      'hr_area_directory',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
      },
    );
    if (response is! List) return const [];
    return response.whereType<Map<String, dynamic>>().map(_fromRow).toList();
  }

  static Future<String> createArea({
    required String name,
    required List<String> clusterIds,
  }) async {
    return (await _client.rpc(
      'hr_create_area_with_clusters',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_name': name.trim(),
        'p_cluster_ids': clusterIds,
      },
    )).toString();
  }

  static Future<String> updateArea({
    required String id,
    required String name,
    required List<String> clusterIds,
  }) async {
    return (await _client.rpc(
      'hr_update_area_with_clusters',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_area_id': id,
        'p_name': name.trim(),
        'p_cluster_ids': clusterIds,
      },
    )).toString();
  }

  static Future<String> deleteArea(String id) async {
    return (await _client.rpc(
      'hr_delete_area',
      params: {
        'p_username': AppConfig.hrUsername,
        'p_password': AppConfig.hrPassword,
        'p_area_id': id,
      },
    )).toString();
  }

  static AreaPreview _fromRow(Map<String, dynamic> row) {
    final createdAt = EmployeeDirectoryService._stringValue(row['created_at']);
    final updatedAt = EmployeeDirectoryService._stringValue(
      row['updated_at'],
      fallback: createdAt,
    );
    return AreaPreview(
      id: EmployeeDirectoryService._stringValue(row['area_id']),
      name: EmployeeDirectoryService._stringValue(
        row['area_name'],
        fallback: 'Unnamed Area',
      ).toUpperCase(),
      clusterCount: DepartmentDirectoryService._intValue(row['cluster_count']),
      storeCount: DepartmentDirectoryService._intValue(row['store_count']),
      clusterNames: EmployeeDirectoryService._stringValue(
        row['cluster_names'],
        fallback: 'No clusters',
      ).toUpperCase(),
      created: DepartmentDirectoryService._formatDate(createdAt),
      updated: DepartmentDirectoryService._formatDate(updatedAt),
    );
  }
}

class AdminWorkflowService {
  static final _client = Supabase.instance.client;

  static Map<String, dynamic> get _credentials => {
    'p_username': AppConfig.hrUsername,
    'p_password': AppConfig.hrPassword,
  };

  static Future<List<AuthorityCandidatePreview>>
  loadAuthorityCandidates() async {
    final response = await _client.rpc(
      'hr_admin_authority_candidates',
      params: _credentials,
    );
    if (response is! List) return const [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(_authorityCandidateFromRow)
        .toList();
  }

  static Future<List<StoreRouteScopePreview>> loadStoreRouteScopes() async {
    final response = await _client.rpc(
      'hr_admin_store_route_scopes',
      params: _credentials,
    );
    if (response is! List) return const [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(_storeRouteScopeFromRow)
        .toList();
  }

  static Future<String> setAuthorityAssignment({
    required String employeeId,
    required String functionId,
    required int authorityLevel,
    String? storeId,
    String? clusterId,
    String? areaId,
  }) async {
    return (await _client.rpc(
      'hr_admin_set_authority_assignment',
      params: {
        ..._credentials,
        'p_employee_id': employeeId,
        'p_function_id': functionId,
        'p_authority_level': authorityLevel,
        'p_store_id': storeId,
        'p_cluster_id': clusterId,
        'p_area_id': areaId,
      },
    )).toString();
  }

  static Future<List<AdminPositionAuthorityPreview>>
  loadPositionAuthorityLevels() async {
    final response = await _client.rpc(
      'hr_admin_position_authority_levels',
      params: _credentials,
    );
    if (response is! List) return const [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(_positionAuthorityFromRow)
        .toList();
  }

  static Future<String> setPositionAuthorityLevel({
    required String positionId,
    required int authorityLevel,
  }) async {
    return (await _client.rpc(
      'hr_admin_set_position_authority_level',
      params: {
        ..._credentials,
        'p_position_id': positionId,
        'p_authority_level': authorityLevel,
      },
    )).toString();
  }

  static Future<String> clearPositionAuthorityLevel(String positionId) async {
    return (await _client.rpc(
      'hr_admin_clear_position_authority_level',
      params: {..._credentials, 'p_position_id': positionId},
    )).toString();
  }

  static Future<List<DepartmentLadderPreview>>
  loadDepartmentApprovalLadders() async {
    final response = await _client.rpc(
      'hr_admin_department_approval_ladders',
      params: _credentials,
    );
    if (response is! List) return const [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(_departmentLadderFromRow)
        .toList();
  }

  static Future<String> setDepartmentApprovalLadder({
    required String departmentId,
    required List<int> levels,
    required Map<int, String> roles,
  }) async {
    final params = {
      ..._credentials,
      'p_department_id': departmentId,
      'p_levels': levels,
      'p_roles': roles.map((level, positionId) {
        return MapEntry(level.toString(), positionId);
      }),
    };

    try {
      return (await _client.rpc(
        'hr_admin_set_department_approval_ladder',
        params: params,
      )).toString();
    } catch (error) {
      final message = error.toString();
      if (roles.isEmpty && message.contains('PGRST202')) {
        return (await _client.rpc(
          'hr_admin_set_department_approval_ladder',
          params: {
            ..._credentials,
            'p_department_id': departmentId,
            'p_levels': levels,
          },
        )).toString();
      }
      rethrow;
    }
  }

  static AuthorityCandidatePreview _authorityCandidateFromRow(
    Map<String, dynamic> row,
  ) {
    return AuthorityCandidatePreview(
      employeeId: EmployeeDirectoryService._stringValue(row['employee_id']),
      employeeNo: EmployeeDirectoryService._stringValue(row['employee_no']),
      fullName: EmployeeDirectoryService._stringValue(
        row['full_name'],
        fallback: 'Unnamed Employee',
      ).toUpperCase(),
      positionId: EmployeeDirectoryService._stringValue(row['position_id']),
      positionName: EmployeeDirectoryService._stringValue(
        row['position_name'],
      ).toUpperCase(),
      positionLevel: _nullableInt(row['position_level']),
      functionId: EmployeeDirectoryService._stringValue(row['function_id']),
      functionName: EmployeeDirectoryService._stringValue(
        row['function_name'],
      ).toUpperCase(),
      areaId: _nullableString(row['area_id']),
      areaName: EmployeeDirectoryService._stringValue(
        row['area_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      clusterId: _nullableString(row['cluster_id']),
      clusterName: EmployeeDirectoryService._stringValue(
        row['cluster_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      storeId: _nullableString(row['store_id']),
      storeName: EmployeeDirectoryService._stringValue(
        row['store_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      companyName: EmployeeDirectoryService._stringValue(
        row['company_name'],
      ).toUpperCase(),
      departmentId: _nullableString(row['department_id']),
      departmentName: EmployeeDirectoryService._stringValue(
        row['department_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      currentAuthorityLevel: _nullableInt(row['current_authority_level']),
    );
  }

  static StoreRouteScopePreview _storeRouteScopeFromRow(
    Map<String, dynamic> row,
  ) {
    return StoreRouteScopePreview(
      departmentId: _nullableString(row['department_id']),
      departmentName: EmployeeDirectoryService._stringValue(
        row['department_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      storeId: EmployeeDirectoryService._stringValue(row['store_id']),
      storeName: EmployeeDirectoryService._stringValue(
        row['store_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      areaId: _nullableString(row['area_id']),
      areaName: EmployeeDirectoryService._stringValue(
        row['area_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      clusterId: _nullableString(row['cluster_id']),
      clusterName: EmployeeDirectoryService._stringValue(
        row['cluster_name'],
        fallback: 'N/A',
      ).toUpperCase(),
      routeApprovers: _routeApproversFromRow(row['route_approvers']),
    );
  }

  static Map<int, List<String>> _routeApproversFromRow(dynamic value) {
    if (value is! Map) return const {};
    final approvers = <int, List<String>>{};
    value.forEach((levelKey, rawNames) {
      final level = int.tryParse(levelKey.toString());
      if (level == null || rawNames is! List) return;
      approvers[level] =
          rawNames
              .map((name) => EmployeeDirectoryService._stringValue(name))
              .where((name) => name.trim().isNotEmpty)
              .map((name) => name.toUpperCase())
              .toSet()
              .toList()
            ..sort();
    });
    return approvers;
  }

  static AdminPositionAuthorityPreview _positionAuthorityFromRow(
    Map<String, dynamic> row,
  ) {
    return AdminPositionAuthorityPreview(
      positionId: EmployeeDirectoryService._stringValue(row['position_id']),
      positionName: EmployeeDirectoryService._stringValue(
        row['position_name'],
      ).toUpperCase(),
      authorityLevel: _nullableInt(row['authority_level']),
      employeeCount: DepartmentDirectoryService._intValue(
        row['employee_count'],
      ),
    );
  }

  static DepartmentLadderPreview _departmentLadderFromRow(
    Map<String, dynamic> row,
  ) {
    final rawLevels = row['route_levels'];
    final levels = rawLevels is List
        ? rawLevels
              .map((level) => int.tryParse(level.toString()))
              .whereType<int>()
              .toList()
        : <int>[];
    final roles = <int, DepartmentRouteRole>{};
    final rawRoles = row['route_roles'];
    if (rawRoles is Map) {
      rawRoles.forEach((levelKey, rawRole) {
        final level = int.tryParse(levelKey.toString());
        if (level == null || rawRole is! Map) return;
        final positionId = _nullableString(rawRole['position_id']);
        if (positionId == null) return;
        roles[level] = DepartmentRouteRole(
          positionId: positionId,
          positionName: EmployeeDirectoryService._stringValue(
            rawRole['position_name'],
          ).toUpperCase(),
        );
      });
    }
    return DepartmentLadderPreview(
      departmentId: EmployeeDirectoryService._stringValue(row['department_id']),
      departmentName: EmployeeDirectoryService._stringValue(
        row['department_name'],
      ).toUpperCase(),
      routeLevels: levels,
      routeRoles: roles,
    );
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static String? _nullableString(dynamic value) {
    final text = EmployeeDirectoryService._stringValue(value, fallback: '');
    return text.isEmpty ? null : text;
  }
}

class LocalSyncService {
  static Database? _db;
  static bool _syncInProgress = false;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static Timer? _periodicSyncTimer;
  static Timer? _connectivityPollTimer;
  static final StreamController<void> _connectionRestoredController =
      StreamController<void>.broadcast();
  static bool? _lastOnline;
  static bool _connectivityStreamSupported = true;

  static Stream<void> get onConnectionRestored =>
      _connectionRestoredController.stream;

  static Future<void> initialize() async {
    await _database;
    if (Platform.isWindows) {
      _connectivityStreamSupported = false;
    }
    if (_connectivitySub == null && _connectivityStreamSupported) {
      try {
        _connectivitySub = Connectivity().onConnectivityChanged.listen(
          (results) {
            if (results.any((r) => r != ConnectivityResult.none)) {
              unawaited(_checkForRestoredConnection());
            } else {
              _lastOnline = false;
            }
          },
          onError: (_) async {
            _connectivityStreamSupported = false;
            await _connectivitySub?.cancel();
            _connectivitySub = null;
          },
          cancelOnError: false,
        );
      } catch (_) {
        _connectivityStreamSupported = false;
      }
    }
    _periodicSyncTimer ??= Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(syncNow());
    });
    // connectivity_plus does not provide a reliable change stream on every
    // Windows setup. A lightweight reachability poll closes that gap.
    _connectivityPollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_checkForRestoredConnection());
    });
    unawaited(_checkForRestoredConnection());
  }

  static Future<void> _checkForRestoredConnection() async {
    final online = await isOnline();
    final wasOnline = _lastOnline;
    _lastOnline = online;
    if (online && wasOnline == false) {
      _connectionRestoredController.add(null);
      unawaited(syncNow());
    }
  }

  static Future<void> syncNow() async {
    if (_syncInProgress) {
      return;
    }
    if (!await isOnline()) {
      return;
    }
    _syncInProgress = true;
    try {
      final db = await _database;
      final rows = await db.query(
        'sync_outbox',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'id ASC',
        limit: 50,
      );
      for (final row in rows) {
        final id = row['id'] as int;
        final entity = (row['entity'] ?? '').toString();
        final action = (row['action'] ?? '').toString();
        final payloadRaw = (row['payload'] ?? '{}').toString();
        try {
          final payload = jsonDecode(payloadRaw);
          if (payload is! Map<String, dynamic>) {
            throw Exception('Invalid payload format');
          }
          await _applyOutboxItem(
            entity: entity,
            action: action,
            payload: payload,
          );
          await db.update(
            'sync_outbox',
            {
              'status': 'done',
              'last_error': null,
              'synced_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (error) {
          await db.update(
            'sync_outbox',
            {'status': 'pending', 'last_error': error.toString()},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }

  static Future<void> cacheRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(table);
      for (final row in rows) {
        await txn.insert(table, {'payload': jsonEncode(row)});
      }
    });
  }

  static Future<List<Map<String, dynamic>>> loadCachedRows(String table) async {
    final db = await _database;
    final rows = await db.query(table, orderBy: 'id ASC');
    return rows
        .map(
          (r) => (jsonDecode((r['payload'] ?? '{}').toString()) as Map)
              .cast<String, dynamic>(),
        )
        .toList(growable: false);
  }

  static Future<void> cacheProfile(
    String employeeId,
    Map<String, dynamic> row,
  ) async {
    final db = await _database;
    await db.insert('employee_profile_cache', {
      'employee_id': employeeId,
      'payload': jsonEncode(row),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> loadCachedProfile(
    String employeeId,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'employee_profile_cache',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (jsonDecode((rows.first['payload'] ?? '{}').toString()) as Map)
        .cast<String, dynamic>();
  }

  static Future<Map<String, EmployeeProfileDetails>>
  loadCachedProfileDetailsByEmployeeId() async {
    final db = await _database;
    final rows = await db.query(
      'employee_profile_cache',
      columns: <String>['employee_id', 'payload'],
      orderBy: 'updated_at DESC',
    );
    final result = <String, EmployeeProfileDetails>{};
    for (final row in rows) {
      final employeeId = (row['employee_id'] ?? '').toString().trim();
      if (employeeId.isEmpty || result.containsKey(employeeId)) {
        continue;
      }
      final payloadRaw = (row['payload'] ?? '{}').toString();
      try {
        final payload = (jsonDecode(payloadRaw) as Map).cast<String, dynamic>();
        result[employeeId] = EmployeeDirectoryService._profileFromRow(payload);
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  static Future<void> enqueue({
    required String entity,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _database;
    await db.insert('sync_outbox', {
      'entity': entity,
      'action': action,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
    unawaited(syncNow());
  }

  static Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        return false;
      }
    } catch (_) {
      // On some desktop platforms, connectivity stream/check may throw.
      // Fall back to DNS reachability test below.
    }
    try {
      final lookup = await InternetAddress.lookup(
        'supabase.co',
      ).timeout(const Duration(seconds: 2));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _applyOutboxItem({
    required String entity,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    if (entity == 'employee' && action == 'create') {
      await EmployeeDirectoryService._createEmployeeRemote(
        EmployeeProfilePayload(
          firstName: (payload['firstName'] ?? '').toString(),
          middleName: (payload['middleName'] ?? '').toString(),
          lastName: (payload['lastName'] ?? '').toString(),
          suffix: (payload['suffix'] ?? '').toString(),
          birthDate: payload['birthDate']?.toString(),
          gender: payload['gender']?.toString(),
          civilStatus: payload['civilStatus']?.toString(),
          phone: payload['phone']?.toString(),
          email: (payload['email'] ?? '').toString(),
          company: payload['company']?.toString(),
          department: payload['department']?.toString(),
          store: payload['store']?.toString(),
          position: payload['position']?.toString(),
          dateHired: payload['dateHired']?.toString(),
          employeeType: (payload['employeeType'] ?? '').toString(),
          employmentStatus: (payload['employmentStatus'] ?? 'pending')
              .toString(),
          schedule: (payload['schedule'] ?? '09:00 AM - 06:00 PM').toString(),
          dayOffDay: (payload['dayOffDay'] ?? 'Sunday').toString(),
          payrollClass: (payload['payrollClass'] ?? '').toString(),
          tin: (payload['tin'] ?? '').toString(),
          sss: (payload['sss'] ?? '').toString(),
          pagibig: (payload['pagibig'] ?? '').toString(),
          philhealth: (payload['philhealth'] ?? '').toString(),
          bankType: (payload['bankType'] ?? '').toString(),
          accountNo: (payload['accountNo'] ?? '').toString(),
          presentAddress: (payload['presentAddress'] ?? '').toString(),
          emergencyContact: (payload['emergencyContact'] ?? '').toString(),
          emergencyContactNo: (payload['emergencyContactNo'] ?? '').toString(),
          zipCode: (payload['zipCode'] ?? '').toString(),
          socialMediaType: (payload['socialMediaType'] ?? '').toString(),
          socialMediaDetail: (payload['socialMediaDetail'] ?? '').toString(),
          otherPhone: (payload['otherPhone'] ?? '').toString(),
          permanentAddress: (payload['permanentAddress'] ?? '').toString(),
          religion: (payload['religion'] ?? '').toString(),
          height: (payload['height'] ?? '').toString(),
          weight: (payload['weight'] ?? '').toString(),
          elementarySchool: (payload['elementarySchool'] ?? '').toString(),
          elementaryYear: (payload['elementaryYear'] ?? '').toString(),
          secondarySchool: (payload['secondarySchool'] ?? '').toString(),
          secondaryYear: (payload['secondaryYear'] ?? '').toString(),
          collegeSchool: (payload['collegeSchool'] ?? '').toString(),
          collegeYear: (payload['collegeYear'] ?? '').toString(),
          collegeCourse: (payload['collegeCourse'] ?? '').toString(),
          yearGraduated: (payload['yearGraduated'] ?? '').toString(),
          fatherName: (payload['fatherName'] ?? '').toString(),
          fatherOccupation: (payload['fatherOccupation'] ?? '').toString(),
          motherMaidenName: (payload['motherMaidenName'] ?? '').toString(),
          motherOccupation: (payload['motherOccupation'] ?? '').toString(),
          numberOfSiblings: (payload['numberOfSiblings'] ?? '').toString(),
          birthOrder: (payload['birthOrder'] ?? '').toString(),
          spouseName: (payload['spouseName'] ?? '').toString(),
          spouseOccupation: (payload['spouseOccupation'] ?? '').toString(),
          spouseContact: (payload['spouseContact'] ?? '').toString(),
          childrenNames: (payload['childrenNames'] ?? '').toString(),
          childrenCount: (payload['childrenCount'] ?? '').toString(),
        ),
      );
      return;
    }
    if (entity == 'employee' && action == 'update') {
      await EmployeeDirectoryService._updateEmployeeRemote(
        id: (payload['id'] ?? '').toString(),
        payload: EmployeeProfilePayload(
          firstName: (payload['firstName'] ?? '').toString(),
          middleName: (payload['middleName'] ?? '').toString(),
          lastName: (payload['lastName'] ?? '').toString(),
          suffix: (payload['suffix'] ?? '').toString(),
          birthDate: payload['birthDate']?.toString(),
          gender: payload['gender']?.toString(),
          civilStatus: payload['civilStatus']?.toString(),
          phone: payload['phone']?.toString(),
          email: (payload['email'] ?? '').toString(),
          company: payload['company']?.toString(),
          department: payload['department']?.toString(),
          store: payload['store']?.toString(),
          position: payload['position']?.toString(),
          dateHired: payload['dateHired']?.toString(),
          employeeType: (payload['employeeType'] ?? '').toString(),
          employmentStatus: (payload['employmentStatus'] ?? 'pending')
              .toString(),
          schedule: (payload['schedule'] ?? '09:00 AM - 06:00 PM').toString(),
          dayOffDay: (payload['dayOffDay'] ?? 'Sunday').toString(),
          payrollClass: (payload['payrollClass'] ?? '').toString(),
          tin: (payload['tin'] ?? '').toString(),
          sss: (payload['sss'] ?? '').toString(),
          pagibig: (payload['pagibig'] ?? '').toString(),
          philhealth: (payload['philhealth'] ?? '').toString(),
          bankType: (payload['bankType'] ?? '').toString(),
          accountNo: (payload['accountNo'] ?? '').toString(),
          presentAddress: (payload['presentAddress'] ?? '').toString(),
          emergencyContact: (payload['emergencyContact'] ?? '').toString(),
          emergencyContactNo: (payload['emergencyContactNo'] ?? '').toString(),
          zipCode: (payload['zipCode'] ?? '').toString(),
          socialMediaType: (payload['socialMediaType'] ?? '').toString(),
          socialMediaDetail: (payload['socialMediaDetail'] ?? '').toString(),
          otherPhone: (payload['otherPhone'] ?? '').toString(),
          permanentAddress: (payload['permanentAddress'] ?? '').toString(),
          religion: (payload['religion'] ?? '').toString(),
          height: (payload['height'] ?? '').toString(),
          weight: (payload['weight'] ?? '').toString(),
          elementarySchool: (payload['elementarySchool'] ?? '').toString(),
          elementaryYear: (payload['elementaryYear'] ?? '').toString(),
          secondarySchool: (payload['secondarySchool'] ?? '').toString(),
          secondaryYear: (payload['secondaryYear'] ?? '').toString(),
          collegeSchool: (payload['collegeSchool'] ?? '').toString(),
          collegeYear: (payload['collegeYear'] ?? '').toString(),
          collegeCourse: (payload['collegeCourse'] ?? '').toString(),
          yearGraduated: (payload['yearGraduated'] ?? '').toString(),
          fatherName: (payload['fatherName'] ?? '').toString(),
          fatherOccupation: (payload['fatherOccupation'] ?? '').toString(),
          motherMaidenName: (payload['motherMaidenName'] ?? '').toString(),
          motherOccupation: (payload['motherOccupation'] ?? '').toString(),
          numberOfSiblings: (payload['numberOfSiblings'] ?? '').toString(),
          birthOrder: (payload['birthOrder'] ?? '').toString(),
          spouseName: (payload['spouseName'] ?? '').toString(),
          spouseOccupation: (payload['spouseOccupation'] ?? '').toString(),
          spouseContact: (payload['spouseContact'] ?? '').toString(),
          childrenNames: (payload['childrenNames'] ?? '').toString(),
          childrenCount: (payload['childrenCount'] ?? '').toString(),
        ),
      );
      return;
    }
    if (entity == 'company' && action == 'create') {
      await CompanyDirectoryService._createCompanyRemote(
        name: (payload['name'] ?? '').toString(),
        contactNumber: (payload['contactNumber'] ?? '').toString(),
        address: (payload['address'] ?? '').toString(),
        logoUrl: (payload['logoUrl'] ?? '').toString(),
      );
      return;
    }
    if (entity == 'company' && action == 'delete') {
      await CompanyDirectoryService._deleteCompanyRemote(
        (payload['id'] ?? '').toString(),
      );
      return;
    }
  }

  static Future<Database> get _database async {
    if (_db != null) {
      return _db!;
    }
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final baseDir = localAppData == null || localAppData.trim().isEmpty
        ? Directory.current.path
        : p.join(localAppData, 'HYG Admin Desktop');
    await Directory(baseDir).create(recursive: true);
    final dbPath = p.join(baseDir, 'hyg_admin_local.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE employee_cache (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE company_cache (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)',
        );
        await db.execute('''
          CREATE TABLE employee_profile_cache (
            employee_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            last_error TEXT,
            created_at TEXT,
            synced_at TEXT
          )
        ''');
      },
    );
    return _db!;
  }
}

class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dkabosehgvldiwtdmvxh.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GPhU0IhaSiDw_VWldGs5ew_I5nG3H18',
  );

  static const hrUsername = String.fromEnvironment(
    'HYG_HR_USERNAME',
    defaultValue: 'hyg_hr',
  );

  static const hrPassword = String.fromEnvironment(
    'HYG_HR_PASSWORD',
    defaultValue: 'hyg_hr2026',
  );

  static const employeePhotoBucket = String.fromEnvironment(
    'HYG_EMPLOYEE_PHOTO_BUCKET',
    defaultValue: 'employee-photos',
  );

  static const localModelUrl = String.fromEnvironment(
    'HYG_LOCAL_MODEL_URL',
    defaultValue: 'http://127.0.0.1:11434/api/generate',
  );

  static const localModelName = String.fromEnvironment(
    'HYG_LOCAL_MODEL_NAME',
    defaultValue: 'qwen3.5:0.8b',
  );
}

class LocalHrModelService {
  static Future<String> healthCheck() async {
    final installed = await _installedOllamaModels();
    if (installed != null && installed.isNotEmpty) {
      final target = AppConfig.localModelName.toLowerCase();
      final hasModel = installed.any((m) => m.toLowerCase() == target);
      if (!hasModel) {
        final sample = installed.take(4).join(', ');
        throw Exception(
          'Local server reachable, but model `${AppConfig.localModelName}` is not installed. Installed: $sample',
        );
      }
      final endpoint = _candidateUris().first.toString();
      return 'Local model ready (${AppConfig.localModelName}) via $endpoint.';
    }
    throw Exception(
      'Cannot verify local server/model. Ensure Ollama is running and reachable on localhost.',
    );
  }

  static Future<List<String>?> _installedOllamaModels() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.parse(AppConfig.localModelUrl);
      final base = uri.replace(path: '', query: '', fragment: '');
      final tagsUri = base.replace(path: '/api/tags');
      final request = await client.getUrl(tagsUri);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final models = decoded['models'];
        if (models is List) {
          return models
              .whereType<Map<String, dynamic>>()
              .map((m) => (m['name'] ?? '').toString())
              .where((name) => name.trim().isNotEmpty)
              .toList(growable: false);
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static List<Uri> _candidateUris() {
    final configured = Uri.parse(AppConfig.localModelUrl);
    final list = <Uri>[configured];
    final base = configured.replace(path: '', query: '', fragment: '');
    final hasGenerate = configured.path.contains('/api/generate');
    final hasChat = configured.path.contains('/v1/chat/completions');
    if (!hasGenerate) {
      list.add(base.replace(path: '/api/generate'));
    }
    if (!hasChat) {
      list.add(base.replace(path: '/v1/chat/completions'));
    }
    final seen = <String>{};
    return list.where((u) => seen.add(u.toString())).toList(growable: false);
  }

  static Future<String?> _callModel({
    required Uri uri,
    required String prompt,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (uri.path.contains('/v1/chat/completions')) {
        request.add(
          utf8.encode(
            jsonEncode({
              'model': AppConfig.localModelName,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.2,
            }),
          ),
        );
      } else {
        request.add(
          utf8.encode(
            jsonEncode({
              'model': AppConfig.localModelName,
              'stream': false,
              'prompt': prompt,
              'options': {'num_predict': 256},
            }),
          ),
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (uri.path.contains('/v1/chat/completions')) {
          final choices = decoded['choices'];
          if (choices is List && choices.isNotEmpty) {
            final first = choices.first;
            if (first is Map<String, dynamic>) {
              final message = first['message'];
              if (message is Map<String, dynamic>) {
                final content = message['content']?.toString().trim();
                if (content != null && content.isNotEmpty) {
                  return content;
                }
              }
            }
          }
        } else {
          final text = decoded['response']?.toString().trim();
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
      return null;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> generateReply({
    required String userQuestion,
    required String hrContext,
  }) async {
    final prompt =
        '''
You are HYG Assist for HR analytics. Use the HR context below as source of truth.
Be concise, professional, and practical. If data is insufficient, say so clearly.

HR Context:
$hrContext

User Question:
$userQuestion
''';
    for (final uri in _candidateUris()) {
      final response = await _callModel(uri: uri, prompt: prompt);
      if (response != null) {
        return response;
      }
    }
    return null;
  }
}

class AdminRequestsService {
  static final _client = Supabase.instance.client;

  static Future<List<AdminRequestItem>> loadAllRequests() async {
    final response = await _client.rpc('admin_get_all_requests');
    if (response is! List) {
      return const [];
    }
    return response
        .whereType<Map<String, dynamic>>()
        .map(AdminRequestItem.fromRow)
        .toList(growable: false);
  }

  /// Deletes a request from Supabase.
  /// [isPerk] should be `true` when the request lives in employee_perk_requests.
  static Future<String> deleteRequest({
    required String requestId,
    required bool isPerk,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_delete_request',
        params: {'p_request_id': requestId, 'p_is_perk': isPerk},
      );
      return response?.toString() ?? 'Request deleted.';
    } catch (e) {
      return 'Failed to delete request: $e';
    }
  }

  /// Updates the status of a request.
  /// [isPerk] should be `true` when the request lives in employee_perk_requests.
  static Future<String> updateRequestStatus({
    required String requestId,
    required bool isPerk,
    required String newStatus,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_update_request_status',
        params: {
          'p_request_id': requestId,
          'p_is_perk': isPerk,
          'p_new_status': newStatus,
        },
      );
      return response?.toString() ?? 'Request updated.';
    } catch (e) {
      return 'Failed to update request: $e';
    }
  }

  /// Updates editable data fields of a request row.
  static Future<String> updateRequestData({
    required String requestId,
    required bool isPerk,
    // ESARF / time
    String? dateFrom,
    String? dateTo,
    String? timeFrom,
    String? timeTo,
    double? totalHours,
    // Leave
    String? leaveType,
    String? leaveCategory,
    String? startDate,
    String? endDate,
    double? totalDays,
    // Shared
    String? reason,
    // Perk
    String? productName,
    int? quantity,
    double? amount,
    double? finalAmount,
    String? txnDate,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_request_id': requestId,
        'p_is_perk': isPerk,
      };
      if (dateFrom != null) params['p_date_from'] = dateFrom;
      if (dateTo != null) params['p_date_to'] = dateTo;
      if (timeFrom != null) params['p_time_from'] = timeFrom;
      if (timeTo != null) params['p_time_to'] = timeTo;
      if (totalHours != null) params['p_total_hours'] = totalHours;
      if (leaveType != null) params['p_leave_type'] = leaveType;
      if (leaveCategory != null) params['p_leave_category'] = leaveCategory;
      if (startDate != null) params['p_start_date'] = startDate;
      if (endDate != null) params['p_end_date'] = endDate;
      if (totalDays != null) params['p_total_days'] = totalDays;
      if (reason != null) params['p_reason'] = reason;
      if (productName != null) params['p_product_name'] = productName;
      if (quantity != null) params['p_quantity'] = quantity;
      if (amount != null) params['p_amount'] = amount;
      if (finalAmount != null) params['p_final_amount'] = finalAmount;
      if (txnDate != null) params['p_txn_date'] = txnDate;

      final response = await _client.rpc(
        'admin_update_request_data',
        params: params,
      );
      return response?.toString() ?? 'Request updated.';
    } catch (e) {
      return 'Failed to update request: $e';
    }
  }
}
