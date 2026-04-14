import re
from datetime import date

from flask import Blueprint, flash, redirect, render_template, request, session, url_for
from flask_login import current_user
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from flask_login import login_required

from . import db
from .helpers import (
    _parse_date,
    _parse_int,
    _save_company_logo,
    _save_employee_photo,
    roles_required,
)
from .models import Company, Employee, User, EsarfRequest

admin = Blueprint("admin", __name__)

ESARF_STATUS_PENDING = "Pending"
ESARF_STATUS_DEPT_MGR_APPROVED = "Dept Mgr Approved"
ESARF_STATUS_DEPT_MGR_OPS_APPROVED = "Dept Mgr Ops Approved"
ESARF_STATUS_APPROVED = "Approved"
ESARF_STATUS_REJECTED = "Rejected"


def _compute_age_from_birth_date(birth_date):
    if not birth_date:
        return Nones

    today = date.today()
    age = today.year - birth_date.year - (
        (today.month, today.day) < (birth_date.month, birth_date.day)
    )
    return age if age >= 0 else None


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

    if status:
        employee_query = employee_query.filter(
            or_(
                Employee.employment_status.ilike(status),
                Employee.status.ilike(status),
            )
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


@admin.route('/register_employee')
@login_required
def register_employee():
    return render_template('admin/register_employee.html')

@admin.route("/add-employee", methods=["POST"])
@roles_required("admin", "hr")
def add_employee():
    employment_status = (request.form.get("employment_status") or "").strip() or "Active"
    birth_date = _parse_date(request.form.get("birth_date"))
    age = _compute_age_from_birth_date(birth_date)

    fields_to_check = {
        "email": "Email Address",
        "employee_no": "Employee ID No.",
        "biometric_no": "Biometric No.",
        "sss_no": "SSS No.",
        "philhealth_no": "PhilHealth No.",
        "pagibig_no": "Pag-IBIG No.",
        "tin_no": "TIN No.",
        "valid_id_no": "Valid ID No.",
        "account_no": "Bank Account No."
    }

    duplicates =[]
    existing_employees = Employee.query.all()

    for field, label in fields_to_check.items():
        form_val = (request.form.get(field) or "").strip()
        if not form_val:
            continue

        # Clean the input: lowercase and remove spaces/dashes (except for email)
        clean_form = form_val.lower() if field == "email" else re.sub(r"[^a-zA-Z0-9]", "", form_val).lower()

        # Check against existing database records
        for emp in existing_employees:
            emp_val = getattr(emp, field, "") or ""
            if not emp_val:
                continue
            
            clean_emp = emp_val.lower() if field == "email" else re.sub(r"[^a-zA-Z0-9]", "", emp_val).lower()
            
            if clean_form == clean_emp:
                duplicates.append(label)
                break  # Move to the next field once a duplicate is found

    # If any duplicates were found, stop and flash the message
    if duplicates:
        session["add_employee_form"] = request.form.to_dict(flat=True)
        flash(f"Duplicate data found for: {', '.join(duplicates)}.", category="error")
        return redirect(url_for("admin.employees"))

    # 2. Process Photo Upload
    photo_file = request.files.get("photo")
    employee_photo_path = _save_employee_photo(photo_file)[0] if photo_file and photo_file.filename else None

    # 3. Create and Save Employee
    new_employee = Employee(
        first_name=request.form.get("first_name"),
        middle_name=request.form.get("middle_name"),
        last_name=request.form.get("last_name"),
        suffix=request.form.get("suffix"),
        age=age,
        religion=request.form.get("religion"),
        educational_attainment=request.form.get("educational_attainment"),
        birth_date=birth_date,
        hired_date=_parse_date(request.form.get("hired_date")),
        department=request.form.get("department"),
        position=request.form.get("position"),
        company=(request.form.get("company") or "").strip(),
        employee_no=request.form.get("employee_no"),
        biometric_no=request.form.get("biometric_no"),
        employee_type=request.form.get("employee_type"),
        location=request.form.get("location"),
        email=request.form.get("email"),
        phone=request.form.get("phone"),
        present_address=request.form.get("present_address"),
        permanent_address=request.form.get("permanent_address"),
        sss_no=request.form.get("sss_no"),
        philhealth_no=request.form.get("philhealth_no"),
        pagibig_no=request.form.get("pagibig_no"),
        tin_no=request.form.get("tin_no"),
        valid_id_no=request.form.get("valid_id_no"),
        facebook=request.form.get("facebook"),
        account_no=request.form.get("account_no"),
        leave_credits=float(request.form.get("leave_credits") or 0),
        status=employment_status,
        photopath=employee_photo_path,
        employment_status=employment_status,
        gender=request.form.get("gender"),
        payroll_frequency=request.form.get("payroll_frequency"),
        emp_code=request.form.get("emp_code"),
        zipCode=request.form.get("zipCode"),
    )

    try:
        db.session.add(new_employee)
        db.session.commit()
        session.pop("add_employee_form", None)
        flash("Employee added successfully.", category="success")
    except IntegrityError:
        db.session.rollback()
        session["add_employee_form"] = request.form.to_dict(flat=True)
        flash("Duplicate data detected. Please use unique employee details.", category="error")
        
    return redirect(url_for("admin.employees"))


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
            if not emp_val:
                continue

            clean_emp = emp_val.lower() if field == "email" else re.sub(r"[^a-zA-Z0-9]", "", emp_val).lower()
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
    employee.facebook = (request.form.get("facebook") or "").strip()
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
