# Settings common to all environments (development|staging|production)
# Place environment specific settings in env_settings.py
# An example file (env_settings_example.py) can be used as a starting point

import os

# Application settings
APP_NAME = "Agricultural Mapping Platform"
APP_SYSTEM_ERROR_SUBJECT_LINE = APP_NAME + " system error"

# Flask settings
WTF_CSRF_ENABLED = True
# Set CSRF time limit to the life of the session
WTF_CSRF_TIME_LIMIT = None

# Flask-SQLAlchemy settings
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Flask-User settings
USER_APP_NAME = APP_NAME

USER_ENABLE_CHANGE_PASSWORD = True  # Allow users to change their password
USER_ENABLE_CHANGE_USERNAME = False  # Allow users to change their username
USER_ENABLE_CONFIRM_EMAIL = True  # Force users to confirm their email
USER_ENABLE_FORGOT_PASSWORD = True  # Allow users to reset their passwords
USER_ENABLE_EMAIL = True  # Register with Email
USER_ENABLE_REGISTRATION = True  # Allow new users to register
USER_ENABLE_RETYPE_PASSWORD = True  # Prompt for `retype password` in:
USER_ENABLE_USERNAME = False  # Register and Login with username

USER_AFTER_CHANGE_PASSWORD_ENDPOINT = 'main.user_profile'
USER_AFTER_CHANGE_USERNAME_ENDPOINT = 'main.user_profile'
USER_AFTER_CONFIRM_ENDPOINT = 'main.select_role_page'
USER_AFTER_FORGOT_PASSWORD_ENDPOINT = 'main.home_page'
USER_AFTER_LOGIN_ENDPOINT = 'main.select_role_page'
USER_AFTER_LOGOUT_ENDPOINT = 'main.home_page'
USER_AFTER_REGISTER_ENDPOINT = 'main.select_role_page'
USER_AFTER_RESEND_CONFIRM_EMAIL_ENDPOINT = 'main.home_page'
USER_AFTER_RESET_PASSWORD_ENDPOINT = 'main.home_page'
USER_UNCONFIRMED_EMAIL_ENDPOINT = 'main.home_page'
USER_UNAUTHORIZED_ENDPOINT = 'main.home_page'

USER_ENABLE_INVITATION = True
USER_REQUIRE_INVITATION = True
USER_INVITE_EXPIRATION = 3*24*3600
USER_AFTER_INVITE_ENDPOINT = 'user.invite'

USER_ENABLE_REMEMBER_ME = False

# Flask_User defaults.
#USER_INVITE_URL = '/user/invite'
#USER_INVITE_TEMPLATE = 'flask_user/invite.html'
#USER_INVITE_EMAIL_TEMPLATE = 'flask_user/emails/invite'
#USER_INVITE_ACCEPT_TEMPLATE = 'flask_user/register.html'
#USER_LOGIN_URL = '/user/sign-in'
#USER_LOGIN_TEMPLATE = 'flask_user/login.html'
