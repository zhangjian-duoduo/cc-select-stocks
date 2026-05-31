#!/usr/bin/env python3
"""更新所有股票价格"""
import pymysql
from data_fetcher import DataFetcher
import time
from db import get_db

df = DataFetcher()
df.min_interval = 0.2
df.max_interval = 0.4

conn = get_db()
cursor = conn.cursor()

cursor.execute("SELECT code FROM stocks")
stocks = cursor.fetchall()

print(f"更新 {len(stocks)} 只股票价格...")

for i, stock in enumerate(stocks):
    code = stock[0]
    try:
        daily = df.fetch_with_fallback('get_stock_daily', code, '20240401', '20240422')
        if daily is not None and len(daily) > 0:
            close = float(daily['close'].iloc[-1])
            start = float(daily['close'].iloc[0])
            change = (close / start - 1) * 100 if start > 0 else 0
            cursor.execute("UPDATE stocks SET price=%s, change_pct=%s WHERE code=%s", (close, change, code))
            conn.commit()
            print(f"[{i+1}/{len(stocks)}] {code}: {close:.2f} ({change:.2f}%)")
    except Exception as e:
        print(f"[{i+1}/{len(stocks)}] {code} 失败: {e}")

cursor.close()
conn.close()
print("完成!")