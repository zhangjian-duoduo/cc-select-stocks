#!/usr/bin/env python3
"""快速测试单只股票"""
from data_fetcher import DataFetcher

df = DataFetcher()
# 缩短延迟用于测试
df.min_interval = 0.5
df.max_interval = 1.0

# 测试一只股票
code = 'sz.000001'
print(f'Testing {code}')

# 日K
daily = df.get_stock_daily_baostock(code, '20240101', '20240422')
if daily is not None:
    print(f'Daily OK: {len(daily)} rows')
print(daily.tail(2) if daily else 'failed')

# 月K
monthly = df.get_stock_monthly(code, '20240101', '20240422')
if monthly is not None:
    print(f'Monthly OK: {len(monthly)} rows')
print(monthly.tail(2) if monthly else 'failed')