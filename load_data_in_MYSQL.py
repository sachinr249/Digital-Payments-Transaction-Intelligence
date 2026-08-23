from sqlalchemy import create_engine
from urllib.parse import quote_plus
import pandas as pd

# 1. Encode the password just in case it contains special characters 
password = quote_plus("@Sachinr249m6#") 
user = "root" 
host = "localhost" # Using 127.0.0.1 instead of localhost 
port = "3306" 
db = "upi"
engine = create_engine(f'mysql+pymysql://{user}:{password}@{host}:{port}/{db}')

# Load data
merchants = pd.read_csv("datasets/merchants.csv")
devices = pd.read_csv("datasets/devices.csv")
refunds = pd.read_csv("datasets/refunds.csv")
transactions = pd.read_csv("datasets/transactions.csv")
users = pd.read_csv("datasets/users.csv")

users.to_sql("users", engine, if_exists="append", index=False)
merchants.to_sql("merchants", engine, if_exists="append", index=False)
devices.to_sql("devices", engine, if_exists="append", index=False)
transactions.to_sql("transactions", engine, if_exists="append", index=False)
refunds.to_sql("refunds", engine, if_exists="append", index=False)

print("Data loaded successfully.")