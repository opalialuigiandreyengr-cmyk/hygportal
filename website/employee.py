from datetime import datetime

from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from . import db
from .models import Employee, EsarfRequest, LeaveRequest

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


@employee.route('/employee/esarf', methods=['GET', 'POST'])
@login_required
def esarf():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

    esarf_form = {}
    esarf_transaction_types = []

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
        reason = request.form.get('reason')

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
            total_hours = float(total_hours_raw) if total_hours_raw else None

            if date_from and date_to and date_to < date_from:
                flash('Date To cannot be earlier than Date From.', category='error')
                return render_template(
                    'esarf.html',
                    esarf_form=esarf_form,
                    esarf_transaction_types=esarf_transaction_types,
                )

            transaction_types_csv = ','.join(transaction_types)

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
            db.session.commit()

            flash(
                f'ESARF request submitted successfully. Transaction Type: {transaction_types_csv}',
                category='success',
            )
            return redirect(url_for('employee.esarf'))
        except Exception:
            db.session.rollback()
            flash('Unable to submit ESARF. Please check your inputs and try again.', category='error')
            return render_template(
                'esarf.html',
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


@employee.route('/submit_leave', methods=['GET', 'POST'])
def submit_leave():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

    if request.method == "POST":
        start_date = datetime.strptime(
        request.form.get("start_date"), "%Y-%m-%d").date()
        end_date = datetime.strptime(
        request.form.get("end_date"), "%Y-%m-%d").date()
        leave_type = request.form.get("leave_date")
        leave_category = request.form.get("leave_category")
        reason = request.form.get("reason")

    new_leave_request = LeaveRequest(
        submitted_by_user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        leave_type=leave_category,
        leave_category=leave_category,
        reason=reason,
    )
    db.session.add(new_leave_request)
    db.session.commit()
    flash(f"Leave request submitted successfull")
    return redirect(url_for("employee.leaves"))


@employee.route('/leaves', methods=['GET', 'POST'])
def leaves():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))

    return render_template("leaves.html", user=current_user)