#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
定时任务管理器 - 自动化选股系统
每日下午4点执行
"""

import threading
import time
import os
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler

# 事件常量
EVENT_JOB_EXECUTED = 'job_executed'
import pymysql
import concurrent.futures
import math


# 数据库配置（密码从环境变量读取，未设置则使用空密码）
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),
    'database': os.environ.get('DB_NAME', 'select_stocks'),
    'charset': 'utf8mb4'
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

def update_daily_kline():
    """更新日K线数据 - 委托给 kline_manager（含除权检测）"""
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from kline_manager import update_today_kline
    update_today_kline()

def aggregate_weekly_kline():
    """从日K数据聚合生成周K线（从上周一开始查，保证上周完整）"""
    print("[定时任务] 开始聚合周K线数据...")

    today = datetime.now()
    this_monday = today - timedelta(days=today.weekday())
    last_monday = this_monday - timedelta(days=7)
    start_date = last_monday.strftime('%Y-%m-%d')
    end_date = today.strftime('%Y-%m-%d')

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("""
            SELECT code, date, open, high, low, close, volume, amount
            FROM stock_kline WHERE period='daily' AND date >= %s AND date <= %s
            ORDER BY code, date
        """, (start_date, end_date))
        rows = cursor.fetchall()

        if not rows:
            print("[定时任务] 无日K数据，跳过周K聚合")
            return

        from collections import defaultdict
        # 按 (code, iso_year, iso_week) 分组
        by_week = defaultdict(list)
        for r in rows:
            d = datetime.strptime(str(r['date']), '%Y-%m-%d')
            week_key = (r['code'], d.isocalendar()[0], d.isocalendar()[1])
            by_week[week_key].append(r)

        saved = 0
        for (code, year, week), daily_rows in by_week.items():
            try:
                daily_rows.sort(key=lambda x: x['date'])
                first = daily_rows[0]
                last = daily_rows[-1]

                high = max(r['high'] for r in daily_rows if r['high'] is not None)
                low = min(r['low'] for r in daily_rows if r['low'] is not None)
                volume = sum(int(r['volume']) if r['volume'] is not None else 0 for r in daily_rows)
                amount = sum(float(r['amount']) if r['amount'] is not None else 0 for r in daily_rows)

                def clean_val(v):
                    if v is None or (isinstance(v, float) and math.isnan(v)):
                        return None
                    return v

                cursor.execute("""
                    INSERT INTO stock_kline (code, date, open, high, low, close, volume, amount, period)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'weekly')
                    ON DUPLICATE KEY UPDATE
                        open = VALUES(open), high = VALUES(high), low = VALUES(low),
                        close = VALUES(close), volume = VALUES(volume), amount = VALUES(amount),
                        updated_at = NOW()
                """, (
                    code, last['date'],
                    clean_val(first['open']), clean_val(high), clean_val(low), clean_val(last['close']),
                    volume, clean_val(amount)
                ))
                saved += 1
            except Exception as e:
                print(f"[定时任务] 周K聚合失败 {code}: {e}")

        conn.commit()
        print(f"[定时任务] 周K聚合完成，保存 {saved} 只")
    finally:
        cursor.close()
        conn.close()

def aggregate_monthly_kline():
    """从日K数据聚合生成月K线（从上月1号查起，保证上月完整）"""
    print("[定时任务] 开始聚合月K线数据...")

    today = datetime.now()
    current_month_start = today.replace(day=1)
    prev_month_start = (current_month_start - timedelta(days=1)).replace(day=1)
    start_date = prev_month_start.strftime('%Y-%m-%d')
    end_date = today.strftime('%Y-%m-%d')

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("""
            SELECT code, date, open, high, low, close, volume, amount
            FROM stock_kline WHERE period='daily' AND date >= %s AND date <= %s
            ORDER BY code, date
        """, (start_date, end_date))
        rows = cursor.fetchall()

        if not rows:
            print("[定时任务] 无日K数据，跳过月K聚合")
            return

        from collections import defaultdict
        # 按 (code, year, month) 分组
        by_month = defaultdict(list)
        for r in rows:
            d = datetime.strptime(str(r['date']), '%Y-%m-%d')
            month_key = (r['code'], d.year, d.month)
            by_month[month_key].append(r)

        saved = 0
        for (code, year, month), daily_rows in by_month.items():
            try:
                daily_rows.sort(key=lambda x: x['date'])
                first = daily_rows[0]
                last = daily_rows[-1]

                high = max(r['high'] for r in daily_rows if r['high'] is not None)
                low = min(r['low'] for r in daily_rows if r['low'] is not None)
                volume = sum(int(r['volume']) if r['volume'] is not None else 0 for r in daily_rows)
                amount = sum(float(r['amount']) if r['amount'] is not None else 0 for r in daily_rows)

                def clean_val(v):
                    if v is None or (isinstance(v, float) and math.isnan(v)):
                        return None
                    return v

                cursor.execute("""
                    INSERT INTO stock_kline (code, date, open, high, low, close, volume, amount, period)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'monthly')
                    ON DUPLICATE KEY UPDATE
                        open = VALUES(open), high = VALUES(high), low = VALUES(low),
                        close = VALUES(close), volume = VALUES(volume), amount = VALUES(amount),
                        updated_at = NOW()
                """, (
                    code, last['date'],
                    clean_val(first['open']), clean_val(high), clean_val(low), clean_val(last['close']),
                    volume, clean_val(amount)
                ))
                saved += 1
            except Exception as e:
                print(f"[定时任务] 月K聚合失败 {code}: {e}")

        conn.commit()
        print(f"[定时任务] 月K聚合完成，保存 {saved} 只")
    finally:
        cursor.close()
        conn.close()

def update_all_financial_data():
    """更新所有A股财务数据（增量更新：只更新财报超过30天的）"""
    print("[财务全量] 开始更新A股财务数据（增量）...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import akshare as ak
    import pandas as pd
    import random
    import time
    import concurrent.futures
    from datetime import datetime, timedelta

    DB_CONFIG = {
        'host': 'localhost',
        'user': 'root',
        'password': '',
        'database': 'select_stocks',
        'charset': 'utf8mb4'
    }

    def get_db():
        return pymysql.connect(**DB_CONFIG)

    # 获取所有股票代码
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT code FROM stock_kline")
    stock_codes = [row[0] for row in cursor.fetchall()]
    cursor.close()
    conn.close()

    print(f"[财务全量] 共 {len(stock_codes)} 只股票需要更新财务数据")

    def fetch_and_save(code):
        """获取并保存单只股票的财务数据"""
        try:
            time.sleep(random.uniform(0.05, 0.15))  # 间隔，避免被API限流

            # 获取财务数据
            fin_df = ak.stock_financial_abstract_new_ths(symbol=code)
            if fin_df is None or len(fin_df) == 0:
                return None

            # 获取净利润数据
            net_profit_df = fin_df[fin_df['metric_name'] == 'parent_holder_net_profit'].copy()
            if len(net_profit_df) == 0:
                return None

            net_profit_df = net_profit_df.sort_values('report_date', ascending=False)
            row = net_profit_df.iloc[0]

            report_date = row['report_date']
            report_name = row.get('report_name', '')

            yoy = row.get('single_yoy')
            mom = row.get('mom')

            yoy_str = f"{float(yoy) * 100:.2f}%" if pd.notna(yoy) else ''
            mom_str = f"{float(mom) * 100:.1f}%" if pd.notna(mom) else ''

            # 获取营收数据
            revenue_df = fin_df[fin_df['metric_name'] == 'operating_income_total']
            revenue_yoy_str = ''
            if len(revenue_df) > 0:
                revenue_row = revenue_df[revenue_df['report_date'] == report_date]
                if len(revenue_row) > 0:
                    rev_yoy = revenue_row.iloc[0].get('single_yoy')
                    if pd.notna(rev_yoy):
                        revenue_yoy_str = f"{float(rev_yoy) * 100:.2f}%"

            # 获取ROE
            roe_str = ''
            roe_df = fin_df[fin_df['metric_name'] == 'index_full_diluted_roe']
            if len(roe_df) > 0:
                roe_df = roe_df.sort_values('report_date', ascending=False)
                roe = roe_df.iloc[0]
                if pd.notna(roe.get('value')):
                    roe_str = str(round(float(roe['value']), 2))

            return {
                'code': code,
                'report_date': report_date,
                'report_name': report_name,
                'net_profit_yoy': yoy_str,
                'net_profit_qoq': mom_str,
                'revenue_yoy': revenue_yoy_str,
                'roe': roe_str
            }
        except Exception as e:
            return None

    # 并行获取财务数据（5个线程）
    success = [0]
    lock = threading.Lock()

    def process_stock(code):
        result = fetch_and_save(code)
        if result:
            try:
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute("""
                    REPLACE INTO stock_financial_history
                    (code, report_date, report_name, net_profit_yoy, net_profit_qoq, revenue_yoy, roe, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                """, (result['code'], result['report_date'], result['report_name'],
                      result['net_profit_yoy'], result['net_profit_qoq'],
                      result['revenue_yoy'], result.get('roe', '')))
                conn.commit()
                cursor.close()
                conn.close()
                with lock:
                    success[0] += 1
                return True
            except:
                return False
        return False

    print("[财务全量] 开始获取财务数据...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(process_stock, stock_codes))

    print(f"[财务全量] 财务数据更新完成，共更新 {success[0]} 只股票")

def run_stock_selection():
    """运行选股算法"""
    print("[定时任务] 开始选股...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from stock_selector import StockSelector
    from data_fetcher import DataFetcher
    from datetime import datetime

    df = DataFetcher()
    selector = StockSelector(df)

    # 执行选股
    selected_stocks = selector.select_stocks(limit=5000)

    if not selected_stocks:
        print("[定时任务] 选股失败")
        return

    # 保存到数据库
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # 获取上一个有数据的日期（从stock_history表读取）
        cursor.execute("""
            SELECT MAX(selected_at) as dt
            FROM stock_history
            LIMIT 1
        """)
        prev_row = cursor.fetchone()
        prev_date = prev_row['dt'].strftime('%Y-%m-%d') if prev_row and prev_row['dt'] else None

        yesterday_stocks = {}
        if prev_date:
            cursor.execute("SELECT code, name FROM stock_history WHERE selected_at = %s", (prev_date,))
            yesterday_stocks = {row['code']: {'name': row['name']} for row in cursor.fetchall()}

        # 9点前用昨天，9点后用今天
        now = datetime.now()
        if now.hour < 9:
            from datetime import timedelta
            today = (now - timedelta(days=1)).strftime('%Y-%m-%d')
        else:
            today = now.strftime('%Y-%m-%d')

        # 保存被剔除的股票
        for code, info in yesterday_stocks.items():
            if code not in [s['code'] for s in selected_stocks]:
                cursor.execute("""
                    INSERT INTO stock_removed (code, name, removed_at)
                    VALUES (%s, %s, %s)
                """, (code, info.get('name', ''), today))

        # 保存今日选股结果到历史
        for stock in selected_stocks:
            sector = stock.get('sector', '') or ''
            cursor.execute("""
                INSERT INTO stock_history (code, name, selected_at)
                VALUES (%s, %s, %s)
            """, (stock['code'], stock['name'], today))

        # 清空旧数据
        cursor.execute("TRUNCATE TABLE stocks")
        cursor.execute("TRUNCATE TABLE stock_analysis")

        # 插入新数据
        for stock in selected_stocks:
            # 获取行业板块信息
            sector = stock.get('sector', '') or ''
            cursor.execute("""
                INSERT INTO stocks (code, name, price, change_pct, selected_at, sector)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (stock['code'], stock['name'], stock['price'], stock['change_pct'], stock['selected_at'], sector))

        conn.commit()
        print(f"[定时任务] 选股完成，共选出 {len(selected_stocks)} 只股票")
        print(f"[定时任务] 记录剔除股票 {len(yesterday_stocks) - len(set(yesterday_stocks.keys()) & set([s['code'] for s in selected_stocks]))} 只")
        print(f"[定时任务] 保存历史记录 {len(selected_stocks)} 只")
    finally:
        cursor.close()
        conn.close()

def should_update_financial_data():
    """每天都需要更新财务数据"""
    return True

def update_analysis(update_financial=False):
    """更新分析数据 - 优化版：优先从本地数据库读取财务数据"""
    print("[定时任务] 开始更新分析数据...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import json
    import concurrent.futures
    import time
    from datetime import datetime
    from analyzer import TechnicalAnalyzer
    from data_fetcher import DataFetcher

    df = DataFetcher()
    analyzer = TechnicalAnalyzer(df, use_local_kline=True)

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("SELECT code FROM stocks")
        stocks = cursor.fetchall()
        stock_codes = [s['code'] for s in stocks]
        print(f"[定时任务] 共 {len(stock_codes)} 只股票需要更新")

        # 步骤1: 从本地数据库读取财务数据（net_profit_yoy, net_profit_qoq）
        print("[定时任务] 从本地数据库读取财务数据...")
        financial_data_cache = {}

        # 批量获取所有股票的财务数据
        cursor.execute("""
            SELECT code, report_date, report_name, net_profit_yoy, net_profit_qoq, roe
            FROM stock_financial_history
            WHERE (code, report_date) IN (
                SELECT code, MAX(report_date) FROM stock_financial_history GROUP BY code
            )
        """)
        for row in cursor.fetchall():
            financial_data_cache[row['code']] = {
                'net_profit_yoy': row['net_profit_yoy'] or '',
                'net_profit_qoq': row['net_profit_qoq'] or '',
                'roe': row['roe'] or '',
                'revenue': '',
                'book_value_per_share': ''
            }

        print(f"[定时任务] 从本地读取了 {len(financial_data_cache)} 只股票的财务数据")

        # 步骤2: 获取已有的ROE数据作为回退
        print("[定时任务] 获取已有的ROE数据...")
        cursor.execute("SELECT code, roe, revenue, book_value_per_share FROM stock_analysis")
        existing_data = {}
        for row in cursor.fetchall():
            existing_data[row['code']] = {
                'roe': row['roe'] or '',
                'revenue': row['revenue'] or '',
                'book_value_per_share': row['book_value_per_share'] or ''
            }

        # 合并数据：使用本地财务数据 + 已有ROE
        for code in stock_codes:
            # 确保缓存中有这条记录
            if code not in financial_data_cache:
                financial_data_cache[code] = {
                    'net_profit_yoy': '',
                    'net_profit_qoq': '',
                    'roe': '',
                    'revenue': '',
                    'book_value_per_share': ''
                }
            if code in existing_data:
                if not financial_data_cache[code].get('roe'):
                    financial_data_cache[code]['roe'] = existing_data[code].get('roe', '')
                if not financial_data_cache[code].get('revenue'):
                    financial_data_cache[code]['revenue'] = existing_data[code].get('revenue', '')
                if not financial_data_cache[code].get('book_value_per_share'):
                    financial_data_cache[code]['book_value_per_share'] = existing_data[code].get('book_value_per_share', '')

        print("[定时任务] 财务数据准备完成，开始更新数据库...")

        # 转换numpy类型为Python原生类型
        import numpy as np
        def convert_numpy(val, default=None):
            if val is None:
                return default
            if isinstance(val, (np.floating, np.integer)):
                return float(val)
            if isinstance(val, np.bool_):
                return bool(val)
            return val

        # 串行更新数据库（保持稳定性）
        updated = 0

        # 使用3个线程并行处理
        import concurrent.futures

        def update_one(code):
            # 带超时和重试的分析
            max_retries = 2
            for attempt in range(max_retries):
                try:
                    # 直接调用分析（signal.alarm在子线程中不可用）
                    analysis = analyzer.analyze_stock(code)

                    financial_data = financial_data_cache.get(code, {})

                    with get_db() as conn2:
                        cursor2 = conn2.cursor(pymysql.cursors.DictCursor)
                        try:
                            cursor2.execute("DELETE FROM stock_analysis WHERE code=%s", (code,))

                            change_5y = convert_numpy(analysis.get('change_5y'), 0)
                            price_percentile = convert_numpy(analysis.get('price_percentile'), 50)
                            chip_concentration = convert_numpy(analysis.get('chip_concentration'), 0.5)
                            price_position = convert_numpy(analysis.get('price_position'), 0.5)

                            cursor2.execute("""
                                INSERT INTO stock_analysis
                                (code, holders_trend, change_5y, price_percentile, chip_concentration, macd_divergence, trend_analysis, price_position, net_profit_yoy, net_profit_qoq, revenue, book_value_per_share, roe, sector, financial_updated_at)
                                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
                            """, (
                                code,
                                json.dumps(analysis.get('holders_trend', [])),
                                change_5y,
                                price_percentile,
                                chip_concentration,
                                json.dumps(analysis.get('macd_divergence', {})),
                                json.dumps(analysis.get('trend_analysis', {})),
                                price_position,
                                financial_data.get('net_profit_yoy', ''),
                                financial_data.get('net_profit_qoq', ''),
                                financial_data.get('revenue', ''),
                                financial_data.get('book_value_per_share', ''),
                                financial_data.get('roe', ''),
                                financial_data.get('sector', '')
                            ))
                            conn2.commit()
                        finally:
                            cursor2.close()
                    return True


                except Exception as e:
                    print(f"分析失败 {code}: {e}")
                    return False

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(update_one, stock_codes))
            updated = sum(1 for r in results if r)

        conn.commit()
        print(f"[定时任务] 分析数据更新完成，共更新 {updated} 只股票")
    finally:
        cursor.close()
        conn.close()

def get_financial_data_fast(code):
    """获取财务数据（使用单季度数据API）"""
    import akshare as ak
    import pandas as pd

    result = {
        'net_profit_yoy': '',
        'net_profit_qoq': '',
        'revenue': '',
        'book_value_per_share': '',
        'roe': ''
    }

    try:
        # 使用新的API获取单季度数据
        df = ak.stock_financial_abstract_new_ths(symbol=code)
        if df is None or len(df) == 0:
            # 备用方案
            return get_financial_data_old(code)

        # 获取净利润数据
        net_profit_df = df[df['metric_name'] == 'parent_holder_net_profit']
        if len(net_profit_df) == 0:
            return get_financial_data_old(code)

        # 按报告期排序，取最新
        net_profit_df = net_profit_df.sort_values('report_date', ascending=False)

        # 最新报告
        latest = net_profit_df.iloc[0]
        latest_report_name = latest['report_name']

        # yoy和mom已经是小数形式（如-1.064表示-106.4%）
        if pd.notna(latest['single_yoy']):
            yoy_val = float(latest['single_yoy']) * 100
            result['net_profit_yoy'] = f"{yoy_val:.2f}"

        # 环比(mom)
        if pd.notna(latest['mom']):
            mom_val = float(latest['mom']) * 100
            result['net_profit_qoq'] = f"{mom_val:.1f}%"

        # 获取营业收入（单位是元，需要转换）
        revenue_df = df[df['metric_name'] == 'operating_income_total']
        if len(revenue_df) > 0:
            revenue_df = revenue_df.sort_values('report_date', ascending=False)
            latest_revenue = revenue_df.iloc[0]
            if pd.notna(latest_revenue['single']):
                revenue_single = float(latest_revenue['single'])
                # 转换为亿元
                if revenue_single >= 100000000:
                    result['revenue'] = f"{revenue_single/100000000:.2f}亿"
                elif revenue_single >= 10000:
                    result['revenue'] = f"{revenue_single/10000:.2f}万"

        # 获取每股净资产（单位是元）
        bv_df = df[df['metric_name'] == 'calc_per_net_assets']
        if len(bv_df) > 0:
            bv_df = bv_df.sort_values('report_date', ascending=False)
            bv = bv_df.iloc[0]
            if pd.notna(bv['value']):
                result['book_value_per_share'] = str(round(float(bv['value']), 2))

        # 获取ROE（已经是百分比形式）
        roe_df = df[df['metric_name'] == 'index_full_diluted_roe']
        if len(roe_df) > 0:
            roe_df = roe_df.sort_values('report_date', ascending=False)
            roe = roe_df.iloc[0]
            if pd.notna(roe['value']):
                result['roe'] = str(round(float(roe['value']), 2))

        return result

    except Exception as e:
        print(f"[财务数据] {code} 获取失败: {e}")
        return get_financial_data_old(code)


def get_financial_data_old(code):
    """备用：使用旧的API获取财务数据"""
    import akshare as ak
    import pandas as pd

    result = {
        'net_profit_yoy': '',
        'net_profit_qoq': '',
        'revenue': '',
        'book_value_per_share': '',
        'roe': ''
    }

    def parse_money(val):
        if val is None or val == False:
            return 0
        val = str(val)
        num = float(val.replace('亿', '').replace('万', '').replace('元', '').replace(',', ''))
        if '亿' in val:
            num *= 10000
        return num

    try:
        df = ak.stock_financial_abstract_ths(symbol=code)
        if df is not None and len(df) > 0:
            df['报告期'] = pd.to_datetime(df['报告期'], errors='coerce')
            df = df.sort_values('报告期', ascending=False)

            latest = df.iloc[0]
            latest_period = str(latest.get('报告期', ''))

            if '-12-31' in latest_period and len(df) > 1:
                q3_mask = df['报告期'].astype(str).str.contains('-09-30')

                if q3_mask.any():
                    q3_row = df[q3_mask].iloc[0]

                    annual_profit = parse_money(latest['净利润'])
                    q3_profit = parse_money(q3_row['净利润'])
                    q4_profit = annual_profit - q3_profit

                    last_year_mask = df['报告期'].astype(str).str.contains('2024-12-31')
                    last_year_q3_mask = df['报告期'].astype(str).str.contains('2024-09-30')

                    if last_year_mask.any() and last_year_q3_mask.any():
                        last_year_row = df[last_year_mask].iloc[0]
                        last_year_q3_row = df[last_year_q3_mask].iloc[0]
                        last_year_annual = parse_money(last_year_row['净利润'])
                        last_year_q3 = parse_money(last_year_q3_row['净利润'])
                        last_year_q4 = last_year_annual - last_year_q3
                        if last_year_q4 != 0:
                            yoy = (q4_profit - last_year_q4) / abs(last_year_q4) * 100
                            result['net_profit_yoy'] = f"{yoy:.2f}"

                    if q3_profit != 0:
                        qoq = (q4_profit - q3_profit) / abs(q3_profit) * 100
                        result['net_profit_qoq'] = f"{qoq:.1f}%"

                    annual_revenue = parse_money(latest['营业总收入'])
                    q3_revenue = parse_money(q3_row['营业总收入'])
                    q4_revenue = annual_revenue - q3_revenue
                    if q4_revenue > 0:
                        result['revenue'] = f"{q4_revenue/10000:.2f}亿"

                    bv = latest['每股净资产']
                    if bv and bv != False:
                        result['book_value_per_share'] = str(bv)

                    roe_raw = latest['净资产收益率-摊薄']
                    if roe_raw and roe_raw != False:
                        result['roe'] = str(roe_raw).replace('%', '')
                    return result

            yoy_raw = latest.get('净利润同比增长率')
            if yoy_raw is not None and yoy_raw != False:
                result['net_profit_yoy'] = str(yoy_raw).replace('%', '')

            revenue_raw = latest.get('营业总收入')
            if revenue_raw is not None and revenue_raw != False:
                result['revenue'] = str(revenue_raw)

            bv_raw = latest.get('每股净资产')
            if bv_raw is not None and bv_raw != False:
                result['book_value_per_share'] = str(bv_raw)

            roe_raw = latest.get('净资产收益率')
            if roe_raw is not None and roe_raw != False:
                result['roe'] = str(roe_raw).replace('%', '')
            else:
                roe_raw = latest.get('净资产收益率-摊薄')
                if roe_raw is not None and roe_raw != False:
                    result['roe'] = str(roe_raw).replace('%', '')

            if len(df) > 1:
                prev = df.iloc[1]
                curr_net = latest['净利润']
                prev_net = prev['净利润']
                try:
                    curr_val = parse_money(curr_net)
                    prev_val = parse_money(prev_net)
                    if prev_val != 0:
                        qoq = (curr_val - prev_val) / abs(prev_val) * 100
                        result['net_profit_qoq'] = f"{qoq:.1f}%"
                except:
                    pass

    except Exception as e:
        pass

    return result


def get_financial_data(code):
    """获取财务数据（营业收入、每股净资产等）- 兼容旧接口"""
    import time
    time.sleep(0.2)  # 稍微等待
    return get_financial_data_fast(code)

def daily_task():
    """每日下午4点执行的任务"""
    import os

    # 检查是否有其他daily_task在运行，避免重复执行
    pid_file = '/tmp/daily_task.lock'
    if os.path.exists(pid_file):
        try:
            with open(pid_file, 'r') as f:
                old_pid = int(f.read().strip())
            # 检查进程是否还活着
            if os.path.exists(f'/proc/{old_pid}'):
                print("[每日任务] 上一次任务还在运行中，跳过本次执行")
                return
        except:
            pass

    # 写入当前进程PID
    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))

    try:
        print("=" * 50)
        print("[每日任务] 开始执行...")
        print("=" * 50)

        # 1. 更新日K线
        try:
            update_daily_kline()
        except Exception as e:
            print(f"[每日任务] 日K线更新失败: {e}")

        # 2. 从日K聚合生成周K
        try:
            aggregate_weekly_kline()
        except Exception as e:
            print(f"[每日任务] 周K聚合失败: {e}")

        # 3. 从日K聚合生成月K
        try:
            aggregate_monthly_kline()
        except Exception as e:
            print(f"[每日任务] 月K聚合失败: {e}")

        # 4. 运行选股
        try:
            run_stock_selection()
        except Exception as e:
            print(f"[每日任务] 选股失败: {e}")

        # 5. 更新所有A股财务数据（必须在分析之前执行）
        try:
            update_all_financial_data()
        except Exception as e:
            print(f"[每日任务] 财务数据更新失败: {e}")

        # 6. 更新分析数据
        try:
            update_analysis()
        except Exception as e:
            print(f"[每日任务] 分析数据更新失败: {e}")

        print("=" * 50)
        print("[每日任务] 执行完成!")
        print("=" * 50)
    finally:
        # 清理锁文件
        try:
            os.remove(pid_file)
        except:
            pass


def update_incremental_financial():
    """增量更新财务数据 - 只更新今天发布财报公告的股票（每小时执行）"""
    print("[增量财务] 开始检查今日财报公告...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import pymysql
    import akshare as ak
    import pandas as pd
    from datetime import datetime
    import concurrent.futures

    DB_CONFIG = {
        'host': 'localhost',
        'user': 'root',
        'password': '',
        'database': 'select_stocks',
        'charset': 'utf8mb4'
    }

    def get_db():
        return pymysql.connect(**DB_CONFIG)

    today = datetime.now().strftime('%Y%m%d')
    stock_codes_updated = []

    try:
        # 获取今日所有公告
        df = ak.stock_notice_report(date=today)
        if df is None or len(df) == 0:
            print("[增量财务] 今日无新公告")
            return

        # 过滤财报相关公告关键词 - 更严格的过滤
        # 只保留真正的财报公告：年度报告、季度报告、业绩预告、业绩快报
        financial_keywords = ['年度报告', '年度报告正文', '季度报告', '业绩预告', '业绩快报', '业绩预增', '业绩预减', '扭亏', '年报', '一季报', '中报', '三季报', '年报摘要']
        df_financial = df[df['公告标题'].apply(
            lambda x: any(kw in str(x) for kw in financial_keywords) if pd.notna(x) else False
        )]

        if len(df_financial) == 0:
            print("[增量财务] 今日无财报公告")
            return

        # 获取需要更新的股票代码
        codes = df_financial['代码'].unique().tolist()
        print(f"[增量财务] 今日有{len(codes)}只股票发布财报公告")

        # 获取这些股票的财务数据
        import random
        import time

        def fetch_and_save(code):
            try:
                time.sleep(random.uniform(0.05, 0.1))
                fin_df = ak.stock_financial_abstract_new_ths(symbol=code)
                if fin_df is None or len(fin_df) == 0:
                    return None

                net_profit_df = fin_df[fin_df['metric_name'] == 'parent_holder_net_profit'].copy()
                if len(net_profit_df) == 0:
                    return None

                net_profit_df = net_profit_df.sort_values('report_date', ascending=False)
                row = net_profit_df.iloc[0]

                return {
                    'code': code,
                    'report_date': row['report_date'],
                    'report_name': row.get('report_name', ''),
                    'net_profit_yoy': f"{float(row.get('single_yoy', 0)) * 100:.2f}%" if pd.notna(row.get('single_yoy')) else '',
                    'net_profit_qoq': f"{float(row.get('mom', 0)) * 100:.1f}%" if pd.notna(row.get('mom')) else '',
                    'is_new': True  # 今天发布公告的股票都保存
                }
            except:
                return None

        # 并行获取财务数据
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            results = list(executor.map(fetch_and_save, codes))

        # 保存到数据库
        conn = get_db()
        cursor = conn.cursor()

        saved = 0
        for result in results:
            if result:
                try:
                    cursor.execute("""
                        REPLACE INTO stock_financial_history
                        (code, report_date, report_name, net_profit_yoy, net_profit_qoq, created_at)
                        VALUES (%s, %s, %s, %s, %s, NOW())
                    """, (result['code'], result['report_date'], result['report_name'],
                         result['net_profit_yoy'], result['net_profit_qoq']))

                    # 只保存最近7天内发布财报的股票到每日更新表
                    if result.get('is_new', False):
                        cursor.execute("""
                            INSERT IGNORE INTO daily_financial_updates
                            (code, name, report_date, report_name, net_profit_yoy, net_profit_qoq, revenue_yoy, updated_date)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, CURDATE())
                        """, (result['code'], '', result['report_date'], result['report_name'],
                             result['net_profit_yoy'], result['net_profit_qoq'], ''))
                        saved += 1
                except:
                    continue

        conn.commit()
        cursor.close()
        conn.close()
        print(f"[增量财务] 更新完成，更新{saved}只股票")

    except Exception as e:
        print(f"[增量财务] 出错: {e}")

def start_scheduler():
    """启动定时任务调度器（持久化存储，重启后保留任务状态）"""
    from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
    from apscheduler.executors.pool import ThreadPoolExecutor

    jobstores = {
        'default': SQLAlchemyJobStore(url='mysql+pymysql://root:@localhost/select_stocks')
    }
    executors = {
        'default': ThreadPoolExecutor(max_workers=1)
    }

    scheduler = BackgroundScheduler(jobstores=jobstores, executors=executors)

    # 每日16:00执行（更新日K → 聚合周K/月K → 选股 → 财务 → 分析）
    scheduler.add_job(daily_task, 'cron', hour=16, minute=0, id='daily_task',
                      replace_existing=True)

    # # 每小时增量更新财务数据（已禁用）
    # scheduler.add_job(update_incremental_financial, 'interval', hours=1, id='incremental_financial')

    scheduler.start()
    print("[调度器] 定时任务已启动 (持久化存储)")
    print("  - 每日16:00: 更新日K → 聚合周K/月K → 选股 → 财务数据 → 分析")

if __name__ == '__main__':
    # 可以手动触发任务进行测试
    import sys
    if len(sys.argv) > 1:
        if sys.argv[1] == 'daily':
            daily_task()
        elif sys.argv[1] == 'test':
            print(f"今日是周几: {datetime.now().weekday()} (0=周一, 4=周五)")
    else:
        # 启动调度器
        start_scheduler()
        print("[主程序] 按Ctrl+C退出")

        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            print("[主程序] 退出")
