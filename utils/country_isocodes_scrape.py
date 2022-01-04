from bs4 import BeautifulSoup as bs
import requests
import pandas as pd

"""
BeautifulSoup used to extract data from wikipedia for country ISO code for use in tracks page map
"""


url = "https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3"
result = requests.get(url)
doc = bs(result.text, "html.parser")

data = []
div = doc.find(["div"], {"class": "plainlist"})
for d in div.findAll("li"):
    code = d.find(["span"], {"class": "monospaced"}).string
    country = d.find("a").string
    data.append([code, country])

df = pd.DataFrame(data)
df.columns = ["code", "country"]
# print(df)
df.to_csv("..\datasets\country_codes.csv")