#!/usr/bin/env python3
"""
同步新规选股需要的财务数据 v2：
修复：营收和研发费用率改用年度（年报）数据
新增：三年营收CAGR、总市值（用于PS-TTM）、机构持股比例
"""
import sys
sys.path.insert(0, '/root/select_stocks')
import pymysql
import requests
from bs4 import BeautifulSoup
import time

from db import get_db

HEADERS = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}

def fetch_eastmoney(report_name, code, fields):
    url = 'https://datacenter.eastmoney.com/securities/api/data/v1/get'
    params = {
        'reportName': report_name,
        'columns': fields,
        'filter': f'(SECURITY_CODE="{code}")',
        'pageSize': 1,
        'sortColumns': 'REPORT_DATE',
        'sortTypes': -1,
        'source': 'HSF10',
        'client': 'PC',
    }
    try:
        r = requests.get(url, params=params, headers=HEADERS, timeout=15)
        d = r.json()
        if d.get('success') and d.get('result') and d['result'].get('data'):
            return d['result']['data'][0]
    except Exception:
        pass
    return None

def fetch_financial_data(code):
    """从akshare获取营收、同比增长率、资产负债率。
    返回: latest_rev(最新季报), annual_rev(最新年报), rev_3y_ago(3年前年报),
           yoy, debt, total_market_cap"""
    try:
        import akshare as ak
        df = ak.stock_financial_abstract_new_ths(symbol=code)
        if df is None or len(df) == 0:
            return None, None, None, None, None, None

        df = df.sort_values('report_date', ascending=False)

        # 最新季度营收
        rev_rows = df[df['metric_name'] == 'operating_income_total']
        latest_rev = None
        if len(rev_rows) > 0:
            v = rev_rows.iloc[0].get('value')
            if v and str(v) != 'nan':
                latest_rev = float(v)

        # 最新年报营收（report_name 包含 '年报'）
        annual_rev_rows = rev_rows[rev_rows['report_name'].str.contains('年报', na=False)]
        annual_rev = None
        rev_3y_ago = None
        if len(annual_rev_rows) >= 4:
            annual_rev = float(annual_rev_rows.iloc[0].get('value'))
            # 3年前年报营收
            rev_3y_ago = float(annual_rev_rows.iloc[3].get('value'))

        # 营收同比增长率（最新报告期）
        yoy = None
        yoy_report_date = None
        yoy_report_name = None
        yoy_rows = df[df['metric_name'] == 'calculate_operating_income_total_yoy_growth_ratio']
        if len(yoy_rows) > 0:
            v = yoy_rows.iloc[0].get('value')
            if v and str(v) != 'nan':
                yoy = float(v)
            rd = yoy_rows.iloc[0].get('report_date')
            if rd and str(rd) != 'nan':
                yoy_report_date = str(rd)[:10]
            rn = yoy_rows.iloc[0].get('report_name')
            if rn and str(rn) != 'nan':
                yoy_report_name = str(rn)

        # 资产负债率
        debt = None
        debt_rows = df[df['metric_name'] == 'assets_debt_ratio']
        if len(debt_rows) > 0:
            v = debt_rows.iloc[0].get('value')
            if v and str(v) != 'nan':
                debt = float(v)

        # 总市值
        market_cap = None
        try:
            info = ak.stock_individual_info_em(symbol=code)
            if info is not None and len(info) > 0:
                mc_row = info[info['item'] == '总市值']
                if len(mc_row) > 0:
                    val = mc_row.iloc[0]['value']
                    if val and str(val) != 'nan':
                        market_cap = float(val)
        except Exception:
            pass

        return latest_rev, annual_rev, rev_3y_ago, yoy, debt, market_cap, yoy_report_date, yoy_report_name
    except Exception:
        return None, None, None, None, None, None, None, None

def fetch_rd_expense_sina(code):
    """从新浪财经获取研发费用（上一财年年报数据）"""
    url = f'https://money.finance.sina.com.cn/corp/go.php/vFD_ProfitStatement/stockid/{code}/ctrl/part/displaytype/4.phtml'
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.encoding = 'gb2312'
        soup = BeautifulSoup(r.text, 'html.parser')

        tables = soup.find_all('table')
        for table in tables:
            rows = table.find_all('tr')
            for row in rows:
                cells = row.find_all('td')
                cell_texts = [c.get_text().strip() for c in cells]
                if cell_texts and '研发费用' in cell_texts[0]:
                    values = []
                    for ct in cell_texts[1:6]:
                        try:
                            values.append(float(ct.replace(',', '')) * 10000)
                        except:
                            values.append(0)
                    title_tag = soup.find('title')
                    if title_tag and '年报' in title_tag.get_text():
                        return values[0]
                    return values[1]  # FY previous annual
    except Exception:
        pass
    return None

def fetch_institutional_ownership():
    """获取机构持股比例（FY2024年报数据）"""
    try:
        import akshare as ak
        df = ak.stock_institute_hold(symbol='20244')  # FY2024 annual
        if df is None or len(df) == 0:
            return {}
        result = {}
        for _, row in df.iterrows():
            code = row['证券代码']
            ratio = row.get('持股比例')
            if ratio and str(ratio) != 'nan':
                result[code] = float(ratio)
        return result
    except Exception:
        return {}

def main(codes=None):
    """codes: 要更新的股票代码列表，为None则更新所有stock_names中股票"""
    conn = get_db()
    cursor = conn.cursor()

    if codes:
        stock_codes = codes
        print("[新规财务v2] 增量更新 {} 只股票".format(len(stock_codes)))
    else:
        cursor.execute("SELECT code FROM stock_names ORDER BY code")
        stock_codes = [r[0] for r in cursor.fetchall()]
        print("[新规财务v2] 共 {} 只股票".format(len(stock_codes)))

    # Pre-fetch institutional ownership for all stocks
    print("[新规财务v2] 获取机构持股数据(FY2024)...")
    inst_ownership = fetch_institutional_ownership()
    print("[新规财务v2] 机构持股数据: {} 只".format(len(inst_ownership)))

    updated = 0
    for i, code in enumerate(stock_codes):
        try:
            latest_rev, annual_rev, rev_3y_ago, yoy, debt, market_cap, yoy_report_date, yoy_report_name = fetch_financial_data(code)

            # EastMoney: operating cash flow
            cf_data = fetch_eastmoney('RPT_DMSK_FN_CASHFLOW', code, 'NETCASH_OPERATE,REPORT_DATE')
            cash_flow = None
            if cf_data and cf_data.get('NETCASH_OPERATE') is not None:
                cash_flow = float(cf_data['NETCASH_OPERATE'])

            # Sina: R&D expense (annual)
            rd_expense = fetch_rd_expense_sina(code)

            # R&D ratio = annual R&D / annual revenue
            rd_ratio = None
            if rd_expense and annual_rev and annual_rev > 0:
                rd_ratio = round(rd_expense / annual_rev * 100, 2)

            # 3-year revenue CAGR
            rev_cagr_3y = None
            if annual_rev and rev_3y_ago and rev_3y_ago > 0:
                rev_cagr_3y = round(((annual_rev / rev_3y_ago) ** (1/3) - 1) * 100, 2)

            # Institutional ownership
            inst_ratio = inst_ownership.get(code)

            # Write to stock_analysis
            revenue_str = "{:.2f}亿".format(annual_rev/1e8) if annual_rev else None
            cursor.execute("""
                INSERT INTO stock_analysis (code, selection_type, debt_ratio, operating_cash_flow,
                    revenue, rd_ratio, rd_expense, total_market_cap,
                    rev_cagr_3y, inst_ownership, financial_updated_at, created_at)
                VALUES (%s, 'standard', %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                debt_ratio = COALESCE(VALUES(debt_ratio), debt_ratio),
                operating_cash_flow = COALESCE(VALUES(operating_cash_flow), operating_cash_flow),
                revenue = COALESCE(VALUES(revenue), revenue),
                rd_ratio = COALESCE(VALUES(rd_ratio), rd_ratio),
                rd_expense = COALESCE(VALUES(rd_expense), rd_expense),
                total_market_cap = COALESCE(VALUES(total_market_cap), total_market_cap),
                rev_cagr_3y = COALESCE(VALUES(rev_cagr_3y), rev_cagr_3y),
                inst_ownership = COALESCE(VALUES(inst_ownership), inst_ownership),
                financial_updated_at = NOW()
            """, (code, debt, cash_flow, revenue_str,
                  rd_ratio, rd_expense, market_cap,
                  rev_cagr_3y, inst_ratio))
            updated += 1

            # Write yoy to stock_financial_history using actual report_date from akshare
            if yoy is not None and yoy_report_date is not None:
                cursor.execute("""
                    INSERT INTO stock_financial_history (code, revenue_yoy, report_date, report_name)
                    VALUES (%s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                    revenue_yoy = VALUES(revenue_yoy),
                    report_name = COALESCE(VALUES(report_name), report_name)
                """, (code, "{}%".format(yoy), yoy_report_date, yoy_report_name))

        except Exception:
            pass

        if (i + 1) % 200 == 0:
            print("  进度: {}/{} (更新{})".format(i+1, len(stock_codes), updated))
        time.sleep(0.1)

    print("[新规财务v2] 完成: 更新 {}/{}".format(updated, len(stock_codes)))

    # Verify
    cursor.execute("""
        SELECT COUNT(*) as t, SUM(rd_ratio IS NOT NULL) as rd,
               SUM(total_market_cap IS NOT NULL) as mc
        FROM stock_analysis
    """)
    r = cursor.fetchone()
    print("[新规财务v2] 统计: R&D {}/{}, 市值 {}/{}".format(r[1], r[0], r[2], r[0]))

    cursor.close()
    conn.close()

if __name__ == '__main__':
    main()
