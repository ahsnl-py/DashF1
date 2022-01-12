from itertools import cycle
from numpy import empty
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, dash_table
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

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
LIST OF FUNCTIONS TO RETRIEVE DATA FROM POSTGRES DB REG. DRIVER INFO
"""
def get_sesson_race_results(year, driver):
    # driver_list = tuple(driver)
    driver_id_list = tuple(driver)
    query = f"""
                SELECT race_date        as Date
                    , driver_fullname   as Driver
                    , running_total_points as Points
                FROM public.udf_driver_stand_yearly({year})
                WHERE driver_id IN {driver_id_list}
            """
    
    # get current driver session running total
    df_running_total = pd.read_sql_query(query, con=db.engine)

    fig_running_total = px.line(
        df_running_total # datasets from db
        , x='date'
        , y='points'
        , color='driver'
        , markers=True
        , color_discrete_sequence=px.colors.qualitative.T10
    )
    fig_running_total.update_layout(
        yaxis=dict(
            title_text="Points",
            titlefont=dict(size=16),
        ),
        xaxis=dict(
            title_text="Total Running Point by Driver",
            titlefont=dict(size=16),
        )
    )
    return fig_running_total

#get total driver points by sessions
def get_total_driver_points_bar(year, driver):    
    driver_id_list = tuple(driver)
    query = f"""
                SELECT distinct driver_ref, total_points 
                FROM public.udf_driver_stand_yearly({year})
                WHERE driver_id IN {driver_id_list}
                ORDER BY total_points ASC
            """
    df = pd.read_sql_query(query, con=db.engine)

    fig_total = px.bar(
        df #get datasets from db
        , x='total_points'
        , y='driver_ref'
        , orientation='h'
        , barmode="group"
        , color_discrete_sequence=px.colors.qualitative.T10
    )

    fig_total.update_layout(
        yaxis=dict(
            title_text="Driver Name",
            titlefont=dict(size=16),
        ),
        xaxis=dict(
            title_text="Points",
            titlefont=dict(size=16),
        )
    )
    return fig_total

def create_table_overview(year, driver):
    driver_id_list = tuple(driver)
    query = f"""
                SELECT distinct team, driver_fullname, driver_number
                    , driver_nationality, total_points, win_total, rank
                FROM public.udf_driver_stand_yearly({year})
                WHERE driver_id IN {driver_id_list}
                ORDER BY total_points DESC
            """
    df = pd.read_sql_query(query, con=db.engine)
    df_col_sel = df[['team', 'driver_fullname', 'driver_number', 'driver_nationality', 'total_points', 'win_total', 'rank']]    
    df_col_sel.rename({
        'team': 'Team'
        ,'driver_fullname': 'Driver'
        ,'driver_number': 'Number'
        ,'driver_nationality': 'Nationality'
        ,'total_points':'Points'
        ,'win_total':'Total Wins'
        ,'rank':'Rank'
    }, axis=1)
    table = dash_table.DataTable(
                id="table",
                columns=[{"name": i, "id": i, "deletable": True} for i in df_col_sel.columns],
                data=df.to_dict("records"),
                page_size=10,
                page_current=0,
                style_header={"backgroundColor": "white", "fontWeight": "bold"},
                style_cell={"textAlign": "center"},
                style_cell_conditional=[
                    {"if": {"column_id": "Finished"}, "textAlign": "center"}
                ],
                style_as_list_view=True,
    )
    return table

def get_driver_list(year):
    query = f"""
                SELECT distinct driver_id, driver_fullname
                FROM public.udf_driver_stand_yearly({year})
            """              
    df_dl = pd.read_sql_query(query, con=db.engine)
    return df_dl.values.tolist()
# functions methods for driver info


"""
LIST OF FUNCTIONS TO RETRIEVE DATA FROM POSTGRES DB REG. TEAM INFO
"""
def get_team_standing_by_year_piechart(year):
    fig = go.Figure()    
    # select from function db
    query = f""" select *
                 from udf_constructor_stand_yearly({year}) """
    df_ts = pd.read_sql_query(query, con=db.engine)
    constructor = list(df_ts.constructors_name)
    points = list(df_ts.total_point)
    df_ts['percent'] = (df_ts['total_point'] / df_ts['total_point'].sum()) * 100
    df_ts.percent = [0.1 if (p < 10.0 and p != 0) else 0 for p in df_ts.percent]
    colors = px.colors.qualitative.T10
    
    fig.add_trace(
        go.Pie( 
            labels=constructor
            , values=points
            , hole=0.3
            , pull=list(df_ts.percent)
        )
    )           
    fig.update_traces(
        hoverinfo='label+percent'
        , textinfo='value'
        , textfont_size=20
        , marker=dict(colors=colors, line=dict(color='#000000', width=2))
    )
    fig.update_layout(
        legend_orientation="v",
        annotations=[dict(text=year, font_size=16, showarrow=False, x=0.5, y=0.5)],
        showlegend=True,
        margin=dict(l=0, r=0, t=0, b=0),
    )

    return fig #return graph for pie charts

def get_team_standing_by_year_table(year): 
    # select from function db
    query = f""" SELECT constructors_name 
                        ,team_nationality
                        ,total_point 
                        ,total_win 
                        ,rank
                FROM public.udf_constructor_stand_yearly({year}) """
    df_ts = pd.read_sql_query(query, con=db.engine)

    table = dash_table.DataTable(
            id="table",
            columns=[{"name": i, "id": i, "deletable": True} for i in df_ts.columns],
            data=df_ts.to_dict("records"),
            page_current=0,
            style_header={"backgroundColor": "white", "fontWeight": "bold"},
            style_cell={"textAlign": "center"},
            style_cell_conditional=[
                {"if": {"column_id": "Finished"}, "textAlign": "center"}
            ],
            style_as_list_view=True,
    )
    return table

"""
CONTENT HEADER: 
    Little introductions 
"""
card_header_style = {"background-color": "#2C3E50",}
card_content = [
    dbc.CardHeader(["WELCOME TO F1STATS!"], style=card_header_style, className="card-title text-light"),
    dbc.CardBody(
        [
            dcc.Markdown(
                """
                This web application produces race results, driver and constructor rankings, and comparisons of Formula 1 seasons from 2011 to the present.
                Built with Python, [Dash](https://plotly.com/dash/), and the [Ergast Developer API](http://ergast.com/mrd/) (Motor Racing Data), this application provides users an in-depth look at the numbers behind Formula 1.
                Questions, comments, or concerns? Feel free to reach out on [LinkedIn](https://www.linkedin.com/in/ahsanulnas/) and check out the source code [here](https://github.com/ahsnl-py/DashF1App).
                """,
            )
        ]
    ),
]


"""
CONTENT SECTIONS FOR DRIVERS: 
    wrap variable: dropdown_driver, dropdown_year, tab_dcss -> layout 
"""
get_sl = get_season_list_year()
dropdown_driver = html.Div(children=
    [
        html.H6("Select Driver(s)"),
        dcc.Loading(
            children=[
                dcc.Dropdown(id="driver-dropdown", multi=True)
            ],
            type="circle",
        ),
    ]
)

dropdown_year = html.Div(
    [
        html.H6("Select Year"),
        dcc.Dropdown(
            id="year-dropdown",
            options=[
                {"label": i, "value": i} for i in get_sl
            ],
            value=2019,
        ),
    ]
)

#driver current session running
tab_dcss = html.Div(children=[
        dbc.Tabs(
            [
                dbc.Tab(label="Scatter", tab_id="scatter"),
                dbc.Tab(label="Histograms", tab_id="histogram"),
                dbc.Tab(label="Table", tab_id="table"),
            ],
            id="tabs",
            active_tab="scatter",
        ),
        html.Div(id="tab-content") #children=[dcc.Graph(figure=fig_running_total)]
    ]
)
# end content sections for drivers

"""
CONTENT SECTIONS FOR TEAMS: 
    wrap variable: dropdown_team, dropdown_year_cons, tab_tcss -> layout 
"""
dropdown_team = html.Div(children=
    [
        html.H6("Select Team(s)"),
        dcc.Loading(
            children=[
                dcc.Dropdown(id="teams-dropdown", multi=True)
            ],
            type="circle",
        ),
    ]
)

dropdown_year_cons = html.Div(
    [
        html.H6("Select Year"),
        dcc.Dropdown(
            id="year-dropdown-team",
            options=[
                {"label": i, "value": i} for i in get_sl
            ],
            value=2019,
        ),
    ]
)

#team current session running
tab_tcss = html.Div(children=[
        dbc.Tabs(
            [
                dbc.Tab(label="PieChart", tab_id="piechart"),
                dbc.Tab(label="Table", tab_id="table"),
                # dbc.Tab(label="Table", tab_id="table"),
            ],
            id="tabs-team",
            active_tab="piechart",
        ),
        html.Div(id="tab-content-team") #children=[dcc.Graph(figure=fig_running_total)]
    ]
)

"""
EXPORTED CONTENT TO index
"""
layout = dbc.Container([
        # dbc.Row([
        #     dbc.Col(
        #             dbc.Card(card_content, color="light", className="shadow")
        #         ),
        # ]),
        # mid: driver
        html.Hr(style={"border":"2px solid #e10600"}),
        html.H1(
            ["Season's statistics of race resutls"], 
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
        html.H4(
            "Driver standings by Year", 
            style={
                "text-align":"center", 
                "font-family":"F1-Reg",
                "padding-top": "30px",
            }
        ),
        html.Hr(style={"border": "2px solid rgb(20 17 17)"}),
        dbc.Row(children=
            [
                dbc.Col(dropdown_year),
                dbc.Col(dropdown_driver)
            ]
        ),
        dbc.Row(
            dbc.Card([tab_dcss], body=True) #content drivers 
            ,className="mt-4 pd-2"
        ),
        # end: team 
        html.H4(
            "Team standings by Year", 
            style={
                "text-align":"center", 
                "font-family":"F1-Reg",
                "padding-top": "30px",
            }
        ),
        html.Hr(style={"border": "2px solid rgb(20 17 17)"}),
        dbc.Row(dropdown_year_cons),
        dbc.Row(
            dbc.Card( [tab_tcss] , body=True), #content team 
            className="my-4"
        ),
    ], className="mt-4"
)


"""
CALLBACK FOR DRIVERS: 
    This callback takes the 'active_tab', 'year', 'drivers' property as input
    main callback: 
        > render_tab_content 
        > update_driver_dropdown
        > get_default_drivers
"""
@app.callback(
    Output("tab-content", "children"),
    [
          Input("tabs", "active_tab")
        , Input("year-dropdown", "value")
        , Input("driver-dropdown", "value")
    ],
)
def render_tab_content(active_tab, year, drivers):
    if active_tab and year and drivers is not None:
        if active_tab == "scatter":
            fig_running_total = get_sesson_race_results(year, drivers)
            return  dcc.Graph(figure=fig_running_total)
        elif active_tab == "histogram":
            fig = get_total_driver_points_bar(year, drivers)
            return dcc.Graph(figure=fig)
        elif active_tab == "table":
            data = create_table_overview(year, drivers)
            return data
            
    return html.Div(
        [
            dbc.Alert(
                f" must select one of the following: year or drivers "
                , color="warning", className = "mt-2 text-center"
            )
        ]
    )

@app.callback(
    Output("driver-dropdown", "options")
    , [Input("year-dropdown", "value")]
)
def update_driver_dropdown(year):
    drivers = get_driver_list(year)
    options = []
    for driver in drivers:
        options.append({"label": driver[1], "value": driver[0]})
    return options

@app.callback(
    Output("driver-dropdown", "value")
    , [Input("year-dropdown", "value")]
)
def get_default_drivers(year):
    default_drivers = get_driver_list(year)
    dd_list = []
    for driver in default_drivers:
        dd_list.append(driver[0])
    
    return dd_list[:6]

"""
CALLBACK FOR TEAM: 
    This callback takes the 'active_tab', 'year', 'drivers' property as input
    main callback: 
        > render_tab_content
        >
# """
@app.callback(
    Output("tab-content-team", "children"),
    [
        Input("tabs-team", "active_tab")
        , Input("year-dropdown-team", "value")        
    ],
)
def render_tab_content_team(active_tab, year):
    if active_tab is not None:
        if active_tab == "piechart":
            return dcc.Graph(figure=get_team_standing_by_year_piechart(year))
        elif active_tab == "table":
            table = get_team_standing_by_year_table(year)
            return table
        # elif active_tab == "table":
        #     data = create_table_overview(year, drivers)
        #     return data
            
    return "No tab selected"


# use later
# card = dbc.Card(
#     [
#         dbc.Row(
#             [
#                 dbc.Col(
#                     dbc.CardImg(
#                         src="/static/images/portrait-placeholder.png",
#                         className="img-fluid rounded-start",
#                     ),
#                     className="col-md-4",
#                 ),
#                 dbc.Col(
#                     dbc.CardBody(
#                         [
#                             html.H4("Card title", className="card-title"),
#                             html.P(
#                                 "This is a wider card with supporting text "
#                                 "below as a natural lead-in to additional "
#                                 "content. This content is a bit longer.",
#                                 className="card-text",
#                             ),
#                             html.Small(
#                                 "Last updated 3 mins ago",
#                                 className="card-text text-muted",
#                             ),
#                         ]
#                     ),
#                     className="col-md-8",
#                 ),
#             ],
#             className="g-0 d-flex align-items-center",
#         )
#     ],
#     className="mb-3",
#     style={"maxWidth": "540px"},
# )