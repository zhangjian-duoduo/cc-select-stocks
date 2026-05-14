#!/usr/bin/env python3
"""
新规选股逻辑 (8个条件，必须全部满足):
第一层：安全过滤
  1. 上市 > 6个月
  2. 非ST / 非*ST
第二层：核心成长创新
  3. 营业收入 ≥ 5亿
  4. 营收同比增长率 ≥ 25%
  5. 研发费用率 ≥ 10%
  6. 资产负债率 ≤ 60%
  7. 经营性现金流 > 0
第三层：行业属性
  8. 属于六大新兴产业/未来产业

审计意见（标准无保留）= 暂不实现，实际95%+非ST公司都满足
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import requests
import time
from datetime import datetime, timedelta


DB_CONFIG = {
    'host': 'localhost', 'user': 'root', 'password': '',
    'database': 'select_stocks', 'charset': 'utf8mb4',
    'autocommit': True
}

EMERGING_CONCEPT_KEYWORDS = [
    '人工智能', '人形机器人', '机器人', '新能源', '新能源汽车',
    '集成电路', '半导体', '国产芯片', '汽车芯片', '第三代半导体',
    '航空航天', '军工', '卫星导航', '低空经济',
    '生物医药', '创新药', '医疗器械',
    '量子科技', '量子通信',
    '脑机接口',
    '6G', '5G',
    '新型储能', '储能', '氢能',
    '智能机器人', '机器视觉', '传感器',
    '新材料', '碳纤维',
    '工业互联网', '工业母机',
    '云计算', '大数据', '数字经济',
    '信创', '国产软件',
    '光伏', '风电',
]

def is_st_stock(stock_name):
    name_upper = str(stock_name).upper()
    for keyword in ["ST", "*ST", "S*ST", "SST"]:
        if keyword in name_upper:
            return True
    return False

def get_db():
    return pymysql.connect(**DB_CONFIG)

def get_listed_days(code, cursor):
    cursor.execute("""
        SELECT MIN(date) as earliest FROM stock_kline
        WHERE code = %s AND period = 'daily'
    """, (code,))
    r = cursor.fetchone()
    if r and r[0]:
        return (datetime.now().date() - r[0]).days
    return 0

def get_financial_data(code, cursor):
    cursor.execute("""
        SELECT debt_ratio, operating_cash_flow, revenue, rd_ratio
        FROM stock_analysis WHERE code = %s
    """, (code,))
    r = cursor.fetchone()
    if r:
        return {
            'debt_ratio': r[0],
            'operating_cash_flow': r[1],
            'revenue': r[2],
            'rd_ratio': r[3],
        }
    return None

def get_revenue_yoy(code, cursor):
    cursor.execute("""
        SELECT revenue_yoy FROM stock_financial_history
        WHERE code = %s AND revenue_yoy IS NOT NULL
        ORDER BY report_date DESC LIMIT 1
    """, (code,))
    r = cursor.fetchone()
    if r and r[0]:
        try:
            val = str(r[0]).replace('%', '').replace('+', '').strip()
            return float(val)
        except:
            pass
    return None

def parse_revenue_yi(revenue_str):
    if not revenue_str:
        return 0
    try:
        s = str(revenue_str).strip()
        if '亿' in s:
            return float(s.replace('亿', ''))
        elif '万' in s:
            return float(s.replace('万', '')) / 10000
        else:
            return float(s) / 1e8
    except:
        return 0

def has_emerging_concept(code, cursor):
    cursor.execute("""
        SELECT concept_name FROM stock_concepts WHERE code = %s
    """, (code,))
    concepts = [r[0] for r in cursor.fetchall()]
    for c in concepts:
        for kw in EMERGING_CONCEPT_KEYWORDS:
            if kw in c:
                return True, c
    return False, ''

def run_selection():
    conn = get_db()
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT code, name FROM stock_names ORDER BY code")
        all_stocks = [(r[0], r[1]) for r in cursor.fetchall()]
        print(f"[新规选股] 候选池：{len(all_stocks)} 只全A股")

        selected = []
        stats = {
            'total': len(all_stocks), 'listed_ok': 0, 'st_ok': 0,
            'revenue_ok': 0, 'yoy_ok': 0, 'rd_ratio_ok': 0,
            'debt_ok': 0, 'cashflow_ok': 0, 'concept_ok': 0
        }

        for i, (code, name) in enumerate(all_stocks):
            # 1: Listed > 180 days
            days = get_listed_days(code, cursor)
            if days < 180:
                continue
            stats['listed_ok'] += 1

            # 2: Non-ST
            if is_st_stock(name):
                continue
            stats['st_ok'] += 1

            # Get financial data
            fin = get_financial_data(code, cursor)
            if not fin:
                continue

            # 3: Revenue >= 5亿
            rev_yi = parse_revenue_yi(fin.get('revenue'))
            if rev_yi < 5:
                continue
            stats['revenue_ok'] += 1

            # 4: Revenue YoY >= 25%
            yoy = get_revenue_yoy(code, cursor)
            if yoy is None or yoy < 25:
                continue
            stats['yoy_ok'] += 1

            # 5: R&D ratio >= 10%
            rd_ratio = fin.get('rd_ratio')
            if rd_ratio is None or rd_ratio < 10:
                continue
            stats['rd_ratio_ok'] += 1

            # 6: Debt ratio <= 60%
            debt = fin.get('debt_ratio')
            if debt is None or debt > 60:
                continue
            stats['debt_ok'] += 1

            # 7: Operating cash flow > 0
            cf = fin.get('operating_cash_flow')
            if cf is None or cf <= 0:
                continue
            stats['cashflow_ok'] += 1

            # 8: Emerging concept
            has_concept, matched_concept = has_emerging_concept(code, cursor)
            if not has_concept:
                continue
            stats['concept_ok'] += 1

            selected.append({
                'code': code,
                'name': name,
                'revenue_yi': rev_yi,
                'yoy': yoy,
                'rd_ratio': rd_ratio,
                'debt_ratio': debt,
                'cash_flow_yi': float(cf) / 1e8 if cf else 0,
                'concept': matched_concept,
            })

            if (i + 1) % 500 == 0:
                print(f"  扫描: {i+1}/{len(all_stocks)} (入选{len(selected)})")

        conn.close()
        return selected, stats

    finally:
        try:
            conn.close()
        except:
            pass

def save_results(selected):
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM stocks WHERE selection_type = 'new_rule'")
        print(f"[新规选股] 清除旧数据: {cursor.rowcount} 条")
        cursor.execute("DELETE FROM stock_analysis WHERE selection_type = 'new_rule'")
        print(f"[新规选股] 清除旧分析: {cursor.rowcount} 条")

        today = datetime.now().date()
        for s in selected:
            cursor.execute("""
                INSERT INTO stocks (code, name, price, change_pct, selected_at, selection_type)
                VALUES (%s, %s, 0, 0, %s, 'new_rule')
            """, (s['code'], s['name'], today))

        conn.commit()
        print(f"[新规选股] 保存 {len(selected)} 只新规股票")
    finally:
        cursor.close()
        conn.close()

def main():
    print("=" * 50)
    print("[新规选股] 开始执行 (8条件: 上市>6月 + 非ST + 营收≥5亿 + 营收YoY≥25% + 研发费用率≥10% + 负债率≤60% + 经营现金流>0 + 新兴产业概念)...")

    selected, stats = run_selection()

    print(f"\n[新规选股] 筛选统计:")
    print(f"  候选池: {stats['total']} 只")
    print(f"  1. 上市>6月: {stats['listed_ok']}")
    print(f"  2. 非ST: {stats['st_ok']}")
    print(f"  3. 营收≥5亿: {stats['revenue_ok']}")
    print(f"  4. 营收同比≥25%: {stats['yoy_ok']}")
    print(f"  5. 研发费用率≥10%: {stats['rd_ratio_ok']}")
    print(f"  6. 资产负债率≤60%: {stats['debt_ok']}")
    print(f"  7. 经营现金流>0: {stats['cashflow_ok']}")
    print(f"  8. 新兴产业概念: {stats['concept_ok']}")
    print(f"  最终入选: {len(selected)} 只")

    if selected:
        print(f"\n入选股票 ({len(selected)} 只):")
        for s in sorted(selected, key=lambda x: x['revenue_yi'], reverse=True):
            print(f"  {s['code']} {s['name']}: 营收{s['revenue_yi']:.1f}亿 YoY{s['yoy']:.1f}% RD{s['rd_ratio']:.1f}% 负债率{s['debt_ratio']:.1f}% 概念:{s['concept']}")

    save_results(selected)
    print("[新规选股] 完成!")

if __name__ == '__main__':
    main()
