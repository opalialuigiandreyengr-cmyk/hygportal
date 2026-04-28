from datetime import datetime, timedelta

from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required
from werkzeug.security import generate_password_hash

from . import db
from .helpers import _save_employee_photo
from .models import Employee, EsarfRequest, LeaveRequest, DiscountRequest, ProductChargeRequest, User

employee = Blueprint('employee', __name__)


@employee.route('/employee_dashboard')
@login_required
def employee_dashboard():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))
    return render_template('employee/dashboard.html', employee=current_user.employee)


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
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

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
            new_request.esarf_number = f"ESARF-{datetime.utcnow().year}-{new_request.id:03d}"
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
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

    esarf_request_items = EsarfRequest.query.filter_by(submitted_by_user_id=current_user.id).order_by(EsarfRequest.id.desc()).all()
    
    return render_template('employee/esarf_requests.html', esarf_requests=esarf_request_items)


@employee.route('/submit_leave', methods=['POST'])
@login_required
def submit_leave():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

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
        db.session.commit()
        flash("Leave request submitted successfully.", category="success")

    except Exception as e:
        db.session.rollback()
        flash("Failed to submit leave. Check your inputs.", category="error")

    return redirect(url_for("employee.leaves"))



@employee.route('/leaves', methods=['GET', 'POST'])
@login_required
def leaves():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

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
    approved_count = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id, status="approved"
    ).count()
    rejected_count = LeaveRequest.query.filter_by(
        submitted_by_user_id=current_user.id, status="rejected"
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

    # Current year counts for discount cap
    now = datetime.utcnow()
    year_start = datetime(now.year, 1, 1)
    year_end = datetime(now.year, 12, 31, 23, 59, 59)

    discount_used = DiscountRequest.query.filter(
        DiscountRequest.submitted_by_user_id == current_user.id,
        DiscountRequest.status.in_(['Pending', 'Approved']),
        DiscountRequest.created_at >= year_start,
        DiscountRequest.created_at <= year_end,
    ).count()
    discount_remaining = max(0, 6 - discount_used)

    # Check if user has pending charge
    pending_charge = ProductChargeRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
        status='Pending',
    ).first()

    # Check if user has pending discount
    pending_discount = DiscountRequest.query.filter_by(
        submitted_by_user_id=current_user.id,
        status='Pending',
    ).first()

    if request.method == 'POST':
        form_type = request.form.get('form_type')

        if form_type == 'discount':
            if pending_discount:
                flash('You already have a pending discount request. Wait for it to be processed before submitting another.', category='error')
                return redirect(url_for('employee.perks'))
            if discount_remaining <= 0:
                flash('You have reached the maximum of 6 Goldilocks discount transactions for this year.', category='error')
                return redirect(url_for('employee.perks'))

            product_name = (request.form.get('product_name') or '').strip()
            quantity_raw = request.form.get('quantity')
            price_raw = request.form.get('price')
            transaction_date_raw = request.form.get('transaction_date')

            if not product_name or not quantity_raw or not price_raw or not transaction_date_raw:
                flash('Please fill in all discount fields.', category='error')
                return redirect(url_for('employee.perks'))

            try:
                quantity = int(quantity_raw)
                price = float(price_raw)
                if quantity <= 0 or price <= 0:
                    flash('Quantity and price must be greater than zero.', category='error')
                    return redirect(url_for('employee.perks'))

                transaction_date = datetime.strptime(transaction_date_raw, '%Y-%m-%d').date()
                amount = round(quantity * price, 2)
                discounted_amount = round(amount * 0.85, 2)

                new_discount = DiscountRequest(
                    submitted_by_user_id=current_user.id,
                    discount_type='Goldilocks',
                    discount_percent=15.0,
                    product_name=product_name,
                    quantity=quantity,
                    price=price,
                    transaction_date=transaction_date,
                    amount=amount,
                    discounted_amount=discounted_amount,
                )
                db.session.add(new_discount)
                db.session.commit()
                flash(f'Goldilocks discount request submitted. 15% off: {amount:.2f} -> {discounted_amount:.2f}', category='success')
            except ValueError:
                flash('Invalid amount or date. Please check your inputs.', category='error')
            except Exception:
                db.session.rollback()
                flash('Failed to submit discount request. Please try again.', category='error')

            return redirect(url_for('employee.perks'))

        elif form_type == 'charge':
            if pending_charge:
                flash('You already have a pending product charge. Wait for it to be processed before submitting another.', category='error')
                return redirect(url_for('employee.perks'))

            product_name = (request.form.get('product_name') or '').strip()
            quantity_raw = request.form.get('quantity')
            price_raw = request.form.get('price')
            transaction_date_raw = request.form.get('transaction_date')

            if not product_name or not quantity_raw or not price_raw or not transaction_date_raw:
                flash('Please fill in all charge fields.', category='error')
                return redirect(url_for('employee.perks'))

            try:
                quantity = int(quantity_raw)
                price = float(price_raw)
                transaction_date = datetime.strptime(transaction_date_raw, '%Y-%m-%d').date()
                if quantity <= 0 or price <= 0:
                    flash('Quantity and price must be greater than zero.', category='error')
                    return redirect(url_for('employee.perks'))

                total_amount = round(quantity * price, 2)
                if total_amount > 3000:
                    flash(f'Total amount ({total_amount:.2f}) exceeds the credit limit of 3,000.00 pesos.', category='error')
                    return redirect(url_for('employee.perks'))

                new_charge = ProductChargeRequest(
                    submitted_by_user_id=current_user.id,
                    product_name=product_name,
                    quantity=quantity,
                    price=price,
                    total_amount=total_amount,
                    transaction_date=transaction_date,
                )
                db.session.add(new_charge)
                db.session.commit()
                flash(f'Product charge request submitted. Total: {total_amount:.2f} pesos', category='success')
            except ValueError:
                flash('Invalid quantity or price. Please check your inputs.', category='error')
            except Exception:
                db.session.rollback()
                flash('Failed to submit charge request. Please try again.', category='error')

            return redirect(url_for('employee.perks'))

    # Charge credit used: sum of approved charges this year
    charge_credit_used = db.session.query(
        db.func.coalesce(db.func.sum(ProductChargeRequest.total_amount), 0)
    ).filter(
        ProductChargeRequest.submitted_by_user_id == current_user.id,
        ProductChargeRequest.status.in_(['Pending', 'Approved']),
        ProductChargeRequest.created_at >= year_start,
        ProductChargeRequest.created_at <= year_end,
    ).scalar()
    charge_credit_limit = 3000
    charge_credit_remaining = max(0, charge_credit_limit - float(charge_credit_used))

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
        pending_discount=pending_discount,
        pending_charge=pending_charge,
        charge_credit_used=float(charge_credit_used),
        charge_credit_limit=charge_credit_limit,
        charge_credit_remaining=charge_credit_remaining,
        discounts=recent_discounts,
        charges=recent_charges,
    )
