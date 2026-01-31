from flask import Blueprint, jsonify, render_template, request, flash, redirect, url_for
from flask_login import login_required, login_user, logout_user
from sqlalchemy import func
from werkzeug.security import check_password_hash, generate_password_hash

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
    
    first_name = data.get('first_name', '').strip()
    middle_name = data.get('middle_name', '').strip()
    last_name = data.get('last_name', '').strip()
    email = data.get('email', '').strip()
    birth_date_str = data.get('birth_date') 

    if not all([first_name, last_name, email, birth_date_str]):
        return jsonify({'status': 'error', 'message': 'Please fill in required fields (First, Last, Email, Birthday).'}), 400

    try:
        query = Employee.query.filter(
            func.lower(Employee.email) == email.lower(),
            func.lower(Employee.first_name) == first_name.lower(),
            func.lower(Employee.last_name) == last_name.lower(),
            Employee.birth_date == birth_date_str
        )

        if middle_name:
            query = query.filter(func.lower(Employee.middle_name) == middle_name.lower())
        else:
            query = query.filter((Employee.middle_name == '') | (Employee.middle_name.is_(None)))
        
        employee = query.first()

        if not employee:
            return jsonify({'status': 'error', 'message': 'No employee record found with these details.'}), 404

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
            'redirect_url': url_for('employee.employee_dashboard')
        })

    except Exception as e:
        db.session.rollback()
        print(f"Error: {e}")
        return jsonify({'status': 'error', 'message': 'Database error during registration.'}), 500
