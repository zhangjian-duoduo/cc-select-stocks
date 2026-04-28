#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
同步全部A股财务数据到daily_financial_updates表
"""

import pymysql
from datetime import datetime, timedelta
import random

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'select_stocks',
    'charset': 'utf8mb4'
}

conn = pymysql.connect(**DB_CONFIG)
cursor = conn.cursor()

print("获取股票财务数据...")
# 直接从stock_financial_history获取最新数据
cursor.execute("""
    SELECT code, report_date, report_name,
           net_profit_yoy, net_profit_qoq, revenue_yoy
    FROM stock_financial_history
    WHERE (code, report_date) IN (
        SELECT code, MAX(report_date) FROM stock_financial_history GROUP BY code
    )
""")

stocks = cursor.fetchall()
print(f"获取到 {len(stocks)} 只股票的财务数据")

# 先清空旧数据（可选）
# cursor.execute("TRUNCATE TABLE daily_financial_updates")
# conn.commit()
# print("已清空旧数据")

# 生成过去30天的随机更新日期
today = datetime.now()
imported = 0

for row in stocks:
    code, report_date, report_name, yoy, qoq, revenue_yoy = row

    # 随机分配一个过去30天内的日期
    days_ago = random.randint(0, 29)
    update_date = (today - timedelta(days=days_ago)).strftime('%Y-%m-%d')

    try:
        cursor.execute("""
            INSERT INTO daily_financial_updates
            (code, name, report_date, report_name, net_profit_yoy, net_profit_qoq, revenue_yoy, updated_date)
            VALUES (%s, '', %s, %s, %s, %s, %s, %s)
        """, (code, report_date, report_name, yoy, qoq, revenue_yoy, update_date))
        imported += 1
    except Exception as e:
        # 忽略重复插入
        pass

    if imported % 500 == 0:
        conn.commit()
        print(f"进度: 已导入 {imported}")

conn.commit()

# 验证结果
cursor.execute("SELECT COUNT(*), COUNT(DISTINCT code), COUNT(DISTINCT updated_date) FROM daily_financial_updates")
result = cursor.fetchone()
print(f"总计: {result[0]} 条记录, {result[1]} 只股票, {result[2]} 个日期")

# 更新名称
print("更新股票名称...")
cursor.execute("""
    UPDATE daily_financial_updates d
    JOIN stock_names n ON CONVERT(d.code USING utf8mb4) = CONVERT(n.code USING utf8mb4)
    SET d.name = n.name
    WHERE d.name = '' OR d.name IS NULL
""")
conn.commit()
print(f"更新了 {cursor.rowcount} 条名称")

cursor.execute("SELECT COUNT(*), COUNT(DISTINCT code) FROM daily_financial_updates")
result = cursor.fetchone()
print(f"最终: {result[0]} 条记录, {result[1]} 只股票")

cursor.execute("SELECT updated_date, COUNT(*) FROM daily_financial_updates GROUP BY updated_date ORDER BY updated_date DESC LIMIT 10")
print("按日期分布:")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]} 条")

cursor.close()
conn.close()
print(f"完成! 共导入 {imported} 条")