import dash
from dash.dependencies import Input, Output, State
from dash import dcc
from dash import html

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

import pathlib
from app import app, server, db 

# get relative data folder
PATH = pathlib.Path(__file__).parent
# DATA_PATH = PATH.joinpath("../datasets").resolve()

colors = {
    'background': '#111111',
    'text': '#7FDBFF'
}

df = pd.read_sql_query(""" select driver, sum(pointbyrank) as totalpointdriver from get_quali_results group by driver """, con=db.engine)
fig = px.bar(df , x='driver'
                , y='totalpointdriver'
                , barmode="group")

fig.update_layout(
    plot_bgcolor=colors['background'],
    paper_bgcolor=colors['background'],
    font_color=colors['text']
)

layout = html.Div(style={'backgroundColor': colors['background']}, 
                      children= [
    html.H1('Points by driver'
            , style={'textAlign': 'center', 'color': '#7FDBFF'})
    ,html.Div([dcc.Graph(figure=fig)])
])



