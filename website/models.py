from datetime import datetime

from . import db
from flask_login import UserMixin


class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=True, unique=True)
    username = db.Column(db.String(100), unique=True)
    password = db.Column(db.String(255))
    role = db.Column(db.String(50), default='user')

    employee = db.relationship('Employee', backref=db.backref('user', uselist=False))


class Employee(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    biometric_no = db.Column(db.String(50))
    first_name = db.Column(db.String(100))
    middle_name = db.Column(db.String(100))
    last_name = db.Column(db.String(100))
    suffix = db.Column(db.String(20))
    age = db.Column(db.Integer)
    religion = db.Column(db.String(100))
    educational_attainment = db.Column(db.String(100))

    birth_date = db.Column(db.Date)
    hired_date = db.Column(db.Date)

    department = db.Column(db.String(50))
    position = db.Column(db.String(100))
    company = db.Column(db.String(100))
    employee_no = db.Column(db.String(50))
    employee_type = db.Column(db.String(50))
    location = db.Column(db.String(100))

    email = db.Column(db.String(100), unique=True)
    phone = db.Column(db.String(20))

    present_address = db.Column(db.Text)
    permanent_address = db.Column(db.Text)

    sss_no = db.Column(db.String(50))
    philhealth_no = db.Column(db.String(50))
    pagibig_no = db.Column(db.String(50))
    tin_no = db.Column(db.String(50))
    valid_id_no = db.Column(db.String(50))

    facebook = db.Column(db.String(100))
    instagram = db.Column(db.String(100))
    tiktok = db.Column(db.String(100))

    account_no = db.Column(db.String(50))
    leave_credits = db.Column(db.Float)

    status = db.Column(db.String(50))
    photopath = db.Column(db.String(255))
    employment_status = db.Column(db.String(50))
    gender = db.Column(db.String(20))
    payroll_frequency = db.Column(db.String(50))

    emp_code = db.Column(db.String(50))
    zipCode = db.Column(db.String(20))


class Company(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    company_name = db.Column(db.String(150), unique=True, nullable=False)
    contact_number = db.Column(db.String(30))
    address = db.Column(db.Text)
    logo_path = db.Column(db.String(255))


class EsarfRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), nullable=False, default='Pending')

    time_schedule = db.Column(db.String(50), nullable=False)
    day_off = db.Column(db.String(20), nullable=False)
    payroll_class = db.Column(db.String(50), nullable=False)
    transaction_types = db.Column(db.String(255), nullable=False)  # CSV: OT,OB

    date_from = db.Column(db.Date, nullable=False)
    date_to = db.Column(db.Date, nullable=False)
    time_from = db.Column(db.Time, nullable=False)
    time_to = db.Column(db.Time, nullable=False)
    total_hours = db.Column(db.Float, nullable=False)
    reason = db.Column(db.Text, nullable=False)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    declined_reason = db.Column(db.String(255))

    submitted_by_user = db.relationship(
        'User',
        backref=db.backref('esarf_requests', lazy=True),
    )
