#!/usr/bin/env python3
"""快速更新板块信息"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import akshare as ak
import time

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'select_stocks',
    'charset': 'utf8mb4'
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

conn = get_db()
cursor = conn.cursor(pymysql.cursors.DictCursor)

# 获取需要更新板块的股票
cursor.execute("SELECT code FROM stock_analysis WHERE sector IS NULL OR sector = ''")
stocks = cursor.fetchall()
print(f"需要更新板块: {len(stocks)} 只")

updated = 0
for stock in stocks:
    code = stock['code']
    sector = ''
    for _ in range(3):  # 重试3次
        try:
            time.sleep(0.3)
            info = ak.stock_individual_info_em(symbol=code)
            sector_row = info[info['item'] == '行业']
            if not sector_row.empty:
                sector = str(sector_row.iloc[0]['value'])
            break
        except Exception as e:
            time.sleep(1)
            continue

    if sector:
        cursor.execute("UPDATE stock_analysis SET sector = %s WHERE code = %s", (sector, code))
        conn.commit()
        updated += 1
        print(f"{code}: {sector}")

cursor.close()
conn.close()
print(f"板块更新完成: {updated}/{len(stocks)}")