part of '../main.dart';

enum EmployeeDeleteMode { soft, hard }

class EmployeePreview {
  const EmployeePreview({
    required this.id,
    required this.name,
    required this.initial,
    required this.email,
    required this.phone,
    required this.photoUrl,
    required this.idNumber,
    required this.company,
    required this.companyName,
    required this.departmentName,
    required this.positionName,
    required this.roleDepartment,
    required this.hired,
    required this.rawHiredDate,
    required this.createdAt,
    required this.status,
    required this.avatarColor,
  });

  final String id;
  final String name;
  final String initial;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final String idNumber;
  final String company;
  final String companyName;
  final String departmentName;
  final String positionName;
  final String roleDepartment;
  final String hired;
  final String? rawHiredDate;
  final DateTime? createdAt;
  final String status;
  final Color avatarColor;
}

class EmployeeProfilePayload {
  const EmployeeProfilePayload({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
    required this.birthDate,
    required this.gender,
    required this.civilStatus,
    required this.phone,
    required this.email,
    required this.company,
    required this.department,
    required this.store,
    required this.position,
    required this.dateHired,
    required this.employeeType,
    required this.employmentStatus,
    required this.schedule,
    required this.dayOffDay,
    required this.payrollClass,
    required this.tin,
    required this.sss,
    required this.pagibig,
    required this.philhealth,
    required this.bankType,
    required this.accountNo,
    required this.presentAddress,
    required this.emergencyContact,
    required this.emergencyContactNo,
    required this.zipCode,
    required this.socialMediaType,
    required this.socialMediaDetail,
    required this.otherPhone,
    required this.permanentAddress,
    required this.religion,
    required this.height,
    required this.weight,
    required this.elementarySchool,
    required this.elementaryYear,
    required this.secondarySchool,
    required this.secondaryYear,
    required this.collegeSchool,
    required this.collegeYear,
    required this.collegeCourse,
    required this.yearGraduated,
    required this.fatherName,
    required this.fatherOccupation,
    required this.motherMaidenName,
    required this.motherOccupation,
    required this.numberOfSiblings,
    required this.birthOrder,
    required this.spouseName,
    required this.spouseOccupation,
    required this.spouseContact,
    required this.childrenNames,
    required this.childrenCount,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String suffix;
  final String? birthDate;
  final String? gender;
  final String? civilStatus;
  final String? phone;
  final String email;
  final String? company;
  final String? department;
  final String? store;
  final String? position;
  final String? dateHired;
  final String employeeType;
  final String employmentStatus;
  final String schedule;
  final String dayOffDay;
  final String payrollClass;
  final String tin;
  final String sss;
  final String pagibig;
  final String philhealth;
  final String bankType;
  final String accountNo;
  final String presentAddress;
  final String emergencyContact;
  final String emergencyContactNo;
  final String zipCode;
  final String socialMediaType;
  final String socialMediaDetail;
  final String otherPhone;
  final String permanentAddress;
  final String religion;
  final String height;
  final String weight;
  final String elementarySchool;
  final String elementaryYear;
  final String secondarySchool;
  final String secondaryYear;
  final String collegeSchool;
  final String collegeYear;
  final String collegeCourse;
  final String yearGraduated;
  final String fatherName;
  final String fatherOccupation;
  final String motherMaidenName;
  final String motherOccupation;
  final String numberOfSiblings;
  final String birthOrder;
  final String spouseName;
  final String spouseOccupation;
  final String spouseContact;
  final String childrenNames;
  final String childrenCount;
}

class EmployeeProfileDetails {
  const EmployeeProfileDetails({
    this.idNumber,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.birthDate,
    this.gender,
    this.civilStatus,
    this.email,
    this.phone,
    this.zipCode,
    this.socialMediaType,
    this.socialMediaDetail,
    this.otherPhone,
    this.presentAddress,
    this.permanentAddress,
    this.dateHired,
    this.religion,
    this.height,
    this.weight,
    this.employeeType,
    this.schedule,
    this.dayOffDay,
    this.payrollClass,
    this.bankType,
    this.companyName,
    this.departmentName,
    this.storeName,
    this.positionName,
    this.tin,
    this.sss,
    this.pagibig,
    this.philhealth,
    this.accountNo,
    this.emergencyContact,
    this.emergencyContactNo,
    this.elementarySchool,
    this.elementaryYear,
    this.secondarySchool,
    this.secondaryYear,
    this.collegeSchool,
    this.collegeYear,
    this.collegeCourse,
    this.yearGraduated,
    this.fatherName,
    this.fatherOccupation,
    this.motherMaidenName,
    this.motherOccupation,
    this.numberOfSiblings,
    this.birthOrder,
    this.spouseName,
    this.spouseOccupation,
    this.spouseContact,
    this.childrenNames,
    this.childrenCount,
  });

  final String? idNumber;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final String? birthDate;
  final String? gender;
  final String? civilStatus;
  final String? email;
  final String? phone;
  final String? zipCode;
  final String? socialMediaType;
  final String? socialMediaDetail;
  final String? otherPhone;
  final String? presentAddress;
  final String? permanentAddress;
  final String? dateHired;
  final String? religion;
  final String? height;
  final String? weight;
  final String? employeeType;
  final String? schedule;
  final String? dayOffDay;
  final String? payrollClass;
  final String? bankType;
  final String? companyName;
  final String? departmentName;
  final String? storeName;
  final String? positionName;
  final String? tin;
  final String? sss;
  final String? pagibig;
  final String? philhealth;
  final String? accountNo;
  final String? emergencyContact;
  final String? emergencyContactNo;
  final String? elementarySchool;
  final String? elementaryYear;
  final String? secondarySchool;
  final String? secondaryYear;
  final String? collegeSchool;
  final String? collegeYear;
  final String? collegeCourse;
  final String? yearGraduated;
  final String? fatherName;
  final String? fatherOccupation;
  final String? motherMaidenName;
  final String? motherOccupation;
  final String? numberOfSiblings;
  final String? birthOrder;
  final String? spouseName;
  final String? spouseOccupation;
  final String? spouseContact;
  final String? childrenNames;
  final String? childrenCount;
}

class CompanyPreview {
  const CompanyPreview({
    required this.id,
    required this.name,
    required this.initials,
    required this.contactNumber,
    required this.address,
    required this.status,
  });

  final String id;
  final String name;
  final String initials;
  final String contactNumber;
  final String address;
  final String status;
}

class DepartmentPreview {
  const DepartmentPreview({
    required this.id,
    required this.name,
    required this.employeeCount,
    required this.created,
    required this.updated,
  });

  final String id;
  final String name;
  final int employeeCount;
  final String created;
  final String updated;
}

class PositionPreview {
  const PositionPreview({
    required this.id,
    required this.name,
    required this.authorityLevel,
    required this.employeeCount,
    required this.created,
    required this.updated,
  });

  final String id;
  final String name;
  final int authorityLevel;
  final int employeeCount;
  final String created;
  final String updated;
}

class DepartmentPositionCatalogPreview {
  const DepartmentPositionCatalogPreview({
    required this.departmentId,
    required this.departmentName,
    required this.positionId,
    required this.positionName,
    required this.authorityLevel,
    required this.employeeCount,
  });

  final String departmentId;
  final String departmentName;
  final String? positionId;
  final String? positionName;
  final int? authorityLevel;
  final int employeeCount;
}

class AdminPositionCatalogPreview {
  const AdminPositionCatalogPreview({
    required this.positionId,
    required this.positionName,
    required this.employeeCount,
  });

  final String positionId;
  final String positionName;
  final int employeeCount;
}

class RegisteredUserPreview {
  const RegisteredUserPreview({
    required this.userProfileId,
    required this.authUserId,
    required this.username,
    required this.email,
    required this.appRole,
    required this.isActive,
    required this.isBanned,
    required this.employeeId,
    required this.employeeNo,
    required this.fullName,
    required this.photoUrl,
    required this.employmentStatus,
    required this.leaveCreditDays,
    required this.leaveUsedDays,
    required this.leaveRemainingDays,
    required this.registeredAt,
    required this.emailConfirmedAt,
    required this.lastSignInAt,
  });

  final String userProfileId;
  final String authUserId;
  final String username;
  final String email;
  final String appRole;
  final bool isActive;
  final bool isBanned;
  final String? employeeId;
  final String employeeNo;
  final String fullName;
  final String? photoUrl;
  final String employmentStatus;
  final double? leaveCreditDays;
  final double? leaveUsedDays;
  final double? leaveRemainingDays;
  final String registeredAt;
  final String emailConfirmedAt;
  final String lastSignInAt;
}

class StorePreview {
  const StorePreview({
    required this.id,
    required this.name,
    required this.companyName,
    required this.clusterName,
    required this.employeeCount,
    required this.created,
    required this.updated,
  });

  final String id;
  final String name;
  final String companyName;
  final String clusterName;
  final int employeeCount;
  final String created;
  final String updated;
}

class ClusterPreview {
  const ClusterPreview({
    required this.id,
    required this.name,
    required this.companyName,
    required this.storeCount,
    required this.storeNames,
    required this.created,
    required this.updated,
  });

  final String id;
  final String name;
  final String companyName;
  final int storeCount;
  final String storeNames;
  final String created;
  final String updated;
}

class AreaPreview {
  const AreaPreview({
    required this.id,
    required this.name,
    required this.clusterCount,
    required this.storeCount,
    required this.clusterNames,
    required this.created,
    required this.updated,
  });

  final String id;
  final String name;
  final int clusterCount;
  final int storeCount;
  final String clusterNames;
  final String created;
  final String updated;
}

class AuthorityCandidatePreview {
  const AuthorityCandidatePreview({
    required this.employeeId,
    required this.employeeNo,
    required this.fullName,
    required this.positionId,
    required this.positionName,
    required this.positionLevel,
    required this.functionId,
    required this.functionName,
    required this.areaId,
    required this.areaName,
    required this.clusterId,
    required this.clusterName,
    required this.storeId,
    required this.storeName,
    required this.companyName,
    required this.departmentId,
    required this.departmentName,
    required this.currentAuthorityLevel,
  });

  final String employeeId;
  final String employeeNo;
  final String fullName;
  final String positionId;
  final String positionName;
  final int? positionLevel;
  final String functionId;
  final String functionName;
  final String? areaId;
  final String areaName;
  final String? clusterId;
  final String clusterName;
  final String? storeId;
  final String storeName;
  final String companyName;
  final String? departmentId;
  final String departmentName;
  final int? currentAuthorityLevel;
}

class StoreRouteScopePreview {
  const StoreRouteScopePreview({
    required this.departmentId,
    required this.departmentName,
    required this.storeId,
    required this.storeName,
    required this.areaId,
    required this.areaName,
    required this.clusterId,
    required this.clusterName,
    required this.routeApprovers,
  });

  final String? departmentId;
  final String departmentName;
  final String storeId;
  final String storeName;
  final String? areaId;
  final String areaName;
  final String? clusterId;
  final String clusterName;
  final Map<int, List<String>> routeApprovers;
}

class AdminPositionAuthorityPreview {
  const AdminPositionAuthorityPreview({
    required this.positionId,
    required this.positionName,
    required this.authorityLevel,
    required this.employeeCount,
  });

  final String positionId;
  final String positionName;
  final int? authorityLevel;
  final int employeeCount;

  AdminPositionAuthorityPreview copyWith({int? authorityLevel}) {
    return AdminPositionAuthorityPreview(
      positionId: positionId,
      positionName: positionName,
      authorityLevel: authorityLevel ?? this.authorityLevel,
      employeeCount: employeeCount,
    );
  }
}

class DepartmentLadderPreview {
  const DepartmentLadderPreview({
    required this.departmentId,
    required this.departmentName,
    required this.routeLevels,
    required this.routeRoles,
  });

  final String departmentId;
  final String departmentName;
  final List<int> routeLevels;
  final Map<int, DepartmentRouteRole> routeRoles;
}

class DepartmentRouteRole {
  const DepartmentRouteRole({
    required this.positionId,
    required this.positionName,
  });

  final String positionId;
  final String positionName;
}

class DepartmentLadderUpdate {
  const DepartmentLadderUpdate({required this.levels, required this.roles});

  final List<int> levels;
  final Map<int, String> roles;
}

enum AdminRequestCategory { esarf, leave, perk }

class AdminRequestItem {
  const AdminRequestItem({
    required this.requestId,
    required this.requestTypeCode,
    required this.requestTypeName,
    required this.status,
    required this.submittedAt,
    required this.finalApprovedAt,
    required this.rejectedAt,
    required this.rejectedReason,
    required this.employeeId,
    required this.employeeNo,
    required this.employeeName,
    required this.employeePhoto,
    required this.departmentName,
    required this.positionName,
    required this.companyName,
    required this.storeName,
    required this.dateFrom,
    required this.dateTo,
    required this.timeFrom,
    required this.timeTo,
    required this.timeSchedule,
    required this.dayOff,
    required this.payrollClass,
    required this.transactionType,
    required this.totalHours,
    required this.leaveType,
    required this.leaveCategory,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.paidDays,
    required this.unpaidDays,
    required this.reason,
    required this.perkApprovalCode,
    required this.perkAmount,
    required this.perkDiscountAmount,
    required this.perkFinalAmount,
    required this.perkBenefit,
    required this.perkProductName,
    required this.perkQuantity,
    required this.approvalSummary,
  });

  final String requestId;
  final String requestTypeCode;
  final String requestTypeName;
  final String status;
  final String? submittedAt;
  final String? finalApprovedAt;
  final String? rejectedAt;
  final String? rejectedReason;
  final String? employeeId;
  final String? employeeNo;
  final String? employeeName;
  final String? employeePhoto;
  final String? departmentName;
  final String? positionName;
  final String? companyName;
  final String? storeName;
  final String? dateFrom;
  final String? dateTo;
  final String? timeFrom;
  final String? timeTo;
  final String? timeSchedule;
  final String? dayOff;
  final String? payrollClass;
  final String? transactionType;
  final double? totalHours;
  final String? leaveType;
  final String? leaveCategory;
  final String? startDate;
  final String? endDate;
  final double? totalDays;
  final double? paidDays;
  final double? unpaidDays;
  final String? reason;
  final String? perkApprovalCode;
  final double? perkAmount;
  final double? perkDiscountAmount;
  final double? perkFinalAmount;
  final String? perkBenefit;
  final String? perkProductName;
  final int? perkQuantity;
  final List<Map<String, dynamic>> approvalSummary;

  AdminRequestCategory get category {
    final code = requestTypeCode.toLowerCase();
    if (code == 'discount' || code == 'charge') {
      return AdminRequestCategory.perk;
    }
    if (code.contains('leave') ||
        code.contains('vl') ||
        code.contains('sl') ||
        code.contains('sil') ||
        code.contains('bl') ||
        code.contains('spl') ||
        code.contains('pl') ||
        code.contains('ml')) {
      return AdminRequestCategory.leave;
    }
    return AdminRequestCategory.esarf;
  }

  /// Comma-separated list of approver names extracted from [approvalSummary].
  String get approverNames {
    if (approvalSummary.isEmpty) return '—';
    final names = approvalSummary
        .map(
          (entry) =>
              (entry['approver_name'] ?? entry['name'] ?? '').toString().trim(),
        )
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return '—';
    return names.join(', ');
  }

  /// Formatted approval summary: Level → Name → Status.
  String get approverDetail {
    if (approvalSummary.isEmpty) return 'No approvals recorded.';
    return approvalSummary
        .map((entry) {
          final level = entry['level']?.toString() ?? '?';
          final name = (entry['approver_name'] ?? entry['name'] ?? 'Unknown')
              .toString()
              .trim();
          final status = (entry['status'] ?? 'pending').toString().trim();
          return 'L$level: $name ($status)';
        })
        .join('\n');
  }

  String get statusLabel {
    final s = status.toLowerCase();
    if (s == 'pending') return 'Pending';
    if (s == 'approved') return 'Approved';
    if (s == 'rejected') return 'Rejected';
    if (s == 'cancelled') return 'Cancelled';
    if (s == 'needs_admin_review') return 'Needs Review';
    return status;
  }

  factory AdminRequestItem.fromRow(Map<String, dynamic> row) {
    final approvalRaw = row['approval_summary'];
    List<Map<String, dynamic>> approvalList = const [];
    if (approvalRaw is List) {
      approvalList = approvalRaw.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
    }

    return AdminRequestItem(
      requestId: row['request_id']?.toString() ?? '',
      requestTypeCode: row['request_type_code']?.toString() ?? '',
      requestTypeName: row['request_type_name']?.toString() ?? '',
      status: row['status']?.toString() ?? 'pending',
      submittedAt: row['submitted_at']?.toString(),
      finalApprovedAt: row['final_approved_at']?.toString(),
      rejectedAt: row['rejected_at']?.toString(),
      rejectedReason: row['rejected_reason']?.toString(),
      employeeId: row['employee_id']?.toString(),
      employeeNo: row['employee_no']?.toString(),
      employeeName: row['employee_name']?.toString(),
      employeePhoto: row['employee_photo']?.toString(),
      departmentName: row['department_name']?.toString(),
      positionName: row['position_name']?.toString(),
      companyName: row['company_name']?.toString(),
      storeName: row['store_name']?.toString(),
      dateFrom: row['date_from']?.toString(),
      dateTo: row['date_to']?.toString(),
      timeFrom: row['time_from']?.toString(),
      timeTo: row['time_to']?.toString(),
      timeSchedule: row['time_schedule']?.toString(),
      dayOff: row['day_off']?.toString(),
      payrollClass: row['payroll_class']?.toString(),
      transactionType: row['transaction_type']?.toString(),
      totalHours: _parseDouble(row['total_hours']),
      leaveType: row['leave_type']?.toString(),
      leaveCategory: row['leave_category']?.toString(),
      startDate: row['start_date']?.toString(),
      endDate: row['end_date']?.toString(),
      totalDays: _parseDouble(row['total_days']),
      paidDays: _parseDouble(row['paid_days']),
      unpaidDays: _parseDouble(row['unpaid_days']),
      reason: row['reason']?.toString(),
      perkApprovalCode: row['perk_approval_code']?.toString(),
      perkAmount: _parseDouble(row['perk_amount']),
      perkDiscountAmount: _parseDouble(row['perk_discount_amount']),
      perkFinalAmount: _parseDouble(row['perk_final_amount']),
      perkBenefit: row['perk_benefit']?.toString(),
      perkProductName: row['perk_product_name']?.toString(),
      perkQuantity: _parseInt(row['perk_quantity']),
      approvalSummary: approvalList,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
