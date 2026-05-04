from datetime import datetime, timedelta
from email.message import EmailMessage
import hashlib
import json
import random
import secrets
import smtplib
import unicodedata
from urllib.error import URLError
from urllib.request import Request, urlopen

from flask import Blueprint, g, jsonify, request
from sqlalchemy import func, or_
from werkzeug.security import check_password_hash, generate_password_hash

from . import db
from .employee import PERK_APPROVAL_EMAIL, PERK_APPROVAL_PASSWORD, PERK_APPROVAL_SENDER
from .helpers import create_notification, philippine_now, sync_department_name
from .models import (
    Company,
    DiscountRequest,
    Employee,
    EsarfRequest,
    LeaveRequest,
    MobileSession,
    Notification,
    ProductChargeRequest,
    User,
)

mobile_api = Blueprint("mobile_api", __name__, url_prefix="/api/mobile")

MOBILE_TOKEN_DAYS = 30
ANNUAL_CASH_LIMIT = 3000.0
ANNUAL_CASH_TRANSACTION_LIMIT = 6
PER_CHARGE_LIMIT = 3000.0


def ok(data=None, message=None, status=200):
    payload = {"status": "success"}
    if message:
        payload["message"] = message
    if data is not None:
        payload["data"] = data
    return jsonify(payload), status


def error(message, status=400):
    return jsonify({"status": "error", "message": message}), status


def _hash_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _issue_mobile_token(user):
    token = secrets.token_urlsafe(48)
    now = philippine_now()
    session = MobileSession(
        user_id=user.id,
        token_hash=_hash_token(token),
        created_at=now,
        last_used_at=now,
        expires_at=now + timedelta(days=MOBILE_TOKEN_DAYS),
    )
    db.session.add(session)
    db.session.commit()
    return token, session


def _current_mobile_session():
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    token = header.removeprefix("Bearer ").strip()
    if not token:
        return None
    session = MobileSession.query.filter_by(token_hash=_hash_token(token)).first()
    if not session or session.expires_at < philippine_now():
        return None
    session.last_used_at = philippine_now()
    db.session.commit()
    return session


def mobile_login_required(view_func):
    def wrapped_view(*args, **kwargs):
        mobile_session = _current_mobile_session()
        if not mobile_session:
            return error("Authentication required.", 401)
        g.mobile_session = mobile_session
        g.mobile_user = mobile_session.user
        return view_func(*args, **kwargs)

    wrapped_view.__name__ = view_func.__name__
    return wrapped_view


def _require_employee_user():
    user = g.mobile_user
    if not user.employee:
        return None, error("Your account is not linked to an employee profile.", 403)
    return user.employee, None


def _date(value):
    return value.isoformat() if value else None


def _time(value):
    return value.strftime("%H:%M") if value else None


def _dt(value):
    return value.isoformat() if value else None


def _float(value):
    return float(value or 0)


def _parse_date(value, field_name):
    if not value:
        raise ValueError(f"{field_name} is required.")
    return datetime.strptime(value, "%Y-%m-%d").date()


def _parse_time(value, field_name):
    if not value:
        raise ValueError(f"{field_name} is required.")
    return datetime.strptime(value, "%H:%M").time()


def _parse_optional_int(value):
    if value in (None, ""):
        return None
    return int(value)


def _compute_age_from_birth_date(birth_date):
    if not birth_date:
        return None
    today = philippine_now().date()
    age = today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))
    return age if age >= 0 else None


def _format_employee_no(hired_date, sequence):
    date_part = hired_date.strftime("%m%d%Y") if hired_date else "00000000"
    return f"{date_part}-{sequence:02d}"


def _next_employee_no_for_date(hired_date):
    prefix = hired_date.strftime("%m%d%Y") if hired_date else "00000000"
    query = Employee.query.with_entities(Employee.employee_no).filter(Employee.employee_no.like(f"{prefix}-%"))
    max_sequence = 0
    for value, in query.all():
        if not value:
            continue
        try:
            max_sequence = max(max_sequence, int(str(value).rsplit("-", 1)[1]))
        except (IndexError, ValueError):
            continue
    return _format_employee_no(hired_date, max_sequence + 1)


def _employee_name(employee):
    return " ".join(
        part for part in [
            employee.first_name,
            employee.middle_name,
            employee.last_name,
            employee.suffix,
        ] if part
    ).strip()


def serialize_user(user):
    return {
        "id": user.id,
        "username": user.username,
        "role": user.role,
        "employee_id": user.employee_id,
    }


def serialize_employee(employee):
    if not employee:
        return None
    fields = [
        "id", "biometric_no", "first_name", "middle_name", "last_name", "suffix",
        "age", "religion", "educational_attainment", "birth_place", "nationality",
        "height", "weight", "civil_status", "department", "position", "company",
        "employee_no", "employee_type", "location", "email", "phone", "house_phone",
        "social_media_type", "social_media_detail", "present_address",
        "permanent_address", "sss_no", "philhealth_no", "pagibig_no", "tin_no",
        "valid_id_no", "valid_id_type", "elementary_school",
        "elementary_year_attended", "secondary_school", "secondary_year_attended",
        "college_school", "college_year_attended", "college_course",
        "year_graduated", "father_name", "father_occupation",
        "mother_maiden_name", "mother_occupation", "no_of_siblings",
        "sibling_birth_order", "spouse_full_name", "spouse_age", "spouse_school",
        "spouse_course_degree", "spouse_occupation", "no_of_children",
        "no_of_male_children", "no_of_female_children", "account_no", "bank_type",
        "status", "photopath", "employment_status", "gender", "zipCode",
    ]
    data = {field: getattr(employee, field) for field in fields}
    data["full_name"] = _employee_name(employee)
    data["birth_date"] = _date(employee.birth_date)
    data["hired_date"] = _date(employee.hired_date)
    data["spouse_birth_date"] = _date(employee.spouse_birth_date)
    data["children_details"] = employee.children_details_list
    return data


def serialize_leave(item):
    return {
        "id": item.id,
        "status": item.status,
        "leave_type": item.leave_type,
        "leave_category": item.leave_category,
        "start_date": _date(item.start_date),
        "end_date": _date(item.end_date),
        "reason": item.reason,
    }


def serialize_esarf(item):
    return {
        "id": item.id,
        "esarf_number": item.esarf_number,
        "status": item.status,
        "time_schedule": item.time_schedule,
        "day_off": item.day_off,
        "payroll_class": item.payroll_class,
        "transaction_types": [x for x in (item.transaction_types or "").split(",") if x],
        "date_from": _date(item.date_from),
        "date_to": _date(item.date_to),
        "time_from": _time(item.time_from),
        "time_to": _time(item.time_to),
        "total_hours": _float(item.total_hours),
        "reason": item.reason,
        "created_at": _dt(item.created_at),
        "declined_reason": item.declined_reason,
    }


def serialize_discount(item):
    return {
        "id": item.id,
        "type": "discount",
        "status": item.status,
        "product_name": item.product_name,
        "quantity": item.quantity,
        "price": _float(item.price),
        "transaction_date": _date(item.transaction_date),
        "amount": _float(item.amount),
        "discounted_amount": _float(item.discounted_amount),
        "approval_code": item.approval_code,
        "declined_reason": item.declined_reason,
        "created_at": _dt(item.created_at),
    }


def serialize_charge(item):
    return {
        "id": item.id,
        "type": "charge",
        "status": item.status,
        "product_name": item.product_name,
        "quantity": item.quantity,
        "price": _float(item.price),
        "transaction_date": _date(item.transaction_date),
        "total_amount": _float(item.total_amount),
        "approval_code": item.approval_code,
        "declined_reason": item.declined_reason,
        "created_at": _dt(item.created_at),
    }


def serialize_notification(item):
    return {
        "id": item.id,
        "title": item.title,
        "message": item.message,
        "category": item.category,
        "link_url": item.link_url,
        "is_read": item.is_read,
        "created_at": _dt(item.created_at),
    }


def _status_counts(model, user_id):
    return {
        "pending": model.query.filter_by(submitted_by_user_id=user_id, status="Pending").count(),
        "approved": model.query.filter(
            model.submitted_by_user_id == user_id,
            model.status.ilike("approved"),
        ).count(),
        "rejected": model.query.filter(
            model.submitted_by_user_id == user_id,
            model.status.ilike("rejected"),
        ).count(),
    }


def _perk_limits(user_id):
    now = philippine_now()
    year_start = datetime(now.year, 1, 1)
    year_end = datetime(now.year, 12, 31, 23, 59, 59)
    discount_count = DiscountRequest.query.filter(
        DiscountRequest.submitted_by_user_id == user_id,
        DiscountRequest.status.in_(["Pending", "Approved"]),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).count()
    discount_used = db.session.query(
        db.func.coalesce(db.func.sum(DiscountRequest.amount), 0)
    ).filter(
        DiscountRequest.submitted_by_user_id == user_id,
        DiscountRequest.status.in_(["Pending", "Approved"]),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).scalar()
    charge_count = ProductChargeRequest.query.filter(
        ProductChargeRequest.submitted_by_user_id == user_id,
        ProductChargeRequest.status.in_(["Pending", "Approved"]),
        ProductChargeRequest.created_at >= year_start,
        ProductChargeRequest.created_at <= year_end,
    ).count()
    discount_used = _float(discount_used)
    return {
        "annual_cash_limit": ANNUAL_CASH_LIMIT,
        "annual_cash_transaction_limit": ANNUAL_CASH_TRANSACTION_LIMIT,
        "per_charge_limit": PER_CHARGE_LIMIT,
        "discount_used": discount_used,
        "discount_remaining": max(0, ANNUAL_CASH_LIMIT - discount_used),
        "discount_transaction_count": discount_count,
        "discount_transaction_remaining": max(0, ANNUAL_CASH_TRANSACTION_LIMIT - discount_count),
        "charge_transaction_count": charge_count,
        "charge_first_available": charge_count == 0,
    }


def _activity_sort_date(value):
    if not value:
        return datetime.min
    if isinstance(value, datetime):
        return value
    return datetime.combine(value, datetime.min.time())


def _parse_products(products):
    parsed = []
    total_quantity = 0
    total_amount = 0.0
    for item in products or []:
        name = (item.get("name") or item.get("product_name") or "").strip()
        quantity = int(item.get("quantity") or 0)
        price = float(item.get("price") or 0)
        if not name or quantity <= 0 or price <= 0:
            raise ValueError("Invalid product details.")
        line_total = round(quantity * price, 2)
        parsed.append({"name": name, "quantity": quantity, "price": price, "line_total": line_total})
        total_quantity += quantity
        total_amount += line_total
    if not parsed:
        raise ValueError("At least one product is required.")
    summary = "; ".join(f"{item['name']} x{item['quantity']} @ {item['price']:.2f}" for item in parsed)
    average_price = round(total_amount / total_quantity, 2) if total_quantity else 0
    return summary, total_quantity, average_price, round(total_amount, 2)


def _generate_unique_perk_code():
    rng = random.SystemRandom()
    while True:
        code = f"{rng.randint(0, 999999):06d}"
        discount_exists = DiscountRequest.query.filter_by(approval_code=code).first()
        charge_exists = ProductChargeRequest.query.filter_by(approval_code=code).first()
        if not discount_exists and not charge_exists:
            return code


def _send_perk_email(email_address, subject, body):
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = f"{PERK_APPROVAL_SENDER} <{PERK_APPROVAL_EMAIL}>"
    message["To"] = email_address
    message.set_content(body)
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
        smtp.login(PERK_APPROVAL_EMAIL, PERK_APPROVAL_PASSWORD)
        smtp.send_message(message)


def _start_perk_verification(employee, mobile_session, payload):
    email_address = (employee.email or "").strip()
    if not email_address:
        return error("Your profile needs a registered email before submitting a perk request.", 400)
    code = _generate_unique_perk_code()
    label = "Employee Discount (Cash)" if payload["form_type"] == "discount" else "Employee Charge (Credit)"
    _send_perk_email(
        email_address,
        f"Your {label} approval code",
        f"Your approval code for {label} is: {code}\n\nEnter this code in the mobile app to complete your request.",
    )
    payload["approval_code"] = code
    payload["email"] = email_address
    payload["request_label"] = label
    mobile_session.pending_perk_request = payload
    db.session.commit()
    return ok({"email": email_address, "request_label": label}, "Approval code sent.")


@mobile_api.route("/auth/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    user = User.query.filter(func.lower(User.username) == username.lower()).first()
    if not user or not check_password_hash(user.password or "", password):
        return error("Invalid username or password.", 401)
    if (user.role or "").strip().lower() != "user":
        return error("Only employee accounts can use the mobile app.", 403)
    token, session = _issue_mobile_token(user)
    return ok({
        "token": token,
        "expires_at": _dt(session.expires_at),
        "user": serialize_user(user),
        "employee": serialize_employee(user.employee),
    })


@mobile_api.route("/auth/logout", methods=["POST"])
@mobile_login_required
def logout():
    db.session.delete(g.mobile_session)
    db.session.commit()
    return ok(message="Logged out.")


@mobile_api.route("/auth/verify-employee", methods=["POST"])
def verify_employee():
    data = request.get_json(silent=True) or {}
    first_name = unicodedata.normalize("NFC", (data.get("first_name") or "").strip())
    last_name = unicodedata.normalize("NFC", (data.get("last_name") or "").strip())
    birth_date_str = data.get("birth_date")
    if not first_name or not last_name or not birth_date_str:
        return error("First Name, Last Name, and Birth Date are required.", 400)

    def ci_match(column, value):
        return or_(
            func.lower(column) == value.lower(),
            column == value,
            column == value.upper(),
            column == value.lower(),
            column == value.title(),
        )

    try:
        birth_date = datetime.strptime(birth_date_str, "%Y-%m-%d").date()
    except ValueError:
        return error("Please enter a valid Birth Date.", 400)
    employee = Employee.query.filter(
        ci_match(Employee.first_name, first_name),
        ci_match(Employee.last_name, last_name),
        Employee.birth_date == birth_date,
    ).first()
    if not employee:
        return error("No employee record found with the provided First Name, Last Name, and Birth Date.", 404)
    if User.query.filter_by(employee_id=employee.id).first():
        return error("An account already exists for this employee.", 409)
    return ok({"employee_id": employee.id})


@mobile_api.route("/auth/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    employee_id = data.get("employee_id")
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    confirm_password = data.get("confirm_password") or ""
    if not data.get("terms_accepted"):
        return error("You must accept the Terms and Conditions.", 400)
    if not employee_id:
        return error("Session lost. Please verify employee details again.", 400)
    if len(username) < 4:
        return error("Username must be at least 4 characters.", 400)
    if len(password) < 7:
        return error("Password must be at least 7 characters.", 400)
    if password != confirm_password:
        return error("Passwords do not match.", 400)
    if User.query.filter_by(username=username).first():
        return error("Username is already taken.", 400)
    employee = Employee.query.get(employee_id)
    if not employee:
        return error("Employee record no longer exists.", 404)
    if User.query.filter_by(employee_id=employee.id).first():
        return error("An account already exists for this employee.", 409)
    user = User(
        username=username,
        password=generate_password_hash(password, method="pbkdf2:sha256"),
        role="user",
        employee_id=employee.id,
    )
    db.session.add(user)
    db.session.commit()
    token, session = _issue_mobile_token(user)
    return ok({
        "token": token,
        "expires_at": _dt(session.expires_at),
        "user": serialize_user(user),
        "employee": serialize_employee(employee),
    }, "Registration successful.", 201)


@mobile_api.route("/auth/register-employee/options", methods=["GET"])
def register_employee_options():
    companies = Company.query.order_by(Company.company_name.asc()).all()
    return ok({
        "companies": [
            {"id": company.id, "company_name": company.company_name}
            for company in companies
        ]
    })


@mobile_api.route("/auth/register-employee", methods=["POST"])
def register_employee_profile():
    data = request.get_json(silent=True) or {}
    first_name = (data.get("first_name") or "").strip()
    last_name = (data.get("last_name") or "").strip()
    if not first_name or not last_name:
        return error("First Name and Last Name are required.", 400)
    existing_employee = Employee.query.filter(
        Employee.first_name.ilike(first_name),
        Employee.last_name.ilike(last_name),
    ).first()
    if existing_employee:
        return error("Employee with the same First Name and Last Name already exists.", 409)

    try:
        birth_date = datetime.strptime(data["birth_date"], "%Y-%m-%d").date() if data.get("birth_date") else None
        hired_date = datetime.strptime(data["hired_date"], "%Y-%m-%d").date() if data.get("hired_date") else None
        employee = Employee(
            first_name=first_name,
            middle_name=(data.get("middle_name") or "").strip(),
            last_name=last_name,
            suffix=(data.get("suffix") or "").strip(),
            birth_date=birth_date,
            age=_compute_age_from_birth_date(birth_date),
            gender=data.get("gender"),
            religion=(data.get("religion") or "").strip(),
            birth_place=(data.get("birth_place") or "").strip(),
            nationality=(data.get("nationality") or "").strip(),
            civil_status=(data.get("civil_status") or "").strip(),
            height=(data.get("height") or "").strip(),
            weight=(data.get("weight") or "").strip(),
            educational_attainment=data.get("educational_attainment"),
            email=(data.get("email") or "").strip(),
            phone=(data.get("phone") or "").strip(),
            house_phone=(data.get("house_phone") or "").strip(),
            social_media_type=(data.get("social_media_type") or "").strip(),
            social_media_detail=(data.get("social_media_detail") or "").strip(),
            present_address=(data.get("present_address") or "").strip(),
            permanent_address=(data.get("permanent_address") or "").strip(),
            zipCode=_parse_optional_int(data.get("zipCode")),
            employee_no=_next_employee_no_for_date(hired_date),
            company=(data.get("company") or "").strip(),
            department=(data.get("department") or "").strip(),
            position=(data.get("position") or "").strip(),
            hired_date=hired_date,
            employee_type=data.get("employee_type"),
            status="Active",
            employment_status="Active",
            sss_no=_parse_optional_int(data.get("sss_no")),
            philhealth_no=_parse_optional_int(data.get("philhealth_no")),
            pagibig_no=_parse_optional_int(data.get("pagibig_no")),
            tin_no=_parse_optional_int(data.get("tin_no")),
            valid_id_type=(data.get("valid_id_type") or "").strip(),
            valid_id_no=_parse_optional_int(data.get("valid_id_no")),
            bank_type=(data.get("bank_type") or "").strip(),
            account_no=_parse_optional_int(data.get("account_no")),
            elementary_school=(data.get("elementary_school") or "").strip(),
            elementary_year_attended=(data.get("elementary_year_attended") or "").strip(),
            secondary_school=(data.get("secondary_school") or "").strip(),
            secondary_year_attended=(data.get("secondary_year_attended") or "").strip(),
            college_school=(data.get("college_school") or "").strip(),
            college_year_attended=(data.get("college_year_attended") or "").strip(),
            college_course=(data.get("college_course") or "").strip(),
            year_graduated=(data.get("year_graduated") or "").strip(),
            father_name=(data.get("father_name") or "").strip(),
            father_occupation=(data.get("father_occupation") or "").strip(),
            mother_maiden_name=(data.get("mother_maiden_name") or "").strip(),
            mother_occupation=(data.get("mother_occupation") or "").strip(),
            no_of_siblings=(data.get("no_of_siblings") or "").strip(),
            sibling_birth_order=(data.get("sibling_birth_order") or "").strip(),
            spouse_full_name=(data.get("spouse_full_name") or "").strip(),
            spouse_age=_parse_optional_int(data.get("spouse_age")),
            spouse_birth_date=datetime.strptime(data["spouse_birth_date"], "%Y-%m-%d").date() if data.get("spouse_birth_date") else None,
            spouse_school=(data.get("spouse_school") or "").strip(),
            spouse_course_degree=(data.get("spouse_course_degree") or "").strip(),
            spouse_occupation=(data.get("spouse_occupation") or "").strip(),
            no_of_male_children=_parse_optional_int(data.get("no_of_male_children")),
            no_of_female_children=_parse_optional_int(data.get("no_of_female_children")),
            children_details=data.get("children_details") if isinstance(data.get("children_details"), list) else None,
        )
        employee.no_of_children = (employee.no_of_male_children or 0) + (employee.no_of_female_children or 0)
        db.session.add(employee)
        sync_department_name(employee.department)
        db.session.flush()

        username = (data.get("reg_username") or "").strip()
        user = None
        if username:
            password = data.get("reg_password") or ""
            confirm = data.get("reg_confirm_password") or ""
            if len(username) < 4:
                db.session.rollback()
                return error("Username must be at least 4 characters.", 400)
            if len(password) < 7:
                db.session.rollback()
                return error("Password must be at least 7 characters when creating an account.", 400)
            if password != confirm:
                db.session.rollback()
                return error("Passwords do not match.", 400)
            if User.query.filter_by(username=username).first():
                db.session.rollback()
                return error(f"Username '{username}' is already taken.", 409)
            user = User(
                username=username,
                password=generate_password_hash(password, method="pbkdf2:sha256"),
                role="user",
                employee_id=employee.id,
            )
            db.session.add(user)

        db.session.commit()
        response = {"employee": serialize_employee(employee)}
        if user:
            token, session = _issue_mobile_token(user)
            response.update({
                "token": token,
                "expires_at": _dt(session.expires_at),
                "user": serialize_user(user),
            })
        return ok(response, "Employee profile created.", 201)
    except ValueError:
        db.session.rollback()
        return error("Please check date and number fields.", 400)
    except Exception:
        db.session.rollback()
        return error("Error saving employee.", 500)


@mobile_api.route("/me", methods=["GET"])
@mobile_login_required
def me():
    return ok({"user": serialize_user(g.mobile_user), "employee": serialize_employee(g.mobile_user.employee)})


@mobile_api.route("/dashboard", methods=["GET"])
@mobile_login_required
def dashboard():
    employee, response = _require_employee_user()
    if response:
        return response
    user_id = g.mobile_user.id
    pending_esarf_hours = db.session.query(
        db.func.coalesce(db.func.sum(EsarfRequest.total_hours), 0)
    ).filter_by(submitted_by_user_id=user_id, status="Pending").scalar()
    profile_fields = [
        employee.first_name, employee.last_name, employee.employee_no, employee.company,
        employee.department, employee.position, employee.employee_type, employee.hired_date,
        employee.email, employee.phone, employee.present_address, employee.birth_date,
        employee.gender, employee.civil_status, employee.sss_no, employee.philhealth_no,
        employee.pagibig_no, employee.tin_no,
    ]
    missing = []
    for label, value in [
        ("employee number", employee.employee_no),
        ("company", employee.company),
        ("department", employee.department),
        ("position", employee.position),
        ("email", employee.email),
        ("phone", employee.phone),
        ("address", employee.present_address),
        ("government IDs", all([employee.sss_no, employee.philhealth_no, employee.pagibig_no, employee.tin_no])),
    ]:
        if not value:
            missing.append(label)

    activity = []
    for item in LeaveRequest.query.filter_by(submitted_by_user_id=user_id).order_by(LeaveRequest.id.desc()).limit(3):
        activity.append({"type": "Leave", "title": item.leave_category, "status": item.status, "date": _date(item.start_date)})
    for item in EsarfRequest.query.filter_by(submitted_by_user_id=user_id).order_by(EsarfRequest.id.desc()).limit(3):
        activity.append({"type": "ESARF", "title": item.esarf_number or "ESARF Request", "status": item.status, "date": _dt(item.created_at)})
    for item in DiscountRequest.query.filter_by(submitted_by_user_id=user_id).order_by(DiscountRequest.id.desc()).limit(3):
        activity.append({"type": "Discount", "title": item.product_name or "Employee discount", "status": item.status, "date": _dt(item.created_at)})
    for item in ProductChargeRequest.query.filter_by(submitted_by_user_id=user_id).order_by(ProductChargeRequest.id.desc()).limit(3):
        activity.append({"type": "Charge", "title": item.product_name or "Product charge", "status": item.status, "date": _dt(item.created_at)})

    activity = sorted(activity, key=lambda item: item.get("date") or "", reverse=True)[:6]
    return ok({
        "greeting_label": "Good evening" if philippine_now().hour >= 18 else "Good afternoon" if philippine_now().hour >= 12 else "Good morning",
        "employee": serialize_employee(employee),
        "leave_counts": _status_counts(LeaveRequest, user_id),
        "esarf_counts": _status_counts(EsarfRequest, user_id),
        "pending_esarf_hours": _float(pending_esarf_hours),
        "perk_limits": _perk_limits(user_id),
        "profile_completion": round((sum(1 for field in profile_fields if field) / len(profile_fields)) * 100),
        "missing_profile_items": missing[:4],
        "recent_activity": activity,
    })


@mobile_api.route("/profile", methods=["GET"])
@mobile_login_required
def profile():
    employee, response = _require_employee_user()
    if response:
        return response
    return ok({"employee": serialize_employee(employee)})


@mobile_api.route("/profile/<section>", methods=["PATCH"])
@mobile_login_required
def update_profile_section(section):
    employee, response = _require_employee_user()
    if response:
        return response
    data = request.get_json(silent=True) or {}
    section_fields = {
        "account": ["first_name", "middle_name", "last_name"],
        "personal": ["birth_date", "age", "gender", "religion", "birth_place", "nationality", "civil_status", "height", "weight", "educational_attainment"],
        "contact": ["email", "phone", "house_phone", "social_media_type", "social_media_detail", "present_address", "zipCode", "permanent_address"],
        "employment": ["company", "employee_type", "hired_date", "location", "department", "position"],
        "government": ["sss_no", "philhealth_no", "pagibig_no", "tin_no", "valid_id_no", "valid_id_type", "account_no", "bank_type"],
        "education": ["elementary_school", "elementary_year_attended", "secondary_school", "secondary_year_attended", "college_school", "college_year_attended", "college_course", "year_graduated"],
        "family": ["father_name", "father_occupation", "mother_maiden_name", "mother_occupation", "no_of_siblings", "sibling_birth_order"],
        "spouse": ["spouse_full_name", "spouse_age", "spouse_birth_date", "spouse_school", "spouse_course_degree", "spouse_occupation"],
        "children": ["no_of_children", "no_of_male_children", "no_of_female_children"],
    }
    int_fields = {"age", "spouse_age", "no_of_children", "no_of_male_children", "no_of_female_children", "sss_no", "philhealth_no", "pagibig_no", "tin_no", "valid_id_no", "account_no", "zipCode"}
    date_fields = {"birth_date", "hired_date", "spouse_birth_date"}
    fields = section_fields.get(section)
    if not fields:
        return error("Unknown profile section.", 404)
    try:
        for field in fields:
            if field not in data:
                continue
            value = data.get(field)
            if value in ("", None):
                setattr(employee, field, None)
            elif field in date_fields:
                setattr(employee, field, datetime.strptime(value, "%Y-%m-%d").date())
            elif field in int_fields:
                setattr(employee, field, int(value))
            else:
                setattr(employee, field, value)
        if section == "children":
            children = data.get("children_details")
            employee.children_details = children if isinstance(children, list) and children else None
        if section == "employment":
            sync_department_name(employee.department)
        db.session.commit()
    except Exception:
        db.session.rollback()
        return error("Failed to update profile section. Please check your inputs.", 400)
    return ok({"employee": serialize_employee(employee)}, "Profile updated.")


@mobile_api.route("/leaves", methods=["GET"])
@mobile_login_required
def leaves():
    page = request.args.get("page", 1, type=int)
    per_page = min(request.args.get("per_page", 10, type=int), 50)
    items = LeaveRequest.query.filter_by(submitted_by_user_id=g.mobile_user.id).order_by(LeaveRequest.id.desc()).paginate(page=page, per_page=per_page)
    return ok({
        "items": [serialize_leave(item) for item in items.items],
        "counts": _status_counts(LeaveRequest, g.mobile_user.id),
        "pagination": {"page": items.page, "per_page": items.per_page, "pages": items.pages, "total": items.total, "has_next": items.has_next, "has_prev": items.has_prev},
    })


@mobile_api.route("/leaves", methods=["POST"])
@mobile_login_required
def create_leave():
    employee, response = _require_employee_user()
    if response:
        return response
    data = request.get_json(silent=True) or {}
    try:
        category = data.get("leave_category")
        if category == "Others":
            category = (data.get("other_leave") or "").strip()
            if not category:
                return error("Please specify your 'Other' leave type.", 400)
        item = LeaveRequest(
            submitted_by_user_id=g.mobile_user.id,
            start_date=_parse_date(data.get("start_date"), "Start date"),
            end_date=_parse_date(data.get("end_date"), "End date"),
            leave_type=data.get("leave_type"),
            leave_category=category,
            reason=data.get("reason"),
        )
        if item.end_date < item.start_date:
            return error("End date cannot be earlier than start date.", 400)
        if not item.leave_type or not item.leave_category or not item.reason:
            return error("Please complete all leave fields.", 400)
        db.session.add(item)
        db.session.flush()
        create_notification(g.mobile_user.id, "Leave sent", f"You requested {category} leave.", category="success")
        db.session.commit()
    except ValueError as exc:
        return error(str(exc), 400)
    except Exception:
        db.session.rollback()
        return error("Failed to submit leave. Check your inputs.", 400)
    return ok({"leave": serialize_leave(item)}, "Leave request submitted.", 201)


@mobile_api.route("/esarfs", methods=["GET"])
@mobile_login_required
def esarfs():
    items = EsarfRequest.query.filter_by(submitted_by_user_id=g.mobile_user.id).order_by(EsarfRequest.id.desc()).all()
    return ok({"items": [serialize_esarf(item) for item in items], "counts": _status_counts(EsarfRequest, g.mobile_user.id)})


@mobile_api.route("/esarfs", methods=["POST"])
@mobile_login_required
def create_esarf():
    employee, response = _require_employee_user()
    if response:
        return response
    data = request.get_json(silent=True) or {}
    try:
        date_from = _parse_date(data.get("date_from"), "Date from")
        date_to = _parse_date(data.get("date_to"), "Date to")
        if date_to < date_from:
            return error("Date To cannot be earlier than Date From.", 400)
        time_from = _parse_time(data.get("time_from"), "Time from")
        time_to = _parse_time(data.get("time_to"), "Time to")
        start_dt = datetime.combine(datetime.today(), time_from)
        end_dt = datetime.combine(datetime.today(), time_to)
        if end_dt <= start_dt:
            end_dt += timedelta(days=1)
        total_hours = float(data.get("total_hours") or round((end_dt - start_dt).total_seconds() / 3600, 2))
        transaction_types = data.get("transaction_types") or []
        if not transaction_types:
            return error("Please select at least one transaction type.", 400)
        required = [data.get("time_schedule"), data.get("day_off"), data.get("payroll_class"), data.get("reason")]
        if not all(required):
            return error("Unable to submit ESARF. Please complete all required fields.", 400)
        item = EsarfRequest(
            submitted_by_user_id=g.mobile_user.id,
            time_schedule=data.get("time_schedule"),
            day_off=data.get("day_off"),
            payroll_class=data.get("payroll_class"),
            transaction_types=",".join(transaction_types),
            date_from=date_from,
            date_to=date_to,
            time_from=time_from,
            time_to=time_to,
            total_hours=total_hours,
            reason=data.get("reason"),
        )
        db.session.add(item)
        db.session.flush()
        item.esarf_number = f"ESARF-{philippine_now().year}-{item.id:03d}"
        create_notification(g.mobile_user.id, "ESARF sent", f"You submitted {item.esarf_number}.", category="success")
        db.session.commit()
    except ValueError as exc:
        return error(str(exc), 400)
    except Exception:
        db.session.rollback()
        return error("Unable to submit ESARF. Please check your inputs and try again.", 400)
    return ok({"esarf": serialize_esarf(item)}, "ESARF request submitted.", 201)


@mobile_api.route("/perks", methods=["GET"])
@mobile_login_required
def perks():
    user_id = g.mobile_user.id
    discounts = DiscountRequest.query.filter_by(submitted_by_user_id=user_id).order_by(DiscountRequest.id.desc()).all()
    charges = ProductChargeRequest.query.filter_by(submitted_by_user_id=user_id).order_by(ProductChargeRequest.id.desc()).all()
    combined = sorted(
        [*map(serialize_discount, discounts), *map(serialize_charge, charges)],
        key=lambda item: item.get("created_at") or "",
        reverse=True,
    )
    return ok({
        "limits": _perk_limits(user_id),
        "pending_discount": any(item.status == "Pending" for item in discounts),
        "pending_verification": g.mobile_session.pending_perk_request,
        "items": combined[:20],
    })


@mobile_api.route("/perks/inventory", methods=["GET"])
@mobile_login_required
def perk_inventory():
    import os
    inventory_url = os.environ.get(
        "INVENTORY_API_URL",
        "https://luigiandreyopalia.pythonanywhere.com/inventory/store_inventory_data",
    )
    try:
        inventory_request = Request(inventory_url, headers={"Accept": "application/json"})
        with urlopen(inventory_request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
        if not payload.get("success") or not isinstance(payload.get("inventories"), list):
            return ok({"products": []})
        products = []
        for item in payload["inventories"]:
            name = (item.get("item_name") or "").strip()
            if not name:
                continue
            try:
                price = float(item.get("price") or 0)
            except (TypeError, ValueError):
                price = 0
            products.append({
                "name": name,
                "price": price,
            })
        return ok({"products": products})
    except URLError:
        return ok({"products": []})
    except Exception:
        return ok({"products": []})


@mobile_api.route("/perks/discount/start", methods=["POST"])
@mobile_login_required
def start_discount():
    employee, response = _require_employee_user()
    if response:
        return response
    limits = _perk_limits(g.mobile_user.id)
    if DiscountRequest.query.filter_by(submitted_by_user_id=g.mobile_user.id, status="Pending").first():
        return error("You already have a pending employee discount request.", 400)
    if limits["discount_transaction_remaining"] <= 0:
        return error("You have reached the maximum of 6 employee discount transactions for this year.", 400)
    if limits["discount_remaining"] <= 0:
        return error("You have reached the PHP 3,000 yearly employee discount limit.", 400)
    data = request.get_json(silent=True) or {}
    try:
        product_name, quantity, price, amount = _parse_products(data.get("products"))
        if amount > limits["discount_remaining"]:
            return error(f"This discount request exceeds your remaining yearly cash discount limit of PHP {limits['discount_remaining']:.2f}.", 400)
        transaction_date = _parse_date(data.get("transaction_date"), "Transaction date")
        payload = {
            "form_type": "discount",
            "product_name": product_name,
            "quantity": quantity,
            "price": price,
            "transaction_date": _date(transaction_date),
            "amount": amount,
            "discounted_amount": round(amount * 0.85, 2),
        }
        return _start_perk_verification(employee, g.mobile_session, payload)
    except ValueError as exc:
        return error(str(exc), 400)
    except Exception:
        return error("Unable to send the approval code. Please try again later.", 500)


@mobile_api.route("/perks/charge/start", methods=["POST"])
@mobile_login_required
def start_charge():
    employee, response = _require_employee_user()
    if response:
        return response
    limits = _perk_limits(g.mobile_user.id)
    data = request.get_json(silent=True) or {}
    try:
        product_name, quantity, price, total_amount = _parse_products(data.get("products"))
        if total_amount > PER_CHARGE_LIMIT:
            return error(f"Total amount ({total_amount:.2f}) exceeds the per-transaction credit limit of PHP {PER_CHARGE_LIMIT:.2f}.", 400)
        transaction_date = _parse_date(data.get("transaction_date"), "Transaction date")
        discount_applies = limits["charge_first_available"]
        payload = {
            "form_type": "charge",
            "product_name": product_name,
            "quantity": quantity,
            "price": price,
            "transaction_date": _date(transaction_date),
            "total_amount": round(total_amount * 0.85, 2) if discount_applies else total_amount,
            "original_amount": total_amount,
            "discount_applies": discount_applies,
        }
        return _start_perk_verification(employee, g.mobile_session, payload)
    except ValueError as exc:
        return error(str(exc), 400)
    except Exception:
        return error("Unable to send the approval code. Please try again later.", 500)


@mobile_api.route("/perks/verify", methods=["POST"])
@mobile_login_required
def verify_perk():
    pending = g.mobile_session.pending_perk_request
    if not pending:
        return error("No perk request is waiting for verification.", 400)
    code = (request.get_json(silent=True) or {}).get("approval_code", "").strip()
    if code != pending.get("approval_code"):
        return error("Invalid approval code. Please try again.", 400)
    try:
        transaction_date = datetime.strptime(pending["transaction_date"], "%Y-%m-%d").date()
        if pending["form_type"] == "discount":
            item = DiscountRequest(
                submitted_by_user_id=g.mobile_user.id,
                status="Approved",
                discount_type="Employee Discount (Cash)",
                discount_percent=15.0,
                product_name=pending["product_name"],
                quantity=int(pending["quantity"]),
                price=float(pending["price"]),
                transaction_date=transaction_date,
                amount=float(pending["amount"]),
                discounted_amount=float(pending["discounted_amount"]),
                approval_code=code,
            )
            message = "Your discount request was approved."
        else:
            item = ProductChargeRequest(
                submitted_by_user_id=g.mobile_user.id,
                status="Approved",
                product_name=pending["product_name"],
                quantity=int(pending["quantity"]),
                price=float(pending["price"]),
                total_amount=float(pending["total_amount"]),
                transaction_date=transaction_date,
                approval_code=code,
            )
            message = "Your charge request was approved."
        db.session.add(item)
        create_notification(g.mobile_user.id, "Perk approved", message, category="approved")
        g.mobile_session.pending_perk_request = None
        db.session.commit()
    except Exception:
        db.session.rollback()
        return error("Failed to save the verified perk request. Please try again.", 400)
    return ok({"perk": serialize_discount(item) if pending["form_type"] == "discount" else serialize_charge(item)}, "Perk request verified and submitted.")


@mobile_api.route("/perks/cancel", methods=["POST"])
@mobile_login_required
def cancel_perk():
    g.mobile_session.pending_perk_request = None
    db.session.commit()
    return ok(message="Perk request verification cancelled.")


@mobile_api.route("/perks/resend", methods=["POST"])
@mobile_login_required
def resend_perk():
    employee, response = _require_employee_user()
    if response:
        return response
    pending = g.mobile_session.pending_perk_request
    if not pending:
        return error("No perk request is waiting for verification.", 400)
    pending.pop("approval_code", None)
    pending.pop("email", None)
    return _start_perk_verification(employee, g.mobile_session, pending)


@mobile_api.route("/notifications", methods=["GET"])
@mobile_login_required
def notifications():
    items = Notification.query.filter_by(user_id=g.mobile_user.id).order_by(Notification.created_at.desc()).all()
    return ok({
        "items": [serialize_notification(item) for item in items],
        "unread_count": sum(1 for item in items if not item.is_read),
    })


@mobile_api.route("/notifications/<int:notification_id>/read", methods=["POST"])
@mobile_login_required
def mark_notification_read(notification_id):
    item = Notification.query.filter_by(id=notification_id, user_id=g.mobile_user.id).first()
    if not item:
        return error("Notification not found.", 404)
    item.is_read = True
    db.session.commit()
    return ok({"notification": serialize_notification(item)}, "Notification marked as read.")


@mobile_api.route("/notifications/<int:notification_id>", methods=["DELETE"])
@mobile_login_required
def delete_notification(notification_id):
    item = Notification.query.filter_by(id=notification_id, user_id=g.mobile_user.id).first()
    if not item:
        return error("Notification not found.", 404)
    db.session.delete(item)
    db.session.commit()
    return ok(message="Notification deleted.")
