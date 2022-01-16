import dash
import dash_bootstrap_components as dbc

from flask_sqlalchemy import SQLAlchemy
from flask import Flask

# select the Bootstrap stylesheets and figure templates for the theme toggle here:
url_theme1 = dbc.themes.JOURNAL
url_theme2 = dbc.themes.DARKLY

# meta_tags are required for the app layout to be mobile responsive
dbc_css = (
    "https://cdn.jsdelivr.net/gh/AnnMarieW/dash-bootstrap-templates/dbc.min.css",
    # "https://use.fontawesome.com/releases/v5.10.2/css/all.css",
)

server = Flask(__name__)
app = dash.Dash(__name__
                ,server=server
                ,suppress_callback_exceptions=True
                ,meta_tags=[{'name': 'viewport','content': 'width=device-width, initial-scale=1.0'}]
                ,external_stylesheets=[url_theme1, dbc_css]
)   
server = app.server

server.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# for your home PostgreSQL test table

# server.config["SQLALCHEMY_DATABASE_URI"] = "postgresql://postgres:LewisxMax1212@localhost/devdashf1"

# for your live Heroku PostgreSQL database
username = 'vhqehuwdwfuyyl'
password = '45b56a2442d08dddebcd39177a2048da8054b203ad75e1916fca9cf16980a05b'
host = 'ec2-3-248-87-6.eu-west-1.compute.amazonaws.com'
port = 5432
dbname = 'ddncsklomh2hu2'
server.config["SQLALCHEMY_DATABASE_URI"] = f"postgresql://{username}:{password}@{host}:{port}/{dbname}"
# server.config["SQLALCHEMY_DATABASE_URI"] = "postgresql://gehhvfyrvfuptd:4376c3e910f1b958715a4828aa0d2628c02223b6e5e10000610de23f2226eeab@ec2-54-74-14-109.eu-west-1.compute.amazonaws.com:5432/ddmgclh4fpen7r"

db = SQLAlchemy(server)

