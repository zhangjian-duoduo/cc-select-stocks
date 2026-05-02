#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API接口模块
"""

from flask import Flask, jsonify, request
import pymysql
import os
import traceback
from datetime import datetime, timedelta

app = Flask(__name__)

# 数据库配置（密码从环境变量读取，未设置则使用空密码）
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),
    'database': os.environ.get('DB_NAME', 'select_stocks'),
    'charset': 'utf8mb4'
}

def get_db():
    """获取数据库连接"""
    return pymysql.connect(**DB_CONFIG)

def extract_quarter(report_name):
    """从报告名称提取季度"""
    if not report_name:
        return ''
    # 使用简单字符串匹配
    if '一季' in report_name:
        return report_name[:4] + 'Q1'
    elif '中报' in report_name:
        return report_name[:4] + 'Q2'
    elif '三季' in report_name:
        return report_name[:4] + 'Q3'
    elif '年报' in report_name:
        return report_name[:4] + 'Q4'
    return ''

@app.route('/api/v1/stocks', methods=['GET'])
def get_stocks():
    """获取选股列表"""
    page = request.args.get('page', 1, type=int)
    page_size = request.args.get('page_size', 50, type=int)
    offset = (page - 1) * page_size

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("""
            SELECT s.code, s.name, s.price, s.change_pct, s.selected_at, s.sector,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position,
                   f.net_profit_yoy, f.net_profit_qoq, a.roe
            FROM stocks s
            LEFT JOIN stock_analysis a ON s.code = a.code
            LEFT JOIN (
                SELECT code, net_profit_yoy, net_profit_qoq
                FROM stock_financial_history
                WHERE (code, report_date) IN (
                    SELECT code, MAX(report_date) FROM stock_financial_history GROUP BY code
                )
            ) f ON s.code = f.code
            ORDER BY s.selected_at DESC
            LIMIT %s OFFSET %s
        """, (page_size, offset))

        result = cursor.fetchall()

        # 转换日期为字符串，确保数值类型正确
        from decimal import Decimal
        import json
        for row in result:
            if row.get('selected_at'):
                row['selected_at'] = row['selected_at'].strftime('%Y-%m-%d')
            # 解析JSON字段
            for json_field in ['holders_trend', 'macd_divergence', 'trend_analysis']:
                if row.get(json_field):
                    try:
                        if isinstance(row[json_field], str):
                            row[json_field] = json.loads(row[json_field])
                    except:
                        row[json_field] = None
                else:
                    row[json_field] = None
            # 统一处理数值字段
            for num_field in ['price', 'change_pct', 'change_5y', 'price_percentile', 'chip_concentration', 'price_position']:
                if row.get(num_field) is not None:
                    try:
                        val = row[num_field]
                        if isinstance(val, (int, float, Decimal)):
                            row[num_field] = float(val)
                        elif isinstance(val, str) and val:
                            row[num_field] = float(val)
                        else:
                            row[num_field] = 0.0 if num_field in ('price', 'change_pct') else None
                    except:
                        row[num_field] = 0.0 if num_field in ('price', 'change_pct') else None
                else:
                    row[num_field] = 0.0 if num_field in ('price', 'change_pct') else None

        return jsonify({'code': 0, 'data': result, 'total': len(result)})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/filter', methods=['POST'])
def filter_stocks():
    """多条件筛选股票"""
    import json
    from decimal import Decimal

    data = request.get_json() or {}
    filters = data.get('filters', [])

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # 获取所有股票和分析数据
        cursor.execute("""
            SELECT s.code, s.name, s.price, s.change_pct, s.selected_at,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position,
                   a.roe, a.net_profit_yoy, a.net_profit_qoq
            FROM stocks s
            LEFT JOIN stock_analysis a ON s.code = a.code
        """)

        stocks = cursor.fetchall()

        # 转换数据格式
        processed_stocks = []
        for row in stocks:
            stock = dict(row)
            if stock.get('selected_at'):
                stock['selected_at'] = stock['selected_at'].strftime('%Y-%m-%d')

            # 解析JSON字段
            for field in ['holders_trend', 'macd_divergence', 'trend_analysis']:
                if stock.get(field) and isinstance(stock[field], str):
                    try:
                        stock[field] = json.loads(stock[field])
                    except:
                        stock[field] = None

            # 转换数值字段
            for field in ['price', 'change_pct', 'change_5y', 'price_percentile', 'chip_concentration', 'price_position']:
                if stock.get(field) is not None:
                    try:
                        stock[field] = float(stock[field])
                    except:
                        stock[field] = None

            processed_stocks.append(stock)

        # 应用筛选条件（传入数据库连接）
        filtered = apply_filters(processed_stocks, filters, conn)

        return jsonify({'code': 0, 'data': filtered, 'total': len(filtered)})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

def apply_filters(stocks, filters, conn=None):
    """应用筛选条件"""
    if not filters:
        return stocks

    # 如果没有提供连接，获取一个新连接
    own_conn = False
    if conn is None:
        conn = get_db()
        own_conn = True

    # 预加载需要的K线数据（批量查询，大幅提升性能）
    kline_cache = _preload_klines(stocks, filters, conn)

    result = []

    for stock in stocks:
        passed = True
        code = stock.get('code')

        for filter_name in filters:
            if filter_name == 'momentum_reversal':
                if not check_momentum_reversal(stock):
                    passed = False
                    break

            elif filter_name == 'ma_alignment':
                if not check_ma_alignment_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'volume_break':
                if not check_volume_break_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'low_volume':
                if not check_low_volume_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'yoy_positive':
                if not check_yoy_positive(code, conn):
                    passed = False
                    break

            elif filter_name == 'qoq_positive':
                if not check_qoq_positive(code, conn):
                    passed = False
                    break

            elif filter_name == 'volume_rise_stagnant':
                if not check_volume_rise_stagnant_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'support_level':
                if not check_support_level_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'resistance_level':
                if not check_resistance_level_cached(code, kline_cache):
                    passed = False
                    break

            elif filter_name == 'high_dividend':
                if not check_high_dividend(stock):
                    passed = False
                    break

            elif filter_name == 'low_pb':
                if not check_low_pb(code, stock.get('price')):
                    passed = False
                    break

            elif filter_name == 'small_cap':
                if not check_small_cap_simple(code, stock.get('price')):
                    passed = False
                    break

            elif filter_name == 'holder_decrease':
                if not check_holder_decrease(stock):
                    passed = False
                    break

            elif filter_name == 'sector_rotation':
                if not check_sector_rotation(stock):
                    passed = False
                    break

        if passed:
            result.append(stock)

    if own_conn and conn:
        conn.close()

    return result


def _preload_klines(stocks, filters, conn):
    """批量预加载K线数据，返回 {code: [{date, close, volume}, ...]} 按日期降序"""
    kline_filters = {'ma_alignment', 'volume_break', 'low_volume', 'volume_rise_stagnant',
                     'support_level', 'resistance_level'}
    if not (set(filters) & kline_filters):
        return {}

    codes = [s['code'] for s in stocks]
    if not codes:
        return {}

    cursor = conn.cursor(pymysql.cursors.DictCursor)
    placeholders = ','.join(['%s'] * len(codes))

    # 加日期过滤避免全表扫描：60日均线最多需要最近90天数据
    limit_per_stock = 60
    cursor.execute(f"""
        SELECT code, date, close, volume
        FROM stock_kline
        WHERE code IN ({placeholders}) AND period = 'daily'
          AND date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
        ORDER BY code, date DESC
    """, codes)

    cache = {}
    for row in cursor.fetchall():
        code = row['code']
        if code not in cache:
            cache[code] = []
        if len(cache[code]) < limit_per_stock:
            cache[code].append({
                'date': row['date'],
                'close': float(row['close']) if row.get('close') else 0,
                'volume': float(row['volume']) if row.get('volume') else 0,
            })

    cursor.close()
    return cache


def check_ma_alignment_cached(code, kline_cache):
    """均线多头排列（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 60:
        return False
    closes = [k['close'] for k in reversed(klines)]
    ma5 = sum(closes[-5:]) / 5
    ma10 = sum(closes[-10:]) / 10
    ma20 = sum(closes[-20:]) / 20
    ma60 = sum(closes[-60:]) / 60
    return ma5 > ma10 > ma20 > ma60


def check_volume_break_cached(code, kline_cache):
    """放量突破（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 21:
        return False
    latest_volume = klines[0]['volume']
    max_vol_20 = max(k['volume'] for k in klines[1:21])
    return latest_volume > max_vol_20 * 0.7


def check_low_volume_cached(code, kline_cache):
    """明显缩量（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 21:
        return False
    latest_volume = klines[0]['volume']
    volumes = [k['volume'] for k in klines[1:21]]
    avg_vol = sum(volumes) / len(volumes) if volumes else 0
    if avg_vol <= 0:
        return False
    return latest_volume < avg_vol * 0.5


def check_volume_rise_stagnant_cached(code, kline_cache):
    """放量滞涨（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 21:
        return False
    latest_volume = klines[0]['volume']
    latest_price = klines[0]['close']
    volumes = [k['volume'] for k in klines[1:21]]
    avg_vol = sum(volumes) / len(volumes) if volumes else 0
    if avg_vol <= 0:
        return False
    is_volume_up = latest_volume > avg_vol * 1.5
    old_price = klines[20]['close']
    if old_price <= 0:
        return False
    price_change = (latest_price - old_price) / old_price * 100
    return is_volume_up and price_change < 5


def check_support_level_cached(code, kline_cache):
    """跌到支撑位（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 20:
        return False
    latest_price = klines[0]['close']
    if latest_price <= 0:
        return False
    low_20 = min(k['close'] for k in klines[:20] if k['close'] > 0)
    if low_20 <= 0:
        return False
    return (latest_price - low_20) / low_20 < 0.03


def check_resistance_level_cached(code, kline_cache):
    """涨到压力位（使用预加载缓存）"""
    klines = kline_cache.get(code, [])
    if len(klines) < 20:
        return False
    latest_price = klines[0]['close']
    if latest_price <= 0:
        return False
    high_20 = max(k['close'] for k in klines[:20] if k['close'] > 0)
    if high_20 <= 0:
        return False
    return (high_20 - latest_price) / high_20 < 0.03

def check_momentum_reversal(stock):
    """检查动量反转：跌幅>50% + MACD底背离"""
    try:
        # 检查5年跌幅>50% (从最高点)
        change_5y = stock.get('change_5y', 0) or 0
        if change_5y > -50:
            return False

        # 检查MACD日线底背离
        macd = stock.get('macd_divergence', {}) or {}
        if not macd.get('daily'):
            return False

        return True
    except:
        return False

def check_holder_decrease(stock):
    """检查股东人数是否连续减少"""
    try:
        holders = stock.get('holders_trend', []) or []
        if len(holders) < 2:
            return False

        # 最新两期比较
        latest = holders[-1].get('holders', 0) or 0
        previous = holders[-2].get('holders', 0) or 0

        return latest < previous
    except:
        return False

def check_ma_alignment(stock_code, conn):
    """检查均线多头排列：5日>10日>20日>60日"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最近60个交易日K线
        cursor.execute("""
            SELECT date, close
            FROM stock_kline
            WHERE code = %s AND period = 'daily'
            ORDER BY date DESC
            LIMIT 60
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 60:
            return False

        # 计算均线（简单移动平均）
        closes = [float(k['close']) for k in reversed(klines)]

        ma5 = sum(closes[-5:]) / 5
        ma10 = sum(closes[-10:]) / 10
        ma20 = sum(closes[-20:]) / 20
        ma60 = sum(closes[-60:]) / 60

        # 多头排列：ma5 > ma10 > ma20 > ma60
        return ma5 > ma10 > ma20 > ma60
    except:
        return False

def check_volume_break(stock_code, conn):
    """检查放量突破：成交量突破20日最高量"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最近21个交易日
        cursor.execute("""
            SELECT date, volume
            FROM stock_kline
            WHERE code = %s AND period = 'daily'
            ORDER BY date DESC
            LIMIT 21
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 21:
            return False

        # 最新一天的成交量
        latest_volume = float(klines[0]['volume'])

        # 20日内最高量
        volumes = [float(k['volume']) for k in klines[1:21]]
        max_volume_20d = max(volumes)

        # 放量：超过20日最高量的70%或突破
        return latest_volume > max_volume_20d * 0.7
    except:
        return False

def check_low_volume(stock_code, conn):
    """检查明显缩量：成交量低于20日平均量的50%"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最近21个交易日
        cursor.execute("""
            SELECT date, volume
            FROM stock_kline
            WHERE code = %s AND period = 'daily'
            ORDER BY date DESC
            LIMIT 21
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 21:
            return False

        # 最新一天的成交量
        latest_volume = float(klines[0]['volume'])

        # 20日平均成交量
        volumes = [float(k['volume']) for k in klines[1:21]]
        avg_volume_20d = sum(volumes) / len(volumes) if volumes else 0

        if avg_volume_20d <= 0:
            return False

        # 缩量：低于20日平均量的50%
        return latest_volume < avg_volume_20d * 0.5
    except:
        return False

def check_yoy_positive(stock_code, conn):
    """检查业绩同比转正：净利润同比 > 0"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最新财报的净利润同比
        cursor.execute("""
            SELECT net_profit_yoy
            FROM stock_financial_history
            WHERE code = %s
            ORDER BY report_date DESC
            LIMIT 1
        """, (stock_code,))

        row = cursor.fetchone()
        if not row or not row.get('net_profit_yoy'):
            return False

        yoy = row['net_profit_yoy']
        if not yoy:
            return False

        # 解析百分比，去除%+符号
        clean_yoy = yoy.replace('%', '').replace('+', '').strip()
        try:
            value = float(clean_yoy)
            return value > 0
        except:
            return False
    except:
        return False

def check_qoq_positive(stock_code, conn):
    """检查业绩环比转正：净利润环比 > 0"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最新财报的净利润环比
        cursor.execute("""
            SELECT net_profit_qoq
            FROM stock_financial_history
            WHERE code = %s
            ORDER BY report_date DESC
            LIMIT 1
        """, (stock_code,))

        row = cursor.fetchone()
        if not row or not row.get('net_profit_qoq'):
            return False

        qoq = row['net_profit_qoq']
        if not qoq:
            return False

        # 解析百分比，去除%+符号
        clean_qoq = qoq.replace('%', '').replace('+', '').strip()
        try:
            value = float(clean_qoq)
            return value > 0
        except:
            return False
    except:
        return False

def check_volume_rise_stagnant(stock_code, conn):
    """检查放量滞涨：成交量放大但价格不涨"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取最近21个交易日
        cursor.execute("""
            SELECT date, volume, close
            FROM stock_kline
            WHERE code = %s AND period = 'daily'
            ORDER BY date DESC
            LIMIT 21
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 21:
            return False

        # 最新一天的成交量和价格
        latest_volume = float(klines[0]['volume'])
        latest_price = float(klines[0]['close'])

        # 20日平均成交量
        volumes = [float(k['volume']) for k in klines[1:21]]
        avg_volume_20d = sum(volumes) / len(volumes) if volumes else 0

        if avg_volume_20d <= 0:
            return False

        # 放量：成交量 > 20日平均量的1.5倍
        is_volume_up = latest_volume > avg_volume_20d * 1.5

        # 获取20日前的价格
        old_price = float(klines[20]['close'])
        if old_price <= 0:
            return False

        # 滞涨：价格涨幅 < 5%
        price_change = (latest_price - old_price) / old_price * 100
        is_price_stagnant = price_change < 5

        return is_volume_up and is_price_stagnant
    except:
        return False

def find_zigzag_peaks_troughs(highs, lows, threshold=5):
    """
    ZigZag算法识别波峰和波谷
    threshold: 最小波动幅度百分比，超过才认为是有效反转
    """
    if len(highs) < 10:
        return [], []

    peaks = []  # 波峰索引
    troughs = []  # 波谷索引

    # 使用close计算趋势
    prices = [(h + l) / 2 for h, l in zip(highs, lows)]  # 用高低点中值

    i = 0
    last_extreme_idx = 0
    last_extreme_type = None  # 'peak' or 'trough'

    while i < len(prices) - 1:
        change = (prices[i + 1] - prices[i]) / prices[i] * 100 if prices[i] != 0 else 0

        # 确定初始趋势
        if abs(change) >= threshold:
            direction = 1 if change > 0 else -1
            last_extreme_type = 'trough' if direction == 1 else 'peak'
            last_extreme_idx = i
            i += 1
            break
        i += 1

    if i >= len(prices) - 1:
        return [], []

    # 继续扫描找到波峰波谷
    while i < len(prices):
        if last_extreme_type == 'trough':
            # 找波峰：从低点向上找最高点
            max_val = prices[last_extreme_idx]
            max_idx = last_extreme_idx
            while i < len(prices):
                if prices[i] > max_val:
                    change_from_last = (prices[i] - max_val) / max_val * 100 if max_val != 0 else 0
                    if change_from_last >= threshold:
                        max_val = prices[i]
                        max_idx = i
                    elif prices[i] < max_val * (1 - threshold / 100):
                        # 反转超过阈值，确认波峰
                        peaks.append(max_idx)
                        last_extreme_type = 'peak'
                        last_extreme_idx = max_idx
                        break
                elif prices[i] < max_val:
                    if (max_val - prices[i]) / max_val * 100 >= threshold:
                        # 反转超过阈值，确认波峰
                        peaks.append(max_idx)
                        last_extreme_type = 'peak'
                        last_extreme_idx = i
                        break
                i += 1
        else:
            # 找波谷：从高点向下找最低点
            min_val = prices[last_extreme_idx]
            min_idx = last_extreme_idx
            while i < len(prices):
                if prices[i] < min_val:
                    change_from_last = (min_val - prices[i]) / min_val * 100 if min_val != 0 else 0
                    if change_from_last >= threshold:
                        min_val = prices[i]
                        min_idx = i
                    elif prices[i] > min_val * (1 + threshold / 100):
                        # 反转超过阈值，确认波谷
                        troughs.append(min_idx)
                        last_extreme_type = 'trough'
                        last_extreme_idx = min_idx
                        break
                elif prices[i] > min_val:
                    if (prices[i] - min_val) / min_val * 100 >= threshold:
                        # 反转超过阈值，确认波谷
                        troughs.append(min_idx)
                        last_extreme_type = 'trough'
                        last_extreme_idx = i
                        break
                i += 1

        i += 1

    return peaks, troughs

def check_support_level(stock_code, conn):
    """检查跌到支撑位：回踩确认 + 波浪分析"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取200根周K线
        cursor.execute("""
            SELECT date, close, high, low
            FROM stock_kline
            WHERE code = %s AND period = 'weekly'
            ORDER BY date DESC
            LIMIT 200
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 100:
            return False

        # 反转数据（从早到晚排序）
        klines = list(reversed(klines))

        # 提取数据
        closes = [float(k['close']) for k in klines]
        highs = [float(k['high']) for k in klines]
        lows = [float(k['low']) for k in klines]

        current_price = closes[-1]
        if current_price <= 0:
            return False

        # 1. ZigZag算法找波峰和波谷
        peaks, troughs = find_zigzag_peaks_troughs(highs, lows, threshold=5)

        if len(peaks) < 2 or len(troughs) < 1:
            return False

        # 2. 找到前一个波谷（比当前低）
        current_idx = len(closes) - 1
        prev_trough = None
        for t in reversed(troughs):
            if t < current_idx:
                prev_trough = t
                break

        # 3. 判断当前是否处于下跌阶段
        # 下跌：从波峰回落
        is_declining = current_price < closes[-2] * 0.95 if len(closes) >= 2 else False

        # 4. 强支撑：下跌中跌到前一个波谷附近
        strong_support = False
        if prev_trough is not None and is_declining:
            trough_price = lows[prev_trough]
            if trough_price > 0:
                distance = abs(current_price - trough_price) / trough_price * 100
                strong_support = distance <= 10

        # 5. 普通支撑：接近近期低点
        import statistics
        recent_lows = sorted(lows[-50:])
        min_low = recent_lows[0]
        low_distance = (current_price - min_low) / min_low * 100 if min_low > 0 else 100

        normal_support = low_distance <= 10

        return strong_support or normal_support
    except:
        return False

def check_resistance_level(stock_code, conn):
    """检查涨到压力位：反弹遇阻 + 波浪分析"""
    try:
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取200根周K线
        cursor.execute("""
            SELECT date, close, high, low
            FROM stock_kline
            WHERE code = %s AND period = 'weekly'
            ORDER BY date DESC
            LIMIT 200
        """, (stock_code,))

        klines = cursor.fetchall()
        if len(klines) < 100:
            return False

        # 反转数据（从早到晚排序）
        klines = list(reversed(klines))

        # 提取数据
        closes = [float(k['close']) for k in klines]
        highs = [float(k['high']) for k in klines]
        lows = [float(k['low']) for k in klines]

        current_price = closes[-1]
        if current_price <= 0:
            return False

        # 1. ZigZag算法找波峰和波谷
        peaks, troughs = find_zigzag_peaks_troughs(highs, lows, threshold=5)

        if len(peaks) < 1 or len(troughs) < 2:
            return False

        # 2. 找到前一个波谷（比当前低）
        current_idx = len(closes) - 1
        prev_trough = None
        for t in reversed(troughs):
            if t < current_idx:
                prev_trough = t
                break

        # 3. 判断当前是否处于上涨/反弹阶段
        is_rising = current_price > closes[-2] * 1.05 if len(closes) >= 2 else False

        # 4. 强压力：反弹中涨到前一个波谷附近
        strong_resistance = False
        if prev_trough is not None and is_rising:
            trough_price = lows[prev_trough]
            if trough_price > 0:
                distance = abs(current_price - trough_price) / trough_price * 100
                strong_resistance = distance <= 10

        # 5. 普通压力：接近近期高点
        import statistics
        recent_highs = sorted(highs[-50:], reverse=True)
        max_high = recent_highs[0]
        high_distance = (max_high - current_price) / max_high * 100 if max_high > 0 else 100

        normal_resistance = high_distance <= 10

        return strong_resistance or normal_resistance
    except:
        return False

def check_small_cap(stock_code, price, conn):
    """检查小盘弹性：估算市值<30亿"""
    try:
        if not price or price <= 0:
            return False

        # 使用股价作为粗略估算：小盘股通常股价较低
        # 假设发行股本3亿股，价格<10元的可能是小盘
        # 这里用简化逻辑：股价<10元 且 代码以000/002/003/300开头是小盘
        if stock_code and price < 10:
            # 000/002/003/300 开头的多为中小盘
            prefix = stock_code[:3]
            if prefix in ['000', '002', '003', '300']:
                return True
        return False
    except:
        return False

def check_high_dividend(stock):
    """检查高股息：使用PE分位作为代理（低PE高股息概率大）"""
    try:
        # 使用PE分位作为代理指标：PE分位<30%说明估值低，高股息概率大
        pe_percentile = stock.get('price_percentile') or 50
        return pe_percentile < 30
    except:
        return False

def check_low_pb(stock_code, price):
    """检查破净：使用股价估算（低价股可能是破净）"""
    try:
        if not price or price <= 0:
            return False
        # 破净股通常股价较低（<5元）
        # 银行股/地产股等传统行业常见破净
        return price < 5
    except:
        return False

def check_sector_rotation(stock):
    """检查行业轮动：热门行业优先"""
    try:
        # 使用股票代码判断行业
        # 000/002开头多为传统行业，300开头多为科技行业
        # 根据近期市场热点，300开头科技股更有活性
        code = stock.get('code', '')
        if code.startswith('300'):
            return True  # 科创板
        if code.startswith('688'):
            return True  # 创业板
        return False
    except:
        return False

def check_small_cap_simple(stock_code, price):
    """检查小盘弹性：股价<10元"""
    try:
        if not price or price <= 0:
            return False
        return price < 10
    except:
        return False

@app.route('/api/v1/stock/<stock_code>', methods=['GET'])
def get_stock_detail(stock_code):
    """获取个股详情"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # 获取基本信息
        cursor.execute("SELECT * FROM stocks WHERE code = %s", (stock_code,))
        stock = cursor.fetchone()

        if not stock:
            return jsonify({'code': 1, 'message': '股票不存在'})

        # 获取分析数据
        cursor.execute("SELECT * FROM stock_analysis WHERE code = %s ORDER BY created_at DESC LIMIT 1", (stock_code,))
        analysis = cursor.fetchone()

        result = {
            'code': stock['code'],
            'name': stock['name'],
            'price': float(stock['price']) if stock.get('price') else 0,
            'change_pct': float(stock['change_pct']) if stock.get('change_pct') else 0,
            'selected_at': stock['selected_at'].strftime('%Y-%m-%d') if stock.get('selected_at') else ''
        }

        if analysis:
            result['holders_trend'] = analysis.get('holders_trend', '[]')
            result['change_5y'] = analysis.get('change_5y', 0)
            result['price_percentile'] = analysis.get('price_percentile', 50)
            result['chip_concentration'] = analysis.get('chip_concentration', 0.5)
            result['macd_divergence'] = analysis.get('macd_divergence', '{}')
            result['sector'] = analysis.get('sector', '')  # 所属行业板块
            result['roe'] = analysis.get('roe', '')
            result['revenue'] = analysis.get('revenue', '')
            result['book_value_per_share'] = analysis.get('book_value_per_share', '')
            result['financial_updated_at'] = analysis.get('financial_updated_at', '')

        # 从财务历史表获取最新数据
        cursor.execute("""
            SELECT net_profit_yoy, net_profit_qoq, report_name
            FROM stock_financial_history
            WHERE code = %s
            ORDER BY report_date DESC
            LIMIT 1
        """, (stock_code,))
        fin_row = cursor.fetchone()
        if fin_row:
            result['net_profit_yoy'] = fin_row.get('net_profit_yoy', '')
            result['net_profit_qoq'] = fin_row.get('net_profit_qoq', '')

        # 支持日/周/月K线 - 返回所有数据
        periods = ['daily', 'weekly', 'monthly']
        for period in periods:
            cursor.execute(f"""
                SELECT date, open, high, low, close, volume
                FROM stock_kline
                WHERE code = %s AND period = %s
                ORDER BY date DESC
            """, (stock_code, period))
            kline_rows = cursor.fetchall()

            kline_data = []
            for row in reversed(kline_rows):
                kline_data.append({
                    'date': row['date'].strftime('%Y-%m-%d') if row.get('date') else '',
                    'open': float(row['open']) if row.get('open') else 0,
                    'high': float(row['high']) if row.get('high') else 0,
                    'low': float(row['low']) if row.get('low') else 0,
                    'close': float(row['close']) if row.get('close') else 0,
                    'volume': float(row['volume']) if row.get('volume') else 0
                })

            result[f'kline_{period}'] = kline_data

        # 兼容旧版本
        result['kline'] = result.get('kline_daily', [])

        # 实时计算趋势分析
        import sys
        sys.path.insert(0, '/root/select_stocks')
        import pandas as pd
        from analyzer import TechnicalAnalyzer
        from data_fetcher import DataFetcher
        if result.get('kline_daily'):
            df = pd.DataFrame(result['kline_daily'])
            df['close'] = pd.to_numeric(df['close'], errors='coerce')
            df['volume'] = pd.to_numeric(df['volume'], errors='coerce')
            df['high'] = pd.to_numeric(df['high'], errors='coerce')
            ta = TechnicalAnalyzer(DataFetcher())
            result['trend_analysis'] = ta.analyze_trend(df)
        else:
            result['trend_analysis'] = {'short': '未知', 'medium': '未知', 'long': '未知'}

        return jsonify({'code': 0, 'data': result})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/refresh', methods=['POST'])
def refresh_stocks():
    """手动刷新选股结果"""
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import json
    from stock_selector import StockSelector
    from data_fetcher import DataFetcher
    from analyzer import TechnicalAnalyzer

    conn = None
    cursor = None

    try:
        df = DataFetcher()
        selector = StockSelector(df)
        analyzer = TechnicalAnalyzer(df)

        # 执行选股
        selected_stocks = selector.select_stocks(limit=6000)

        if not selected_stocks:
            return jsonify({'code': 1, 'message': '选股失败'})

        conn = get_db()
        cursor = conn.cursor()

        # 使用事务保护：先删后插，失败可回滚
        try:
            cursor.execute("START TRANSACTION")
            cursor.execute("DELETE FROM stocks")
            cursor.execute("DELETE FROM stock_analysis")

            for stock in selected_stocks:
            cursor.execute("""
                INSERT INTO stocks (code, name, price, change_pct, selected_at)
                VALUES (%s, %s, %s, %s, %s)
            """, (stock['code'], stock['name'], stock['price'], stock['change_pct'], stock['selected_at']))

            # 分析每只股票
            analysis = analyzer.analyze_stock(stock['code'])
            cursor.execute("""
                INSERT INTO stock_analysis
                (code, holders_trend, change_5y, price_percentile, chip_concentration, macd_divergence, trend_analysis, price_position)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                stock['code'],
                json.dumps(analysis.get('holders_trend', [])),
                analysis.get('change_5y', 0),
                analysis.get('price_percentile', 50),
                analysis.get('chip_concentration', 0.5),
                json.dumps(analysis.get('macd_divergence', {})),
                json.dumps(analysis.get('trend_analysis', {})),
                analysis.get('price_position', 0.5)
            ))

            conn.commit()
        except:
            conn.rollback()
            raise

        # 保存历史记录
        today = datetime.now().strftime('%Y-%m-%d')
        for stock in selected_stocks:
            cursor.execute("""
                INSERT INTO stock_history (code, name, selected_at)
                VALUES (%s, %s, %s)
            """, (stock['code'], stock['name'], today))

        conn.commit()

        return jsonify({'code': 0, 'message': f'选股完成，共选出 {len(selected_stocks)} 只股票'})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/changes', methods=['GET'])
def get_stock_changes():
    """获取今日与昨日的股票变化"""
    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        today = datetime.now().strftime('%Y-%m-%d')
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

        # 获取今日选中的股票
        cursor.execute("SELECT code, name FROM stocks")
        today_stocks = {row['code']: row['name'] for row in cursor.fetchall()}

        # 获取昨日选中的股票
        cursor.execute("SELECT code, name FROM stock_history WHERE selected_at = %s", (yesterday,))
        yesterday_stocks = {row['code']: row['name'] for row in cursor.fetchall()}

        # 今日新增的股票
        new_stocks = []
        for code, name in today_stocks.items():
            if code not in yesterday_stocks:
                new_stocks.append({'code': code, 'name': name, 'type': 'new'})

        # 今日剔除的股票
        removed_stocks = []
        for code, name in yesterday_stocks.items():
            if code not in today_stocks:
                removed_stocks.append({'code': code, 'name': name, 'type': 'removed'})

        return jsonify({
            'code': 0,
            'data': {
                'date': today,
                'new': new_stocks,
                'removed': removed_stocks,
                'new_count': len(new_stocks),
                'removed_count': len(removed_stocks)
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/removed', methods=['GET'])
def get_removed_stocks():
    """获取被剔除股票的历史记录"""
    # 月份参数，如 2026-04
    month = request.args.get('month')

    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        if month:
            # 查询指定月份
            cursor.execute("""
                SELECT code, name, sector, price, change_pct, removed_at
                FROM stock_removed
                WHERE DATE_FORMAT(removed_at, '%%Y-%%m') = %s
                ORDER BY removed_at DESC, code ASC
            """, (month,))
        else:
            # 获取最近30天的剔除记录
            cursor.execute("""
                SELECT code, name, sector, price, change_pct, removed_at
                FROM stock_removed
                ORDER BY removed_at DESC, code ASC
                LIMIT 100
            """)

        rows = cursor.fetchall()

        # 按日期分组
        grouped = {}
        for row in rows:
            date = row['removed_at'].strftime('%Y-%m-%d') if row.get('removed_at') else ''
            if date not in grouped:
                grouped[date] = []
            if row.get('price'):
                row['price'] = float(row['price'])
            if row.get('change_pct'):
                row['change_pct'] = float(row['change_pct'])
            grouped[date].append(row)

        return jsonify({
            'code': 0,
            'data': grouped
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/changes/<date>', methods=['GET'])
def get_changes_by_date(date):
    """获取指定日期的变化"""
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 从stock_history获取指定日期的数据
        cursor.execute("""
            SELECT code, name FROM stock_history WHERE selected_at = %s
        """, (date,))
        stocks_on_date = {row['code']: row['name'] for row in cursor.fetchall()}

        # 获取前一天的数据（找到上一个有数据的日期）
        from datetime import datetime, timedelta
        dt = datetime.strptime(date, '%Y-%m-%d')

        # 找到上一个有数据的日期
        cursor.execute("""
            SELECT DATE_FORMAT(selected_at, '%%Y-%%m-%%d') as dt
            FROM stock_history
            WHERE selected_at < %s
            GROUP BY DATE_FORMAT(selected_at, '%%Y-%%m-%%d')
            ORDER BY MAX(selected_at) DESC
            LIMIT 1
        """, (date,))
        prev_row = cursor.fetchone()
        prev_date = prev_row['dt'] if prev_row else None

        prev_stocks = {}
        if prev_date:
            cursor.execute("""
                SELECT code, name FROM stock_history WHERE selected_at = %s
            """, (prev_date,))
            prev_stocks = {row['code']: row['name'] for row in cursor.fetchall()}

        # 今日新增（今日有，之前没有）
        new_stocks = []
        for code, name in stocks_on_date.items():
            if code not in prev_stocks:
                # 尝试获取sector信息
                cursor.execute("SELECT sector, price, change_pct FROM stocks WHERE code = %s", (code,))
                stock_info = cursor.fetchone()
                sector = stock_info['sector'] if stock_info else ''
                price = float(stock_info['price']) if stock_info and stock_info.get('price') else None
                change_pct = float(stock_info['change_pct']) if stock_info and stock_info.get('change_pct') else None
                new_stocks.append({
                    'code': code,
                    'name': name,
                    'type': 'new',
                    'sector': sector or '',
                    'price': price,
                    'change_pct': change_pct
                })

        # 今日剔除（之前有，今日没有）
        removed_stocks = []
        for code, name in prev_stocks.items():
            if code not in stocks_on_date:
                # 从stock_removed获取剔除时的信息
                cursor.execute("""
                    SELECT sector, price, change_pct FROM stock_removed
                    WHERE code = %s AND removed_at = %s
                """, (code, date))
                removed_info = cursor.fetchone()
                sector = removed_info['sector'] if removed_info else ''
                price = float(removed_info['price']) if removed_info and removed_info.get('price') else None
                change_pct = float(removed_info['change_pct']) if removed_info and removed_info.get('change_pct') else None
                removed_stocks.append({
                    'code': code,
                    'name': name,
                    'type': 'removed',
                    'sector': sector or '',
                    'price': price,
                    'change_pct': change_pct
                })

        # 如果前一天没有数据（可能是第一天），则全部算新增
        if not prev_stocks:
            new_stocks = []
            for code, name in stocks_on_date.items():
                cursor.execute("SELECT sector, price, change_pct FROM stocks WHERE code = %s", (code,))
                stock_info = cursor.fetchone()
                sector = stock_info['sector'] if stock_info else ''
                price = float(stock_info['price']) if stock_info and stock_info.get('price') else None
                change_pct = float(stock_info['change_pct']) if stock_info and stock_info.get('change_pct') else None
                new_stocks.append({
                    'code': code,
                    'name': name,
                    'type': 'new',
                    'sector': sector or '',
                    'price': price,
                    'change_pct': change_pct
                })
            removed_stocks = []

        return jsonify({
            'code': 0,
            'data': {
                'date': date,
                'new': new_stocks,
                'removed': removed_stocks,
                'new_count': len(new_stocks),
                'removed_count': len(removed_stocks)
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/changes/month/<year_month>', methods=['GET'])
def get_changes_by_month(year_month):
    """获取指定月份的变化汇总"""
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取该月所有有数据的日期
        cursor.execute("""
            SELECT DISTINCT DATE_FORMAT(selected_at, '%%Y-%%m-%%d') as dt
            FROM stock_history
            WHERE DATE_FORMAT(selected_at, '%%Y-%%m') = %s
            ORDER BY dt
        """, (year_month,))
        dates = [row['dt'] for row in cursor.fetchall()]

        # 获取该月被剔除的股票
        cursor.execute("""
            SELECT code, name, sector, price, change_pct, removed_at
            FROM stock_removed
            WHERE DATE_FORMAT(removed_at, '%%Y-%%m') = %s
            ORDER BY removed_at DESC
        """, (year_month,))
        removed_rows = cursor.fetchall()

        removed_by_date = {}
        for row in removed_rows:
            date = row['removed_at'].strftime('%Y-%m-%d') if row.get('removed_at') else ''
            if date not in removed_by_date:
                removed_by_date[date] = []
            if row.get('price'):
                row['price'] = float(row['price'])
            if row.get('change_pct'):
                row['change_pct'] = float(row['change_pct'])
            removed_by_date[date].append(row)

        return jsonify({
            'code': 0,
            'data': {
                'month': year_month,
                'dates': dates,
                'removed': removed_by_date
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/refresh_analysis', methods=['POST'])
def refresh_analysis():
    """只刷新现有股票的分析数据，不重新选股"""
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import json
    from data_fetcher import DataFetcher
    from analyzer import TechnicalAnalyzer

    conn = None
    cursor = None

    try:
        df = DataFetcher()
        analyzer = TechnicalAnalyzer(df)

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取所有现有股票
        cursor.execute("SELECT code FROM stocks")
        stocks = cursor.fetchall()

        if not stocks:
            return jsonify({'code': 1, 'message': '没有现有股票数据'})

        updated = 0
        for stock in stocks:
            code = stock['code']
            print(f"[刷新分析] {code}")

            # 分析每只股票
            try:
                analysis = analyzer.analyze_stock(code)

                # 更新分析数据
                cursor.execute("""
                    UPDATE stock_analysis SET
                        holders_trend = %s,
                        change_5y = %s,
                        price_percentile = %s,
                        chip_concentration = %s,
                        macd_divergence = %s,
                        trend_analysis = %s,
                        price_position = %s
                    WHERE code = %s
                """, (
                    json.dumps(analysis.get('holders_trend', [])),
                    analysis.get('change_5y', 0),
                    analysis.get('price_percentile', 50),
                    analysis.get('chip_concentration', 0.5),
                    json.dumps(analysis.get('macd_divergence', {})),
                    json.dumps(analysis.get('trend_analysis', {})),
                    analysis.get('price_position', 0.5),
                    code
                ))
                updated += 1
            except Exception as e:
                print(f"[刷新分析] {code} 失败: {e}")
                continue

        conn.commit()

        return jsonify({'code': 0, 'message': f'分析刷新完成，共更新 {updated} 只股票'})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/stocks/batch', methods=['POST'])
def get_stocks_batch():
    """根据代码列表批量获取股票数据（用于自选股等场景）
    请求体: {"codes": ["000001", "300531", ...]}
    返回完整的股票卡片数据，包括分析数据
    """
    data = request.get_json() or {}
    codes = data.get('codes', [])

    if not codes:
        return jsonify({'code': 1, 'message': '缺少codes参数'})

    conn = None
    cursor = None
    try:
        import json
        from decimal import Decimal

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        placeholders = ','.join(['%s'] * len(codes))
        cursor.execute(f"""
            SELECT t.code, t.close as kline_close, t.date as kline_date,
                   n.name,
                   s.price, s.change_pct, s.sector,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position, a.roe,
                   f.net_profit_yoy, f.net_profit_qoq
            FROM (
                SELECT k.code, k.close, k.date
                FROM stock_kline k
                INNER JOIN (
                    SELECT code, MAX(date) as max_date
                    FROM stock_kline
                    WHERE code IN ({placeholders}) AND period = 'daily'
                    GROUP BY code
                ) m ON k.code = m.code AND k.date = m.max_date AND k.period = 'daily'
            ) t
            LEFT JOIN stock_names n ON CONVERT(t.code USING utf8mb4) = CONVERT(n.code USING utf8mb4)
            LEFT JOIN stocks s ON CONVERT(t.code USING utf8mb4) = CONVERT(s.code USING utf8mb4)
            LEFT JOIN stock_analysis a ON CONVERT(t.code USING utf8mb4) = CONVERT(a.code USING utf8mb4)
            LEFT JOIN (
                SELECT code, net_profit_yoy, net_profit_qoq
                FROM stock_financial_history
                WHERE (code, report_date) IN (
                    SELECT code, MAX(report_date) FROM stock_financial_history GROUP BY code
                )
            ) f ON CONVERT(t.code USING utf8mb4) = CONVERT(f.code USING utf8mb4)
        """, codes)

        rows = cursor.fetchall()
        result = {}

        for row in rows:
            code = row['code']
            price = float(row['kline_close']) if row.get('kline_close') else (float(row['price']) if row.get('price') else 0)

            change_pct = None
            if row.get('change_pct') is not None:
                try:
                    change_pct = float(row['change_pct'])
                except:
                    pass

            # 解析JSON字段
            for json_field in ['holders_trend', 'macd_divergence', 'trend_analysis']:
                if row.get(json_field):
                    try:
                        if isinstance(row[json_field], str):
                            row[json_field] = json.loads(row[json_field])
                    except:
                        row[json_field] = None
                else:
                    row[json_field] = None

            item = {
                'code': code,
                'name': row.get('name') or code,
                'price': price,
                'change_pct': change_pct,
                'sector': row.get('sector'),
                'holders_trend': row.get('holders_trend'),
                'change_5y': float(row['change_5y']) if row.get('change_5y') is not None else None,
                'price_percentile': float(row['price_percentile']) if row.get('price_percentile') is not None else None,
                'chip_concentration': float(row['chip_concentration']) if row.get('chip_concentration') is not None else None,
                'macd_divergence': row.get('macd_divergence'),
                'trend_analysis': row.get('trend_analysis'),
                'price_position': float(row['price_position']) if row.get('price_position') is not None else None,
                'roe': row.get('roe'),
                'net_profit_yoy': row.get('net_profit_yoy'),
                'net_profit_qoq': row.get('net_profit_qoq'),
            }
            result[code] = item

        # 对没查到K线的股票，尝试从stocks+analysis表获取
        missing = [c for c in codes if c not in result]
        if missing:
            m_placeholders = ','.join(['%s'] * len(missing))
            cursor.execute(f"""
                SELECT s.code, s.name, s.price, s.change_pct, s.sector,
                       a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                       a.macd_divergence, a.trend_analysis, a.price_position, a.roe,
                       f.net_profit_yoy, f.net_profit_qoq
                FROM stocks s
                LEFT JOIN stock_analysis a ON s.code = a.code
                LEFT JOIN (
                    SELECT code, net_profit_yoy, net_profit_qoq
                    FROM stock_financial_history
                    WHERE (code, report_date) IN (
                        SELECT code, MAX(report_date) FROM stock_financial_history GROUP BY code
                    )
                ) f ON s.code = f.code
                WHERE s.code IN ({m_placeholders})
            """, missing)
            for s in cursor.fetchall():
                code = s['code']
                for json_field in ['holders_trend', 'macd_divergence', 'trend_analysis']:
                    if s.get(json_field):
                        try:
                            if isinstance(s[json_field], str):
                                s[json_field] = json.loads(s[json_field])
                        except:
                            s[json_field] = None
                result[code] = {
                    'code': code,
                    'name': s.get('name') or code,
                    'price': float(s['price']) if s.get('price') else 0,
                    'change_pct': float(s['change_pct']) if s.get('change_pct') else None,
                    'sector': s.get('sector'),
                    'holders_trend': s.get('holders_trend'),
                    'change_5y': float(s['change_5y']) if s.get('change_5y') is not None else None,
                    'price_percentile': float(s['price_percentile']) if s.get('price_percentile') is not None else None,
                    'chip_concentration': float(s['chip_concentration']) if s.get('chip_concentration') is not None else None,
                    'macd_divergence': s.get('macd_divergence'),
                    'trend_analysis': s.get('trend_analysis'),
                    'price_position': float(s['price_position']) if s.get('price_position') is not None else None,
                    'roe': s.get('roe'),
                    'net_profit_yoy': s.get('net_profit_yoy'),
                    'net_profit_qoq': s.get('net_profit_qoq'),
                }

            # 还有缺失的，查stock_names（连stocks表都没有）
            still_missing = [c for c in missing if c not in result]
            if still_missing:
                sm_placeholders = ','.join(['%s'] * len(still_missing))
                cursor.execute(
                    f"SELECT code, name FROM stock_names WHERE CONVERT(code USING utf8mb4) IN ({sm_placeholders})",
                    still_missing
                )
                for n in cursor.fetchall():
                    code = n['code']
                    result[code] = {
                        'code': code, 'name': n.get('name') or code,
                        'price': 0, 'change_pct': None,
                        'sector': None, 'holders_trend': None,
                        'change_5y': None, 'price_percentile': None,
                        'chip_concentration': None, 'macd_divergence': None,
                        'trend_analysis': None, 'price_position': None,
                        'roe': None, 'net_profit_yoy': None, 'net_profit_qoq': None,
                    }

                for code in still_missing:
                    if code not in result:
                        result[code] = {
                            'code': code, 'name': code,
                            'price': 0, 'change_pct': None,
                            'sector': None, 'holders_trend': None,
                            'change_5y': None, 'price_percentile': None,
                            'chip_concentration': None, 'macd_divergence': None,
                            'trend_analysis': None, 'price_position': None,
                            'roe': None, 'net_profit_yoy': None, 'net_profit_qoq': None,
                        }

        return jsonify({'code': 0, 'data': result})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/health', methods=['GET'])
def health():
    """健康检查"""
    return jsonify({'status': 'ok', 'time': datetime.now().isoformat()})

# ============= K线数据管理接口 =============

@app.route('/api/v1/kline/init', methods=['POST'])
def kline_init():
    """初始化K线数据 - 一次性获取所有A股历史K线
    首次调用后不需要再次调用
    """
    import threading

    limit = request.args.get('limit', type=int)  # 可选：限制股票数量，用于测试

    # 在后台运行
    def run_init():
        import sys
        sys.path.insert(0, '/root/select_stocks')
        from kline_manager import init_all_kline_data
        init_all_kline_data(limit)

    threading.Thread(target=run_init, daemon=True).start()

    msg = 'K线数据初始化已开始'
    if limit:
        msg += f'（限制前{limit}只）'
    msg += '，请稍后查看进度'

    return jsonify({'code': 0, 'message': msg})

@app.route('/api/v1/kline/update', methods=['POST'])
def kline_update():
    """更新当日K线数据 - 增量更新"""
    import threading

    # 在后台运行
    def run_update():
        import sys
        sys.path.insert(0, '/root/select_stocks')
        from kline_manager import update_today_kline
        update_today_kline()

    threading.Thread(target=run_update, daemon=True).start()

    return jsonify({
        'code': 0,
        'message': 'K线数据更新已开始，请稍后查看结果'
    })

@app.route('/api/v1/kline/status', methods=['GET'])
def kline_status():
    """查看K线数据状态"""
    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 统计各周期的数据量
        cursor.execute("""
            SELECT period, COUNT(DISTINCT code) as stock_count, COUNT(*) as total_count
            FROM stock_kline
            GROUP BY period
        """)
        stats = cursor.fetchall()

        # 获取最新日期
        cursor.execute("""
            SELECT period, MAX(date) as latest_date
            FROM stock_kline
            GROUP BY period
        """)
        latest_dates = {row['period']: row['latest_date'] for row in cursor.fetchall()}

        result = {
            'total_stocks': sum(s['stock_count'] for s in stats),
            'periods': []
        }

        for s in stats:
            result['periods'].append({
                'period': s['period'],
                'stock_count': s['stock_count'],
                'data_count': s['total_count'],
                'latest_date': str(latest_dates.get(s['period'], ''))
            })

        return jsonify({'code': 0, 'data': result})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/kline/load', methods=['GET'])
def kline_load():
    """从本地数据库加载K线数据供分析使用"""
    import pandas as pd

    code = request.args.get('code')
    period = request.args.get('period', 'daily')  # daily/weekly/monthly
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')

    if not code:
        return jsonify({'code': 1, 'message': '缺少股票代码'})

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 构建查询
        query = "SELECT * FROM stock_kline WHERE code = %s AND period = %s"
        params = [code, period]

        if start_date:
            query += " AND date >= %s"
            params.append(start_date)
        if end_date:
            query += " AND date <= %s"
            params.append(end_date)

        query += " ORDER BY date"

        cursor.execute(query, params)
        rows = cursor.fetchall()

        if not rows:
            return jsonify({'code': 1, 'message': '没有K线数据'})

        # 转换为DataFrame
        df = pd.DataFrame(rows)
        df = df.drop('id', axis=1)

        return jsonify({'code': 0, 'data': df.to_dict(orient='records')})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/update_prices', methods=['POST'])
def update_prices():
    """更新实时价格 - iOS app打开时调用
    使用腾讯免费接口获取实时行情
    """
    import urllib.request
    import ssl
    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取所有股票代码
        cursor.execute("SELECT code FROM stocks")
        stocks = cursor.fetchall()

        if not stocks:
            return jsonify({'code': 0, 'message': '没有股票数据'})

        # 构建腾讯API请求
        codes = []
        for s in stocks:
            code = s['code']
            if code.startswith('6'):
                codes.append(f'sh{code}')
            else:
                codes.append(f'sz{code}')

        # 批量获取实时价格 (最多200只)
        url = f'http://qt.gtimg.cn/q={",".join(codes[:200])}'
        context = ssl._create_unverified_context()
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        response = urllib.request.urlopen(req, timeout=10, context=context)
        data = response.read().decode('gb2312', errors='ignore')

        # 解析数据
        updated = 0
        for item in data.split(';'):
            if not item.strip():
                continue
            try:
                parts = item.split('=')
                if len(parts) < 2:
                    continue
                full_code = parts[0].split('_')[-1]
                # 提取股票代码
                if full_code.startswith('sh'):
                    stock_code = full_code[2:]
                elif full_code.startswith('sz'):
                    stock_code = full_code[2:]
                else:
                    continue

                # 解析价格数据
                fields = parts[1].split('~')
                if len(fields) > 32:
                    current_price = float(fields[3]) if fields[3] else 0
                    change_pct = float(fields[32]) if fields[32] else 0  # 涨跌幅在第32位

                    if current_price > 0:
                        cursor.execute("""
                            UPDATE stocks SET price = %s, change_pct = %s WHERE code = %s
                        """, (current_price, change_pct, stock_code))
                        updated += 1
            except Exception:
                continue

        conn.commit()

        return jsonify({
            'code': 0,
            'message': f'更新成功 {updated} 只股票',
            'count': updated
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route('/api/v1/refresh_analysis_scheduled', methods=['POST'])
def refresh_analysis_scheduled():
    """定时任务：下午4点更新分析数据"""
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import json
    from data_fetcher import DataFetcher
    from analyzer import TechnicalAnalyzer

    conn = None
    cursor = None

    try:
        df = DataFetcher()
        analyzer = TechnicalAnalyzer(df)

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取所有现有股票
        cursor.execute("SELECT code FROM stocks")
        stocks = cursor.fetchall()

        if not stocks:
            return jsonify({'code': 1, 'message': '没有现有股票数据'})

        updated = 0
        for stock in stocks:
            code = stock['code']
            print(f"[定时任务] 分析 {code}")

            try:
                analysis = analyzer.analyze_stock(code)

                # 检查分析数据是否已存在
                cursor.execute("SELECT code FROM stock_analysis WHERE code = %s", (code,))
                exists = cursor.fetchone()

                if exists:
                    # 更新
                    cursor.execute("""
                        UPDATE stock_analysis SET
                            holders_trend = %s,
                            change_5y = %s,
                            price_percentile = %s,
                            chip_concentration = %s,
                            macd_divergence = %s,
                            trend_analysis = %s,
                            price_position = %s,
                            updated_at = NOW()
                        WHERE code = %s
                    """, (
                        json.dumps(analysis.get('holders_trend', [])),
                        analysis.get('change_5y', 0),
                        analysis.get('price_percentile', 50),
                        analysis.get('chip_concentration', 0.5),
                        json.dumps(analysis.get('macd_divergence', {})),
                        json.dumps(analysis.get('trend_analysis', {})),
                        analysis.get('price_position', 0.5),
                        code
                    ))
                else:
                    # 插入
                    cursor.execute("""
                        INSERT INTO stock_analysis
                        (code, holders_trend, change_5y, price_percentile, chip_concentration, macd_divergence, trend_analysis, price_position)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """, (
                        code,
                        json.dumps(analysis.get('holders_trend', [])),
                        analysis.get('change_5y', 0),
                        analysis.get('price_percentile', 50),
                        analysis.get('chip_concentration', 0.5),
                        json.dumps(analysis.get('macd_divergence', {})),
                        json.dumps(analysis.get('trend_analysis', {})),
                        analysis.get('price_position', 0.5)
                    ))
                updated += 1
            except Exception as e:
                print(f"[定时任务] {code} 失败: {e}")
                continue

        conn.commit()

        return jsonify({'code': 0, 'message': f'分析数据更新完成，共更新 {updated} 只股票'})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/financial_updates', methods=['GET'])
def get_financial_updates():
    """获取今日财务数据有更新的股票"""
    conn = None
    cursor = None
    try:
        sort_by = request.args.get('sort_by', 'net_profit_yoy')  # net_profit_yoy, net_profit_qoq
        order = request.args.get('order', 'desc')  # asc, desc

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)
        today = datetime.now().strftime('%Y-%m-%d')

        # 验证排序参数
        valid_sorts = ['net_profit_yoy', 'net_profit_qoq']
        if sort_by not in valid_sorts:
            sort_by = 'net_profit_yoy'
        if order not in ['asc', 'desc']:
            order = 'desc'

        # 从daily_financial_updates获取今日更新的数据，join获取名称
        cursor.execute(f"""
            SELECT DISTINCT d.code, n.name, d.report_date, d.report_name,
                   d.net_profit_yoy, d.net_profit_qoq, d.revenue_yoy, d.updated_date,
                   s.price, s.change_pct
            FROM daily_financial_updates d
            LEFT JOIN stock_names n ON CONVERT(d.code USING utf8mb4) = CONVERT(n.code USING utf8mb4)
            LEFT JOIN stocks s ON CONVERT(d.code USING utf8mb4) = CONVERT(s.code USING utf8mb4)
            WHERE d.updated_date = %s
            ORDER BY d.{sort_by} {order.upper()}
        """, (today,))

        rows = cursor.fetchall()
        stocks = []
        for row in rows:
            code = str(row['code'])
            # 如果有price说明在选股列表中
            has_price = row.get('price') is not None
            stock = {
                'code': code,
                'name': row['name'] or '',
                'report_date': str(row['report_date']) if row['report_date'] else '',
                'report_name': row['report_name'] or '',
                'net_profit_yoy': row['net_profit_yoy'] or '',
                'net_profit_qoq': row['net_profit_qoq'] or '',
                'revenue_yoy': row['revenue_yoy'] or '',
                'financial_updated_at': row['updated_date'].strftime('%Y-%m-%d') if row['updated_date'] else today,
                'price': float(row['price']) if row.get('price') else None,
                'change_pct': float(row['change_pct']) if row.get('change_pct') else None,
                'in_watchlist': has_price
            }
            stocks.append(stock)

        return jsonify({
            'code': 0,
            'data': {
                'date': today,
                'count': len(stocks),
                'stocks': stocks
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/financial_updates/date/<date_str>', methods=['GET'])
def get_financial_updates_by_date(date_str):
    """获取指定日期的财务更新"""
    conn = None
    cursor = None
    try:
        sort_by = request.args.get('sort_by', 'net_profit_yoy')
        order = request.args.get('order', 'desc')

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 验证日期格式
        try:
            datetime.strptime(date_str, '%Y-%m-%d')
        except:
            return jsonify({'code': 1, 'message': '日期格式错误'})

        # 验证排序参数
        valid_sorts = ['net_profit_yoy', 'net_profit_qoq']
        if sort_by not in valid_sorts:
            sort_by = 'net_profit_yoy'
        if order not in ['asc', 'desc']:
            order = 'desc'

        # 获取指定日期的数据，join获取名称
        cursor.execute(f"""
            SELECT DISTINCT d.code, n.name, d.report_date, d.report_name,
                   d.net_profit_yoy, d.net_profit_qoq, d.revenue_yoy, d.updated_date,
                   s.price, s.change_pct
            FROM daily_financial_updates d
            LEFT JOIN stock_names n ON CONVERT(d.code USING utf8mb4) = CONVERT(n.code USING utf8mb4)
            LEFT JOIN stocks s ON CONVERT(d.code USING utf8mb4) = CONVERT(s.code USING utf8mb4)
            WHERE d.updated_date = %s
            ORDER BY d.{sort_by} {order.upper()}
        """, (date_str,))

        rows = cursor.fetchall()
        stocks = []
        for row in rows:
            stock = {
                'code': row['code'],
                'name': row['name'] or '',
                'report_date': str(row['report_date']) if row['report_date'] else '',
                'report_name': row['report_name'] or '',
                'net_profit_yoy': row['net_profit_yoy'] or '',
                'net_profit_qoq': row['net_profit_qoq'] or '',
                'revenue_yoy': row['revenue_yoy'] or '',
                'financial_updated_at': row['updated_date'].strftime('%Y-%m-%d') if row['updated_date'] else date_str,
                'price': float(row['price']) if row.get('price') else None,
                'change_pct': float(row['change_pct']) if row.get('change_pct') else None
            }
            stocks.append(stock)

        return jsonify({
            'code': 0,
            'data': {
                'date': date_str,
                'count': len(stocks),
                'stocks': stocks
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/financial_updates/dates', methods=['GET'])
def get_financial_update_dates():
    """获取有财务更新的日期列表（用于日历）"""
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 获取所有有更新的日期及其数量
        cursor.execute("""
            SELECT updated_date, COUNT(*) as count
            FROM daily_financial_updates
            GROUP BY updated_date
            ORDER BY updated_date DESC
        """)

        rows = cursor.fetchall()
        dates = []
        for row in rows:
            dates.append({
                'date': row['updated_date'].strftime('%Y-%m-%d') if row['updated_date'] else '',
                'count': row['count']
            })

        return jsonify({
            'code': 0,
            'data': {
                'dates': dates,
                'total': len(dates)
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/financial_updates/month/<year_month>', methods=['GET'])
def get_financial_updates_by_month(year_month):
    """获取指定月份的财务更新"""
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 验证月份格式
        try:
            datetime.strptime(year_month + '-01', '%Y-%m-%d')
        except:
            return jsonify({'code': 1, 'message': '月份格式错误'})

        # 获取指定月份的数据
        cursor.execute("""
            SELECT updated_date, COUNT(*) as count
            FROM daily_financial_updates
            WHERE DATE_FORMAT(updated_date, '%%Y-%%m') = %s
            GROUP BY updated_date
            ORDER BY updated_date
        """, (year_month,))

        rows = cursor.fetchall()
        dates = []
        for row in rows:
            dates.append({
                'date': row['updated_date'].strftime('%Y-%m-%d') if row['updated_date'] else '',
                'count': row['count']
            })

        return jsonify({
            'code': 0,
            'data': {
                'month': year_month,
                'dates': dates
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route('/api/v1/stock/<stock_code>/financial_history', methods=['GET'])
def get_stock_financial_history(stock_code):
    """获取股票的历史财务数据（2年）"""
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # 查询最近2年的财务数据（最新的8条，然后反转顺序）
        cursor.execute("""
            SELECT report_date, report_name, quarter, net_profit_yoy, net_profit_qoq, revenue_yoy
            FROM stock_financial_history
            WHERE code = %s
            ORDER BY report_date DESC
            LIMIT 8
        """, (stock_code,))

        rows = cursor.fetchall()
        # 反转顺序（从旧到新）
        rows = list(reversed(rows))

        history = []
        for row in rows:
            report_name = row.get('report_name', '')
            # 从report_name提取季度
            quarter = extract_quarter(report_name)
            history.append({
                'report_date': row['report_date'].strftime('%Y-%m-%d') if row.get('report_date') else '',
                'report_name': report_name,
                'quarter': quarter,
                'net_profit_yoy': row.get('net_profit_yoy', ''),
                'net_profit_qoq': row.get('net_profit_qoq', ''),
                'revenue_yoy': row.get('revenue_yoy', '')
            })

        return jsonify({
            'code': 0,
            'data': {
                'code': stock_code,
                'count': len(history),
                'history': history
            }
        })

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


if __name__ == '__main__':
    # 注册定时任务（下午4点更新分析数据）
    from datetime import datetime, timedelta
    import threading
    import time

    def run_scheduled_task():
        """下午4点执行分析数据更新"""
        while True:
            now = datetime.now()
            if now.hour == 16 and now.minute == 0:
                print("[定时任务] 开始执行分析数据更新...")
                try:
                    with app.test_request_context():
                        result = refresh_analysis_scheduled()
                        print("[定时任务] 完成:", result.get_data(as_text=True))
                except Exception as e:
                    print(f"[定时任务] 失败: {e}")
                    import traceback
                    traceback.print_exc()
            time.sleep(60)

    # 启动定时任务检查（在后台线程）
    threading.Thread(target=run_scheduled_task, daemon=True).start()

    app.run(host='0.0.0.0', port=5000, debug=True)