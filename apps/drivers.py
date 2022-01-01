import time
from numpy import empty
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, dash_table, State, MATCH
from app import app, db

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go


season_list = list()
for i in range(2011, 2022):
    season_list.append(i)

"""
GET DATASETS:
    > return driver standings points over the course of selected sessions 
    > return 
"""
def get_driver_stand_year(year):
    sql = f"""  select fgds.*, fcc.colorhex
                from public.func_get_driver_stand_year({year}) fgds
                inner join public.factconstructorcolor fcc
                    on fgds.team = fcc.team """  
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
                            , win_total as podiums
                            , coalesce(fc.color_code_hex, 'no_color') as colorhex
                    from public.udf_driver_stand_yearly({year}) as udf_d
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
    return generate_driver_card(df_dsy.to_dict())

def get_driver_stats(year, id):
    query = f"""
                SELECT *
                    , round(total_podiums/SUM(total_podiums) over(order by (select null)), 2) percentage_win_race
                FROM (
                    select driver_id, driver_fullname
                        , sum(iswin) total_win
                        , sum(is_second) total_win_runner_up
                        , sum(is_third)	total_win_third
                        , sum(point) total_point_race
                        , round(avg(point), 2) average_point_gp
                        , (sum(iswin) + sum(is_second) + sum(is_third)) total_podiums 
                    from public.vw_race_results
                    where year = cast({year} as char(4))
                        and driver_id = cast({id} as int)
                    group by driver_id, driver_fullname
                ) t
            """
    df_gds = pd.read_sql_query(query, con=db.engine)

    return df_gds




"""
COMPONENTS TO RENDER:
    > Cards 
    > Dropdown year -- to view all driver standing and their quick stats
"""

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
        ,[ t for t in df_dict['drivernumber'].values()] # 8 driver number
        ,[ t for t in df_dict['colorhex'].values()]     # 9 team color code
        ,[ t for t in df_dict['driver_id'].values()]    # 10 driver id -- unique identified of driver
    ))    

    card_content = list()
    for d in driver_props_tuple:
        if d[5] > 0:
            wins_badge = html.Div(dbc.Badge(f"{d[5]} wins", pill=True, color="success", className="me-1"))
        else:
            wins_badge = html.Div("")


        if d[9] == 'no_color':
            style_header = {"background-color": '#f6efd0',}
        else:
            style_header = {"background-color": f"{d[9]}",}

        accordion_t =   dbc.Accordion(
            [
                dbc.AccordionItem(
                    html.Div(id="accordion-driver"),
                    title="Item 1",
                    item_id=f"{d[10]}",
                ),
            ],
            id="accordion",            
        )

        accordion =   dbc.Accordion(
            [
                dbc.AccordionItem(
                    html.Div(id={
                        'type': "accordion-driver",
                        'index': f'{d[10]}'
                    }),
                    title="Item 1",
                    item_id=f"{d[10]}",
                ),
            ],
            # id="accordion", 
            id={
                'type': "accordion",
                'index': f'{d[10]}'
            },
            # start_collapsed=True,           
        )

        card = [
            dbc.CardHeader(
                [
                    html.H6(
                        dbc.Badge(
                            f"{d[2]}", 
                            pill=True, 
                            text_color="dark", 
                            color="white", 
                            className="me-1"
                        )
                    ),
                    html.H6(
                        dbc.Badge(
                            f"{d[1]} PTS",
                            color="dark",
                            text_color=f"{d[3]}",
                            # className="border m-1",
                        )                         
                    ),
                ]
                , className="card-header d-flex justify-content-between align-items-center"
                , style=style_header
            ),
            dbc.CardBody(
                [
                    html.Div(
                        [
                            html.H5(f"{d[8]} - {d[0]}"),
                            wins_badge,
                        ], className="d-flex justify-content-between align-items-center"
                    ),
                
                    html.Hr(),
                    html.Div([
                        html.H6(f"{d[6]}", className="card-text m-0",),            
                        html.H6(f"{d[4]}", className="card-text",),
                    ], className="d-flex justify-content-between align-items-center  mb-4"),
                    accordion,
                ]
            ),
        ]

        card_content.append(card)
    
    return card_content

dropdown_year_cons = html.Div(
    [
        html.H6("Select Year", className="text-light"),
        dcc.Dropdown(
            id="session-year-input",
            options=[
                {"label": i, "value": i} for i in season_list
            ],
            value=2016,
        ),
    ]
)


def get_gp_name(year):
    query = f"""
                select distinct cast(date as char(10)) as date, gp_name 
                from public.vw_race_results 
                where year = cast({year} as char(4))
            """
    df_gp = pd.read_sql_query(query, con=db.engine)
    list_gp_name = df_gp.gp_name.tolist()
    marks = {
            ix: {'label': t.split()[0] + '_GP', 
                                    'style': {'color':'#f50'}} for ix, t in enumerate(list_gp_name)
        }
    return marks

gps_marks = []
# get_gp_name(2016)
gp_slider = dcc.Slider(
    min=0,
    max=len(gps_marks)+1,
    value=len(gps_marks)/2,
    step=1,
    # marks={
    #     'Australian_GP': {'label': 'Australian_GP', 'style': {'color': '#f50'}}, 'British_GP': {'label': 'British_GP', 'style': {'color': '#f50'}}
    # },
    marks=gps_marks,
    included=False
)




layout = html.Div([
    dbc.Container(
        dbc.Alert(
            [
                html.Div(
                    [
                        html.H4("Check out this season's official!"),
                        html.H6("Full breakdown of drivers, points and current positions. Follow your favourite F1 drivers on and off the track."
                        ),
                    ]
                    , className="rounded bg-light text-dark p-2 mb-0"
                    
                ),
                html.Div(dropdown_year_cons, className="my-2"),
                # html.Div(gp_slider, className="mt-4 text-light"),
            ], color="#2C3E50", className="mt-4"
        ),
    ),
    html.Div(id="cards"),
    
])

@app.callback(
    Output('cards', 'children'),
    Input('session-year-input', 'value'),
    # Input('collapse-button', 'n_clicks'),
)
def get_card_layout(year):
    content_card = []
    cards_driver = get_driver_stand_year(year)
    card_list = list()
    for i in cards_driver:
        col_card = dbc.Col(dbc.Card(i,className="shadow"))
        card_list.append(col_card)

    cards_driver =  dbc.Container([
            dbc.Row([i for i in card_list[0:2]], className="mb-4")
            ,dbc.Row([i for i in card_list[2:5]], className="mb-4")
            ,dbc.Row([i for i in card_list[5:8]], className="mb-4")
            ,dbc.Row([i for i in card_list[8:11]], className="mb-4")
            ,dbc.Row([i for i in card_list[11:14]], className="mb-4")
            ,dbc.Row([i for i in card_list[14:17]], className="mb-4")
            ,dbc.Row([i for i in card_list[17:20]], className="mb-4")
            ,dbc.Row([i for i in card_list[20:23]], className="mb-4")
            ,dbc.Row([i for i in card_list[23:26]], className="mb-4")
        ])
    # time.sleep(20)
    return cards_driver

@app.callback(
    # Output("accordion-driver", "children"),
    Output({'type': "accordion-driver", 'index': MATCH}, "children"),
    [
        # Input("accordion", "active_item"),
        Input(component_id={'type': "accordion", 'index': MATCH}, component_property='active_item'),
    ],
)
def change_item(item):
    print(item)
    return f"Item selected: {item}"