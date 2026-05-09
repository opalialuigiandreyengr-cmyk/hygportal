from datetime import datetime, timedelta
from email.message import EmailMessage
import json
import os
import random
import re
import smtplib
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from flask import Blueprint, flash, jsonify, redirect, render_template, request, session, url_for
from flask_login import current_user, login_required
from sqlalchemy import or_
from werkzeug.security import generate_password_hash

from . import db
from .helpers import _save_employee_photo, create_notification, philippine_now, sync_department_name
from .models import (
    Company,
    Department,
    Employee,
    EsarfRequest,
    LeaveRequest,
    DiscountRequest,
    ProductChargeRequest,
    Notification,
    User,
    EsarfApprover,
    LeaveApprover,
)

employee = Blueprint('employee', __name__)

PERK_APPROVAL_EMAIL = "icount.itsolution@gmail.com"
PERK_APPROVAL_PASSWORD = "llpb llss ztrm ujtj"
PERK_APPROVAL_SENDER = "HYG Employee Portal - No Reply"
AI_PROVIDER = os.getenv("AI_PROVIDER", "openrouter").strip().lower()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free").strip()
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini").strip()
LOCAL_AI_MODEL = os.getenv("OLLAMA_MODEL", "qwen3.5:0.8b").strip()
AI_OLLAMA_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
AI_MODEL_OPTIONS = (LOCAL_AI_MODEL, OPENROUTER_MODEL if AI_PROVIDER == "openrouter" else OPENAI_MODEL)
AI_DEFAULT_MODEL = AI_MODEL_OPTIONS[0]
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"

ESARF_STATUS_DEPT_MGR_APPROVED = "Dept Mgr Approved"
LEAVE_STATUS_DEPT_HR_APPROVED = "Dept/HR Approved"


def _format_employee_no(hired_date, sequence):
    date_part = hired_date.strftime("%m%d%Y") if hired_date else "00000000"
    return f"{date_part}-{sequence:02d}"


def _next_employee_no_for_date(hired_date, exclude_employee_id=None):
    prefix = hired_date.strftime("%m%d%Y") if hired_date else "00000000"
    query = Employee.query.with_entities(Employee.employee_no).filter(
        Employee.employee_no.like(f"{prefix}-%")
    )
    if exclude_employee_id is not None:
        query = query.filter(Employee.id != exclude_employee_id)

    max_sequence = 0
    for value, in query.all():
        if not value:
            continue
        try:
            max_sequence = max(max_sequence, int(str(value).rsplit("-", 1)[1]))
        except (IndexError, ValueError):
            continue
    return _format_employee_no(hired_date, max_sequence + 1)


def _should_refresh_employee_no(employee_no, hired_date):
    normalized_employee_no = (str(employee_no or "").strip()).lower()
    return (
        not normalized_employee_no
        or normalized_employee_no in {"none", "n/a", "null"}
        or normalized_employee_no.startswith("00000000-")
    )


def _require_employee_profile():
    if current_user.employee:
        return None
    flash('Your account is not linked to an employee profile.', category='error')
    return redirect(url_for('views.home'))


def _normalize_text(value):
    return " ".join((value or "").strip().lower().split())


def _ai_model_choice(value):
    selected = (value or AI_DEFAULT_MODEL or AI_MODEL_OPTIONS[0]).strip()
    if selected not in AI_MODEL_OPTIONS:
        return AI_MODEL_OPTIONS[0]
    return selected


def _ollama_model_detected(model_name=LOCAL_AI_MODEL):
    if not AI_OLLAMA_URL or not model_name:
        return False

    try:
        tags_request = Request(f"{AI_OLLAMA_URL}/api/tags", method="GET")
        with urlopen(tags_request, timeout=1.5) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return False

    for model in data.get("models") or []:
        name = (model.get("name") or "").strip()
        base_name = name.split(":", 1)[0]
        if name == model_name or base_name == model_name:
            return True
    return False


def _configured_ai_provider_model(model):
    provider = (os.getenv("AI_PROVIDER") or AI_PROVIDER or "openrouter").strip().lower()
    if provider == "ollama":
        return provider, LOCAL_AI_MODEL
    if provider == "openai":
        return provider, model if model == OPENAI_MODEL else OPENAI_MODEL
    return "openrouter", model if model == OPENROUTER_MODEL else OPENROUTER_MODEL


def _resolve_ai_provider_model(model):
    if _ollama_model_detected(LOCAL_AI_MODEL):
        return "ollama", LOCAL_AI_MODEL
    return _configured_ai_provider_model(model)


def _ai_system_prompt():
    return (
        "You are HYG Assist, a concise employee portal assistant. "
        "Help draft workplace messages, explain HR portal steps, and keep answers practical. "
        "For HR/Admin users, answer HR database questions about employees, companies, departments, age, gender, status, company, and department counts from the portal data. "
        "For employee perks, support Employee Discount (Cash) and Employee Charge (Credit). "
        "When an employee asks to apply for either perk, ask for transaction date, product name, quantity, and unit price if missing. "
        "Do not invent company policy; say when HR/Admin confirmation is needed. "
        "When drafting a message and details are missing, write a usable draft with simple placeholders. "
        "Use clean plain text for drafts; avoid Markdown symbols such as asterisks, bold markers, and heading hashes. "
        "Keep the final answer direct and employee-friendly."
    )


def _call_openai_chat(message, model):
    api_key = (os.getenv("OPENAI_API_KEY") or "").strip()
    if not api_key:
        raise RuntimeError("missing_openai_key")

    from openai import OpenAI

    client = OpenAI(api_key=api_key)
    response = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": _ai_system_prompt()},
            {"role": "user", "content": message},
        ],
    )
    return (response.output_text or "").strip(), ""


def _call_openrouter_chat(message, model):
    api_key = (os.getenv("OPENROUTER_API_KEY") or "").strip()
    if not api_key:
        raise RuntimeError("missing_openrouter_key")

    payload = {
        "model": model or OPENROUTER_MODEL,
        "messages": [
            {"role": "system", "content": _ai_system_prompt()},
            {"role": "user", "content": message},
        ],
        "temperature": 0.4,
        "max_tokens": 350,
    }
    request_payload = json.dumps(payload).encode("utf-8")
    openrouter_request = Request(
        OPENROUTER_API_URL,
        data=request_payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": os.getenv("APP_PUBLIC_URL", "https://www.pythonanywhere.com"),
            "X-Title": "HYG Employee Portal",
        },
        method="POST",
    )

    with urlopen(openrouter_request, timeout=60) as response:
        data = json.loads(response.read().decode("utf-8"))

    choices = data.get("choices") or []
    first_choice = choices[0] if choices else {}
    message_data = first_choice.get("message") or {}
    reply = (message_data.get("content") or "").strip()
    return reply, ""


def _call_ollama_chat(message, model):
    if not AI_OLLAMA_URL:
        raise RuntimeError("missing_ollama_url")

    payload = {
        "model": model,
        "stream": False,
        "think": False,
        "messages": [
            {
                "role": "system",
                "content": _ai_system_prompt(),
            },
            {"role": "user", "content": message},
        ],
        "options": {
            "temperature": 0.4,
            "num_ctx": 2048,
            "num_predict": 350,
        },
    }
    request_payload = json.dumps(payload).encode("utf-8")
    ollama_request = Request(
        f"{AI_OLLAMA_URL}/api/chat",
        data=request_payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urlopen(ollama_request, timeout=300) as response:
        data = json.loads(response.read().decode("utf-8"))

    message_data = data.get("message") or {}
    reply = (message_data.get("content") or "").strip()
    thinking = (message_data.get("thinking") or "").strip()
    return reply, thinking


def _call_general_ai_chat(message, model):
    provider, resolved_model = _resolve_ai_provider_model(model)
    
    # Check if API keys are configured
    api_key_configured = False
    if provider == "ollama":
        if AI_OLLAMA_URL:
            api_key_configured = True
    elif provider == "openai":
        if (os.getenv("OPENAI_API_KEY") or "").strip():
            api_key_configured = True
    else:  # openrouter
        if (os.getenv("OPENROUTER_API_KEY") or "").strip():
            api_key_configured = True
    
    # If no API key is configured, return "Coming Soon" message
    if not api_key_configured:
        return (
            "HYG Assist AI is coming soon! This feature will be available once the AI setup is complete. "
            "In the meantime, I can still help you with:\n"
            "• Draft leave requests (just mention dates)\n"
            "• Draft ESARF requests (mention overtime, offset, etc.)\n"
            "• Employee discount and charge requests\n"
            "• HR questions about employee counts",
            "AI features are being set up for PythonAnywhere deployment."
        )
    
    # Call the appropriate AI provider
    if provider == "ollama":
        return _call_ollama_chat(message, resolved_model)
    if provider == "openai":
        return _call_openai_chat(message, resolved_model)
    return _call_openrouter_chat(message, resolved_model)


def _build_assist_thinking(prompt):
    prompt_lower = (prompt or "").lower()
    if "offset" in prompt_lower and any(word in prompt_lower for word in ("credit", "credits", "balance", "have", "left", "available")):
        return "I checked the offset credit balance saved on your portal account."
    if _detect_ai_perk_type(prompt_lower):
        return "I understood this as an employee perk request and checked the required cash discount or credit charge details."
    if "leave" in prompt_lower:
        return "I understood this as a leave request, found the date range, chose a likely leave category, and prepared a draft for review."
    if "esarf" in prompt_lower:
        return "I focused on the ESARF reason, made the wording clear, and kept it ready for review before submitting."
    if "summarize" in prompt_lower or "summary" in prompt_lower:
        return "I read for the main point, separated the important details, and looked for the next action needed."
    return "I read your request, chose a helpful employee-friendly format, and kept the answer practical."


def _detect_ai_perk_type(prompt):
    text = (prompt or "").lower()
    mentions_discount = (
        "employee discount" in text
        or "cash discount" in text
        or "discount cash" in text
        or ("discount" in text and any(word in text for word in ("apply", "avail", "perk", "cash", "employee")))
    )
    mentions_charge = (
        "employee charge" in text
        or "credit charge" in text
        or "charge credit" in text
        or ("charge" in text and any(word in text for word in ("apply", "avail", "perk", "credit", "employee")))
    )

    if mentions_discount and not mentions_charge:
        return "discount"
    if mentions_charge and not mentions_discount:
        return "charge"
    if mentions_discount or mentions_charge or ("perk" in text and any(word in text for word in ("apply", "avail", "request"))):
        return "perk"
    return None


def _extract_ai_money_amount(prompt):
    text = (prompt or "").lower().replace(",", "")
    match = re.search(r"(?:php|p)\s*(\d+(?:\.\d{1,2})?)|(\d+(?:\.\d{1,2})?)\s*(?:php|pesos?)", text)
    if not match:
        return None
    try:
        return float(match.group(1) or match.group(2))
    except (TypeError, ValueError):
        return None


def _answer_ai_perk_request(prompt):
    perk_type = _detect_ai_perk_type(prompt)
    if not perk_type:
        return None

    text = (prompt or "").lower()
    today = philippine_now().date().isoformat()
    amount = _extract_ai_money_amount(prompt)
    has_product = any(word in text for word in ("product", "item", "buy", "purchase", "order"))
    has_quantity = bool(re.search(r"\b(?:qty|quantity|x)\s*\d+\b|\b\d+\s*(?:pc|pcs|piece|pieces)\b", text))
    has_date = bool(re.search(r"\b(20\d{2}-\d{2}-\d{2}|today|tomorrow|yesterday)\b", text))

    if perk_type == "discount":
        missing = []
        if not has_date:
            missing.append("transaction date")
        if not has_product:
            missing.append("product name")
        if not has_quantity:
            missing.append("quantity")
        if amount is None:
            missing.append("unit price or total amount")

        detail_line = (
            f"I have the amount as PHP {amount:.2f}. "
            if amount is not None
            else ""
        )
        if missing:
            reply = (
                "Sure, I can help with Employee Discount (Cash). "
                "Please send the " + ", ".join(missing) + ". "
                f"{detail_line}This request uses the cash discount form: 15% off, with a PHP 3,000 yearly cap and up to 6 transactions per year."
            )
        else:
            reply = (
                "This looks ready for Employee Discount (Cash). "
                f"{detail_line}Open the Perks page, choose Employee Discount (Cash), confirm the product, quantity, unit price, and transaction date, then submit for the approval code."
            )
        return {
            "reply": reply,
            "thinking": _build_assist_thinking(prompt),
            "action_url": url_for("employee.perks"),
            "action_label": "Open Perks",
        }

    if perk_type == "charge":
        missing = []
        if not has_date:
            missing.append("transaction date")
        if not has_product:
            missing.append("product name")
        if not has_quantity:
            missing.append("quantity")
        if amount is None:
            missing.append("unit price or total amount")

        limit_note = "Employee Charge (Credit) has a PHP 3,000 per-transaction limit."
        if amount is not None and amount > 3000:
            limit_note = f"The amount PHP {amount:.2f} is above the PHP 3,000 per-transaction credit limit."
        first_note = " The first yearly credit transaction gets 15% off."

        if missing:
            reply = (
                "Sure, I can help with Employee Charge (Credit). "
                "Please send the " + ", ".join(missing) + ". "
                f"{limit_note}{first_note}"
            )
        else:
            reply = (
                "This looks ready for Employee Charge (Credit). "
                f"{limit_note}{first_note} Open the Perks page, choose Employee Charge (Credit), review the item details, then submit for the approval code."
            )
        return {
            "reply": reply,
            "thinking": _build_assist_thinking(prompt),
            "action_url": url_for("employee.perks"),
            "action_label": "Open Perks",
        }

    return {
        "reply": (
            "Which perk do you want to apply for: Employee Discount (Cash) or Employee Charge (Credit)? "
            f"Send the transaction date, product name, quantity, and unit price. If the transaction date is today, you can use {today}."
        ),
        "thinking": _build_assist_thinking(prompt),
        "action_url": url_for("employee.perks"),
        "action_label": "Open Perks",
    }


def _is_hr_prompt(prompt):
    text = (prompt or "").lower()
    if any(term in text for term in ("employee discount", "employee charge", "cash discount", "credit charge")):
        return False
    hr_terms = (
        "hr",
        "employee",
        "employees",
        "company",
        "companies",
        "department",
        "departments",
        "age",
        "agge",
        "gender",
        "male",
        "female",
        "active",
        "pending",
        "resigned",
        "suspended",
        "terminated",
        "awol",
        "on leave",
    )
    return any(term in text for term in hr_terms) and any(
        term in text for term in ("how many", "count", "total", "list", "breakdown", "do we have", "status")
    )


def _user_can_view_hr_ai():
    return (current_user.role or "").strip().lower() in {"admin", "hr"}


def _count_employees_for_field(field_name, value):
    field = getattr(Employee, field_name)
    normalized_value = (value or "").strip().lower()
    return Employee.query.filter(db.func.lower(db.func.trim(field)) == normalized_value).count()


def _top_count_lines(rows, limit=8):
    visible = [row for row in rows if row[0] and str(row[0]).strip()]
    visible.sort(key=lambda row: row[1], reverse=True)
    return "\n".join(f"- {name}: {count}" for name, count in visible[:limit]) or "- No data available."


def _answer_ai_hr_question(prompt):
    if not _is_hr_prompt(prompt):
        return None

    if not _user_can_view_hr_ai():
        return {
            "reply": "HR database questions are available only to HR and admin accounts.",
            "thinking": "I recognized this as an HR data question and checked your portal role before showing totals.",
        }

    text = (prompt or "").lower()
    total_employees = Employee.query.count()

    age_match = re.search(r"\b(?:age|agge|aged)\s*(?:is|=|:)?\s*(\d{1,3})\b|\b(\d{1,3})\s*(?:years old|year old|yrs old)\b", text)
    if age_match and "employee" in text:
        age = int(age_match.group(1) or age_match.group(2))
        count = Employee.query.filter(Employee.age == age).count()
        return {
            "reply": f"We have {count} employee{'s' if count != 1 else ''} age {age}.",
            "thinking": "I filtered employee records by exact age.",
            "action_url": url_for("admin.employees"),
            "action_label": "Open Employees",
        }

    status_labels = ("Active", "Pending", "Resigned", "Suspended", "On Leave", "Terminated", "AWOL")
    for status in status_labels:
        if status.lower() in text:
            count = Employee.query.filter(
                or_(
                    db.func.lower(db.func.trim(Employee.employment_status)) == status.lower(),
                    db.func.lower(db.func.trim(Employee.status)) == status.lower(),
                )
            ).count()
            return {
                "reply": f"We have {count} {status.lower()} employee{'s' if count != 1 else ''}.",
                "thinking": "I checked both employment_status and status fields for this HR count.",
                "action_url": url_for("admin.employees", status=status),
                "action_label": "Open Employees",
            }

    if "male" in text or "female" in text:
        gender = "Female" if "female" in text else "Male"
        count = _count_employees_for_field("gender", gender)
        return {
            "reply": f"We have {count} {gender.lower()} employee{'s' if count != 1 else ''}.",
            "thinking": "I filtered employee records by gender.",
            "action_url": url_for("admin.employees"),
            "action_label": "Open Employees",
        }

    company_names = [company.company_name for company in Company.query.order_by(Company.company_name.asc()).all()]
    for company_name in company_names:
        if company_name and company_name.lower() in text:
            count = _count_employees_for_field("company", company_name)
            return {
                "reply": f"{company_name} has {count} employee{'s' if count != 1 else ''}.",
                "thinking": "I matched the company name and counted employees assigned to it.",
                "action_url": url_for("admin.employees", company=company_name),
                "action_label": "Open Employees",
            }

    department_names = [department.department_name for department in Department.query.order_by(Department.department_name.asc()).all()]
    for department_name in department_names:
        if department_name and department_name.lower() in text:
            count = _count_employees_for_field("department", department_name)
            return {
                "reply": f"{department_name} has {count} employee{'s' if count != 1 else ''}.",
                "thinking": "I matched the department name and counted employees assigned to it.",
                "action_url": url_for("admin.employees", search=department_name),
                "action_label": "Open Employees",
            }

    if "company" in text and any(term in text for term in ("breakdown", "by company", "per company", "list", "employee count")):
        rows = db.session.query(Employee.company, db.func.count(Employee.id)).group_by(Employee.company).all()
        return {
            "reply": "Employee count by company:\n" + _top_count_lines(rows),
            "thinking": "I grouped employees by company.",
            "action_url": url_for("admin.dashboard"),
            "action_label": "Open HR Dashboard",
        }

    if "department" in text and any(term in text for term in ("breakdown", "by department", "per department", "list", "employee count")):
        rows = db.session.query(Employee.department, db.func.count(Employee.id)).group_by(Employee.department).all()
        return {
            "reply": "Employee count by department:\n" + _top_count_lines(rows),
            "thinking": "I grouped employees by department.",
            "action_url": url_for("admin.dashboard"),
            "action_label": "Open HR Dashboard",
        }

    if "compan" in text and any(term in text for term in ("how many", "total", "count", "do we have")):
        total_companies = Company.query.count()
        return {
            "reply": f"We have {total_companies} compan{'y' if total_companies == 1 else 'ies'} in the portal.",
            "thinking": "I counted company records from the HR company table.",
            "action_url": url_for("admin.companies"),
            "action_label": "Open Companies",
        }

    if "department" in text and any(term in text for term in ("how many", "total", "count", "do we have")):
        total_departments = Department.query.count()
        return {
            "reply": f"We have {total_departments} department{'s' if total_departments != 1 else ''} in the portal.",
            "thinking": "I counted department records from the HR department table.",
            "action_url": url_for("admin.departments"),
            "action_label": "Open Departments",
        }

    if "status" in text or "breakdown" in text:
        rows = db.session.query(Employee.employment_status, db.func.count(Employee.id)).group_by(Employee.employment_status).all()
        return {
            "reply": "Employee status breakdown:\n" + _top_count_lines(rows),
            "thinking": "I grouped employees by employment status.",
            "action_url": url_for("admin.dashboard"),
            "action_label": "Open HR Dashboard",
        }

    if "employee" in text or "hr" in text:
        pending_employees = Employee.query.filter(
            or_(
                Employee.status == "Pending",
                Employee.employment_status == "Pending",
            )
        ).count()
        total_companies = Company.query.count()
        total_departments = Department.query.count()
        return {
            "reply": (
                f"HR summary:\n"
                f"- Employees: {total_employees}\n"
                f"- Companies: {total_companies}\n"
                f"- Departments: {total_departments}\n"
                f"- Pending employees: {pending_employees}"
            ),
            "thinking": "I pulled the same core totals shown on the HR dashboard.",
            "action_url": url_for("admin.dashboard"),
            "action_label": "Open HR Dashboard",
        }

    return None


def _answer_portal_account_question(prompt):
    prompt_lower = (prompt or "").lower()
    asks_offset = "offset" in prompt_lower and any(
        word in prompt_lower
        for word in ("credit", "credits", "balance", "have", "left", "available")
    )
    if not asks_offset:
        return None

    credits = max(0.0, float(current_user.offset_credits or 0))
    unit = "hour" if credits == 1 else "hours"
    return {
        "reply": f"You currently have {credits:.2f} offset credit {unit} available.",
        "thinking": _build_assist_thinking(prompt),
    }


def _parse_ai_time_range(prompt):
    text = (prompt or "").lower()
    match = re.search(
        r"\b(?:from\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b",
        text,
    )
    if not match:
        return None

    start_hour = int(match.group(1))
    start_minute = int(match.group(2) or "0")
    start_meridiem = match.group(3)
    end_hour = int(match.group(4))
    end_minute = int(match.group(5) or "0")
    end_meridiem = match.group(6)

    if not start_meridiem:
        start_meridiem = end_meridiem

    def to_24_hour(hour, meridiem):
        if hour == 12:
            hour = 0
        if meridiem == "pm":
            hour += 12
        return hour

    return (
        f"{to_24_hour(start_hour, start_meridiem):02d}:{start_minute:02d}",
        f"{to_24_hour(end_hour, end_meridiem):02d}:{end_minute:02d}",
    )


def _parse_ai_request_date(prompt):
    text = (prompt or "").lower()
    today = philippine_now().date()
    if "yesterday" in text:
        return today - timedelta(days=1)
    if "today" in text:
        return today
    if "tomorrow" in text or "tommorow" in text:
        return today + timedelta(days=1)

    iso_match = re.search(r"\b(20\d{2}-\d{2}-\d{2})\b", text)
    if iso_match:
        try:
            return datetime.strptime(iso_match.group(1), "%Y-%m-%d").date()
        except ValueError:
            return today

    return today


def _parse_ai_date_range(prompt):
    text = (prompt or "").lower()
    single_date = _parse_ai_request_date(prompt)
    if any(word in text for word in ("yesterday", "today", "tomorrow", "tommorow")):
        return single_date, single_date

    months = {
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    }
    month_names = "|".join(sorted(months.keys(), key=len, reverse=True))
    match = re.search(
        rf"\b({month_names})\.?\s+(\d{{1,2}})(?:\s*(?:to|-|until)\s*(?:(?:{month_names})\.?\s+)?(\d{{1,2}}))?(?:,\s*(20\d{{2}}))?",
        text,
    )
    if not match:
        return single_date, single_date

    month = months[match.group(1)]
    start_day = int(match.group(2))
    end_day = int(match.group(3) or start_day)
    today = philippine_now().date()
    year = int(match.group(4) or today.year)

    try:
        start_date = datetime(year, month, start_day).date()
        end_date = datetime(year, month, end_day).date()
    except ValueError:
        return single_date, single_date

    if end_date < start_date:
        end_date = start_date
    return start_date, end_date


def _calculate_time_hours(time_from, time_to):
    start_time = datetime.strptime(time_from, "%H:%M").time()
    end_time = datetime.strptime(time_to, "%H:%M").time()
    start_dt = datetime.combine(philippine_now().date(), start_time)
    end_dt = datetime.combine(philippine_now().date(), end_time)
    if end_dt <= start_dt:
        end_dt += timedelta(days=1)
    return round((end_dt - start_dt).total_seconds() / 3600, 2)


def _build_ai_esarf_draft(prompt):
    text = (prompt or "").lower()
    is_use_offset = "use offset" in text or "use my offset" in text
    is_offset = (
        is_use_offset
        or "offset" in text
        or any(word in text for word in ("overtime", " ot ", " ot.", "file ot", "rendered ot"))
    )
    if not is_offset:
        return None

    time_range = _parse_ai_time_range(prompt)
    if not time_range:
        return None

    date_value = _parse_ai_request_date(prompt)
    time_from, time_to = time_range
    reason_source = ""
    reason_match = re.search(r"\b(?:due to|because of|because|for)\s+(.+)$", prompt, flags=re.IGNORECASE)
    if reason_match:
        reason_source = reason_match.group(1).strip().rstrip(".")
    transaction_type = "Use Offset" if is_use_offset else ("Offset" if "offset" in text and "overtime" not in text and " ot " not in text else "OT")
    reason_labels = {
        "OT": "overtime",
        "Offset": "offset",
        "Use Offset": "use offset",
    }
    reason = (
        f"Rendered {reason_labels[transaction_type]} for {reason_source}."
        if reason_source
        else f"Rendered {reason_labels[transaction_type]} for urgent work requirements."
    )

    employee_profile = current_user.employee
    payroll_class = "Managerial" if employee_profile and employee_profile.position and "manager" in employee_profile.position.lower() else "Rank and File"

    return {
        "time_schedule": "9AM - 6PM",
        "day_off": "Sun",
        "payroll_class": payroll_class,
        "transaction_types": [transaction_type],
        "date_from": date_value.strftime("%Y-%m-%d"),
        "date_to": date_value.strftime("%Y-%m-%d"),
        "time_from": time_from,
        "time_to": time_to,
        "total_hours": f"{_calculate_time_hours(time_from, time_to):.2f}",
        "reason": reason,
    }


def _build_ai_leave_draft(prompt):
    text = (prompt or "").lower()
    if "leave" not in text:
        return None

    start_date, end_date = _parse_ai_date_range(prompt)
    reason_source = ""
    reason_match = re.search(r"\b(?:because of|because|due to|for)\s+(.+)$", prompt, flags=re.IGNORECASE)
    if reason_match:
        reason_source = reason_match.group(1).strip().rstrip(".")

    category = "Vacation Leave"
    other_leave = ""
    if any(word in text for word in ("sick", "medical", "doctor", "hospital", "illness")):
        category = "Sick Leave"
    elif any(word in text for word in ("emergency", "urgent")):
        category = "Emergency Leave"
    elif any(word in text for word in ("maternity", "paternity")):
        category = "Maternity Leave"
    elif "birthday" in text:
        category = "Vacation Leave"
    elif reason_source:
        category = "Others"
        other_leave = "Personal Leave"

    return {
        "start_date": start_date.strftime("%Y-%m-%d"),
        "end_date": end_date.strftime("%Y-%m-%d"),
        "leave_type": "With Pay",
        "leave_category": category,
        "other_leave": other_leave,
        "reason": reason_source.capitalize() if reason_source else "Personal leave request.",
    }


def _can_auto_dept_approve_esarf():
    assignment = EsarfApprover.query.filter_by(user_id=current_user.id).first()
    if not assignment or assignment.approver_role != "dept manager":
        return False

    requester_department = _normalize_text(current_user.employee.department if current_user.employee else "")
    approver_department = _normalize_text(assignment.department_name)
    if approver_department and requester_department:
        return approver_department == requester_department
    return True


def _can_auto_first_approve_leave():
    assignment = LeaveApprover.query.filter_by(user_id=current_user.id).first()
    if not assignment:
        return False
    if assignment.approver_role == "hr":
        return True
    if assignment.approver_role != "department":
        return False

    requester_department = _normalize_text(current_user.employee.department if current_user.employee else "")
    approver_department = _normalize_text(assignment.department_name)
    if approver_department and requester_department:
        return approver_department == requester_department
    return True


def _activity_sort_date(value):
    if not value:
        return datetime.min
    if isinstance(value, datetime):
        return value
    return datetime.combine(value, datetime.min.time())


def _total_leave_days(start_date, end_date):
    return ((end_date - start_date).days + 1) if start_date and end_date else 0


def _build_leave_type_value(raw_leave_type, start_date, end_date):
    leave_type = (raw_leave_type or "").strip()
    if leave_type != "Both":
        return leave_type, None

    total_days = _total_leave_days(start_date, end_date)

    try:
        with_pay_days = int((request.form.get("with_pay_days") or "0").strip())
        without_pay_days = int((request.form.get("without_pay_days") or "0").strip())
    except ValueError:
        return None, "Please enter valid numbers for With Pay and Without Pay days."

    if with_pay_days < 0 or without_pay_days < 0:
        return None, "Leave day split cannot be negative."
    if with_pay_days == 0 and without_pay_days == 0:
        return None, "Please provide your leave day split for Both pay type."
    if with_pay_days + without_pay_days != total_days:
        return None, f"Leave day split must equal total leave days ({total_days})."

    return f"Both (With Pay: {with_pay_days}, Without Pay: {without_pay_days})", None


@employee.route('/employee_dashboard')
@login_required
def employee_dashboard():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    emp = current_user.employee
    now = philippine_now()
    local_now = now
    greeting_label = 'Good morning'
    if local_now.hour >= 18:
        greeting_label = 'Good evening'
    elif local_now.hour >= 12:
        greeting_label = 'Good afternoon'

    year_start = datetime(now.year, 1, 1)
    year_end = datetime(now.year, 12, 31, 23, 59, 59)
    annual_cash_limit = 3000.0
    annual_cash_transaction_limit = 6
    per_charge_limit = 3000.0

    leave_counts = {
        'pending': LeaveRequest.query.filter_by(
            submitted_by_user_id=current_user.id,
            status='Pending',
        ).count(),
        'approved': LeaveRequest.query.filter(
            LeaveRequest.submitted_by_user_id == current_user.id,
            LeaveRequest.status.ilike('approved'),
        ).count(),
        'rejected': LeaveRequest.query.filter(
            LeaveRequest.submitted_by_user_id == current_user.id,
            LeaveRequest.status.ilike('rejected'),
        ).count(),
    }

    esarf_counts = {
        'pending': EsarfRequest.query.filter_by(
            submitted_by_user_id=current_user.id,
            status='Pending',
        ).count(),
        'approved': EsarfRequest.query.filter(
            EsarfRequest.submitted_by_user_id == current_user.id,
            EsarfRequest.status.ilike('approved'),
        ).count(),
        'rejected': EsarfRequest.query.filter(
            EsarfRequest.submitted_by_user_id == current_user.id,
            EsarfRequest.status.ilike('rejected'),
        ).count(),
    }
    offset_hours_this_year = float(current_user.offset_credits or 0)

    discount_transaction_count = DiscountRequest.query.filter(
        DiscountRequest.submitted_by_user_id == current_user.id,
        DiscountRequest.status.in_(['Pending', 'Approved']),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).count()
    discount_used = db.session.query(
        db.func.coalesce(db.func.sum(DiscountRequest.amount), 0)
    ).filter(
        DiscountRequest.submitted_by_user_id == current_user.id,
        DiscountRequest.status.in_(['Pending', 'Approved']),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).scalar()
    discount_used = float(discount_used or 0)
    discount_remaining = max(0, annual_cash_limit - discount_used)

    charge_transaction_count = ProductChargeRequest.query.filter(
        ProductChargeRequest.submitted_by_user_id == current_user.id,
        ProductChargeRequest.status.in_(['Pending', 'Approved']),
        ProductChargeRequest.created_at >= year_start,
        ProductChargeRequest.created_at <= year_end,
    ).count()

    profile_fields = [
        emp.first_name, emp.last_name, emp.employee_no, emp.company, emp.department,
        emp.position, emp.employee_type, emp.hired_date, emp.email, emp.phone,
        emp.present_address, emp.birth_date, emp.gender, emp.civil_status,
        emp.sss_no, emp.philhealth_no, emp.pagibig_no, emp.tin_no,
    ]
    completed_profile_fields = sum(1 for field in profile_fields if field)
    profile_completion = round((completed_profile_fields / len(profile_fields)) * 100)
    missing_profile_items = []
    for label, value in [
        ('employee number', emp.employee_no),
        ('company', emp.company),
        ('department', emp.department),
        ('position', emp.position),
        ('email', emp.email),
        ('phone', emp.phone),
        ('address', emp.present_address),
        ('government IDs', all([emp.sss_no, emp.philhealth_no, emp.pagibig_no, emp.tin_no])),
    ]:
        if not value:
            missing_profile_items.append(label)

    recent_leaves = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(LeaveRequest.id.desc()).limit(3).all()
    recent_esarfs = EsarfRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(EsarfRequest.id.desc()).limit(3).all()
    recent_discounts = DiscountRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(DiscountRequest.id.desc()).limit(3).all()
    recent_charges = ProductChargeRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(ProductChargeRequest.id.desc()).limit(3).all()

    recent_activity = []
    for item in recent_leaves:
        recent_activity.append({
            'type': 'Leave',
            'title': item.leave_category,
            'status': item.status,
            'date': item.start_date,
            'icon': 'fa-calendar-day',
        })
    for item in recent_esarfs:
        recent_activity.append({
            'type': 'ESARF',
            'title': item.esarf_number or 'ESARF Request',
            'status': item.status,
            'date': item.created_at,
            'icon': 'fa-file-signature',
        })
    for item in recent_discounts:
        recent_activity.append({
            'type': 'Discount',
            'title': item.product_name or 'Employee discount',
            'status': item.status,
            'date': item.created_at,
            'icon': 'fa-tags',
        })
    for item in recent_charges:
        recent_activity.append({
            'type': 'Charge',
            'title': item.product_name or 'Product charge',
            'status': item.status,
            'date': item.created_at,
            'icon': 'fa-receipt',
        })
    recent_activity = sorted(
        recent_activity,
        key=lambda activity: _activity_sort_date(activity['date']),
        reverse=True,
    )[:6]

    return render_template(
        'employee/dashboard.html',
        employee=emp,
        greeting_label=greeting_label,
        leave_counts=leave_counts,
        esarf_counts=esarf_counts,
        pending_offset_hours=float(offset_hours_this_year or 0),
        annual_cash_limit=annual_cash_limit,
        annual_cash_transaction_limit=annual_cash_transaction_limit,
        per_charge_limit=per_charge_limit,
        discount_used=discount_used,
        discount_remaining=discount_remaining,
        discount_transaction_count=discount_transaction_count,
        discount_transaction_remaining=max(0, annual_cash_transaction_limit - discount_transaction_count),
        charge_transaction_count=charge_transaction_count,
        charge_first_available=charge_transaction_count == 0,
        profile_completion=profile_completion,
        missing_profile_items=missing_profile_items[:4],
        recent_activity=recent_activity,
    )


@employee.route('/employee/settings')
@login_required
def settings():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect
    return render_template('employee/settings.html')


@employee.route('/employee/profile/<int:employee_id>')
@login_required
def view_employee(employee_id):
    employee_data = Employee.query.get_or_404(employee_id)
    return render_template('employee/employee_profile.html', employee=employee_data)


@employee.route('/employee/profile/<int:employee_id>/update_info', methods=['POST'])
@login_required
def update_info(employee_id):
    employee_data = Employee.query.get_or_404(employee_id)

    if current_user.role == 'user' and current_user.employee_id != employee_id:
        flash('You can only update your own information.', category='error')
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

    first_name = (request.form.get('first_name') or '').strip()
    middle_name = (request.form.get('middle_name') or '').strip()
    last_name = (request.form.get('last_name') or '').strip()
    username = (request.form.get('username') or '').strip()
    new_password = request.form.get('new_password') or ''
    confirm_password = request.form.get('confirm_password') or ''

    if not first_name or not last_name:
        flash('First Name and Last Name are required.', category='error')
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

    if not username or len(username) < 4:
        flash('Username must be at least 4 characters.', category='error')
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

    # Check username uniqueness (exclude current user)
    existing_user = User.query.filter(User.username == username, User.id != employee_data.user.id).first() if employee_data.user else None
    if existing_user:
        flash('Username is already taken.', category='error')
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

    # Password: only update if both fields are filled and match
    if new_password or confirm_password:
        if new_password != confirm_password:
            flash('Passwords do not match.', category='error')
            return redirect(url_for('employee.view_employee', employee_id=employee_id))
        if len(new_password) < 7:
            flash('Password must be at least 7 characters.', category='error')
            return redirect(url_for('employee.view_employee', employee_id=employee_id))

    try:
        employee_data.first_name = first_name
        employee_data.middle_name = middle_name or None
        employee_data.last_name = last_name

        # Photo upload
        photo_file = request.files.get('photo')
        if photo_file and photo_file.filename:
            photo_path, photo_error = _save_employee_photo(photo_file)
            if photo_error:
                flash(photo_error, category='error')
                return redirect(url_for('employee.view_employee', employee_id=employee_id))
            if photo_path:
                employee_data.photopath = photo_path

        if employee_data.user:
            employee_data.user.username = username
            if new_password:
                employee_data.user.password = generate_password_hash(new_password, method='pbkdf2:sha256')

        db.session.commit()
        flash('Information updated successfully.', category='success')
    except Exception:
        db.session.rollback()
        flash('Failed to update information. Please try again.', category='error')

    return redirect(url_for('employee.view_employee', employee_id=employee_id))


@employee.route('/employee/profile/<int:employee_id>/update_section/<section>', methods=['POST'])
@login_required
def update_section(employee_id, section):
    employee_data = Employee.query.get_or_404(employee_id)

    requested_anchor = (request.form.get('active_section') or '').strip().lower()

    def _profile_redirect():
        if requested_anchor:
            return redirect(url_for('employee.view_employee', employee_id=employee_id, _anchor=requested_anchor))
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

    if current_user.role == 'user' and current_user.employee_id != employee_id:
        flash('You can only edit your own profile.', category='error')
        return _profile_redirect()

    SECTION_FIELDS = {
        'personal': ['birth_date', 'age', 'gender', 'religion', 'birth_place',
                     'nationality', 'civil_status', 'height', 'weight', 'educational_attainment'],
        'contact': ['email', 'phone', 'house_phone',
                    'social_media_type', 'social_media_detail',
                    'present_address', 'zipCode', 'permanent_address'],
        'employment': ['company', 'employee_type', 'hired_date', 'location',
                       'department', 'position'],
        'government': ['sss_no', 'philhealth_no', 'pagibig_no', 'tin_no',
                       'valid_id_no', 'valid_id_type', 'account_no', 'bank_type'],
        'education': ['elementary_school', 'elementary_year_attended',
                      'secondary_school', 'secondary_year_attended',
                      'college_school', 'college_year_attended',
                      'college_course', 'year_graduated'],
        'family': ['father_name', 'father_occupation', 'mother_maiden_name',
                   'mother_occupation', 'no_of_siblings', 'sibling_birth_order'],
        'spouse': ['spouse_full_name', 'spouse_age', 'spouse_birth_date',
                   'spouse_school', 'spouse_course_degree', 'spouse_occupation'],
        'children': ['no_of_children', 'no_of_male_children', 'no_of_female_children'],
    }

    INT_FIELDS = {'age', 'spouse_age', 'no_of_children', 'no_of_male_children', 'no_of_female_children',
                  'sss_no', 'philhealth_no', 'pagibig_no', 'tin_no', 'valid_id_no', 'account_no', 'zipCode'}
    DATE_FIELDS = {'birth_date', 'hired_date', 'spouse_birth_date'}

    fields = SECTION_FIELDS.get(section, [])
    if not fields:
        flash('Unknown section.', category='error')
        return _profile_redirect()

    try:
        for field in fields:
            if not hasattr(employee_data, field):
                continue
            value = request.form.get(field)
            if value is None:
                continue
            if value == '':
                setattr(employee_data, field, None)
                continue
            if field in DATE_FIELDS:
                value = datetime.strptime(value, '%Y-%m-%d').date()
            elif field in INT_FIELDS:
                value = int(value)
            setattr(employee_data, field, value)

        if section == 'employment' and _should_refresh_employee_no(
            employee_data.employee_no,
            employee_data.hired_date,
        ):
            employee_data.employee_no = _next_employee_no_for_date(
                employee_data.hired_date,
                exclude_employee_id=employee_data.id,
            )

        if section == 'employment':
            sync_department_name(employee_data.department)

        if section == 'children':
            names = request.form.getlist('child_full_name[]')
            ages = request.form.getlist('child_age[]')
            birth_dates = request.form.getlist('child_birth_date[]')
            schools = request.form.getlist('child_school[]')
            school_levels = request.form.getlist('child_school_level[]')
            occupations = request.form.getlist('child_occupation[]')
            children_list = []
            for i in range(len(names)):
                child = {}
                if i < len(names) and names[i]:
                    child['full_name'] = names[i]
                if i < len(ages) and ages[i]:
                    child['age'] = ages[i]
                if i < len(birth_dates) and birth_dates[i]:
                    child['birth_date'] = birth_dates[i]
                if i < len(schools) and schools[i]:
                    child['school'] = schools[i]
                if i < len(school_levels) and school_levels[i]:
                    child['school_level'] = school_levels[i]
                if i < len(occupations) and occupations[i]:
                    child['occupation'] = occupations[i]
                if child:
                    children_list.append(child)
            employee_data.children_details = children_list if children_list else None

        db.session.commit()
        flash(section.replace('_', ' ').title() + ' updated successfully.', category='success')
    except Exception:
        db.session.rollback()
        flash('Failed to update ' + section.replace('_', ' ').title() + '. Please check your inputs.', category='error')

    return _profile_redirect()


@employee.route('/employee/esarf_requests')
@login_required
def esarf_requests():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect
    # Get ESARF requests submitted by the current user
    esarf_requests = EsarfRequest.query.filter_by(submitted_by_user_id=current_user.id).order_by(EsarfRequest.id.desc()).all()
    return render_template('employee/esarf_requests.html', esarf_requests=esarf_requests)

@employee.route('/employee/esarf_detail/<int:req_id>')
@login_required
def esarf_detail(req_id):
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect
    esarf_req = EsarfRequest.query.get_or_404(req_id)
    # Ensure the request belongs to the current user
    if esarf_req.submitted_by_user_id != current_user.id:
        flash('You are not authorized to view this request.', category='error')
        return redirect(url_for('employee.esarf_requests'))
    return render_template('employee/esarf_detail.html', esarf_request=esarf_req)


@employee.route('/employee/esarf', methods=['GET', 'POST'])
@login_required
def esarf():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    esarf_form = {}
    esarf_transaction_types = []
    if request.method == 'GET' and request.args.get('ai_draft') == '1':
        draft = session.pop('ai_esarf_draft', None)
        if isinstance(draft, dict):
            esarf_form = {
                'time_schedule': draft.get('time_schedule', ''),
                'day_off': draft.get('day_off', ''),
                'payroll_class': draft.get('payroll_class', ''),
                'date_from': draft.get('date_from', ''),
                'date_to': draft.get('date_to', ''),
                'time_from': draft.get('time_from', ''),
                'time_to': draft.get('time_to', ''),
                'total_hours': draft.get('total_hours', ''),
                'reason': draft.get('reason', ''),
            }
            esarf_transaction_types = draft.get('transaction_types', [])
            flash('HYG Assist prepared your ESARF draft. Please review and submit when ready.', category='info')

    def calculate_esarf_hours(start_time, end_time):
        if not start_time or not end_time:
            return None

        start_dt = datetime.combine(datetime.today(), start_time)
        end_dt = datetime.combine(datetime.today(), end_time)
        if end_dt <= start_dt:
            end_dt = end_dt + timedelta(days=1)

        return round((end_dt - start_dt).total_seconds() / 3600, 2)

    available_offset_hours = max(0.0, float(current_user.offset_credits or 0))

    if request.method == 'POST':
        time_schedule = request.form.get('time_schedule')
        day_off = request.form.get('day_off')
        payroll_class = request.form.get('payroll_class')
        transaction_types = request.form.getlist('transaction_type')
        date_from_raw = request.form.get('date_from')
        date_to_raw = request.form.get('date_to')
        time_from_raw = request.form.get('time_from')
        time_to_raw = request.form.get('time_to')
        total_hours_raw = request.form.get('total_hours')
        reason = request.form.get('reason') or 'Auto-saved ESARF request'

        esarf_form = {
            'time_schedule': time_schedule or '',
            'day_off': day_off or '',
            'payroll_class': payroll_class or '',
            'date_from': date_from_raw or '',
            'date_to': date_to_raw or '',
            'time_from': time_from_raw or '',
            'time_to': time_to_raw or '',
            'total_hours': total_hours_raw or '',
            'reason': reason or '',
        }
        esarf_transaction_types = transaction_types

        try:
            date_from = datetime.strptime(date_from_raw, '%Y-%m-%d').date() if date_from_raw else None
            date_to = datetime.strptime(date_to_raw, '%Y-%m-%d').date() if date_to_raw else None
            time_from = datetime.strptime(time_from_raw, '%H:%M').time() if time_from_raw else None
            time_to = datetime.strptime(time_to_raw, '%H:%M').time() if time_to_raw else None
            total_hours = float(total_hours_raw) if total_hours_raw else calculate_esarf_hours(time_from, time_to)

            if date_from and date_to and date_to < date_from:
                flash('Date To cannot be earlier than Date From.', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            transaction_types_csv = ','.join(transaction_types)
            transaction_type_labels = {
                'UT': 'Undertime (UT)',
                'OT': 'Overtime (OT)',
                'FIO': 'Failure to Punch In/Out (FIO)',
                'OB': 'Official Business (OB)',
                'Adjustment': 'Adjustment',
                'Offset': 'Offset',
                'Use Offset': 'Use Offset',
            }
            transaction_types_display = ', '.join(
                transaction_type_labels.get(transaction_type, transaction_type)
                for transaction_type in transaction_types
            )

            if not transaction_types_csv:
                flash('Please select at least one transaction type.', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            has_offset = 'Offset' in transaction_types
            has_ot_or_ut = 'OT' in transaction_types or 'UT' in transaction_types
            if has_offset and has_ot_or_ut:
                flash('Offset cannot be combined with Overtime (OT) or Undertime (UT).', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            has_use_offset = 'Use Offset' in transaction_types
            if has_use_offset and (has_offset or has_ot_or_ut):
                flash('Use Offset cannot be combined with Offset, Overtime (OT), or Undertime (UT).', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            if has_use_offset and total_hours is not None and total_hours > available_offset_hours:
                flash(
                    f'Insufficient offset credits. Available: {available_offset_hours:.2f} hrs, Requested: {total_hours:.2f} hrs.',
                    category='error',
                )
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            if not all([time_schedule, day_off, payroll_class, date_from, date_to, time_from, time_to, reason]) or total_hours is None:
                flash('Unable to submit ESARF. Please complete all required fields.', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                    available_offset_hours=available_offset_hours,
                )

            if has_use_offset:
                request_status = "Approved"
            else:
                request_status = ESARF_STATUS_DEPT_MGR_APPROVED if _can_auto_dept_approve_esarf() else "Pending"

            new_request = EsarfRequest(
                submitted_by_user_id=current_user.id,
                status=request_status,
                time_schedule=time_schedule,
                day_off=day_off,
                payroll_class=payroll_class,
                transaction_types=transaction_types_csv,
                date_from=date_from,
                date_to=date_to,
                time_from=time_from,
                time_to=time_to,
                total_hours=total_hours,
                reason=reason,
            )
            db.session.add(new_request)
            db.session.flush()
            new_request.esarf_number = f"ESARF-{datetime.utcnow().year}-{new_request.id:03d}"
            if has_use_offset and request_status == "Approved":
                current_user.offset_credits = max(0.0, float(current_user.offset_credits or 0) - float(total_hours or 0))
            db.session.commit()

            if new_request.status == "Approved" and has_use_offset:
                flash(
                    f'ESARF request {new_request.esarf_number} submitted and auto-approved for Use Offset. '
                    f'Transaction Type: {transaction_types_display}',
                    category='success',
                )
            elif new_request.status == ESARF_STATUS_DEPT_MGR_APPROVED:
                flash(
                    f'ESARF request {new_request.esarf_number} submitted and auto-approved at Department Manager stage. '
                    f'Transaction Type: {transaction_types_display}',
                    category='success',
                )
            else:
                flash(
                    f'ESARF request {new_request.esarf_number} submitted successfully. Transaction Type: {transaction_types_display}',
                    category='success',
                )
            return redirect(url_for('employee.esarf_requests'))
        except Exception:
            db.session.rollback()
            flash('Unable to submit ESARF. Please check your inputs and try again.', category='error')
            return render_template(
                'employee/esarf.html',
                esarf_form=esarf_form,
                esarf_transaction_types=esarf_transaction_types,
                available_offset_hours=available_offset_hours,
            )

    return render_template(
        'employee/esarf.html',
        esarf_form=esarf_form,
        esarf_transaction_types=esarf_transaction_types,
        available_offset_hours=available_offset_hours,
    )


@employee.route('/submit_leave', methods=['POST'])
@login_required
def submit_leave():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    try:
        start_date = datetime.strptime(request.form.get("start_date"), "%Y-%m-%d").date()
        end_date = datetime.strptime(request.form.get("end_date"), "%Y-%m-%d").date()
        leave_type = request.form.get("leave_type")  # Fixed typo: was leave_date
        leave_category = request.form.get("leave_category")
        other_leave = request.form.get("other_leave")
        reason = request.form.get("reason")

        if end_date < start_date:
            flash("End date cannot be earlier than start date.", category="error")
            return redirect(url_for("employee.leaves"))

        if not leave_type:
            flash("Please choose a leave pay type.", category="error")
            return redirect(url_for("employee.leaves"))

        if leave_category == "Others" and not other_leave:
            flash("Please specify your 'Other' leave type.", category="error")
            return redirect(url_for("employee.leaves"))

        # Use the 'other_leave' value if "Others" selected
        final_category = other_leave if leave_category == "Others" else leave_category
        final_leave_type, leave_type_error = _build_leave_type_value(leave_type, start_date, end_date)
        if leave_type_error:
            flash(leave_type_error, category="error")
            return redirect(url_for("employee.leaves"))

        new_leave_request = LeaveRequest(
            submitted_by_user_id=current_user.id,
            status=LEAVE_STATUS_DEPT_HR_APPROVED if _can_auto_first_approve_leave() else "Pending",
            start_date=start_date,
            end_date=end_date,
            leave_type=final_leave_type,
            leave_category=final_category,
            reason=reason,
        )

        db.session.add(new_leave_request)
        db.session.flush()
        create_notification(
            current_user.id,
            "Leave sent",
            f"You requested {final_category} leave.",
            category="success",
            link_url=url_for("employee.leave_requests"),
        )
        db.session.commit()
        if new_leave_request.status == LEAVE_STATUS_DEPT_HR_APPROVED:
            flash(
                "Leave request submitted and auto-approved at Department/HR stage.",
                category="success",
            )
        else:
            flash("Leave request submitted successfully.", category="success")

    except Exception as e:
        db.session.rollback()
        flash("Failed to submit leave. Check your inputs.", category="error")

    return redirect(url_for("employee.leaves"))


@employee.route('/employee/leave_requests/<int:leave_id>/update', methods=['POST'])
@login_required
def update_leave_request(leave_id):
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    leave_request = LeaveRequest.query.get_or_404(leave_id)
    if leave_request.submitted_by_user_id != current_user.id:
        flash("You are not allowed to modify this leave request.", category="error")
        return redirect(url_for("employee.leave_requests"))

    if (leave_request.status or "").lower() != "pending":
        flash("Only pending leave requests can be edited.", category="error")
        return redirect(url_for("employee.leave_requests"))

    leave_type = request.form.get("leave_type")
    leave_category = request.form.get("leave_category")
    other_leave = request.form.get("other_leave")
    reason = request.form.get("reason")

    if not leave_type:
        flash("Please choose a leave pay type.", category="error")
        return redirect(url_for("employee.leave_requests"))

    if leave_category == "Others" and not other_leave:
        flash("Please specify your 'Other' leave type.", category="error")
        return redirect(url_for("employee.leave_requests"))

    final_leave_type, leave_type_error = _build_leave_type_value(
        leave_type,
        leave_request.start_date,
        leave_request.end_date,
    )
    if leave_type_error:
        flash(leave_type_error, category="error")
        return redirect(url_for("employee.leave_requests"))

    leave_request.leave_type = final_leave_type
    leave_request.leave_category = other_leave if leave_category == "Others" else leave_category
    leave_request.reason = reason

    try:
        db.session.commit()
        flash("Leave request updated successfully.", category="success")
    except Exception:
        db.session.rollback()
        flash("Unable to update leave request. Please try again.", category="error")

    return redirect(url_for("employee.leave_requests"))


@employee.route('/employee/leave_requests', methods=['GET'])
@login_required
def leave_requests():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    leave_request_items = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id
    ).order_by(LeaveRequest.id.desc()).all()

    return render_template(
        'employee/leave_requests.html',
        leave_requests=leave_request_items,
    )



@employee.route('/leaves', methods=['GET', 'POST'])
@login_required
def leaves():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    leave_form = {}
    if request.args.get('ai_draft') == '1':
        draft = session.pop('ai_leave_draft', None)
        if isinstance(draft, dict):
            leave_form = {
                'start_date': draft.get('start_date', ''),
                'end_date': draft.get('end_date', ''),
                'leave_type': draft.get('leave_type', ''),
                'leave_category': draft.get('leave_category', ''),
                'other_leave': draft.get('other_leave', ''),
                'reason': draft.get('reason', ''),
            }
            flash('HYG Assist prepared your leave draft. Please review and submit when ready.', category='info')

    # Pagination parameters
    page = request.args.get('page', 1, type=int)  # Get the current page, default=1
    per_page = 5  # Number of leave requests per page, adjust as needed

    # Paginate leave requests
    leave_requests = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id
    ).order_by(LeaveRequest.id.desc()).paginate(page=page, per_page=per_page)

    # Count statuses (can remain as-is)
    pending_count = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id, status="Pending"
    ).count()
    approved_count = LeaveRequest.query.filter(
        LeaveRequest.submitted_by_user_id == current_user.id,
        LeaveRequest.status.ilike("approved"),
    ).count()
    rejected_count = LeaveRequest.query.filter(
        LeaveRequest.submitted_by_user_id == current_user.id,
        LeaveRequest.status.ilike("rejected"),
    ).count()

    return render_template(
        "leaves.html",
        user=current_user,
        leaves=leave_requests.items,  # Only the items for the current page
        pagination=leave_requests,    # Pass the pagination object for controls
        pending_count=pending_count,
        approved_count=approved_count,
        rejected_count=rejected_count,
        leave_form=leave_form,
    )


@employee.route('/employee/proxy_inventory', methods=['GET'])
@login_required
def proxy_inventory():
    import json
    import os
    from urllib.request import urlopen, Request
    from urllib.error import URLError

    inventory_url = os.environ.get(
        'INVENTORY_API_URL',
        'https://luigiandreyopalia.pythonanywhere.com/inventory/store_inventory_data'
    )

    try:
        req = Request(inventory_url, headers={'Accept': 'application/json'})
        with urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data, 200
    except URLError:
        return {"success": True, "inventories": []}, 200
    except Exception:
        return {"success": True, "inventories": []}, 200


@employee.route('/employee/perks', methods=['GET', 'POST'])
@login_required
def perks():
    emp = current_user.employee if current_user.is_authenticated else None

    # Current year limits automatically reset because every cap is scoped to this year.
    now = philippine_now()
    year_start = datetime(now.year, 1, 1)
    year_end = datetime(now.year, 12, 31, 23, 59, 59)
    annual_cash_limit = 3000.0
    annual_cash_transaction_limit = 6
    per_charge_limit = 3000.0

    discount_transaction_count = DiscountRequest.query.filter(
        DiscountRequest.submitted_by_user_id == current_user.id,
        DiscountRequest.status.in_(['Pending', 'Approved']),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).count()
    discount_used = db.session.query(
        db.func.coalesce(db.func.sum(DiscountRequest.amount), 0)
    ).filter(
        DiscountRequest.submitted_by_user_id == current_user.id,
        DiscountRequest.status.in_(['Pending', 'Approved']),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).scalar()
    discount_used = float(discount_used or 0)
    discount_remaining = max(0, annual_cash_limit - discount_used)
    discount_transaction_remaining = max(0, annual_cash_transaction_limit - discount_transaction_count)

    charge_transaction_count = ProductChargeRequest.query.filter(
        ProductChargeRequest.submitted_by_user_id == current_user.id,
        ProductChargeRequest.status.in_(['Pending', 'Approved']),
        ProductChargeRequest.created_at >= year_start,
        ProductChargeRequest.created_at <= year_end,
    ).count()
    charge_first_available = charge_transaction_count == 0

    def _generate_unique_perk_code():
        rng = random.SystemRandom()
        while True:
            code = f"{rng.randint(0, 999999):06d}"
            discount_exists = DiscountRequest.query.filter_by(approval_code=code).first()
            charge_exists = ProductChargeRequest.query.filter_by(approval_code=code).first()
            if not discount_exists and not charge_exists:
                return code

    def _send_perk_approval_code(email_address, code, request_label):
        message = EmailMessage()
        message["Subject"] = f"Your {request_label} approval code"
        message["From"] = f"{PERK_APPROVAL_SENDER} <{PERK_APPROVAL_EMAIL}>"
        message["To"] = email_address
        message.set_content(
            "This is an automated message from HYG Employee Portal.\n\n"
            f"Your approval code for {request_label} is: {code}\n\n"
            "Enter this code in the Employee Perks page to complete your request.\n"
            "Please do not reply to this email."
        )

        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(PERK_APPROVAL_EMAIL, PERK_APPROVAL_PASSWORD)
            smtp.send_message(message)

    def _employee_display_name():
        if not emp:
            return current_user.username
        return (
            f"{emp.first_name or ''} "
            f"{(emp.middle_name[:1] + '.') if emp.middle_name else ''} "
            f"{emp.last_name or ''} "
            f"{emp.suffix or ''}"
        ).strip() or current_user.username

    def _send_perk_slip(email_address, payload, approval_code):
        request_label = payload.get('request_label') or (
            'Employee Discount (Cash)' if payload['form_type'] == 'discount' else 'Employee Charge (Credit)'
        )
        employee_name = _employee_display_name()
        employee_no = emp.employee_no if emp and emp.employee_no else 'N/A'
        department = emp.department if emp and emp.department else 'N/A'
        company = emp.company if emp and emp.company else 'N/A'
        transaction_date = payload.get('transaction_date') or 'N/A'
        product_summary = payload.get('product_name') or 'N/A'

        if payload['form_type'] == 'discount':
            amount = float(payload.get('amount') or 0)
            final_amount = float(payload.get('discounted_amount') or 0)
            benefit_line = '15% Employee Discount'
            total_label = 'Cashier amount after discount'
            amount_rows = (
                f"<tr><td>Purchase amount</td><td>PHP {amount:.2f}</td></tr>"
                f"<tr><td>Discounted amount</td><td>PHP {final_amount:.2f}</td></tr>"
            )
        else:
            original_amount = float(payload.get('original_amount') or payload.get('total_amount') or 0)
            final_amount = float(payload.get('total_amount') or 0)
            benefit_line = '15% first-transaction discount' if payload.get('discount_applies') else 'No discount'
            total_label = 'Approved credit amount'
            amount_rows = (
                f"<tr><td>Credit amount</td><td>PHP {original_amount:.2f}</td></tr>"
                f"<tr><td>{total_label}</td><td>PHP {final_amount:.2f}</td></tr>"
            )

        html = f"""
        <html>
          <body style="margin:0;padding:24px;background:#f5f7fb;font-family:Arial,sans-serif;color:#0f172a;">
            <div style="max-width:680px;margin:0 auto;background:#ffffff;border:1px solid #dbe4f0;border-radius:14px;overflow:hidden;">
              <div style="padding:22px 26px;background:#0f172a;color:#ffffff;">
                <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#cbd5e1;">HYG Employee Portal</div>
                <h1 style="margin:8px 0 0;font-size:24px;line-height:1.2;">{request_label} Slip</h1>
                <p style="margin:8px 0 0;color:#e2e8f0;">Show this approved slip to the cashier.</p>
              </div>
              <div style="padding:24px 26px;">
                <div style="display:block;padding:18px;border:1px solid #bfdbfe;border-radius:12px;background:#eff6ff;text-align:center;margin-bottom:20px;">
                  <div style="font-size:12px;font-weight:700;color:#475569;">Approval Code</div>
                  <div style="margin-top:6px;font-size:34px;letter-spacing:.18em;font-weight:800;color:#1d4ed8;">{approval_code}</div>
                  <div style="margin-top:8px;font-size:13px;color:#475569;">Status: <strong style="color:#16a34a;">Approved</strong></div>
                </div>
                <table style="width:100%;border-collapse:collapse;font-size:14px;">
                  <tr><td style="padding:9px 0;color:#64748b;">Employee</td><td style="padding:9px 0;text-align:right;font-weight:700;">{employee_name}</td></tr>
                  <tr><td style="padding:9px 0;color:#64748b;">Employee No.</td><td style="padding:9px 0;text-align:right;font-weight:700;">{employee_no}</td></tr>
                  <tr><td style="padding:9px 0;color:#64748b;">Department</td><td style="padding:9px 0;text-align:right;font-weight:700;">{department}</td></tr>
                  <tr><td style="padding:9px 0;color:#64748b;">Company</td><td style="padding:9px 0;text-align:right;font-weight:700;">{company}</td></tr>
                  <tr><td style="padding:9px 0;color:#64748b;">Transaction date</td><td style="padding:9px 0;text-align:right;font-weight:700;">{transaction_date}</td></tr>
                  <tr><td style="padding:9px 0;color:#64748b;">Benefit</td><td style="padding:9px 0;text-align:right;font-weight:700;">{benefit_line}</td></tr>
                </table>
                <div style="margin-top:18px;padding:16px;border:1px solid #e2e8f0;border-radius:12px;background:#f8fafc;">
                  <div style="font-size:12px;font-weight:800;color:#64748b;margin-bottom:8px;">Items</div>
                  <div style="font-size:14px;line-height:1.5;font-weight:700;">{product_summary}</div>
                </div>
                <table style="width:100%;border-collapse:collapse;font-size:15px;margin-top:18px;">
                  {amount_rows}
                </table>
                <div style="margin-top:22px;padding:14px;border-radius:10px;background:#fff7ed;color:#92400e;font-size:13px;line-height:1.45;">
                  Cashier note: Verify the approval code and employee identity before honoring this slip.
                </div>
              </div>
            </div>
            <p style="max-width:680px;margin:14px auto 0;text-align:center;color:#94a3b8;font-size:12px;">This is an automated no-reply email.</p>
          </body>
        </html>
        """

        text = (
            f"{request_label} Slip\n"
            f"Status: Approved\n"
            f"Approval Code: {approval_code}\n"
            f"Employee: {employee_name}\n"
            f"Employee No.: {employee_no}\n"
            f"Department: {department}\n"
            f"Company: {company}\n"
            f"Transaction date: {transaction_date}\n"
            f"Items: {product_summary}\n"
            f"{total_label}: PHP {final_amount:.2f}\n"
            "Show this approved slip to the cashier."
        )

        message = EmailMessage()
        message["Subject"] = f"Approved {request_label} Slip - Code {approval_code}"
        message["From"] = f"{PERK_APPROVAL_SENDER} <{PERK_APPROVAL_EMAIL}>"
        message["To"] = email_address
        message.set_content(text)
        message.add_alternative(html, subtype="html")

        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(PERK_APPROVAL_EMAIL, PERK_APPROVAL_PASSWORD)
            smtp.send_message(message)

    def _start_perk_verification(payload):
        applicant_email = (emp.email if emp and emp.email else "").strip()
        if not applicant_email:
            flash('Your employee profile does not have a registered email address. Please add an email before submitting a perk request.', category='error')
            return False

        code = _generate_unique_perk_code()
        request_label = 'Employee Discount (Cash)' if payload['form_type'] == 'discount' else 'Employee Charge (Credit)'
        try:
            _send_perk_approval_code(applicant_email, code, request_label)
        except Exception:
            flash('Unable to send the approval code. Please check the registered email or try again later.', category='error')
            return False

        payload['approval_code'] = code
        payload['email'] = applicant_email
        payload['request_label'] = request_label
        session['pending_perk_request'] = payload
        session.modified = True
        flash(f'Approval code sent to {applicant_email}. Enter the code to complete your request.', category='info')
        return True

    # Check if user has pending discount
    pending_discount = DiscountRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
        status='Pending',
    ).first()

    if request.method == 'POST':
        form_type = request.form.get('form_type')

        if form_type == 'cancel_perk_code':
            session.pop('pending_perk_request', None)
            flash('Perk request verification cancelled.', category='info')
            return redirect(url_for('employee.perks'))

        if form_type == 'resend_perk_code':
            pending_payload = session.get('pending_perk_request')
            if not pending_payload:
                flash('No perk request is waiting for verification.', category='error')
                return redirect(url_for('employee.perks'))
            pending_payload.pop('approval_code', None)
            if _start_perk_verification(pending_payload):
                flash('A new approval code was sent.', category='success')
            return redirect(url_for('employee.perks'))

        if form_type == 'verify_perk_code':
            pending_payload = session.get('pending_perk_request')
            approval_code = (request.form.get('approval_code') or '').strip()
            if not pending_payload:
                flash('No perk request is waiting for verification.', category='error')
                return redirect(url_for('employee.perks'))
            if approval_code != pending_payload.get('approval_code'):
                flash('Invalid approval code. Please try again.', category='error')
                return redirect(url_for('employee.perks'))

            try:
                transaction_date = datetime.strptime(pending_payload['transaction_date'], '%Y-%m-%d').date()
                if pending_payload['form_type'] == 'discount':
                    new_discount = DiscountRequest(
                        submitted_by_user_id=current_user.id,
                        status='Approved',
                        discount_type='Employee Discount (Cash)',
                        discount_percent=15.0,
                        product_name=pending_payload['product_name'],
                        quantity=int(pending_payload['quantity']),
                        price=float(pending_payload['price']),
                        transaction_date=transaction_date,
                        amount=float(pending_payload['amount']),
                        discounted_amount=float(pending_payload['discounted_amount']),
                        approval_code=approval_code,
                    )
                    db.session.add(new_discount)
                    db.session.flush()
                    create_notification(
                        current_user.id,
                        "Perk approved",
                        "Your discount request was approved.",
                        category="approved",
                        link_url=url_for("employee.perks"),
                    )
                    success_message = 'Employee discount request verified and submitted.'
                else:
                    new_charge = ProductChargeRequest(
                        submitted_by_user_id=current_user.id,
                        status='Approved',
                        product_name=pending_payload['product_name'],
                        quantity=int(pending_payload['quantity']),
                        price=float(pending_payload['price']),
                        total_amount=float(pending_payload['total_amount']),
                        transaction_date=transaction_date,
                        approval_code=approval_code,
                    )
                    db.session.add(new_charge)
                    db.session.flush()
                    create_notification(
                        current_user.id,
                        "Perk approved",
                        "Your charge request was approved.",
                        category="approved",
                        link_url=url_for("employee.perks"),
                    )
                    success_message = 'Employee charge request verified and submitted.'

                db.session.commit()
                try:
                    _send_perk_slip(pending_payload['email'], pending_payload, approval_code)
                except Exception:
                    flash('Request approved and saved, but the cashier slip email could not be sent. Please contact HR.', category='error')
                    session.pop('pending_perk_request', None)
                    return redirect(url_for('employee.perks'))

                session.pop('pending_perk_request', None)
                flash(f'{success_message} Cashier slip sent to {pending_payload["email"]}.', category='success')
            except Exception:
                db.session.rollback()
                flash('Failed to save the verified perk request. Please try again.', category='error')
            return redirect(url_for('employee.perks'))

        def _parse_perk_products(form_prefix):
            names = request.form.getlist(f'{form_prefix}_product_name[]')
            quantities = request.form.getlist(f'{form_prefix}_quantity[]')
            prices = request.form.getlist(f'{form_prefix}_price[]')

            if not names:
                names = [request.form.get('product_name')]
                quantities = [request.form.get('quantity')]
                prices = [request.form.get('price')]

            products = []
            total_quantity = 0
            total_amount = 0.0

            for name_raw, quantity_raw, price_raw in zip(names, quantities, prices):
                product_name = (name_raw or '').strip()
                if not product_name and not quantity_raw and not price_raw:
                    continue
                if not product_name or not quantity_raw or not price_raw:
                    raise ValueError('missing')

                quantity = int(quantity_raw)
                price = float(price_raw)
                if quantity <= 0 or price <= 0:
                    raise ValueError('invalid')

                line_total = round(quantity * price, 2)
                products.append({
                    'name': product_name,
                    'quantity': quantity,
                    'price': price,
                    'line_total': line_total,
                })
                total_quantity += quantity
                total_amount += line_total

            if not products:
                raise ValueError('missing')

            product_summary = '; '.join(
                f"{item['name']} x{item['quantity']} @ {item['price']:.2f}"
                for item in products
            )
            average_price = round(total_amount / total_quantity, 2) if total_quantity else 0
            return product_summary, total_quantity, average_price, round(total_amount, 2)

        if form_type == 'discount':
            if pending_discount:
                flash('You already have a pending employee discount request. Wait for it to be processed before submitting another.', category='error')
                return redirect(url_for('employee.perks'))
            if discount_transaction_remaining <= 0:
                flash('You have reached the maximum of 6 employee discount transactions for this year.', category='error')
                return redirect(url_for('employee.perks'))
            if discount_remaining <= 0:
                flash('You have reached the PHP 3,000 yearly employee discount limit.', category='error')
                return redirect(url_for('employee.perks'))

            transaction_date_raw = request.form.get('transaction_date')

            if not transaction_date_raw:
                flash('Please fill in all discount fields.', category='error')
                return redirect(url_for('employee.perks'))

            try:
                product_name, quantity, price, amount = _parse_perk_products('discount')
                transaction_date = datetime.strptime(transaction_date_raw, '%Y-%m-%d').date()
                if amount > discount_remaining:
                    flash(f'This discount request exceeds your remaining yearly cash discount limit of PHP {discount_remaining:.2f}.', category='error')
                    return redirect(url_for('employee.perks'))
                discounted_amount = round(amount * 0.85, 2)

                payload = {
                    'form_type': 'discount',
                    'product_name': product_name,
                    'quantity': quantity,
                    'price': price,
                    'transaction_date': transaction_date_raw,
                    'amount': amount,
                    'discounted_amount': discounted_amount,
                }
                _start_perk_verification(payload)
            except ValueError:
                flash('Invalid amount or date. Please check your inputs.', category='error')
            except Exception:
                db.session.rollback()
                flash('Failed to submit discount request. Please try again.', category='error')

            return redirect(url_for('employee.perks'))

        elif form_type == 'charge':
            transaction_date_raw = request.form.get('transaction_date')

            if not transaction_date_raw:
                flash('Please fill in all charge fields.', category='error')
                return redirect(url_for('employee.perks'))

            try:
                product_name, quantity, price, total_amount = _parse_perk_products('charge')
                transaction_date = datetime.strptime(transaction_date_raw, '%Y-%m-%d').date()
                if total_amount > per_charge_limit:
                    flash(f'Total amount ({total_amount:.2f}) exceeds the per-transaction credit limit of PHP {per_charge_limit:.2f}.', category='error')
                    return redirect(url_for('employee.perks'))

                charge_discount_applies = charge_first_available
                final_total_amount = round(total_amount * 0.85, 2) if charge_discount_applies else total_amount

                payload = {
                    'form_type': 'charge',
                    'product_name': product_name,
                    'quantity': quantity,
                    'price': price,
                    'transaction_date': transaction_date_raw,
                    'total_amount': final_total_amount,
                    'original_amount': total_amount,
                    'discount_applies': charge_discount_applies,
                }
                _start_perk_verification(payload)
            except ValueError:
                flash('Invalid quantity or price. Please check your inputs.', category='error')
            except Exception:
                db.session.rollback()
                flash('Failed to submit charge request. Please try again.', category='error')

            return redirect(url_for('employee.perks'))

    # GET: gather history (combined, newest 5)
    discounts = DiscountRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(DiscountRequest.id.desc()).all()

    charges = ProductChargeRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
    ).order_by(ProductChargeRequest.id.desc()).all()

    all_perks = sorted(
        list(discounts) + list(charges),
        key=lambda x: x.created_at if x.created_at else datetime.min,
        reverse=True,
    )[:5]

    recent_discounts = [p for p in all_perks if isinstance(p, DiscountRequest)]
    recent_charges = [p for p in all_perks if isinstance(p, ProductChargeRequest)]

    return render_template(
        'employee/perks.html',
        employee=emp,
        discount_remaining=discount_remaining,
        discount_used=discount_used,
        discount_transaction_count=discount_transaction_count,
        discount_transaction_remaining=discount_transaction_remaining,
        annual_cash_transaction_limit=annual_cash_transaction_limit,
        annual_cash_limit=annual_cash_limit,
        pending_discount=pending_discount,
        charge_transaction_count=charge_transaction_count,
        charge_first_available=charge_first_available,
        charge_credit_limit=per_charge_limit,
        pending_perk_approval=session.get('pending_perk_request'),
        discounts=recent_discounts,
        charges=recent_charges,
    )


@employee.route('/employee/ai-messages', methods=['GET'])
@login_required
def ai_messages():
    return render_template(
        'employee/ai_messages.html',
        ai_models=AI_MODEL_OPTIONS,
        default_ai_model=_ai_model_choice(None),
        ollama_url=AI_OLLAMA_URL,
    )


@employee.route('/employee/ai-messages/chat', methods=['POST'])
@login_required
def ai_messages_chat():
    data = request.get_json(silent=True) or {}
    prompt = (data.get('message') or '').strip()
    model = _ai_model_choice(data.get('model'))

    if not prompt:
        return jsonify({
            'success': False,
            'message': 'Tell HYG Assist what you need help with first.',
        }), 400

    account_answer = _answer_portal_account_question(prompt)
    if account_answer:
        return jsonify({
            'success': True,
            'reply': account_answer['reply'],
            'thinking': account_answer['thinking'],
            'model': 'portal account',
        })

    hr_answer = _answer_ai_hr_question(prompt)
    if hr_answer:
        response = {
            'success': True,
            'reply': hr_answer['reply'],
            'thinking': hr_answer['thinking'],
            'model': 'portal hr',
        }
        if hr_answer.get('action_url'):
            response['action_url'] = hr_answer['action_url']
            response['action_label'] = hr_answer.get('action_label') or 'Open HR'
        return jsonify(response)

    perk_answer = _answer_ai_perk_request(prompt)
    if perk_answer:
        return jsonify({
            'success': True,
            'reply': perk_answer['reply'],
            'thinking': perk_answer['thinking'],
            'action_url': perk_answer['action_url'],
            'action_label': perk_answer['action_label'],
            'model': 'portal perks',
        })

    leave_draft = _build_ai_leave_draft(prompt)
    if leave_draft:
        session['ai_leave_draft'] = leave_draft
        return jsonify({
            'success': True,
            'reply': (
                f"I prepared a leave request draft for {leave_draft['start_date']} "
                f"to {leave_draft['end_date']}. Please review it before submitting."
            ),
            'thinking': _build_assist_thinking(prompt),
            'action_url': url_for('employee.leaves', ai_draft=1),
            'action_label': 'Review Leave Draft',
            'model': 'portal draft',
        })

    esarf_draft = _build_ai_esarf_draft(prompt)
    if esarf_draft:
        session['ai_esarf_draft'] = esarf_draft
        draft_type = esarf_draft['transaction_types'][0]
        draft_type_label = {
            'OT': 'overtime',
            'Offset': 'offset',
            'Use Offset': 'use-offset',
        }.get(draft_type, draft_type)
        article = 'an' if draft_type_label[0].lower() in {'a', 'e', 'i', 'o', 'u'} else 'a'
        return jsonify({
            'success': True,
            'reply': (
                f"I prepared {article} {draft_type_label} ESARF draft for {esarf_draft['date_from']} "
                f"from {esarf_draft['time_from']} to {esarf_draft['time_to']} "
                f"({esarf_draft['total_hours']} hours). Please review it before submitting."
            ),
            'thinking': 'I understood this as an ESARF request, filled the date and time, calculated the hours, and generated a clear reason.',
            'action_url': url_for('employee.esarf', ai_draft=1),
            'action_label': 'Review ESARF Draft',
            'model': 'portal draft',
        })

    try:
        reply, thinking = _call_general_ai_chat(prompt, model)
    except HTTPError as exc:
        if exc.code == 404:
            return jsonify({
                'success': False,
                'message': 'HYG Assist is almost ready. Please ask IT to finish the AI setup on this device.',
            }), 503
        return jsonify({
            'success': False,
            'message': 'HYG Assist had trouble answering. Please try again in a moment.',
        }), 503
    except RuntimeError as exc:
        if str(exc) == "missing_openrouter_key":
            return jsonify({
                'success': False,
                'message': 'HYG Assist AI is coming soon! The AI feature will be available once setup is complete on PythonAnywhere.',
            }), 503
        if str(exc) == "missing_openai_key":
            return jsonify({
                'success': False,
                'message': 'HYG Assist AI is coming soon! The AI feature will be available once setup is complete.',
            }), 503
        if str(exc) == "missing_ollama_url":
            return jsonify({
                'success': False,
                'message': 'HYG Assist AI is coming soon! The AI feature will be available once setup is complete.',
            }), 503
        return jsonify({
            'success': False,
            'message': 'HYG Assist is not configured yet.',
        }), 503
    except (URLError, TimeoutError, OSError):
        return jsonify({
            'success': False,
            'message': 'HYG Assist is unavailable right now. Please try again when this device is ready.',
        }), 503

    if not reply:
        reply = 'The model replied with an empty response. Please try a shorter prompt.'

    _, active_model = _resolve_ai_provider_model(model)
    return jsonify({
        'success': True,
        'reply': reply,
        'thinking': thinking or _build_assist_thinking(prompt),
        'model': active_model,
    })


@employee.route('/notifications', methods=['GET'])
@login_required
def notifications():
    notification_items = Notification.query.filter_by(
        user_id=current_user.id,
    ).order_by(Notification.created_at.desc()).all()
    now = philippine_now()
    for item in notification_items:
        if not item.created_at:
            item.relative_time = ""
            continue
        seconds = max(0, int((now - item.created_at).total_seconds()))
        if seconds < 60:
            item.relative_time = "now"
        elif seconds < 3600:
            item.relative_time = f"{seconds // 60}m"
        elif seconds < 86400:
            item.relative_time = f"{seconds // 3600}h"
        elif seconds < 604800:
            item.relative_time = f"{seconds // 86400}d"
        else:
            item.relative_time = item.created_at.strftime("%b %d")
    unread_count = sum(1 for item in notification_items if not item.is_read)
    return render_template(
        'employee/notifications.html',
        notifications=notification_items,
        unread_count=unread_count,
    )


@employee.route('/notifications/<int:notification_id>/read', methods=['POST'])
@login_required
def mark_notification_read(notification_id):
    notification = Notification.query.filter_by(
        id=notification_id,
        user_id=current_user.id,
    ).first_or_404()
    notification.is_read = True
    db.session.commit()
    flash('Notification marked as read.', category='success')
    return redirect(request.form.get('next') or url_for('employee.notifications'))


@employee.route('/notifications/<int:notification_id>/delete', methods=['POST'])
@login_required
def delete_notification(notification_id):
    notification = Notification.query.filter_by(
        id=notification_id,
        user_id=current_user.id,
    ).first_or_404()
    db.session.delete(notification)
    db.session.commit()
    flash('Notification deleted.', category='success')
    return redirect(url_for('employee.notifications'))
