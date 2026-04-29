from flask import Blueprint, jsonify, render_template, request, flash, redirect, url_for
from flask_login import login_required, login_user, logout_user
from sqlalchemy import func, or_
from werkzeug.security import check_password_hash, generate_password_hash
import unicodedata

from . import db
from .models import Employee, User

auth = Blueprint('auth', __name__)


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
                if user.role == 'user':
                    return redirect(url_for('employee.employee_dashboard'))
                if user.role == 'timekeeper':
                    return redirect(url_for('admin.esarf_requests'))
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
    middle_name = unicodedata.normalize('NFC', data.get('middle_name', '').strip())
    last_name = unicodedata.normalize('NFC', data.get('last_name', '').strip())
    email = unicodedata.normalize('NFC', data.get('email', '').strip())
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
        # Step 1: Find by first + last name
        query = Employee.query.filter(
            ci_match(Employee.first_name, first_name),
            ci_match(Employee.last_name, last_name)
        )

        if middle_name:
            query = query.filter(ci_match(Employee.middle_name, middle_name))
        
        if email:
            query = query.filter(func.lower(Employee.email) == email.lower())
        
        employee = query.first()

        if not employee:
            return jsonify({'status': 'error', 'message': 'No employee record found with the provided First and Last Name.'}), 404

        # Step 2: Check birth date if employee has one stored
        if employee.birth_date and birth_date_str:
            # Convert DB date to string for comparison (handles Date objects)
            db_birth_str = employee.birth_date.strftime('%Y-%m-%d') if hasattr(employee.birth_date, 'strftime') else str(employee.birth_date)
            if db_birth_str != birth_date_str:
                return jsonify({'status': 'error', 'message': 'Birth Date does not match our records.'}), 404
        # If employee.birth_date is NULL, skip birth date check

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
            employee_id=employee_id
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
