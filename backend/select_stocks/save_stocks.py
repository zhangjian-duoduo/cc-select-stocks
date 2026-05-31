#!/usr/bin/env python3
"""保存选股结果到数据库"""
import pymysql
from datetime import datetime
import re
from db import get_db

# 读取选股结果
stocks = []
with open('/tmp/selector.log', 'r') as f:
    for line in f:
        if '选中:' in line:
            # 提取股票代码和名称
            match = re.search(r'选中: (sh\.\d+) (.+)', line)
            if match:
                stocks.append({
                    'code': match.group(1),
                    'name': match.group(2).strip()
                })

print(f"读取到 {len(stocks)} 只股票")

# 连接数据库
conn = get_db()
cursor = conn.cursor()

# 清空旧数据
cursor.execute("TRUNCATE TABLE stocks")
print("已清空旧数据")

# 插入新数据
for stock in stocks:
    # 转换代码格式: sh.600009 -> 600009
    code = stock['code'].replace('sh.', '').replace('sz.', '')
    cursor.execute("""
        INSERT INTO stocks (code, name, price, change_pct, selected_at)
        VALUES (%s, %s, 0, 0, %s)
    """, (code, stock['name'], datetime.now().strftime('%Y-%m-%d')))

conn.commit()
print(f"已保存 {len(stocks)} 只股票到数据库")

cursor.close()
conn.close()