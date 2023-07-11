# Copyright 2014 SolidBuilds.com. All rights reserved #
# Authors: Ling Thio <ling.thio@gmail.com>


from datetime import datetime
from flask import current_app, flash
from flask import Blueprint, redirect, render_template
from flask import request, url_for
from flask_user import current_user, login_required, roles_accepted
from flask_user.views import _get_safe_next_param, render, _send_registered_email, _endpoint_url, _do_login_user
from flask_user import signals

from webapp import db
from webapp.models.user_models import User, Role, AdminRegisterForm, EmployerRegisterForm, EmployeeRegisterForm
from webapp.models.user_models import AdminProfileForm, EmployerProfileForm, EmployeeProfileForm, SuspendUserForm
from webapp.models.user_models import TrainingVideoForm
from MappingCommon import MappingCommon

# When using a Flask app factory we must use a blueprint to avoid needing 'app' for '@app.route'
main_blueprint = Blueprint('main', __name__, template_folder='templates')

@main_blueprint.route('/')
def base_page():
    return redirect(url_for('main.home_page'))

# The Home page is accessible to anyone
@main_blueprint.route('/home')
def home_page():
    return render_template('pages/home_page.html')

# ----------------------------------------------------------------
# The Administrator page is accessible to authenticated users with the 'admin' role
@main_blueprint.route('/admin')
@roles_accepted('admin')
@login_required
def admin_page():
    return render_template('pages/admin_page.html')

# The Administrator submenu is accessible to authenticated users with the 'admin' role
@main_blueprint.route('/admin/list_admins_employers')
@roles_accepted('admin')
@login_required
def list_admins_employers():
    # Get all users that are admins or employers.
    users = User.query.filter(User.roles.any((Role.name=='admin') | (Role.name=='employer'))).all()
    admin_list = []
    employer_list = []
    for user in users:
        if user.get_roles_string() == 'admin':
            admin_list.append((user.last_name, user.first_name, user.email))
        elif user.get_roles_string() == 'employer':
            employer_list.append((user.company_name, user.last_name, user.first_name, user.email))
    admin_list.sort()
    employer_list.sort()
    return render_template('pages/list_admins_employers_page.html', admin_list=admin_list, employer_list=employer_list)

# The Administrator submenu is accessible to authenticated users with the 'admin' role.
@main_blueprint.route('/employer/list_employees_by_admin')
@roles_accepted('admin')
@login_required
def list_employees_by_admin():
    # Get all users that are employers.
    employers = User.query.filter(User.roles.any(Role.name=='employer')).all()
    employer_list = []
    for employer in employers:
        # Get all users invited by this employer.
        users = User.query.filter(User.invited_by == employer.id).all()
        employee_list = []
        for user in users:
            employee_list.append((user.last_name, user.first_name, user.email))
        employee_list.sort()
        employer_list.append((employer.company_name, employee_list))
    employer_list.sort()
    return render_template('pages/list_employees_by_admin_page.html', employer_list=employer_list)

# The Administrator submenu is accessible to authenticated users with the 'admin' role
@main_blueprint.route('/admin/admin_employer_invite')
@roles_accepted('admin')
@login_required
def admin_employer_invite():
    return redirect(url_for('user.invite'))

# The Administrator submenu is accessible to authenticated users with the 'admin' role
@main_blueprint.route('/admin/suspend_admin_employer_employee', methods=['GET', 'POST'])
@roles_accepted('admin')
@login_required
def suspend_admin_employer_employee():
    
    user_manager =  current_app.user_manager
    db_adapter = user_manager.db_adapter
    form = SuspendUserForm(request.form)

    # Process valid POST
    if request.method == 'POST' and form.validate():
        # Validate the specified email address.
        email = form.email.data
        user = User.query.filter(User.email == email).first()
        if not user:
            flash("No such user", "error")
            return redirect(url_for('main.suspend_admin_employer_employee'))
        if int(form.activate_flag.data):
            activate = True
            verb = 'reactivated.'
        else:
            activate = False
            verb = 'suspended.'
        db_adapter.update_object(user, active=activate)

        # Save modified user record
        db_adapter.commit()

        flash('User has been successfully ' + verb, 'success')

    # Process GET or invalid POST
    return render_template('pages/suspend_admin_employer_employee_page.html', form=form)

# ----------------------------------------------------------------
# The Employer page is accessible to authenticated users with the 'employer' or 'admin' role.
@main_blueprint.route('/employer')
@roles_accepted('employer', 'admin')
@login_required
def employer_page():
    return render_template('pages/employer_page.html')

# The Employer submenu is accessible to authenticated users with the 'employer' role.
@main_blueprint.route('/employer/list_employees_by employer')
@roles_accepted('employer')
@login_required
def list_employees_by_employer():
    # Get all users invited by this employer.
    users = User.query.filter(User.invited_by == current_user.id).all()
    employee_list = []
    for user in users:
        employee_list.append((user.last_name, user.first_name, user.email))
    employee_list.sort()
    employer = User.query.filter(User.id == current_user.id).first()
    return render_template('pages/list_employees_by_employer_page.html', company_name=employer.company_name, employee_list=employee_list)

# The Employer submenu is accessible to authenticated users with the 'employer' role
@main_blueprint.route('/employer/employee_invite')
@roles_accepted('employer')
@login_required
def employee_invite():
    return redirect(url_for('user.invite'))

# The Employer submenu is accessible to authenticated users with the 'employer' role
@main_blueprint.route('/employer/suspend_employee', methods=['GET', 'POST'])
@roles_accepted('employer')
@login_required
def suspend_employee():
    user_manager =  current_app.user_manager
    db_adapter = user_manager.db_adapter
    form = SuspendUserForm(request.form)

    # Process valid POST
    if request.method == 'POST' and form.validate():
        # Validate the specified email address.
        email = form.email.data
        user = User.query.filter((User.email == email) & (User.invited_by == current_user.id)).first()
        if not user:
            flash("No such employee", "error")
            return redirect(url_for('main.suspend_employee'))
        if int(form.activate_flag.data):
            activate = True
            verb = 'reactivated.'
        else:
            activate = False
            verb = 'suspended.'
        db_adapter.update_object(user, active=activate)

        # Save modified user record
        db_adapter.commit()

        flash('Employee has been successfully ' + verb, 'success')

    # Process GET or invalid POST
    return render_template('pages/suspend_employee_page.html', form=form)

# ----------------------------------------------------------------
# The Employee page is accessible to authenticated users with the 'employee' or 'admin' role.
@main_blueprint.route('/employee')
@roles_accepted('employee', 'admin')
@login_required  # Limits access to authenticated users
def employee_page():
    return render_template('pages/employee_page.html')

# The Employee submenu is accessible to authenticated users with the 'employee' role
@main_blueprint.route('/employee/training')
@roles_accepted('employee')
@login_required  # Limits access to authenticated users
def training():
    trainingForm = TrainingVideoForm(request.form)
    mapc = MappingCommon()

    # Read configuration parameters.
    videoUrl = mapc.getConfiguration('VideoUrl')
    introVideo = mapc.getConfiguration('QualTest_IntroVideo')
    introWidth = mapc.getConfiguration('QualTest_IntroVideoWidth')
    introHeight = mapc.getConfiguration('QualTest_IntroVideoHeight')
    instructionalVideo = mapc.getConfiguration('QualTest_InstructionalVideo')
    instructionalWidth = mapc.getConfiguration('QualTest_InstructionalVideoWidth')
    instructionalHeight = mapc.getConfiguration('QualTest_InstructionalVideoHeight')
    introUrl = "%s/%s" % (videoUrl, introVideo)
    instructionalUrl = "%s/%s" % (videoUrl, instructionalVideo)

    # Load up the training form.
    trainingForm.introUrl.data = introUrl
    trainingForm.introWidth.data = introWidth
    trainingForm.introHeight.data = introHeight
    trainingForm.instructionalUrl.data = instructionalUrl
    trainingForm.instructionalWidth.data = instructionalWidth
    trainingForm.instructionalHeight.data = instructionalHeight

    return render_template('pages/training_page.html', form=trainingForm)

# ----------------------------------------------------------------
# The registration page is accessible to all users by invitation only.
def register():
    """ Display registration form and create new User."""

    user_manager =  current_app.user_manager
    db_adapter = user_manager.db_adapter

    safe_next = _get_safe_next_param('next', user_manager.after_login_endpoint)
    safe_reg_next = _get_safe_next_param('reg_next', user_manager.after_register_endpoint)

    # invite token used to determine validity of registeree
    invite_token = request.values.get("token")

    # require invite without a token should disallow the user from registering
    if user_manager.require_invitation and not invite_token:
        flash("Registration is invite only", "error")
        return redirect(url_for('user.login'))

    user_invite = None
    if invite_token and db_adapter.UserInvitationClass:
        user_invite = db_adapter.find_first_object(db_adapter.UserInvitationClass, token=invite_token)
        if user_invite is None:
            flash("Invalid invitation token", "error")
            return redirect(url_for('user.login'))

    # Initialize form
    login_form = user_manager.login_form()                      # for login_or_register.html
    if user_invite.role == 'admin':
        register_form = AdminRegisterForm(request.form)
    elif user_invite.role == 'employer':
        register_form = EmployerRegisterForm(request.form)
    elif user_invite.role == 'employee':
        register_form = EmployeeRegisterForm(request.form)

    if user_invite:
        register_form.invite_token.data = invite_token

    if request.method!='POST':
        login_form.next.data     = register_form.next.data     = safe_next
        login_form.reg_next.data = register_form.reg_next.data = safe_reg_next
        if user_invite:
            register_form.email.data = user_invite.email
            if hasattr(db_adapter.UserInvitationClass, 'role'):
                register_form.role.data = user_invite.role

    # Process valid POST
    if request.method=='POST' and register_form.validate():
        # Create a User object using Form fields that have a corresponding User field
        User = db_adapter.UserClass
        user_class_fields = User.__dict__
        user_fields = {}

        # Create a UserEmail object using Form fields that have a corresponding UserEmail field
        if db_adapter.UserEmailClass:
            UserEmail = db_adapter.UserEmailClass
            user_email_class_fields = UserEmail.__dict__
            user_email_fields = {}

        # Create a UserAuth object using Form fields that have a corresponding UserAuth field
        if db_adapter.UserAuthClass:
            UserAuth = db_adapter.UserAuthClass
            user_auth_class_fields = UserAuth.__dict__
            user_auth_fields = {}

        Role = db_adapter.RoleClass
        role_class_fields = Role.__dict__
        role_fields = {}

        # Enable user account
        if db_adapter.UserProfileClass:
            if hasattr(db_adapter.UserProfileClass, 'active'):
                user_auth_fields['active'] = True
            elif hasattr(db_adapter.UserProfileClass, 'is_enabled'):
                user_auth_fields['is_enabled'] = True
            else:
                user_auth_fields['is_active'] = True
        else:
            if hasattr(db_adapter.UserClass, 'active'):
                user_fields['active'] = True
            elif hasattr(db_adapter.UserClass, 'is_enabled'):
                user_fields['is_enabled'] = True
            else:
                user_fields['is_active'] = True

        # For all form fields
        role = None
        for field_name, field_value in register_form.data.items():
            # Hash password field
            if field_name=='password':
                hashed_password = user_manager.hash_password(field_value)
                if db_adapter.UserAuthClass:
                    user_auth_fields['password'] = hashed_password
                else:
                    user_fields['password'] = hashed_password
            elif field_name == 'role':
                role = Role.query.filter(Role.name == field_value).first()
            # Store corresponding Form fields into the User object and/or UserProfile object
            else:
                if field_name in user_class_fields:
                    user_fields[field_name] = field_value
                if db_adapter.UserEmailClass:
                    if field_name in user_email_class_fields:
                        user_email_fields[field_name] = field_value
                if db_adapter.UserAuthClass:
                    if field_name in user_auth_class_fields:
                        user_auth_fields[field_name] = field_value

        if user_invite:
            user_fields['invited_by'] = user_invite.invited_by

        # Add User record using named arguments 'user_fields'
        user = db_adapter.add_object(User, **user_fields)
        if (role):
            user.roles.append(role)

        if db_adapter.UserProfileClass:
            user_profile = user

        # Add UserEmail record using named arguments 'user_email_fields'
        if db_adapter.UserEmailClass:
            user_email = db_adapter.add_object(UserEmail,
                    user=user,
                    is_primary=True,
                    **user_email_fields)
        else:
            user_email = None

        # Add UserAuth record using named arguments 'user_auth_fields'
        if db_adapter.UserAuthClass:
            user_auth = db_adapter.add_object(UserAuth, **user_auth_fields)
            if db_adapter.UserProfileClass:
                user = user_auth
            else:
                user.user_auth = user_auth

        require_email_confirmation = True
        if user_invite:
            if user_invite.email == register_form.email.data:
                require_email_confirmation = False
                db_adapter.update_object(user, confirmed_at=datetime.utcnow())

            # Clear token so invite can only be used once.
            user_invite.token = None

        db_adapter.commit()

        # Send 'registered' email and delete new User object if send fails
        if user_manager.send_registered_email:
            try:
                # Send 'registered' email
                _send_registered_email(user, user_email, require_email_confirmation)
            except Exception as e:
                # delete new User object if send  fails
                db_adapter.delete_object(user)
                db_adapter.commit()
                raise

        # Send user_registered signal
        signals.user_registered.send(current_app._get_current_object(),
                                     user=user,
                                     user_invite=user_invite)

        # Redirect if USER_ENABLE_CONFIRM_EMAIL is set
        if user_manager.enable_confirm_email and require_email_confirmation:
            safe_reg_next = user_manager.make_safe_url_function(register_form.reg_next.data)
            return redirect(safe_reg_next)

        # Auto-login after register or redirect to login page
        if 'reg_next' in request.args:
            safe_reg_next = user_manager.make_safe_url_function(register_form.reg_next.data)
        else:
            safe_reg_next = _endpoint_url(user_manager.after_confirm_endpoint)
        if user_manager.auto_login_after_register:
            return _do_login_user(user, safe_reg_next)                     # auto-login
        else:
            return redirect(url_for('user.login')+'?next='+quote(safe_reg_next))  # redirect to login page

    # Process GET or invalid POST
    return render(user_manager.register_template,
            form=register_form,
            login_form=login_form,
            register_form=register_form)

# ----------------------------------------------------------------
@main_blueprint.route('/user/profile', methods=['GET', 'POST'])
@login_required
def user_profile():
    # Initialize form
    if current_user.has_role('admin'):
        form = AdminProfileForm(request.form)
    elif current_user.has_role('employer'):
        form = EmployerProfileForm(request.form)
    elif current_user.has_role('employee'):
        form = EmployeeProfileForm(request.form)

    # Process valid POST
    if request.method == 'POST' and form.validate():
        # Copy form fields to user_profile fields
        form.populate_obj(current_user)

        # Save user_profile
        db.session.commit()

        # Redirect to user_profile page
        return redirect(url_for('main.user_profile'))

    # Process GET or invalid POST
    return render_template('pages/user_profile_page.html', form=form)

# ----------------------------------------------------------------
@main_blueprint.route('/select_role_page')
@login_required
def select_role_page():
    if current_user.has_role('admin'):
        return redirect(url_for('main.admin_page'))
    elif current_user.has_role('employer'):
        return redirect(url_for('main.employer_page'))
    elif current_user.has_role('employee'):
        return redirect(url_for('main.employee_page'))
    return redirect(url_for('main.home_page'))
