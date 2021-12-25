import dash
from dash import Input, Output, dcc, html


import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

import pathlib
from app import app, server, db 


df_running_total = pd.read_sql_query(""" select racedate as date, driver, pointrunningtotal from get_race_running_total_points where driver in ('VER', 'HAM', 'BOT') """, con=db.engine)
fig_running_total = px.line(df_running_total 
    , x='date'
    , y='pointrunningtotal'
    , color='driver'
    , markers=True
)

mark_values = {1985:'1985',1988:'1988',1991:'1991',1994:'1994',
               1997:'1997',2000:'2000',2003:'2003',2006:'2006',
               2009:'2009',2012:'2012',2015:'2015',2016:'2016'}

layout = html.Div(children= [
    html.H1('Point by driver on each session'
            , style={'textAlign': 'center'})
    ,html.Div([dcc.Graph(figure=fig_running_total)])
])