import os
from pathlib import Path

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from sqlalchemy import func
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
        ("HR_USERNAME", "HR_PASSWORD", "hr"),
        ("TIMEKEEPER_USERNAME", "TIMEKEEPER_PASSWORD", "timekeeper"),
    ]

    has_changes = False

    for username_key, password_key, role in account_configs:
        username = (os.getenv(username_key) or "").strip()
        password = os.getenv(password_key) or ""
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
        _sync_service_accounts()
        print("Created database!")

    login_manager = LoginManager()
    login_manager.login_view = 'auth.login'
    login_manager.login_message = 'Please login to access this page.'
    login_manager.login_message_category = 'info'
    login_manager.init_app(app)

    @login_manager.user_loader
    def load_user(id):
        return User.query.get(int(id))
    
    return app
