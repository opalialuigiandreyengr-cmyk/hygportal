from flask import Blueprint, jsonify, render_template, request, flash, redirect, url_for
from flask_login import login_required, login_user, logout_user
from sqlalchemy import func, or_
from werkzeug.security import check_password_hash, generate_password_hash
from datetime import datetime
import unicodedata

from . import db
from .models import Employee, User

auth = Blueprint('auth', __name__)

def _is_at_least_one_year_from_hired_date(hired_date):
    if not hired_date:
        return False

    today = datetime.now().date()
    years = today.year - hired_date.year
    if (today.month, today.day) < (hired_date.month, hired_date.day):
        years -= 1
    return years >= 1


@auth.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = (request.form.get('username') or '').strip()
        password = request.form.get('password') or ''

        user = User.query.filter(func.lower(User.username) == username.lower()).first()
        if user:
            if check_password_hash(user.password, password):
                flash('Logged in successfully!', category='success')
                login_user(user)
                if (user.role or '').strip().lower() == 'user':
                    return redirect(url_for('employee.employee_dashboard'))
                return redirect(url_for('views.home'))
            else:
                flash('Incorrect password, try again.', category='error')
        else:
            flash('Username does not exist.', category='error')
         
    return render_template('login.html')


# ---------------------
# LOGOUT
# ---------------------
@auth.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('views.home'))


@auth.route('/register', methods=['GET'])
def register():
    return render_template("register.html")

# STEP 1: VERIFY EMPLOYEE
@auth.route('/api/verify-employee', methods=['POST'])
def verify_employee():
    data = request.get_json()
    
    first_name = unicodedata.normalize('NFC', data.get('first_name', '').strip())
    last_name = unicodedata.normalize('NFC', data.get('last_name', '').strip())
    birth_date_str = data.get('birth_date') 

    if not first_name or not last_name or not birth_date_str:
        return jsonify({'status': 'error', 'message': 'First Name, Last Name, and Birth Date are required.'}), 400

    def ci_match(column, value):
        """Case-insensitive match that works with SQLite's ASCII-only lower()/upper()."""
        if not value:
            return column.is_(None)
        return or_(
            func.lower(column) == value.lower(),
            column == value,
            column == value.upper(),
            column == value.lower(),
            column == value.title(),
        )

    try:
        try:
            birth_date = datetime.strptime(birth_date_str, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({'status': 'error', 'message': 'Please enter a valid Birth Date.'}), 400

        # Registration verification is based only on first name, last name, and birth date.
        query = Employee.query.filter(
            ci_match(Employee.first_name, first_name),
            ci_match(Employee.last_name, last_name),
            Employee.birth_date == birth_date,
        )
        
        employee = query.first()

        if not employee:
            return jsonify({'status': 'error', 'message': 'No employee record found with the provided First Name, Last Name, and Birth Date.'}), 404

        existing_user = User.query.filter_by(employee_id=employee.id).first()
        if existing_user:
            return jsonify({'status': 'error', 'message': 'An account already exists for this employee.'}), 409

        return jsonify({
            'status': 'success', 
            'message': 'Employee verified successfully.',
            'employee_id': employee.id 
        })

    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'status': 'error', 'message': 'Internal Server Error'}), 500


# STEP 2 & 3: CREATE ACCOUNT
@auth.route('/api/complete-registration', methods=['POST'])
def complete_registration():
    data = request.get_json()
    
    employee_id = data.get('employee_id')
    username = data.get('username', '').strip()
    password = data.get('password')
    confirm_password = data.get('confirm_password')
    terms_accepted = data.get('terms_accepted') 

    if not terms_accepted:
        return jsonify({'status': 'error', 'message': 'You must accept the Terms and Conditions.'}), 400

    if not employee_id:
        return jsonify({'status': 'error', 'message': 'Session lost. Please verify employee details again.'}), 400

    if len(username) < 4:
        return jsonify({'status': 'error', 'message': 'Username must be at least 4 characters.'}), 400

    if len(password) < 7:
        return jsonify({'status': 'error', 'message': 'Password must be at least 7 characters.'}), 400

    if password != confirm_password:
        return jsonify({'status': 'error', 'message': 'Passwords do not match.'}), 400

    user_check = User.query.filter_by(username=username).first()
    if user_check:
        return jsonify({'status': 'error', 'message': 'Username is already taken.'}), 400

    try:
        employee = Employee.query.get(employee_id)
        if not employee:
            return jsonify({'status': 'error', 'message': 'Employee record no longer exists.'}), 404

        new_user = User(
            username=username,
            password=generate_password_hash(password, method='pbkdf2:sha256'),
            role='user',
            employee_id=employee_id,
            leave_credits=7 if _is_at_least_one_year_from_hired_date(employee.hired_date) else 0,
            offset_credits=0.0,
        )

        db.session.add(new_user)
        db.session.commit()
        login_user(new_user, remember=True)

        return jsonify({
            'status': 'success', 
            'message': 'Registration successful!',
            'redirect_url': url_for('employee.view_employee', employee_id=employee.id)
        })

    except Exception as e:
        db.session.rollback()
        print(f"Error: {e}")
        return jsonify({'status': 'error', 'message': 'Database error during registration.'}), 500
