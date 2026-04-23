#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析指标模块 - MACD/筹码集中度/趋势分析
"""

import pandas as pd
import numpy as np
import pymysql
from typing import Dict, List, Optional
from datetime import datetime, timedelta


# 数据库配置
DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'select_stocks',
    'charset': 'utf8mb4'
}

def get_db():
    """获取数据库连接"""
    return pymysql.connect(**DB_CONFIG)


class TechnicalAnalyzer:
    """技术分析器"""

    def __init__(self, data_fetcher, use_local_kline=True):
        self.df = data_fetcher
        self.use_local_kline = use_local_kline

    def load_kline_from_db(self, stock_code: str, period: str = 'daily', years: int = 10) -> Optional[pd.DataFrame]:
        """从本地数据库加载K线数据"""
        if not self.use_local_kline:
            return None

        try:
            conn = get_db()
            cursor = conn.cursor(pymysql.cursors.DictCursor)

            # 计算起始日期
            start_date = (datetime.now() - timedelta(days=years*365)).strftime('%Y-%m-%d')
            end_date = datetime.now().strftime('%Y-%m-%d')

            cursor.execute("""
                SELECT code, date, open, high, low, close, volume, amount
                FROM stock_kline
                WHERE code = %s AND period = %s AND date >= %s AND date <= %s
                ORDER BY date
            """, (stock_code, period, start_date, end_date))

            rows = cursor.fetchall()
            cursor.close()
            conn.close()

            if not rows:
                return None

            df = pd.DataFrame(rows)
            # 确保日期列是datetime类型
            df['date'] = pd.to_datetime(df['date'])

            return df

        except Exception as e:
            print(f"[本地K线] 加载失败: {e}")
            return None

    def calculate_macd(self, df: pd.DataFrame, fast: int = 12, slow: int = 26, signal: int = 9) -> pd.DataFrame:
        """计算MACD指标"""
        if df is None or len(df) < slow + signal:
            return None

        try:
            df = df.copy()
            df['close'] = pd.to_numeric(df['close'], errors='coerce')

            # 计算EMA
            ema_fast = df['close'].ewm(span=fast, adjust=False).mean()
            ema_slow = df['close'].ewm(span=slow, adjust=False).mean()

            # DIF
            df['dif'] = ema_fast - ema_slow
            # DEA
            df['dea'] = df['dif'].ewm(span=signal, adjust=False).mean()
            # MACD柱
            df['macd'] = (df['dif'] - df['dea']) * 2

            return df

        except Exception as e:
            print(f"[MACD计算] 失败: {e}")
            return None

    def check_macd_divergence(self, df: pd.DataFrame, periods: List[int] = [5, 20, 60]) -> Dict[str, bool]:
        """检查MACD底背离 - 区分上涨/下跌趋势，只检测底背离"""
        result = {'daily': False, 'weekly': False, 'monthly': False}

        if df is None or len(df) < 60:
            return result

        try:
            df = self.calculate_macd(df)
            if df is None:
                return result

            # 使用多个周期检测
            test_periods = [20, 60, 120]  # 日、周、月周期对应的回看天数

            for period in test_periods:
                if len(df) < period + 30:
                    continue

                recent = df.tail(period + 30)
                prices = recent['close'].values
                difs = recent['dif'].values
                dea = recent['dea'].values if 'dea' in recent.columns else recent.get('macd', difs)

                if len(prices) < 40:
                    continue

                # 判断整体趋势：比较前半段和后半段的平均价格
                mid = len(prices) // 2
                first_half_avg = sum(prices[:mid]) / mid
                second_half_avg = sum(prices[mid:]) / (len(prices) - mid)

                is_downtrend = second_half_avg < first_half_avg * 0.95  # 后半段明显低于前半段

                if not is_downtrend:
                    continue  # 只在下跌趋势中检测底背离

                # 找最近的两个明显低点
                low_points = []
                for i in range(10, len(prices) - 10):
                    # 检查是否是局部最低点
                    if (prices[i] < prices[i-1] and prices[i] < prices[i+1] and
                        prices[i] < prices[i-2] and prices[i] < prices[i+2]):
                        low_points.append((i, prices[i], difs[i]))

                if len(low_points) < 2:
                    continue

                # 比较最近的两个低点
                last_low_idx, last_low_price, last_low_dif = low_points[-1]
                prev_low_idx, prev_low_price, prev_low_dif = low_points[-2]

                # 底背离：价格创新低，但DIF没有创新低（或明显抬高）
                if last_low_price < prev_low_price * 0.98:  # 价格创新低
                    if last_low_dif >= prev_low_dif * 0.9:  # DIF没有明显创新低
                        # 找到日线级别的底背离
                        if period <= 20:
                            result['daily'] = True
                        elif period <= 60:
                            result['weekly'] = True
                        else:
                            result['monthly'] = True
                        break

        except Exception as e:
            print(f"[MACD背离检查] 失败: {e}")

        return result

    def calculate_chip_concentration(self, stock_code: str) -> float:
        """计算筹码集中度 - 多维度综合算法"""
        try:
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=180)).strftime('%Y%m%d')

            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
            if daily_df is None or len(daily_df) < 30:
                return 0.5

            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            daily_df['volume'] = pd.to_numeric(daily_df['volume'], errors='coerce')
            daily_df = daily_df.dropna(subset=['close', 'volume'])

            if len(daily_df) < 30:
                return 0.5

            # ===== 方法1: 价格分布法 (权重40%) =====
            score1 = self._price_distribution_score(daily_df)

            # ===== 方法2: 量价关系法 (权重40%) =====
            score2 = self._volume_price_score(daily_df)

            # ===== 方法3: 换手率振幅法 (权重20%) =====
            score3 = self._turnover_amplitude_score(daily_df)

            # 综合评分
            concentration = score1 * 0.4 + score2 * 0.4 + score3 * 0.2
            return round(min(0.95, max(0.05, concentration)), 2)

        except Exception as e:
            print(f"[筹码集中度] 计算失败: {e}")
            return 0.5

    def _price_distribution_score(self, df: pd.DataFrame) -> float:
        """方法1: 价格分布法 - 找出成交量密集区"""
        try:
            recent = df.tail(60).copy()
            current_price = recent['close'].iloc[-1]

            # 计算价格区间
            min_price = recent['close'].min()
            max_price = recent['close'].max()

            if max_price <= min_price:
                return 0.5

            # 将价格分成10个区间
            price_range = max_price - min_price
            bin_size = price_range / 10

            # 统计每个区间的成交量
            volume_bins = {}
            for _, row in recent.iterrows():
                price = row['close']
                vol = row['volume']
                # 计算价格落在哪个区间
                bin_idx = int((price - min_price) / bin_size) if bin_size > 0 else 5
                bin_idx = min(9, max(0, bin_idx))
                volume_bins[bin_idx] = volume_bins.get(bin_idx, 0) + vol

            if not volume_bins:
                return 0.5

            # 找出成交量最大的区间
            max_vol_bin = max(volume_bins, key=volume_bins.get)
            max_vol = volume_bins[max_vol_bin]

            # 计算当前价格落在哪个区间
            current_bin = int((current_price - min_price) / bin_size) if bin_size > 0 else 5
            current_bin = min(9, max(0, current_bin))

            # 当前价格在密集区 -> 筹码集中
            # 距离密集区越远 -> 筹码越分散
            distance = abs(current_bin - max_vol_bin)

            if distance <= 1:
                # 当前价格在成交量最大区间附近
                return 0.7 + (max_vol_bin == current_bin) * 0.15
            elif distance <= 2:
                return 0.5 + (1 - distance/2) * 0.2
            else:
                return 0.3

        except Exception as e:
            print(f"[价格分布] 失败: {e}")
            return 0.5

    def _volume_price_score(self, df: pd.DataFrame) -> float:
        """方法2: 量价关系法 - 缩量上涨=主力控盘"""
        try:
            recent = df.tail(60).copy()
            recent['change'] = recent['close'].pct_change()
            recent['volume_change'] = recent['volume'].pct_change()

            # 上涨日缩量 = 主力控盘 (筹码集中)
            # 下跌日放量 = 主力出货 (筹码分散)

            up_days = recent[recent['change'] > 0]
            down_days = recent[recent['change'] < 0]

            if len(up_days) == 0 or len(down_days) == 0:
                return 0.5

            avg_vol_up = up_days['volume'].mean()
            avg_vol_down = down_days['volume'].mean()

            # 计算平均价格
            avg_price_up = up_days['close'].mean()
            avg_price_down = down_days['close'].mean()

            # 量比 = 上涨均量 / 下跌均量
            vol_ratio = avg_vol_up / avg_vol_down if avg_vol_down > 0 else 1.0

            # 涨幅 = 上涨幅度 / 下跌幅度
            avg_change_up = up_days['change'].mean() if len(up_days) > 0 else 0
            avg_change_down = abs(down_days['change'].mean()) if len(down_days) > 0 else 0

            # 上涨日缩量 + 下跌日放量 = 筹码集中
            # 理想情况: 量比 < 0.7 且 涨幅 > 下跌幅度
            if vol_ratio < 0.7:
                return 0.8
            elif vol_ratio < 0.85:
                return 0.65
            elif vol_ratio < 1.0:
                return 0.55
            elif vol_ratio < 1.3:
                return 0.45
            else:
                return 0.3

        except Exception as e:
            print(f"[量价关系] 失败: {e}")
            return 0.5

    def _turnover_amplitude_score(self, df: pd.DataFrame) -> float:
        """方法3: 换手率振幅法"""
        try:
            recent = df.tail(60).copy()

            # 平均换手率 (需要市值数据，这里用成交量/总股本估算)
            # 简化: 用成交量与流通市值的比例
            avg_volume = recent['volume'].mean()

            # 振幅 = (最高 - 最低) / 最低
            highest = recent['close'].max()
            lowest = recent['close'].min()
            amplitude = (highest - lowest) / lowest if lowest > 0 else 0

            # 价格波动程度
            price_std = recent['close'].std() / recent['close'].mean()

            # 低换手 + 低振幅 = 筹码集中
            # 高换手 + 高振幅 = 筹码分散
            if amplitude < 0.1:  # 低振幅
                return 0.7 + (1 - amplitude) * 0.2
            elif amplitude < 0.2:
                return 0.55
            elif amplitude < 0.3:
                return 0.45
            else:
                return 0.35

        except Exception as e:
            print(f"[换手振幅] 失败: {e}")
            return 0.5

    def analyze_trend(self, df: pd.DataFrame) -> Dict[str, str]:
        """分析短中长趋势"""
        result = {'short': '未知', 'medium': '未知', 'long': '未知'}

        if df is None or len(df) < 120:
            return result

        try:
            df = df.copy()
            df['close'] = pd.to_numeric(df['close'], errors='coerce')
            df['volume'] = pd.to_numeric(df['volume'], errors='coerce')

            # 短期分析 (1-4周)
            if len(df) >= 20:
                ma5 = df['close'].rolling(5).mean().iloc[-1]
                ma20 = df['close'].rolling(20).mean().iloc[-1]
                current = df['close'].iloc[-1]

                if current > ma5 > ma20:
                    result['short'] = '上涨趋势'
                elif current < ma5 < ma20:
                    result['short'] = '下跌趋势'
                else:
                    result['short'] = '震荡'

            # 中期分析 (1-6月) - 60交易日
            if len(df) >= 60:
                ma20 = df['close'].rolling(20).mean().iloc[-1]
                ma60 = df['close'].rolling(60).mean().iloc[-1]
                current = df['close'].iloc[-1]

                if current > ma20 > ma60:
                    result['medium'] = '上涨趋势'
                elif current < ma20 < ma60:
                    result['medium'] = '下跌趋势'
                else:
                    result['medium'] = '震荡筑底'

            # 长期分析 (1-3年) - 120交易日
            if len(df) >= 120:
                ma60 = df['close'].rolling(60).mean().iloc[-1]
                ma120 = df['close'].rolling(120).mean().iloc[-1]
                current = df['close'].iloc[-1]

                if current > ma60 > ma120:
                    result['long'] = '上涨趋势'
                elif current < ma60 < ma120:
                    result['long'] = '下跌趋势'
                else:
                    result['long'] = '长期筑底'

        except Exception as e:
            print(f"[趋势分析] 失败: {e}")

        return result

    def get_holder_trend(self, stock_code: str, years: int = 5) -> List[Dict]:
        """获取股东人数趋势 (使用akshare东方财富数据)"""
        try:
            import akshare as ak

            # 使用akshare获取股东户数数据
            df = ak.stock_zh_a_gdhs_detail_em(symbol=stock_code)

            if df is None or len(df) == 0:
                return []

            # 按日期排序，最新的在前面
            df = df.sort_values('股东户数统计截止日', ascending=False)

            result = []
            for _, row in df.head(20).iterrows():  # 最多20期
                date_str = str(row.get('股东户数统计截止日', ''))
                holders = row.get('股东户数-本次', 0)

                # 转换日期格式为季度
                if date_str and len(date_str) >= 10:
                    year = date_str[:4]
                    month = int(date_str[5:7])
                    quarter = (month - 1) // 3 + 1
                    date_formatted = f"{year}Q{quarter}"
                else:
                    date_formatted = date_str

                result.append({
                    'date': date_formatted,
                    'holders': int(holders) if holders else 0
                })

            return result

        except Exception as e:
            print(f"[股东人数趋势] 获取失败: {e}")
            return []

    def get_change_5y(self, stock_code: str) -> float:
        """计算5年涨跌幅度"""
        try:
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')

            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
            if daily_df is None or len(daily_df) < 100:
                return 0.0

            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')

            start_price = daily_df['close'].iloc[0]
            end_price = daily_df['close'].iloc[-1]

            if start_price and start_price > 0:
                change = (end_price - start_price) / start_price * 100
                return round(change, 2)
            return 0.0
        except Exception as e:
            print(f"[5年涨跌] 失败: {e}")
            return 0.0

    def get_price_position(self, stock_code: str) -> float:
        """计算当前价格在5年区间的位置 (0-1)"""
        try:
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')

            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
            if daily_df is None or len(daily_df) < 100:
                return 0.5

            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            daily_df = daily_df.dropna(subset=['close'])

            lowest = daily_df['close'].min()
            highest = daily_df['close'].max()
            current = daily_df['close'].iloc[-1]

            if highest > lowest:
                position = (current - lowest) / (highest - lowest)
                return round(position, 3)
            return 0.5
        except Exception as e:
            print(f"[价格位置] 失败: {e}")
            return 0.5

    def get_price_percentile(self, stock_code: str) -> float:
        """获取价格历史分位 (基于5年价格位置估算)"""
        try:
            # 获取5年日K数据
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')

            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
            if daily_df is None or len(daily_df) < 100:
                return 50.0

            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            daily_df = daily_df.dropna(subset=['close'])

            if len(daily_df) < 100:
                return 50.0

            # 使用价格位置作为估值代理
            # 低位 = 低估值 (0-30%)
            # 中位 = 正常估值 (30-70%)
            # 高位 = 高估值 (70-100%)
            lowest = daily_df['close'].min()
            highest = daily_df['close'].max()
            current = daily_df['close'].iloc[-1]

            if highest > lowest:
                position = (current - lowest) / (highest - lowest)
                # 转换为百分位 (低位置 = 低估值 = 低百分位)
                percentile = position * 100
                return round(percentile, 1)

            return 50.0

        except Exception as e:
            print(f"[估值百分位] 失败: {e}")
            return 50.0

    def analyze_stock(self, stock_code: str) -> Dict:
        """完整的股票分析"""
        print(f"[分析] {stock_code}")

        # 优先从本地数据库获取K线数据
        daily_df = self.load_kline_from_db(stock_code, 'daily', years=10)

        # 如果本地没有，尝试从外部获取
        if daily_df is None or len(daily_df) < 100:
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=365*5)).strftime('%Y%m%d')
            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)

        # MACD底背离
        macd_div = self.check_macd_divergence(daily_df) if daily_df is not None else {}

        # 筹码集中度 (多维度综合算法)
        chip_conc = self.calculate_chip_concentration(stock_code)

        # 趋势分析
        trend = self.analyze_trend(daily_df) if daily_df is not None else {}

        # 股东人数趋势 (从东方财富获取真实数据)
        holders_trend = self.get_holder_trend(stock_code)

        # 5年涨跌
        change_5y = self.get_change_5y(stock_code)

        # 价格历史分位 (基于5年价格位置估算，非真实PE)
        price_percentile = self.get_price_percentile(stock_code)

        # 价格位置
        price_position = self.get_price_position(stock_code)

        return {
            'code': stock_code,
            'holders_trend': holders_trend,
            'change_5y': change_5y,
            'price_percentile': price_percentile,
            'chip_concentration': chip_conc,
            'macd_divergence': macd_div,
            'trend_analysis': trend,
            'price_position': price_position
        }


if __name__ == "__main__":
    from data_fetcher import DataFetcher

    df = DataFetcher()
    analyzer = TechnicalAnalyzer(df)
    result = analyzer.analyze_stock("000001")
    print(result)