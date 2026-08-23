-- ============================================================
-- Digital Payments Transaction Intelligence - Schema
-- ============================================================

CREATE TABLE users (
    user_id             INT PRIMARY KEY,
    signup_date         DATE NOT NULL,
    city                VARCHAR(50),
    state               VARCHAR(50),
    acquisition_channel VARCHAR(50),
    age_bucket          VARCHAR(10),
    kyc_status          VARCHAR(20),
    is_churned          BOOLEAN
);

CREATE TABLE merchants (
    merchant_id     INT PRIMARY KEY,
    merchant_name   VARCHAR(150),
    category        VARCHAR(50),
    tier            VARCHAR(20),
    city            VARCHAR(50),
    state           VARCHAR(50),
    onboarding_date DATE NOT NULL
);

CREATE TABLE devices (
    device_id       INT PRIMARY KEY,
    user_id         INT NOT NULL,
    device_type     VARCHAR(20),
    primary_network VARCHAR(10),
    CONSTRAINT device_userid_fk FOREIGN KEY(user_id) REFERENCES users(user_id)
);

CREATE TABLE transactions (
    transaction_id   INT PRIMARY KEY,
    user_id          INT NOT NULL,
    merchant_id      INT,               
    transaction_type VARCHAR(5),         
    payment_mode     VARCHAR(20),
    amount           DECIMAL(12,2),
    timestamp        DATETIME NOT NULL,
    status           VARCHAR(10),        
    failure_reason   VARCHAR(50),
    device_type      VARCHAR(20),
    network_type     VARCHAR(10),
    CONSTRAINT tran_userid_fk FOREIGN KEY(user_id) REFERENCES users(user_id)
    -- merchant_id intentionally not FK-enforced since -1 marks "no merchant" (P2P)
);

CREATE TABLE refunds (
    refund_id      INT PRIMARY KEY,
    transaction_id INT NOT NULL,
    refund_amount  DECIMAL(12,2),
    refund_date    DATETIME,
    refund_reason  VARCHAR(50),
    CONSTRAINT refund_tansaction_id FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
);

-- ============================================================
-- Indexes - added because 1M-row transactions table is where
-- "analyzing large, complex, multi-dimensional data" starts to
-- actually matter. Try queries before/after these to show the
-- EXPLAIN-plan difference in your write-up.
-- ============================================================
CREATE INDEX idx_txn_user      ON transactions(user_id);
CREATE INDEX idx_txn_merchant  ON transactions(merchant_id);
CREATE INDEX idx_txn_timestamp ON transactions(timestamp);
CREATE INDEX idx_txn_status    ON transactions(status);
CREATE INDEX idx_merchant_cat  ON merchants(category);
CREATE INDEX idx_users_city    ON users(city);

