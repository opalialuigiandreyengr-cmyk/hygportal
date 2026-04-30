from datetime import datetime, timedelta
from email.message import EmailMessage
import random
import smtplib

from flask import Blueprint, flash, redirect, render_template, request, session, url_for
from flask_login import current_user, login_required
from werkzeug.security import generate_password_hash

from . import db
from .helpers import _save_employee_photo, create_notification, philippine_now
from .models import Employee, EsarfRequest, LeaveRequest, DiscountRequest, ProductChargeRequest, Notification, User

employee = Blueprint('employee', __name__)

PERK_APPROVAL_EMAIL = "icount.itsolution@gmail.com"
PERK_APPROVAL_PASSWORD = "llpb llss ztrm ujtj"
PERK_APPROVAL_SENDER = "HYG Employee Portal - No Reply"


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


def _activity_sort_date(value):
    if not value:
        return datetime.min
    if isinstance(value, datetime):
        return value
    return datetime.combine(value, datetime.min.time())


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
    pending_esarf_hours = db.session.query(
        db.func.coalesce(db.func.sum(EsarfRequest.total_hours), 0)
    ).filter(
        EsarfRequest.submitted_by_user_id == current_user.id,
        EsarfRequest.status == 'Pending',
    ).scalar()

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
        pending_esarf_hours=float(pending_esarf_hours or 0),
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

    if current_user.role == 'user' and current_user.employee_id != employee_id:
        flash('You can only edit your own profile.', category='error')
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

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
        return redirect(url_for('employee.view_employee', employee_id=employee_id))

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

    return redirect(url_for('employee.view_employee', employee_id=employee_id))


@employee.route('/employee/esarf', methods=['GET', 'POST'])
@login_required
def esarf():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    esarf_form = {}
    esarf_transaction_types = []

    def calculate_esarf_hours(start_time, end_time):
        if not start_time or not end_time:
            return None

        start_dt = datetime.combine(datetime.today(), start_time)
        end_dt = datetime.combine(datetime.today(), end_time)
        if end_dt <= start_dt:
            end_dt = end_dt + timedelta(days=1)

        return round((end_dt - start_dt).total_seconds() / 3600, 2)

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
                )

            transaction_types_csv = ','.join(transaction_types)
            transaction_type_labels = {
                'UT': 'Undertime (UT)',
                'OT': 'Overtime (OT)',
                'FIO': 'Failure to Punch In/Out (FIO)',
                'OB': 'Official Business (OB)',
                'Adjustment': 'Adjustment',
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
                )

            if not all([time_schedule, day_off, payroll_class, date_from, date_to, time_from, time_to, reason]) or total_hours is None:
                flash('Unable to submit ESARF. Please complete all required fields.', category='error')
                return render_template(
                    'employee/esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                )

            new_request = EsarfRequest(
                submitted_by_user_id=current_user.id,
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
            new_request.esarf_number = f"ESARF-{philippine_now().year}-{new_request.id:03d}"
            create_notification(
                current_user.id,
                "ESARF sent",
                f"You submitted {new_request.esarf_number}.",
                category="success",
                link_url=url_for("employee.esarf_requests"),
            )
            db.session.commit()

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
            )

    return render_template('employee/esarf.html', esarf_form=esarf_form, esarf_transaction_types=esarf_transaction_types)



@employee.route('/employee/esarf_requests', methods=['GET'])
@login_required
def esarf_requests():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

    esarf_request_items = EsarfRequest.query.filter_by(submitted_by_user_id=current_user.id).order_by(EsarfRequest.id.desc()).all()
    
    return render_template('employee/esarf_requests.html', esarf_requests=esarf_request_items)


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

        if leave_category == "Others" and not other_leave:
            flash("Please specify your 'Other' leave type.", category="error")
            return redirect(url_for("employee.leaves"))

        # Use the 'other_leave' value if "Others" selected
        final_category = other_leave if leave_category == "Others" else leave_category

        new_leave_request = LeaveRequest(
            submitted_by_user_id=current_user.id,
            start_date=start_date,
            end_date=end_date,
            leave_type=leave_type,
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
            link_url=url_for("employee.leaves"),
        )
        db.session.commit()
        flash("Leave request submitted successfully.", category="success")

    except Exception as e:
        db.session.rollback()
        flash("Failed to submit leave. Check your inputs.", category="error")

    return redirect(url_for("employee.leaves"))



@employee.route('/leaves', methods=['GET', 'POST'])
@login_required
def leaves():
    profile_redirect = _require_employee_profile()
    if profile_redirect:
        return profile_redirect

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
        rejected_count=rejected_count
    )


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
