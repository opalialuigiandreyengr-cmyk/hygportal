"""One-time script to rebuild the employee table with only the columns
defined in models.py, preserving PRIMARY KEY and UNIQUE constraints.

This also drops ALL obsolete columns that are no longer in the model.
"""
import sqlite3

DB_PATH = "instance/database.db"

# These are the ONLY columns that should exist, matching models.py
KEEP_COLUMNS = [
    "id",
    "biometric_no",
    "first_name",
    "middle_name",
    "last_name",
    "suffix",
    "age",
    "religion",
    "educational_attainment",
    "birth_place",
    "nationality",
    "height",
    "weight",
    "civil_status",
    "birth_date",
    "hired_date",
    "department",
    "position",
    "company",
    "employee_no",
    "employee_type",
    "location",
    "email",
    "phone",
    "house_phone",
    "social_media_type",
    "social_media_detail",
    "present_address",
    "permanent_address",
    "sss_no",
    "philhealth_no",
    "pagibig_no",
    "tin_no",
    "valid_id_no",
    "valid_id_type",
    "elementary_school",
    "elementary_year_attended",
    "secondary_school",
    "secondary_year_attended",
    "college_school",
    "college_year_attended",
    "college_course",
    "year_graduated",
    "father_name",
    "father_occupation",
    "mother_maiden_name",
    "mother_occupation",
    "no_of_siblings",
    "sibling_birth_order",
    "spouse_full_name",
    "spouse_age",
    "spouse_birth_date",
    "spouse_school",
    "spouse_course_degree",
    "spouse_occupation",
    "no_of_children",
    "no_of_male_children",
    "no_of_female_children",
    "children_details",
    "account_no",
    "bank_type",
    "status",
    "photopath",
    "employment_status",
    "gender",
    "zipCode",
]

# Proper CREATE TABLE matching models.py
def get_create_sql():
    return """CREATE TABLE employee_new (
        id INTEGER NOT NULL PRIMARY KEY,
        biometric_no VARCHAR(50),
        first_name VARCHAR(100),
        middle_name VARCHAR(100),
        last_name VARCHAR(100),
        suffix VARCHAR(20),
        age INTEGER,
        religion VARCHAR(100),
        educational_attainment VARCHAR(100),
        birth_place VARCHAR(150),
        nationality VARCHAR(100),
        height VARCHAR(50),
        weight VARCHAR(50),
        civil_status VARCHAR(50),
        birth_date DATE,
        hired_date DATE,
        department VARCHAR(50),
        position VARCHAR(100),
        company VARCHAR(100),
        employee_no VARCHAR(50),
        employee_type VARCHAR(50),
        location VARCHAR(100),
        email VARCHAR(100) UNIQUE,
        phone VARCHAR(20),
        house_phone VARCHAR(30),
        social_media_type VARCHAR(50),
        social_media_detail VARCHAR(255),
        present_address TEXT,
        permanent_address TEXT,
        sss_no INTEGER,
        philhealth_no INTEGER,
        pagibig_no INTEGER,
        tin_no INTEGER,
        valid_id_no INTEGER,
        valid_id_type VARCHAR(50),
        elementary_school VARCHAR(150),
        elementary_year_attended VARCHAR(100),
        secondary_school VARCHAR(150),
        secondary_year_attended VARCHAR(100),
        college_school VARCHAR(150),
        college_year_attended VARCHAR(100),
        college_course VARCHAR(150),
        year_graduated VARCHAR(50),
        father_name VARCHAR(150),
        father_occupation VARCHAR(150),
        mother_maiden_name VARCHAR(150),
        mother_occupation VARCHAR(150),
        no_of_siblings VARCHAR(50),
        sibling_birth_order VARCHAR(100),
        spouse_full_name VARCHAR(150),
        spouse_age INTEGER,
        spouse_birth_date DATE,
        spouse_school VARCHAR(150),
        spouse_course_degree VARCHAR(150),
        spouse_occupation VARCHAR(150),
        no_of_children INTEGER,
        no_of_male_children INTEGER,
        no_of_female_children INTEGER,
        children_details JSON,
        account_no INTEGER,
        bank_type VARCHAR(50),
        status VARCHAR(50),
        photopath VARCHAR(255),
        employment_status VARCHAR(50),
        gender VARCHAR(20),
        "zipCode" INTEGER
    )"""


def main():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = OFF")
    cur = conn.cursor()

    # 1. Read current columns
    cur.execute("PRAGMA table_info(employee)")
    current_cols = [row[1] for row in cur.fetchall()]
    print(f"Current columns ({len(current_cols)}): {current_cols}")

    # 2. Find columns being dropped
    dropped = [c for c in current_cols if c not in KEEP_COLUMNS]
    print(f"\nDropping {len(dropped)} obsolete columns: {dropped}")

    # 3. Build column list for data copy (only keep columns that exist in both)
    copy_cols = [c for c in KEEP_COLUMNS if c in current_cols]
    cols_expr = ", ".join(f'"{c}"' for c in copy_cols)

    # 4. Create new table with proper schema
    cur.execute(get_create_sql())
    print("Created employee_new with proper schema (PRIMARY KEY, UNIQUE).")

    # 5. Copy data
    cur.execute(f'INSERT INTO employee_new ({cols_expr}) SELECT {cols_expr} FROM employee')
    print(f"Copied data for {len(copy_cols)} columns.")

    # 6. Drop old and rename
    cur.execute("DROP TABLE employee")
    cur.execute("ALTER TABLE employee_new RENAME TO employee")
    print("Dropped old table, renamed employee_new -> employee.")

    conn.commit()
    conn.execute("PRAGMA foreign_keys = ON")

    # Verify
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(employee)")
    final_cols = [row[1] for row in cur.fetchall()]
    print(f"\nFinal columns ({len(final_cols)}): {final_cols}")

    # Verify row count
    cur.execute("SELECT COUNT(*) FROM employee")
    count = cur.fetchone()[0]
    print(f"Row count: {count}")

    conn.close()
    print("Done!")


if __name__ == "__main__":
    main()
