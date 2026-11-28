-- 021_contact_messages.sql (MariaDB / MySQL)
-- Messages sent through the contact form (signed-in users and visitors).
-- Additive only: one new table.

CREATE TABLE IF NOT EXISTS contact_messages (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    user_id       INT NULL,
    name          VARCHAR(120) NOT NULL,
    email         VARCHAR(255) NOT NULL,
    phone         VARCHAR(40)  NULL,
    topic         VARCHAR(40)  NULL,
    message       TEXT         NOT NULL,
    status        VARCHAR(16)  NOT NULL DEFAULT 'new',
    admin_note    TEXT         NULL,
    handled_by    INT          NULL,
    handled_at    VARCHAR(64)  NULL,
    ip_address    VARCHAR(64)  NULL,
    country       VARCHAR(8)   NULL,
    city          VARCHAR(128) NULL,
    device        VARCHAR(128) NULL,
    page          VARCHAR(255) NULL,
    visitor_id    VARCHAR(64)  NULL,
    created_at    VARCHAR(64)  NOT NULL,

    INDEX idx_contact_status  (status),
    INDEX idx_contact_created (created_at),
    INDEX idx_contact_user    (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
