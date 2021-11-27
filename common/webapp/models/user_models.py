# Copyright 2014 SolidBuilds.com. All rights reserved
#
# Authors: Ling Thio <ling.thio@gmail.com>

from flask_user import current_user
from flask_user import UserMixin
from flask_user.forms import RegisterForm, InviteForm
from flask_wtf import FlaskForm
from wtforms import StringField, IntegerField, SubmitField, BooleanField, RadioField, validators
from webapp import db


# Define the User data model. Make sure to add the flask_user.UserMixin !!
class User(db.Model, UserMixin):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)

    # User authentication information (required for Flask-User)
    email = db.Column(db.Unicode(255), nullable=False, server_default=u'', unique=True)
    confirmed_at = db.Column(db.DateTime())
    password = db.Column(db.String(255), nullable=False, server_default='')
    active = db.Column(db.Boolean(), nullable=False, server_default='0')

    # User information
    first_name = db.Column(db.Unicode(50), nullable=False, server_default=u'')
    last_name = db.Column(db.Unicode(50), nullable=False, server_default=u'')
    company_name = db.Column(db.Unicode(255), nullable=True, server_default=u'')
    street_address = db.Column(db.Unicode(255), nullable=True, server_default=u'')
    city = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    state_province = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    postal_code = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    country = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    phone = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    fax = db.Column(db.Unicode(50), nullable=True, server_default=u'')
    date_of_birth = db.Column(db.Unicode(50), nullable=True, server_default=u'')

    # Relationships

    # Id of user that invited this user to register
    # Unlike 'roles' below which has a many-to-many relationship with users,
    # 'invited_by' only has a many-to-one relationship with users that are inviters.
    # This works because we are only allowing one role per user for AgroImpacts.
    invited_by = db.Column(db.Integer(), db.ForeignKey('users.id', ondelete='CASCADE'))

    roles = db.relationship('Role', secondary='users_roles',
                            backref=db.backref('users', lazy='dynamic'))
    # Default the session length to 1 hour.
    sessionLifetime = 3600

# Define the Role data model
class Role(db.Model):
    __tablename__ = 'roles'
    id = db.Column(db.Integer(), primary_key=True)
    name = db.Column(db.String(50), nullable=False, server_default=u'', unique=True)  # for @roles_accepted()
    label = db.Column(db.Unicode(255), server_default=u'')  # for display purposes
    # Role that is permitted to invite users with 'name' role.
    invited_by = db.Column(db.String(50), nullable=True, server_default=u'')

# Define the UserRoles association model
class UsersRoles(db.Model):
    __tablename__ = 'users_roles'
    id = db.Column(db.Integer(), primary_key=True)
    user_id = db.Column(db.Integer(), db.ForeignKey('users.id', ondelete='CASCADE'))
    role_id = db.Column(db.Integer(), db.ForeignKey('roles.id', ondelete='CASCADE'))

class UserInvitation(db.Model):
    __tablename__ = 'user_invites'
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), nullable=False)
    # User id of the inviter
    invited_by = db.Column(db.Integer, db.ForeignKey('users.id'))
    # Role to be assigned to the invitee once they register
    role = db.Column(db.Integer, db.ForeignKey('roles.id'))
    # Token used for registration page to identify user registering
    token = db.Column(db.String(100), nullable=True, server_default='')

# Define the Admin registration form
class AdminRegisterForm(RegisterForm):
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])

# Define the Employer registration form
# It augments the Flask-User RegisterForm with additional fields
class EmployerRegisterForm(RegisterForm):
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])
    company_name = StringField('Company name', validators=[
        validators.DataRequired('Company name is required')])
    street_address = StringField('Street address', validators=[
        validators.DataRequired('Street address is required')])
    city = StringField('City', validators=[
        validators.DataRequired('City is required')])
    state_province = StringField('State/Province', validators=[
        validators.DataRequired('State/Province is required')])
    postal_code = StringField('Postal code', validators=[
        validators.DataRequired('Postal code is required')])
    country = StringField('Country', validators=[
        validators.DataRequired('Country is required')])
    phone = StringField('Phone', validators=[
        validators.DataRequired('Phone is required')])
    fax = StringField('Fax', validators=[
        validators.DataRequired('Fax is required')])

# Define the Employee registration form
# It augments the Flask-User RegisterForm with additional fields
class EmployeeRegisterForm(RegisterForm):
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])
    street_address = StringField('Street address')
    city = StringField('City')
    state_province = StringField('State/Province')
    postal_code = StringField('Postal code')
    country = StringField('Country')
    phone = StringField('Phone', validators=[
        validators.DataRequired('Phone is required')])
    date_of_birth = StringField('Date of birth')

# Define the Admin profile form
class AdminProfileForm(FlaskForm):
    email = StringField('Email Address', validators=[
        validators.DataRequired('Email address is required')])
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])
    submit = SubmitField('Save')

# Define the Employer profile form
class EmployerProfileForm(FlaskForm):
    email = StringField('Email Address', validators=[
        validators.DataRequired('Email address is required')])
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])
    company_name = StringField('Company name', validators=[
        validators.DataRequired('Company name is required')])
    street_address = StringField('Street address', validators=[
        validators.DataRequired('Street address is required')])
    city = StringField('City', validators=[
        validators.DataRequired('City is required')])
    state_province = StringField('State/Province', validators=[
        validators.DataRequired('State/Province is required')])
    postal_code = StringField('Postal code', validators=[
        validators.DataRequired('Postal code is required')])
    country = StringField('Country', validators=[
        validators.DataRequired('Country is required')])
    phone = StringField('Phone', validators=[
        validators.DataRequired('Phone is required')])
    fax = StringField('Fax', validators=[
        validators.DataRequired('Fax is required')])
    submit = SubmitField('Save')

# Define the Employee profile form
class EmployeeProfileForm(FlaskForm):
    email = StringField('Email Address', validators=[
        validators.DataRequired('Email address is required')])
    first_name = StringField('First name', validators=[
        validators.DataRequired('First name is required')])
    last_name = StringField('Last name', validators=[
        validators.DataRequired('Last name is required')])
    street_address = StringField('Street address')
    city = StringField('City')
    state_province = StringField('State/Province')
    postal_code = StringField('Postal code')
    country = StringField('Country')
    phone = StringField('Phone', validators=[
        validators.DataRequired('Phone is required')])
    date_of_birth = StringField('Date of birth')
    submit = SubmitField('Save')

# Define the Suspend User form
class SuspendUserForm(FlaskForm):
    email = StringField('Email Address', validators=[
        validators.DataRequired('Email address is required')])
    activate_flag = RadioField('', choices=[('0','Suspend'), ('1','Reactivate')]) 
    submit = SubmitField('Submit')

# Define the Mapping form
class MappingForm(FlaskForm):
    # Input fields
    savedMaps = BooleanField()      # True if worker saved results; False if KML was skipped.
    kmlData = StringField()         # KML object representing worker-mapped polygons
    comment = StringField()         # Worker comment (assignment only)

    # Input/Output fields
    kmlName = StringField()
    hitId = IntegerField()
    assignmentId = IntegerField()
    tryNum = IntegerField()         # Try number (qualification test only)

    # Output fields
    reqMethod = StringField()       # Whether preceding request was POST or GET
    progressStatus = StringField()  # Training status (e.g., # KMLs mapped successfully)
    kmlFrameHeight = StringField()  # Height in pixels of iframe for map display
    kmlFrameUrl = StringField()     # URL for generating iframe (e.g., getkml)
    submitTo = StringField()        # URL for showkml.js to submit to when done
    resultsAccepted = StringField() # Boolean indicating to showkml.js whether worker mapped successfully

# Define the History form
class HistoryForm(FlaskForm):
    # Input fields
    inquiryId = IntegerField()      # Assignment ID of a worker inquiry
    inquiryMessage = StringField()  # Associated explanatory worker message

    # Input/Output fields
    timeZone = IntegerField()       # Contains worker's offset in minutes from UTC

    # Output fields
    assignmentData = StringField()  # Assignment query results for current page
    bonusData = StringField()       # Bonus query results for current page
    submitTo = StringField()        # URL for showkml.js to submit to when done
    prompt = BooleanField()         # If true, then prompt worker for question or comment.

# Define the Training Video form
class TrainingVideoForm(FlaskForm):
    # Output fields
    introUrl = StringField()            # Intro video's URL         
    introWidth = StringField()          # Intro video's width in pixels
    introHeight = StringField()         # Intro video's height in pixels
    instructionalUrl = StringField()    # Instructional video's URL
    instructionalWidth = StringField()  # Instruction video's width in pixels
    instructionalHeight = StringField() # Instruction video's height in pixels

