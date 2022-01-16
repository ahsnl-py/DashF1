from numpy import empty
import time
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, dash_table
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime
from flat_file_reader import schedule_df


future = datetime(2022, schedule_df['month_index'][0], schedule_df['end_date'][0], 0, 0, 0)
now  = datetime.now()
duration = future - now
duration_in_s = duration.total_seconds()
days  = divmod(duration_in_s, 86400)[0]


schedule_cards = []

for i in range(0, len(schedule_df.index), 4):
    card_cols = []
    for j in range(i, i+4):
        card = []
        if j < len(schedule_df.index):
            location = schedule_df.loc[j, 'location']
            month = schedule_df.loc[j, 'month']
            start_date = schedule_df.loc[j, 'start_date']
            end_date = schedule_df.loc[j, 'end_date']
            title = schedule_df.loc[j, 'title']

            card = dbc.Card(children=
                            [
                                dbc.CardBody(children=
                                    [html.H3([f"{location}"], style={"font-family":"F1-Bold"}),
                                    html.H6([f"{month} {start_date}-{end_date}"],style={"font-family":"F1-Reg"}),
                                    html.P([f"{title}"], style={"font-family":"F1-Reg", "font-size":"0.8rem"})]
                                ),
                            ],
                    style={"border":"2px solid #e10600"}
                    )

        card_cols.append(
            dbc.Col(card, style={"padding-top":"0.5rem"})
        )

    schedule_cards.append(dbc.Row(card_cols))

layout = dbc.Container([
            dbc.Card(children=
                [
                    dbc.CardBody(children=
                        [
                            html.H4("Lights out in", style={"text-align":"center", "font-family":"F1-Reg"}),
                            html.Div(children=[
                                html.Div(html.H1(f"{str(days)[0]}", style={"text-align":"center", "font-size":"80px", "font-family":"F1-Bold"}), 
                                    style={"padding":"5px", "margin":"2px", "background":"#e10600", "color":"white", "width":"80px", "border-radius": "10px"}),
                                html.Div(html.H1(f"{str(days)[1]}", style={"text-align":"center", "font-size":"80px", "font-family":"F1-Bold"}), 
                                    style={"padding":"5px", "margin":"2px", "background":"#e10600", "color":"white", "width":"80px", "border-radius": "10px"}),
                                ], style={"display":"flex", "justify-content":"center"}
                            ),
                            html.H3("DAYS", style={"text-align":"center", "font-family":"F1-Bold"})
                        ]
                    ),
                ], style={"border":"none"}
            ),
            html.Div(schedule_cards)
], style={"padding":"0.5rem"})
