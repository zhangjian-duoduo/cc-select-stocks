#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
K线数据模块 - 存储所有A股历史K线数据
"""

import baostock as bs
import pymysql
import pandas as pd
from datetime import datetime, timedelta
from typing import Optional
import time
import os

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

def create_kline_table():
    """创建K线数据表"""
    conn = get_db()
    cursor = conn.cursor()

    try:
        # 创建K线数据表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS stock_kline (
                id INT AUTO_INCREMENT PRIMARY KEY,
                code VARCHAR(10) NOT NULL,
                date DATE NOT NULL,
                open DECIMAL(10,2),
                high DECIMAL(10,2),
                low DECIMAL(10,2),
                close DECIMAL(10,2),
                volume BIGINT,
                amount DECIMAL(20,2),
                period VARCHAR(10) NOT NULL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY uk_code_date_period (code, date, period),
                INDEX idx_code_period (code, period),
                INDEX idx_date (date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """)
        conn.commit()
        print("[数据库] K线表创建成功")
    finally:
        cursor.close()
        conn.close()

def get_all_stock_codes() -> list:
    """获取所有A股代码"""
    # 优先从本地文件读取
    local_file = os.path.join(os.path.dirname(__file__), 'stock_codes.txt')
    if os.path.exists(local_file):
        try:
            with open(local_file, 'r') as f:
                codes = [line.strip() for line in f if line.strip()]
            if codes:
                print(f"[本地文件] 读取到 {len(codes)} 只股票")
                return codes
        except Exception as e:
            print(f"[本地文件] 读取失败: {e}")

    # 回退到akshare
    import akshare as ak
    try:
        df = ak.stock_info_a_code_name()
        stocks = []
        for _, row in df.iterrows():
            code = str(row['code']).zfill(6)
            if code.startswith('6') or code.startswith('0') or code.startswith('3'):
                stocks.append(code)
        return stocks
    except Exception as e:
        print(f"[akshare] 获取股票列表失败: {e}")

    # 最后回退到baostock
    lg = bs.login()
    if lg.error_code != '0':
        print(f"[baostock] 登录失败: {lg.error_msg}")
        return []

    rs = bs.query_all_stock()
    stocks = []
    while rs.error_code == '0' and rs.next():
        row = rs.get_row_data()
        code = row[0]
        if code.startswith('sh.6') or code.startswith('sz.0') or code.startswith('sz.3'):
            stocks.append(code.replace('sh.', '').replace('sz.', ''))

    bs.logout()
    return stocks

def fetch_kline_data(stock_code: str, period: str = 'daily', latest_only: bool = False) -> Optional[pd.DataFrame]:
    """获取单只股票的K线数据
    latest_only: True=只获取最新数据, False=获取全部历史数据
    """
    lg = bs.login()
    if lg.error_code != '0':
        return None

    # 转换周期
    frequency_map = {
        'daily': 'd',
        'weekly': 'w',
        'monthly': 'm'
    }
    frequency = frequency_map.get(period, 'd')

    # 6开头是上海，0/3开头是深圳
    bs_code = f'sh.{stock_code}' if stock_code.startswith('6') else f'sz.{stock_code}'

    # 根据参数决定获取多少数据
    if latest_only:
        # 只需要最新数据 - 快速获取
        if period == 'daily':
            start_date = (datetime.now() - timedelta(days=10)).strftime('%Y-%m-%d')
        elif period == 'weekly':
            start_date = (datetime.now() - timedelta(days=60)).strftime('%Y-%m-%d')
        else:  # monthly
            start_date = (datetime.now() - timedelta(days=365)).strftime('%Y-%m-%d')
    else:
        # 获取全部历史数据
        start_date = '1990-01-01'

    end_date = datetime.now().strftime('%Y-%m-%d')

    rs = bs.query_history_k_data_plus(
        bs_code,
        "date,code,open,high,low,close,volume,amount",
        start_date=start_date,
        end_date=end_date,
        frequency=frequency,
        adjustflag="2"  # 前复权
    )

    data_list = []
    while rs.error_code == '0' and rs.next():
        data_list.append(rs.get_row_data())

    bs.logout()

    if not data_list:
        return None

    df = pd.DataFrame(data_list, columns=['date', 'code', 'open', 'high', 'low', 'close', 'volume', 'amount'])

    # 过滤无效数据
    df = df[df['close'].notna() & (df['close'] != '')]
    if df.empty:
        return None

    # 转换数据类型
    for col in ['open', 'high', 'low', 'close']:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    df['volume'] = pd.to_numeric(df['volume'], errors='coerce')
    df['amount'] = pd.to_numeric(df['amount'], errors='coerce')

    df['period'] = period

    return df

def save_kline_to_db(df: pd.DataFrame, stock_code: str, period: str) -> int:
    """保存K线数据到数据库"""
    if df is None or df.empty:
        return 0

    conn = get_db()
    cursor = conn.cursor()

    saved = 0
    try:
        for _, row in df.iterrows():
            try:
                cursor.execute("""
                    INSERT INTO stock_kline (code, date, open, high, low, close, volume, amount, period)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        open = VALUES(open),
                        high = VALUES(high),
                        low = VALUES(low),
                        close = VALUES(close),
                        volume = VALUES(volume),
                        amount = VALUES(amount),
                        updated_at = NOW()
                """, (
                    stock_code,
                    row['date'],
                    row['open'],
                    row['high'],
                    row['low'],
                    row['close'],
                    int(row['volume']) if pd.notna(row['volume']) else 0,
                    row['amount'],
                    period
                ))
                saved += 1
            except Exception as e:
                print(f"[保存] {stock_code} {period} {row['date']} 失败: {e}")
                continue

        conn.commit()
    finally:
        cursor.close()
        conn.close()

    return saved

def init_all_kline_data(stock_limit: int = None):
    """初始化所有股票的K线数据"""
    print("[初始化] 开始获取所有A股K线数据...")

    # 创建表
    create_kline_table()

    # 获取所有股票代码
    stocks = get_all_stock_codes()
    print(f"[初始化] 共获取 {len(stocks)} 只A股")

    if stock_limit:
        stocks = stocks[:stock_limit]
        print(f"[初始化] 限制处理前 {stock_limit} 只")

    # 处理的周期
    periods = ['daily', 'weekly', 'monthly']

    total_saved = 0
    for i, code in enumerate(stocks):
        print(f"[初始化] ({i+1}/{len(stocks)}) 处理 {code}...")

        for period in periods:
            try:
                # 添加延时避免被限流
                time.sleep(0.3)

                df = fetch_kline_data(code, period)
                if df is not None:
                    saved = save_kline_to_db(df, code, period)
                    print(f"  - {period}: {saved} 条")
                    total_saved += saved
            except Exception as e:
                print(f"  - {period} 失败: {e}")
                continue

    print(f"[初始化] 完成！共保存 {total_saved} 条K线数据")

def update_today_kline():
    """更新当日K线数据（增量更新）"""
    print("[更新] 开始更新当日K线数据...")

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # 获取所有股票代码
        cursor.execute("SELECT DISTINCT code FROM stock_kline")
        stocks = [row['code'] for row in cursor.fetchall()]

        print(f"[更新] 共 {len(stocks)} 只股票")

        periods = ['daily']  # 只需要更新日K

        total_updated = 0
        for i, code in enumerate(stocks):
            print(f"[更新] ({i+1}/{len(stocks)}) 更新 {code}...")

            for period in periods:
                try:
                    time.sleep(0.2)

                    df = fetch_kline_data(code, period)
                    if df is not None and not df.empty:
                        # 只取最新的数据
                        latest = df.tail(1)
                        saved = save_kline_to_db(latest, code, period)
                        if saved > 0:
                            total_updated += 1
                except Exception as e:
                    print(f"  - 失败: {e}")
                    continue

        print(f"[更新] 完成！共更新 {total_updated} 只股票")

    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1:
        if sys.argv[1] == 'init':
            # 初始化所有K线数据
            limit = int(sys.argv[2]) if len(sys.argv) > 2 else None
            init_all_kline_data(limit)
        elif sys.argv[1] == 'update':
            # 更新当日数据
            update_today_kline()
    else:
        print("使用方法:")
        print("  python kline_manager.py init [limit]  - 初始化K线数据（可选限制数量）")
        print("  python kline_manager.py update        - 更新当日K线数据")