#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API接口模块
"""

from flask import Flask, jsonify, request
import pymysql
from datetime import datetime, timedelta

app = Flask(__name__)

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
            SELECT s.code, s.name, s.price, s.change_pct, s.selected_at,
                   a.holders_trend, a.change_5y, a.price_percentile, a.chip_concentration,
                   a.macd_divergence, a.trend_analysis, a.price_position,
                   a.net_profit_yoy, a.net_profit_qoq, a.roe
            FROM stocks s
            LEFT JOIN stock_analysis a ON s.code = a.code
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
            if row.get('price'):
                try:
                    val = row['price']
                    if isinstance(val, (int, float, Decimal)):
                        row['price'] = float(val)
                    elif val and val != 'None':
                        row['price'] = float(val)
                    else:
                        row['price'] = 0.0
                except:
                    row['price'] = 0.0
            if row.get('change_pct'):
                try:
                    val = row['change_pct']
                    if isinstance(val, (int, float, Decimal)):
                        row['change_pct'] = float(val)
                    elif isinstance(val, str) and val:
                        row['change_pct'] = float(val)
                    elif val and val != 'None':
                        row['change_pct'] = float(val)
                    else:
                        row['change_pct'] = 0.0
                except:
                    row['change_pct'] = 0.0
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
            # 处理数值字段 - 统一处理所有可能为字符串的数值字段
            for num_field in ['price', 'change_pct', 'change_5y', 'price_percentile', 'chip_concentration', 'price_position']:
                if row.get(num_field) is not None:
                    try:
                        val = row[num_field]
                        if isinstance(val, (int, float, Decimal)):
                            row[num_field] = float(val)
                        elif isinstance(val, str) and val:
                            # 尝试转换字符串为数字
                            row[num_field] = float(val)
                        else:
                            row[num_field] = None
                    except:
                        row[num_field] = None
                else:
                    row[num_field] = None

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
                   a.macd_divergence, a.trend_analysis, a.price_position
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

    result = []

    for stock in stocks:
        passed = True

        for filter_name in filters:
            if filter_name == 'momentum_reversal':
                # 动量反转：跌幅>50% + MACD底背离 + 缩量
                if not check_momentum_reversal(stock):
                    passed = False
                    break

            elif filter_name == 'ma_alignment':
                # 均线多头排列：需要K线数据计算
                if not check_ma_alignment(stock.get('code'), conn):
                    passed = False
                    break

            elif filter_name == 'volume_break':
                # 放量突破：需要K线成交量数据
                if not check_volume_break(stock.get('code'), conn):
                    passed = False
                    break

            elif filter_name == 'high_dividend':
                # 高股息：使用PE分位作为代理（低PE高股息概率大）
                if not check_high_dividend(stock):
                    passed = False
                    break

            elif filter_name == 'low_pb':
                # 破净：使用股价和代码估算（低价股可能是破净）
                if not check_low_pb(stock.get('code'), stock.get('price')):
                    passed = False
                    break

            elif filter_name == 'small_cap':
                # 小盘弹性：股价<10元
                if not check_small_cap_simple(stock.get('code'), stock.get('price')):
                    passed = False
                    break

            elif filter_name == 'holder_decrease':
                # 股东人数减少
                if not check_holder_decrease(stock):
                    passed = False
                    break

            elif filter_name == 'sector_rotation':
                # 行业轮动：科创板/创业板优先
                if not check_sector_rotation(stock):
                    passed = False
                    break

        if passed:
            result.append(stock)

    if own_conn and conn:
        conn.close()

    return result

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
        selected_stocks = selector.select_stocks(limit=5000)

        if not selected_stocks:
            return jsonify({'code': 1, 'message': '选股失败'})

        conn = get_db()
        cursor = conn.cursor()

        # 清空旧数据
        cursor.execute("TRUNCATE TABLE stocks")
        cursor.execute("TRUNCATE TABLE stock_analysis")

        # 插入新数据
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
                cursor.execute("SELECT id FROM stock_analysis WHERE code = %s", (code,))
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

if __name__ == '__main__':
    # 注册定时任务（下午4点更新分析数据）
    from datetime import datetime, timedelta
    import threading

    def run_scheduled_task():
        """下午4点执行分析数据更新"""
        while True:
            now = datetime.now()
            # 设置每天下午4点执行
            target_hour = 16
            target_minute = 0

            if now.hour == target_hour and now.minute == target_minute:
                print("[定时任务] 开始执行分析数据更新...")
                with app.test_request_context():
                    result = refresh_analysis_scheduled()
                    print("[定时任务] 完成:", result.get_data(as_text=True))

            # 每分钟检查一次
            threading.Timer(60, run_scheduled_task).start()
            break

    # 启动定时任务检查（在后台线程）
    threading.Thread(target=run_scheduled_task, daemon=True).start()

    app.run(host='0.0.0.0', port=5000, debug=True)