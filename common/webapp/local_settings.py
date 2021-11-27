from MappingCommon import MappingCommon

mapc = MappingCommon()
params = mapc.parseYaml("config.yaml")

# *****************************
# Environment specific settings
# *****************************

# DO NOT use "DEBUG = True" in production environments
DEBUG = params['labeller']['DEBUG']

# DO NOT use Unsecure Secrets in production environments
# Generate a safe one with:
#     python -c "import os; print repr(os.urandom(24));"
SECRET_KEY = params['labeller']['SECRET_KEY']

# SQLAlchemy settings
db_user = params['labeller']['db_username']
db_password = params['labeller']['db_password']
db_url= '127.0.0.1:5432'
DB_URL = 'postgresql+psycopg2://{user}:{pw}@{url}/{db}'.format(user=db_user,pw=db_password,url=db_url,db=mapc.db_name)
SQLALCHEMY_DATABASE_URI = DB_URL
SQLALCHEMY_TRACK_MODIFICATIONS = False    # Avoids a SQLAlchemy Warning

# Flask-Mail settings
# For smtp.gmail.com to work, you MUST set "Allow less secure apps" to ON in Google Accounts.
# Change it in https://myaccount.google.com/security#connectedapps (near the bottom).
MAIL_SERVER = params['labeller']['MAIL_SERVER']
MAIL_PORT = params['labeller']['MAIL_PORT']
MAIL_USE_SSL = params['labeller']['MAIL_USE_SSL']
MAIL_USE_TLS = params['labeller']['MAIL_USE_TLS']
MAIL_USERNAME = params['labeller']['MAIL_USERNAME']
MAIL_PASSWORD = params['labeller']['MAIL_PASSWORD']

MAIL_DEFAULT_SENDER = '"AgroImpacts Administrator" <lestes@clarku.edu>'
ADMINS = [
    '"AgroImpacts Administrator" <lestes@clarku.edu>',
    ]
