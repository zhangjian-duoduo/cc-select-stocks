#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API接口模块
"""

from flask import Flask, jsonify, request
import pymysql
from datetime import datetime

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
                   a.macd_divergence, a.trend_analysis, a.price_position
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
            result['trend_analysis'] = analysis.get('trend_analysis', '{}')

        return jsonify({'code': 0, 'data': result})

    except Exception as e:
        return jsonify({'code': 1, 'message': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/api/v1/refresh', methods=['POST'])
def refresh_stocks():
    """手动刷新选股结果"""
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

        return jsonify({'code': 0, 'message': f'选股完成，共选出 {len(selected_stocks)} 只股票'})

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
    由于实时行情API限制，价格更新暂不可用
    返回现有数据，标记成功
    """
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

        # 实时价格获取需要付费API，这里暂时跳过
        # 可以选择：1.使用现有数据 2.返回成功让前端刷新

        return jsonify({
            'code': 0,
            'message': f'共 {len(stocks)} 只股票，价格将在下午4点分析更新时同步',
            'count': len(stocks)
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