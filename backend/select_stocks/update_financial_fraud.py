#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
财务造假风险检测
通过抓取新浪财经资产负债表和利润表，计算常见造假指标
写入 stock_analysis.financial_fraud_risk (0=正常, 1=高风险)
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import requests
import re
import time
from bs4 import BeautifulSoup

from db import get_db

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
}


def parse_sina_number(s):
    """解析新浪财经数字（万元），返回元"""
    if not s:
        return 0
    s = s.strip().replace(',', '')
    try:
        return float(s) * 10000
    except ValueError:
        return 0


def scrape_profit_statement(code):
    """抓取利润表，返回 (营业收入, 净利润)"""
    url = f'https://vip.stock.finance.sina.com.cn/corp/go.php/vFD_ProfitStatement/stockid/{code}/ctrl/part/displaytype/4.phtml'
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.encoding = 'gb2312'
        soup = BeautifulSoup(r.text, 'html.parser')
        tables = soup.find_all('table')
        revenue = 0
        net_profit = 0
        for table in tables:
            rows = table.find_all('tr')
            for row in rows:
                cells = row.find_all('td')
                cell_texts = [c.get_text().strip() for c in cells]
                if not cell_texts:
                    continue
                if '营业总收入' in cell_texts[0] or '营业收入' in cell_texts[0]:
                    vals = [parse_sina_number(ct) for ct in cell_texts[1:6]]
                    if vals:
                        revenue = max(vals)
                if '净利润' in cell_texts[0] and '归属于母公司' not in str(cell_texts[0]):
                    vals = [parse_sina_number(ct) for ct in cell_texts[1:6]]
                    if vals:
                        net_profit = max(vals)
        return revenue, net_profit
    except Exception:
        return 0, 0


def scrape_balance_sheet(code):
    """抓取资产负债表，返回 (应收账款, 存货, 总资产)"""
    url = f'https://vip.stock.finance.sina.com.cn/corp/go.php/vFD_BalanceSheet/stockid/{code}/ctrl/part/displaytype/4.phtml'
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.encoding = 'gb2312'
        soup = BeautifulSoup(r.text, 'html.parser')
        tables = soup.find_all('table')
        receivables = 0
        inventory = 0
        total_assets = 0
        for table in tables:
            rows = table.find_all('tr')
            for row in rows:
                cells = row.find_all('td')
                cell_texts = [c.get_text().strip() for c in cells]
                if not cell_texts:
                    continue
                if '应收票据及应收账款' in cell_texts[0] or '应收账款' in cell_texts[0]:
                    vals = [parse_sina_number(ct) for ct in cell_texts[1:6]]
                    if vals:
                        receivables = max(vals)
                if '存货' in cell_texts[0] and '跌价' not in cell_texts[0]:
                    vals = [parse_sina_number(ct) for ct in cell_texts[1:6]]
                    if vals:
                        inventory = max(vals)
                if '资产总计' in cell_texts[0]:
                    vals = [parse_sina_number(ct) for ct in cell_texts[1:6]]
                    if vals:
                        total_assets = max(vals)
        return receivables, inventory, total_assets
    except Exception:
        return 0, 0, 0


def detect_fraud(code):
    """
    检测财务造假风险
    返回: risk_score (0-10), 是否高风险 (0/1)
    """
    revenue, net_profit = scrape_profit_statement(code)
    receivables, inventory, total_assets = scrape_balance_sheet(code)

    risk_flags = 0
    reasons = []

    # 指标1: 应收账款/营业收入 > 80%
    if revenue > 0 and receivables > 0:
        ratio = receivables / revenue
        if ratio > 0.8:
            risk_flags += 3
            reasons.append(f"应收账款是营收的{ratio:.0%}")

    # 指标2: 存货/总资产 > 40%
    if total_assets > 0 and inventory > 0:
        ratio = inventory / total_assets
        if ratio > 0.4:
            risk_flags += 2
            reasons.append(f"存货占总资产{ratio:.0%}")

    # 指标3: 收入为0或负
    if revenue <= 0:
        risk_flags += 2
        reasons.append("营业收入异常")

    # 指标4: 净利润为负但应收高
    if net_profit < 0 and receivables > 0 and revenue > 0 and receivables / revenue > 0.5:
        risk_flags += 3
        reasons.append("亏损+高应收")

    is_high_risk = 1 if risk_flags >= 4 else 0
    return is_high_risk


def main(codes=None):
    """检测所有股票的财务造假风险"""
    conn = get_db()
    cursor = conn.cursor(pymysql.cursors.DictCursor)

    try:
        if codes:
            stock_codes = codes
        else:
            cursor.execute("SELECT code FROM stock_names ORDER BY code")
            stock_codes = [r['code'] for r in cursor.fetchall()]

        print(f"[财务造假] 共 {len(stock_codes)} 只股票")

        updated = 0
        risky = 0
        for i, code in enumerate(stock_codes):
            try:
                risk = detect_fraud(code)
                if risk == 1:
                    risky += 1

                cursor.execute("""
                    INSERT INTO stock_analysis (code, financial_fraud_risk, created_at)
                    VALUES (%s, %s, NOW())
                    ON DUPLICATE KEY UPDATE
                        financial_fraud_risk = VALUES(financial_fraud_risk)
                """, (code, risk))
                updated += 1

                time.sleep(0.2)

            except Exception:
                pass

            if (i + 1) % 100 == 0:
                conn.commit()
                print(f"[财务造假] 进度: {i+1}/{len(stock_codes)} (更新 {updated}, 风险 {risky})")

        conn.commit()
        print(f"[财务造假] 完成: 总 {updated}, 高风险 {risky}")

    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    main()
