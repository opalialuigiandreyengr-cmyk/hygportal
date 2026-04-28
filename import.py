import pandas as pd
from datetime import date
from website import create_app, db
from website.models import Employee


# =========================
# CONFIG
# =========================
EXCEL_FILE = "employees.xlsx"


# =========================
# HELPERS
# =========================
def parse_date(value):
    if pd.isna(value) or value == "":
        return None

    try:
        return pd.to_datetime(value).date()
    except:
        return None


def clean_value(value):
    if pd.isna(value) or value == "":
        return None
    return str(value).strip()


def calculate_age(birth_date):
    if not birth_date:
        return None

    today = date.today()
    return today.year - birth_date.year - (
        (today.month, today.day) < (birth_date.month, birth_date.day)
    )


# =========================
# IMPORT FUNCTION
# =========================
def import_employees():
    df = pd.read_excel(EXCEL_FILE)

    print(f"Found {len(df)} rows")

    for index, row in df.iterrows():
        try:

            # Parse birthday first (needed for age)
            birth_date = parse_date(row.get("Birthday"))

            employee = Employee(
                # Name
                first_name=clean_value(row.get("First Name")),
                middle_name=clean_value(row.get("Middle Name")),
                last_name=clean_value(row.get("Last Name")),

                # Personal Info
                birth_date=birth_date,
                age=calculate_age(birth_date),  # ✅ AUTO-CALCULATED

                # Address
                present_address=clean_value(row.get("Employee Address 1")),
                permanent_address=clean_value(row.get("Employee Address 1")),
                zipCode=clean_value(row.get("Zip Code")),

                # Dates
                hired_date=parse_date(row.get("Hired Date")),

                # Work
                department=clean_value(row.get("Department")),
                employee_type=clean_value(row.get("Employee Type")),

                # Government IDs
                sss_no=clean_value(row.get("SSS No.")),
                tin_no=clean_value(row.get("TIN No.")),
                philhealth_no=clean_value(row.get("PhilHealth No.")),
                pagibig_no=clean_value(row.get("Pag-Ibig No.")),

                # Bank
                account_no=clean_value(row.get("Account No.")),

                # Default values
                status="Active",
                leave_credits=0,
                employment_status="Regular"
            )

            db.session.add(employee)

            print(
                f"Row {index + 1}: Added "
                f"{employee.first_name} {employee.last_name}"
            )

        except Exception as e:
            print(f"Row {index + 1} ERROR: {str(e)}")

    db.session.commit()
    print("Import completed successfully!")


# =========================
# RUN
# =========================
if __name__ == "__main__":
    app = create_app()

    with app.app_context():
        import_employees()