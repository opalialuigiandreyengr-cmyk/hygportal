import re
import csv
import io
from datetime import date, datetime

from flask import Blueprint, flash, redirect, render_template, request, session, url_for, Response
from flask_login import current_user
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from flask_login import login_required
from werkzeug.security import generate_password_hash

from . import db
from .helpers import (
    _parse_date,
    _parse_int,
    _save_company_logo,
    _save_employee_photo,
    roles_required,
)
from .models import Company, Employee, User, EsarfRequest, DiscountRequest, ProductChargeRequest, PerkApprover

admin = Blueprint("admin", __name__)

ESARF_STATUS_PENDING = "Pending"
ESARF_STATUS_DEPT_MGR_APPROVED = "Dept Mgr Approved"
ESARF_STATUS_DEPT_MGR_OPS_APPROVED = "Dept Mgr Ops Approved"
ESARF_STATUS_APPROVED = "Approved"
ESARF_STATUS_REJECTED = "Rejected"


def _compute_age_from_birth_date(birth_date):
    if not birth_date:
        return None

    today = date.today()
    age = today.year - birth_date.year - (
        (today.month, today.day) < (birth_date.month, birth_date.day)
    )
    return age if age >= 0 else None


EMPLOYEE_TEXT_FIELDS = [
    "birth_place",
    "nationality",
    "height",
    "weight",
    "civil_status",
    "house_phone",
    "social_media_type",
    "social_media_detail",
    "permanent_address",
    "elementary_school",
    "elementary_year_attended",
    "secondary_school",
    "secondary_year_attended",
    "college_school",
    "college_year_attended",
    "college_course",
    "year_graduated",
    "father_name",
    "father_occupation",
    "mother_maiden_name",
    "mother_occupation",
    "no_of_siblings",
    "sibling_birth_order",
    "spouse_full_name",
    "spouse_school",
    "spouse_course_degree",
    "spouse_occupation",
    "bank_type",
    "valid_id_type",
]

EMPLOYEE_INT_FIELDS = [
    "spouse_age",
    "no_of_children",
    "no_of_male_children",
    "no_of_female_children",
]

EMPLOYEE_DATE_FIELDS = [
    "spouse_birth_date",
]


def _apply_extended_employee_fields(employee):
    for field in EMPLOYEE_TEXT_FIELDS:
        setattr(employee, field, (request.form.get(field) or "").strip())

    for field in EMPLOYEE_INT_FIELDS:
        setattr(employee, field, _parse_int(request.form.get(field)))

    for field in EMPLOYEE_DATE_FIELDS:
        setattr(employee, field, _parse_date(request.form.get(field)))

    employee.children_details = _parse_children_details()


def _parse_children_details():
    names = request.form.getlist("child_full_name[]")
    ages = request.form.getlist("child_age[]")
    birth_dates = request.form.getlist("child_birth_date[]")
    schools = request.form.getlist("child_school[]")
    school_levels = request.form.getlist("child_school_level[]")
    occupations = request.form.getlist("child_occupation[]")

    children = []
    total = max(
        len(names),
        len(ages),
        len(birth_dates),
        len(schools),
        len(school_levels),
        len(occupations),
    )

    for index in range(total):
        child = {
            "label": f"Child {index + 1}",
            "full_name": names[index].strip() if index < len(names) else "",
            "age": _parse_int(ages[index]) if index < len(ages) else None,
            "birth_date": birth_dates[index].strip() if index < len(birth_dates) else "",
            "school": schools[index].strip() if index < len(schools) else "",
            "school_level": school_levels[index].strip() if index < len(school_levels) else "",
            "occupation": occupations[index].strip() if index < len(occupations) else "",
        }
        if any(value for key, value in child.items() if key != "label"):
            children.append(child)

    return children


@admin.route("/employees")
@roles_required("admin", "hr")
def employees():
    search = (request.args.get("search") or "").strip()
    status = (request.args.get("status") or "").strip()
    company = (request.args.get("company") or "").strip()
    page = request.args.get("page", 1, type=int)
    per_page = 10

    employee_query = Employee.query

    if search:
        search_pattern = f"%{search}%"
        employee_query = employee_query.filter(
            or_(
                Employee.first_name.ilike(search_pattern),
                Employee.middle_name.ilike(search_pattern),
                Employee.last_name.ilike(search_pattern),
                Employee.email.ilike(search_pattern),
                Employee.employee_no.ilike(search_pattern),
                Employee.department.ilike(search_pattern),
                Employee.position.ilike(search_pattern),
                Employee.company.ilike(search_pattern),
            )
        )

    # Default: exclude Pending employees unless explicitly filtered
    if status:
        employee_query = employee_query.filter(
            or_(
                Employee.employment_status.ilike(status),
                Employee.status.ilike(status),
            )
        )
    else:
        employee_query = employee_query.filter(
            Employee.employment_status != "Pending",
            Employee.status != "Pending",
        )

    if company:
        employee_query = employee_query.filter(Employee.company == company)

    employee_pagination = employee_query.order_by(Employee.id.desc()).paginate(
        page=page,
        per_page=per_page,
        error_out=False,
    )
    employee_items = employee_pagination.items
    company_items = Company.query.order_by(Company.company_name.asc()).all()
    add_employee_form = session.pop("add_employee_form", {})

    return render_template(
        "admin/employees.html",
        employees=employee_items,
        companies=company_items,
        add_employee_form=add_employee_form,
        employee_pagination=employee_pagination,
        employee_filters={
            "search": search,
            "status": status,
            "company": company,
        },
    )


@admin.route("/companies")
@roles_required("admin", "hr")
def companies():
    search = (request.args.get("search") or "").strip()
    contact_filter = (request.args.get("contact_filter") or "").strip()
    page = request.args.get("page", 1, type=int)
    per_page = 10

    company_query = Company.query

    if search:
        search_pattern = f"%{search}%"
        company_query = company_query.filter(
            or_(
                Company.company_name.ilike(search_pattern),
                Company.contact_number.ilike(search_pattern),
                Company.address.ilike(search_pattern),
            )
        )

    if contact_filter == "with_contact":
        company_query = company_query.filter(
            Company.contact_number.isnot(None),
            Company.contact_number != "",
        )
    elif contact_filter == "without_contact":
        company_query = company_query.filter(
            or_(
                Company.contact_number.is_(None),
                Company.contact_number == "",
            )
        )

    company_pagination = company_query.order_by(Company.id.desc()).paginate(
        page=page,
        per_page=per_page,
        error_out=False,
    )
    company_items = company_pagination.items

    return render_template(
        "admin/companies.html",
        companies=company_items,
        company_pagination=company_pagination,
        company_filters={
            "search": search,
            "contact_filter": contact_filter,
        },
    )

# from sqlalchemy import or_

@admin.route("/dashboard")
@roles_required("admin", "hr")
def dashboard():

    # Total employees
    total_employees = Employee.query.count()

    # Pending employees (from your system: status or employment_status = "Pending")
    pending_employees = Employee.query.filter(
        or_(
            Employee.status == "Pending",
            Employee.employment_status == "Pending"
        )
    ).count()

    return render_template(
        "admin/dashboard.html",
        total_employees=total_employees,
        pending_employees=pending_employees
    )


@admin.route('/register_employee')
def register_employee():
    companies = Company.query.order_by(Company.company_name.asc()).all()
    return render_template('admin/register_employee.html', companies=companies)

@admin.route("/add-employee", methods=["POST"])
def add_employee():

    # Always default status
    employment_status = "Pending"

    # Parse birthdate and compute age
    birth_date = _parse_date(request.form.get("birth_date"))
    age = _compute_age_from_birth_date(birth_date)

    # Get name fields (ADDED FOR DUPLICATE CHECK ONLY)
    first_name = (request.form.get("first_name") or "").strip()
    last_name = (request.form.get("last_name") or "").strip()

    # ✅ DUPLICATE CHECK ADDED (NO OTHER CHANGES)
    existing_employee = Employee.query.filter(
        Employee.first_name.ilike(first_name),
        Employee.last_name.ilike(last_name)
    ).first()

    if existing_employee:
        flash("Employee with the same First Name and Last Name already exists!", "error")
        return redirect(url_for("admin.employees"))

    # Photo upload
    photo_file = request.files.get("photo")
    employee_photo_path = (
        _save_employee_photo(photo_file)[0]
        if photo_file and photo_file.filename
        else None
    )

    # Create employee (ONLY fields from your HTML form)
    new_employee = Employee(
        # Personal Info
        first_name=request.form.get("first_name"),
        middle_name=request.form.get("middle_name"),
        last_name=request.form.get("last_name"),
        suffix=request.form.get("suffix"),
        age=age,
        gender=request.form.get("gender"),
        religion=request.form.get("religion"),
        birth_date=birth_date,
        educational_attainment=request.form.get("educational_attainment"),

        # Contact Info
        email=request.form.get("email"),
        phone=request.form.get("phone"),
        zipCode=request.form.get("zipCode"),
        present_address=request.form.get("present_address"),

        # Employment Info
        employee_no=(request.form.get("employee_no") or "").strip(),
        company=(request.form.get("company") or "").strip(),
        department=(request.form.get("department") or "").strip(),
        hired_date=_parse_date(request.form.get("hired_date")),
        employee_type=request.form.get("employee_type"),

        # Government IDs & Bank
        sss_no=(request.form.get("sss_no") or "").strip(),
        philhealth_no=(request.form.get("philhealth_no") or "").strip(),
        pagibig_no=(request.form.get("pagibig_no") or "").strip(),
        tin_no=(request.form.get("tin_no") or "").strip(),
        valid_id_no=(request.form.get("valid_id_no") or "").strip(),
        account_no=(request.form.get("account_no") or "").strip(),

        # Photo
        photopath=employee_photo_path,

        # DEFAULT STATUS (NO USER INPUT)
        status=(request.form.get("employment_status") or "Active"),
        employment_status=(request.form.get("employment_status") or "Active"),
    )
    _apply_extended_employee_fields(new_employee)

    try:
        db.session.add(new_employee)
        db.session.flush()  # get new_employee.id before creating user

        # Create user account if username is provided
        reg_username = (request.form.get("reg_username") or "").strip()
        reg_password = request.form.get("reg_password") or ""
        reg_confirm = request.form.get("reg_confirm_password") or ""
        reg_role = "user"

        if reg_username:
            if len(reg_username) < 4:
                db.session.rollback()
                flash("Username must be at least 4 characters.", "error")
                return redirect(url_for("admin.employees"))
            if not reg_password or len(reg_password) < 7:
                db.session.rollback()
                flash("Password must be at least 7 characters when creating an account.", "error")
                return redirect(url_for("admin.employees"))
            if reg_password != reg_confirm:
                db.session.rollback()
                flash("Passwords do not match.", "error")
                return redirect(url_for("admin.employees"))

            existing_user = User.query.filter_by(username=reg_username).first()
            if existing_user:
                db.session.rollback()
                flash(f"Username '{reg_username}' is already taken.", "error")
                return redirect(url_for("admin.employees"))

            new_user = User(
                username=reg_username,
                password=generate_password_hash(reg_password, method="pbkdf2:sha256"),
                role=reg_role,
                employee_id=new_employee.id,
            )
            db.session.add(new_user)

        db.session.commit()
        flash("Employee added successfully.", "success")

    except Exception:
        db.session.rollback()
        flash("Error saving employee.", "error")
        return redirect(url_for("admin.employees"))

    return redirect(url_for("employee.view_employee", employee_id=new_employee.id))
# EDIT EMPLOYEE
@admin.route("/edit-employee/<int:employee_id>", methods=["POST"])
@roles_required("admin", "hr")
def edit_employee(employee_id):
    employee = Employee.query.filter_by(id=employee_id).first()
    if not employee:
        flash("Employee not found.", category="error")
        return redirect(url_for("admin.employees"))

    fields_to_check = {
        "email": "Email Address",
        "employee_no": "Employee ID No.",
        "biometric_no": "Biometric No.",
        "sss_no": "SSS No.",
        "philhealth_no": "PhilHealth No.",
        "pagibig_no": "Pag-IBIG No.",
        "tin_no": "TIN No.",
        "valid_id_no": "Valid ID No.",
        "account_no": "Bank Account No.",
    }

    duplicates = []
    existing_employees = Employee.query.filter(Employee.id != employee.id).all()

    for field, label in fields_to_check.items():
        form_val = (request.form.get(field) or "").strip()
        if not form_val:
            continue

        clean_form = form_val.lower() if field == "email" else re.sub(r"[^a-zA-Z0-9]", "", form_val).lower()

        for emp in existing_employees:
            emp_val = getattr(emp, field, "") or ""

            # ✅ FORCE STRING SAFETY
            emp_val = str(emp_val)

            if not emp_val:
                continue

            if field == "email":
                clean_emp = emp_val.lower()
            else:
                clean_emp = re.sub(r"[^a-zA-Z0-9]", "", emp_val).lower()

            if clean_form == clean_emp:
                duplicates.append(label)
                break

    email = (request.form.get("email") or "").strip()
    employee_no = (request.form.get("employee_no") or "").strip()
    biometric_no = (request.form.get("biometric_no") or "").strip()

    if duplicates:
        flash(f"Duplicate data found for: {', '.join(duplicates)}.", category="error")
        return redirect(url_for("admin.employees"))

    employment_status = (request.form.get("employment_status") or "").strip() or employee.employment_status
    company_name = (request.form.get("company") or "").strip()
    birth_date = _parse_date(request.form.get("birth_date")) or employee.birth_date
    hired_date = _parse_date(request.form.get("hired_date")) or employee.hired_date

    first_name = (request.form.get("first_name") or "").strip()
    last_name = (request.form.get("last_name") or "").strip()
    department = (request.form.get("department") or "").strip()
    position = (request.form.get("position") or "").strip()

    # Process photo update if a new photo is uploaded
    photo_file = request.files.get("photo")
    if photo_file and photo_file.filename:
        employee_photo_path, _ = _save_employee_photo(photo_file)
        if employee_photo_path:
            employee.photopath = employee_photo_path  # Only update if a valid new photo exists

    # 1. Personal Information
    employee.first_name = first_name
    employee.middle_name = (request.form.get("middle_name") or "").strip()
    employee.last_name = last_name
    employee.suffix = (request.form.get("suffix") or "").strip()
    employee.birth_date = birth_date
    employee.age = _parse_int(request.form.get("age"))
    employee.gender = request.form.get("gender")
    employee.religion = (request.form.get("religion") or "").strip()
    employee.biometric_no = biometric_no
    employee.educational_attainment = request.form.get("educational_attainment")

    # 2. Contact & Address
    employee.email = email
    employee.phone = (request.form.get("phone") or "").strip()
    employee.zipCode = (request.form.get("zipCode") or "").strip()
    employee.present_address = (request.form.get("present_address") or "").strip()

    # 3. Employment Details
    employee.employee_no = employee_no
    employee.company = company_name
    employee.department = department
    employee.position = position
    employee.hired_date = hired_date
    employee.employee_type = request.form.get("employee_type")
    employee.employment_status = employment_status
    employee.status = employment_status

    # 4. Government IDs & Bank
    employee.sss_no = (request.form.get("sss_no") or "").strip()
    employee.philhealth_no = (request.form.get("philhealth_no") or "").strip()
    employee.pagibig_no = (request.form.get("pagibig_no") or "").strip()
    employee.tin_no = (request.form.get("tin_no") or "").strip()
    employee.valid_id_no = (request.form.get("valid_id_no") or "").strip()
    employee.account_no = (request.form.get("account_no") or "").strip()
    _apply_extended_employee_fields(employee)

    try:
        db.session.commit()
        flash("Employee updated successfully.", category="success")
    except IntegrityError:
        db.session.rollback()
        flash("Duplicate data detected. Please use unique employee details.", category="error")

    return redirect(url_for("admin.employees"))


@admin.route("/add-company", methods=["POST"])
@roles_required("admin", "hr")
def add_company():
    company_name = (request.form.get("company_name") or "").strip()
    contact_number = request.form.get("contact_number")
    address = request.form.get("address")
    logo_path = _save_company_logo(request.files.get("company_logo"))

    if not company_name:
        flash("Company name is required.", category="error")
        return redirect(url_for("admin.companies"))

    new_company = Company(
        company_name=company_name,
        contact_number=contact_number,
        address=address,
        logo_path=logo_path,
    )

    try:
        db.session.add(new_company)
        db.session.commit()
        flash("Company added successfully.", category="success")
    except IntegrityError:
        db.session.rollback()
        flash("Company could not be saved. It may already exist.", category="error")

    return redirect(url_for("admin.companies"))


@admin.route("/edit-company/<int:company_id>", methods=["POST"])
@roles_required("admin", "hr")
def edit_company(company_id):
    company = Company.query.filter_by(id=company_id).first()
    if not company:
        flash("Company not found.", category="error")
        return redirect(url_for("admin.companies"))

    company_name = (request.form.get("company_name") or "").strip()
    contact_number = (request.form.get("contact_number") or "").strip()
    address = (request.form.get("address") or "").strip()

    if not company_name:
        flash("Company name is required.", category="error")
        return redirect(url_for("admin.companies"))

    duplicate_company = Company.query.filter(
        Company.id != company.id,
        Company.company_name == company_name,
    ).first()
    if duplicate_company:
        flash("Company name already exists. Please use a different name.", category="error")
        return redirect(url_for("admin.companies"))

    company.company_name = company_name
    company.contact_number = contact_number or None
    company.address = address or None

    logo_file = request.files.get("company_logo")
    if logo_file and logo_file.filename:
        logo_path = _save_company_logo(logo_file)
        if not logo_path:
            flash("Company logo must be a JPG or PNG file.", category="error")
            return redirect(url_for("admin.companies"))
        company.logo_path = logo_path

    try:
        db.session.commit()
        flash("Company updated successfully.", category="success")
    except IntegrityError:
        db.session.rollback()
        flash("Company could not be updated. It may already exist.", category="error")

    return redirect(url_for("admin.companies"))


@admin.route('/users', methods=['GET'])
@roles_required("admin")
def users():
    user_items = User.query.order_by(User.id.desc()).all()
    return render_template('admin/users.html', users=user_items)


@admin.route("/update-user/<int:user_id>", methods=["POST"])
@roles_required("admin")
def update_user(user_id):
    user = User.query.filter_by(id=user_id).first()
    if not user:
        flash("User not found.", category="error")
        return redirect(url_for("admin.users"))

    raw_role = request.form.get("role") or ""
    role_key = " ".join(
        raw_role.strip().lower().replace("_", " ").replace("-", " ").replace(",", " ").split()
    )
    role_aliases = {
        "admin": "admin",
        "user": "user",
        "hr": "hr",
        "timekeeper": "timekeeper",
        "general manager": "general manager",
        "gm": "general manager",
        "operation": "operation",
        "operations": "operation",
        "dept manager": "dept manager",
        "department manager": "dept manager",
    }
    role = role_aliases.get(role_key)
    if not role:
        flash("Invalid user role.", category="error")
        return redirect(url_for("admin.users"))

    user.role = role

    if user.employee:
        employment_status = (request.form.get("employment_status") or "").strip()
        if employment_status:
            user.employee.employment_status = employment_status
            user.employee.status = employment_status

    try:
        db.session.commit()
        flash("User updated successfully.", category="success")
    except IntegrityError:
        db.session.rollback()
        flash("Could not update user. Please try again.", category="error")

    return redirect(url_for("admin.users"))


@admin.route('/esarf_requests', methods=['GET'])
@roles_required("admin", "timekeeper", "dept manager", "operation", "general manager")
def esarf_requests():
    esarf_request_query = EsarfRequest.query
    current_role = (current_user.role or "").strip().lower()
    if current_role == "operation":
        esarf_request_query = esarf_request_query.filter(
            EsarfRequest.status.in_(
                [
                    ESARF_STATUS_DEPT_MGR_APPROVED,
                    ESARF_STATUS_DEPT_MGR_OPS_APPROVED,
                    ESARF_STATUS_APPROVED,
                ]
            )
        )
    elif current_role == "general manager":
        esarf_request_query = esarf_request_query.filter(
            EsarfRequest.status.in_(
                [
                    ESARF_STATUS_DEPT_MGR_OPS_APPROVED,
                    ESARF_STATUS_APPROVED,
                ]
            )
        )
    esarf_request_items = esarf_request_query.order_by(EsarfRequest.id.desc()).all()
    return render_template('admin/esarf_requests.html', esarf_requests=esarf_request_items)


@admin.route("/esarf_requests/<int:esarf_id>/status", methods=["POST"])
@roles_required("admin", "timekeeper", "dept manager", "operation", "general manager")
def update_esarf_status(esarf_id):
    esarf_request = EsarfRequest.query.filter_by(id=esarf_id).first()
    if not esarf_request:
        flash("ESARF request not found.", category="error")
        return redirect(url_for("admin.esarf_requests"))

    current_role = (current_user.role or "").strip().lower()
    action = (request.form.get("action") or "").strip().lower()

    # Backward-compatible fallback for old forms that still submit "status".
    legacy_status = (request.form.get("status") or "").strip().title()
    if not action and legacy_status == ESARF_STATUS_APPROVED:
        if current_role == "dept manager":
            action = "dept_manager_approve"
        elif current_role == "operation":
            action = "operation_approve"
        elif current_role == "general manager":
            action = "general_manager_approve"
        else:
            action = "approve"
    elif not action and legacy_status == ESARF_STATUS_REJECTED:
        action = "reject"

    if current_role == "dept manager":
        if action == "reject":
            if esarf_request.status != ESARF_STATUS_PENDING:
                flash("Only pending requests can be declined.", category="error")
                return redirect(url_for("admin.esarf_requests"))
            reject_reason = (request.form.get("reject_reason") or "").strip()
            if not reject_reason:
                flash("Decline reason is required.", category="error")
                return redirect(url_for("admin.esarf_requests"))

            esarf_request.status = ESARF_STATUS_REJECTED
            esarf_request.declined_reason = f"Dept Manager: {reject_reason}"
            success_message = f"ESARF request #{esarf_request.id} declined by Dept Manager. Reason: {reject_reason}"
        elif action == "dept_manager_approve":
            if esarf_request.status in {ESARF_STATUS_REJECTED, ESARF_STATUS_APPROVED}:
                flash("This request can no longer be department-manager approved.", category="error")
                return redirect(url_for("admin.esarf_requests"))
            if esarf_request.status in {ESARF_STATUS_DEPT_MGR_APPROVED, ESARF_STATUS_DEPT_MGR_OPS_APPROVED}:
                flash("Department manager approval is already recorded.", category="info")
                return redirect(url_for("admin.esarf_requests"))

            esarf_request.status = ESARF_STATUS_DEPT_MGR_APPROVED
            success_message = (
                f"ESARF request #{esarf_request.id}: Department Manager approval recorded. "
                "Waiting for remaining signatories."
            )
        else:
            flash(
                "Department manager can approve as first signatory or decline pending requests.",
                category="error",
            )
            return redirect(url_for("admin.esarf_requests"))
    elif current_role == "operation":
        if action != "operation_approve":
            flash("Operation role can only record second-signatory approval.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status in {ESARF_STATUS_REJECTED, ESARF_STATUS_APPROVED}:
            flash("This request can no longer be operation-approved.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status == ESARF_STATUS_PENDING:
            flash("Department manager approval is required before operation approval.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status == ESARF_STATUS_DEPT_MGR_OPS_APPROVED:
            flash("Operation approval is already recorded.", category="info")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status != ESARF_STATUS_DEPT_MGR_APPROVED:
            flash("Current request status is not valid for operation approval.", category="error")
            return redirect(url_for("admin.esarf_requests"))

        esarf_request.status = ESARF_STATUS_DEPT_MGR_OPS_APPROVED
        success_message = (
            f"ESARF request #{esarf_request.id}: Operations approval recorded. "
            "Waiting for remaining signatory."
        )
    elif current_role == "general manager":
        if action != "general_manager_approve":
            flash("General manager can only record final-signatory approval.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status in {ESARF_STATUS_REJECTED, ESARF_STATUS_APPROVED}:
            flash("This request can no longer be general-manager approved.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status != ESARF_STATUS_DEPT_MGR_OPS_APPROVED:
            flash("Operations approval is required before general manager approval.", category="error")
            return redirect(url_for("admin.esarf_requests"))

        esarf_request.status = ESARF_STATUS_APPROVED
        success_message = f"ESARF request #{esarf_request.id}: General Manager approval recorded. Request is now Approved."
    elif current_role in {"admin", "timekeeper"}:
        if action != "reject":
            flash(
                "Final approval requires all 3 signatories. "
                "Department manager, operation, and general manager approvals are enabled.",
                category="error",
            )
            return redirect(url_for("admin.esarf_requests"))
        if esarf_request.status != ESARF_STATUS_PENDING:
            flash("Only pending requests can be declined.", category="error")
            return redirect(url_for("admin.esarf_requests"))
        reject_reason = (request.form.get("reject_reason") or "").strip()
        if not reject_reason:
            flash("Decline reason is required.", category="error")
            return redirect(url_for("admin.esarf_requests"))

        role_labels = {
            "admin": "Admin",
            "timekeeper": "Timekeeper",
            "dept manager": "Dept Manager",
        }
        declined_by_label = role_labels.get(current_role, current_role.title())
        esarf_request.status = ESARF_STATUS_REJECTED
        esarf_request.declined_reason = f"{declined_by_label}: {reject_reason}"
        success_message = f"ESARF request #{esarf_request.id} declined by {declined_by_label}. Reason: {reject_reason}"
    else:
        flash("You do not have permission to update this request.", category="error")
        return redirect(url_for("admin.esarf_requests"))

    try:
        db.session.commit()
        flash(success_message, category="success")
    except Exception:
        db.session.rollback()
        flash("Unable to update ESARF request status.", category="error")

    return redirect(url_for("admin.esarf_requests"))


@admin.route('/leave_requests', methods=['GET'])
@roles_required("admin", "timekeeper")
def leave_requests():

    return render_template('admin/leave_requests.html', )


@admin.route('/perk_requests', methods=['GET'])
@login_required
def perk_requests():
    # Allow admin, hr, or assigned perk approvers
    is_approver = PerkApprover.query.filter_by(user_id=current_user.id).first()
    if not is_approver and current_user.role not in ('admin', 'hr'):
        flash('You do not have permission to view perk requests.', category='error')
        return redirect(url_for('views.home'))

    # Build combined list
    all_requests = []
    for d in DiscountRequest.query.order_by(DiscountRequest.created_at.desc()).all():
        all_requests.append({
            'id': d.id,
            'type': 'discount',
            'status': d.status,
            'product_name': d.product_name,
            'quantity': d.quantity,
            'price': d.price,
            'amount': d.amount,
            'discounted_amount': d.discounted_amount,
            'total_amount': d.discounted_amount,
            'transaction_date': d.transaction_date,
            'created_at': d.created_at,
            'declined_reason': d.declined_reason,
            'submitted_by_user': d.submitted_by_user,
        })
    for c in ProductChargeRequest.query.order_by(ProductChargeRequest.created_at.desc()).all():
        all_requests.append({
            'id': c.id,
            'type': 'charge',
            'status': c.status,
            'product_name': c.product_name,
            'quantity': c.quantity,
            'price': c.price,
            'amount': c.total_amount,
            'discounted_amount': None,
            'total_amount': c.total_amount,
            'transaction_date': c.transaction_date,
            'created_at': c.created_at,
            'declined_reason': c.declined_reason,
            'submitted_by_user': c.submitted_by_user,
        })

    # Sort by created_at desc
    all_requests.sort(key=lambda x: x['created_at'] if x['created_at'] else date.min, reverse=True)

    # Counters
    count_all = len(all_requests)
    count_pending = sum(1 for r in all_requests if r['status'] == 'Pending')
    count_approved = sum(1 for r in all_requests if r['status'] == 'Approved')
    count_rejected = sum(1 for r in all_requests if r['status'] == 'Rejected')

    # Filters
    filter_type = request.args.get('type', '') or request.args.get('type_mobile', '')
    filter_status = request.args.get('status', '')
    filter_search = request.args.get('search', '').strip().lower()
    filter_date_from = request.args.get('date_from', '').strip()
    filter_date_to = request.args.get('date_to', '').strip()

    # Parse date range
    date_from = None
    date_to = None
    try:
        if filter_date_from:
            date_from = datetime.strptime(filter_date_from, '%Y-%m-%d').date()
    except ValueError:
        pass
    try:
        if filter_date_to:
            date_to = datetime.strptime(filter_date_to, '%Y-%m-%d').date()
    except ValueError:
        pass

    filtered = all_requests
    if filter_type:
        filtered = [r for r in filtered if r['type'] == filter_type]
    if filter_status:
        filtered = [r for r in filtered if r['status'] == filter_status]
    if filter_search:
        filtered = [r for r in filtered if (
            filter_search in (r['product_name'] or '').lower() or
            filter_search in (r['submitted_by_user'].username or '').lower() or
            (r['submitted_by_user'].employee and filter_search in (
                (r['submitted_by_user'].employee.first_name or '').lower() + ' ' +
                (r['submitted_by_user'].employee.last_name or '').lower()
            ))
        )]
    if date_from:
        filtered = [r for r in filtered if r['created_at'] and r['created_at'].date() >= date_from]
    if date_to:
        filtered = [r for r in filtered if r['created_at'] and r['created_at'].date() <= date_to]

    # Pagination
    per_page = 5
    page = request.args.get('page', 1, type=int)
    total = len(filtered)
    total_pages = max(1, (total + per_page - 1) // per_page)
    page = max(1, min(page, total_pages))
    start = (page - 1) * per_page
    end = start + per_page
    page_requests = filtered[start:end]

    return render_template(
        'admin/perk_requests.html',
        is_approver=is_approver,
        requests=page_requests,
        count_all=count_all,
        count_pending=count_pending,
        count_approved=count_approved,
        count_rejected=count_rejected,
        filter_type=filter_type,
        filter_status=filter_status,
        filter_search=filter_search,
        filter_date_from=filter_date_from,
        filter_date_to=filter_date_to,
        page=page,
        total_pages=total_pages,
        total=total,
        per_page=per_page,
        start=start + 1 if total > 0 else 0,
        end=min(end, total),
    )


@admin.route('/perk_requests/export', methods=['GET'])
@login_required
def export_perk_requests():
    # Permission check
    is_approver = PerkApprover.query.filter_by(user_id=current_user.id).first()
    if not is_approver and current_user.role not in ('admin', 'hr'):
        flash('You do not have permission to export perk requests.', category='error')
        return redirect(url_for('views.home'))

    # Build combined list (same logic as perk_requests)
    all_requests = []
    for d in DiscountRequest.query.order_by(DiscountRequest.created_at.desc()).all():
        all_requests.append({
            'id': d.id,
            'type': 'discount',
            'status': d.status,
            'product_name': d.product_name,
            'quantity': d.quantity,
            'price': d.price,
            'amount': d.amount,
            'discounted_amount': d.discounted_amount,
            'total_amount': d.discounted_amount,
            'transaction_date': d.transaction_date,
            'created_at': d.created_at,
            'declined_reason': d.declined_reason,
            'submitted_by_user': d.submitted_by_user,
        })
    for c in ProductChargeRequest.query.order_by(ProductChargeRequest.created_at.desc()).all():
        all_requests.append({
            'id': c.id,
            'type': 'charge',
            'status': c.status,
            'product_name': c.product_name,
            'quantity': c.quantity,
            'price': c.price,
            'amount': c.total_amount,
            'discounted_amount': None,
            'total_amount': c.total_amount,
            'transaction_date': c.transaction_date,
            'created_at': c.created_at,
            'declined_reason': c.declined_reason,
            'submitted_by_user': c.submitted_by_user,
        })

    all_requests.sort(key=lambda x: x['created_at'] if x['created_at'] else date.min, reverse=True)

    # Apply same filters
    filter_type = request.args.get('type', '') or request.args.get('type_mobile', '')
    filter_status = request.args.get('status', '')
    filter_search = request.args.get('search', '').strip().lower()
    filter_date_from = request.args.get('date_from', '').strip()
    filter_date_to = request.args.get('date_to', '').strip()

    date_from = None
    date_to = None
    try:
        if filter_date_from:
            date_from = datetime.strptime(filter_date_from, '%Y-%m-%d').date()
    except ValueError:
        pass
    try:
        if filter_date_to:
            date_to = datetime.strptime(filter_date_to, '%Y-%m-%d').date()
    except ValueError:
        pass

    filtered = all_requests
    if filter_type:
        filtered = [r for r in filtered if r['type'] == filter_type]
    if filter_status:
        filtered = [r for r in filtered if r['status'] == filter_status]
    if filter_search:
        filtered = [r for r in filtered if (
            filter_search in (r['product_name'] or '').lower() or
            filter_search in (r['submitted_by_user'].username or '').lower() or
            (r['submitted_by_user'].employee and filter_search in (
                (r['submitted_by_user'].employee.first_name or '').lower() + ' ' +
                (r['submitted_by_user'].employee.last_name or '').lower()
            ))
        )]
    if date_from:
        filtered = [r for r in filtered if r['created_at'] and r['created_at'].date() >= date_from]
    if date_to:
        filtered = [r for r in filtered if r['created_at'] and r['created_at'].date() <= date_to]

    # Generate CSV
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['ID', 'Type', 'Employee', 'Product', 'Qty', 'Unit Price', 'Amount', 'Discounted/Total', 'Transaction Date', 'Date Requested', 'Status', 'Decline Reason'])

    for r in filtered:
        user = r['submitted_by_user']
        emp = user.employee if user and user.employee else None
        emp_name = (
            (emp.first_name or '') +
            (' ' + emp.middle_name[:1] + '.' if emp and emp.middle_name else '') +
            ' ' + (emp.last_name or '') +
            (' ' + emp.suffix if emp and emp.suffix else '')
        ).strip() if emp else (user.username if user else 'N/A')

        final_amount = r['discounted_amount'] if r['discounted_amount'] else r['total_amount']
        writer.writerow([
            r['id'],
            r['type'].title(),
            emp_name,
            r['product_name'],
            r['quantity'],
            f"{r['price']:.2f}",
            f"{r['amount']:.2f}",
            f"{final_amount:.2f}",
            r['transaction_date'].strftime('%Y-%m-%d') if r['transaction_date'] else '',
            r['created_at'].strftime('%Y-%m-%d %H:%M') if r['created_at'] else '',
            r['status'],
            r['declined_reason'] or '',
        ])

    output.seek(0)
    return Response(
        output.getvalue(),
        mimetype='text/csv',
        headers={'Content-Disposition': 'attachment; filename=perk_requests.csv'},
    )


@admin.route('/perk_requests/<string:perk_type>/<int:perk_id>/approve', methods=['POST'])
@login_required
def approve_perk(perk_type, perk_id):
    # Check if user is admin/hr or assigned approver
    is_approver = PerkApprover.query.filter_by(user_id=current_user.id).first()
    if not is_approver and current_user.role not in ('admin', 'hr'):
        flash('You do not have permission to approve perk requests.', category='error')
        return redirect(url_for('admin.perk_requests'))

    if perk_type == 'discount':
        if is_approver and not is_approver.can_approve_discount and current_user.role not in ('admin', 'hr'):
            flash('You are not authorized to approve discount requests.', category='error')
            return redirect(url_for('admin.perk_requests'))
        perk = DiscountRequest.query.get_or_404(perk_id)
    elif perk_type == 'charge':
        if is_approver and not is_approver.can_approve_charge and current_user.role not in ('admin', 'hr'):
            flash('You are not authorized to approve charge requests.', category='error')
            return redirect(url_for('admin.perk_requests'))
        perk = ProductChargeRequest.query.get_or_404(perk_id)
    else:
        flash('Invalid perk type.', category='error')
        return redirect(url_for('admin.perk_requests'))

    if perk.status != 'Pending':
        flash('Only pending requests can be approved.', category='error')
        return redirect(url_for('admin.perk_requests'))

    perk.status = 'Approved'
    try:
        db.session.commit()
        flash(f'{perk_type.title()} request #{perk_id} approved.', category='success')
    except Exception:
        db.session.rollback()
        flash('Failed to update request status.', category='error')

    return redirect(url_for('admin.perk_requests'))


@admin.route('/perk_requests/<string:perk_type>/<int:perk_id>/decline', methods=['POST'])
@login_required
def decline_perk(perk_type, perk_id):
    # Check if user is admin/hr or assigned approver
    is_approver = PerkApprover.query.filter_by(user_id=current_user.id).first()
    if not is_approver and current_user.role not in ('admin', 'hr'):
        flash('You do not have permission to decline perk requests.', category='error')
        return redirect(url_for('admin.perk_requests'))

    if perk_type == 'discount':
        if is_approver and not is_approver.can_approve_discount and current_user.role not in ('admin', 'hr'):
            flash('You are not authorized to decline discount requests.', category='error')
            return redirect(url_for('admin.perk_requests'))
        perk = DiscountRequest.query.get_or_404(perk_id)
    elif perk_type == 'charge':
        if is_approver and not is_approver.can_approve_charge and current_user.role not in ('admin', 'hr'):
            flash('You are not authorized to decline charge requests.', category='error')
            return redirect(url_for('admin.perk_requests'))
        perk = ProductChargeRequest.query.get_or_404(perk_id)
    else:
        flash('Invalid perk type.', category='error')
        return redirect(url_for('admin.perk_requests'))

    if perk.status != 'Pending':
        flash('Only pending requests can be declined.', category='error')
        return redirect(url_for('admin.perk_requests'))

    decline_reason = (request.form.get('decline_reason') or '').strip()
    if not decline_reason:
        flash('Decline reason is required.', category='error')
        return redirect(url_for('admin.perk_requests'))

    perk.status = 'Rejected'
    perk.declined_reason = decline_reason
    try:
        db.session.commit()
        flash(f'{perk_type.title()} request #{perk_id} declined.', category='success')
    except Exception:
        db.session.rollback()
        flash('Failed to update request status.', category='error')

    return redirect(url_for('admin.perk_requests'))


# ================= SETTINGS =================

@admin.route('/settings', methods=['GET', 'POST'])
@roles_required("admin")
def settings():
    if request.method == 'POST':
        action = request.form.get('action')

        if action == 'add_approver':
            user_id = request.form.get('user_id')
            can_discount = 'can_approve_discount' in request.form
            can_charge = 'can_approve_charge' in request.form

            if not user_id:
                flash('Please select a user.', category='error')
                return redirect(url_for('admin.settings'))

            user = User.query.get(user_id)
            if not user:
                flash('User not found.', category='error')
                return redirect(url_for('admin.settings'))

            existing = PerkApprover.query.filter_by(user_id=user.id).first()
            if existing:
                flash(f'{user.username} is already a perk approver.', category='error')
                return redirect(url_for('admin.settings'))

            new_approver = PerkApprover(
                user_id=user.id,
                can_approve_discount=can_discount,
                can_approve_charge=can_charge,
            )
            db.session.add(new_approver)
            try:
                db.session.commit()
                flash(f'{user.username} added as perk approver.', category='success')
            except Exception:
                db.session.rollback()
                flash('Failed to add approver.', category='error')
            return redirect(url_for('admin.settings'))

        elif action == 'remove_approver':
            approver_id = request.form.get('approver_id')
            approver = PerkApprover.query.get(approver_id)
            if approver:
                db.session.delete(approver)
                try:
                    db.session.commit()
                    flash('Approver removed.', category='success')
                except Exception:
                    db.session.rollback()
                    flash('Failed to remove approver.', category='error')
            else:
                flash('Approver not found.', category='error')
            return redirect(url_for('admin.settings'))

        elif action == 'update_approver':
            approver_id = request.form.get('approver_id')
            approver = PerkApprover.query.get(approver_id)
            if approver:
                approver.can_approve_discount = 'can_approve_discount' in request.form
                approver.can_approve_charge = 'can_approve_charge' in request.form
                try:
                    db.session.commit()
                    flash('Approver permissions updated.', category='success')
                except Exception:
                    db.session.rollback()
                    flash('Failed to update approver.', category='error')
            else:
                flash('Approver not found.', category='error')
            return redirect(url_for('admin.settings'))

    # GET
    approvers = PerkApprover.query.order_by(PerkApprover.id.desc()).all()
    approver_user_ids = [a.user_id for a in approvers]
    # Users eligible to be approvers (non-admin users that are not already approvers)
    eligible_users = User.query.filter(
        User.id.notin_(approver_user_ids),
        User.role != 'admin',
    ).all()

    return render_template(
        'admin/settings.html',
        approvers=approvers,
        eligible_users=eligible_users,
    )
