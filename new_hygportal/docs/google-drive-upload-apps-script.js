  /**
   * Upload-only Google Apps Script for Employee Documents.
   *
   * No Advanced Drive API required.
   * Uses DriveApp only, so setup is simpler.
   *
   * Deploy as Web App:
   * - Execute as: Me
   * - Who has access: Anyone with the link
   *
   * Request JSON:
   * {
   *   "rootFolderId": "1N-OzBcYFP5-l3CcEWuaGcLSxU8iFm0zV",
   *   "company": "Chawnah Foods INC.",
   *   "department": "OPERATIONS",
   *   "docType": "tin",
   *   "fileName": "tin_17188888888.jpg",
   *   "mimeType": "image/jpeg",
   *   "base64Data": "...."
   * }
   */

  function doGet() {
    return json_({
      ok: true,
      message: 'Drive uploader is running.',
      requiredFields: [
        'rootFolderId',
        'company',
        'department',
        'docType',
        'fileName',
        'mimeType',
        'base64Data'
      ]
    });
  }

  function doPost(e) {
    try {
      if (!e || !e.postData || !e.postData.contents) {
        return json_({ ok: false, error: 'Missing request body.' });
      }

      var body = JSON.parse(e.postData.contents || '{}');
      validate_(body);

      var root = DriveApp.getFolderById(String(body.rootFolderId).trim());
      var companyFolder = getOrCreateFolder_(root, sanitize_(body.company));
      var departmentFolder = getOrCreateFolder_(companyFolder, sanitize_(body.department));
      var docFolder = getOrCreateFolder_(departmentFolder, sanitize_(String(body.docType).toUpperCase()));

      var bytes = Utilities.base64Decode(body.base64Data);
      var fileName = sanitize_(body.fileName || ('upload_' + Date.now() + '.bin'));
      var mimeType = String(body.mimeType || 'application/octet-stream').trim();
      var blob = Utilities.newBlob(bytes, mimeType, fileName);
    var file = docFolder.createFile(blob);

    // Keep private by default.
    file.setSharing(DriveApp.Access.PRIVATE, DriveApp.Permission.VIEW);
    var detectedTin = '';
    if (String(body.docType || '').toLowerCase() === 'tin') {
      detectedTin = tryExtractTinViaOcr_(file.getId());
    }

    return json_({
      ok: true,
      fileId: file.getId(),
      fileName: file.getName(),
        webViewLink: file.getUrl(),
      webContentLink: 'https://drive.google.com/uc?id=' + file.getId() + '&export=download',
      mimeType: file.getMimeType(),
      sizeBytes: file.getSize(),
      drivePath: companyFolder.getName() + '/' + departmentFolder.getName() + '/' + docFolder.getName(),
      detectedNumber: detectedTin || null
    });
  } catch (err) {
      return json_({
        ok: false,
        error: err && err.message ? err.message : String(err)
      });
    }
  }

  function validate_(body) {
    var required = ['rootFolderId', 'company', 'department', 'docType', 'base64Data'];
    for (var i = 0; i < required.length; i++) {
      var key = required[i];
      if (!body[key] || String(body[key]).trim() === '') {
        throw new Error('Missing required field: ' + key);
      }
    }
  }

  function getOrCreateFolder_(parent, name) {
    var it = parent.getFoldersByName(name);
    if (it.hasNext()) return it.next();
    return parent.createFolder(name);
  }

  function sanitize_(value) {
    return String(value || '').replace(/[\\/:*?"<>|]/g, '_').trim() || 'UNKNOWN';
  }

function json_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * OCR TIN using Drive API HTTP call (no Advanced Service object needed).
 * Needs Google Drive API enabled in linked GCP project.
 * Returns '' if OCR cannot run.
 */
function tryExtractTinViaOcr_(fileId) {
  try {
    var accessToken = ScriptApp.getOAuthToken();
    var copyUrl =
      'https://www.googleapis.com/drive/v2/files/' +
      encodeURIComponent(fileId) +
      '/copy?ocr=true&ocrLanguage=en';

    var copyResp = UrlFetchApp.fetch(copyUrl, {
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify({
        title: 'OCR_' + Date.now(),
        mimeType: 'application/vnd.google-apps.document'
      }),
      headers: {
        Authorization: 'Bearer ' + accessToken
      },
      muteHttpExceptions: true
    });

    if (copyResp.getResponseCode() >= 300) {
      return '';
    }

    var copyJson = JSON.parse(copyResp.getContentText() || '{}');
    var docId = copyJson.id;
    if (!docId) {
      return '';
    }

    var text = '';
    try {
      text = DocumentApp.openById(docId).getBody().getText() || '';
    } finally {
      DriveApp.getFileById(docId).setTrashed(true);
    }

    return extractTin_(text);
  } catch (_err) {
    return '';
  }
}

function extractTin_(rawText) {
  var text = String(rawText || '').toUpperCase().replace(/\s+/g, ' ').trim();
  if (!text) return '';

  // Common PH TIN formats: 000-000-000 or 000-000-000-000
  var m = text.match(/\b(\d{3}[- ]?\d{3}[- ]?\d{3}(?:[- ]?\d{3})?)\b/);
  if (!m) return '';
  return m[1].replace(/[ ]/g, '-');
}
