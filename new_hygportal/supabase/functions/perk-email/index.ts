import { createClient } from 'npm:@supabase/supabase-js@2';
import nodemailer from 'npm:nodemailer@6.9.15';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type StartBody = {
  action: 'start';
  formType: 'discount' | 'charge';
  transactionDate: string;
  products: Array<{ name: string; quantity: number; price: number }>;
  email?: string;
};

type VerifyBody = {
  action: 'verify';
  requestId: string;
  approvalCode: string;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Method not allowed.' }, 405);
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader) {
      return json({ error: 'Authentication required.' }, 401);
    }

    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const supabaseAnonKey = requiredEnv('SUPABASE_ANON_KEY');
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const body = (await req.json()) as StartBody | VerifyBody;
    if (body.action === 'start') {
      return await startRequest(supabase, body);
    }
    if (body.action === 'verify') {
      return await verifyRequest(supabase, body);
    }

    return json({ error: 'Invalid email action.' }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to process perk email.' }, 500);
  }
});

async function startRequest(supabase: ReturnType<typeof createClient>, body: StartBody) {
  const { data, error } = await supabase.rpc('start_employee_perk_request', {
    p_form_type: body.formType,
    p_transaction_date: body.transactionDate,
    p_products: body.products,
    p_email: body.email ?? null,
  });

  if (error) return json({ error: error.message }, 400);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return json({ error: 'Unable to create perk request.' }, 400);

  await sendMail({
    to: row.email,
    subject: `HYG Portal approval code: ${row.approval_code}`,
    text: [
      `Your ${row.request_label} approval code is ${row.approval_code}.`,
      '',
      'Enter this code in HYG Portal to approve and complete your request.',
    ].join('\n'),
    html: `
      <div style="font-family:Arial,sans-serif;color:#0f172a;line-height:1.5">
        <h2 style="margin:0 0 12px">HYG Portal Approval Code</h2>
        <p>Your <strong>${escapeHtml(row.request_label)}</strong> approval code is:</p>
        <div style="font-size:28px;font-weight:800;letter-spacing:4px;background:#fef3c7;border-radius:8px;padding:14px 18px;display:inline-block">${escapeHtml(row.approval_code)}</div>
        <p>Enter this code in HYG Portal to approve and complete your request.</p>
      </div>
    `,
  });

  return json({
    requestId: row.request_id,
    email: row.email,
    requestLabel: row.request_label,
  });
}

async function verifyRequest(supabase: ReturnType<typeof createClient>, body: VerifyBody) {
  const { data, error } = await supabase.rpc('verify_employee_perk_request', {
    p_request_id: body.requestId,
    p_approval_code: body.approvalCode,
  });

  if (error) return json({ error: error.message }, 400);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return json({ error: 'Unable to verify perk request.' }, 400);

  const amount = Number(row.amount ?? 0);
  const finalAmount = Number(row.final_amount ?? 0);
  const discountAmount = Number(row.discount_amount ?? Math.max(amount - finalAmount, 0));
  const slipTitle = `${row.request_label ?? 'Employee Benefit'} Slip`;
  const employeeName = String(row.employee_name ?? 'Employee').toUpperCase();
  const employeeNo = String(row.employee_no ?? 'N/A').toUpperCase();
  const departmentName = String(row.department_name ?? 'N/A').toUpperCase();
  const companyName = String(row.company_name ?? 'N/A');
  const benefit = String(row.benefit ?? 'Employee benefit');
  const itemText = String(row.product_name ?? 'No items listed');

  await sendMail({
    to: row.email,
    subject: `HYG Employee Portal approved slip: ${row.approval_code}`,
    text: [
      'HYG Employee Portal',
      slipTitle,
      'Show this approved slip to the cashier.',
      '',
      'Approval Code',
      row.approval_code,
      'Status: Approved',
      '',
      `Employee\t${employeeName}`,
      `Employee No.\t${employeeNo}`,
      `Department\t${departmentName}`,
      `Company\t${companyName}`,
      `Transaction date: ${row.transaction_date}`,
      `Benefit\t${benefit}`,
      '',
      'Items',
      itemText,
      `Subtotal:\tPHP ${formatMoney(amount)}`,
      `Discount 15%:\tPHP ${formatMoney(discountAmount)}`,
      `Total:\tPHP ${formatMoney(finalAmount)}`,
      '',
      'Cashier note: Verify the approval code and employee identity before honoring this slip.',
    ].join('\n'),
    html: approvedSlipHtml({
      title: slipTitle,
      code: String(row.approval_code ?? ''),
      employeeName,
      employeeNo,
      departmentName,
      companyName,
      transactionDate: String(row.transaction_date ?? ''),
      benefit,
      itemText,
      amount,
      discountAmount,
      finalAmount,
    }),
  });

  return json({
    requestId: row.request_id,
    email: row.email,
    requestLabel: row.request_label,
    productName: row.product_name,
    transactionDate: row.transaction_date,
    amount,
    finalAmount,
  });
}

function approvedSlipHtml({
  title,
  code,
  employeeName,
  employeeNo,
  departmentName,
  companyName,
  transactionDate,
  benefit,
  itemText,
  amount,
  discountAmount,
  finalAmount,
}: {
  title: string;
  code: string;
  employeeName: string;
  employeeNo: string;
  departmentName: string;
  companyName: string;
  transactionDate: string;
  benefit: string;
  itemText: string;
  amount: number;
  discountAmount: number;
  finalAmount: number;
}) {
  return `
    <div style="margin:0;padding:24px;background:#f1f5f9;font-family:Arial,sans-serif;color:#0f172a;line-height:1.45">
      <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #dbe3ee;border-radius:14px;overflow:hidden;box-shadow:0 10px 28px rgba(15,23,42,.12)">
        <div style="background:#0f172a;color:#ffffff;padding:18px 22px">
          <div style="font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#facc15">HYG Employee Portal</div>
          <h1 style="margin:6px 0 0;font-size:22px;line-height:1.2">${escapeHtml(title)}</h1>
          <p style="margin:8px 0 0;color:#cbd5e1;font-size:14px">Show this approved slip to the cashier.</p>
        </div>

        <div style="padding:20px 22px">
          <div style="border:2px dashed #facc15;background:#fffbeb;border-radius:12px;padding:16px;text-align:center;margin-bottom:16px">
            <div style="font-size:12px;font-weight:800;text-transform:uppercase;color:#92400e">Approval Code</div>
            <div style="font-size:34px;font-weight:900;letter-spacing:6px;color:#0f172a;margin-top:4px">${escapeHtml(code)}</div>
            <div style="display:inline-block;margin-top:10px;padding:5px 12px;border-radius:999px;background:#dcfce7;color:#166534;font-size:12px;font-weight:900;text-transform:uppercase">Status: Approved</div>
          </div>

          <table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:16px">
            ${slipRow('Employee', employeeName)}
            ${slipRow('Employee No.', employeeNo)}
            ${slipRow('Department', departmentName)}
            ${slipRow('Company', companyName)}
            ${slipRow('Transaction date', transactionDate)}
            ${slipRow('Benefit', benefit)}
          </table>

          <div style="border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;margin-bottom:14px">
            <div style="background:#f8fafc;border-bottom:1px solid #e2e8f0;padding:10px 12px;font-size:13px;font-weight:900;text-transform:uppercase;color:#475569">Items</div>
            <div style="padding:12px;font-size:15px;font-weight:700;color:#0f172a">${escapeHtml(itemText)}</div>
          </div>

          <table style="width:100%;border-collapse:collapse;font-size:15px">
            ${amountRow('Subtotal:', `PHP ${formatMoney(amount)}`)}
            ${amountRow('Discount 15%:', `PHP ${formatMoney(discountAmount)}`)}
            <tr>
              <td style="padding:12px;border-top:2px solid #0f172a;font-size:17px;font-weight:900">Total:</td>
              <td style="padding:12px;border-top:2px solid #0f172a;text-align:right;font-size:20px;font-weight:900;color:#b45309">PHP ${formatMoney(finalAmount)}</td>
            </tr>
          </table>
        </div>

        <div style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:14px 22px;color:#475569;font-size:13px">
          <strong>Cashier note:</strong> Verify the approval code and employee identity before honoring this slip.
        </div>
      </div>
    </div>
  `;
}

async function sendMail(message: { to: string; subject: string; text: string; html: string }) {
  const user = requiredEnv('GMAIL_USER');
  const pass = requiredEnv('GMAIL_APP_PASSWORD');
  const senderName = Deno.env.get('GMAIL_SENDER_NAME') ?? 'HYG Portal';
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user, pass },
  });

  await transporter.sendMail({
    from: `"${senderName}" <${user}>`,
    ...message,
  });
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function formatMoney(value: number) {
  return value.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function slipRow(label: string, value: string) {
  return `
    <tr>
      <td style="border-bottom:1px solid #e2e8f0;padding:9px 0;color:#64748b;font-weight:800;width:38%">${escapeHtml(label)}</td>
      <td style="border-bottom:1px solid #e2e8f0;padding:9px 0;text-align:right;font-weight:800;color:#0f172a">${escapeHtml(value)}</td>
    </tr>
  `;
}

function amountRow(label: string, value: string) {
  return `
    <tr>
      <td style="padding:8px 12px;color:#475569;font-weight:800">${escapeHtml(label)}</td>
      <td style="padding:8px 12px;text-align:right;font-weight:900;color:#0f172a">${escapeHtml(value)}</td>
    </tr>
  `;
}

function escapeHtml(value: unknown) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
