#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
选股算法模块 - 优化版
支持A股和ETF选股
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from datetime import datetime, timedelta
import concurrent.futures
import time


class StockSelector:
    """选股算法 - 优化版"""

    def __init__(self, data_fetcher):
        self.df = data_fetcher
        # 缩短请求间隔用于批量处理
        self.df.min_interval = 0.3
        self.df.max_interval = 0.8
        # 数据缓存
        self.cache = {}

    def is_st_stock(self, stock_name: str) -> bool:
        """判断是否为ST股"""
        name_upper = str(stock_name).upper()
        keywords = ['ST', '*ST', 'S*ST', 'SST']
        for keyword in keywords:
            if keyword in name_upper:
                return True
        return False

    def check_bottom_consolidation(self, monthly_df: pd.DataFrame, months: int = 12) -> bool:
        """检查月K是否在底部震荡"""
        if monthly_df is None or len(monthly_df) < months:
            return False
        try:
            monthly_df = monthly_df.copy()
            monthly_df['high'] = pd.to_numeric(monthly_df['high'], errors='coerce')
            monthly_df['low'] = pd.to_numeric(monthly_df['low'], errors='coerce')
            recent = monthly_df.tail(months)
            amplitude = (recent['high'].max() - recent['high'].min()) / recent['high'].min()
            return amplitude < 2.0  # 振幅率 < 200%
        except:
            return False

    def check_volume_price规律(self, daily_df: pd.DataFrame) -> bool:
        """检查量价配合规律: 上涨月成交量 > 下跌月成交量
        只要上涨月成交量大于下跌月成交量即可（不要求倍数）
        """
        if daily_df is None or len(daily_df) < 60:
            return False
        try:
            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            daily_df['volume'] = pd.to_numeric(daily_df['volume'], errors='coerce')

            # 按月分组
            daily_df['date'] = pd.to_datetime(daily_df['date'])
            daily_df['month'] = daily_df['date'].dt.to_period('M')

            monthly = daily_df.groupby('month').agg({
                'close': 'last',
                'volume': 'sum'
            }).reset_index()

            # 判断涨跌
            if len(monthly) < 2:
                return False
            monthly['change'] = monthly['close'].pct_change()
            monthly['is_up'] = monthly['change'] > 0

            # 上涨月和下跌月的成交量
            up_volume = monthly[monthly['is_up'] == True]['volume'].sum()
            down_volume = monthly[monthly['is_up'] == False]['volume'].sum()

            # 只要上涨月成交量大于下跌月成交量即可
            return up_volume > down_volume

        except:
            return False

    def check_price_at_low(self, daily_df: pd.DataFrame, threshold: float = 0.3) -> bool:
        """检查当前股价是否处于历史低位30%以下"""
        if daily_df is None or len(daily_df) < 100:
            return False
        try:
            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            recent = daily_df.tail(250 * 5)  # 最近5年
            min_price = recent['close'].min()
            max_price = recent['close'].max()
            current_price = recent['close'].iloc[-1]
            if max_price == min_price:
                return False
            position = (current_price - min_price) / (max_price - min_price)
            return position < threshold
        except:
            return False

    def evaluate_stock(self, stock_code: str, stock_name: str, etf_mode: bool = False) -> Optional[Dict]:
        """评估单只股票是否符合条件"""
        # 条件1: 过滤ST股
        if self.is_st_stock(stock_name):
            return None

        end_date = datetime.now().strftime('%Y%m%d')
        start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')  # 5年数据

        # 获取月K数据
        monthly_df = self.df.fetch_with_fallback('get_stock_monthly', stock_code, start_date, end_date)
        if monthly_df is None or len(monthly_df) < 12:
            return None

        # 条件2: 月K底部震荡
        if not self.check_bottom_consolidation(monthly_df):
            return None

        # 获取日K数据
        daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
        if daily_df is None or len(daily_df) < 60:
            return None

        # 条件3: 量价配合
        if not self.check_volume_price规律(daily_df):
            return None

        # 条件4: 股价历史低位
        if not self.check_price_at_low(daily_df):
            return None

        # 转换数据类型
        daily_df = daily_df.copy()
        daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')

        current_price = daily_df['close'].iloc[-1]
        # change_pct应该是当日涨跌幅（和前一天相比）
        if len(daily_df) >= 2:
            prev_price = daily_df['close'].iloc[-2]
            change_pct = float((current_price / prev_price - 1) * 100) if pd.notna(current_price) and pd.notna(prev_price) and prev_price != 0 else 0
        else:
            change_pct = 0

        return {
            'code': stock_code,
            'name': stock_name,
            'price': float(current_price) if pd.notna(current_price) else 0,
            'change_pct': change_pct,
            'selected_at': datetime.now().strftime('%Y-%m-%d'),
            'type': 'ETF' if etf_mode else 'A'
        }

    def select_stocks(self, limit: int = 50, etf_mode: bool = False) -> List[Dict]:
        """执行选股 - 支持A股和ETF"""
        print(f"[选股算法] {'ETF' if etf_mode else 'A股'} 选股开始...")

        all_stocks = self.df.fetch_with_fallback('get_stock_list')
        if all_stocks is None:
            print("[选股算法] 获取股票列表失败")
            return []

        selected = []
        total = len(all_stocks)
        processed = 0

        for idx, row in all_stocks.iterrows():
            stock_code = row.get('code', '')
            stock_name = row.get('name', '')

            if not stock_code or not stock_name:
                continue

            # ETF模式判断
            is_etf = 'ETF' in stock_name or '指数' in stock_name

            if etf_mode:
                # ETF模式：只选ETF
                if not is_etf:
                    continue
            else:
                # A股模式：排除ETF
                if is_etf:
                    continue

            processed += 1
            if processed % 100 == 0:
                print(f"[选股算法] 已处理 {processed}/{total}, 选出 {len(selected)}")

            result = self.evaluate_stock(stock_code, stock_name, etf_mode)
            if result:
                selected.append(result)
                print(f"[选股] 选中: {stock_code} {stock_name}")

            if len(selected) >= limit:
                break

        print(f"[选股算法] {'ETF' if etf_mode else 'A股'} 选股完成，共选出 {len(selected)} 只")
        return selected


if __name__ == "__main__":
    from data_fetcher import DataFetcher

    df = DataFetcher()
    selector = StockSelector(df)
    results = selector.select_stocks(limit=20)
    print(f"选出股票: {len(results)}")
    for r in results[:5]:
        print(f"  {r['code']} {r['name']}")