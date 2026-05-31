#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
同步机构持仓历史数据
从东方财富获取每只股票近8个季度的十大股东明细，分类汇总机构/个人持股比例
"""

import pymysql
import sys
import os
import time
import concurrent.futures
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from db import get_db

# 8 quarters of report dates (YYYYMMDD)
# These are the standard report dates for Chinese A-shares
REPORT_DATES = [
    '20240630', '20240930', '20241231',
    '20250331', '20250630', '20250930', '20251231',
    '20260331',
]

# Institution classification keywords
INST_KEYWORDS = [
    '公司', '集团', '基金', '保险', '银行', '证券', '信托',
    'QFII', '社保', '香港中央结算', '资产管理', '投资',
    '中央汇金', '证金', '国开', '财政局', '国有资产',
    '控股', '实业', '资本', '创业投资', '养老金', '年金',
    '财务公司', '期货', '资产管理', '理财', '私募',
    '回购专用', '企业年金', '基本养老保险',
]


def is_institution(name: str) -> bool:
    """判断股东名称是否为机构"""
    if not name:
        return False
    for kw in INST_KEYWORDS:
        if kw in name:
            return True
    return False


def create_table():
    """创建机构持仓历史表"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS stock_institutional_holdings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code VARCHAR(10) NOT NULL,
            report_date VARCHAR(8) NOT NULL,
            inst_ratio DECIMAL(10,4) DEFAULT 0 COMMENT '机构持股比例合计(%)',
            total_ratio DECIMAL(10,4) DEFAULT 0 COMMENT '十大股东持股比例合计(%)',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uk_code_date (code, report_date),
            INDEX idx_code (code),
            INDEX idx_report_date (report_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)
    conn.commit()
    cursor.close()
    conn.close()
    print("[机构持仓] 数据表已创建/确认")


def fetch_and_save_stock(code: str, conn):
    """拉取一只股票的所有季度数据并保存"""
    import akshare as ak

    prefix = 'sh' if code.startswith(('6', '9', '5', '68')) else 'sz'
    symbol = f"{prefix}{code}"

    cursor = conn.cursor()

    for report_date in REPORT_DATES:
        try:
            # Check if already synced
            cursor.execute(
                "SELECT id FROM stock_institutional_holdings WHERE code = %s AND report_date = %s",
                (code, report_date)
            )
            if cursor.fetchone():
                continue

            df = ak.stock_gdfx_top_10_em(symbol=symbol, date=report_date)
            if df is None or len(df) == 0:
                continue

            inst_ratio = 0.0
            total_ratio = 0.0

            for _, row in df.iterrows():
                name = str(row.get('股东名称', ''))
                ratio = row.get('占总股本持股比例', 0)
                try:
                    ratio = float(ratio) if ratio else 0
                except (ValueError, TypeError):
                    ratio = 0

                total_ratio += ratio
                if is_institution(name):
                    inst_ratio += ratio

            cursor.execute("""
                INSERT INTO stock_institutional_holdings (code, report_date, inst_ratio, total_ratio)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    inst_ratio = VALUES(inst_ratio),
                    total_ratio = VALUES(total_ratio)
            """, (code, report_date, round(inst_ratio, 4), round(total_ratio, 4)))

            time.sleep(0.3)  # Rate limiting

        except Exception as e:
            # Skip individual stock errors, log and continue
            pass

    cursor.close()
    return code


def sync_incremental(codes: list):
    """增量同步：只更新指定股票的机构持仓数据"""
    if not codes:
        print("[机构持仓] 增量同步：无股票需要更新")
        return

    print(f"[机构持仓] 增量同步：{len(codes)} 只股票")
    create_table()

    total = len(codes)
    processed = 0
    lock = threading.Lock()

    def process(code):
        nonlocal processed
        conn = get_db()
        try:
            result = fetch_and_save_stock(code, conn)
            conn.commit()
            with lock:
                processed += 1
                if processed % 50 == 0:
                    print(f"[机构持仓] 增量进度: {processed}/{total}")
            return result
        except Exception:
            return None
        finally:
            conn.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(process, codes))

    print(f"[机构持仓] 增量同步完成，处理 {processed} 只股票")


def sync_all(retry_failed_only=False):
    """全量同步所有股票的机构持仓数据"""
    print("[机构持仓] 开始同步...")

    create_table()

    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    # Get all stock codes
    if retry_failed_only:
        # Only retry stocks that have 0 rows or missing quarters
        cursor.execute("""
            SELECT s.code FROM stock_names s
            WHERE s.code NOT IN (
                SELECT DISTINCT code FROM stock_institutional_holdings
                GROUP BY code HAVING COUNT(*) >= 6
            )
            ORDER BY s.code
        """)
    else:
        cursor.execute("SELECT DISTINCT code FROM stock_names ORDER BY code")

    stock_codes = [r['code'] for r in cursor.fetchall()]
    cursor.close()
    conn.close()

    total = len(stock_codes)
    print(f"[机构持仓] 共 {total} 只股票需要同步")

    processed = 0
    lock = threading.Lock()

    def process(code):
        nonlocal processed
        conn = get_db()
        try:
            result = fetch_and_save_stock(code, conn)
            conn.commit()
            with lock:
                processed += 1
                if processed % 100 == 0:
                    print(f"[机构持仓] 进度: {processed}/{total}")
            return result
        except Exception:
            return None
        finally:
            conn.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(process, stock_codes))

    print(f"[机构持仓] 同步完成，处理 {processed} 只股票")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--retry', action='store_true', help='只重试失败的')
    parser.add_argument('--codes', type=str, default='', help='逗号分隔的股票代码列表（增量模式）')
    args = parser.parse_args()
    if args.codes:
        code_list = [c.strip() for c in args.codes.split(',') if c.strip()]
        sync_incremental(code_list)
    else:
        sync_all(retry_failed_only=args.retry)
