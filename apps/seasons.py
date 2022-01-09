import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output
import plotly.express as px
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

import dash_bootstrap_components as dbc
from dash import Input, Output, html

"""
    CONTENT SOURCE: Get race available from 2011-onwards
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
        
"""
    CONTENT GENERATOR: Generate three different tab that contains
        > Winning stats
        > Fastestes Lap stats
        > Laps stat -- closer look on each driver completed race during race gp year
"""
def generate_win_stat(df):
    fig_bar = go.Figure()
    fig_chart = go.Figure()
    fig_bar = px.bar(df , x=["total_first_place", "total_second_place", "total_third_place"]
                    , y="driver_fullname"
                    , orientation='h'
                    , title="Driver Standing Total"
                    , color_discrete_sequence=['#54A24B', '#EECA3B', '#B279A2']
    )

    fig_chart = px.pie(df
            , names='driver_team'
            , values='total_count_podiums'
            , title='Team total point earn by driver'
            , color_discrete_sequence=px.colors.qualitative.T10
        )
    fig_chart.update_traces(textposition='inside', textinfo='percent+label')
    fig_bar.update_layout(
        yaxis=dict(
            title_text="Driver Name",
            titlefont=dict(size=12),
        ),
        xaxis=dict(
            title_text="Total Podium Count",
            titlefont=dict(size=12),
        )
    )

    row_item = dbc.Row([
        dbc.Col(dcc.Graph(figure=fig_bar, style={'width': '90vh', 'height': '90vh'})),
        dbc.Col(dcc.Graph(figure=fig_chart, style={'width': '70vh', 'height': '70vh'}))
    ])

    return html.Div([row_item])

def generate_fastest_lap_stats(df):
    fig = go.Figure()
    fig_chart = go.Figure()
    fig = px.bar(df , x='count_fastest_lap'
                    , y="driver_fullname"
                    , orientation='h'
                    , title="Driver Fastest Lap Total"
                    , color_discrete_sequence=['#4C78A8']
    )
    fig_chart = px.pie(df
            , names='driver_team'
            , values='count_fastest_lap'
            , title='Team Count by Driver'
            , color_discrete_sequence=px.colors.qualitative.T10
    )
    fig_chart.update_traces(textposition='inside', textinfo='percent+label')
    # fig_chart.update_traces(textinfo="percent")
    fig.update_layout(
        yaxis=dict(
            title_text="Driver Name",
            titlefont=dict(size=12),
        ),
        xaxis=dict(
            title_text="Total Count Fastest Lap",
            titlefont=dict(size=12),
        )
    )
    row_item = dbc.Row([
        dbc.Col(dcc.Graph(figure=fig, style={'width': '90vh', 'height': '90vh'})),
        dbc.Col(dcc.Graph(figure=fig_chart, style={'width': '70vh', 'height': '70vh'}))
    ])

    return html.Div([row_item])

def generate_laps_stats(df):
    fig = px.bar(df , x=["total_lap_raced", "total_lap_not_raced"]
                    , y="driver_fullname"
                    , orientation='h'
                    , title="Driver Total lap vs DNF"
                    , color_discrete_sequence=['#54A24B','#E45756']
    )
    fig_team = px.bar(df , x=["total_lap_raced", "total_lap_not_raced"]
                    , y="driver_team"
                    , orientation='h'
                    , title="Team Total lap vs DNF"
                    , color_discrete_sequence=['#54A24B','#E45756']
    )
    # print(px.colors.qualitative.T10)
    fig.update_layout(
        autosize=True,
        height=750,
        yaxis=dict(
            title_text="Driver Name",
            titlefont=dict(size=12),
        ),
        xaxis=dict(
            title_text="Lap total Complete vs. DNF",
            titlefont=dict(size=12),
        )
    )

    fig_team.update_layout(
        autosize=True,
        yaxis=dict(
            title_text="Team Name",
            titlefont=dict(size=12),
        ),
        xaxis=dict(
            title_text="Lap total Complete vs. DNF",
            titlefont=dict(size=12),
        )
    )

    return html.Div(
            [dcc.Graph(figure=fig),dcc.Graph(figure=fig_team)]
        )

        
"""
    CONTENT PREPARATIONS 
"""
get_sl = get_season_list_year()
dropdown_year_cons = html.Div(
    [
        html.H6("Select Year", className="text-light"),
        dcc.Dropdown(
            id="session-year-input-seasons",
            options=[
                {"label": i, "value": i} for i in get_sl
            ],
            value=2016,
        ),
    ]
)

tabs = html.Div([
        dbc.Tabs([
                dbc.Tab(label="Winning Stats", tab_id="wins-1"),
                dbc.Tab(label="Fastest Lap Stats", tab_id="fastest-lap-2"),
                dbc.Tab(label="Lap Stats", tab_id="lap-3"),
            ],
            id="tabs-seasons",
            active_tab="wins-1",
        ),
        html.Div(id="content"),
    ]
)

"""
CONTENT EXPORT LAYOUT
"""
layout = html.Div([
    dbc.Container([
            dbc.Alert([
                    html.Div(
                        [
                            html.H4("F1 Statics by seasons"),
                            html.H6("Full breakdown of drivers and constructors, points and current positions."),
                        ], 
                        className="rounded bg-light text-dark p-2 mb-0"
                    ),
                    html.Div(dropdown_year_cons, className="my-2"),
                ], 
                color="#2C3E50", className="mt-4"
            ),
            html.Div([tabs], className="mt-5"),
        ]
    )
])

@app.callback(
    Output("content", "children")
    ,[
        Input("session-year-input-seasons", "value"),
        Input("tabs-seasons", "active_tab")
    ]
)
def switch_tab(year, at):
    if at == "wins-1":
        query = f"""
                    select  driver_fullname
                            , driver_team
                            , total_first_place
                            , total_second_place
                            , total_third_place
                            , total_count_podiums
                    from public.udf_driver_stats({year})
                    where total_first_place > 0
                        or total_second_place > 0
                        or total_third_place > 0
                    order by total_count_podiums asc 
                """
        df_w = pd.read_sql_query(query, con=db.engine)
        return generate_win_stat(df_w)

    elif at == "fastest-lap-2":
        query = f"""
                    select driver_fullname, driver_team, count_fastest_lap
                    from public.udf_driver_stats({year})
                    where count_fastest_lap > 0
                    order by count_fastest_lap asc 
                """
        df_fl = pd.read_sql_query(query, con=db.engine)
        return generate_fastest_lap_stats(df_fl)

    elif at == "lap-3":
        query = f"""
                    select driver_team
                            , driver_fullname
                            , total_lap_raced  
                            , total_lap_not_raced 
                    from public.udf_driver_stats({year})
                    order by total_lap_raced asc
                """
        df_l = pd.read_sql_query(query, con=db.engine)
        return generate_laps_stats(df_l)

    return html.P("This shouldn't ever be displayed...")