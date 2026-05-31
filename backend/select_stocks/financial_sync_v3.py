#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
财报数据同步 v3
全量/增量同步A股最新财报数据到 stock_financial_history 和 daily_financial_updates
数据来源: akshare.stock_financial_abstract_new_ths
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import akshare as ak
import pandas as pd
import time
from datetime import datetime

from db import get_db


def fetch_latest_financial(code):
    """获取单只股票最新财报数据"""
    result = {
        'report_date': None,
        'report_name': None,
        'net_profit_yoy': None,
        'net_profit_qoq': None,
        'roe': None
    }
    try:
        df = ak.stock_financial_abstract_new_ths(symbol=code)
        if df is None or len(df) == 0:
            return result

        df = df.sort_values('report_date', ascending=False)

        # 净利润数据
        net_profit_rows = df[df['metric_name'] == 'parent_holder_net_profit']
        if len(net_profit_rows) == 0:
            return result

        latest = net_profit_rows.iloc[0]
        result['report_date'] = str(latest['report_date'])[:10] if pd.notna(latest.get('report_date')) else None
        result['report_name'] = str(latest['report_name']) if pd.notna(latest.get('report_name')) else None

        # 净利润同比 (single_yoy)
        if pd.notna(latest.get('single_yoy')):
            yoy_val = float(latest['single_yoy']) * 100
            result['net_profit_yoy'] = f"{yoy_val:.2f}"

        # 净利润环比 (mom)
        if pd.notna(latest.get('mom')):
            mom_val = float(latest['mom']) * 100
            result['net_profit_qoq'] = f"{mom_val:.1f}%"

        # ROE
        roe_rows = df[df['metric_name'] == 'index_full_diluted_roe']
        if len(roe_rows) > 0:
            roe = roe_rows.iloc[0]
            if pd.notna(roe.get('value')):
                result['roe'] = str(round(float(roe['value']), 2))

    except Exception as e:
        print(f"[财务v3] {code} 获取失败: {e}")

    return result


def sync_financial_reports(mode='full'):
    """
    mode='full': 全量更新所有A股最新财报
    mode='incremental': 跳过今日已更新的股票
    """
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        # 获取股票列表
        if mode == 'incremental':
            cursor.execute("""
                SELECT DISTINCT code FROM daily_financial_updates
                WHERE DATE(created_at) = CURDATE()
            """)
            codes = [r['code'] for r in cursor.fetchall()]
            if not codes:
                print("[财务v3] 增量模式: 今日无需要更新的股票")
                return
            print(f"[财务v3] 增量模式: {len(codes)} 只股票")
        else:
            cursor.execute("SELECT code, name FROM stock_names ORDER BY code")
            rows = cursor.fetchall()
            codes = [r['code'] for r in rows]
            print(f"[财务v3] 全量模式: {len(codes)} 只股票")

        updated_fh = 0
        updated_du = 0
        today = datetime.now().strftime('%Y-%m-%d')

        for i, code in enumerate(codes):
            try:
                fin = fetch_latest_financial(code)
                if fin['report_date'] is None:
                    continue

                # 写入 stock_financial_history
                cursor.execute("""
                    INSERT INTO stock_financial_history (code, report_date, report_name, net_profit_yoy, net_profit_qoq, roe)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        report_name = VALUES(report_name),
                        net_profit_yoy = VALUES(net_profit_yoy),
                        net_profit_qoq = VALUES(net_profit_qoq),
                        roe = VALUES(roe)
                """, (code, fin['report_date'], fin['report_name'],
                      fin['net_profit_yoy'], fin['net_profit_qoq'], fin['roe']))
                updated_fh += 1

                # 写入 daily_financial_updates
                cursor.execute("""
                    INSERT INTO daily_financial_updates (code, report_date, report_name, net_profit_yoy, net_profit_qoq, updated_date)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        report_date = VALUES(report_date),
                        report_name = VALUES(report_name),
                        net_profit_yoy = VALUES(net_profit_yoy),
                        net_profit_qoq = VALUES(net_profit_qoq)
                """, (code, fin['report_date'], fin['report_name'],
                      fin['net_profit_yoy'], fin['net_profit_qoq'], today))
                updated_du += 1

                time.sleep(0.08)  # 避免请求过快

            except Exception as e:
                print(f"[财务v3] {code} 写入失败: {e}")

            if (i + 1) % 500 == 0:
                conn.commit()
                print(f"[财务v3] 进度: {i+1}/{len(codes)} (FH:{updated_fh}, DU:{updated_du})")

        conn.commit()
        print(f"[财务v3] 完成: stock_financial_history {updated_fh}, daily_financial_updates {updated_du}")

    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else 'full'
    sync_financial_reports(mode=mode)
