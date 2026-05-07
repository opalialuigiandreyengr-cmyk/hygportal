import os
import time
from pathlib import Path

from flask import Flask, make_response, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from sqlalchemy import inspect, text, func
from sqlalchemy.exc import OperationalError
from werkzeug.security import check_password_hash, generate_password_hash

db = SQLAlchemy()

DB_NAME = "database.db"


def _load_env_file(file_path):
    if not file_path.exists():
        return

    for raw_line in file_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[7:].strip()
        if not key:
            continue

        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]

        os.environ.setdefault(key, value)


def _sync_service_accounts():
    from .models import User

    account_configs = [
        {
            "username_env": "ADMIN_USERNAME",
            "password_env": "ADMIN_PASSWORD",
            "default_username": "admin",
            "default_password": "admin123",
            "role": "admin",
        },
        {
            "username_env": "HR_USERNAME",
            "password_env": "HR_PASSWORD",
            "default_username": "",
            "default_password": "",
            "role": "hr",
        },
        {
            "username_env": "TIMEKEEPER_USERNAME",
            "password_env": "TIMEKEEPER_PASSWORD",
            "default_username": "",
            "default_password": "",
            "role": "timekeeper",
        },
    ]

    has_changes = False

    for config in account_configs:
        username = (
            os.getenv(config["username_env"], config["default_username"]) or ""
        ).strip()
        password = os.getenv(config["password_env"], config["default_password"]) or ""
        role = config["role"]
        if not username or not password:
            continue

        user = User.query.filter(func.lower(User.username) == username.lower()).first()

        if user is None:
            db.session.add(
                User(
                    username=username,
                    password=generate_password_hash(password, method="pbkdf2:sha256"),
                    role=role,
                )
            )
            has_changes = True
            continue

        if user.role != role:
            user.role = role
            has_changes = True
        if user.employee_id is not None:
            user.employee_id = None
            has_changes = True
        if not user.password or not check_password_hash(user.password, password):
            user.password = generate_password_hash(password, method="pbkdf2:sha256")
            has_changes = True

    if has_changes:
        db.session.commit()


def _sync_employee_columns():
    from .models import Employee

    inspector = inspect(db.engine)
    existing_columns = {
        column["name"] for column in inspector.get_columns(Employee.__tablename__)
    }

    sqlite_types = {
        "Integer": "INTEGER",
        "Float": "FLOAT",
        "Date": "DATE",
        "DateTime": "DATETIME",
        "JSON": "JSON",
        "Text": "TEXT",
    }

    for column in Employee.__table__.columns:
        if column.name in existing_columns:
            continue

        column_type = sqlite_types.get(column.type.__class__.__name__, "VARCHAR")
        if column_type == "VARCHAR" and getattr(column.type, "length", None):
            column_type = f"VARCHAR({column.type.length})"

        db.session.execute(
            text(f"ALTER TABLE {Employee.__tablename__} ADD COLUMN {column.name} {column_type}")
        )

    db.session.commit()


def _sync_user_columns():
    from .models import User

    inspector = inspect(db.engine)
    existing_columns = {
        column["name"] for column in inspector.get_columns(User.__tablename__)
    }

    if "offset_credits" not in existing_columns:
        db.session.execute(
            text(f"ALTER TABLE {User.__tablename__} ADD COLUMN offset_credits FLOAT DEFAULT 0")
        )
        db.session.commit()

    db.session.execute(
        text(f"UPDATE {User.__tablename__} SET offset_credits = 0 WHERE offset_credits IS NULL")
    )
    db.session.commit()


def _sync_esarf_columns():
    from .models import EsarfRequest

    inspector = inspect(db.engine)
    existing_columns = {
        column["name"] for column in inspector.get_columns(EsarfRequest.__tablename__)
    }

    if "esarf_number" not in existing_columns:
        db.session.execute(
            text(f"ALTER TABLE {EsarfRequest.__tablename__} ADD COLUMN esarf_number VARCHAR(20)")
        )
        db.session.commit()

    has_changes = False
    for esarf_request in EsarfRequest.query.filter(
        (EsarfRequest.esarf_number.is_(None)) | (EsarfRequest.esarf_number == "")
    ).order_by(EsarfRequest.id.asc()).all():
        year = esarf_request.created_at.year if esarf_request.created_at else 2026
        esarf_request.esarf_number = f"ESARF-{year}-{esarf_request.id:03d}"
        has_changes = True

    if has_changes:
        try:
            db.session.commit()
        except OperationalError as exc:
            db.session.rollback()
            if "database is locked" not in str(exc).lower():
                raise
            print("Skipped ESARF number backfill because the database is locked.")


def _sync_perk_columns():
    from .models import DiscountRequest, ProductChargeRequest

    inspector = inspect(db.engine)
    for model in (DiscountRequest, ProductChargeRequest):
        existing_columns = {
            column["name"] for column in inspector.get_columns(model.__tablename__)
        }
        if "approval_code" not in existing_columns:
            db.session.execute(
                text(f"ALTER TABLE {model.__tablename__} ADD COLUMN approval_code VARCHAR(12)")
            )

    db.session.commit()


def _sync_departments():
    from .helpers import sync_department_name
    from .models import Employee

    existing_departments = (
        db.session.query(Employee.department)
        .filter(Employee.department.isnot(None), Employee.department != "")
        .distinct()
        .all()
    )
    for department, in existing_departments:
        sync_department_name(department)

    db.session.commit()


def _sync_esarf_approvers():
    from .models import EsarfApprover, User

    approver_roles = {"dept manager", "operation", "general manager"}
    has_changes = False

    for user in User.query.filter(User.role.in_(approver_roles)).all():
        existing = EsarfApprover.query.filter_by(user_id=user.id).first()
        if existing:
            if existing.approver_role != user.role:
                existing.approver_role = user.role
                has_changes = True
            if user.role != "dept manager" and existing.department_name:
                existing.department_name = None
                has_changes = True
            continue

        department_name = None
        if user.role == "dept manager" and user.employee:
            department_name = (user.employee.department or "").strip() or None

        db.session.add(
            EsarfApprover(
                user_id=user.id,
                approver_role=user.role,
                department_name=department_name,
            )
        )
        has_changes = True

    if has_changes:
        db.session.commit()


def _migrate_employee_children_details():
    from .models import Employee

    inspector = inspect(db.engine)
    existing_columns = {
        column["name"] for column in inspector.get_columns(Employee.__tablename__)
    }
    legacy_child_columns = [
        "first_child_full_name",
        "first_child_age",
        "first_child_birth_date",
        "first_child_school",
        "first_child_school_level",
        "first_child_occupation",
        "second_child_full_name",
        "second_child_age",
        "second_child_birth_date",
        "second_child_school",
        "second_child_school_level",
        "second_child_occupation",
        "third_child_full_name",
        "third_child_age",
        "third_child_birth_date",
        "third_child_school",
        "third_child_school_level",
        "third_child_occupation",
    ]
    if not {"children_details", *legacy_child_columns}.issubset(existing_columns):
        return

    legacy_groups = [
        ("first", "First Child"),
        ("second", "2nd Child"),
        ("third", "3rd Child"),
    ]
    has_changes = False

    for employee in Employee.query.filter(Employee.children_details.is_(None)).all():
        row = db.session.execute(
            text(
                "SELECT "
                + ", ".join(legacy_child_columns)
                + " FROM employee WHERE id = :employee_id"
            ),
            {"employee_id": employee.id},
        ).mappings().first()
        children = []

        for prefix, label in legacy_groups:
            child = {
                "label": label,
                "full_name": row[f"{prefix}_child_full_name"],
                "age": row[f"{prefix}_child_age"],
                "birth_date": str(row[f"{prefix}_child_birth_date"] or ""),
                "school": row[f"{prefix}_child_school"],
                "school_level": row[f"{prefix}_child_school_level"],
                "occupation": row[f"{prefix}_child_occupation"],
            }
            if any(value for key, value in child.items() if key != "label"):
                children.append(child)

        if children:
            employee.children_details = children
            has_changes = True

    if has_changes:
        db.session.commit()

def create_app():
    app = Flask(__name__)

    project_root = Path(app.root_path).parent
    _load_env_file(project_root / ".env")

    app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DB_NAME}'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['SECRET_KEY'] = os.getenv("SECRET_KEY", "thisisasecretkey")

    def _static_version():
        static_dir = Path(app.root_path) / 'static'
        newest = 0
        for pattern in ['css/**/*.css', 'js/**/*.js']:
            for f in static_dir.glob(pattern):
                try:
                    mtime = f.stat().st_mtime
                    if mtime > newest:
                        newest = mtime
                except OSError:
                    continue
        return str(int(newest)) if newest else str(int(time.time()))

    @app.context_processor
    def inject_static_version():
        return dict(static_version=_static_version())
    
    db.init_app(app)

    from .views import views
    from .auth import auth
    from .admin import admin
    from .employee import employee
    from .mobile_api import mobile_api
    

    app.register_blueprint(auth, url_prefix='/')
    app.register_blueprint(views, url_prefix='/')
    app.register_blueprint(admin, url_prefix='/')
    app.register_blueprint(employee, url_prefix='/')
    app.register_blueprint(mobile_api)

    from .models import User

    with app.app_context():
        db.create_all()
        _sync_employee_columns()
        _sync_user_columns()
        _sync_esarf_columns()
        _sync_perk_columns()
        _sync_departments()
        _sync_esarf_approvers()
        _migrate_employee_children_details()
        _sync_service_accounts()
        print("Created database!")

    login_manager = LoginManager()
    login_manager.login_view = 'auth.login'
    login_manager.login_message = 'Please login to access this page.'
    login_manager.login_message_category = 'info'
    login_manager.init_app(app)

    @app.context_processor
    def inject_global_user_status():
        from flask_login import current_user
        unread_notification_count = 0
        is_esarf_approver = False
        is_leave_approver = False
        approver_request_count = 0
        if current_user.is_authenticated:
            from .models import Employee, EsarfApprover, EsarfRequest, LeaveApprover, LeaveRequest, Notification, PerkApprover, User
            is_perk_approver = PerkApprover.query.filter_by(user_id=current_user.id).first() is not None
            is_esarf_approver = EsarfApprover.query.filter_by(user_id=current_user.id).first() is not None
            is_leave_approver = LeaveApprover.query.filter_by(user_id=current_user.id).first() is not None
            unread_notification_count = Notification.query.filter_by(
                user_id=current_user.id,
                is_read=False,
            ).count()

            role = (current_user.role or "").strip().lower()
            esarf_count = 0
            leave_count = 0

            if role in {"admin", "timekeeper"}:
                esarf_count = EsarfRequest.query.filter(
                    EsarfRequest.status.in_(["Pending", "Dept Mgr Approved", "Dept Mgr Ops Approved"])
                ).count()
                leave_count = LeaveRequest.query.filter(
                    LeaveRequest.status.in_(["Pending", "Dept/HR Approved"])
                ).count()
            else:
                esarf_assignment = EsarfApprover.query.filter_by(user_id=current_user.id).first()
                if esarf_assignment:
                    esarf_query = EsarfRequest.query
                    if esarf_assignment.approver_role == "dept manager":
                        dept = (esarf_assignment.department_name or "").strip().lower()
                        if dept:
                            esarf_query = (
                                esarf_query.join(EsarfRequest.submitted_by_user)
                                .join(User.employee)
                                .filter(db.func.lower(db.func.trim(Employee.department)) == dept)
                            )
                        else:
                            esarf_query = esarf_query.filter(EsarfRequest.id.is_(None))
                        esarf_query = esarf_query.filter(EsarfRequest.status == "Pending")
                    elif esarf_assignment.approver_role == "operation":
                        esarf_query = esarf_query.filter(EsarfRequest.status == "Dept Mgr Approved")
                    elif esarf_assignment.approver_role == "general manager":
                        esarf_query = esarf_query.filter(EsarfRequest.status == "Dept Mgr Ops Approved")
                    esarf_count = esarf_query.count()

                leave_assignment = LeaveApprover.query.filter_by(user_id=current_user.id).first()
                if leave_assignment:
                    leave_query = LeaveRequest.query
                    if leave_assignment.approver_role == "department":
                        dept = (leave_assignment.department_name or "").strip().lower()
                        if dept:
                            leave_query = (
                                leave_query.join(LeaveRequest.submitted_by_user)
                                .join(User.employee)
                                .filter(db.func.lower(db.func.trim(Employee.department)) == dept)
                            )
                        else:
                            leave_query = leave_query.filter(LeaveRequest.id.is_(None))
                        leave_query = leave_query.filter(LeaveRequest.status == "Pending")
                    elif leave_assignment.approver_role == "hr":
                        leave_query = leave_query.filter(LeaveRequest.status == "Pending")
                    elif leave_assignment.approver_role == "operation":
                        leave_query = leave_query.filter(LeaveRequest.status == "Dept/HR Approved")
                    leave_count = leave_query.count()

            approver_request_count = esarf_count + leave_count
        else:
            is_perk_approver = False
        return dict(
            is_perk_approver=is_perk_approver,
            is_esarf_approver=is_esarf_approver,
            is_leave_approver=is_leave_approver,
            approver_request_count=approver_request_count,
            unread_notification_count=unread_notification_count,
        )

    @login_manager.user_loader
    def load_user(id):
        return User.query.get(int(id))

    @app.route("/sw.js")
    def service_worker():
        response = make_response(send_from_directory(app.static_folder, "sw.js"))
        response.headers["Content-Type"] = "application/javascript; charset=utf-8"
        response.headers["Cache-Control"] = "no-cache"
        return response

    @app.route("/offline")
    def offline():
        return send_from_directory(app.static_folder, "offline.html")
    
    return app
