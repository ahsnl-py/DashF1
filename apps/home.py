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
                editable=True,
                cell_selectable=True,
                filter_action="native",
                sort_action="native",
                style_table={"overflowX": "auto"},
    )
    return table

def get_driver_list(year):
    year = 2021
    sql = f"""  
            SELECT DISTINCT vwgr.driver, concat(ltrim(fd.forename),' ',ltrim(fd.surname))
            FROM get_race_running_total_points vwgr 
            left JOIN factdrivers fd 
                ON (vwgr.driver = fd.code AND vwgr.driverno = fd.number)
            WHERE extract(year from vwgr.racedate) = {year} """                     
    df_dl = pd.read_sql_query(sql, con=db.engine)
    return df_dl.values.tolist()



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
])

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
        # mid: content 
        html.Div(children=[
            html.P("Driver current standings", className="h3 my-4 fst-normal")
        ]),
        dbc.Row(children=
        [
            dbc.Col(dropdown_year),
            dbc.Col(dropdown_driver)
        ]),
        dbc.Row(
            [tab_dcss]
            ,className="mt-4 pd-2"
        ),
    ]
)

@app.callback(
    Output("tab-content", "children"),
    [
          Input("tabs", "active_tab")
        , Input("year-dropdown", "value")
        , Input("driver-dropdown", "value")
    ],
)
def render_tab_content(active_tab, year, drivers):
    print(active_tab, year, drivers)
    """
    This callback takes the 'active_tab' property as input, as well as the
    stored graphs, and renders the tab content depending on what the value of
    'active_tab' is.
    """
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
