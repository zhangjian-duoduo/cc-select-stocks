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

def create_holders_table():
    """创建股东人数表"""
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS stock_holders (
                id INT AUTO_INCREMENT PRIMARY KEY,
                code VARCHAR(10) NOT NULL,
                date VARCHAR(10) NOT NULL,  -- 格式: 2025Q1
                holders INT,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY uk_code_date (code, date),
                INDEX idx_code (code)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """)
        conn.commit()
        print("[数据库] 股东人数表创建成功")
    finally:
        cursor.close()
        conn.close()


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
        """Check MACD bottom divergence using Elliott Wave Theory
        Improvements:
        1. Use Elliott Wave to identify wave structure
        2. Compare same-level wave lows
        3. Check 5-wave down vs 3-wave down patterns
        """
        result = {'daily': False, 'weekly': False, 'monthly': False}

        if df is None or len(df) < 60:
            return result

        try:
            df = self.calculate_macd(df)
            if df is None:
                return result

            # Calculate MACD bar
            if 'dea' in df.columns:
                df = df.copy()
                df['macd_bar'] = (df['dif'] - df['dea']) * 2

            test_periods = [20, 60, 120]

            for period in test_periods:
                if len(df) < period + 30:
                    continue

                recent = df.tail(period + 30).copy()
                prices = recent['close'].values
                difs = recent['dif'].values
                dea = recent['dea'].values if 'dea' in recent.columns else difs
                bars = recent['macd_bar'].values if 'macd_bar' in recent.columns else difs - dea

                if len(prices) < 40:
                    continue

                # Use Elliott Wave Theory to identify waves
                waves = self._identify_elliott_waves(prices, difs, dea, bars)

                if len(waves) < 3:
                    continue

                # Check for bottom divergence in down waves
                # Compare last two significant lows in the down wave sequence
                divergence_found = self._check_wave_divergence(waves)

                if divergence_found:
                    if period <= 20:
                        result['daily'] = True
                    elif period <= 60:
                        result['weekly'] = True
                    else:
                        result['monthly'] = True

        except Exception as e:
            print(f"[MACD divergence check] failed: {e}")

        return result

    def _identify_elliott_waves(self, prices, difs, dea, bars):
        """Identify Elliott Wave structure
        Returns list of waves with type and data
        Wave types: 1,2,3,4,5 (up), A,B,C (down)
        """
        if len(prices) < 30:
            return []

        # First, find all turning points
        turning_points = self._find_all_turning_points(prices, difs, dea, bars)

        if len(turning_points) < 4:
            return []

        # Label waves based on the pattern
        # Starting from the beginning, alternate up/down
        waves = []
        for i, tp in enumerate(turning_points):
            wave_type = 'up' if i % 2 == 0 else 'down'
            waves.append({
                'index': tp['index'],
                'type': wave_type,
                'price': tp['price'],
                'dif': tp['dif'],
                'dea': tp['dea'],
                'bar': tp['bar']
            })

        # Determine if we're in an uptrend or downtrend overall
        if len(waves) >= 2:
            first_price = waves[0]['price']
            last_price = waves[-1]['price']
            is_downtrend = last_price < first_price

            # If downtrend, flip wave numbering
            # First wave down is labeled as 1 (not A)
            if is_downtrend:
                for w in waves:
                    w['type'] = 'down' if w['type'] == 'up' else 'up'

        return waves

    def _find_all_turning_points(self, prices, difs, dea, bars):
        """Find all significant turning points"""
        points = []

        if len(prices) < 20:
            return points

        # Use multiple windows to find significant turns
        windows = [3, 5, 8]

        for window in windows:
            for i in range(window, len(prices) - window):
                # Check if local low
                is_low = True
                for j in range(i - window, i + window + 1):
                    if j != i and prices[j] <= prices[i]:
                        is_low = False
                        break

                if is_low:
                    # Check if already added nearby
                    add = True
                    for p in points:
                        if abs(p['index'] - i) <= window:
                            if prices[i] < p['price']:
                                points.remove(p)
                            else:
                                add = False
                                break
                    if add:
                        points.append({
                            'index': i,
                            'type': 'low',
                            'price': prices[i],
                            'dif': difs[i],
                            'dea': dea[i],
                            'bar': bars[i]
                        })

                # Check if local high
                is_high = True
                for j in range(i - window, i + window + 1):
                    if j != i and prices[j] >= prices[i]:
                        is_high = False
                        break

                if is_high:
                    add = True
                    for p in points:
                        if abs(p['index'] - i) <= window:
                            if prices[i] > p['price']:
                                points.remove(p)
                            else:
                                add = False
                                break
                    if add:
                        points.append({
                            'index': i,
                            'type': 'high',
                            'price': prices[i],
                            'dif': difs[i],
                            'dea': dea[i],
                            'bar': bars[i]
                        })

        # Sort by index
        points.sort(key=lambda x: x['index'])

        # Keep only significant points (remove too close ones)
        if len(points) > 1:
            filtered = [points[0]]
            for i in range(1, len(points)):
                # Keep if far enough from last kept point
                if points[i]['index'] - filtered[-1]['index'] >= 5:
                    filtered.append(points[i])
            return filtered

        return points

    def _check_wave_divergence(self, waves):
        """Check for bottom divergence in wave structure
        Compare: 5th wave low vs 3rd wave low (in down sequence)
        Or: C wave low vs A wave low
        """
        if len(waves) < 4:
            return False

        # Get all down wave lows
        down_waves = [w for w in waves if w['type'] == 'down']

        if len(down_waves) < 2:
            return False

        # Compare last two down wave lows
        last_low = down_waves[-1]
        prev_low = down_waves[-2]

        # Check if price made new low
        if last_low['price'] >= prev_low['price'] * 0.98:
            return False

        # Calculate divergence score (at least 2 indicators)
        score = 0

        # DIF divergence
        if last_low['dif'] >= prev_low['dif'] * 0.85:
            score += 1

        # DEA divergence
        if last_low['dea'] >= prev_low['dea'] * 0.85:
            score += 1

        # MACD bar divergence
        if last_low['bar'] >= prev_low['bar'] * 0.8:
            score += 1

        return score >= 2

    def calculate_chip_concentration(self, stock_code: str) -> float:
        """计算筹码集中度 - 优化版多维度综合算法

        优化点：
        1. 时间加权：近期成交量权重更大
        2. 成本区间分析：底部价格区间成交量占比
        3. 股东人数因子：股东减少=筹码集中
        4. 移动成本分布：20/80成本线
        5. 更精细的价格分箱
        """
        try:
            end_date = datetime.now().strftime('%Y%m%d')
            start_date = (datetime.now() - timedelta(days=250)).strftime('%Y%m%d')

            daily_df = self.df.fetch_with_fallback('get_stock_daily', stock_code, start_date, end_date)
            if daily_df is None or len(daily_df) < 60:
                return 0.5

            daily_df = daily_df.copy()
            daily_df['close'] = pd.to_numeric(daily_df['close'], errors='coerce')
            daily_df['volume'] = pd.to_numeric(daily_df['volume'], errors='coerce')
            daily_df = daily_df.dropna(subset=['close', 'volume'])

            if len(daily_df) < 60:
                return 0.5

            # ===== 方法1: 成本分布法 (权重35%) =====
            score1 = self._cost_distribution_score(daily_df)

            # ===== 方法2: 时间加权价格分布 (权重25%) =====
            score2 = self._time_weighted_price_distribution(daily_df)

            # ===== 方法3: 量价配合法 (权重20%) =====
            score3 = self._volume_price_score(daily_df)

            # ===== 方法4: 股东人数因子 (权重10%) =====
            score4 = self._holder_number_score(stock_code)

            # ===== 方法5: 移动成本线 (权重10%) =====
            score5 = self._cost_line_score(daily_df)

            # 综合评分
            concentration = score1 * 0.35 + score2 * 0.25 + score3 * 0.20 + score4 * 0.10 + score5 * 0.10
            return round(min(0.95, max(0.05, concentration)), 2)

        except Exception as e:
            print(f"[筹码集中度] 计算失败: {e}")
            return 0.5

    def _cost_distribution_score(self, df: pd.DataFrame) -> float:
        """成本分布法 - 底部价格区间成交量占比"""
        try:
            recent = df.tail(120).copy()
            current_price = recent['close'].iloc[-1]

            # 计算价格区间（20个更精细）
            min_price = recent['close'].min()
            max_price = recent['close'].max()

            if max_price <= min_price or max_price == 0:
                return 0.5

            # 底部1/3价格区间为"低成本区"
            price_range = max_price - min_price
            low_threshold = min_price + price_range * 0.33
            mid_threshold = min_price + price_range * 0.66

            # 统计各区间成交量
            low_vol = recent[recent['close'] <= low_threshold]['volume'].sum()
            mid_vol = recent[(recent['close'] > low_threshold) & (recent['close'] <= mid_threshold)]['volume'].sum()
            high_vol = recent[recent['close'] > mid_threshold]['volume'].sum()

            total_vol = low_vol + mid_vol + high_vol
            if total_vol == 0:
                return 0.5

            # 底部成交量占比
            low_ratio = low_vol / total_vol

            # 当前价格在低位还是高位
            if current_price <= low_threshold:
                position_bonus = 0.15  # 当前价格就在低成本区
            elif current_price <= mid_threshold:
                position_bonus = 0.05
            else:
                position_bonus = -0.05

            # 底部占比超过50%说明大量筹码在低位
            score = min(0.9, low_ratio * 1.3 + position_bonus)
            return max(0.1, score)

        except:
            return 0.5

    def _time_weighted_price_distribution(self, df: pd.DataFrame) -> float:
        """时间加权价格分布 - 近期权重更大"""
        try:
            # 分成4个30天窗口，每个窗口权重递增
            windows = []
            weights = [0.1, 0.2, 0.3, 0.4]  # 越近权重越大

            for i in range(4):
                start_idx = len(df) - 120 + i * 30
                end_idx = start_idx + 30
                if start_idx >= 0:
                    window = df.iloc[start_idx:min(end_idx, len(df))].copy()
                    if len(window) > 0:
                        current = window['close'].iloc[-1]
                        min_p = window['close'].min()
                        max_p = window['close'].max()

                        if max_p > min_p:
                            # 当前价在区间的位置（0=最低，1=最高）
                            position = (current - min_p) / (max_p - min_p)
                            # 越接近底部分数越高
                            score = 1 - position
                            windows.append(score * weights[i])

            if not windows:
                return 0.5

            return sum(windows) / sum(weights[:len(windows)])

        except:
            return 0.5

    def _holder_number_score(self, stock_code: str) -> float:
        """股东人数因子 - 股东减少=筹码集中"""
        try:
            holders_trend = self.get_holder_trend(stock_code)
            if not holders_trend or len(holders_trend) < 2:
                return 0.5  # 无数据时返回中性

            # 比较最近两个季度的股东人数（数组已按旧到新排列）
            oldest_holders = holders_trend[0].get('holders', 0)
            latest_holders = holders_trend[-1].get('holders', 0)

            if oldest_holders == 0:
                return 0.5

            change_pct = (latest_holders - oldest_holders) / oldest_holders

            # 股东减少=筹码集中（加分）
            # 股东增加=筹码分散（减分）
            if change_pct < -0.2:  # 减少超过20%
                return 0.85
            elif change_pct < -0.1:  # 减少超过10%
                return 0.70
            elif change_pct < 0:  # 减少
                return 0.55
            elif change_pct < 0.1:  # 略增
                return 0.45
            elif change_pct < 0.2:  # 增加超过10%
                return 0.30
            else:  # 大幅增加
                return 0.15

        except:
            return 0.5

    def _cost_line_score(self, df: pd.DataFrame) -> float:
        """移动成本线 - 20/80成本线分析"""
        try:
            recent = df.tail(120).copy()
            current_price = recent['close'].iloc[-1]

            # 按成交量加权计算成本线
            total_vol = 0
            weighted_price = 0
            for _, row in recent.iterrows():
                vol = row['volume']
                price = row['close']
                weighted_price += price * vol
                total_vol += vol

            if total_vol == 0:
                return 0.5

            avg_cost = weighted_price / total_vol

            # 20%成本线：20%的成交量在哪个价格以下
            # 80%成本线：80%的成交量在哪个价格以下
            # 简化计算：用当前价与平均成本的比值

            if current_price <= avg_cost * 0.9:
                # 当前价低于平均成本10%以上，高度集中
                return 0.85
            elif current_price <= avg_cost:
                # 当前价低于平均成本
                return 0.70
            elif current_price <= avg_cost * 1.1:
                # 当前价略高于平均成本
                return 0.50
            elif current_price <= avg_cost * 1.3:
                # 当前价高于平均成本10-30%
                return 0.35
            else:
                # 当前价高于平均成本30%以上，高度分散
                return 0.20

        except:
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
        """分析短中长趋势 - 优化版"""
        result = {'short': '未知', 'medium': '未知', 'long': '未知'}

        if df is None or len(df) < 250:
            return result

        try:
            df = df.copy()
            df['close'] = pd.to_numeric(df['close'], errors='coerce')
            df['volume'] = pd.to_numeric(df['volume'], errors='coerce')

            # 计算MACD指标
            ema12 = df['close'].ewm(span=12, adjust=False).mean()
            ema26 = df['close'].ewm(span=26, adjust=False).mean()
            dif = ema12 - ema26
            dea = dif.ewm(span=9, adjust=False).mean()
            macd_bar = (dif - dea) * 2

            # ===== 短期分析 (1-4周) =====
            # 放量突破20日高点 + MACD金叉
            if len(df) >= 20:
                current = df['close'].iloc[-1]
                ma20 = df['close'].rolling(20).mean().iloc[-1]
                ma60 = df['close'].rolling(60).mean().iloc[-1]
                high20 = df['high'].rolling(20).max().iloc[-1]
                vol_ma20 = df['volume'].rolling(20).mean().iloc[-1]
                current_vol = df['volume'].iloc[-1]

                # 放量突破20日高点
                volume_breakout = current_vol > vol_ma20 * 1.5 and current > high20
                # MACD金叉 (DIF从下往上穿过DEA)
                macd_golden = dif.iloc[-1] > dea.iloc[-1] and dif.iloc[-2] <= dea.iloc[-2]

                if volume_breakout and macd_golden:
                    result['short'] = '上涨趋势'
                elif current < ma20 < ma60:
                    result['short'] = '下跌趋势'
                else:
                    result['short'] = '震荡'

            # ===== 中期分析 (1-6月) =====
            # 站上年线(250日) + 股东减少
            if len(df) >= 250:
                current = df['close'].iloc[-1]
                ma250 = df['close'].rolling(250).mean().iloc[-1]  # 年线

                above_year_line = current > ma250  # 站上年线

                if above_year_line:
                    result['medium'] = '上涨趋势'
                elif current < ma250 * 0.8:  # 远离年线下方
                    result['medium'] = '下跌趋势'
                else:
                    result['medium'] = '震荡筑底'

            # ===== 长期分析 (1-3年) =====
            # 月K线MACD零轴上金叉
            # 需要周K数据来判断长期
            if len(df) >= 60:
                # 60周均线
                ma60_week = df['close'].rolling(60).mean().iloc[-1]
                current = df['close'].iloc[-1]

                # 月MACD金叉判断：检查DIF和DEA的关系
                macd_above_zero = dif.iloc[-1] > 0  # MACD在零轴上方
                macd_golden_long = dif.iloc[-1] > dea.iloc[-1] and dif.iloc[-3] <= dea.iloc[-3]

                if macd_above_zero and macd_golden_long and current > ma60_week:
                    result['long'] = '上涨趋势'
                elif current < ma60_week * 0.7:
                    result['long'] = '下跌趋势'
                else:
                    result['long'] = '长期筑底'

        except Exception as e:
            print(f"[趋势分析] 失败: {e}")

        return result

    def get_holder_trend(self, stock_code: str, years: int = 5) -> List[Dict]:
        """获取股东人数趋势 - 优先从本地数据库获取
        返回从旧到新的时间序列（供图表从左到右显示）"""

        # 1. 先从本地数据库获取
        try:
            conn = get_db()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            # 按时间升序排列（旧到新）
            cursor.execute("""
                SELECT date, holders FROM stock_holders
                WHERE code = %s ORDER BY date ASC LIMIT 20
            """, (stock_code,))
            rows = cursor.fetchall()
            cursor.close()
            conn.close()

            if rows and len(rows) > 0:
                result = [{'date': row['date'], 'holders': row['holders']} for row in rows]
                print(f"[股东人数] 从本地获取 {stock_code}: {len(result)} 条")
                return result
        except Exception as e:
            print(f"[股东人数] 本地获取失败: {e}")

        # 2. 本地没有，从网络获取
        try:
            import akshare as ak
            df = ak.stock_zh_a_gdhs_detail_em(symbol=stock_code)

            if df is None or len(df) == 0:
                return []

            # 按日期排序
            df = df.sort_values('股东户数统计截止日', ascending=False)

            result = []
            conn = get_db()
            cursor = conn.cursor()

            for _, row in df.head(20).iterrows():
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

                holders_val = int(holders) if holders else 0
                result.append({
                    'date': date_formatted,
                    'holders': holders_val
                })

                # 保存到本地数据库
                try:
                    cursor.execute("""
                        INSERT INTO stock_holders (code, date, holders)
                        VALUES (%s, %s, %s)
                        ON DUPLICATE KEY UPDATE holders = VALUES(holders)
                    """, (stock_code, date_formatted, holders_val))
                except:
                    pass

            conn.commit()
            cursor.close()
            conn.close()

            print(f"[股东人数] 从网络获取 {stock_code}: {len(result)} 条")
            # 反转结果：从旧到新（供图表从左到右显示）
            result.reverse()
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