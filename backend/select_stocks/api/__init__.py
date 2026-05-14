#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API接口模块
"""

from flask import Flask, jsonify, request
import pymysql
import os
import traceback
import logging
from datetime import datetime, timedelta
from functools import wraps
from collections import defaultdict

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.FileHandler('/root/select_stocks/api.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('api')

app = Flask(__name__)

# API Key 鉴权（从环境变量读取，未设置则使用默认值）
API_KEY = os.environ.get('API_KEY', 'select-stocks-2024')

def require_api_key(f):
    """API Key 鉴权装饰器"""
    @wraps(f)
    def decorated(*args, **kwargs):
        key = request.headers.get('X-API-Key') or request.args.get('api_key')
        if key != API_KEY:
            logger.warning(f"鉴权失败: {request.path} from {request.remote_addr}")
            return jsonify({'code': 403, 'message': '未授权访问'}), 403
        return f(*args, **kwargs)
    return decorated

# 数据库配置（密码从环境变量读取，未设置则使用空密码）
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),
    'database': os.environ.get('DB_NAME', 'select_stocks'),
    'charset': 'utf8mb4',
    'connect_timeout': 10,
    'read_timeout': 30,
    'autocommit': True
}

# 生产环境建议使用 DBUtils 连接池替代每次新建连接:
#   pip install DBUtils
#   from dbutils.pooled_db import PooledDB
#   pool = PooledDB(pymysql, mincached=2, maxcached=10, maxconnections=20, **DB_CONFIG)
#   def get_db():
#       return pool.connection()

def get_db():
    """获取数据库连接（带重试）"""
    import time
    for attempt in range(3):
        try:
            return pymysql.connect(**DB_CONFIG)
        except pymysql.Error as e:
            if attempt < 2:
                logger.warning(f"数据库连接失败(尝试 {attempt+1}/3): {e}")
                time.sleep(1)
            else:
                raise

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
@require_api_key
def get_stocks():
    """获取选股列表"""
    page = request.args.get('page', 1, type=int)
    page_size = request.args.get('page_size', 50, type=int)
    selection_type = request.args.get('type', 'standard', type=str)
    if selection_type not in ('standard', 'new_rule'):
        selection_type = 'standard'
    offset = (page - 1) * page_size

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # Count total before pagination
        cursor.execute("SELECT COUNT(*) as cnt FROM stocks s WHERE s.selection_type = %s", (selection_type,))
        total_count = cursor.fetchone()['cnt']

        cursor.execute("""
            SELECT s.code, s.name, s.price, s.change_pct, s.selected_at, s.sector,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position,
                   f.net_profit_yoy, f.net_profit_qoq, a.roe,
                   a.revenue, a.book_value_per_share,
                   a.total_market_cap, a.dividend_count,
                    a.other_receivables_ratio, a.fund_embezzlement_risk,
                    a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk
            FROM stocks s
            LEFT JOIN stock_analysis a ON s.code = a.code
            LEFT JOIN (
                SELECT h.code, h.net_profit_yoy, h.net_profit_qoq
                FROM stock_financial_history h
                INNER JOIN (
                    SELECT code, MAX(report_date) as max_date
                    FROM stock_financial_history
                    WHERE code IN (SELECT code FROM stocks WHERE selection_type = %s)
                    GROUP BY code
                ) m ON h.code = m.code AND h.report_date = m.max_date
            ) f ON s.code = f.code
            WHERE s.selection_type = %s
            ORDER BY s.selected_at DESC
            LIMIT %s OFFSET %s
        """, (selection_type, selection_type, page_size, offset))

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
            for num_field in ['price', 'change_pct', 'change_5y', 'price_percentile', 'chip_concentration', 'price_position', 'book_value_per_share', 'total_market_cap', 'dividend_count', 'other_receivables_ratio', 'fund_embezzlement_risk', 'financial_fraud_risk']:
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

        # 附加概念板块和大涨原因
        stock_codes = [row['code'] for row in result]
        if stock_codes:
            placeholders = ','.join(['%s'] * len(stock_codes))
            concept_map = defaultdict(list)
            cursor.execute(f"""
                SELECT code, concept_name FROM stock_concepts
                WHERE code IN ({placeholders}) AND is_active = 1
                ORDER BY code, concept_name
            """, stock_codes)
            for cr in cursor.fetchall():
                concept_map[cr['code']].append(cr['concept_name'])

            # 获取最新概念涨跌数据用于大涨原因推断（兜底：如今天未加载则用最近可用日期）
            perf_map = {}
            cursor.execute("""
                SELECT concept_name, change_pct FROM daily_concept_performance
                WHERE trade_date = (SELECT MAX(trade_date) FROM daily_concept_performance)
            """)
            for pr in cursor.fetchall():
                perf_map[pr['concept_name']] = float(pr['change_pct']) if pr['change_pct'] else 0

            for row in result:
                code = row['code']
                concepts = concept_map.get(code, [])
                c_pct = row.get('change_pct', 0) or 0
                c_pct_f = float(c_pct) if c_pct else 0

                # 大涨原因: 找该股票所属概念中今日涨幅最高的
                surge_reason = None
                surge_concept = None
                top_concepts = concepts[:5]
                if c_pct_f >= 5.0 and concepts:
                    best_concept = None
                    best_pct = 0
                    for c in concepts:
                        cp = perf_map.get(c, -999)
                        if cp > best_pct:
                            best_pct = cp
                            best_concept = c
                    if best_concept and best_pct > 0:
                        surge_concept = best_concept
                        if c_pct_f >= 9.9:
                            surge_reason = f"{surge_concept}领涨+{best_pct:.1f}%"
                        elif c_pct_f >= 7.0:
                            surge_reason = f"{surge_concept}驱动+{best_pct:.1f}%"
                        else:
                            surge_reason = f"{surge_concept}走强+{best_pct:.1f}%"
                        # 将驱动概念排到第一位
                        if surge_concept in top_concepts:
                            top_concepts.remove(surge_concept)
                        top_concepts = [surge_concept] + top_concepts[:4]

                row['concepts'] = top_concepts
                row['surge_reason'] = surge_reason
                row['surge_concept'] = surge_concept

        return jsonify({'code': 0, 'data': result, 'total': total_count})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/filter', methods=['POST'])
@require_api_key
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
            SELECT s.code, s.name, s.price, s.change_pct, s.selected_at, s.sector,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position,
                   a.roe, a.net_profit_yoy, a.net_profit_qoq,
                   a.revenue, a.book_value_per_share,
                   a.total_market_cap, a.dividend_count,
                   a.other_receivables_ratio, a.fund_embezzlement_risk,
                   a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk
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
            for field in ['price', 'change_pct', 'change_5y', 'price_percentile', 'chip_concentration', 'price_position', 'book_value_per_share', 'total_market_cap', 'dividend_count', 'other_receivables_ratio', 'fund_embezzlement_risk', 'financial_fraud_risk', 'rd_ratio', 'debt_ratio', 'operating_cash_flow']:
                if stock.get(field) is not None:
                    try:
                        stock[field] = float(stock[field])
                    except:
                        stock[field] = None

            processed_stocks.append(stock)

        # 应用筛选条件（传入数据库连接）
        filtered = apply_filters(processed_stocks, filters, conn)

        # 附加概念板块和大涨原因
        if filtered:
            stock_codes = [s['code'] for s in filtered]
            placeholders = ','.join(['%s'] * len(stock_codes))
            concept_map = defaultdict(list)
            cursor.execute(f"""
                SELECT code, concept_name FROM stock_concepts
                WHERE code IN ({placeholders}) AND is_active = 1
                ORDER BY code, concept_name
            """, stock_codes)
            for cr in cursor.fetchall():
                concept_map[cr['code']].append(cr['concept_name'])

            perf_map = {}
            cursor.execute("""
                SELECT concept_name, change_pct FROM daily_concept_performance
                WHERE trade_date = (SELECT MAX(trade_date) FROM daily_concept_performance)
            """)
            for pr in cursor.fetchall():
                perf_map[pr['concept_name']] = float(pr['change_pct']) if pr['change_pct'] else 0

            for s in filtered:
                code = s['code']
                concepts = concept_map.get(code, [])
                c_pct = s.get('change_pct', 0) or 0
                c_pct_f = float(c_pct) if c_pct else 0

                surge_reason = None
                surge_concept = None
                top_concepts = concepts[:5]
                if c_pct_f >= 5.0 and concepts:
                    best_concept = None
                    best_pct = 0
                    for c in concepts:
                        cp = perf_map.get(c, -999)
                        if cp > best_pct:
                            best_pct = cp
                            best_concept = c
                    if best_concept and best_pct > 0:
                        surge_concept = best_concept
                        if c_pct_f >= 9.9:
                            surge_reason = f"{surge_concept}领涨+{best_pct:.1f}%"
                        elif c_pct_f >= 7.0:
                            surge_reason = f"{surge_concept}驱动+{best_pct:.1f}%"
                        else:
                            surge_reason = f"{surge_concept}走强+{best_pct:.1f}%"
                        if surge_concept in top_concepts:
                            top_concepts.remove(surge_concept)
                        top_concepts = [surge_concept] + top_concepts[:4]

                s['concepts'] = top_concepts
                s['surge_reason'] = surge_reason
                s['surge_concept'] = surge_concept

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
@require_api_key
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

        # 获取概念板块
        cursor.execute("""
            SELECT concept_name FROM stock_concepts
            WHERE code = %s AND is_active = 1
            ORDER BY concept_name
        """, (stock_code,))
        concept_rows = cursor.fetchall()
        result['concepts'] = [r['concept_name'] for r in concept_rows]

        # 大涨原因
        c_pct = result.get('change_pct', 0) or 0
        if c_pct >= 5.0 and result['concepts']:
            today = datetime.now().strftime('%Y-%m-%d')
            concept_names = result['concepts']
            placeholders = ','.join(['%s'] * len(concept_names))
            cursor.execute(f"""
                SELECT concept_name, change_pct FROM daily_concept_performance
                WHERE concept_name IN ({placeholders}) AND trade_date = (SELECT MAX(trade_date) FROM daily_concept_performance)
                ORDER BY change_pct DESC LIMIT 1
            """, concept_names)
            top = cursor.fetchone()
            if top and top['change_pct'] and float(top['change_pct']) > 0:
                result['surge_concept'] = top['concept_name']
                sc = float(top['change_pct'])
                if c_pct >= 9.9:
                    result['surge_reason'] = f"{top['concept_name']}领涨+{sc:.1f}%"
                elif c_pct >= 7.0:
                    result['surge_reason'] = f"{top['concept_name']}驱动+{sc:.1f}%"
                else:
                    result['surge_reason'] = f"{top['concept_name']}走强+{sc:.1f}%"

        return jsonify({'code': 0, 'data': result})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/refresh', methods=['POST'])
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
            logger.info(f"[刷新分析] {code}")

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
                logger.error(f"[刷新分析] {code} 失败: {e}")
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
@require_api_key
def get_stocks_batch():
    """根据代码列表批量获取股票数据（用于自选股等场景）
    请求体: {"codes": ["000001", "300531", ...]}
    返回完整的股票卡片数据，包括分析数据
    """
    data = request.get_json() or {}
    codes = data.get('codes', [])

    if not codes:
        return jsonify({'code': 1, 'message': '缺少codes参数'})

    def _safe_float(v):
        if v is None or v == '':
            return None
        try:
            return float(v)
        except (ValueError, TypeError):
            return None

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
                   a.macd_divergence, a.trend_analysis, a.price_position, a.roe, a.sector as a_sector,
                   a.total_market_cap, a.dividend_count,
                   a.other_receivables_ratio, a.fund_embezzlement_risk,
                   a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk, a.book_value_per_share, a.revenue,
                   f.net_profit_yoy, f.net_profit_qoq, f.roe as fin_roe
            FROM (
                SELECT CONVERT(k.code USING utf8mb4) COLLATE utf8mb4_unicode_ci as code, k.close, k.date
                FROM stock_kline k
                INNER JOIN (
                    SELECT code, MAX(date) as max_date
                    FROM stock_kline
                    WHERE code IN ({placeholders}) AND period = 'daily'
                    GROUP BY code
                ) m ON k.code = m.code AND k.date = m.max_date AND k.period = 'daily'
            ) t
            LEFT JOIN stock_names n ON t.code = CONVERT(n.code USING utf8mb4) COLLATE utf8mb4_unicode_ci
            LEFT JOIN stocks s ON t.code = s.code
            LEFT JOIN stock_analysis a ON t.code = a.code
            LEFT JOIN (
                SELECT h.code, h.net_profit_yoy, h.net_profit_qoq, h.roe
                FROM stock_financial_history h
                INNER JOIN (
                    SELECT code, MAX(report_date) as max_date
                    FROM stock_financial_history
                    WHERE code IN ({placeholders})
                    GROUP BY code
                ) m ON h.code = m.code AND h.report_date = m.max_date
            ) f ON t.code = f.code
        """, codes + codes)

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
                'sector': row.get('sector') or row.get('a_sector'),
                'holders_trend': row.get('holders_trend'),
                'change_5y': _safe_float(row.get('change_5y')),
                'price_percentile': _safe_float(row.get('price_percentile')),
                'chip_concentration': _safe_float(row.get('chip_concentration')),
                'macd_divergence': row.get('macd_divergence'),
                'trend_analysis': row.get('trend_analysis'),
                'price_position': _safe_float(row.get('price_position')),
                'roe': row.get('roe') or row.get('fin_roe'),
                'net_profit_yoy': row.get('net_profit_yoy'),
                'net_profit_qoq': row.get('net_profit_qoq'),
                'total_market_cap': _safe_float(row.get('total_market_cap')),
                'dividend_count': int(row['dividend_count']) if row.get('dividend_count') not in (None, '') else None,
                'other_receivables_ratio': _safe_float(row.get('other_receivables_ratio')),
                'fund_embezzlement_risk': _safe_float(row.get('fund_embezzlement_risk')),
                'financial_fraud_risk': _safe_float(row.get('financial_fraud_risk')),
                'book_value_per_share': _safe_float(row.get('book_value_per_share')),
                'revenue': row.get('revenue'),
            }
            result[code] = item

        # 对没查到K线的股票，尝试从stocks+analysis表获取
        missing = [c for c in codes if c not in result]
        if missing:
            m_placeholders = ','.join(['%s'] * len(missing))
            cursor.execute(f"""
                SELECT s.code, s.name, s.price, s.change_pct, s.sector,
                       a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                       a.macd_divergence, a.trend_analysis, a.price_position, a.roe, a.sector as a_sector,
                       a.total_market_cap, a.dividend_count,
                       a.other_receivables_ratio, a.fund_embezzlement_risk,
                       a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk, a.book_value_per_share,
                       f.net_profit_yoy, f.net_profit_qoq, f.roe as fin_roe
                FROM stocks s
                LEFT JOIN stock_analysis a ON s.code = a.code
                LEFT JOIN (
                    SELECT h.code, h.net_profit_yoy, h.net_profit_qoq, h.roe
                    FROM stock_financial_history h
                    INNER JOIN (
                        SELECT code, MAX(report_date) as max_date
                        FROM stock_financial_history
                        WHERE code IN ({m_placeholders})
                        GROUP BY code
                    ) m ON h.code = m.code AND h.report_date = m.max_date
                ) f ON s.code = f.code
                WHERE s.code IN ({m_placeholders})
            """, missing + missing)
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
                    'sector': s.get('sector') or s.get('a_sector'),
                    'holders_trend': s.get('holders_trend'),
                    'change_5y': _safe_float(s.get('change_5y')),
                    'price_percentile': _safe_float(s.get('price_percentile')),
                    'chip_concentration': _safe_float(s.get('chip_concentration')),
                    'macd_divergence': s.get('macd_divergence'),
                    'trend_analysis': s.get('trend_analysis'),
                    'price_position': _safe_float(s.get('price_position')),
                    'roe': s.get('roe') or s.get('fin_roe'),
                    'net_profit_yoy': s.get('net_profit_yoy'),
                    'net_profit_qoq': s.get('net_profit_qoq'),
                    'total_market_cap': _safe_float(s.get('total_market_cap')),
                    'dividend_count': int(s['dividend_count']) if s.get('dividend_count') not in (None, '') else None,
                    'other_receivables_ratio': _safe_float(s.get('other_receivables_ratio')),
                    'fund_embezzlement_risk': _safe_float(s.get('fund_embezzlement_risk')),
                    'financial_fraud_risk': _safe_float(s.get('financial_fraud_risk')),
                    'book_value_per_share': _safe_float(s.get('book_value_per_share')),
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

        # ===== 补充MACD背离和板块 =====
        all_codes = list(result.keys())
        result_list = list(result.values())
        _enrich_macd_and_sector(cursor, all_codes, result_list)
        for item in result_list:
            result[item['code']] = item

        # ===== 补充概念板块和大涨原因 =====
        if all_codes:
            c_placeholders = ','.join(['%s'] * len(all_codes))
            concept_map = defaultdict(list)
            cursor.execute(f"""
                SELECT code, concept_name FROM stock_concepts
                WHERE code IN ({c_placeholders}) AND is_active = 1
                ORDER BY code, concept_name
            """, all_codes)
            for cr in cursor.fetchall():
                concept_map[cr['code']].append(cr['concept_name'])

            perf_map = {}
            cursor.execute("""
                SELECT concept_name, change_pct FROM daily_concept_performance
                WHERE trade_date = (SELECT MAX(trade_date) FROM daily_concept_performance)
            """)
            for pr in cursor.fetchall():
                perf_map[pr['concept_name']] = float(pr['change_pct']) if pr['change_pct'] else 0

            for code, item in result.items():
                concepts = concept_map.get(code, [])
                c_pct = item.get('change_pct') or 0
                c_pct_f = float(c_pct) if c_pct else 0

                surge_reason = None
                surge_concept = None
                top_concepts = concepts[:5]
                if c_pct_f >= 5.0 and concepts:
                    best_concept = None
                    best_pct = 0
                    for c in concepts:
                        cp = perf_map.get(c, -999)
                        if cp > best_pct:
                            best_pct = cp
                            best_concept = c
                    if best_concept and best_pct > 0:
                        surge_concept = best_concept
                        if c_pct_f >= 9.9:
                            surge_reason = f"{surge_concept}领涨+{best_pct:.1f}%"
                        elif c_pct_f >= 7.0:
                            surge_reason = f"{surge_concept}驱动+{best_pct:.1f}%"
                        else:
                            surge_reason = f"{surge_concept}走强+{best_pct:.1f}%"
                        if surge_concept in top_concepts:
                            top_concepts.remove(surge_concept)
                        top_concepts = [surge_concept] + top_concepts[:4]

                item['concepts'] = top_concepts
                item['surge_reason'] = surge_reason
                item['surge_concept'] = surge_concept

        # ===== 用K线数据补充缺失的分析字段 =====
        enrich_codes = [
            code for code, item in result.items()
            if item.get('change_pct') is None
            or item.get('change_5y') is None
            or item.get('price_percentile') is None
            or item.get('price_position') is None
        ]
        if enrich_codes:
            e_placeholders = ','.join(['%s'] * len(enrich_codes))

            # 计算 change_pct: 今日相对昨日的涨跌幅
            cursor.execute(f"""
                SELECT code, close,
                       LAG(close) OVER (PARTITION BY code ORDER BY date) as prev_close,
                       ROW_NUMBER() OVER (PARTITION BY code ORDER BY date DESC) as rn
                FROM stock_kline
                WHERE code IN ({e_placeholders}) AND period = 'daily'
            """, enrich_codes)
            pct_rows = [r for r in cursor.fetchall() if r['rn'] <= 2]
            pct_latest = {}
            pct_prev = {}
            for r in pct_rows:
                if r['rn'] == 1:
                    pct_latest[r['code']] = float(r['close']) if r['close'] else 0
                elif r['rn'] == 2:
                    pct_prev[r['code']] = float(r['close']) if r['close'] else 0

            for code in enrich_codes:
                if code in pct_latest and code in pct_prev and pct_prev[code] > 0:
                    item = result.get(code)
                    if item and item.get('change_pct') is None:
                        item['change_pct'] = round((pct_latest[code] - pct_prev[code]) / pct_prev[code] * 100, 2)

            # 计算 change_5y: 5年涨跌幅
            cursor.execute(f"""
                SELECT code, close,
                       ROW_NUMBER() OVER (PARTITION BY code ORDER BY date DESC) as rn_desc,
                       ROW_NUMBER() OVER (PARTITION BY code ORDER BY date ASC) as rn_asc
                FROM stock_kline
                WHERE code IN ({e_placeholders}) AND period = 'daily'
                  AND date <= DATE_SUB(CURDATE(), INTERVAL 5 YEAR)
            """, enrich_codes)
            _5y_latest = {}
            for r in cursor.fetchall():
                if r['rn_desc'] == 1:
                    _5y_latest[r['code']] = float(r['close']) if r['close'] else 0

            for code in enrich_codes:
                if code in pct_latest and code in _5y_latest and _5y_latest[code] > 0:
                    item = result.get(code)
                    if item and item.get('change_5y') is None:
                        item['change_5y'] = round((pct_latest[code] - _5y_latest[code]) / _5y_latest[code] * 100, 2)

            # 计算 price_percentile 和 price_position（基于近2年数据）
            cursor.execute(f"""
                SELECT code, close
                FROM stock_kline
                WHERE code IN ({e_placeholders}) AND period = 'daily'
                  AND date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
                ORDER BY code, date
            """, enrich_codes)
            from collections import defaultdict as dd
            code_closes = dd(list)
            for r in cursor.fetchall():
                code_closes[r['code']].append(float(r['close']) if r['close'] else 0)

            for code, closes in code_closes.items():
                if not closes or code not in pct_latest:
                    continue
                item = result.get(code)
                if not item:
                    continue
                cur_price = pct_latest[code]
                if item.get('price_percentile') is None:
                    below = sum(1 for c in closes if c < cur_price)
                    item['price_percentile'] = round(below / len(closes), 3)
                if item.get('price_position') is None:
                    mn, mx = min(closes), max(closes)
                    if mx > mn:
                        item['price_position'] = round((cur_price - mn) / (mx - mn), 3)

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
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
@require_api_key
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
            logger.info(f"[定时任务] 分析 {code}")

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
                logger.error(f"[定时任务] {code} 失败: {e}")
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
@require_api_key
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
            LEFT JOIN stocks s ON CONVERT(d.code USING utf8mb4) = s.code
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
@require_api_key
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
            LEFT JOIN stocks s ON CONVERT(d.code USING utf8mb4) = s.code
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
@require_api_key
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
@require_api_key
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
@require_api_key
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


@app.route('/api/v1/search_stocks', methods=['GET'])
@require_api_key
def search_stocks():
    """搜索全部A股股票（支持代码、名称、拼音首字母），返回完整股票卡片数据
    GET /api/v1/search_stocks?q=xxx
    返回: {code: 0, data: [{code, name, price, change_pct, ...}], total: N}
    最多返回50条
    """
    q = request.args.get('q', '').strip()
    if not q or len(q) < 1:
        return jsonify({'code': 1, 'message': '缺少搜索关键词'})

    def _safe_float(v):
        if v is None or v == '':
            return None
        try:
            return float(v)
        except (ValueError, TypeError):
            return None

    conn = None
    cursor = None
    try:
        import json
        from decimal import Decimal

        conn = get_db()
        cursor = conn.cursor(pymysql.cursors.DictCursor)

        # Step 1: 搜索匹配的股票代码、名称和拼音
        like_q = f'%{q}%'
        cursor.execute("""
            SELECT code, name FROM stock_names
            WHERE code LIKE %s OR name LIKE %s OR pinyin LIKE %s
            ORDER BY
                CASE WHEN code = %s THEN 1
                     WHEN code LIKE %s THEN 2
                     WHEN name LIKE %s THEN 3
                     WHEN pinyin LIKE %s THEN 3
                     ELSE 4 END,
                code
            LIMIT 50
        """, (like_q, like_q, like_q, q, f'{q}%', f'{q}%', f'{q}%'))
        results = list(cursor.fetchall())

        if not results:
            return jsonify({'code': 0, 'data': [], 'total': 0})

        results = results[:50]
        codes = [r['code'] for r in results]

        # Step 2: 批量获取股价、技术分析、财务数据（一次查询完成）
        placeholders = ','.join(['%s'] * len(codes))
        cursor.execute(f"""
            SELECT t.code, t.close as kline_close,
                   s.price as stocks_price, s.change_pct as stocks_change_pct, s.sector as stocks_sector,
                   a.sector as a_sector, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.price_position, a.roe, a.holders_trend, a.macd_divergence, a.trend_analysis,
                   a.total_market_cap, a.dividend_count, a.other_receivables_ratio,
                   a.fund_embezzlement_risk, a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk, a.book_value_per_share, a.revenue,
                   f.net_profit_yoy, f.net_profit_qoq, f.roe as fin_roe
            FROM (
                SELECT CONVERT(k.code USING utf8mb4) COLLATE utf8mb4_unicode_ci as code, k.close
                FROM stock_kline k
                INNER JOIN (
                    SELECT code, MAX(date) as max_date
                    FROM stock_kline
                    WHERE code IN ({placeholders}) AND period = 'daily'
                    GROUP BY code
                ) m ON k.code = m.code AND k.date = m.max_date AND k.period = 'daily'
            ) t
            LEFT JOIN stocks s ON t.code = s.code
            LEFT JOIN stock_analysis a ON t.code = a.code
            LEFT JOIN (
                SELECT h.code, h.net_profit_yoy, h.net_profit_qoq, h.roe
                FROM stock_financial_history h
                INNER JOIN (
                    SELECT code, MAX(report_date) as max_date
                    FROM stock_financial_history
                    WHERE code IN ({placeholders})
                    GROUP BY code
                ) m ON h.code = m.code AND h.report_date = m.max_date
            ) f ON t.code = f.code
        """, codes + codes)

        price_rows = cursor.fetchall()
        price_map = {}
        for row in price_rows:
            code = row['code']
            kline_close = row.get('kline_close')
            price = float(kline_close) if kline_close else (float(row['stocks_price']) if row.get('stocks_price') else 0)

            # 涨跌幅：优先从stocks表，否则后续从K线计算
            change_pct = None
            if row.get('stocks_change_pct') is not None:
                try:
                    change_pct = float(row['stocks_change_pct'])
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

            price_map[code] = {
                'price': price,
                'change_pct': change_pct,
                'sector': row.get('stocks_sector') or row.get('a_sector'),
                'change_5y': _safe_float(row.get('change_5y')),
                'price_percentile': _safe_float(row.get('price_percentile')),
                'chip_concentration': _safe_float(row.get('chip_concentration')),
                'price_position': _safe_float(row.get('price_position')),
                'roe': row.get('roe') or row.get('fin_roe'),
                'net_profit_yoy': row.get('net_profit_yoy'),
                'net_profit_qoq': row.get('net_profit_qoq'),
                'holders_trend': row.get('holders_trend'),
                'macd_divergence': row.get('macd_divergence'),
                'trend_analysis': row.get('trend_analysis'),
                'total_market_cap': _safe_float(row.get('total_market_cap')),
                'dividend_count': int(row['dividend_count']) if row.get('dividend_count') not in (None, '') else None,
                'other_receivables_ratio': _safe_float(row.get('other_receivables_ratio')),
                'fund_embezzlement_risk': _safe_float(row.get('fund_embezzlement_risk')),
                'financial_fraud_risk': _safe_float(row.get('financial_fraud_risk')),
                'book_value_per_share': _safe_float(row.get('book_value_per_share')),
                'revenue': row.get('revenue'),
            }

        # 对没有K线数据的，尝试直接从stocks表获取
        missing = [c for c in codes if c not in price_map]
        if missing:
            m_placeholders = ','.join(['%s'] * len(missing))
            cursor.execute(f"""
                SELECT s.code, s.price, s.change_pct, s.sector,
                       a.change_5y, a.price_percentile, a.chip_concentration,
                       a.price_position, a.roe, a.sector as a_sector,
                       a.holders_trend, a.macd_divergence, a.trend_analysis,
                       a.total_market_cap, a.dividend_count,
                       a.other_receivables_ratio, a.fund_embezzlement_risk,
                       a.rd_ratio, a.debt_ratio, a.operating_cash_flow, a.financial_fraud_risk, a.book_value_per_share,
                       f.net_profit_yoy, f.net_profit_qoq, f.roe as fin_roe
                FROM stocks s
                LEFT JOIN stock_analysis a ON s.code = a.code
                LEFT JOIN (
                    SELECT h.code, h.net_profit_yoy, h.net_profit_qoq, h.roe
                    FROM stock_financial_history h
                    INNER JOIN (
                        SELECT code, MAX(report_date) as max_date
                        FROM stock_financial_history
                        WHERE code IN ({m_placeholders})
                        GROUP BY code
                    ) m ON h.code = m.code AND h.report_date = m.max_date
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
                price_map[code] = {
                    'price': float(s['price']) if s.get('price') else 0,
                    'change_pct': float(s['change_pct']) if s.get('change_pct') else None,
                    'sector': s.get('sector') or s.get('a_sector'),
                    'change_5y': _safe_float(s.get('change_5y')),
                    'price_percentile': _safe_float(s.get('price_percentile')),
                    'chip_concentration': _safe_float(s.get('chip_concentration')),
                    'price_position': _safe_float(s.get('price_position')),
                    'roe': s.get('roe') or s.get('fin_roe'),
                    'net_profit_yoy': s.get('net_profit_yoy'),
                    'net_profit_qoq': s.get('net_profit_qoq'),
                    'holders_trend': s.get('holders_trend'),
                    'macd_divergence': s.get('macd_divergence'),
                    'trend_analysis': s.get('trend_analysis'),
                    'total_market_cap': _safe_float(s.get('total_market_cap')),
                    'dividend_count': int(s['dividend_count']) if s.get('dividend_count') not in (None, '') else None,
                    'other_receivables_ratio': _safe_float(s.get('other_receivables_ratio')),
                    'fund_embezzlement_risk': _safe_float(s.get('fund_embezzlement_risk')),
                    'financial_fraud_risk': _safe_float(s.get('financial_fraud_risk')),
                    'book_value_per_share': _safe_float(s.get('book_value_per_share')),
                }

        # 对没有涨跌幅的股票，从最近2条K线计算
        pct_needed = [c for c in codes if c in price_map and price_map[c].get('change_pct') is None]
        if pct_needed:
            p_placeholders = ','.join(['%s'] * len(pct_needed))
            cursor.execute(f"""
                SELECT code, close FROM (
                    SELECT code, close,
                           ROW_NUMBER() OVER (PARTITION BY code ORDER BY date DESC) as rn
                    FROM stock_kline
                    WHERE code IN ({p_placeholders}) AND period = 'daily'
                ) r WHERE r.rn <= 2
                ORDER BY code, rn
            """, pct_needed)
            prev_map = {}
            for r in cursor.fetchall():
                code = r['code']
                if code not in prev_map:
                    prev_map[code] = float(r['close']) if r['close'] else 0
                elif code in price_map:
                    cur = price_map[code].get('price', 0)
                    prev = float(r['close']) if r['close'] else 0
                    if cur > 0 and prev > 0:
                        price_map[code]['change_pct'] = round((cur - prev) / prev * 100, 2)

        # 获取概念板块和大涨原因
        concept_map = defaultdict(list)
        cursor.execute(f"""
            SELECT code, concept_name FROM stock_concepts
            WHERE code IN ({placeholders}) AND is_active = 1
            ORDER BY code, concept_name
        """, codes)
        for cr in cursor.fetchall():
            concept_map[cr['code']].append(cr['concept_name'])

        perf_map = {}
        cursor.execute("""
            SELECT concept_name, change_pct FROM daily_concept_performance
            WHERE trade_date = (SELECT MAX(trade_date) FROM daily_concept_performance)
        """)
        for pr in cursor.fetchall():
            perf_map[pr['concept_name']] = float(pr['change_pct']) if pr['change_pct'] else 0

        # 组装返回数据
        data = []
        for r in results:
            code = r['code']
            name = r['name']
            extra = price_map.get(code, {})
            concepts = concept_map.get(code, [])
            c_pct = extra.get('change_pct') or 0
            c_pct_f = float(c_pct) if c_pct else 0

            surge_reason = None
            surge_concept = None
            top_concepts = concepts[:5]
            if c_pct_f >= 5.0 and concepts:
                best_concept = None
                best_pct = 0
                for c in concepts:
                    cp = perf_map.get(c, -999)
                    if cp > best_pct:
                        best_pct = cp
                        best_concept = c
                if best_concept and best_pct > 0:
                    surge_concept = best_concept
                    if c_pct_f >= 9.9:
                        surge_reason = f"{surge_concept}领涨+{best_pct:.1f}%"
                    elif c_pct_f >= 7.0:
                        surge_reason = f"{surge_concept}驱动+{best_pct:.1f}%"
                    else:
                        surge_reason = f"{surge_concept}走强+{best_pct:.1f}%"
                    if surge_concept in top_concepts:
                        top_concepts.remove(surge_concept)
                    top_concepts = [surge_concept] + top_concepts[:4]

            data.append({
                'code': code,
                'name': name,
                'price': extra.get('price', 0),
                'change_pct': extra.get('change_pct'),
                'sector': extra.get('sector'),
                'change_5y': extra.get('change_5y'),
                'price_percentile': extra.get('price_percentile'),
                'chip_concentration': extra.get('chip_concentration'),
                'price_position': extra.get('price_position'),
                'roe': extra.get('roe'),
                'net_profit_yoy': extra.get('net_profit_yoy'),
                'net_profit_qoq': extra.get('net_profit_qoq'),
                'concepts': top_concepts,
                'surge_reason': surge_reason,
                'surge_concept': surge_concept,
                'holders_trend': extra.get('holders_trend'),
                'macd_divergence': extra.get('macd_divergence'),
                'trend_analysis': extra.get('trend_analysis'),
                'total_market_cap': extra.get('total_market_cap'),
                'dividend_count': extra.get('dividend_count'),
                'other_receivables_ratio': extra.get('other_receivables_ratio'),
                'fund_embezzlement_risk': extra.get('fund_embezzlement_risk'),
                'financial_fraud_risk': extra.get('financial_fraud_risk'),
                'book_value_per_share': extra.get('book_value_per_share'),
                'revenue': extra.get('revenue'),
            })

        return jsonify({
            'code': 0,
            'data': data,
            'total': len(data)
        })

    except Exception as e:
        logger.error(f"搜索股票失败: {e}")
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def _compute_macd_divergence(daily_closes, weekly_closes=None, monthly_closes=None):
    """从K线收盘价计算MACD底背离。
    daily_closes: 日线收盘价列表（按日期升序，至少60个）
    weekly_closes: 周线收盘价（可选）
    monthly_closes: 月线收盘价（可选）
    返回 dict: {daily: bool, weekly: bool, monthly: bool} 或 None
    """
    def ema(data, period):
        if len(data) < period:
            return None
        multiplier = 2.0 / (period + 1)
        result = [sum(data[:period]) / period]
        for price in data[period:]:
            result.append((price - result[-1]) * multiplier + result[-1])
        # 补齐开头
        padding = [result[0]] * (period - 1)
        return padding + result

    def detect_divergence(closes):
        """检测近60根K线中的底背离：价格新低但MACD柱未新低"""
        if not closes or len(closes) < 60:
            return False
        ema12 = ema(closes, 12)
        ema26 = ema(closes, 26)
        if ema12 is None or ema26 is None:
            return False
        macd_line = [e12 - e26 for e12, e26 in zip(ema12, ema26)]
        signal_line = ema(macd_line, 9)
        if signal_line is None:
            return False
        # 对齐长度
        min_len = min(len(closes), len(macd_line), len(signal_line))
        closes = closes[-min_len:]
        macd_line = macd_line[-min_len:]
        signal_line = signal_line[-min_len:]
        histogram = [m - s for m, s in zip(macd_line, signal_line)]

        lookback = min(60, len(closes))
        c = closes[-lookback:]
        h = histogram[-lookback:]

        # 找价格局部低点 (前后各2根K线)
        lows = []
        for i in range(2, len(c) - 2):
            if c[i] <= c[i-1] and c[i] <= c[i-2] and c[i] <= c[i+1] and c[i] <= c[i+2]:
                lows.append((i, c[i], h[i]))
        if len(lows) < 2:
            return False
        # 最近两个低点：价格更低但柱状图更高 → 底背离
        a, b = lows[-2], lows[-1]
        return b[1] < a[1] and b[2] > a[2]

    result = {'daily': detect_divergence(daily_closes)}
    if weekly_closes:
        result['weekly'] = detect_divergence(weekly_closes)
    if monthly_closes:
        result['monthly'] = detect_divergence(monthly_closes)
    return result


def _enrich_macd_and_sector(cursor, codes, result_list):
    """为股票列表补充MACD背离和板块数据。
    result_list: [{code, ...}, ...] 会被原地修改。
    """
    if not codes:
        return
    e_placeholders = ','.join(['%s'] * len(codes))

    # --- 取日线数据计算MACD背离 ---
    try:
        cursor.execute(f"""
            SELECT code, close, date FROM stock_kline
            WHERE code IN ({e_placeholders}) AND period = 'daily'
            ORDER BY code, date
        """, codes)
        from collections import defaultdict as dd2
        daily_map = dd2(list)
        for r in cursor.fetchall():
            daily_map[r['code']].append(float(r['close']) if r['close'] else 0)

        # 尝试取周线/月线
        weekly_map = {}
        monthly_map = {}
        try:
            cursor.execute(f"""
                SELECT code, close, date FROM stock_kline
                WHERE code IN ({e_placeholders}) AND period = 'weekly'
                ORDER BY code, date
            """, codes)
            for r in cursor.fetchall():
                weekly_map.setdefault(r['code'], []).append(float(r['close']) if r['close'] else 0)
        except:
            pass
        try:
            cursor.execute(f"""
                SELECT code, close, date FROM stock_kline
                WHERE code IN ({e_placeholders}) AND period = 'monthly'
                ORDER BY code, date
            """, codes)
            for r in cursor.fetchall():
                monthly_map.setdefault(r['code'], []).append(float(r['close']) if r['close'] else 0)
        except:
            pass

        for item in result_list:
            code = item.get('code', '')
            daily = daily_map.get(code, [])
            if len(daily) >= 60:
                macd = _compute_macd_divergence(
                    daily,
                    weekly_map.get(code),
                    monthly_map.get(code)
                )
                item['macd_divergence'] = macd
    except Exception as e:
        logger.warning(f"MACD计算失败: {e}")

    # --- 补板块（优先stock_analysis中的sector，其次从stocks表） ---
    try:
        missing_sector = [item['code'] for item in result_list if not item.get('sector')]
        if missing_sector:
            m_placeholders = ','.join(['%s'] * len(missing_sector))
            cursor.execute(f"""
                SELECT code, sector FROM stock_analysis
                WHERE code IN ({m_placeholders}) AND sector IS NOT NULL AND sector != ''
            """, missing_sector)
            sector_map = {r['code']: r['sector'] for r in cursor.fetchall()}
            for item in result_list:
                if not item.get('sector') and item['code'] in sector_map:
                    item['sector'] = sector_map[item['code']]
    except Exception as e:
        logger.warning(f"板块补充失败: {e}")


# 拼音首字母映射表（从 stock_names 自动生成，共 1419 个字符）
_PINYIN_INITIAL_MAP = {
    '一': 'y',
    '丁': 'dz',
    '七': 'q',
    '万': 'mw',
    '三': 's',
    '上': 's',
    '下': 'x',
    '不': 'bf',
    '世': 's',
    '业': 'y',
    '丛': 'c',
    '东': 'd',
    '丝': 's',
    '两': 'l',
    '严': 'y',
    '中': 'z',
    '丰': 'f',
    '临': 'l',
    '丸': 'w',
    '丹': 'd',
    '为': 'w',
    '丽': 'l',
    '乃': 'an',
    '久': 'j',
    '义': 'y',
    '之': 'z',
    '乐': 'ly',
    '乔': 'q',
    '乖': 'g',
    '九': 'j',
    '乡': 'x',
    '买': 'm',
    '乳': 'r',
    '乾': 'gq',
    '争': 'z',
    '事': 'sz',
    '二': 'e',
    '云': 'y',
    '互': 'h',
    '五': 'w',
    '井': 'j',
    '亚': 'y',
    '交': 'j',
    '亦': 'y',
    '产': 'c',
    '亨': 'hpx',
    '享': 'x',
    '京': 'j',
    '亭': 't',
    '亮': 'l',
    '人': 'r',
    '亿': 'y',
    '仁': 'r',
    '今': 'j',
    '从': 'cz',
    '仑': 'l',
    '仔': 'z',
    '仕': 's',
    '仙': 'x',
    '仟': 'q',
    '代': 'd',
    '以': 'sy',
    '仪': 'y',
    '仲': 'z',
    '件': 'jm',
    '任': 'lr',
    '份': 'bf',
    '企': 'q',
    '伊': 'y',
    '伍': 'w',
    '众': 'yz',
    '优': 'y',
    '会': 'hk',
    '伟': 'w',
    '传': 'cz',
    '伦': 'l',
    '伯': 'bm',
    '位': 'lw',
    '住': 'z',
    '佐': 'z',
    '佑': 'y',
    '体': 'bct',
    '何': 'h',
    '余': 'txy',
    '佛': 'bf',
    '作': 'z',
    '你': 'n',
    '佩': 'p',
    '佰': 'bm',
    '佳': 'j',
    '供': 'g',
    '依': 'y',
    '侨': 'q',
    '俊': 'djs',
    '保': 'b',
    '信': 'sx',
    '修': 'x',
    '倍': 'bp',
    '值': 'z',
    '健': 'j',
    '偶': 'o',
    '储': 'c',
    '催': 'c',
    '傲': 'a',
    '像': 'x',
    '儒': 'r',
    '儿': 'er',
    '元': 'y',
    '兄': 'kx',
    '充': 'c',
    '兆': 'z',
    '先': 'x',
    '光': 'g',
    '克': 'k',
    '免': 'mw',
    '兔': 'ct',
    '兖': 'y',
    '全': 'q',
    '八': 'b',
    '公': 'g',
    '六': 'l',
    '兰': 'l',
    '共': 'gh',
    '关': 'g',
    '兴': 'x',
    '兵': 'b',
    '其': 'jq',
    '具': 'j',
    '典': 'dt',
    '养': 'y',
    '冀': 'j',
    '内': 'nr',
    '冈': 'g',
    '冉': 'dnr',
    '再': 'z',
    '军': 'j',
    '农': 'n',
    '冠': 'g',
    '冢': 'z',
    '冰': 'bn',
    '冶': 'y',
    '冷': 'l',
    '净': 'cj',
    '准': 'z',
    '凌': 'l',
    '凡': 'f',
    '凤': 'f',
    '凯': 'k',
    '凰': 'h',
    '出': 'c',
    '分': 'f',
    '划': 'gh',
    '列': 'l',
    '则': 'z',
    '刚': 'g',
    '创': 'c',
    '初': 'c',
    '利': 'l',
    '制': 'z',
    '券': 'qx',
    '刻': 'k',
    '前': 'jq',
    '剑': 'j',
    '力': 'l',
    '办': 'b',
    '加': 'j',
    '务': 'w',
    '动': 'd',
    '助': 'cz',
    '励': 'l',
    '劲': 'j',
    '势': 's',
    '勃': 'b',
    '勒': 'l',
    '勘': 'k',
    '勤': 'q',
    '包': 'bfp',
    '化': 'h',
    '北': 'b',
    '匠': 'j',
    '匹': 'p',
    '医': 'y',
    '千': 'q',
    '升': 's',
    '半': 'bp',
    '华': 'h',
    '协': 'x',
    '卓': 'z',
    '南': 'n',
    '博': 'b',
    '卡': 'kq',
    '卧': 'w',
    '卫': 'w',
    '印': 'y',
    '厂': 'achy',
    '压': 'y',
    '厚': 'h',
    '原': 'y',
    '厦': 'sx',
    '厨': 'c',
    '参': 'cs',
    '叉': 'c',
    '友': 'y',
    '双': 's',
    '发': 'f',
    '变': 'b',
    '口': 'k',
    '古': 'gk',
    '只': 'z',
    '可': 'gk',
    '台': 'sty',
    '史': 's',
    '叶': 'xy',
    '号': 'hx',
    '司': 'cs',
    '合': 'gh',
    '吉': 'j',
    '吊': 'd',
    '同': 't',
    '名': 'm',
    '向': 'x',
    '君': 'j',
    '启': 'q',
    '吴': 'tw',
    '吾': 'wy',
    '呈': 'ck',
    '周': 'z',
    '味': 'mw',
    '命': 'm',
    '和': 'h',
    '咨': 'z',
    '咸': 'jx',
    '品': 'p',
    '哈': 'hst',
    '响': 'x',
    '哲': 'z',
    '唐': 't',
    '唯': 'w',
    '商': 's',
    '啤': 'p',
    '善': 's',
    '喜': 'cx',
    '喻': 'y',
    '嘉': 'j',
    '嘴': 'z',
    '器': 'q',
    '囊': 'n',
    '四': 's',
    '回': 'h',
    '因': 'y',
    '团': 'qt',
    '园': 'wy',
    '围': 'w',
    '固': 'g',
    '国': 'g',
    '图': 't',
    '圆': 'y',
    '土': 'cdt',
    '圣': 'ks',
    '在': 'z',
    '地': 'd',
    '圳': 'chqz',
    '场': 'c',
    '均': 'jy',
    '坊': 'f',
    '坐': 'z',
    '坚': 'j',
    '坛': 't',
    '坤': 'k',
    '坦': 't',
    '坪': 'p',
    '垒': 'l',
    '垦': 'ky',
    '埃': 'az',
    '城': 'c',
    '埔': 'bp',
    '域': 'y',
    '培': 'p',
    '基': 'j',
    '堂': 't',
    '塑': 's',
    '塔': 'dt',
    '塘': 't',
    '塞': 's',
    '境': 'j',
    '墙': 'q',
    '墨': 'm',
    '壕': 'h',
    '士': 's',
    '壮': 'z',
    '声': 'qs',
    '壶': 'h',
    '壹': 'y',
    '备': 'b',
    '复': 'f',
    '夏': 'jx',
    '外': 'w',
    '多': 'd',
    '夜': 'y',
    '大': 'dt',
    '天': 't',
    '太': 't',
    '夫': 'f',
    '央': 'y',
    '头': 't',
    '夷': 'y',
    '奇': 'ajqy',
    '奈': 'n',
    '奋': 'fk',
    '奔': 'bf',
    '奕': 'y',
    '奥': 'ay',
    '好': 'h',
    '如': 'r',
    '妆': 'z',
    '妙': 'm',
    '妮': 'n',
    '姆': 'm',
    '姓': 'sx',
    '姚': 'ty',
    '姿': 'z',
    '威': 'w',
    '娃': 'gw',
    '娜': 'n',
    '娱': 'y',
    '婴': 'y',
    '媒': 'm',
    '子': 'z',
    '字': 'z',
    '存': 'c',
    '孚': 'f',
    '学': 'x',
    '孩': 'h',
    '宁': 'nz',
    '宅': 'cdz',
    '宇': 'y',
    '安': 'a',
    '宋': 's',
    '完': 'kw',
    '宏': 'h',
    '宗': 'z',
    '宙': 'z',
    '宜': 'y',
    '宝': 'b',
    '实': 's',
    '宠': 'c',
    '客': 'kq',
    '宣': 'x',
    '室': 's',
    '宫': 'g',
    '家': 'gj',
    '宸': 'c',
    '容': 'ry',
    '宾': 'b',
    '宿': 'qsx',
    '密': 'm',
    '富': 'f',
    '寒': 'h',
    '寰': 'hx',
    '导': 'd',
    '寿': 's',
    '封': 'bf',
    '小': 'x',
    '尔': 'e',
    '尖': 'j',
    '尚': 'cs',
    '尤': 'y',
    '尼': 'n',
    '居': 'j',
    '展': 'z',
    '属': 'sz',
    '屯': 'tz',
    '山': 's',
    '屹': 'gy',
    '屿': 'y',
    '岛': 'd',
    '岩': 'y',
    '岭': 'l',
    '岱': 'd',
    '岳': 'y',
    '岸': 'a',
    '岹': 't',
    '峆': 'h',
    '峡': 'x',
    '峨': 'e',
    '峰': 'f',
    '崇': 'c',
    '崧': 's',
    '崴': 'w',
    '嵘': 'r',
    '巍': 'w',
    '川': 'c',
    '州': 'z',
    '工': 'g',
    '巨': 'jq',
    '巴': 'b',
    '巷': 'hx',
    '市': 'fs',
    '布': 'b',
    '帅': 's',
    '帆': 'f',
    '希': 'x',
    '帕': 'mp',
    '帝': 'd',
    '帮': 'b',
    '常': 'c',
    '干': 'ag',
    '平': 'bp',
    '年': 'n',
    '并': 'b',
    '幸': 'nx',
    '广': 'agy',
    '庄': 'pz',
    '庆': 'q',
    '床': 'c',
    '库': 'k',
    '应': 'y',
    '店': 'd',
    '府': 'f',
    '度': 'dz',
    '座': 'z',
    '庭': 't',
    '康': 'k',
    '廊': 'l',
    '延': 'y',
    '建': 'j',
    '开': 'k',
    '引': 'y',
    '弘': 'h',
    '弟': 'dt',
    '张': 'z',
    '弦': 'x',
    '强': 'jq',
    '当': 'd',
    '录': 'l',
    '形': 'x',
    '彤': 't',
    '彦': 'py',
    '彩': 'c',
    '彬': 'b',
    '影': 'y',
    '征': 'z',
    '徐': 'x',
    '徕': 'l',
    '得': 'd',
    '御': 'y',
    '微': 'w',
    '德': 'd',
    '徽': 'h',
    '心': 'x',
    '必': 'b',
    '志': 'z',
    '快': 'k',
    '态': 't',
    '思': 's',
    '怡': 'y',
    '急': 'j',
    '总': 'z',
    '恒': 'h',
    '恩': 'e',
    '恬': 't',
    '息': 'x',
    '恺': 'k',
    '悍': 'h',
    '悦': 'y',
    '惠': 'h',
    '想': 'x',
    '意': 'y',
    '感': 'gh',
    '慈': 'c',
    '慕': 'm',
    '慧': 'h',
    '憬': 'j',
    '懋': 'm',
    '戈': 'g',
    '戎': 'r',
    '成': 'c',
    '我': 'w',
    '戴': 'd',
    '户': 'h',
    '房': 'fp',
    '手': 's',
    '才': 'cz',
    '托': 't',
    '扬': 'y',
    '承': 'cz',
    '技': 'jq',
    '投': 'dt',
    '抗': 'gk',
    '抚': 'f',
    '护': 'h',
    '报': 'b',
    '拉': 'l',
    '拓': 'tz',
    '拖': 'ct',
    '招': 'qsz',
    '拜': 'b',
    '择': 'z',
    '拱': 'gj',
    '拾': 'js',
    '持': 'c',
    '指': 'z',
    '挖': 'w',
    '振': 'z',
    '据': 'j',
    '捷': 'cjq',
    '掌': 'z',
    '探': 'tx',
    '控': 'kq',
    '推': 't',
    '搏': 'b',
    '摩': 'm',
    '撒': 's',
    '播': 'b',
    '放': 'f',
    '政': 'z',
    '敏': 'm',
    '敖': 'a',
    '教': 'j',
    '敦': 'dtz',
    '数': 's',
    '敷': 'f',
    '文': 'w',
    '斋': 'z',
    '斗': 'dz',
    '料': 'l',
    '断': 'd',
    '斯': 's',
    '新': 'x',
    '方': 'fpw',
    '施': 'sy',
    '旅': 'l',
    '旋': 'x',
    '族': 'csz',
    '旗': 'q',
    '无': 'mw',
    '日': 'r',
    '旦': 'd',
    '旭': 'x',
    '时': 's',
    '旷': 'k',
    '旺': 'w',
    '昀': 'y',
    '昂': 'ay',
    '昆': 'hk',
    '昇': 's',
    '昊': 'h',
    '昌': 'c',
    '明': 'm',
    '易': 'y',
    '昕': 'x',
    '星': 'x',
    '映': 'y',
    '春': 'c',
    '昭': 'z',
    '是': 'st',
    '昱': 'y',
    '显': 'x',
    '晋': 'j',
    '晓': 'x',
    '晖': 'h',
    '晟': 'cjs',
    '晨': 'c',
    '普': 'p',
    '景': 'jy',
    '晶': 'j',
    '智': 'z',
    '曙': 's',
    '曦': 'x',
    '曲': 'q',
    '曼': 'm',
    '月': 'ry',
    '有': 'wy',
    '朋': 'p',
    '服': 'bf',
    '朔': 's',
    '朗': 'l',
    '望': 'w',
    '朝': 'cz',
    '期': 'jq',
    '木': 'm',
    '未': 'w',
    '本': 'b',
    '术': 'sz',
    '朱': 'sz',
    '朴': 'p',
    '机': 'jw',
    '杉': 's',
    '李': 'l',
    '材': 'c',
    '村': 'c',
    '来': 'l',
    '杨': 'y',
    '杭': 'hk',
    '杯': 'b',
    '杰': 'j',
    '松': 's',
    '板': 'b',
    '极': 'j',
    '构': 'g',
    '林': 'l',
    '果': 'gl',
    '枪': 'q',
    '枫': 'f',
    '架': 'j',
    '柏': 'b',
    '染': 'r',
    '柔': 'r',
    '柘': 'z',
    '柯': 'k',
    '柳': 'l',
    '柴': 'cz',
    '标': 'b',
    '树': 's',
    '栖': 'qx',
    '株': 'z',
    '核': 'ghk',
    '格': 'ghl',
    '桂': 'g',
    '桃': 'tz',
    '桐': 'dt',
    '桑': 's',
    '桥': 'q',
    '桩': 'z',
    '梅': 'm',
    '梓': 'z',
    '梦': 'm',
    '梯': 't',
    '械': 'x',
    '检': 'j',
    '棉': 'm',
    '棒': 'b',
    '棕': 'z',
    '森': 's',
    '棵': 'k',
    '椰': 'y',
    '楚': 'c',
    '楠': 'n',
    '楹': 'y',
    '楼': 'l',
    '概': 'gj',
    '榈': 'l',
    '榕': 'r',
    '榜': 'bp',
    '榨': 'z',
    '模': 'm',
    '横': 'gh',
    '橙': 'cd',
    '橡': 'x',
    '橦': 'ctz',
    '欢': 'h',
    '欣': 'x',
    '欧': 'o',
    '歌': 'g',
    '正': 'z',
    '步': 'b',
    '武': 'w',
    '殷': 'y',
    '毅': 'y',
    '母': 'mw',
    '每': 'm',
    '毓': 'y',
    '比': 'bp',
    '毕': 'b',
    '毛': 'm',
    '氏': 'jsz',
    '民': 'm',
    '气': 'q',
    '氟': 'f',
    '氧': 'y',
    '氯': 'l',
    '水': 's',
    '永': 'y',
    '汇': 'h',
    '汉': 'h',
    '江': 'j',
    '池': 'ct',
    '汤': 'st',
    '汽': 'gqy',
    '汾': 'fp',
    '沃': 'w',
    '沈': 'cst',
    '沐': 'm',
    '沙': 's',
    '沧': 'c',
    '沪': 'h',
    '河': 'h',
    '油': 'y',
    '治': 'cz',
    '沿': 'y',
    '泉': 'q',
    '泊': 'bp',
    '泓': 'h',
    '法': 'f',
    '泛': 'f',
    '波': 'b',
    '泥': 'n',
    '泰': 't',
    '泵': 'blp',
    '泸': 'l',
    '泽': 'z',
    '洁': 'j',
    '洋': 'xy',
    '洗': 'x',
    '洛': 'l',
    '津': 'j',
    '洪': 'h',
    '洲': 'z',
    '活': 'gh',
    '洽': 'hq',
    '派': 'bmp',
    '流': 'l',
    '测': 'c',
    '济': 'j',
    '浔': 'x',
    '浙': 'z',
    '浦': 'p',
    '浩': 'gh',
    '浪': 'l',
    '浴': 'y',
    '海': 'h',
    '涌': 'cy',
    '涛': 't',
    '润': 'r',
    '涪': 'fp',
    '涯': 'y',
    '液': 'sy',
    '淋': 'l',
    '淮': 'h',
    '深': 's',
    '淳': 'cz',
    '添': 't',
    '淼': 'm',
    '清': 'q',
    '渔': 'y',
    '渝': 'y',
    '渡': 'd',
    '渤': 'b',
    '渥': 'ow',
    '温': 'wy',
    '港': 'gh',
    '游': 'ly',
    '湃': 'bp',
    '湖': 'h',
    '湘': 'x',
    '湾': 'w',
    '源': 'y',
    '溢': 'y',
    '溪': 'qx',
    '溯': 's',
    '满': 'm',
    '滦': 'l',
    '滨': 'b',
    '演': 'y',
    '漫': 'm',
    '漱': 's',
    '漳': 'z',
    '潍': 'w',
    '潜': 'q',
    '潞': 'l',
    '潭': 'dtxy',
    '潮': 'c',
    '澄': 'cd',
    '澜': 'l',
    '澳': 'ay',
    '激': 'j',
    '濠': 'h',
    '濮': 'p',
    '瀚': 'h',
    '瀛': 'y',
    '灏': 'h',
    '火': 'h',
    '灵': 'l',
    '灿': 'c',
    '炀': 'y',
    '炜': 'w',
    '炬': 'j',
    '炭': 't',
    '点': 'd',
    '炼': 'l',
    '烁': 's',
    '烨': 'y',
    '热': 'r',
    '烷': 'w',
    '烽': 'f',
    '焊': 'h',
    '焦': 'jq',
    '焰': 'y',
    '然': 'r',
    '煌': 'h',
    '煜': 'y',
    '煤': 'm',
    '照': 'z',
    '熊': 'x',
    '熔': 'r',
    '熙': 'xy',
    '熟': 's',
    '熵': 's',
    '燃': 'r',
    '燕': 'y',
    '爆': 'b',
    '爱': 'a',
    '片': 'p',
    '版': 'b',
    '牌': 'p',
    '牛': 'n',
    '牡': 'm',
    '牧': 'm',
    '物': 'w',
    '特': 't',
    '狄': 'dt',
    '狮': 's',
    '狼': 'hl',
    '猫': 'm',
    '獐': 'z',
    '玄': 'x',
    '玉': 'y',
    '王': 'wy',
    '玑': 'j',
    '玛': 'm',
    '玩': 'w',
    '玮': 'w',
    '环': 'h',
    '现': 'x',
    '玲': 'l',
    '玻': 'b',
    '珀': 'p',
    '珂': 'k',
    '珈': 'j',
    '珍': 'z',
    '珑': 'l',
    '珠': 'z',
    '球': 'q',
    '理': 'l',
    '琏': 'l',
    '琚': 'j',
    '琛': 'c',
    '琪': 'q',
    '琴': 'q',
    '瑜': 'y',
    '瑞': 'r',
    '瑶': 'y',
    '璃': 'l',
    '璞': 'p',
    '璟': 'j',
    '瓦': 'w',
    '瓷': 'c',
    '甘': 'gh',
    '生': 's',
    '用': 'y',
    '甬': 'dy',
    '田': 't',
    '甲': 'j',
    '申': 's',
    '电': 'd',
    '畅': 'c',
    '界': 'j',
    '疆': 'j',
    '疗': 'l',
    '疫': 'y',
    '癀': 'h',
    '登': 'd',
    '白': 'b',
    '百': 'bm',
    '的': 'd',
    '皇': 'hw',
    '皓': 'h',
    '皖': 'hw',
    '皮': 'p',
    '盈': 'y',
    '益': 'y',
    '盐': 'y',
    '盖': 'g',
    '盘': 'p',
    '盛': 'cs',
    '盟': 'm',
    '目': 'm',
    '直': 'z',
    '相': 'x',
    '盾': 'dsy',
    '省': 'sx',
    '眉': 'm',
    '看': 'k',
    '真': 'z',
    '眼': 'wy',
    '睡': 's',
    '睦': 'm',
    '睿': 'r',
    '瞳': 't',
    '知': 'z',
    '矩': 'j',
    '石': 'ds',
    '矽': 'x',
    '矿': 'k',
    '码': 'm',
    '研': 'xy',
    '硅': 'gh',
    '硕': 's',
    '确': 'q',
    '碁': 'q',
    '碧': 'b',
    '碱': 'jx',
    '碳': 't',
    '磁': 'c',
    '磊': 'l',
    '祖': 'jz',
    '神': 's',
    '祥': 'x',
    '祯': 'z',
    '祺': 'q',
    '禄': 'l',
    '福': 'f',
    '禧': 'x',
    '禹': 'y',
    '禾': 'h',
    '秀': 'x',
    '秉': 'b',
    '秋': 'q',
    '种': 'cz',
    '科': 'k',
    '租': 'jz',
    '秦': 'q',
    '积': 'jz',
    '移': 'cy',
    '稀': 'x',
    '程': 'c',
    '税': 'st',
    '稳': 'w',
    '稽': 'jq',
    '穗': 's',
    '空': 'k',
    '窖': 'jz',
    '窗': 'c',
    '立': 'lw',
    '竞': 'j',
    '章': 'z',
    '竹': 'z',
    '笑': 'x',
    '笛': 'd',
    '第': 'd',
    '筑': 'z',
    '策': 'c',
    '简': 'j',
    '箔': 'b',
    '管': 'g',
    '箭': 'j',
    '米': 'm',
    '粉': 'f',
    '粤': 'y',
    '粮': 'l',
    '精': 'jq',
    '糖': 't',
    '素': 's',
    '索': 's',
    '紫': 'z',
    '红': 'gh',
    '纤': 'qx',
    '纪': 'j',
    '纬': 'w',
    '纯': 'c',
    '纳': 'n',
    '纵': 'z',
    '纸': 'z',
    '纺': 'f',
    '纽': 'n',
    '线': 'x',
    '绅': 's',
    '细': 'x',
    '织': 'z',
    '经': 'j',
    '绒': 'r',
    '结': 'j',
    '绘': 'h',
    '络': 'l',
    '绝': 'j',
    '统': 't',
    '继': 'j',
    '绳': 's',
    '维': 'w',
    '绸': 'c',
    '综': 'z',
    '绿': 'l',
    '缆': 'l',
    '缘': 'y',
    '网': 'w',
    '罗': 'l',
    '罡': 'g',
    '罩': 'z',
    '置': 'z',
    '羊': 'y',
    '美': 'm',
    '羚': 'l',
    '群': 'q',
    '羽': 'hy',
    '翎': 'l',
    '翔': 'x',
    '翘': 'q',
    '翠': 'c',
    '翰': 'h',
    '翱': 'a',
    '翼': 'y',
    '耀': 'y',
    '老': 'l',
    '者': 'z',
    '而': 'en',
    '耐': 'n',
    '聆': 'l',
    '联': 'l',
    '聚': 'j',
    '肃': 's',
    '肇': 'z',
    '肉': 'r',
    '股': 'g',
    '肥': 'bf',
    '肯': 'k',
    '育': 'yz',
    '胎': 't',
    '胜': 'qsx',
    '胞': 'bp',
    '胤': 'y',
    '胶': 'jx',
    '能': 'ntx',
    '脉': 'm',
    '脑': 'n',
    '腔': 'kq',
    '腾': 't',
    '腿': 't',
    '膜': 'm',
    '臣': 'c',
    '自': 'z',
    '至': 'dz',
    '致': 'z',
    '臻': 'z',
    '舍': 's',
    '舒': 'sy',
    '舜': 's',
    '舟': 'z',
    '航': 'h',
    '舶': 'b',
    '船': 'c',
    '艇': 't',
    '良': 'l',
    '色': 's',
    '艺': 'y',
    '艾': 'ay',
    '节': 'j',
    '芋': 'xy',
    '芒': 'hmw',
    '芝': 'z',
    '芦': 'hl',
    '芬': 'f',
    '芭': 'bp',
    '芯': 'x',
    '花': 'h',
    '芳': 'f',
    '芸': 'y',
    '苏': 's',
    '苑': 'y',
    '苗': 'm',
    '若': 'r',
    '英': 'y',
    '茂': 'm',
    '范': 'f',
    '茅': 'm',
    '茗': 'm',
    '茵': 'y',
    '茶': 'c',
    '荃': 'cq',
    '荆': 'j',
    '草': 'cz',
    '荒': 'hk',
    '荣': 'r',
    '药': 'y',
    '荻': 'd',
    '莆': 'fp',
    '莎': 's',
    '莞': 'gw',
    '莫': 'm',
    '莱': 'l',
    '莲': 'l',
    '菌': 'j',
    '菜': 'c',
    '菱': 'l',
    '菲': 'f',
    '萃': 'c',
    '萤': 'y',
    '萧': 'x',
    '萱': 'x',
    '葆': 'b',
    '葡': 'bp',
    '葫': 'h',
    '葵': 'k',
    '蒂': 'd',
    '蒙': 'm',
    '蒽': 'e',
    '蓉': 'r',
    '蓝': 'l',
    '蔚': 'wy',
    '蔬': 's',
    '蕊': 'jr',
    '蕾': 'l',
    '薇': 'w',
    '藏': 'cz',
    '蘅': 'h',
    '虹': 'ghj',
    '蛇': 'csty',
    '蛋': 'd',
    '蜀': 's',
    '蜂': 'f',
    '蜓': 'dt',
    '蜻': 'jq',
    '蝶': 'dt',
    '螂': 'l',
    '融': 'r',
    '螳': 't',
    '螺': 'l',
    '蟒': 'm',
    '蟠': 'fp',
    '蠡': 'l',
    '血': 'x',
    '行': 'hx',
    '衍': 'y',
    '街': 'j',
    '衡': 'h',
    '衢': 'q',
    '表': 'b',
    '装': 'z',
    '裕': 'y',
    '襄': 'x',
    '西': 'x',
    '观': 'g',
    '规': 'g',
    '觅': 'm',
    '视': 's',
    '觉': 'j',
    '角': 'gjl',
    '解': 'jx',
    '触': 'c',
    '誉': 'y',
    '计': 'j',
    '认': 'r',
    '讯': 'x',
    '记': 'j',
    '许': 'hx',
    '设': 's',
    '证': 'z',
    '识': 'sz',
    '诊': 'z',
    '试': 's',
    '诚': 'c',
    '询': 'x',
    '语': 'y',
    '诺': 'n',
    '读': 'd',
    '调': 'dt',
    '谊': 'y',
    '谐': 'x',
    '谱': 'p',
    '谷': 'gly',
    '豆': 'd',
    '象': 'x',
    '豪': 'h',
    '豫': 'sxy',
    '贝': 'b',
    '贡': 'g',
    '财': 'c',
    '贤': 'x',
    '货': 'h',
    '质': 'z',
    '购': 'g',
    '贵': 'g',
    '贸': 'm',
    '贺': 'h',
    '赁': 'l',
    '资': 'z',
    '赋': 'f',
    '赐': 'c',
    '赛': 's',
    '赞': 'z',
    '赢': 'y',
    '赣': 'g',
    '赤': 'c',
    '赫': 'hs',
    '起': 'q',
    '超': 'ct',
    '越': 'hy',
    '趋': 'q',
    '趣': 'cqz',
    '跃': 'y',
    '跨': 'k',
    '路': 'l',
    '车': 'cj',
    '轨': 'g',
    '轩': 'x',
    '轮': 'l',
    '软': 'r',
    '轴': 'z',
    '轻': 'q',
    '载': 'z',
    '辅': 'f',
    '辆': 'l',
    '辉': 'h',
    '辐': 'f',
    '辰': 'c',
    '辽': 'l',
    '达': 'dt',
    '迁': 'q',
    '迅': 'x',
    '迈': 'm',
    '迎': 'y',
    '运': 'y',
    '近': 'j',
    '返': 'f',
    '进': 'j',
    '远': 'y',
    '连': 'l',
    '迦': 'jx',
    '迪': 'd',
    '透': 'st',
    '递': 'd',
    '通': 't',
    '速': 's',
    '造': 'cz',
    '逸': 'y',
    '道': 'd',
    '遥': 'y',
    '邑': 'ey',
    '邦': 'b',
    '邮': 'y',
    '邵': 's',
    '郎': 'l',
    '郑': 'z',
    '部': 'bp',
    '郴': 'cl',
    '都': 'd',
    '鄂': 'e',
    '酉': 'y',
    '配': 'p',
    '酒': 'j',
    '酵': 'j',
    '酷': 'k',
    '醋': 'cz',
    '采': 'c',
    '里': 'l',
    '重': 'ctz',
    '野': 'sy',
    '量': 'l',
    '金': 'j',
    '鑫': 'x',
    '针': 'z',
    '钒': 'f',
    '钛': 't',
    '钜': 'j',
    '钟': 'z',
    '钠': 'n',
    '钢': 'g',
    '钦': 'q',
    '钧': 'j',
    '钨': 'w',
    '钰': 'y',
    '钱': 'q',
    '钴': 'g',
    '钻': 'z',
    '钼': 'm',
    '钽': 't',
    '钾': 'j',
    '铀': 'y',
    '铁': 't',
    '铂': 'b',
    '铃': 'l',
    '铅': 'qy',
    '铖': 'c',
    '铜': 't',
    '铝': 'l',
    '铭': 'm',
    '银': 'y',
    '铸': 'z',
    '铺': 'p',
    '链': 'l',
    '销': 'x',
    '锁': 's',
    '锂': 'l',
    '锅': 'g',
    '锆': 'g',
    '锈': 'x',
    '锋': 'f',
    '锌': 'x',
    '锐': 'r',
    '锗': 'z',
    '锚': 'm',
    '锝': 'd',
    '锡': 'x',
    '锦': 'j',
    '键': 'j',
    '锴': 'k',
    '锻': 'd',
    '镁': 'm',
    '镇': 'z',
    '镜': 'j',
    '镭': 'l',
    '长': 'cz',
    '门': 'm',
    '闰': 'r',
    '闻': 'w',
    '闽': 'm',
    '阀': 'f',
    '阅': 'y',
    '防': 'f',
    '阳': 'y',
    '阴': 'y',
    '阵': 'z',
    '阿': 'ae',
    '际': 'j',
    '陆': 'l',
    '陇': 'l',
    '陕': 's',
    '院': 'y',
    '险': 'x',
    '陵': 'l',
    '隅': 'y',
    '隆': 'l',
    '隧': 'sz',
    '雁': 'y',
    '雄': 'x',
    '雅': 'y',
    '集': 'j',
    '雕': 'd',
    '雨': 'y',
    '雪': 'x',
    '零': 'l',
    '雷': 'l',
    '霄': 'x',
    '震': 'sz',
    '霍': 'hs',
    '霖': 'l',
    '霞': 'x',
    '露': 'l',
    '霸': 'bp',
    '青': 'jq',
    '靠': 'k',
    '面': 'm',
    '鞍': 'a',
    '韩': 'h',
    '韬': 't',
    '音': 'y',
    '韵': 'y',
    '韶': 's',
    '顶': 'd',
    '顺': 's',
    '顾': 'g',
    '顿': 'd',
    '颀': 'q',
    '领': 'l',
    '频': 'p',
    '颖': 'y',
    '风': 'f',
    '飘': 'p',
    '飞': 'f',
    '食': 'sy',
    '饭': 'f',
    '饮': 'y',
    '饰': 's',
    '饲': 's',
    '首': 's',
    '香': 'x',
    '馨': 'x',
    '马': 'm',
    '驰': 'c',
    '驱': 'q',
    '驼': 't',
    '驾': 'j',
    '骄': 'j',
    '骆': 'l',
    '验': 'y',
    '骏': 'j',
    '骐': 'q',
    '骑': 'q',
    '骨': 'g',
    '高': 'g',
    '鬼': 'g',
    '魂': 'h',
    '魅': 'm',
    '魔': 'm',
    '鱼': 'y',
    '鲁': 'l',
    '鲍': 'b',
    '鳌': 'a',
    '鸟': 'dn',
    '鸡': 'j',
    '鸣': 'm',
    '鸥': 'o',
    '鸽': 'g',
    '鸿': 'h',
    '鹄': 'gh',
    '鹅': 'e',
    '鹏': 'p',
    '鹞': 'y',
    '鹤': 'h',
    '鹭': 'l',
    '鹰': 'y',
    '鹿': 'l',
    '麒': 'q',
    '麟': 'l',
    '麦': 'm',
    '麻': 'm',
    '麾': 'h',
    '黄': 'h',
    '黎': 'l',
    '黑': 'h',
    '黔': 'q',
    '默': 'm',
    '黛': 'd',
    '鼎': 'dz',
    '鼓': 'g',
    '鼠': 's',
    '齐': 'jq',
    '齿': 'c',
    '龄': 'l',
    '龙': 'l'
}


def _pinyin_initials(name):
    """获取股票名称的所有可能拼音首字母组合"""
    result_list = ['']
    for ch in name:
        if 'A' <= ch <= 'Z' or 'a' <= ch <= 'z' or '0' <= ch <= '9':
            result_list = [r + ch.lower() for r in result_list]
        else:
            initials = _PINYIN_INITIAL_MAP.get(ch, '')
            if not initials:
                result_list = [r + '_' for r in result_list]
            else:
                new_list = []
                for r in result_list:
                    for c in initials:
                        new_list.append(r + c)
                result_list = new_list
    return list(set(result_list))


def _pinyin_match(query, name):
    """检查query是否匹配name的任意拼音首字母组合"""
    variants = _pinyin_initials(name)
    query_lower = query.lower()
    for v in variants:
        if query_lower in v:
            return True
    return False


if __name__ == '__main__':
    # 注意：定时任务已由 scheduler_manager.py 的 APScheduler 统一管理（每日16:00执行）
    # 此处不再启动重复的线程，避免任务被执行两次

    # 生产环境应使用 gunicorn 替代 Flask dev server:
    #   gunicorn -w 4 -b 0.0.0.0:5000 api:app
    # 开发环境:
    #   python api/__init__.py
    app.run(host='0.0.0.0', port=5000, debug=False)