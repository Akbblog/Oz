-- 012_results_whatsapp_columns.sql
-- Add WhatsApp contact fields to scraping results (MySQL)

ALTER TABLE results ADD COLUMN whatsapp TEXT NULL;
ALTER TABLE results ADD COLUMN whatsapp_url TEXT NULL;
