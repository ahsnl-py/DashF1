from bs4 import BeautifulSoup as bs
import requests
import pandas as pd

"""
BeautifulSoup used to extract data from Formula1 schedule page ("https://www.formula1.com/en/racing/2022.html")
and save on a dataframe for use in schedule page (schedule.py). Ideally dataframe would be updated once a month/week 
incase of schedule changes. 
Note: no security issues scraping from F1 page.

"""


url = "https://www.formula1.com/en/racing/2022.html"
result = requests.get(url)
doc = bs(result.text, "html.parser")
months = doc.find_all(["span"], {"class": "month-wrapper"})
start_dates = doc.find_all(["span"], {"class": "start-date"})
end_dates = doc.find_all(["span"], {"class": "end-date"})
location = doc.find_all(["div"], {"class": "event-place"})
title = doc.find_all(["div"], {"class": "event-title"})

month_dict = {"Jan" : 1, "Feb" : 2, "Mar" : 3, "Apr" : 4, "May" : 5, "Jun" : 6, "Jul" : 7, "Aug" : 8, "Sep" : 9, "Oct" : 10, "Nov" : 11, "Dec" : 12}

data = []
for month, start, end, loc, title in zip(months, start_dates, end_dates, location, title):\
    data.append([loc.contents[0], month.string, month_dict[month.string.split("-")[0]], start.string, end.string, title.string])

df = pd.DataFrame(data)
df.columns = ["location", "month", "month_index", "start_date", "end_date",  "title"]
df.to_csv(".\datasets\schedule_2022.csv")


