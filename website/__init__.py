import os
from pathlib import Path

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from sqlalchemy import inspect, text, func
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
    
    db.init_app(app)

    from .views import views
    from .auth import auth
    from .admin import admin
    from .employee import employee
    

    app.register_blueprint(auth, url_prefix='/')
    app.register_blueprint(views, url_prefix='/')
    app.register_blueprint(admin, url_prefix='/')
    app.register_blueprint(employee, url_prefix='/')

    from .models import User

    with app.app_context():
        db.create_all()
        _sync_employee_columns()
        _sync_esarf_columns()
        _migrate_employee_children_details()
        _sync_service_accounts()
        print("Created database!")

    login_manager = LoginManager()
    login_manager.login_view = 'auth.login'
    login_manager.login_message = 'Please login to access this page.'
    login_manager.login_message_category = 'info'
    login_manager.init_app(app)

    @app.context_processor
    def inject_perk_approver_status():
        from flask_login import current_user
        if current_user.is_authenticated:
            from .models import PerkApprover
            is_perk_approver = PerkApprover.query.filter_by(user_id=current_user.id).first() is not None
        else:
            is_perk_approver = False
        return dict(is_perk_approver=is_perk_approver)

    @login_manager.user_loader
    def load_user(id):
        return User.query.get(int(id))
    
    return app
