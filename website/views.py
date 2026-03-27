from flask import Blueprint, redirect, render_template, url_for
from flask_login import current_user, login_required
views = Blueprint('views', __name__)

@views.route('/')
@login_required
def home():
    if current_user.role == 'user':
        return redirect(url_for('employee.employee_dashboard'))
    return render_template("dashboard.html")


@views.route('/attendance')
def attendance():
    return render_template("attendance.html")


@views.route('/about')
def about():
    return render_template("about.html")


@views.route('/founder')
def founder():
    return render_template("founder.html")

@views.route('/esarf')
@login_required
def esarf():
    if current_user.role != 'user':
        return redirect(url_for('views.home'))
    return redirect(url_for('employee.esarf'))
