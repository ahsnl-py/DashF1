from numpy import empty
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
from dash import html, dcc, Input, Output, State, dash_table
from app import app, db

import pandas as pd
import plotly.express as px
import geojson
from datetime import datetime
import visdcc

"""
Function returns pandas DataFrame with unique countries where races have taken place, 
country ISO codes, and number of races taken place in each country 
"""
def get_circuit_counts():
    circuits_df = pd.read_csv("./datasets/circuits.csv")
    race_df = pd.read_csv("./datasets/races.csv")
    country_codes_df = pd.read_csv("./datasets/country_codes.csv")

    circuit_race_counts = race_df.value_counts(subset=['circuitId']).to_frame('count').reset_index()
    df_merge = pd.merge(circuits_df, circuit_race_counts, on='circuitId', how='left')
    country_counts = df_merge.groupby(['country']).sum().reset_index()
    df = pd.merge(country_counts, country_codes_df, on='country', how='left')

    return df

def get_circuits_in_country(country):
    circuits_df = pd.read_csv("./datasets/circuits.csv")
    race_df = pd.read_csv("./datasets/races.csv")

    country_circuits = circuits_df[['circuitId', 'country', 'name', 'location']].loc[circuits_df['country']==country]
    country_circuits.rename({"name": 'circuit_name'}, axis=1, inplace=True)
    df = pd.merge(country_circuits, race_df, on='circuitId', how='left')
    df.sort_values('year', inplace=True)
    df.reset_index(drop=True, inplace=True)

    return df

def get_most_driver_wins(df):
    results_df = pd.read_csv("./datasets/results.csv")
    drivers_df = pd.read_csv("./datasets/drivers.csv")

    df2 = pd.merge(results_df, df, on='raceId', how='inner')
    df3 = df2.loc[df2['positionText'] == '1']
    df4 = df3.value_counts(subset=['driverId']).to_frame('count').reset_index()
    df5 = pd.merge(df4, drivers_df, on='driverId', how='inner')
    df6 = df5.loc[df5['count'] == df5['count'].max()]

    most_wins = ""
    for i in range(len(df6)):
        forename = df6['forename'].values[i]
        surname = df6['surname'].values[i]
        count = df6['count'].values[i]
        most_wins += f"{forename} {surname} ({int(count)})"
        if i != len(df6)-1:
            most_wins += ", "
    
    return most_wins

def get_most_const_wins(df):
    results_df = pd.read_csv("./datasets/results.csv")
    constructors_df = pd.read_csv("./datasets/constructors.csv")

    df2 = pd.merge(results_df, df, on='raceId', how='inner')
    df3 = df2.loc[df2['positionText'] == '1']
    df4 = df3.value_counts(subset=['constructorId']).to_frame('count').reset_index()
    df5 = pd.merge(df4, constructors_df, on='constructorId', how='inner')
    df6 = df5.loc[df5['count'] == df5['count'].max()]

    most_wins = ""
    for i in range(len(df6)):
        name = df6['name'].values[i]
        count = df6['count'].values[i]
        most_wins += f"{name} ({int(count)})"
        if i != len(df6)-1:
            most_wins += ", "
    return most_wins

def get_fastest(df):
    results_df = pd.read_csv("./datasets/results.csv")
    drivers_df = pd.read_csv("./datasets/drivers.csv")

    df2 = pd.merge(results_df, df, on='raceId', how='inner')
    df2['fastestLapTime'] = df2['fastestLapTime'].apply(lambda x: datetime.strptime(x, '%M:%S.%f').time() if x != '\\N' else datetime.strptime("10:0.0", '%M:%S.%f').time())
    min = df2['fastestLapTime'].min()
    idxmin = df2[df2['fastestLapTime'] == min]

    fastest_time = f"{min.minute}:{min.second}.{str(min.microsecond)[:3]}"
    driver_id = idxmin['driverId'].values[0]
    driver_idx = drivers_df[drivers_df['driverId'] == driver_id]
    forename = driver_idx['forename'].values[0]
    surname = driver_idx['surname'].values[0]
    year = idxmin['year'].values[0]
    driver_name = f"{forename} {surname} ({int(year)})"

    if min.minute == 10:
        fastest_time = "N/A"
        driver_name = "N/A"


    return fastest_time, driver_name


def shorten_years(years):
    years_sh = ""
    for i, year in enumerate(years):
        if i == 0:
            year_i = f"{int(year)}"
        elif year != years[i-1] + 1:
            if year_i != f"{int(years[i-1])}":
                year_i += f"-{int(years[i-1])}"

            years_sh += f"{year_i}, "
            year_i = f"{int(year)}"
        
        if i == len(years)-1:
            if year_i != f"{int(years[i])}":
                year_i += f"-{int(years[i])}"
            
            years_sh += f"{year_i}"
    
    return years_sh

def country_card(df):
    number_of_circuits = len(df['circuitId'].unique())
    number_of_races = len(df['raceId'].unique())
    years_held = df['year'].unique()
    year_sh = shorten_years(years_held)
    most_races_held = df.value_counts(subset=['circuit_name']).idxmax()[0]
    driver_most_wins = get_most_driver_wins(df)
    const_most_wins = get_most_const_wins(df)

    subheading_style = {"margin-bottom":"0px"}

    card = dbc.Card(className="h-100 shadow mb-4", 
                    children=
                        [
                            dbc.CardBody(children=
                                [
                                    dbc.Row(children=[
                                        dbc.Col([
                                            html.P(children="Number of Circuits", style=subheading_style),
                                            html.H6(children=f"{number_of_circuits}"),
                                            html.P(children="Races Held", style=subheading_style),
                                            html.H6(children=f"{number_of_races}"),
                                            html.P(children="Years Held", style=subheading_style),
                                            html.H6(children=f"{year_sh}"),
                                        ]),

                                        dbc.Col([
                                            html.P(children="Circuit with Most Races Held", style=subheading_style),
                                            html.H6(children=f"{most_races_held}"),
                                            html.P(children="Driver with Most Wins", style=subheading_style),
                                            html.H6(children=f"{driver_most_wins}"),
                                            html.P(children="Constructor with Most Wins", style=subheading_style),
                                            html.H6(children=f"{const_most_wins}"),
                                        ])
                                    ]
                                    )
                                ]
                            )
                        ], 
                    )
    return card

def track_cards(df):
    circuits = df['circuit_name'].unique()

    heading_style = {"font-family":"F1-Reg", "font-weight":'lighter'}
    location_style = {"font-family":"F1-Bold"}
    subheading_style = {"margin-bottom":"0px"}

    circuit_rows = []
    for i in range(0, len(circuits), 4):
        circuits_cols = []

        for j in range(i, i+4):

            card = []
            if j < len(circuits):
                circuit = circuits[j-1]
                circuit_df = df.loc[df['circuit_name'] == circuit]
                location = circuit_df['location'].unique()[0]
                years = circuit_df['year'].unique()
                number = len(years)
                years_sh = shorten_years(years)
                fastest_time, fastest_driver = get_fastest(circuit_df)
                driver_most_wins = get_most_driver_wins(circuit_df)
                const_most_wins = get_most_const_wins(circuit_df)

                card = dbc.Card(className="h-100 shadow", children=
                                [
                                    dbc.CardBody(children=
                                        [
                                            html.H5(children=f"{circuit}", style=heading_style),
                                            html.H6(children=f"{location}", style=location_style),
                                            html.Hr(style={"border":"2px solid #e10600"}),
                                            html.P(children="Total Races Held", style=subheading_style),
                                            html.H6(children=f"{number}"),
                                            html.P(children="Years Held", style=subheading_style),
                                            html.H6(children=f"{years_sh}"),
                                            html.P(children="Most Wins (Driver)", style=subheading_style),
                                            html.H6(children=f"{driver_most_wins}"),
                                            html.P(children="Most Wins (Constructor)", style=subheading_style),
                                            html.H6(children=f"{const_most_wins}"),
                                            html.P(children="Fastest Lap Time", style=subheading_style),
                                            html.H6(children=f"{fastest_time}"),
                                            html.P(children="Fastest Lap Record Holder", style=subheading_style),
                                            html.H6(children=f"{fastest_driver}"),
                                        ]
                                    )
                                ], style={"border":"2px solid #e10600"},
                            )
                
            circuits_cols.append(dbc.Col(card))
        
        circuit_rows.append(dbc.Row(circuits_cols, className="mb-4"))

    return circuit_rows

"""
Configuring Mapbox settings and loading polygon data for map from geojson file
"""
token = open("apps/.mapbox_token").read()

geojson_PATH = "datasets/countries.geo.json"
with open(geojson_PATH) as f:
    gj = geojson.load(f)

"""
Map figure colored based on number of races held in each country.
Countries names mapped based on ISO codes found in geojson properties.
"""
circuit_counts_df = get_circuit_counts()
fig = px.choropleth_mapbox(
        circuit_counts_df,
        geojson=gj,
        color='count',
        locations="code", 
        featureidkey="properties.adm0_a3_is",
        color_continuous_scale=px.colors.sequential.Reds,
        hover_name="country",
        hover_data=["count"],
        zoom=1)
fig.update_layout(
        height=600,
        margin={"r":0,"t":0,"l":0,"b":0},
        mapbox_accesstoken=token)

"""
EXPORTED CONTENT TO index
"""
layout = dbc.Container([
            dcc.Graph(
                id='mapbox', 
                figure=fig,
                style={"margin-top":"1rem"},
                config=dict(
                    displayModeBar=False
                )
            ),
            html.Div(visdcc.Run_js(id = 'scroll')),
            html.Div(
                id = "track-card",
                children=None,
                style={"margin-top":"3rem", "padding-top":"1rem"}
            ),
], style={"padding":"0.5rem"})


"""
CALLBACK FOR TRACK DATA
When a country on the map is clicked, 
cards are generated for each track in the country
providing basic stats:
    > Track name
    > Track location
    > Number of races held
    > Number of years held
    > Lap records and record holders
    > Driver with most wins
    > COnstructor with most wins
"""
@app.callback(
    Output("track-card", "children"),
    Output("scroll", "run"),
    [Input("mapbox", "clickData")],
)
def circuit_details(clickdata):

    if clickdata is not None:
        country = clickdata['points'][0]['hovertext']
        df =  get_circuits_in_country(country)
        df.dropna(inplace=True)

        data = [html.H2(f"{country}", 
                        style={
                            "text-align":"center", 
                            "font-family":"F1-Bold",
                            "margin-bottom":"2rem"
                        }
                    ),
                country_card(df)
                ] 
        data += track_cards(df)

        js_script = '''
             var cardarea = document.getElementById('track-card');
             cardarea.scrollIntoView({behavior: "smooth", block: "start", inline: "nearest"});
             '''
        
        return data, js_script
    else:
        return None, None