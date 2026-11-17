import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_desktop/main.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as image_pkg;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RequestPdfService generates valid PDF for ESARF request with entries & proofs', () async {
    // 1x1 transparent PNG as mock image data
    final dummyPngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );

    final mockItem = AdminRequestItem(
      requestId: 'ESARF-2026-001',
      requestTypeCode: 'ot',
      requestTypeName: 'Overtime',
      status: 'approved',
      submittedAt: '2026-10-20T08:00:00Z',
      finalApprovedAt: '2026-10-21T10:00:00Z',
      rejectedAt: null,
      rejectedReason: null,
      employeeId: 'EMP-1001',
      employeeNo: '1001',
      employeeName: 'Juan Dela Cruz',
      employeePhoto: null,
      departmentName: 'Information Technology',
      positionName: 'Senior Software Engineer',
      companyName: 'HYG Corporation',
      storeName: 'Main Office',
      dateFrom: '2026-10-18',
      dateTo: '2026-10-18',
      timeFrom: '17:00',
      timeTo: '21:00',
      timeSchedule: '08:00 - 17:00',
      dayOff: 'Sunday',
      payrollClass: 'Semi-Monthly',
      transactionType: 'Overtime',
      totalHours: 4.0,
      leaveType: null,
      leaveCategory: null,
      leaveCredits: null,
      startDate: null,
      endDate: null,
      totalDays: null,
      paidDays: null,
      unpaidDays: null,
      reason: 'Urgent system deployment and database migration [Proof: https://example.com/proof1.jpg] [ProofTime: 2026-10-18 21:05] [ProofLoc: 14.5995, 120.9842]',
      perkApprovalCode: null,
      perkAmount: null,
      perkDiscountAmount: null,
      perkFinalAmount: null,
      perkBenefit: null,
      perkProductName: null,
      perkQuantity: null,
      approvalSummary: [
        {
          'level': 1,
          'approver_name': 'Maria Santos',
          'approver_position_name': 'Team Lead',
          'status': 'approved',
          'acted_at': '2026-10-20 09:30',
        },
        {
          'level': 2,
          'approver_name': 'Roberto Gomez',
          'approver_position_name': 'Operations Manager',
          'status': 'approved',
          'acted_at': '2026-10-21 10:00',
        },
      ],
      entries: [
        EsarfEntryItem(
          id: 'ENTRY-1',
          requestId: 'ESARF-2026-001',
          dateFrom: '2026-10-18',
          dateTo: '2026-10-18',
          timeFrom: '17:00',
          timeTo: '21:00',
          timeSchedule: '08:00 - 17:00',
          dayOff: 'Sunday',
          transactionType: 'Overtime',
          totalHours: 4.0,
          reason: 'Deployment support',
        ),
      ],
    );

    final pdf = pw.Document();
    final pdfBytes = await RequestPdfService.buildPdfDocument(
      pdf: pdf,
      item: mockItem,
      isEsarf: true,
      logoBytes: null,
      proofs: [
        RequestProofItem(
          proofUrl: 'https://example.com/proof1.jpg',
          proofTime: '2026-10-18 21:05',
          proofLocation: '14.5995, 120.9842',
          proofId: 'PROOF-999',
          proofSource: 'camera',
        ),
      ],
      downloadedImages: {
        'https://example.com/proof1.jpg': dummyPngBytes,
      },
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    // Verify standard PDF header %PDF-
    final headerString = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(headerString, equals('%PDF-'));
  });

  test('RequestPdfService generates valid PDF for Leave request with photo proof', () async {
    final dummyPngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );

    final mockLeaveItem = AdminRequestItem(
      requestId: 'LEAVE-2026-042',
      requestTypeCode: 'sl',
      requestTypeName: 'Sick Leave',
      status: 'validated',
      submittedAt: '2026-10-15T07:30:00Z',
      finalApprovedAt: '2026-10-15T09:00:00Z',
      rejectedAt: null,
      rejectedReason: null,
      employeeId: 'EMP-1002',
      employeeNo: '1002',
      employeeName: 'Ana Clara Reyes',
      employeePhoto: null,
      departmentName: 'Human Resources',
      positionName: 'HR Specialist',
      companyName: 'HYG Retail Corp',
      storeName: 'Branch 05',
      dateFrom: null,
      dateTo: null,
      timeFrom: null,
      timeTo: null,
      timeSchedule: null,
      dayOff: null,
      payrollClass: null,
      transactionType: null,
      totalHours: null,
      leaveType: 'Full Day',
      leaveCategory: 'Sick Leave',
      leaveCredits: 12.0,
      startDate: '2026-10-15',
      endDate: '2026-10-16',
      totalDays: 2.0,
      paidDays: 2.0,
      unpaidDays: 0.0,
      reason: 'Acute gastroenteritis. Medical certificate attached. [Proof: https://example.com/medcert.png]',
      perkApprovalCode: null,
      perkAmount: null,
      perkDiscountAmount: null,
      perkFinalAmount: null,
      perkBenefit: null,
      perkProductName: null,
      perkQuantity: null,
      approvalSummary: [
        {
          'level': 1,
          'approver_name': 'Carlos Rivera',
          'approver_position_name': 'HR Director',
          'status': 'validated',
          'acted_at': '2026-10-15 09:00',
        },
      ],
      entries: const [],
    );

    final pdf = pw.Document();
    final pdfBytes = await RequestPdfService.buildPdfDocument(
      pdf: pdf,
      item: mockLeaveItem,
      isEsarf: false,
      logoBytes: null,
      proofs: [
        RequestProofItem(
          proofUrl: 'https://example.com/medcert.png',
          proofSource: 'gallery',
        ),
      ],
      downloadedImages: {
        'https://example.com/medcert.png': dummyPngBytes,
      },
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    final headerString = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(headerString, equals('%PDF-'));
  });

  test('RequestPdfService resolves company-specific logo for Chawnah Foods Inc.', () async {
    final chawnahLogoBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    final chawnahLogoDataUrl = 'data:image/png;base64,$chawnahLogoBase64';

    final mockCompanies = [
      const CompanyPreview(
        id: 'comp-01',
        name: 'HYG Group',
        initials: 'HYG',
        logoUrl: null,
        contactNumber: '123',
        address: 'HQ',
        status: 'active',
      ),
      CompanyPreview(
        id: 'comp-02',
        name: 'Chawnah Foods INC.',
        initials: 'CFI',
        logoUrl: chawnahLogoDataUrl,
        contactNumber: '456',
        address: 'Cebu City',
        status: 'active',
      ),
    ];

    // 1. Verify fuzzy matching for "Chawnah Foods Inc."
    final matchedCompany = RequestPdfService.findMatchingCompany(
      mockCompanies,
      'Chawnah Foods Inc.',
    );
    expect(matchedCompany, isNotNull);
    expect(matchedCompany!.name, equals('Chawnah Foods INC.'));
    expect(matchedCompany.logoUrl, equals(chawnahLogoDataUrl));

    // 2. Verify resolveCompanyLogo returns the company logo bytes
    final mockItem = AdminRequestItem(
      requestId: 'ESARF-CF-100',
      requestTypeCode: 'ot',
      requestTypeName: 'Overtime',
      status: 'pending',
      submittedAt: '2026-10-25T08:00:00Z',
      finalApprovedAt: null,
      rejectedAt: null,
      rejectedReason: null,
      employeeId: 'EMP-CF-01',
      employeeNo: 'CF001',
      employeeName: 'Chawnah Staff',
      employeePhoto: null,
      departmentName: 'Production',
      positionName: 'Cook',
      companyName: 'Chawnah Foods Inc.',
      storeName: 'Chawnah Branch 1',
      dateFrom: '2026-10-25',
      dateTo: '2026-10-25',
      timeFrom: '08:00',
      timeTo: '17:00',
      timeSchedule: '08:00 - 17:00',
      dayOff: 'Sunday',
      payrollClass: 'Rank and File',
      transactionType: 'Overtime',
      totalHours: 2.0,
      leaveType: null,
      leaveCategory: null,
      leaveCredits: null,
      startDate: null,
      endDate: null,
      totalDays: null,
      paidDays: null,
      unpaidDays: null,
      reason: 'Weekend preparation',
      perkApprovalCode: null,
      perkAmount: null,
      perkDiscountAmount: null,
      perkFinalAmount: null,
      perkBenefit: null,
      perkProductName: null,
      perkQuantity: null,
      approvalSummary: const [],
      entries: const [],
    );

    final logoBytes = await RequestPdfService.resolveCompanyLogo(
      item: mockItem,
      preloadedCompanies: mockCompanies,
    );

    expect(logoBytes, isNotNull);
    expect(logoBytes, equals(base64Decode(chawnahLogoBase64)));

    // 3. Verify PDF builds successfully with company logo
    final pdf = pw.Document();
    final pdfBytes = await RequestPdfService.buildPdfDocument(
      pdf: pdf,
      item: mockItem,
      isEsarf: true,
      logoBytes: logoBytes,
      proofs: const [],
      downloadedImages: const {},
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    final headerString = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(headerString, equals('%PDF-'));
  });

  test('RequestPdfService supports wide company logos with expanded container sizing', () async {
    // Generate valid 100x20 PNG using package:image
    final testImg = image_pkg.Image(width: 100, height: 20);
    image_pkg.fill(testImg, color: image_pkg.ColorRgba8(0, 180, 80, 255));
    final dummyWidePng = Uint8List.fromList(image_pkg.encodePng(testImg));

    final mockCompanies = [
      CompanyPreview(
        id: 'comp-03',
        name: 'Cakes and Occasions Corporation',
        initials: 'COC',
        logoUrl: 'data:image/png;base64,${base64Encode(dummyWidePng)}',
        contactNumber: '789',
        address: 'Mandaue City',
        status: 'active',
      ),
    ];

    final matched = RequestPdfService.findMatchingCompany(
      mockCompanies,
      'Cakes and Occasions Corp.',
    );
    expect(matched, isNotNull);
    expect(matched!.name, equals('Cakes and Occasions Corporation'));

    final mockItem = AdminRequestItem(
      requestId: 'ESARF-COC-200',
      requestTypeCode: 'ot',
      requestTypeName: 'Overtime',
      status: 'approved',
      submittedAt: '2026-10-26T08:00:00Z',
      finalApprovedAt: '2026-10-26T12:00:00Z',
      rejectedAt: null,
      rejectedReason: null,
      employeeId: 'EMP-COC-01',
      employeeNo: 'COC001',
      employeeName: 'Baker Specialist',
      employeePhoto: null,
      departmentName: 'Kitchen',
      positionName: 'Head Baker',
      companyName: 'Cakes and Occasions Corp.',
      storeName: 'Branch 2',
      dateFrom: '2026-10-26',
      dateTo: '2026-10-26',
      timeFrom: '06:00',
      timeTo: '15:00',
      timeSchedule: '06:00 - 15:00',
      dayOff: 'Monday',
      payrollClass: 'Rank and File',
      transactionType: 'Overtime',
      totalHours: 3.0,
      leaveType: null,
      leaveCategory: null,
      leaveCredits: null,
      startDate: null,
      endDate: null,
      totalDays: null,
      paidDays: null,
      unpaidDays: null,
      reason: 'Cake production for weekend rush',
      perkApprovalCode: null,
      perkAmount: null,
      perkDiscountAmount: null,
      perkFinalAmount: null,
      perkBenefit: null,
      perkProductName: null,
      perkQuantity: null,
      approvalSummary: const [],
      entries: const [],
    );

    final logoBytes = await RequestPdfService.resolveCompanyLogo(
      item: mockItem,
      preloadedCompanies: mockCompanies,
    );
    expect(logoBytes, isNotNull);

    final pdf = pw.Document();
    final pdfBytes = await RequestPdfService.buildPdfDocument(
      pdf: pdf,
      item: mockItem,
      isEsarf: true,
      logoBytes: logoBytes,
      proofs: const [],
      downloadedImages: const {},
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    final headerString = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(headerString, equals('%PDF-'));
  });

  test('RequestPdfService matches and resolves Cake Haven Incorporation logo', () async {
    final cakeHavenLogo = image_pkg.Image(width: 80, height: 25);
    image_pkg.fill(cakeHavenLogo, color: image_pkg.ColorRgba8(240, 100, 50, 255));
    final cakeHavenPng = Uint8List.fromList(image_pkg.encodePng(cakeHavenLogo));
    final cakeHavenDataUrl = 'data:image/png;base64,${base64Encode(cakeHavenPng)}';

    final mockCompanies = [
      CompanyPreview(
        id: 'CAKES_HAVEN',
        name: 'Cakes Haven Incorporation',
        initials: 'CAKES_HAVEN',
        logoUrl: cakeHavenDataUrl,
        contactNumber: '09123456789',
        address: 'Cebu',
        status: 'active',
      ),
    ];

    // Verify both "Cake Haven Incorporation" and "Cake Haven" match "Cakes Haven Incorporation"
    final matched1 = RequestPdfService.findMatchingCompany(
      mockCompanies,
      'Cake Haven Incorporation',
    );
    expect(matched1, isNotNull);
    expect(matched1!.id, equals('CAKES_HAVEN'));
    expect(matched1.logoUrl, equals(cakeHavenDataUrl));

    final matched2 = RequestPdfService.findMatchingCompany(
      mockCompanies,
      'Cake Haven',
    );
    expect(matched2, isNotNull);
    expect(matched2!.id, equals('CAKES_HAVEN'));

    final mockItem = AdminRequestItem(
      requestId: 'ESARF-CH-300',
      requestTypeCode: 'ot',
      requestTypeName: 'Overtime',
      status: 'approved',
      submittedAt: '2026-10-27T08:00:00Z',
      finalApprovedAt: null,
      rejectedAt: null,
      rejectedReason: null,
      employeeId: 'EMP-CH-01',
      employeeNo: 'CH001',
      employeeName: 'Cake Haven Staff',
      employeePhoto: null,
      departmentName: 'Bakery',
      positionName: 'Pastry Chef',
      companyName: 'Cake Haven Incorporation',
      storeName: 'Main Store',
      dateFrom: '2026-10-27',
      dateTo: '2026-10-27',
      timeFrom: '08:00',
      timeTo: '17:00',
      timeSchedule: '08:00 - 17:00',
      dayOff: 'Sunday',
      payrollClass: 'Rank and File',
      transactionType: 'Overtime',
      totalHours: 2.0,
      leaveType: null,
      leaveCategory: null,
      leaveCredits: null,
      startDate: null,
      endDate: null,
      totalDays: null,
      paidDays: null,
      unpaidDays: null,
      reason: 'Pastry preparation',
      perkApprovalCode: null,
      perkAmount: null,
      perkDiscountAmount: null,
      perkFinalAmount: null,
      perkBenefit: null,
      perkProductName: null,
      perkQuantity: null,
      approvalSummary: const [],
      entries: const [],
    );

    final logoBytes = await RequestPdfService.resolveCompanyLogo(
      item: mockItem,
      preloadedCompanies: mockCompanies,
    );
    expect(logoBytes, isNotNull);

    final pdf = pw.Document();
    final pdfBytes = await RequestPdfService.buildPdfDocument(
      pdf: pdf,
      item: mockItem,
      isEsarf: true,
      logoBytes: logoBytes,
      proofs: const [],
      downloadedImages: const {},
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
  });
}
