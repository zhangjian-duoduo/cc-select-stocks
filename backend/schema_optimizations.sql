-- ============================================================
-- Schema优化建议
-- 解决 CONVERT(code USING utf8mb4) 和索引缺失导致的性能问题
-- ============================================================

-- ============================================================
-- 1. 关键性能索引（高优先级，应立即执行）
-- ============================================================

-- stock_kline 表最大（300万+行），高频查询模式:
--   WHERE code=? AND period='daily' ORDER BY date DESC LIMIT 60
ALTER TABLE stock_kline ADD INDEX idx_code_period_date (code, period, date);

-- stock_financial_history 高频查询模式:
--   WHERE code=? ORDER BY report_date DESC LIMIT 1
ALTER TABLE stock_financial_history ADD INDEX idx_code_report_date (code, report_date);

-- stock_history 变化查询模式:
--   WHERE selected_at=? / GROUP BY selected_at
ALTER TABLE stock_history ADD INDEX idx_selected_at (selected_at);

-- stock_removed 日期查询:
ALTER TABLE stock_removed ADD INDEX idx_removed_at (removed_at);

-- daily_financial_updates:
ALTER TABLE daily_financial_updates ADD INDEX idx_updated_date (updated_date);

-- ============================================================
-- 2. 字符集统一（消除 CONVERT，推荐执行方案A）
-- ============================================================

-- 方案A：统一字符集（推荐，一劳永逸）
-- 在执行前建议先备份相关表

-- ALTER TABLE stock_names MODIFY code VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- ALTER TABLE stock_kline MODIFY code VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- ALTER TABLE daily_financial_updates MODIFY code VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 方案B：添加函数索引（MySQL 8.0.13+支持，无需改表结构）
-- 如果无法修改列定义，可添加函数索引优化查询

-- CREATE INDEX idx_stock_names_code_utf8 ON stock_names ((CONVERT(code USING utf8mb4)));
-- CREATE INDEX idx_daily_financial_updates_code_utf8 ON daily_financial_updates ((CONVERT(code USING utf8mb4)));

-- 验证字符集差异（排查问题用）
-- SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_SET_NAME, COLLATION_NAME
-- FROM information_schema.COLUMNS
-- WHERE TABLE_SCHEMA = 'select_stocks' AND COLUMN_NAME = 'code'
-- ORDER BY TABLE_NAME;

-- ============================================================
-- 3. 财务数据格式优化
-- net_profit_yoy 当前存储为 "15.5%" 字符串，建议增加数值列
-- ============================================================

-- ALTER TABLE stock_financial_history
--   ADD COLUMN net_profit_yoy_num DECIMAL(10,2)
--     GENERATED ALWAYS AS (CAST(REPLACE(REPLACE(net_profit_yoy, '%', ''), '+', '') AS DECIMAL(10,2))) STORED;
-- ALTER TABLE stock_financial_history
--   ADD COLUMN net_profit_qoq_num DECIMAL(10,2)
--     GENERATED ALWAYS AS (CAST(REPLACE(REPLACE(net_profit_qoq, '%', ''), '+', '') AS DECIMAL(10,2))) STORED;
-- CREATE INDEX idx_fin_yoy_num ON stock_financial_history(net_profit_yoy_num DESC);

-- ============================================================
-- 4. 历史数据定期清理（建议添加到定时任务中）
-- ============================================================

-- 保留最近90天的 stock_history
-- DELETE FROM stock_history WHERE selected_at < DATE_SUB(CURDATE(), INTERVAL 90 DAY);

-- 保留最近180天的 stock_removed
-- DELETE FROM stock_removed WHERE removed_at < DATE_SUB(CURDATE(), INTERVAL 180 DAY);

-- ============================================================
-- 5. 生产环境连接池配置
-- 建议安装 DBUtils 并使用连接池替代每次新建连接:
--   pip install DBUtils
-- 然后在 get_db() 中:
--   from dbutils.pooled_db import PooledDB
--   pool = PooledDB(pymysql, mincached=2, maxcached=10, maxconnections=20, **DB_CONFIG)
--   def get_db():
--       return pool.connection()
-- ============================================================
