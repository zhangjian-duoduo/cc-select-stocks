#!/usr/bin/env python3
"""
检测资金占用：通过"其他应收款/总资产"比率判断
使用新浪财经资产负债表页面抓取数据
"""
import sys
sys.path.insert(0, '/root/select_stocks')

import pymysql
import requests
import re
import time

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'select_stocks',
    'charset': 'utf8mb4',
    'autocommit': True
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

def parse_sina_number(s):
    """解析新浪财经中的数字（万元），返回元"""
    if not s:
        return 0
    s = s.strip().replace(',', '')
    try:
        val_wan = float(s)
        return val_wan * 10000  # 万元→元
    except ValueError:
        return 0

def scrape_balance_sheet(code):
    """抓取新浪财经资产负债表，返回 (其他应收款元, 总资产元)"""
    url = f'https://vip.stock.finance.sina.com.cn/corp/go.php/vFD_BalanceSheet/stockid/{code}/ctrl/part/displaytype/4.phtml'
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    }
    try:
        r = requests.get(url, headers=headers, timeout=30)
        r.encoding = 'gbk'
        html = r.text

        other_receivable = 0
        total_assets = 0

        # 匹配 其他应收款(合计) 行 - 提取第一个数值（最新一期）
        m = re.search(r'其他应收款\(合计\).*?<td[^>]*>([\d,.-]+)</td>', html, re.DOTALL)
        if m:
            other_receivable = parse_sina_number(m.group(1))

        # 匹配 资产总计 行
        m = re.search(r'资产总计.*?<td[^>]*>([\d,.-]+)</td>', html, re.DOTALL)
        if m:
            total_assets = parse_sina_number(m.group(1))

        return other_receivable, total_assets
    except Exception as e:
        print(f"  {code}: 抓取失败 - {e}")
        return 0, 0

def main(codes=None):
    """codes: 要检测的股票代码列表，为None则检测所有stocks表中股票"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        if codes:
            all_codes = codes
            print(f"增量检测 {len(all_codes)} 只股票")
        else:
            cursor.execute("SELECT code FROM stocks ORDER BY code")
            all_codes = [s['code'] for s in cursor.fetchall()]
            print(f"共 {len(all_codes)} 只股票")

        updated = 0
        failed = 0

        for i, code in enumerate(all_codes):
            other, total = scrape_balance_sheet(code)

            if total > 0 and other > 0:
                ratio = other / total * 100
                risk_flag = 1 if (ratio > 30 and other > 200_000_000) else 0

                cursor.execute("""
                    INSERT INTO stock_analysis (code, other_receivables_ratio, fund_embezzlement_risk, created_at)
                    VALUES (%s, %s, %s, NOW())
                    ON DUPLICATE KEY UPDATE
                        other_receivables_ratio = VALUES(other_receivables_ratio),
                        fund_embezzlement_risk = VALUES(fund_embezzlement_risk)
                """, (code, round(ratio, 2), risk_flag))
                updated += 1

                if risk_flag:
                    print(f"  ⚠️ {code}: ratio={ratio:.1f}%, other={other/10000:.0f}万, total={total/10000:.0f}万 ***高风险***")
                elif (i + 1) % 50 == 0:
                    print(f"  {code}: ratio={ratio:.1f}% [{i+1}/{len(all_codes)}]")
            elif total > 0:
                ratio = 0
                risk_flag = 0
                cursor.execute("""
                    INSERT INTO stock_analysis (code, other_receivables_ratio, fund_embezzlement_risk, created_at)
                    VALUES (%s, %s, %s, NOW())
                    ON DUPLICATE KEY UPDATE
                        other_receivables_ratio = VALUES(other_receivables_ratio),
                        fund_embezzlement_risk = VALUES(fund_embezzlement_risk)
                """, (code, round(ratio, 2), risk_flag))
                updated += 1
            else:
                failed += 1
                print(f"  {code}: 数据为空 [{i+1}/{len(all_codes)}]")

            time.sleep(0.3)  # 避免被封

        conn.commit()
        print(f"\n资金占用检测完成：更新 {updated} 只，失败 {failed} 只")

        # 显示风险股票
        if updated > 0:
            cursor.execute("""
                SELECT s.code, s.name, a.other_receivables_ratio
                FROM stock_analysis a
                JOIN stocks s ON a.code = s.code
                WHERE a.fund_embezzlement_risk = 1
            """)
            risky = cursor.fetchall()
            if risky:
                print(f"\n高风险股票 ({len(risky)} 只)：")
                for r in risky:
                    print(f"  {r['code']} {r['name']}: {r['other_receivables_ratio']}%")
            else:
                print("\n无高风险股票")

    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    main()
