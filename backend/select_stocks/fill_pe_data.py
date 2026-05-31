#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PE 数据填充
更新 stock_analysis 的 pe_ttm 和 pe_percentile 字段
数据来源: akshare + 本地 stock_kline 表
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import akshare as ak
import time
from datetime import datetime, timedelta

from db import get_db


def get_pe_ttm(code):
    """从 akshare 获取 PE-TTM"""
    try:
        df = ak.stock_a_pe(symbol=code)
        if df is not None and len(df) > 0:
            latest = df.iloc[-1]
            pe = latest.get('pe')
            if pe and str(pe) != 'nan':
                return float(pe)
    except Exception:
        pass
    return None


def get_price_series(code):
    """从 stock_kline 获取5年日K价格序列"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    try:
        start_date = (datetime.now() - timedelta(days=365 * 5)).strftime('%Y-%m-%d')
        cursor.execute("""
            SELECT date, close FROM stock_kline
            WHERE code = %s AND period = 'daily' AND date >= %s
            ORDER BY date
        """, (code, start_date))
        rows = cursor.fetchall()
        if rows:
            return [float(r['close']) for r in rows if r['close'] is not None]
    except Exception:
        pass
    finally:
        cursor.close()
        conn.close()
    return []


def calculate_pe_percentile(price_series, current_pe):
    """基于历史价格分布估算 PE 百分位"""
    if not price_series or current_pe is None:
        return None
    if current_pe <= 0:
        return 100.0  # 亏损 = 历史最高PE位置

    # 简化：用价格分布近似PE分布（PE = 价格 / EPS，同一股票EPS相对稳定）
    current_price = price_series[-1] if price_series else 0
    if current_price <= 0:
        return None

    # 计算有多少历史价格低于当前价格
    lower_count = sum(1 for p in price_series if p < current_price)
    percentile = lower_count / len(price_series) * 100
    return round(percentile, 2)


def update_pe_data(codes=None):
    """更新 PE 数据到 stock_analysis"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        if codes:
            stock_codes = codes
        else:
            cursor.execute("SELECT code FROM stock_names ORDER BY code")
            stock_codes = [r['code'] for r in cursor.fetchall()]

        print(f"[PE数据] 共 {len(stock_codes)} 只股票")

        updated = 0
        for i, code in enumerate(stock_codes):
            try:
                pe_ttm = get_pe_ttm(code)
                prices = get_price_series(code)
                pe_percentile = calculate_pe_percentile(prices, pe_ttm) if pe_ttm else None

                cursor.execute("""
                    INSERT INTO stock_analysis (code, pe_ttm, pe_percentile, created_at)
                    VALUES (%s, %s, %s, NOW())
                    ON DUPLICATE KEY UPDATE
                        pe_ttm = COALESCE(VALUES(pe_ttm), pe_ttm),
                        pe_percentile = COALESCE(VALUES(pe_percentile), pe_percentile)
                """, (code, pe_ttm, pe_percentile))
                updated += 1

                time.sleep(0.15)

            except Exception:
                pass

            if (i + 1) % 200 == 0:
                conn.commit()
                print(f"[PE数据] 进度: {i+1}/{len(stock_codes)} (更新 {updated})")

        conn.commit()
        print(f"[PE数据] 完成: 更新 {updated}/{len(stock_codes)}")

    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    update_pe_data()
