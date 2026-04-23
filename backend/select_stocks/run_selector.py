#!/usr/bin/env python3
"""选股测试脚本 - 先测试50只"""
from data_fetcher import DataFetcher
from stock_selector import StockSelector
import time

print("=" * 50)
print("开始选股测试 (50只)")
print("=" * 50)

start = time.time()
df = DataFetcher()
# 缩短延迟
df.min_interval = 0.2
df.max_interval = 0.5

selector = StockSelector(df)

# 执行选股
results = selector.select_stocks(limit=50)

print("=" * 50)
print(f"选股完成: {len(results)} 只")
print(f"耗时: {time.time()-start:.1f} 秒")
print("=" * 50)

for r in results:
    print(f"  {r['code']} {r['name']}")