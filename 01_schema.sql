-- Проект: анализ платежей и просрочки по кредитному портфелю
-- СУБД: PostgreSQL 12+  |  Данные полностью синтетические

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS clients;

CREATE TABLE clients (
    client_id     SERIAL PRIMARY KEY,
    region        TEXT NOT NULL,
    segment       TEXT NOT NULL,          -- standard / salary / premium
    registered_at DATE NOT NULL
);

CREATE TABLE loans (
    loan_id      SERIAL PRIMARY KEY,
    client_id    INT NOT NULL REFERENCES clients(client_id),
    product      TEXT NOT NULL,           -- cash / card / auto
    amount       NUMERIC(12,2) NOT NULL,  -- сумма кредита
    rate         NUMERIC(4,3) NOT NULL,   -- годовая ставка, 0.180 = 18%
    term_months  INT NOT NULL,
    issued_at    DATE NOT NULL
);

CREATE TABLE payments (
    payment_id  SERIAL PRIMARY KEY,
    loan_id     INT NOT NULL REFERENCES loans(loan_id),
    due_date    DATE NOT NULL,            -- плановая дата платежа
    due_amount  NUMERIC(12,2) NOT NULL,   -- плановая сумма
    paid_date   DATE,                     -- NULL = не оплачен на дату среза
    paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE INDEX idx_loans_client    ON loans(client_id);
CREATE INDEX idx_payments_loan   ON payments(loan_id);
CREATE INDEX idx_payments_due    ON payments(due_date);
