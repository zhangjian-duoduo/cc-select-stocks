#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
同步股票名称到stock_kline - 使用子查询分批更新
"""

import pymysql
import time

from db import get_db

conn = get_db()
cursor = conn.cursor()

# 获取需要更新的代码列表（每只股票只取最新日期的一条）
print("获取需要更新的股票...")
cursor.execute("""
    SELECT DISTINCT k.code
    FROM stock_kline k
    LEFT JOIN stock_names n ON k.code = n.code
    WHERE k.name IS NULL OR k.name = ''
    LIMIT 2000
""")
codes = [row[0] for row in cursor.fetchall()]
print(f"需要更新 {len(codes)} 只股票")

# 逐个更新，每100个提交
total = len(codes)
updated = 0

for i, code in enumerate(codes):
    try:
        cursor.execute("""
            UPDATE stock_kline
            SET name = (SELECT name FROM stock_names WHERE stock_names.code = stock_kline.code LIMIT 1)
            WHERE code = %s AND (name IS NULL OR name = '')
            LIMIT 1
        """, (code,))
        updated += cursor.rowcount
    except Exception as e:
        print(f"更新 {code} 失败: {e}")

    if (i + 1) % 50 == 0:
        conn.commit()
        print(f"进度: {i+1}/{total} (已更新 {updated})")
        time.sleep(0.5)

conn.commit()
print(f"最终更新了 {updated} 条")

# 验证
cursor.execute("SELECT COUNT(DISTINCT code) FROM stock_kline WHERE name IS NOT NULL AND name != ''")
result = cursor.fetchone()
print(f"有名称的股票数: {result[0]}")

cursor.close()
conn.close()
print("完成!")