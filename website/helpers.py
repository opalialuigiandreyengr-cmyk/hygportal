import os
import uuid
from datetime import datetime
from functools import wraps

from flask import current_app, flash, redirect, url_for
from flask_login import current_user, login_required
from werkzeug.utils import secure_filename

ALLOWED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
MAX_EMPLOYEE_PHOTO_BYTES = 10 * 1024 * 1024


def roles_required(*allowed_roles):
    def decorator(view_func):
        @wraps(view_func)
        @login_required
        def wrapped_view(*args, **kwargs):
            if current_user.role not in allowed_roles:
                flash("You do not have permission to access that page.", category="error")
                return redirect(url_for("views.home"))
            return view_func(*args, **kwargs)

        return wrapped_view

    return decorator


def _parse_date(value):
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _parse_int(value):
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _save_company_logo(file_storage):
    if not file_storage or not file_storage.filename:
        return None

    filename = secure_filename(file_storage.filename)
    _, ext = os.path.splitext(filename.lower())
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        return None

    logo_dir = os.path.join(current_app.root_path, "static", "images", "logos")
    os.makedirs(logo_dir, exist_ok=True)

    unique_filename = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(logo_dir, unique_filename)
    file_storage.save(file_path)
    return f"images/logos/{unique_filename}"


def _save_employee_photo(file_storage):
    if not file_storage or not file_storage.filename:
        return None, "ID picture is required."

    filename = secure_filename(file_storage.filename)
    _, ext = os.path.splitext(filename.lower())
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        return None, "ID picture must be a JPG or PNG file."

    try:
        file_storage.stream.seek(0, os.SEEK_END)
        file_size = file_storage.stream.tell()
        file_storage.stream.seek(0)
    except (AttributeError, OSError):
        file_size = 0

    if file_size > MAX_EMPLOYEE_PHOTO_BYTES:
        return None, "ID picture must be 10MB or smaller."

    photo_dir = os.path.join(current_app.root_path, "static", "images", "employees")
    os.makedirs(photo_dir, exist_ok=True)

    unique_filename = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(photo_dir, unique_filename)
    file_storage.save(file_path)
    return f"images/employees/{unique_filename}", None
