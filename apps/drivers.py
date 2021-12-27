import enum
from numpy import empty
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, dash_table
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

"""
GET DATASETS:
    return driver standings points over the course of selected sessions 
"""
def get_driver_stand_year(year):
    sql = f""" select * from public.func_get_driver_stand_year({year})"""                     
    df_dsy = pd.read_sql_query(sql, con=db.engine)
    # to dynamically set color based on score points throughout session 
    df_dsy['percent'] = df_dsy['points']/sum(df_dsy['points']) * 100
    df_dsy.loc[df_dsy['percent'].between(0,1.5, inclusive=True), 'color'] = 'danger'
    df_dsy.loc[df_dsy['percent'].between(1.5,5, inclusive=True), 'color'] = 'warning'
    df_dsy.loc[df_dsy['percent'] >= 5.5 , 'color'] = 'success'
    # to get first name from fullname
    splitted = df_dsy['driver'].str.split()
    df_dsy['firstname'] = splitted.str[0]
    return generate_driver_card(df_dsy.to_dict())


def generate_driver_card(df_dict):
    driver_props_tuple = list(zip(
         [ t for t in df_dict['driver'].values()]       # 0 driver
        ,[ t for t in df_dict['points'].values()]       # 1 points
        ,[ t for t in df_dict['rank'].values()]         # 2 rank
        ,[ t for t in df_dict['color'].values()]        # 3 color -- dynamically pass args to badge color
        ,[ t for t in df_dict['nationality'].values()]  # 4 nationality
        ,[ t for t in df_dict['podiums'].values()]      # 5 count 1st place in the race
        ,[ t for t in df_dict['team'].values()]         # 6 driver current team 
        ,[ t for t in df_dict['firstname'].values()]    # 7 driver firstname
    ))

    card_content = list()
    for d in driver_props_tuple:
        if d[5] > 0:
            wins_badge = html.Div(dbc.Badge(f"{d[5]} wins", pill=True, color="success", className="me-1"))
        else:
            wins_badge = html.Div("")

        cards = [
            dbc.CardHeader(
                [
                    html.H6(f"{d[2]}"),
                    html.H6(
                        dbc.Badge(
                            f"{d[1]} PTS",
                            color="white",
                            text_color=f"{d[3]}",
                            className="border m-1",
                        )                         
                    ),
                ], className="card-header d-flex justify-content-between align-items-center"
            ),
            dbc.CardBody(
                [
                    html.Div(
                        [
                            html.H5(f"{d[0]}"),
                            wins_badge,
                        ], className="d-flex justify-content-between align-items-center"
                    ),
                
                    html.Hr(),
                    html.Div([
                        html.H6(f"{d[6]}", className="card-text m-0",),            
                        html.H6(f"{d[4]}", className="card-text",),
                    ], className="d-flex justify-content-between align-items-center  mb-4"),
                    dbc.CardLink(f"Checkout {d[7]} stats!", href="#"),
                ]
            ),
        ]

        card_content.append(cards)

    return card_content

get_driver_meta = get_driver_stand_year(2021)
card_list = list()
for i in get_driver_meta:
    col_card = dbc.Col(dbc.Card(i,className="shadow"))
    card_list.append(col_card)

driver_standing_card = dbc.Container([
        dbc.Row([i for i in card_list[0:3]], className="mb-4")
        ,dbc.Row([i for i in card_list[3:7]], className="mb-4")
        ,dbc.Row([i for i in card_list[7:11]], className="mb-4")
        ,dbc.Row([i for i in card_list[11:15]], className="mb-4")
        ,dbc.Row([i for i in card_list[15:20]], className="mb-4")
    ])

layout = html.Div([
    dbc.Container(
        dbc.Alert(
            [
                html.H4("Check out this season's official!", className="alert-heading"),
                html.P(
                "Full breakdown of drivers, points and current positions. Follow your favourite F1 drivers on and off the track."
                ),
                html.Hr(),
            ], color="#FAE5D3", className="mt-4"
        ),
    ),
    driver_standing_card
    
])

