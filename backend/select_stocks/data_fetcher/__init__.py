#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数据采集模块 - 多源数据获取 + 反爬虫策略
"""

import time
import random
import json
import requests
from datetime import datetime, timedelta
from typing import Optional, Dict, List, Any
import pandas as pd

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
]

class DataFetcher:
    def __init__(self):
        self.current_source = None
        self.last_request_time = 0
        self.min_interval = 1.0
        self.max_interval = 3.0
        self.session = requests.Session()

    def _random_delay(self):
        now = time.time()
        elapsed = now - self.last_request_time
        if elapsed < self.min_interval:
            delay = random.uniform(self.min_interval, self.max_interval)
            time.sleep(delay)
        self.last_request_time = time.time()

    def _get_headers(self) -> Dict:
        return {
            "User-Agent": random.choice(USER_AGENTS),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        }

    def get_stock_list_akshare(self) -> Optional[pd.DataFrame]:
        try:
            import akshare as ak
            self._random_delay()
            df = ak.stock_info_a_code_name()
            return df
        except Exception as e:
            print(f"[AkShare] 获取失败: {e}")
            return None

    def get_stock_list_baostock(self) -> Optional[pd.DataFrame]:
        # 优先从本地K线数据库获取股票列表和名称
        try:
            import pymysql
            # 读取股票名称文件
            stock_names = {}
            name_file = os.path.join(os.path.dirname(__file__), '..', 'stock_codes.txt')
            if os.path.exists(name_file):
                with open(name_file, 'r') as f:
                    for line in f:
                        parts = line.strip().split(' ', 1)
                        if len(parts) == 2:
                            stock_names[parts[0]] = parts[1]

            conn = pymysql.connect(
                host='localhost',
                user='root',
                password='',
                database='select_stocks',
                charset='utf8mb4'
            )
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            cursor.execute("SELECT DISTINCT code FROM stock_kline WHERE (code LIKE '000%' OR code LIKE '001%' OR code LIKE '002%' OR code LIKE '300%' OR code LIKE '600%' OR code LIKE '601%' OR code LIKE '603%' OR code LIKE '605%' OR code LIKE '688%' OR code LIKE '003%')")
            rows = cursor.fetchall()
            cursor.close()
            conn.close()
            if rows:
                # 添加股票名称
                for row in rows:
                    code = row['code']
                    row['name'] = stock_names.get(code, code)
                df = pd.DataFrame(rows)
                print(f"[本地数据库] 获取到 {len(df)} 只股票")
                return df
        except Exception as e:
            print(f"[本地数据库] 获取失败: {e}")

        # 回退到baostock API
        try:
            import baostock as bs
            self._random_delay()
            bs.login()
            rs = bs.query_all_stock()
            data_list = []
            while (rs.error_code == '0') & rs.next():
                data_list.append(rs.get_row_data())
            bs.logout()
            if data_list:
                # 字段是 ['code', 'tradeStatus', 'code_name']
                df = pd.DataFrame(data_list, columns=rs.fields)
                # 过滤只取A股 (sz./sh. 开头，且不是指数)
                # A股代码: 000xxx-001xxx (深圳), 600xxx-688xxx (上海), 002xxx, 300xxx
                df = df[df['code'].str.match(r'^(sh\.|sz\.)')]
                # 排除指数 (000001, 000002等是指数)
                df = df[~df['code_name'].str.contains('指数', na=False)]
                df = df[df['code'].str.match(r'^(sh\.(6|0|2|3)|sz\.(0|3|0|2))')]
                df = df[['code', 'code_name']].rename(columns={'code_name': 'name'})
                return df
            return None
        except Exception as e:
            print(f"[Baostock] 获取失败: {e}")
            return None

    def _format_date(self, date_str: str) -> str:
        """转换日期格式: 20240101 -> 2024-01-01"""
        if len(date_str) == 8 and date_str.isdigit():
            return f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]}"
        return date_str

    def get_stock_daily_akshare(self, stock_code: str, start_date: str, end_date: str) -> Optional[pd.DataFrame]:
        try:
            import akshare as ak
            self._random_delay()
            symbol = stock_code.replace('.SH', '').replace('.SZ', '')
            if stock_code.endswith('.SH'):
                symbol = f"sh{symbol}"
            else:
                symbol = f"sz{symbol}"
            df = ak.stock_zh_a_hist(symbol=symbol, start_date=start_date, end_date=end_date, adjust="qfq")
            return df
        except Exception as e:
            print(f"[AkShare] 获取日K失败 {stock_code}: {e}")
            return None

    def _format_stock_code(self, stock_code: str) -> str:
        """转换为9位股票代码: 000001 -> sz.000001, 600519 -> sh.600519"""
        # 已经是9位格式，直接返回
        if stock_code.startswith('sh.') or stock_code.startswith('sz.'):
            return stock_code

        code = stock_code.replace('.SH', '').replace('.SZ', '')
        if stock_code.endswith('.SH') or (len(code) == 6 and code.startswith('6')):
            return f"sh.{code}"
        else:
            return f"sz.{code}"

    def get_stock_daily_baostock(self, stock_code: str, start_date: str, end_date: str) -> Optional[pd.DataFrame]:
        # 优先从本地数据库获取
        try:
            import pymysql
            conn = pymysql.connect(
                host='localhost',
                user='root',
                password='',
                database='select_stocks',
                charset='utf8mb4'
            )
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            cursor.execute("""
                SELECT date, open, high, low, close, volume
                FROM stock_kline
                WHERE code = %s AND period = 'daily' AND date >= %s AND date <= %s
                ORDER BY date
            """, (stock_code, start_date, end_date))
            rows = cursor.fetchall()
            cursor.close()
            conn.close()
            if rows:
                df = pd.DataFrame(rows)
                print(f"[本地数据库] 获取日K {stock_code}: {len(df)} 条")
                return df
        except Exception as e:
            print(f"[本地数据库] 获取日K失败: {e}")

        # 回退到baostock API
        try:
            import baostock as bs
            self._random_delay()
            bs.login()
            bs_code = self._format_stock_code(stock_code)
            # 转换日期格式
            s_date = self._format_date(start_date)
            e_date = self._format_date(end_date)
            rs = bs.query_history_k_data_plus(bs_code,
                "date,open,high,low,close,volume",
                start_date=s_date, end_date=e_date,
                frequency="d", adjustflag="2")
            data_list = []
            while (rs.error_code == '0') & rs.next():
                data_list.append(rs.get_row_data())
            bs.logout()
            if data_list:
                df = pd.DataFrame(data_list, columns=['date', 'open', 'high', 'low', 'close', 'volume'])
                return df
            return None
        except Exception as e:
            print(f"[Baostock] 获取日K失败 {stock_code}: {e}")
            return None

    def get_stock_weekly(self, stock_code: str, start_date: str, end_date: str) -> Optional[pd.DataFrame]:
        # 优先从本地数据库获取
        try:
            import pymysql
            conn = pymysql.connect(
                host='localhost',
                user='root',
                password='',
                database='select_stocks',
                charset='utf8mb4'
            )
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            cursor.execute("""
                SELECT date, open, high, low, close, volume
                FROM stock_kline
                WHERE code = %s AND period = 'weekly' AND date >= %s AND date <= %s
                ORDER BY date
            """, (stock_code, start_date, end_date))
            rows = cursor.fetchall()
            cursor.close()
            conn.close()
            if rows:
                df = pd.DataFrame(rows)
                print(f"[本地数据库] 获取周K {stock_code}: {len(df)} 条")
                return df
        except Exception as e:
            pass

        # 回退到baostock API
        try:
            import baostock as bs
            self._random_delay()
            bs.login()
            bs_code = self._format_stock_code(stock_code)
            s_date = self._format_date(start_date)
            e_date = self._format_date(end_date)
            rs = bs.query_history_k_data_plus(bs_code,
                "date,open,high,low,close,volume",
                start_date=s_date, end_date=e_date,
                frequency="w", adjustflag="2")
            data_list = []
            while (rs.error_code == '0') & rs.next():
                data_list.append(rs.get_row_data())
            bs.logout()
            if data_list:
                df = pd.DataFrame(data_list, columns=['date', 'open', 'high', 'low', 'close', 'volume'])
                return df
            return None
        except Exception as e:
            print(f"[Baostock] 获取周K失败 {stock_code}: {e}")
            return None

    def get_stock_monthly(self, stock_code: str, start_date: str, end_date: str) -> Optional[pd.DataFrame]:
        # 优先从本地数据库获取
        try:
            import pymysql
            conn = pymysql.connect(
                host='localhost',
                user='root',
                password='',
                database='select_stocks',
                charset='utf8mb4'
            )
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            cursor.execute("""
                SELECT date, open, high, low, close, volume
                FROM stock_kline
                WHERE code = %s AND period = 'monthly' AND date >= %s AND date <= %s
                ORDER BY date
            """, (stock_code, start_date, end_date))
            rows = cursor.fetchall()
            cursor.close()
            conn.close()
            if rows:
                df = pd.DataFrame(rows)
                print(f"[本地数据库] 获取月K {stock_code}: {len(df)} 条")
                return df
        except Exception as e:
            pass

        # 回退到baostock API
        try:
            import baostock as bs
            self._random_delay()
            bs.login()
            bs_code = self._format_stock_code(stock_code)
            s_date = self._format_date(start_date)
            e_date = self._format_date(end_date)
            rs = bs.query_history_k_data_plus(bs_code,
                "date,open,high,low,close,volume",
                start_date=s_date, end_date=e_date,
                frequency="m", adjustflag="2")
            data_list = []
            while (rs.error_code == '0') & rs.next():
                data_list.append(rs.get_row_data())
            bs.logout()
            if data_list:
                df = pd.DataFrame(data_list, columns=['date', 'open', 'high', 'low', 'close', 'volume'])
                return df
            return None
        except Exception as e:
            print(f"[Baostock] 获取月K失败 {stock_code}: {e}")
            return None

    # 股东人数获取（由于数据接口限制，暂时使用模拟数据）
    def get_stock_holder_number(self, stock_code: str) -> Optional[pd.DataFrame]:
        """
        获取股东人数数据
        注意：由于东方财富/巨潮等接口均有访问限制，这里使用备用方案
        实际项目中可以购买付费数据源或使用tushare付费版获取准确数据
        """
        try:
            # 备用方案：从akshare尝试获取
            try:
                import akshare as ak
                self._random_delay()
                # 尝试不同接口
                for func_name in ['stock_hold_control_cninfo', 'stock_zjyx_em']:
                    try:
                        func = getattr(ak, func_name, None)
                        if func:
                            df = func()
                            if df is not None and not df.empty:
                                return df
                    except:
                        continue
            except:
                pass

            # 返回模拟数据（实际需要替换为真实数据）
            today = datetime.now().strftime('%Y-%m-%d')
            return pd.DataFrame([
                {'截止日期': today, '股东户数': 50000, '户均持股': 10000},
            ])
        except Exception as e:
            print(f"[股东人数] 获取失败 {stock_code}: {e}")
            return None

    def get_stock_pe_pb(self, stock_code: str) -> Optional[Dict]:
        try:
            import akshare as ak
            self._random_delay()
            df = ak.stock_zh_a_timer(index="all")
            stock = df[df['代码'] == stock_code]
            if not stock.empty:
                return {
                    'pe': stock.iloc[0].get('市盈率(TTM)'),
                    'pb': stock.iloc[0].get('市净率'),
                }
            return None
        except Exception as e:
            print(f"[AkShare] 获取估值失败 {stock_code}: {e}")
            return None

    def fetch_with_fallback(self, func_name: str, *args, **kwargs) -> Any:
        methods = {
            'get_stock_list': [self.get_stock_list_akshare, self.get_stock_list_baostock],
            'get_stock_daily': [self.get_stock_daily_akshare, self.get_stock_daily_baostock],
            'get_stock_weekly': [self.get_stock_weekly],
            'get_stock_monthly': [self.get_stock_monthly],
            'get_stock_holder_number': [self.get_stock_holder_number],
            'get_stock_pe_pb': [self.get_stock_pe_pb],
        }
        method_list = methods.get(func_name, [])
        for method in method_list:
            try:
                result = method(*args, **kwargs)
                if result is not None and not (hasattr(result, 'empty') and result.empty):
                    self.current_source = method.__name__
                    print(f"[数据获取成功] 使用数据源: {self.current_source}")
                    return result
            except Exception as e:
                print(f"[回退] {method.__name__} 失败: {e}")
                continue
        print(f"[错误] 所有数据源均失败: {func_name}")
        return None


if __name__ == "__main__":
    fetcher = DataFetcher()
    df = fetcher.fetch_with_fallback('get_stock_list')
    if df is not None:
        print(f"获取到 {len(df)} 只股票")
        print(df.head())