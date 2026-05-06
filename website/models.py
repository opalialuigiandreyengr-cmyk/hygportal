from . import db
from .helpers import philippine_now
from flask_login import UserMixin


class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=True, unique=True)
    username = db.Column(db.String(100), unique=True)
    password = db.Column(db.String(255))
    role = db.Column(db.String(50), default='user')
    leave_credits = db.Column(db.Integer)

    employee = db.relationship('Employee', backref=db.backref('user', uselist=False))


class MobileSession(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    token_hash = db.Column(db.String(64), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    last_used_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    pending_perk_request = db.Column(db.JSON)

    user = db.relationship(
        'User',
        backref=db.backref('mobile_sessions', lazy=True, cascade='all, delete-orphan'),
    )


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
    birth_place = db.Column(db.String(150))
    nationality = db.Column(db.String(100))
    height = db.Column(db.String(50))
    weight = db.Column(db.String(50))
    civil_status = db.Column(db.String(50))

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
    house_phone = db.Column(db.String(30))
    social_media_type = db.Column(db.String(50))
    social_media_detail = db.Column(db.String(255))

    present_address = db.Column(db.Text)
    permanent_address = db.Column(db.Text)

    sss_no = db.Column(db.Integer)
    philhealth_no = db.Column(db.Integer)
    pagibig_no = db.Column(db.Integer)
    tin_no = db.Column(db.Integer)
    valid_id_no = db.Column(db.Integer)
    valid_id_type = db.Column(db.String(50))

    elementary_school = db.Column(db.String(150))
    elementary_year_attended = db.Column(db.String(100))
    secondary_school = db.Column(db.String(150))
    secondary_year_attended = db.Column(db.String(100))
    college_school = db.Column(db.String(150))
    college_year_attended = db.Column(db.String(100))
    college_course = db.Column(db.String(150))
    year_graduated = db.Column(db.String(50))

    father_name = db.Column(db.String(150))
    father_occupation = db.Column(db.String(150))
    mother_maiden_name = db.Column(db.String(150))
    mother_occupation = db.Column(db.String(150))
    no_of_siblings = db.Column(db.String(50))
    sibling_birth_order = db.Column(db.String(100))

    spouse_full_name = db.Column(db.String(150))
    spouse_age = db.Column(db.Integer)
    spouse_birth_date = db.Column(db.Date)
    spouse_school = db.Column(db.String(150))
    spouse_course_degree = db.Column(db.String(150))
    spouse_occupation = db.Column(db.String(150))

    no_of_children = db.Column(db.Integer)
    no_of_male_children = db.Column(db.Integer)
    no_of_female_children = db.Column(db.Integer)
    children_details = db.Column(db.JSON)

    @property
    def children_details_list(self):
        return self.children_details if isinstance(self.children_details, list) else []

    account_no = db.Column(db.Integer)
    bank_type = db.Column(db.String(50))

    status = db.Column(db.String(50))
    photopath = db.Column(db.String(255))
    employment_status = db.Column(db.String(50))
    gender = db.Column(db.String(20))

    zipCode = db.Column(db.Integer)


class Company(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    company_name = db.Column(db.String(150), unique=True, nullable=False)
    contact_number = db.Column(db.String(30))
    address = db.Column(db.Text)
    logo_path = db.Column(db.String(255))


class Department(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    department_name = db.Column(db.String(100), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    updated_at = db.Column(
        db.DateTime,
        default=philippine_now,
        onupdate=philippine_now,
        nullable=False,
    )


class EsarfRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    esarf_number = db.Column(db.String(20), unique=True)
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

    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    declined_reason = db.Column(db.String(255))

    submitted_by_user = db.relationship(
        'User',
        backref=db.backref('esarf_requests', lazy=True),
    )


class EsarfApprover(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, unique=True)
    approver_role = db.Column(db.String(50), nullable=False)
    department_name = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    updated_at = db.Column(
        db.DateTime,
        default=philippine_now,
        onupdate=philippine_now,
        nullable=False,
    )

    user = db.relationship(
        'User',
        backref=db.backref('esarf_approver', uselist=False),
    )


class LeaveRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), nullable=False, default='Pending')
    leave_type = db.Column(db.String(20), nullable=False)
    leave_category = db.Column(db.String(100), nullable=False)
    start_date = db.Column(db.Date, nullable=False)
    end_date = db.Column(db.Date, nullable=False)
    reason = db.Column(db.String(255))
    submitted_by_user = db.relationship(
        'User',
        backref=db.backref('leave_requests', lazy=True),
    )


class DiscountRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), nullable=False, default='Pending')
    discount_type = db.Column(db.String(50), nullable=False, default='Goldilocks')
    discount_percent = db.Column(db.Float, nullable=False, default=15.0)
    product_name = db.Column(db.String(150))
    quantity = db.Column(db.Integer)
    price = db.Column(db.Float)
    transaction_date = db.Column(db.Date, nullable=False)
    amount = db.Column(db.Float, nullable=False)
    discounted_amount = db.Column(db.Float, nullable=False)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    approval_code = db.Column(db.String(12))
    declined_reason = db.Column(db.String(255))
    submitted_by_user = db.relationship(
        'User',
        backref=db.backref('discount_requests', lazy=True),
    )


class ProductChargeRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), nullable=False, default='Pending')
    product_name = db.Column(db.String(150), nullable=False)
    quantity = db.Column(db.Integer, nullable=False)
    price = db.Column(db.Float, nullable=False)
    total_amount = db.Column(db.Float, nullable=False)
    transaction_date = db.Column(db.Date)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    approval_code = db.Column(db.String(12))
    declined_reason = db.Column(db.String(255))
    submitted_by_user = db.relationship(
        'User',
        backref=db.backref('product_charge_requests', lazy=True),
    )


class PerkApprover(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, unique=True)
    can_approve_discount = db.Column(db.Boolean, default=True, nullable=False)
    can_approve_charge = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)
    user = db.relationship(
        'User',
        backref=db.backref('perk_approver', uselist=False),
    )


class Notification(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    title = db.Column(db.String(140), nullable=False)
    message = db.Column(db.Text, nullable=False)
    category = db.Column(db.String(40), nullable=False, default='info')
    link_url = db.Column(db.String(255))
    is_read = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(db.DateTime, default=philippine_now, nullable=False)

    user = db.relationship(
        'User',
        backref=db.backref('notifications', lazy=True, cascade='all, delete-orphan'),
    )
