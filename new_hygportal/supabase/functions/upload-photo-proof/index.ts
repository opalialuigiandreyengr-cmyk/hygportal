import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type UploadBody = {
  photoBase64: string; // Base64 data URL or raw base64 string
  employeeName: string;
  storeName?: string;
  timestamp: string;
  timeDigits: string;
  timePeriod: string;
  dateFormatted: string;
  dayFormatted: string;
  locationText: string;
  latitude?: number;
  longitude?: number;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Method not allowed.' }, 405);
    }

    const body = (await req.json()) as UploadBody;
    if (!body.photoBase64) {
      return json({ error: 'photoBase64 is required.' }, 400);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 1. Get Google Drive Service Account Access Token
    const accessToken = await getGoogleDriveAccessToken();
    // 1. Root Folder: "HYG Portal Photo Proof" created directly in My Drive ('root')
    const parentTargetId = Deno.env.get('GDRIVE_ROOT_FOLDER_ID') || 'root';
    const mainFolderId = await getOrCreateDriveFolder(accessToken, 'HYG Portal Photo Proof', parentTargetId);

    // 2. Clean names for Store & Employee
    const storeNameClean = (body.storeName || 'General Store').replaceAll(/[^a-zA-Z0-9 _-]/g, '').trim();
    const empNameClean = (body.employeeName || 'Employee').replaceAll(/[^a-zA-Z0-9 _-]/g, '').trim();

    // 3. Format Date string as MMDDYYYY (e.g. 09012026)
    let dateFolderStr = '09012026';
    if (body.timestamp) {
      const d = new Date(body.timestamp);
      if (!isNaN(d.getTime())) {
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const yyyy = d.getFullYear();
        dateFolderStr = `${mm}${dd}${yyyy}`;
      }
    } else if (body.dateFormatted) {
      dateFolderStr = body.dateFormatted.replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '');
    }

    // 4. Create 3-Tier Folder Hierarchy: HYG Portal Photo Proof -> [Store] -> [Date] -> [Employee]
    const storeFolderId = await getOrCreateDriveFolder(accessToken, storeNameClean, mainFolderId);
    const dateFolderId = await getOrCreateDriveFolder(accessToken, dateFolderStr, storeFolderId);
    const empFolderId = await getOrCreateDriveFolder(accessToken, empNameClean, dateFolderId);

    // 5. Prepare Base64 Image Data & Upload File
    const rawStr = body.photoBase64.includes(',') ? body.photoBase64.split(',')[1] : body.photoBase64;
    const cleanBase64 = rawStr.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '').trim();

    const timeDigitsClean = (body.timeDigits || '').replace(':', '');
    const timePeriodClean = body.timePeriod || '';
    const fileName = `${empNameClean.replaceAll(' ', '_')}_${timeDigitsClean}_${timePeriodClean}.jpg`;

    const driveFile = await uploadFileToDrive(accessToken, empFolderId, fileName, cleanBase64, 'image/jpeg');

    // 4. Make File Readable via Link
    await makeDriveFileReadable(accessToken, driveFile.id);

    const driveWebViewLink = driveFile.webViewLink || `https://drive.google.com/file/d/${driveFile.id}/view`;

    // 5. Insert Record into Supabase photo_proofs table
    const { data: dbData, error: dbError } = await supabase.from('photo_proofs').insert({
      employee_name: body.employeeName,
      store_name: body.storeName,
      timestamp: body.timestamp,
      time_digits: body.timeDigits,
      time_period: body.timePeriod,
      date_formatted: body.dateFormatted,
      day_formatted: body.dayFormatted,
      location_text: body.locationText,
      latitude: body.latitude,
      longitude: body.longitude,
      drive_file_id: driveFile.id,
      drive_web_view_link: driveWebViewLink,
    }).select().single();

    if (dbError) {
      console.warn('DB insert error (file saved to Drive successfully):', dbError);
    }

    return json({
      success: true,
      driveFileId: driveFile.id,
      driveWebViewLink,
      record: dbData,
    });
  } catch (error) {
    console.error('Upload Error:', error);
    return json({
      success: false,
      error: error instanceof Error ? `${error.message} (stack: ${error.stack})` : String(error),
    }, 200);
  }
});

const OAUTH_CLIENT_ID = ''; // Set via Supabase secret: GDRIVE_OAUTH_CLIENT_ID
const OAUTH_CLIENT_SECRET = ''; // Set via Supabase secret: GDRIVE_OAUTH_CLIENT_SECRET
const OAUTH_REFRESH_TOKEN = ''; // Set via Supabase secret: GDRIVE_OAUTH_REFRESH_TOKEN

const DEFAULT_CLIENT_EMAIL = ''; // Set via Supabase secret: GDRIVE_SERVICE_ACCOUNT_EMAIL
const DEFAULT_PRIVATE_KEY = ``; // Set via Supabase secret: GDRIVE_PRIVATE_KEY

async function getGoogleDriveAccessToken(): Promise<string> {
  const refreshToken = Deno.env.get('GDRIVE_OAUTH_REFRESH_TOKEN') || OAUTH_REFRESH_TOKEN;
  const clientId = Deno.env.get('GDRIVE_OAUTH_CLIENT_ID') || OAUTH_CLIENT_ID;
  const clientSecret = Deno.env.get('GDRIVE_OAUTH_CLIENT_SECRET') || OAUTH_CLIENT_SECRET;

  if (refreshToken && clientId && clientSecret) {
    try {
      const params = new URLSearchParams();
      params.append('client_id', clientId);
      params.append('client_secret', clientSecret);
      params.append('refresh_token', refreshToken);
      params.append('grant_type', 'refresh_token');

      const res = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
      });

      const tokenData = await res.json();
      if (tokenData.access_token) {
        return tokenData.access_token;
      }
      console.warn('OAuth refresh token exchange fallback:', tokenData);
    } catch (err) {
      console.warn('OAuth refresh token error:', err);
    }
  }

  const serviceAccountJsonStr = Deno.env.get('GDRIVE_SERVICE_ACCOUNT_KEY');
  let clientEmail = Deno.env.get('GDRIVE_CLIENT_EMAIL') || DEFAULT_CLIENT_EMAIL;
  let privateKey = Deno.env.get('GDRIVE_PRIVATE_KEY') || DEFAULT_PRIVATE_KEY;

  if (serviceAccountJsonStr) {
    try {
      const parsed = JSON.parse(serviceAccountJsonStr);
      if (parsed.client_email) clientEmail = parsed.client_email;
      if (parsed.private_key) privateKey = parsed.private_key;
    } catch {
      // ignore
    }
  }

  // Create JWT for Google OAuth2
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaim = base64UrlEncode(JSON.stringify(claim));
  const signatureInput = `${encodedHeader}.${encodedClaim}`;

  const signature = await signRS256(signatureInput, privateKey);
  const jwt = `${signatureInput}.${signature}`;

  const params = new URLSearchParams();
  params.append('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  params.append('assertion', jwt);

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  const tokenData = await res.json();
  if (!tokenData.access_token) {
    throw new Error(`Failed to get Google Drive access token: ${JSON.stringify(tokenData)}`);
  }

  return tokenData.access_token;
}

async function getOrCreateDriveFolder(accessToken: string, folderName: string, parentFolderId: string): Promise<string> {
  const query = `name = '${folderName}' and '${parentFolderId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
  const res = await fetch(`https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(query)}&supportsAllDrives=true&includeItemsFromAllDrives=true`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const data = await res.json();
  if (data.files && data.files.length > 0) {
    return data.files[0].id;
  }

  const createRes = await fetch('https://www.googleapis.com/drive/v3/files?supportsAllDrives=true', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      name: folderName,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentFolderId],
    }),
  });

  const folder = await createRes.json();
  return folder.id;
}

async function uploadFileToDrive(
  accessToken: string,
  parentFolderId: string,
  fileName: string,
  cleanBase64Data: string,
  mimeType: string = 'image/jpeg',
): Promise<{ id: string; webViewLink?: string }> {
  const metadata = {
    name: fileName,
    parents: [parentFolderId],
  };

  const boundary = '-------314159265358979323846';
  const multipartBody = [
    `--${boundary}`,
    'Content-Type: application/json; charset=UTF-8',
    '',
    JSON.stringify(metadata),
    `--${boundary}`,
    `Content-Type: ${mimeType}`,
    'Content-Transfer-Encoding: base64',
    '',
    cleanBase64Data,
    `--${boundary}--`,
  ].join('\r\n');

  const res = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,webViewLink', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': `multipart/related; boundary=${boundary}`,
    },
    body: multipartBody,
  });

  const file = await res.json();
  if (!file.id) {
    throw new Error(`Google Drive upload failed: ${JSON.stringify(file)}`);
  }

  return file;
}

async function makeDriveFileReadable(accessToken: string, fileId: string) {
  try {
    await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}/permissions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        role: 'reader',
        type: 'anyone',
      }),
    });
  } catch {
    // ignore
  }
}

async function signRS256(message: string, pemKey: string): Promise<string> {
  const cleanPem = pemKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll('\n', '')
    .replaceAll('\r', '')
    .trim();

  const binaryDer = Uint8Array.from(atob(cleanPem), (c) => c.charCodeAt(0));

  const importedKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const encoder = new TextEncoder();
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    importedKey,
    encoder.encode(message),
  );

  return base64UrlEncode(new Uint8Array(signatureBuffer));
}

function base64UrlEncode(strOrBytes: string | Uint8Array): string {
  let base64 = typeof strOrBytes === 'string' ? btoa(strOrBytes) : base64FromBytes(strOrBytes);
  return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function base64FromBytes(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
