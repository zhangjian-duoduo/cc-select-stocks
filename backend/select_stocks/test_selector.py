#!/usr/bin/env python3
from data_fetcher import DataFetcher
from stock_selector import StockSelector
import time

start = time.time()
df = DataFetcher()
selector = StockSelector(df)

print('=== 开始选股测试 ===')
results = selector.select_stocks(limit=3)
print(f'选出: {len(results)} 只')
print(f'耗时: {time.time()-start:.1f}秒')
for r in results:
    print(f"  {r['code']} {r['name']}")