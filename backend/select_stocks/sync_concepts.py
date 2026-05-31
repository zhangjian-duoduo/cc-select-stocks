#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
概念板块同步
- sync_concept_mapping: 同步股票-概念板块映射 (周一执行)
- sync_daily_concept_performance: 同步概念板块每日表现 (每日执行)
数据来源: akshare
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import akshare as ak
import pandas as pd
import time
from datetime import datetime

from db import get_db


def sync_concept_mapping():
    """同步所有概念板块及其成分股映射 (周一执行)"""
    conn = get_db()
    cursor = conn.cursor()

    try:
        print("[概念映射] 开始同步...")

        # 获取所有概念板块名称
        concept_df = ak.stock_board_concept_name_em()
        if concept_df is None or len(concept_df) == 0:
            print("[概念映射] 获取概念列表失败")
            return

        # 标记所有旧映射为非活跃
        cursor.execute("UPDATE stock_concepts SET is_active = 0")
        conn.commit()

        total_concepts = len(concept_df)
        total_stocks = 0

        for i, (_, row) in enumerate(concept_df.iterrows()):
            concept_name = row.get('板块名称', '')
            if not concept_name:
                continue

            try:
                # 获取该概念的成分股
                cons_df = ak.stock_board_concept_cons_em(symbol=concept_name)
                if cons_df is None or len(cons_df) == 0:
                    continue

                for _, stock_row in cons_df.iterrows():
                    stock_code = str(stock_row.get('代码', ''))
                    stock_name = str(stock_row.get('名称', ''))

                    if not stock_code:
                        continue

                    cursor.execute("""
                        INSERT INTO stock_concepts (code, concept_name, is_active)
                        VALUES (%s, %s, 1)
                        ON DUPLICATE KEY UPDATE is_active = 1
                    """, (stock_code, concept_name))
                    total_stocks += 1

            except Exception as e:
                pass

            time.sleep(0.1)

            if (i + 1) % 50 == 0:
                conn.commit()
                print(f"[概念映射] 进度: {i+1}/{total_concepts} 个概念")

        conn.commit()
        print(f"[概念映射] 完成: {total_concepts} 个概念, {total_stocks} 条映射")

    finally:
        cursor.close()
        conn.close()


def sync_daily_concept_performance():
    """同步概念板块每日表现 (每日执行)"""
    conn = get_db()
    cursor = conn.cursor()

    try:
        today = datetime.now().strftime('%Y-%m-%d')
        print(f"[概念表现] 开始同步 ({today})...")

        # 获取概念板块当日行情
        df = ak.stock_board_concept_hist_em(symbol='概念指数', period='daily',
                                              start_date=today.replace('-', ''),
                                              end_date=today.replace('-', ''))
        if df is None or len(df) == 0:
            # 回退：获取当日所有概念板块实时数据
            df = ak.stock_board_concept_name_em()
            if df is None or len(df) == 0:
                print("[概念表现] 无概念数据")
                return

        updated = 0
        for _, row in df.iterrows():
            try:
                concept_name = row.get('板块名称', row.get('名称', ''))
                change_pct = row.get('涨跌幅', row.get('最新价', 0))

                if not concept_name:
                    continue

                cursor.execute("""
                    INSERT INTO daily_concept_performance (date, concept_name, change_pct)
                    VALUES (%s, %s, %s)
                    ON DUPLICATE KEY UPDATE change_pct = VALUES(change_pct)
                """, (today, concept_name, float(change_pct) if change_pct else 0))
                updated += 1

            except Exception:
                pass

        conn.commit()
        print(f"[概念表现] 完成: {updated} 个概念")

    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'mapping':
        sync_concept_mapping()
    elif len(sys.argv) > 1 and sys.argv[1] == 'daily':
        sync_daily_concept_performance()
    else:
        sync_daily_concept_performance()
        sync_concept_mapping()
