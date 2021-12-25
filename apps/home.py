from numpy import empty
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, dash_table
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

season_list = list()
for i in range(2011, 2022):
    season_list.append(i)

"""
LIST OF FUNCTIONS TO RETRIEVE DATA FROM POSTGRES DB REG. DRIVER INFO
"""
def get_sesson_race_results(year, driver):
    driver_list = tuple(driver)
    sql = f""" SELECT racedate as date
                    , driver, pointrunningtotal 
            FROM get_race_running_total_points 
            WHERE extract(year from racedate) = {year}
                AND driver IN {driver_list}  """

    # get current driver session running total
    df_running_total = pd.read_sql_query(sql, con=db.engine)

    fig_running_total = px.line(
        df_running_total # datasets from db
        , x='date'
        , y='pointrunningtotal'
        , color='driver'
        , markers=True
        # , template=template_theme1
    )
    return fig_running_total

#get total driver points by sessions
def get_total_driver_points(year, driver):    
    driver_list = tuple(driver)
    sql = f""" SELECT driver, sum(pointbyrank) as totalpointdriver 
            FROM get_quali_results
            WHERE extract(year from racedate) = {year} 
                AND driver IN {driver_list}
            GROUP BY driver """
    df = pd.read_sql_query(sql, con=db.engine)

    df_total = px.bar(
        df #get datasets from db
        , x='driver'
        , y='totalpointdriver'
        , barmode="group"
    )
    return df_total

def create_table_overview(year, driver):
    driver_list = tuple(driver)
    sql = f"""
            select racedate, racetrackname, driverno as carnumber, driver as drivercode
					,laptime as fastestlaptime, pointbyrank as points
			from public.get_quali_results
			WHERE extract(year from racedate) = {year} 
                AND driver IN {driver_list}
            """
    df = pd.read_sql_query(sql, con=db.engine)

    table = dash_table.DataTable(
                id="table",
                columns=[{"name": i, "id": i, "deletable": True} for i in df.columns],
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
    sql = f"""  
            SELECT DISTINCT vwgr.driver, concat(ltrim(fd.forename),' ',ltrim(fd.surname))
            FROM get_race_running_total_points vwgr 
            left JOIN factdrivers fd 
                ON (vwgr.driver = fd.code AND vwgr.driverno = fd.number)
            WHERE extract(year from vwgr.racedate) = {year} """                     
    df_dl = pd.read_sql_query(sql, con=db.engine)
    return df_dl.values.tolist()
# functions methods for driver info


"""
LIST OF FUNCTIONS TO RETRIEVE DATA FROM POSTGRES DB REG. DRIVER INFO
"""
def get_team_standing_by_year_piechart(year):
    fig = go.Figure()    
    # select from function db
    sql = f""" SELECT * FROM func_get_constr_stand_year({year}) """
    df_ts = pd.read_sql_query(sql, con=db.engine)

    constructor = list(df_ts.team)
    points = list(df_ts.points)
    df_ts['percent'] = (df_ts['points'] / df_ts['points'].sum()) * 100
    df_ts.percent = [0.1 if (p < 10.0 and p != 0) else 0 for p in df_ts.percent]

    fig.add_trace(
        go.Pie( 
            labels=constructor
            , values=points
            , hole=0.3
            , pull=list(df_ts.percent)
        )
    )           
    fig.update_traces(textinfo="percent")
    fig.update_layout(
        legend_orientation="v",
        annotations=[dict(text=str(year), font_size=16, showarrow=False, x=0.5, y=0.5)],
        showlegend=True,
        margin=dict(l=0, r=0, t=0, b=0),
       
    )

    return fig #return graph for pie charts

def get_team_standing_by_year_table(year): 
    # select from function db
    sql = f""" SELECT * FROM func_get_constr_stand_year({year}) """
    df_ts = pd.read_sql_query(sql, con=db.engine)

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
CONTENT SECTIONS FOR DRIVERS: 
    wrap variable: dropdown_driver, dropdown_year, tab_dcss -> layout 
"""
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
                {"label": i, "value": i} for i in season_list
            ],
            value=2021,
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
        html.Div(id="tab-content", className="p-4") #children=[dcc.Graph(figure=fig_running_total)]
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
                {"label": i, "value": i} for i in season_list
            ],
            value=2021,
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

layout = dbc.Container([
        dbc.Row([
                # start: Intro and Info 
                dbc.Card(children=
                    [
                        dbc.CardHeader("WELCOME TO F1STATS!"),
                        dbc.CardBody(children=
                            [
                                dcc.Markdown(
                                    """
                                    This web application produces race results, driver and constructor rankings, up-to-date timetables, circuit layouts, and comparisons of Formula 1 seasons from 1950 to the present.
                                    Built with Python, [Dash](https://plotly.com/dash/), and the [Ergast Developer API](http://ergast.com/mrd/) (Motor Racing Data), this application provides users an in-depth look at the numbers behind Formula 1.
                                    Questions, comments, or concerns? Feel free to reach out on [LinkedIn](https://www.linkedin.com/in/jeonchristopher/) and check out the source code [here](https://github.com/christopherjeon/F1STATS-public).
                                    """,
                                    # style={"margin": "0 10px"},
                                )
                            ]
                        ),
                    ],
                    className="p-4",
                ), 
        ]),
        # mid: driver 
        html.Div(children=[
            html.P("Driver current standings", className="h3 my-4 fst-normal")
        ]),
        dbc.Row(children=
        [
            dbc.Col(dropdown_year),
            dbc.Col(dropdown_driver)
        ]),
        dbc.Row(
            [tab_dcss] #content drivers 
            ,className="mt-4 pd-2"
        ),
        # end: team 
        html.Div(children=[
            html.P("Team current standings", className="h3 my-4 fst-normal")
        ]),
        dbc.Row(dropdown_year_cons),
        dbc.Row(
            [tab_tcss] #content team 
            ,className="mt-4 pd-2"
        ),
    ]
)


"""
CALLBACK FOR DRRIVERS: 
    This callback takes the 'active_tab', 'year', 'drivers' property as input
    main callback: 
        > render_tab_content
        >
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
    if active_tab is not None:
        if active_tab == "scatter":
            fig_running_total = get_sesson_race_results(year, drivers)
            return  dcc.Graph(figure=fig_running_total)
        elif active_tab == "histogram":
            fig = get_total_driver_points(year, drivers)
            return dcc.Graph(figure=fig)
        elif active_tab == "table":
            data = create_table_overview(year, drivers)
            return data
            
    return "No tab selected"

@app.callback(Output("driver-dropdown", "options"), [Input("year-dropdown", "value")])
def update_driver_dropdown(year):
    drivers = get_driver_list(year)
    options = []
    for driver in drivers:
        options.append({"label": driver[1], "value": driver[0]})
    return options

@app.callback(Output("driver-dropdown", "value"), [Input("year-dropdown", "value")])
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