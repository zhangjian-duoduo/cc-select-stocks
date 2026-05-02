#!/usr/bin/env python3
"""测试量价配合"""
from data_fetcher import DataFetcher
from stock_selector import StockSelector
import pandas as pd

df = DataFetcher()
selector = StockSelector(df)

code = 'sz.000001'
daily = df.fetch_with_fallback('get_stock_daily', code, '20240101', '20240422')
print('Daily rows:', len(daily) if daily is not None else 'None')

if daily is not None:
    # 转换数据类型
    daily['close'] = pd.to_numeric(daily['close'], errors='coerce')
    daily['volume'] = pd.to_numeric(daily['volume'], errors='coerce')

    # 分月
    daily['date'] = pd.to_datetime(daily['date'])
    daily['month'] = daily['date'].dt.to_period('M')
    monthly = daily.groupby('month').agg({'close': 'last', 'volume': 'sum'}).reset_index()
    monthly = monthly.dropna()
    monthly['change'] = monthly['close'].pct_change()
    monthly['is_up'] = monthly['change'] > 0

    print(monthly)

    up_vol = monthly[monthly['is_up'] == True]['volume'].sum()
    down_vol = monthly[monthly['is_up'] == False]['volume'].sum()
    print(f'上涨月成交量: {up_vol:.0f}')
    print(f'下跌月成交量: {down_vol:.0f}')
    ratio = up_vol/down_vol if down_vol > 0 else 0
    print(f'倍数: {ratio:.2f}')

    result = selector.check_volume_price_pattern(daily, min_ratio=2.0)
    print(f'量价配合 (2倍): {result}')