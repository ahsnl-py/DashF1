import dash
import dash_bootstrap_components as dbc
from app import app, db
from dash import Input, Output, State, dcc, html
import pandas as pd

layout  = html.Div(
    [
        dbc.Accordion(
            [
                dbc.AccordionItem(
                    "This is the content of the first section",
                    title="Item 1",
                    item_id="item-1",
                ),
                dbc.AccordionItem(
                    "This is the content of the second section",
                    title="Item 2",
                    item_id="item-x",
                ),
                dbc.AccordionItem(
                    "This is the content of the third section",
                    title="Item 3",
                    item_id="item-y",
                ),
            ],
            id="accordion",
            active_item="item-1",
        ),
        html.Div(id="accordion-contents", className="mt-3"),
    ]
)


@app.callback(
    Output("accordion-contents", "children"),
    [Input("accordion", "active_item")],
)
def change_item(item):
    print(item)
    return f"Item selected: {item}"