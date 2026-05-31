#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
风险数据更新
更新 stock_analysis 的 total_market_cap 和 dividend_count 字段
数据来源: akshare
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import akshare as ak
import time

from db import get_db


def get_market_cap(code):
    """获取总市值（单位：元）"""
    try:
        info = ak.stock_individual_info_em(symbol=code)
        if info is not None and len(info) > 0:
            mc_row = info[info['item'] == '总市值']
            if len(mc_row) > 0:
                val = mc_row.iloc[0]['value']
                if val and str(val) != 'nan':
                    return float(val)
    except Exception:
        pass
    return None


def get_dividend_count(code):
    """获取历史分红次数"""
    try:
        df = ak.stock_history_dividend_detail(symbol=code, indicator='分红')
        if df is not None and len(df) > 0:
            return len(df)
    except Exception:
        pass
    return 0


def update_risk_data(codes=None):
    """更新风险数据到 stock_analysis"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        if codes:
            stock_codes = codes
        else:
            cursor.execute("SELECT code FROM stock_names ORDER BY code")
            stock_codes = [r['code'] for r in cursor.fetchall()]

        print(f"[风险数据] 共 {len(stock_codes)} 只股票")

        updated = 0
        for i, code in enumerate(stock_codes):
            try:
                market_cap = get_market_cap(code)
                dividend_count = get_dividend_count(code)

                if market_cap is not None or dividend_count > 0:
                    cursor.execute("""
                        INSERT INTO stock_analysis (code, total_market_cap, dividend_count, created_at)
                        VALUES (%s, %s, %s, NOW())
                        ON DUPLICATE KEY UPDATE
                            total_market_cap = COALESCE(VALUES(total_market_cap), total_market_cap),
                            dividend_count = COALESCE(VALUES(dividend_count), dividend_count)
                    """, (code, market_cap, dividend_count))
                    updated += 1

                time.sleep(0.1)

            except Exception as e:
                pass

            if (i + 1) % 200 == 0:
                conn.commit()
                print(f"[风险数据] 进度: {i+1}/{len(stock_codes)} (更新 {updated})")

        conn.commit()
        print(f"[风险数据] 完成: 更新 {updated}/{len(stock_codes)}")

    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    update_risk_data()
