import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output
import plotly.express as px
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

import dash_bootstrap_components as dbc
from dash import Input, Output, html

def get_season_list_year():
    query = f"""
                    SELECT DISTINCT year FROM vw_race_results ORDER BY YEAR ASC
            """
    df_sly = pd.read_sql_query(query, con=db.engine)
    
    season_list = list()
    for i in df_sly['year']:
        season_list.append(i)
    
    return season_list

def get_stats_from_db(year, tab_option):

    if tab_option == 'wins-1':
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


def generate_win_stat(df):
    fig = go.Figure()
    fig_chart = go.Figure()
    fig = px.bar(df , x=["total_first_place", "total_second_place", "total_third_place"]
                    , y="driver_fullname"
                    , orientation='h'
                    , title="Driver Standing Total")

    fig_chart = px.pie(df
            , names='driver_team'
            , values='total_count_podiums'
            , title='Team total point earn by driver'
        )
    fig_chart.update_traces(textposition='inside', textinfo='percent+label')
    # fig_chart.update_traces(textinfo="percent")

    row_item = dbc.Row([
        dbc.Col(dcc.Graph(figure=fig, style={'width': '90vh', 'height': '90vh'})),
        dbc.Col(dcc.Graph(figure=fig_chart, style={'width': '70vh', 'height': '70vh'}))
    ])

    return html.Div([row_item])
        

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

tabs = html.Div(
    [
        dbc.Tabs(
            [
                dbc.Tab(label="Winning Stats", tab_id="wins-1"),
                dbc.Tab(label="Tab 2", tab_id="tab-2"),
            ],
            id="tabs-seasons",
            active_tab="wins-1",
        ),
        html.Div(id="content"),
    ]
)

layout = html.Div([
    dbc.Container([
            dbc.Alert(
                [
                    html.Div(
                        [
                            html.H4("F1 Statics by seasons"),
                            html.H6("Full breakdown of drivers and constructors, points and current positions."
                            ),
                        ]
                        , className="rounded bg-light text-dark p-2 mb-0"
                        
                    ),
                    html.Div(dropdown_year_cons, className="my-2"),
                ], color="#2C3E50", className="mt-4"
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
        return get_stats_from_db(year, at)
    elif at == "tab-2":
        return "tab2_content"
    return html.P("This shouldn't ever be displayed...")