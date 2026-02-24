-- 012_results_whatsapp_columns_sqlite.sql
-- Add WhatsApp contact fields to scraping results (SQLite)

ALTER TABLE results ADD COLUMN whatsapp TEXT;
ALTER TABLE results ADD COLUMN whatsapp_url TEXT;
