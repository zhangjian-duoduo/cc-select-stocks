#!/usr/bin/env python3
"""更新股票财务数据和板块信息"""
import sys
sys.path.insert(0, '/root/select_stocks')

import pymysql
import pandas as pd
import akshare as ak
import json
import time

from db import get_db

def update_financial_data(codes=None):
    """从akshare获取财务数据并更新到数据库。
    codes: 要更新的股票代码列表，为None则更新所有stocks表中的股票"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        if codes:
            stocks = [{'code': c} for c in codes]
            print(f"增量更新 {len(stocks)} 只有财报更新的股票")
        else:
            cursor.execute("SELECT code FROM stocks")
            stocks = cursor.fetchall()
            print(f"共 {len(stocks)} 只股票需要更新财务数据")

        updated = 0
        for i, stock in enumerate(stocks):
            code = stock['code']
            try:
                # 获取财务摘要数据
                df = ak.stock_financial_abstract_ths(symbol=code)
                if df is not None and len(df) > 0:
                    # 按日期从新到旧排序
                    df['报告期'] = pd.to_datetime(df['报告期'], errors='coerce')
                    df = df.sort_values('报告期', ascending=False)

                    # 取最新一期年报(12月31日)
                    latest = None
                    for _, row in df.iterrows():
                        period = str(row.get('报告期', ''))
                        roe_val = row.get('净资产收益率-摊薄')
                        # 跳过False和空值
                        if roe_val and roe_val != False and '-12-31' in period:
                            latest = row
                            break
                    # 如果没有年报，用最新的有数据的
                    if latest is None:
                        for _, row in df.iterrows():
                            if row.get('净资产收益率-摊薄') and row.get('净资产收益率-摊薄') != False:
                                latest = row
                                break
                    if latest is None:
                        latest = df.iloc[0]

                    # 净利润同比
                    net_profit_yoy = ''
                    yoy_raw = latest.get('净利润同比增长率')
                    if yoy_raw is not None and yoy_raw != False:
                        net_profit_yoy = str(yoy_raw).replace('%', '')

                    # ROE (净资产收益率)
                    roe = ''
                    roe_raw = latest.get('净资产收益率')
                    if roe_raw is not None and roe_raw != False:
                        roe = str(roe_raw).replace('%', '')
                    else:
                        # 尝试获取净资产收益率-摊薄
                        roe_raw = latest.get('净资产收益率-摊薄')
                        if roe_raw is not None and roe_raw != False:
                            roe = str(roe_raw).replace('%', '')

                    # 净利润环比 (需要计算)
                    net_profit_qoq = ''
                    if len(df) > 1:
                        prev = df.iloc[1]
                        curr_net = latest.get('净利润', '0')
                        prev_net = prev.get('净利润', '0')
                        try:
                            # 转换为数值
                            def parse_money(val):
                                val = str(val)
                                num = float(val.replace('亿', '').replace('万', '').replace('元', ''))
                                if '亿' in val:
                                    num *= 10000
                                return num
                            curr_val = parse_money(curr_net)
                            prev_val = parse_money(prev_net)
                            if prev_val != 0:
                                qoq = (curr_val - prev_val) / abs(prev_val) * 100
                                net_profit_qoq = f"{qoq:.1f}%"
                        except:
                            pass

                    # 营业收入
                    revenue = ''
                    revenue_raw = latest.get('营业总收入')
                    if revenue_raw is not None and revenue_raw != False:
                        revenue = str(revenue_raw)

                    # 每股净资产
                    book_value_per_share = ''
                    bv_raw = latest.get('每股净资产')
                    if bv_raw is not None and bv_raw != False:
                        book_value_per_share = str(bv_raw)

                # 获取板块信息
                sector = ''
                try:
                    info_df = ak.stock_individual_info_em(symbol=code)
                    sector_row = info_df[info_df['item'] == '行业']
                    if not sector_row.empty:
                        sector = str(sector_row.iloc[0]['value'])
                except:
                    pass

                # 更新数据库
                cursor.execute("""
                    INSERT INTO stock_analysis (code, net_profit_yoy, net_profit_qoq, revenue, book_value_per_share, roe, sector, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                    ON DUPLICATE KEY UPDATE
                        net_profit_yoy = VALUES(net_profit_yoy),
                        net_profit_qoq = VALUES(net_profit_qoq),
                        revenue = VALUES(revenue),
                        book_value_per_share = VALUES(book_value_per_share),
                        roe = VALUES(roe),
                        sector = VALUES(sector),
                        created_at = NOW()
                """, (code, net_profit_yoy, net_profit_qoq, revenue, book_value_per_share, roe, sector))

                conn.commit()
                updated += 1

                if (i + 1) % 10 == 0:
                    print(f"已更新 {i+1}/{len(stocks)}")

                time.sleep(0.5)  # 避免请求过快

            except Exception as e:
                print(f"股票 {code} 更新失败: {e}")
                continue

        print(f"财务数据更新完成，共更新 {updated} 只股票")

    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    update_financial_data()
