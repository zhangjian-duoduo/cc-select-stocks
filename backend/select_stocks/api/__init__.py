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
                if row.get(num_field):
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
        selected_stocks = selector.select_stocks(limit=100)

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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)