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

    def check_bottom_consolidation(self, monthly_df: pd.DataFrame, months: int = 24) -> bool:
        """检查月K是否在底部震荡
        最近24个月月K振幅 < 300%
        """
        if monthly_df is None or len(monthly_df) < months:
            return False
        try:
            monthly_df = monthly_df.copy()
            monthly_df['high'] = pd.to_numeric(monthly_df['high'], errors='coerce')
            monthly_df['low'] = pd.to_numeric(monthly_df['low'], errors='coerce')
            recent = monthly_df.tail(months)
            amplitude = (recent['high'].max() - recent['low'].min()) / recent['low'].min()
            return amplitude < 3.0  # 振幅率 < 300%
        except:
            return False

    def check_volume_price规律(self, monthly_df: pd.DataFrame, weekly_df: pd.DataFrame) -> bool:
        """检查量价配合规律:
        周K上涨波段：至少5根K线，从低点开始到高点不再创新高结束
        周K下跌波段：至少5根K线，从高点开始到低点不再创新低结束
        上涨波段成交量 > 下跌波段成交量，且这样的规律大于70%
        """
        if weekly_df is None or len(weekly_df) < 60:
            return False
        try:
            weekly_df = weekly_df.copy()
            weekly_df['close'] = pd.to_numeric(weekly_df['close'], errors='coerce')
            weekly_df['high'] = pd.to_numeric(weekly_df['high'], errors='coerce')
            weekly_df['low'] = pd.to_numeric(weekly_df['low'], errors='coerce')
            weekly_df['volume'] = pd.to_numeric(weekly_df['volume'], errors='coerce')
            weekly_df = weekly_df.sort_values('date').reset_index(drop=True)

            # 识别波段
            waves = []  # [(type, volume_sum, kline_count), ...], type: 1=上涨, -1=下跌
            i = 0
            n = len(weekly_df)

            while i < n:
                # 从当前点开始识别上涨波段
                wave_start = i
                up_volumes = []
                up_highs = []

                # 找上涨波段：至少5根K线，高点不再创新高
                j = i + 1
                while j < n:
                    current_high = weekly_df['high'].iloc[j]
                    prev_high = weekly_df['high'].iloc[j - 1]

                    if current_high > prev_high:
                        up_volumes.append(weekly_df['volume'].iloc[j - 1])
                        up_highs.append(prev_high)
                        j += 1
                    else:
                        # 高点不再创新高，检查是否有足够的K线
                        kline_count = j - i
                        if kline_count >= 5:
                            # 加入上涨波段
                            up_volumes.append(weekly_df['volume'].iloc[j - 1])
                            total_up_volume = sum(up_volumes)
                            waves.append((1, total_up_volume, kline_count))
                            i = j  # 从下跌点继续
                        break
                else:
                    # 到末尾了
                    kline_count = j - i
                    if kline_count >= 5:
                        total_up_volume = sum(up_volumes) + weekly_df['volume'].iloc[-1]
                        waves.append((1, total_up_volume, kline_count))
                    break

                if j >= n:
                    break

                # 从当前点开始识别下跌波段：至少5根K线，低点不再创新低
                down_volumes = []
                k = j
                while k < n:
                    current_low = weekly_df['low'].iloc[k]
                    prev_low = weekly_df['low'].iloc[k - 1]

                    if current_low < prev_low:
                        down_volumes.append(weekly_df['volume'].iloc[k - 1])
                        k += 1
                    else:
                        # 低点不再创新低，检查是否有足够的K线
                        kline_count = k - j
                        if kline_count >= 5:
                            # 加入下跌波段
                            down_volumes.append(weekly_df['volume'].iloc[k - 1])
                            total_down_volume = sum(down_volumes)
                            waves.append((-1, total_down_volume, kline_count))
                            i = k  # 从下一个上涨点继续
                        else:
                            # 下跌少于5根，属于上涨波段的一部分
                            i = j
                        break
                else:
                    # 到末尾了
                    kline_count = k - j
                    if kline_count >= 5:
                        total_down_volume = sum(down_volumes)
                        waves.append((-1, total_down_volume, kline_count))
                    break

                if k >= n:
                    break

            # 统计上涨波段成交量 > 下跌波段成交量的次数
            up_count = 0
            down_count = 0

            for w in waves:
                wave_type, wave_volume, kline_count = w
                if wave_type == 1:
                    up_count += 1
                else:
                    down_count += 1

            # 计算符合条件的波段对数（上涨成交量 > 下跌成交量）
            valid_wave_pairs = 0
            total_wave_pairs = 0

            # 配对统计：上涨波段后跟下跌波段
            for idx in range(len(waves) - 1):
                current_type, current_vol, _ = waves[idx]
                next_type, next_vol, _ = waves[idx + 1]

                # 上涨波段后面紧跟下跌波段
                if current_type == 1 and next_type == -1:
                    total_wave_pairs += 1
                    if current_vol > next_vol:
                        valid_wave_pairs += 1

            if total_wave_pairs == 0:
                return False

            # 上涨波段成交量大于下跌波段成交量的比例 > 70%
            return (valid_wave_pairs / total_wave_pairs) >= 0.7

        except Exception as e:
            print(f"[量价分析] 错误: {e}")
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

        # 条件2: 过滤指数/主题基金（没有K线数据的）
        # 检查该股票是否有月K数据（至少60条）
        end_date = datetime.now().strftime('%Y%m%d')
        start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')
        monthly_df = self.df.fetch_with_fallback('get_stock_monthly', stock_code, start_date, end_date)
        if monthly_df is None or len(monthly_df) < 60:
            return None

        # 条件3: 月K底部震荡（最近24个月振幅 < 300%）
        if not self.check_bottom_consolidation(monthly_df):
            return None

        # 获取周K数据（用于量价配合分析）
        weekly_df = self.df.fetch_with_fallback('get_stock_weekly', stock_code, start_date, end_date)

        # 条件3: 量价配合（上涨波段成交量 > 下跌波段成交量 * 70%）
        if not self.check_volume_price规律(monthly_df, weekly_df):
            return None

        # 获取日K数据（用于股价低位判断）
        daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
        if daily_df is None or len(daily_df) < 60:
            return None

        # 条件4: 股价历史低位（5年30%以下）
        if not self.check_price_at_low(daily_df, threshold=0.3):
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

    def select_stocks(self, limit: int = 5000, etf_mode: bool = False) -> List[Dict]:
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