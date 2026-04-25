#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
定时任务管理器 - 自动化选股系统
每日/每周/每月下午4点执行
"""

import threading
import time
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
import pymysql
import concurrent.futures


# 数据库配置
DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'select_stocks',
    'charset': 'utf8mb4'
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

def is_last_trading_day_of_week():
    """判断是否是本周最后一个交易日（周五）"""
    today = datetime.now()
    # 周五就是一周最后一个交易日
    return today.weekday() == 4

def is_last_trading_day_of_month():
    """判断是否是本月最后一个交易日"""
    today = datetime.now()
    # 获取本月最后一天
    if today.month == 12:
        last_day = datetime(today.year + 1, 1, 1) - timedelta(days=1)
    else:
        last_day = datetime(today.year, today.month + 1, 1) - timedelta(days=1)

    # 如果今天接近月末且是交易日
    return (today.day >= last_day.day - 3) and today.weekday() < 5

def update_daily_kline():
    """更新日K线数据（并行优化版）"""
    print("[定时任务] 开始更新日K线数据...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from kline_manager import update_today_kline

    # 只更新日K
    from kline_manager import fetch_kline_data, save_kline_to_db, get_all_stock_codes, get_db

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("SELECT DISTINCT code FROM stock_kline WHERE period = 'daily'")
        stocks = [row['code'] for row in cursor.fetchall()]
        print(f"[定时任务] 共 {len(stocks)} 只股票需要更新")

        updated = [0]
        lock = threading.Lock()

        def update_one(code):
            try:
                time.sleep(0.15)  # 缩短间隔
                df = fetch_kline_data(code, 'daily')
                if df is not None and not df.empty:
                    latest = df.tail(1)
                    save_kline_to_db(latest, code, 'daily')
                with lock:
                    updated[0] += 1
                    if updated[0] % 200 == 0:
                        print(f"[定时任务] 已更新 {updated[0]}/{len(stocks)}")
                return True
            except Exception as e:
                return False

        # 并行处理 - 10个线程
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            list(executor.map(update_one, stocks))

        print(f"[定时任务] 日K线更新完成，共更新 {updated[0]} 只")
    finally:
        cursor.close()
        conn.close()

def update_weekly_kline():
    """更新周K线数据（并行优化版）"""
    print("[定时任务] 开始更新周K线数据...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from kline_manager import fetch_kline_data, save_kline_to_db, get_all_stock_codes, get_db

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("SELECT DISTINCT code FROM stock_kline WHERE period = 'weekly'")
        stocks = [row['code'] for row in cursor.fetchall()]
        print(f"[定时任务] 共 {len(stocks)} 只股票需要更新")

        updated = [0]
        lock = threading.Lock()

        def update_one(code):
            try:
                time.sleep(0.2)
                df = fetch_kline_data(code, 'weekly')
                if df is not None and not df.empty:
                    latest = df.tail(1)
                    save_kline_to_db(latest, code, 'weekly')
                with lock:
                    updated[0] += 1
                return True
            except Exception as e:
                return False

        # 并行处理 - 10个线程
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            list(executor.map(update_one, stocks))

        print(f"[定时任务] 周K线更新完成，共更新 {updated[0]} 只")
    finally:
        cursor.close()
        conn.close()

def update_monthly_kline():
    """更新月K线数据"""
    print("[定时任务] 开始更新月K线数据...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from kline_manager import fetch_kline_data, save_kline_to_db, get_all_stock_codes, get_db

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("SELECT DISTINCT code FROM stock_kline WHERE period = 'monthly'")
        stocks = [row['code'] for row in cursor.fetchall()]
        print(f"[定时任务] 共 {len(stocks)} 只股票需要更新")

        for i, code in enumerate(stocks):
            try:
                time.sleep(0.3)
                df = fetch_kline_data(code, 'monthly')
                if df is not None and not df.empty:
                    latest = df.tail(1)
                    save_kline_to_db(latest, code, 'monthly')
            except Exception as e:
                continue

        print("[定时任务] 月K线更新完成")
    finally:
        cursor.close()
        conn.close()

def run_stock_selection():
    """运行选股算法"""
    print("[定时任务] 开始选股...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    from stock_selector import StockSelector
    from data_fetcher import DataFetcher

    df = DataFetcher()
    selector = StockSelector(df)

    # 执行选股
    selected_stocks = selector.select_stocks(limit=5000)

    if not selected_stocks:
        print("[定时任务] 选股失败")
        return

    # 保存到数据库
    conn = get_db()
    cursor = conn.cursor()

    try:
        # 清空旧数据
        cursor.execute("TRUNCATE TABLE stocks")
        cursor.execute("TRUNCATE TABLE stock_analysis")

        # 插入新数据
        for stock in selected_stocks:
            cursor.execute("""
                INSERT INTO stocks (code, name, price, change_pct, selected_at)
                VALUES (%s, %s, %s, %s, %s)
            """, (stock['code'], stock['name'], stock['price'], stock['change_pct'], stock['selected_at']))

        conn.commit()
        print(f"[定时任务] 选股完成，共选出 {len(selected_stocks)} 只股票")
    finally:
        cursor.close()
        conn.close()

def update_analysis():
    """更新分析数据"""
    print("[定时任务] 开始更新分析数据...")
    import sys
    sys.path.insert(0, '/root/select_stocks')
    import json
    from analyzer import TechnicalAnalyzer
    from data_fetcher import DataFetcher

    df = DataFetcher()
    analyzer = TechnicalAnalyzer(df, use_local_kline=True)

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        cursor.execute("SELECT code FROM stocks")
        stocks = cursor.fetchall()

        updated = 0
        for stock in stocks:
            code = stock['code']
            try:
                analysis = analyzer.analyze_stock(code)

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

                if updated % 10 == 0:
                    print(f"[定时任务] 已更新 {updated} 只股票")
            except Exception as e:
                print(f"[定时任务] {code} 分析失败: {e}")
                continue

        conn.commit()
        print(f"[定时任务] 分析数据更新完成，共更新 {updated} 只股票")
    finally:
        cursor.close()
        conn.close()

def daily_task():
    """每日下午4点执行的任务"""
    print("=" * 50)
    print("[每日任务] 开始执行...")
    print("=" * 50)

    # 1. 更新日K线
    update_daily_kline()

    # 2. 运行选股
    run_stock_selection()

    # 3. 更新分析数据
    update_analysis()

    print("=" * 50)
    print("[每日任务] 执行完成!")
    print("=" * 50)

def weekly_task():
    """每周最后一个交易日下午4点执行"""
    if not is_last_trading_day_of_week():
        print("[周任务] 今天不是本周最后一个交易日，跳过")
        return

    print("=" * 50)
    print("[周任务] 开始执行（周五）...")
    print("=" * 50)

    # 更新周K线
    update_weekly_kline()

    # 重新选股
    run_stock_selection()

    # 更新分析
    update_analysis()

    print("=" * 50)
    print("[周任务] 执行完成!")
    print("=" * 50)

def monthly_task():
    """每月最后一个交易日下午4点执行"""
    if not is_last_trading_day_of_month():
        print("[月任务] 今天不是本月最后一个交易日，跳过")
        return

    print("=" * 50)
    print("[月任务] 开始执行（月末）...")
    print("=" * 50)

    # 更新月K线
    update_monthly_kline()

    # 重新选股
    run_stock_selection()

    # 更新分析
    update_analysis()

    print("=" * 50)
    print("[月任务] 执行完成!")
    print("=" * 50)

def start_scheduler():
    """启动定时任务调度器"""
    scheduler = BackgroundScheduler()

    # 每日下午4点执行
    scheduler.add_job(daily_task, 'cron', hour=16, minute=0)

    # 每周五下午4点执行（检查是否为最后交易日）
    scheduler.add_job(weekly_task, 'cron', hour=16, minute=10)

    # 每月最后几个交易日下午4点执行
    scheduler.add_job(monthly_task, 'cron', hour=16, minute=20, day='28-31')

    scheduler.start()
    print("[调度器] 定时任务已启动")
    print("  - 每日16:00: 更新日K + 选股 + 分析")
    print("  - 每周五16:10: 更新周K + 选股 + 分析")
    print("  - 每月末16:20: 更新月K + 选股 + 分析")

if __name__ == '__main__':
    # 可以手动触发任务进行测试
    import sys
    if len(sys.argv) > 1:
        if sys.argv[1] == 'daily':
            daily_task()
        elif sys.argv[1] == 'weekly':
            weekly_task()
        elif sys.argv[1] == 'monthly':
            monthly_task()
        elif sys.argv[1] == 'test':
            print(f"今日是周几: {datetime.now().weekday()} (0=周一, 4=周五)")
            print(f"是否周五: {is_last_trading_day_of_week()}")
            print(f"是否月末: {is_last_trading_day_of_month()}")
    else:
        # 启动调度器
        start_scheduler()
        print("[主程序] 按Ctrl+C退出")

        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            print("[主程序] 退出")