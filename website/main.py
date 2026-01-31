from flask import Flask, render_template, request, flash, redirect, url_for

app = Flask(__name__)
app.secret_key = "secret"  # Use a random secret in production

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        email = request.form.get('email')
        password = request.form.get('password')

        if email != "user@company.com":
            flash("Email does not exist", "error")
        elif password != "password":
            flash("Incorrect password", "warning")
        else:
            flash("Logged in successfully!", "success")
            flash("Remember to check your email for updates", "info")

        return redirect(url_for('index'))

    return render_template('login.html')


if __name__ == "__main__":
    app.run(debug=True)