 
from dash import (
    Input, Output, State, dcc, html
)
import dash_bootstrap_components as dbc

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from app import app, server 
from apps import home, drivers, seasons, tracks, schedule


PLOTLY_LOGO = "https://images.plot.ly/logo/new-branding/plotly-logomark.png"

template_theme1 = "journal"
template_theme2 = "darkly"

content_nav = dbc.Row(
    [
        dbc.Nav(
            [
                dbc.NavItem(dbc.NavLink("Home", active=True, href="/")),
                dbc.NavItem(dbc.NavLink("Driver", active=True, href="/drivers")),
                dbc.NavItem(dbc.NavLink("Seasons", active=True, href="/seasons")),
                dbc.NavItem(dbc.NavLink("Schedule", active=True, href="/schedule")),
                dbc.NavItem(dbc.NavLink("Tracks", active=True, href="/tracks")),
                dbc.DropdownMenu(
                    [dbc.DropdownMenuItem("Item 1"), dbc.DropdownMenuItem("Item 2")],
                    label="Dropdown",
                    nav=True,
                ),
            ]
        )
    ],
    className="g-0 ms-auto flex-nowrap",
    align="center",
)


navbar = dbc.Navbar(
    dbc.Container(
        [
            html.A(
                # Use row and col to control vertical alignment of logo / brand
            dbc.Row(
                [
                    dbc.Col(html.Img(src=PLOTLY_LOGO, height="30px")),
                    dbc.Col(dbc.NavbarBrand("Dashf1", className="ms-2")),
                ],
                align="center",
                className="g-0",
            ),
            href="https://plotly.com",
            style={"textDecoration": "none"},
            ), 
            dbc.NavbarToggler(id="navbar-toggler", n_clicks=0),  
            dbc.Collapse(
                content_nav,
                id="navbar-collapse",
                is_open=False,
                navbar=True,
            ),
        ],
    ),
    color="primary",
    dark=True,
)

content = html.Div(id='page-content', children=[])

app.layout = html.Div([ 
    dcc.Location(id='url', refresh=False) #pathname=['apps/driver_stand'] 
    ,navbar           
    ,content
])

# add callback for toggling the collapse on small screens
@app.callback(
    Output("navbar-collapse", "is_open"),
    [Input("navbar-toggler", "n_clicks")],
    [State("navbar-collapse", "is_open")],
)
def toggle_navbar_collapse(n, is_open):
    if n:
        return not is_open
    return is_open


@app.callback(Output('page-content', 'children'),
              [Input('url', 'pathname')])
def display_page(pathname):
    if pathname == "/":
        return home.layout
    elif pathname == '/drivers':
        return drivers.layout
    elif pathname == '/seasons':
        return seasons.layout
    elif pathname == "/schedule":
        return schedule.layout
    elif pathname == "/tracks":
        return tracks.layout
    else:
        return "404 Page Error! Please choose a link"


if __name__ == '__main__':
    app.run_server(debug=True)