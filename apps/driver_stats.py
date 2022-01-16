from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, State, MATCH
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
    
    return df_dsy

def get_driver_stats_by_name(name):    
    query = f"""
                SELECT driver_fullname 
                    , driver_team 
                    , total_first_place 
                    , total_second_place 
                    , total_third_place 
                    , total_points 
                    , average_point_gp 
                    , total_count_podiums
                    , win_ration 
                    , count_fastest_lap 
                    , total_lap_raced 
                    , total_lap_not_raced
                    , gp_enter
                FROM udf_driver_stats(name=>'{name}')
            """                   
    df_dsy = pd.read_sql_query(query, con=db.engine)

    return df_dsy


def generate_driver_card(df):
    
    df = get_driver_overview_stats(df)

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
                d_fname = df.loc[j, 'firstname']

                if d_color_team == 'no_color':
                    border_col = {"border":f"2px solid #e10600"}
                else:
                    border_col = {"border":f"2px solid {d_color_team}"}

                df_ds = get_driver_stats_by_name(d_name)
                content_driver_stats = dbc.ListGroup(
                    [
                        dbc.ListGroupItem([
                                html.H6(f"Grand Prix Enter"),
                                html.P(f"{df_ds.iloc[0]['gp_enter']}", style={'marginBottom': 0}),
                            ], 
                            className="d-flex justify-content-between align-items-center",
                        ),
                        dbc.ListGroupItem([
                                html.H6(f"Total Podiums"),
                                html.P(f"{df_ds.iloc[0]['total_count_podiums']}", style={'marginBottom': 0}),
                            ], 
                            className="d-flex justify-content-between align-items-center",  
                        ),
                        dbc.ListGroupItem([
                                html.H6(f"Total Points"),
                                html.P(f"{df_ds.iloc[0]['total_points']} ({df_ds.iloc[0]['average_point_gp']} avg)", style={'marginBottom': 0}),
                            ], 
                            className="d-flex justify-content-between align-items-center",
                        ),
                        dbc.ListGroupItem([
                                html.H6(f"Total Wins"),
                                html.P(f"{df_ds.iloc[0]['total_first_place']}", style={'marginBottom': 0}),
                            ], 
                            className="d-flex justify-content-between align-items-center",
                        ),
                        dbc.ListGroupItem([
                                html.H6(f"Win Ratio"),
                                html.P(f"{df_ds.iloc[0]['win_ration']}", style={'marginBottom': 0}),
                            ], 
                            className="d-flex justify-content-between align-items-center",
                        ),
                        
                    ],
                    flush=True,
                )

                offcanvas = html.Div(
                    [
                        dbc.Button(
                            f"{d_fname} stats", size="sm",
                            id={
                                "type":"open-offcanvas",
                                "index": j
                            }, 
                            n_clicks=0
                        ),
                        # dbc.Button(
                        #     "Open Offcanvas", id={
                        #         "type":"open-offcanvas",
                        #         "index": j
                        #     }, 
                        #     n_clicks=0
                        # ),
                        dbc.Offcanvas(
                            html.Div(
                                [
                                    html.Hr(style={f"border": "1px solid rgb(20 17 17)"}),
                                    html.H3(
                                        f"{d_name}",
                                        style={
                                            "text-align":"center", 
                                            "font-family":"F1-Reg",
                                        }),
                                    html.Hr(style={f"border": "1px solid rgb(20 17 17)"}),
                                    content_driver_stats
                                ]
                            ),
                            id={
                                'type': 'offcanvas-output',
                                'index': j
                            },
                            title=f'Driver Stats',
                            is_open=False,
                        ),
                    ]
                )

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
                                        html.P([f"{d_nationality}"], style={"font-family":"F1-Reg", "font-size":"0.8rem"}),
                                    ],
                                    className="d-flex justify-content-between align-items-center mb-1",
                                ),
                                html.Div(
                                    [
                                        html.H6(f"{d_team}",style={"font-family":"F1-Reg", "font-size":"0.9rem"}),
                                        html.Div(offcanvas),
                                    ],
                                    className="d-flex justify-content-between align-items-center mb-1",
                                )
                            ]
                        ),
                    ],
                    style=border_col, 
                    # className="w-100 hover-shadow"
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

"""
CALLBACK: to render all driver card based on year input
"""

@app.callback(
    Output('driver-cards', 'children'),    
    Input('session-year-input', 'value'),
)
def get_card_layout(year):
    cards_driver = generate_driver_card(year)
    return cards_driver

"""
PATTERN-MATCHING CALLBACK: each canvas will open according to the index of the card in the layout. 
"""
@app.callback(
    Output({'type': 'offcanvas-output', 'index': MATCH}, 'is_open'),
    Input({'type': 'open-offcanvas', 'index': MATCH}, 'n_clicks'),
    State({'type': 'offcanvas-output', 'index': MATCH}, 'is_open'),
)
def display_output(n1, is_open):

    if n1:
        return not is_open
    return is_open

