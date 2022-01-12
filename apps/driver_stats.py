from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, State, dash_table
from app import app, db

import pandas as pd
import plotly.express as px

"""
MAIN FUNCTION FOR IMPORT DATASETS 
    > get_season_list_year()
    > get_driver_overview_stats()
"""

def get_season_list_year():
    query = f"""
                    SELECT DISTINCT year FROM vw_race_results ORDER BY YEAR ASC
            """
    df_sly = pd.read_sql_query(query, con=db.engine)
    
    season_list = list()
    for i in df_sly['year']:
        season_list.append(i)
    
    return season_list


def get_driver_overview_stats(yr):
    query = f"""
                SELECT *, ROW_NUMBER() OVER(ORDER BY t.points DESC) AS rank
                FROM (
                    select distinct 
                            driver_id
			                , team
                            , driver_fullname as driver
                            , driver_code       
                            , driver_number as drivernumber
                            , driver_nationality as nationality
                            , total_points as points 
                            , win_total 
                            , coalesce(fc.color_code_hex, 'no_color') as colorhex
                    from public.udf_driver_stand_yearly({yr}) as udf_d
                    inner join fact_constructors fc
                        on udf_d.team = fc.constructors_name
                ) t """                   
    df_dsy = pd.read_sql_query(query, con=db.engine)
    # to dynamically set color based on score points throughout session 
    df_dsy['percent'] = df_dsy['points']/sum(df_dsy['points']) * 100
    df_dsy.loc[df_dsy['percent'].between(0,1.5, inclusive=True), 'color'] = 'danger'
    df_dsy.loc[df_dsy['percent'].between(1.5,5, inclusive=True), 'color'] = 'warning'
    df_dsy.loc[df_dsy['percent'] >= 5.5 , 'color'] = 'success'
    # to get first name from fullname
    splitted = df_dsy['driver'].str.split()
    df_dsy['firstname'] = splitted.str[0]
    
    return generate_driver_card(df_dsy)

def generate_driver_card(df):
    
    driver_card = []
    for i in range(0, len(df.index), 4):
        card_col = []

        for j in range(i, i+4):
            card = []
            

            if j < len(df.index):
                d_name = df.loc[j, 'driver']
                d_point = df.loc[j, 'points']
                d_rank = df.loc[j, 'rank']
                d_team = df.loc[j, 'team']
                d_nationality = df.loc[j, 'nationality'] 
                point_color_grade = df.loc[j, 'color']
                d_color_team = df.loc[j, 'colorhex']
                d_num = df.loc[j, 'drivernumber']
                d_wins = df.loc[j, 'win_total']

                if d_color_team == 'no_color':
                    border_col = {"border":f"2px solid #e10600"}
                else:
                    border_col = {"border":f"2px solid {d_color_team}"}

                card = dbc.Card(children=
                    [
                        dbc.CardBody(children=
                            [
                                html.Div([
                                        html.H6(f"{d_rank}", style={"font-family":"F1-Bold"}),
                                        # html.H6(
                                        #     f"{d_point} PTS"
                                        #     , style={"font-family":"F1-Reg", "color": f"{point_color_grade}"}
                                        #     # , text_color=f"{point_color_grade}",
                                        # ),
                                        html.H6(
                                            dbc.Badge(
                                                f"{d_point} PTS",
                                                color="dark",
                                                text_color=f"{point_color_grade}",
                                                # className="border m-1",
                                            )                         
                                        )
                                    ], 
                                    className="d-flex justify-content-between align-items-center mb-1",
                                    
                                ),
                                html.H5(f"{d_name}", style={"font-family":"F1-Bold"}),
                                html.Hr(style={"border":f"2px solid {d_color_team}"}),
                                html.Div(
                                    [
                                        html.H6(f"{d_num}",style={"font-family":"F1-Reg"}),
                                        html.H6(f"{d_team}",style={"font-family":"F1-Reg", "font-size":"0.9rem"}),
                                    ],
                                    className="d-flex justify-content-between align-items-center mb-1",
                                ),
                                html.P([f"{d_nationality}"], style={"font-family":"F1-Reg", "font-size":"0.8rem"}),
                            ]
                        ),
                    ],
                    style=border_col, 
                    # className="shadow"
                )    

            card_col.append(
                dbc.Col(card)
            )
        driver_card.append(dbc.Row(card_col, className="mb-4"))

    return driver_card


    

get_sl = get_season_list_year()
dropdown_year_cons = html.Div(
    [
        html.H6("Select Year", className="text-dark"),
        dcc.Dropdown(
            id="session-year-input",
            options=[
                {"label": i, "value": i} for i in get_sl
            ],
            value=2016,
        ),
    ]
)

card_year = dbc.Card(
    dbc.CardBody(
    [html.Div(dropdown_year_cons, className="p-1"),],
    # style={"border":"2px solid #e10600"}, 
    )
)

layout = html.Div([
    dbc.Container(
        [
            html.Div(
                [
                    html.Hr(style={"border":"2px solid #e10600"}),
                    html.H1(
                        ["Check out this season's official!"], 
                        style={
                            "text-align":"left", 
                            "font-family":"F1-Bold",
                        }
                    ),
                    html.H6(
                        "Full breakdown of drivers, points and current positions. Follow your favourite F1 drivers on and off the track.",
                        style={
                            "text-align":"left", 
                            "font-family":"F1-Reg",
                        }
                    ),
                    html.Hr(style={"border":"2px solid #e10600"}),
                    html.Div(dropdown_year_cons, className="my-3 p-2"),
                    # html.Div(card_year)
                ],
                className="my-4"
            ),
            # html.Div(card, className="my-4"),
            html.Div(id="driver-cards"),
        ]
        
    ),
    
    
])

@app.callback(
    Output('driver-cards', 'children'),
    Input('session-year-input', 'value'),
)
def get_card_layout(year):
    cards_driver = get_driver_overview_stats(year)
    return cards_driver


# header = dbc.Alert(
#                 [
#                     html.Div(
#                         [
#                             html.H4(
#                                 "Check out this season's official!",
#                                 style={
#                                     "text-align":"left", 
#                                     "font-family":"F1-Bold",
#                                 }
#                             ),
#                             html.H6(
#                                 "Full breakdown of drivers, points and current positions. Follow your favourite F1 drivers on and off the track.",
#                                 style={
#                                     "text-align":"left", 
#                                     "font-family":"F1-Reg",
#                                 }
#                             ),
#                         ], 
#                         className="rounded bg-light text-dark p-2 my-2"
#                     ),
#                     html.Div(dropdown_year_cons, className="my-2"),
#                     # html.Div(gp_slider, className="mt-4 text-light"),
#                 ], color="#e10600", className="mt-4"
#             )