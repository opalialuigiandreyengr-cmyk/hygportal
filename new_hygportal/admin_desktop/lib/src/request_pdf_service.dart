part of '../main.dart';

/// Service responsible for generating and downloading official PDF documents
/// for ESARF (Employee Service Action Request Form) and Leave Requests,
/// including all details, approval audit history, and embedded photo proofs.
class RequestPdfService {
  RequestPdfService._();

  static const String _hygDeepNavy = '#071426';
  static const String _hygGold = '#E2B93B';

  static final Map<String, Uint8List> _companyLogoMemoryCache = {};
  static List<CompanyPreview>? _cachedCompanies;
  static DateTime? _companiesCacheTime;

  /// Loads companies from CompanyDirectoryService with a 5-minute memory cache.
  static Future<List<CompanyPreview>> _getCompanies() async {
    if (_cachedCompanies != null && _companiesCacheTime != null) {
      if (DateTime.now().difference(_companiesCacheTime!).inMinutes < 5) {
        return _cachedCompanies!;
      }
    }
    try {
      final companies = await CompanyDirectoryService.loadCompanies();
      _cachedCompanies = companies;
      _companiesCacheTime = DateTime.now();
      return companies;
    } catch (e) {
      debugPrint('Failed to load companies in RequestPdfService: $e');
      return _cachedCompanies ?? const [];
    }
  }

  /// Finds the company matching targetName or company_id from a list of companies.
  /// Handles exact name match, normalized match without punctuation, and corporate suffix stripping
  /// (e.g. "Chawnah Foods Inc." matches "Chawnah Foods INC.").
  static CompanyPreview? findMatchingCompany(
    List<CompanyPreview> companies,
    String? targetName, {
    Map<String, dynamic>? rawRow,
  }) {
    if (companies.isEmpty) return null;

    // 1. Direct company_id match from rawRow if available
    final rawCompanyId = rawRow?['company_id']?.toString().trim();
    if (rawCompanyId != null && rawCompanyId.isNotEmpty) {
      for (final c in companies) {
        if (c.id.toLowerCase() == rawCompanyId.toLowerCase()) {
          return c;
        }
      }
    }

    if (targetName == null || targetName.trim().isEmpty) return null;
    final cleanTarget = targetName.trim().toLowerCase();

    // 2. Exact match (case-insensitive)
    for (final c in companies) {
      if (c.name.trim().toLowerCase() == cleanTarget) {
        return c;
      }
    }

    // 3. Normalized alphanumeric match (removes punctuation, spaces)
    String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normTarget = normalize(cleanTarget);
    for (final c in companies) {
      if (normalize(c.name) == normTarget && normTarget.isNotEmpty) {
        return c;
      }
    }

    // 4. Normalized match stripping corporate suffixes (inc, corp, corporation, co, etc.)
    String stripSuffix(String s) {
      return s
          .toLowerCase()
          .replaceAll(
            RegExp(r'\b(inc|incorporated|incorporation|corp|corporation|co|company|ltd|limited)\b', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();
    }

    final strippedTarget = stripSuffix(cleanTarget);
    if (strippedTarget.isNotEmpty) {
      for (final c in companies) {
        final strippedComp = stripSuffix(c.name);
        if (strippedComp.isNotEmpty &&
            (strippedComp == strippedTarget ||
                strippedComp.contains(strippedTarget) ||
                strippedTarget.contains(strippedComp))) {
          return c;
        }
      }
    }

    // 5. Token stem matching (handles singular/plural like "Cake Haven" vs "Cakes Haven Incorporation")
    List<String> getStems(String s) {
      return s
          .toLowerCase()
          .replaceAll(
            RegExp(r'\b(inc|incorporated|incorporation|corp|corporation|co|company|ltd|limited)\b', caseSensitive: false),
            '',
          )
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w.endsWith('s') && w.length > 3 ? w.substring(0, w.length - 1) : w)
          .toList();
    }

    final targetStems = getStems(cleanTarget);
    if (targetStems.isNotEmpty) {
      for (final c in companies) {
        final compStems = getStems(c.name);
        if (compStems.isNotEmpty) {
          final targetJoined = targetStems.join('');
          final compJoined = compStems.join('');
          if (targetJoined == compJoined ||
              (targetStems.length >= 2 && compStems.length >= 2 &&
               targetStems.every((st) => compStems.contains(st))) ||
              (compStems.length >= 2 && targetStems.length >= 2 &&
               compStems.every((st) => targetStems.contains(st)))) {
            return c;
          }
        }
      }
    }

    // 6. Code / initials match (e.g. CAKES_HAVEN, CFI, COC)
    for (final c in companies) {
      final init = c.initials.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normCode = c.id.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if ((init.isNotEmpty && init == normTarget) ||
          (normCode.isNotEmpty && normCode == normTarget)) {
        return c;
      }
    }

    return null;
  }

  /// Resolves the company logo bytes for the employee's company.
  /// Looks up the company uploaded logo from the company screen / directory.
  /// Falls back to the default HYG logo if no company logo is uploaded or if download fails.
  static Future<Uint8List?> resolveCompanyLogo({
    required AdminRequestItem item,
    List<CompanyPreview>? preloadedCompanies,
  }) async {
    try {
      final companies = preloadedCompanies ?? await _getCompanies();
      final matched = findMatchingCompany(companies, item.companyName, rawRow: item.rawRow);

      if (matched != null) {
        final cacheKey = matched.id.isNotEmpty ? matched.id : matched.name.toLowerCase();
        if (_companyLogoMemoryCache.containsKey(cacheKey)) {
          final cached = _companyLogoMemoryCache[cacheKey];
          if (cached != null && cached.isNotEmpty) {
            return cached;
          }
        }

        final logoUrl = matched.logoUrl?.trim();
        if (logoUrl != null && logoUrl.isNotEmpty) {
          final bytes = await _downloadImageBytes(logoUrl);
          if (bytes != null && bytes.isNotEmpty) {
            final trimmed = _trimAndNormalizeLogoBytes(bytes);
            _companyLogoMemoryCache[cacheKey] = trimmed;
            return trimmed;
          }
        }
      }
    } catch (e) {
      debugPrint('Error resolving company logo for ${item.companyName}: $e');
    }

    // Fallback: Default HYG Logo asset
    try {
      final byteData = await rootBundle.load('assets/hyg_logo.png');
      final bytes = byteData.buffer.asUint8List();
      return _trimAndNormalizeLogoBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Sanitizes text for safe filename usage.
  static String _sanitizeFileName(String text) {
    return text.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();
  }

  /// Converts Google Drive or other indirect URLs to direct previewable image URLs.
  static String _getDirectProofImageUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('data:image/')) return trimmed;

    final lh3Match = RegExp(r'googleusercontent\.com/d/([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
    if (lh3Match != null) return 'https://lh3.googleusercontent.com/d/${lh3Match.group(1)}=w1200';

    final driveMatch1 = RegExp(r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
    if (driveMatch1 != null) return 'https://lh3.googleusercontent.com/d/${driveMatch1.group(1)}=w1200';

    final driveMatch2 = RegExp(r'drive\.google\.com/open\?id=([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
    if (driveMatch2 != null) return 'https://lh3.googleusercontent.com/d/${driveMatch2.group(1)}=w1200';

    final driveMatch3 = RegExp(r'drive\.google\.com/uc\?(?:export=view&)?id=([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
    if (driveMatch3 != null) return 'https://lh3.googleusercontent.com/d/${driveMatch3.group(1)}=w1200';

    return trimmed;
  }

  /// Downloads and normalizes image bytes for PDF embedding.
  /// Handles Base64 data URLs, remote HTTP/HTTPS images, and converts non-JPEG/PNG formats to JPEG.
  static Future<Uint8List?> _downloadImageBytes(String rawUrl) async {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) return null;

    try {
      // 1. Base64 data URL
      if (cleanUrl.startsWith('data:image/')) {
        final commaIdx = cleanUrl.indexOf(',');
        final b64 = commaIdx != -1 ? cleanUrl.substring(commaIdx + 1) : cleanUrl;
        final bytes = base64Decode(b64);
        return _normalizeImageBytes(bytes);
      }

      // 2. HTTP/HTTPS URL
      final directUrl = _getDirectProofImageUrl(cleanUrl);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      client.userAgent = 'HYGPortalAdminDesktop/1.0';

      final request = await client.getUrl(Uri.parse(directUrl)).timeout(const Duration(seconds: 12));
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final bytes = bytesBuilder.takeBytes();
        if (bytes.isNotEmpty) {
          return _normalizeImageBytes(bytes);
        }
      }
    } catch (e) {
      debugPrint('Failed to download image from $rawUrl: $e');
    }
    return null;
  }

  /// Normalizes image bytes into JPEG format if not already standard PNG or JPEG,
  /// ensuring complete compatibility with the PDF renderer.
  static Uint8List? _normalizeImageBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final isPng = bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final isJpg = bytes.length > 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8;

      if (isPng || isJpg) {
        return bytes;
      }

      // Try decoding using image_pkg (e.g. WebP, GIF, BMP)
      final decoded = image_pkg.decodeImage(bytes);
      if (decoded != null) {
        return Uint8List.fromList(image_pkg.encodeJpg(decoded, quality: 85));
      }
    } catch (e) {
      debugPrint('Error normalizing image bytes: $e');
    }
    return bytes;
  }

  /// Trims transparent or blank outer borders from company logo image bytes so the logo
  /// fills its visual boundaries without empty whitespace padding.
  static Uint8List _trimAndNormalizeLogoBytes(Uint8List bytes) {
    if (bytes.isEmpty) return bytes;
    try {
      final img = image_pkg.decodeImage(bytes);
      if (img == null) return bytes;

      final hasAlpha = img.hasAlpha;
      int minX = img.width;
      int minY = img.height;
      int maxX = -1;
      int maxY = -1;

      for (int y = 0; y < img.height; y++) {
        for (int x = 0; x < img.width; x++) {
          final p = img.getPixel(x, y);
          final bool isContent;
          if (hasAlpha) {
            // For images with an alpha channel, non-transparent pixels are content
            isContent = p.a > 15;
          } else {
            // For opaque images with solid backgrounds, non-near-white pixels are content
            isContent = p.r < 245 || p.g < 245 || p.b < 245;
          }

          if (isContent) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      // If non-empty content was found, crop outer padding with a 2px buffer
      if (maxX >= minX && maxY >= minY) {
        final cropX = (minX - 2).clamp(0, img.width - 1);
        final cropY = (minY - 2).clamp(0, img.height - 1);
        final cropMaxX = (maxX + 2).clamp(0, img.width - 1);
        final cropMaxY = (maxY + 2).clamp(0, img.height - 1);
        final cropW = cropMaxX - cropX + 1;
        final cropH = cropMaxY - cropY + 1;

        // Only crop if at least 4% of empty margin exists on either axis
        if (cropW < img.width * 0.96 || cropH < img.height * 0.96) {
          final cropped = image_pkg.copyCrop(
            img,
            x: cropX,
            y: cropY,
            width: cropW,
            height: cropH,
          );
          return Uint8List.fromList(image_pkg.encodePng(cropped));
        }
      }
    } catch (e) {
      debugPrint('Error trimming logo bytes: $e');
    }
    return bytes;
  }

  /// Main entry point: Generates and saves a PDF document for an ESARF or Leave request.
  static Future<void> downloadRequestPdf({
    required BuildContext context,
    required AdminRequestItem item,
  }) async {
    final isEsarf = item.category == AdminRequestCategory.esarf;
    final isLeave = item.category == AdminRequestCategory.leave;
    if (!isEsarf && !isLeave) return;

    final messenger = ScaffoldMessenger.of(context);

    // Show non-blocking progress dialog
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: HygColors.goldStrong),
                ),
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preparing ${isEsarf ? "ESARF" : "Leave"} Request PDF...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Gathering request details & photo proofs...',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      // 1. Gather all photo proofs
      final proofsToProcess = <RequestProofItem>[];
      if (isEsarf && item.entries.isNotEmpty) {
        for (final entry in item.entries) {
          for (final p in entry.proofs) {
            if (p.proofUrl.trim().isNotEmpty &&
                !proofsToProcess.any((x) => x.proofUrl.trim() == p.proofUrl.trim())) {
              proofsToProcess.add(p);
            }
          }
        }
      }

      for (final p in item.proofs) {
        if (p.proofUrl.trim().isNotEmpty &&
            !proofsToProcess.any((x) => x.proofUrl.trim() == p.proofUrl.trim())) {
          proofsToProcess.add(p);
        }
      }

      if (proofsToProcess.isEmpty && item.proofUrl != null && item.proofUrl!.trim().isNotEmpty) {
        proofsToProcess.add(RequestProofItem(
          proofUrl: item.proofUrl!.trim(),
          proofTime: item.isGallery ? null : item.proofTime,
          proofLocation: item.isGallery ? null : item.proofLocation,
          proofId: item.isGallery ? null : item.proofId,
          proofSource: item.proofSource,
        ));
      }

      // 2. Download proofs and resolve company logo in parallel
      final Map<String, Uint8List> downloadedImages = {};
      final downloadFutures = proofsToProcess.map((proof) async {
        final url = proof.proofUrl.trim();
        if (url.isNotEmpty && !downloadedImages.containsKey(url)) {
          final bytes = await _downloadImageBytes(url);
          if (bytes != null && bytes.isNotEmpty) {
            downloadedImages[url] = bytes;
          }
        }
      }).toList();

      final companyLogoFuture = resolveCompanyLogo(item: item);
      await Future.wait([...downloadFutures, companyLogoFuture]);
      final logoBytes = await companyLogoFuture;

      // 4. Load fonts
      pw.Font? regularFont;
      pw.Font? boldFont;
      try {
        final regData = await rootBundle.load('assets/fonts/Inter.ttf');
        regularFont = pw.Font.ttf(regData);
        final bData = await rootBundle.load('assets/fonts/Poppins-Bold.ttf');
        boldFont = pw.Font.ttf(bData);
      } catch (_) {}

      // 5. Generate PDF Document
      final pdf = pw.Document(
        theme: regularFont != null
            ? pw.ThemeData.withFont(base: regularFont, bold: boldFont ?? regularFont)
            : null,
      );

      final pdfBytes = await buildPdfDocument(
        pdf: pdf,
        item: item,
        isEsarf: isEsarf,
        logoBytes: logoBytes,
        proofs: proofsToProcess,
        downloadedImages: downloadedImages,
      );

      // Dismiss loading dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      // 6. Save via FilePicker
      final empNamePart = _sanitizeFileName(item.employeeName ?? 'Employee');
      final reqIdPart = _sanitizeFileName(item.requestId);
      final defaultFileName = '${isEsarf ? "ESARF" : "Leave"}_Request_${empNamePart}_$reqIdPart.pdf';

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Save Request PDF',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: pdfBytes,
      );

      if (savePath == null) return; // User cancelled

      final file = File(savePath);
      if (!await file.exists()) {
        await file.writeAsBytes(pdfBytes);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Request PDF saved: ${p.basename(savePath)}'),
          backgroundColor: const Color(0xFF166534),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Open PDF',
            textColor: Colors.white,
            onPressed: () {
              if (Platform.isWindows) {
                Process.run('cmd', ['/c', 'start', '', savePath]);
              } else if (Platform.isMacOS) {
                Process.run('open', [savePath]);
              } else {
                Process.run('xdg-open', [savePath]);
              }
            },
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('Error generating request PDF: $e\n$stack');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: const Color(0xFFB91C1C),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Builds the multi-page PDF structure.
  static Future<Uint8List> buildPdfDocument({
    required pw.Document pdf,
    required AdminRequestItem item,
    required bool isEsarf,
    required Uint8List? logoBytes,
    required List<RequestProofItem> proofs,
    required Map<String, Uint8List> downloadedImages,
  }) async {
    final navyColor = pdf_core.PdfColor.fromHex(_hygDeepNavy);
    final goldColor = pdf_core.PdfColor.fromHex(_hygGold);
    final borderColor = pdf_core.PdfColor.fromHex('#CBD5E1');
    final tableHeaderBg = pdf_core.PdfColor.fromHex('#F1F5F9');
    final lightBg = pdf_core.PdfColor.fromHex('#F8FAFC');
    final mutedText = pdf_core.PdfColor.fromHex('#64748B');
    final darkText = pdf_core.PdfColor.fromHex('#0F172A');

    // Status colors
    final status = item.status.trim().toLowerCase();
    final isAutoBirthday = item.isAutoApprovedBirthdayGrant;
    final isApproved = status == 'approved' || status == 'validated' || (isAutoBirthday && status != 'rejected' && status != 'cancelled');
    final isRejected = status == 'rejected';
    final isCancelled = status == 'cancelled';

    final statusBgColor = isApproved
        ? pdf_core.PdfColor.fromHex('#DCFCE7')
        : (isRejected || isCancelled
            ? pdf_core.PdfColor.fromHex('#FEE2E2')
            : pdf_core.PdfColor.fromHex('#DBEAFE'));
    final statusTextColor = isApproved
        ? pdf_core.PdfColor.fromHex('#166534')
        : (isRejected || isCancelled
            ? pdf_core.PdfColor.fromHex('#991B1B')
            : pdf_core.PdfColor.fromHex('#1E40AF'));

    final statusText = isAutoBirthday
        ? 'APPROVED (SYSTEM BIRTHDAY GRANT)'
        : item.statusLabel.toUpperCase();

    // Entries for ESARF
    final isLeave = !isEsarf;
    final esarfEntries = isEsarf
        ? (item.entries.isNotEmpty
            ? item.entries
            : EsarfEntryItem.parseEsarfEntriesFromReason(item.rawRow))
        : <EsarfEntryItem>[];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pdf_core.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: borderColor, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HYG PORTAL | ${isEsarf ? "ESARF REQUEST" : "LEAVE REQUEST"} | REF #${item.requestId}',
                  style: pw.TextStyle(fontSize: 8, color: mutedText, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Employee: ${item.employeeName ?? "-"} (${item.employeeNo ?? "N/A"})',
                  style: pw.TextStyle(fontSize: 8, color: mutedText),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: borderColor, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HYG Online Portal | Official HR Record',
                  style: pw.TextStyle(fontSize: 8, color: mutedText),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: mutedText, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Printed: ${DateTime.now().toLocal().toString().substring(0, 16)}',
                  style: pw.TextStyle(fontSize: 8, color: mutedText),
                ),
              ],
            ),
          );
        },
        build: (context) => [
          // ── 1. Top Header & Corporate Identity ──────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logoBytes != null)
                pw.Container(
                  width: 260,
                  height: 52,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(
                    pw.MemoryImage(_trimAndNormalizeLogoBytes(logoBytes)),
                    fit: pw.BoxFit.contain,
                  ),
                )
              else
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      (item.companyName != null && item.companyName!.trim().isNotEmpty)
                          ? item.companyName!.trim().toUpperCase()
                          : 'HYG GROUP OF COMPANIES',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: navyColor,
                      ),
                    ),
                    pw.Text(
                      'HYG ONLINE HUMAN RESOURCE PORTAL',
                      style: pw.TextStyle(fontSize: 8, color: mutedText),
                    ),
                  ],
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    isEsarf
                        ? 'EMPLOYEE SERVICE ACTION REQUEST'
                        : 'APPLICATION FOR LEAVE OF ABSENCE',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: lightBg,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(color: borderColor, width: 0.8),
                    ),
                    child: pw.Text(
                      'REF NO: ${item.requestId}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: darkText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Double accent bar
          pw.SizedBox(height: 10),
          pw.Container(height: 3, color: navyColor),
          pw.Container(height: 1.5, color: goldColor),
          pw.SizedBox(height: 12),

          // ── 2. Request Status & Filing Banner ───────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              color: statusBgColor,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(
                color: pdf_core.PdfColor(statusTextColor.red, statusTextColor.green, statusTextColor.blue, 0.4),
                width: 1,
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      'STATUS: ',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: statusTextColor,
                      ),
                    ),
                    pw.Text(
                      statusText,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: statusTextColor,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Submitted: ${_formatDateString(item.submittedAt, includeTime: true) ?? "-"}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: statusTextColor,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── 3. Section: Employee Profile ───────────────────────────
          _buildSectionHeader('EMPLOYEE INFORMATION', navyColor),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderColor, width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
              color: lightBg,
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Employee Name:', item.employeeName ?? '-', isBold: true),
                      pw.SizedBox(height: 4),
                      _buildInfoRow('Employee No:', item.employeeNo ?? item.employeeId ?? '-'),
                      pw.SizedBox(height: 4),
                      _buildInfoRow('Position / Title:', item.positionName ?? '-'),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Department:', item.departmentName ?? '-'),
                      pw.SizedBox(height: 4),
                      _buildInfoRow('Store / Branch:', item.storeName ?? '-'),
                      pw.SizedBox(height: 4),
                      _buildInfoRow('Company:', item.companyName ?? 'HYG Group of Companies'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── 4. Section: Particulars of Request ─────────────────────
          if (isEsarf) ...[
            _buildSectionHeader('SERVICE ACTION PARTICULARS (ESARF)', navyColor),
            pw.SizedBox(height: 6),
            if (esarfEntries.isNotEmpty) ...[
              pw.Table(
                border: pw.TableBorder.all(color: borderColor, width: 0.6),
                columnWidths: {
                  0: const pw.FixedColumnWidth(22), // #
                  1: const pw.FlexColumnWidth(2.2), // Type
                  2: const pw.FlexColumnWidth(2.3), // Dates
                  3: const pw.FlexColumnWidth(2.3), // Time Bound
                  4: const pw.FlexColumnWidth(2.0), // Schedule
                  5: const pw.FixedColumnWidth(38), // Hours
                  6: const pw.FlexColumnWidth(3.0), // Remarks
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: tableHeaderBg),
                    children: [
                      _buildTableCell('#', isHeader: true, align: pw.TextAlign.center),
                      _buildTableCell('Type', isHeader: true),
                      _buildTableCell('Date(s)', isHeader: true),
                      _buildTableCell('Time Bound', isHeader: true),
                      _buildTableCell('Schedule/Day Off', isHeader: true),
                      _buildTableCell('Hours', isHeader: true, align: pw.TextAlign.right),
                      _buildTableCell('Reason / Remarks', isHeader: true),
                    ],
                  ),
                  for (int i = 0; i < esarfEntries.length; i++) ...[
                    _buildEsarfEntryRow(i + 1, esarfEntries[i]),
                  ],
                ],
              ),
              pw.SizedBox(height: 6),
              // ESARF Summary Totals
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: borderColor, width: 0.6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Entries: ${esarfEntries.length}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkText),
                    ),
                    pw.Text(
                      'Overall Total Hours: ${_formatHours(item.totalHours ?? _sumEntryHours(esarfEntries))}',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: navyColor),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Single ESARF Entry
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderColor, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: lightBg,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildInfoRow('Transaction Type:', item.transactionType ?? item.requestTypeName, isBold: true),
                        ),
                        pw.Expanded(
                          child: _buildInfoRow('Total Hours:', _formatHours(item.totalHours), isBold: true),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildInfoRow('Coverage Dates:', _formatDateRange(item.dateFrom, item.dateTo)),
                        ),
                        pw.Expanded(
                          child: _buildInfoRow('Time Bound:', _formatTimeRange(item.timeFrom, item.timeTo)),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildInfoRow('Time Schedule:', item.timeSchedule ?? '-'),
                        ),
                        pw.Expanded(
                          child: _buildInfoRow('Day Off / Payroll:', '${item.dayOff ?? "-"} / ${item.payrollClass ?? "-"}'),
                        ),
                      ],
                    ),
                    if (item.cleanReasonText.isNotEmpty || (item.reason != null && item.reason!.isNotEmpty)) ...[
                      pw.SizedBox(height: 6),
                      pw.Divider(color: borderColor, thickness: 0.5),
                      pw.SizedBox(height: 4),
                      _buildInfoRow('Reason / Purpose:', item.cleanReasonText.isNotEmpty ? item.cleanReasonText : (item.reason ?? '-')),
                    ],
                  ],
                ),
              ),
            ],
          ] else if (isLeave) ...[
            _buildSectionHeader('LEAVE APPLICATION PARTICULARS', navyColor),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
                color: lightBg,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildInfoRow('Leave Category:', item.leaveCategory ?? item.requestTypeName, isBold: true),
                      ),
                      pw.Expanded(
                        child: _buildInfoRow('Leave Type:', item.leaveType ?? 'Full Day', isBold: true),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildInfoRow('Start Date:', item.startDate ?? item.dateFrom ?? '-'),
                      ),
                      pw.Expanded(
                        child: _buildInfoRow('End Date:', item.endDate ?? item.dateTo ?? '-'),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildInfoRow(
                          'Total Duration:',
                          '${_formatDaysNum(item.totalDays)} (${_formatDaysNum(item.paidDays)} Paid, ${_formatDaysNum(item.unpaidDays)} Unpaid)',
                          isBold: true,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildInfoRow('Leave Credits:', item.leaveCredits != null ? '${_formatDaysNum(item.leaveCredits)} available' : 'N/A'),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: borderColor, thickness: 0.5),
                  pw.SizedBox(height: 4),
                  _buildInfoRow(
                    'Reason for Leave:',
                    item.cleanReasonText.isNotEmpty ? item.cleanReasonText : (item.reason ?? item.remarks ?? '-'),
                  ),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 14),

          // ── 5. Section: Approval Route & Audit History ──────────────
          _buildSectionHeader('APPROVAL ROUTE & AUDIT TRAIL', navyColor),
          pw.SizedBox(height: 6),
          if (isAutoBirthday) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: pdf_core.PdfColor.fromHex('#F0FDF4'),
                border: pw.Border.all(color: pdf_core.PdfColor.fromHex('#BBF7D0'), width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    '[AUTO-APPROVED] Birthday Leave Grant:',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: pdf_core.PdfColor.fromHex('#166534')),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Text(
                      'Granted automatically by HYG Portal System for the employee\'s birthday month.',
                      style: pw.TextStyle(fontSize: 9, color: pdf_core.PdfColor.fromHex('#166534')),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (item.approvalSummary.isNotEmpty) ...[
            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.6),
              columnWidths: {
                0: const pw.FixedColumnWidth(45), // Level
                1: const pw.FlexColumnWidth(3),   // Approver Name
                2: const pw.FlexColumnWidth(3),   // Position
                3: const pw.FixedColumnWidth(65), // Status
                4: const pw.FlexColumnWidth(2.5), // Timestamp
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: tableHeaderBg),
                  children: [
                    _buildTableCell('Level', isHeader: true, align: pw.TextAlign.center),
                    _buildTableCell('Designated Approver', isHeader: true),
                    _buildTableCell('Position / Role', isHeader: true),
                    _buildTableCell('Status', isHeader: true, align: pw.TextAlign.center),
                    _buildTableCell('Timestamp / Acted At', isHeader: true),
                  ],
                ),
                for (final step in item.approvalSummary) ...[
                  _buildApprovalStepRow(step, item),
                ],
              ],
            ),
          ] else ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: lightBg,
                border: pw.Border.all(color: borderColor, width: 0.6),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'No approvals recorded yet or pending approval assignment.',
                style: pw.TextStyle(fontSize: 8.5, color: mutedText, fontStyle: pw.FontStyle.italic),
              ),
            ),
          ],
          pw.SizedBox(height: 14),

          // ── 6. Section: Attached Photo Proofs ───────────────────────
          _buildSectionHeader(
            'ATTACHED PHOTO PROOF(S)${proofs.isNotEmpty ? " (${proofs.length})" : ""}',
            navyColor,
          ),
          pw.SizedBox(height: 6),
          if (proofs.isEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: lightBg,
                border: pw.Border.all(color: borderColor, width: 0.6),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'No photo proofs were attached for this request.',
                style: pw.TextStyle(fontSize: 8.5, color: mutedText, fontStyle: pw.FontStyle.italic),
              ),
            ),
          ] else ...[
            for (int pIdx = 0; pIdx < proofs.length; pIdx++) ...[
              _buildProofCard(
                proofIndex: pIdx + 1,
                totalProofs: proofs.length,
                proof: proofs[pIdx],
                imageBytes: downloadedImages[proofs[pIdx].proofUrl.trim()],
                borderColor: borderColor,
                lightBg: lightBg,
                mutedText: mutedText,
                darkText: darkText,
                navyColor: navyColor,
              ),
              if (pIdx < proofs.length - 1) pw.SizedBox(height: 10),
            ],
          ],
          pw.SizedBox(height: 20),

          // ── 7. Confidentiality Notice ───────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderColor, width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
              color: lightBg,
            ),
            child: pw.Text(
              'CONFIDENTIALITY NOTICE: This document contains confidential information intended solely for the use of ${(item.companyName != null && item.companyName!.trim().isNotEmpty) ? item.companyName!.trim() : "HYG Group of Companies"}. Unauthorized distribution or copying is strictly prohibited. System-generated and validated electronically via HYG Online HR Portal.',
              style: pw.TextStyle(fontSize: 7, color: mutedText, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Helper Widgets for PDF Building ───────────────────────────────

  static pw.Widget _buildSectionHeader(String title, pdf_core.PdfColor color) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3.5,
          height: 12,
          color: color,
        ),
        pw.SizedBox(width: 5),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: pdf_core.PdfColor.fromHex('#475569'),
            ),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: pdf_core.PdfColor.fromHex('#0F172A'),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.5 : 7.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader
              ? pdf_core.PdfColor.fromHex('#1E293B')
              : pdf_core.PdfColor.fromHex('#0F172A'),
        ),
      ),
    );
  }

  static pw.TableRow _buildEsarfEntryRow(int index, EsarfEntryItem entry) {
    final dateRange = _formatDateRange(entry.dateFrom, entry.dateTo);
    final timeBound = _formatTimeRange(entry.timeFrom, entry.timeTo);
    final schedule = [
      if (entry.timeSchedule != null && entry.timeSchedule!.trim().isNotEmpty) entry.timeSchedule!.trim(),
      if (entry.dayOff != null && entry.dayOff!.trim().isNotEmpty) 'Off: ${entry.dayOff!.trim()}',
    ].join('\n');
    final reason = entry.cleanReasonText.isNotEmpty
        ? entry.cleanReasonText
        : (entry.reason ?? '-');

    return pw.TableRow(
      children: [
        _buildTableCell('$index', align: pw.TextAlign.center),
        _buildTableCell(entry.transactionType ?? '-'),
        _buildTableCell(dateRange.isNotEmpty ? dateRange : '-'),
        _buildTableCell(timeBound.isNotEmpty ? timeBound : '-'),
        _buildTableCell(schedule.isNotEmpty ? schedule : '-'),
        _buildTableCell(_formatHours(entry.totalHours), align: pw.TextAlign.right),
        _buildTableCell(reason),
      ],
    );
  }

  static pw.TableRow _buildApprovalStepRow(Map<String, dynamic> step, AdminRequestItem item) {
    final rawLevel = step['position_level'] ??
        step['approver_level'] ??
        step['level'] ??
        step['required_level'] ??
        step['route_level'] ??
        '-';
    final levelStr = rawLevel.toString().startsWith('L') ? rawLevel.toString() : 'L$rawLevel';
    final name = (step['approver_name'] ?? step['name'] ?? '-').toString().trim();
    final pos = (step['approver_position_name'] ?? step['position_name'] ?? 'Approver').toString().trim();
    final status = (step['status'] ?? 'pending').toString().trim().toUpperCase();
    final timestamp = (step['acted_at'] ?? step['timestamp'] ?? item.finalApprovedAt ?? '-').toString().trim();

    return pw.TableRow(
      children: [
        _buildTableCell(levelStr, align: pw.TextAlign.center),
        _buildTableCell(name),
        _buildTableCell(pos),
        _buildTableCell(status, align: pw.TextAlign.center),
        _buildTableCell(timestamp.isNotEmpty ? timestamp : '-'),
      ],
    );
  }

  static pw.Widget _buildProofCard({
    required int proofIndex,
    required int totalProofs,
    required RequestProofItem proof,
    required Uint8List? imageBytes,
    required pdf_core.PdfColor borderColor,
    required pdf_core.PdfColor lightBg,
    required pdf_core.PdfColor mutedText,
    required pdf_core.PdfColor darkText,
    required pdf_core.PdfColor navyColor,
  }) {
    final isGallery = proof.isGallery;
    final sourceLabel = isGallery ? 'Uploaded from Gallery' : (proof.proofSource ?? 'Camera Capture');

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
        color: lightBg,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Proof Title Bar
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: pdf_core.PdfColor.fromHex('#F1F5F9'),
              border: pw.Border(bottom: pw.BorderSide(color: borderColor, width: 0.6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Photo Proof #$proofIndex of $totalProofs',
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: navyColor),
                ),
                pw.Text(
                  'Source: $sourceLabel',
                  style: pw.TextStyle(fontSize: 7.5, color: mutedText, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),

          // Proof Image Container
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: imageBytes != null && imageBytes.isNotEmpty
                ? pw.Center(
                    child: pw.ConstrainedBox(
                      constraints: const pw.BoxConstraints(
                        maxHeight: 260,
                        maxWidth: 440,
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(
                          pw.MemoryImage(imageBytes),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                  )
                : pw.Container(
                    height: 90,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: pdf_core.PdfColor.fromHex('#F8FAFC'),
                      border: pw.Border.all(color: borderColor, width: 0.6),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Attached Photo Proof [Image file could not be retrieved offline]',
                          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: darkText),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'URL: ${proof.proofUrl}',
                          style: pw.TextStyle(fontSize: 7.5, color: mutedText),
                          maxLines: 2,
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),

          // Metadata footer below image
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: borderColor, width: 0.6)),
              color: pdf_core.PdfColor.fromHex('#F8FAFC'),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (!isGallery && proof.proofTime != null && proof.proofTime!.isNotEmpty)
                  pw.Expanded(
                    child: pw.Text(
                      'Time: ${proof.proofTime}',
                      style: pw.TextStyle(fontSize: 7.5, color: darkText),
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                if (!isGallery && proof.proofLocation != null && proof.proofLocation!.isNotEmpty)
                  pw.Expanded(
                    child: pw.Text(
                      'Location: ${proof.proofLocation}',
                      style: pw.TextStyle(fontSize: 7.5, color: darkText),
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                if (!isGallery && proof.proofId != null && proof.proofId!.isNotEmpty)
                  pw.Text(
                    'Verification ID: ${proof.proofId}',
                    style: pw.TextStyle(fontSize: 7.5, color: mutedText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Utility Formatters ────────────────────────────────────────────

  static String _formatHours(double? hours) {
    if (hours == null || hours <= 0) return '0 hrs';
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()} hrs';
    }
    return '${hours.toStringAsFixed(1)} hrs';
  }

  static double _sumEntryHours(List<EsarfEntryItem> entries) {
    double sum = 0;
    for (final e in entries) {
      sum += (e.totalHours ?? 0);
    }
    return sum;
  }

  static String _formatDateRange(String? df, String? dt) {
    final from = _formatDateString(df);
    final to = _formatDateString(dt);
    if (from != null && to != null && from != to) {
      return '$from to $to';
    }
    return from ?? to ?? '-';
  }

  static String _formatTimeRange(String? tf, String? tt) {
    final from = _format12HourTime(tf);
    final to = _format12HourTime(tt);
    if (from.isNotEmpty && to.isNotEmpty) {
      return '$from - $to';
    }
    return from.isNotEmpty ? from : (to.isNotEmpty ? to : '-');
  }
}
