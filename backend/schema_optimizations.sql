-- ============================================================
-- Schema优化建议 (#20, #29)
-- 解决CONVERT(code USING utf8mb4)导致的性能问题
--
-- 问题：stock_names、stock_kline、daily_financial_updates
-- 表的code列字符集与其他表不一致，导致JOIN时需要CONVERT，
-- 阻止索引使用，造成全表扫描
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
