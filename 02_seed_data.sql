-- Генерация синтетических данных. Дата среза: 2025-12-31.
-- setseed делает результат воспроизводимым (в рамках одной версии PostgreSQL).
SELECT setseed(0.42);

-- 1) Клиенты: 2000 шт.
INSERT INTO clients (region, segment, registered_at)
SELECT
    (ARRAY['Казань','Набережные Челны','Нижнекамск','Альметьевск','Елабуга'])[1 + floor(random()*5)::int],
    (ARRAY['standard','standard','standard','salary','salary','premium'])[1 + floor(random()*6)::int],
    DATE '2022-01-01' + floor(random()*900)::int
FROM generate_series(1, 2000);

-- 2) Кредиты: 3000 шт., выдача с 2024-01-01 по 2025-06-30
INSERT INTO loans (client_id, product, amount, rate, term_months, issued_at)
SELECT
    1 + floor(random()*2000)::int,
    (ARRAY['cash','cash','card','auto'])[1 + floor(random()*4)::int],
    round((30000 + random()*470000)::numeric, -3),
    round((0.12 + random()*0.14)::numeric, 3),
    (ARRAY[6,12,12,24,36])[1 + floor(random()*5)::int],
    DATE '2024-01-01' + floor(random()*546)::int
FROM generate_series(1, 3000);

-- 3) Платежи: график по месяцам + фактическое поведение заёмщика.
--    risk — «склонность к просрочке» договора (перекошена к 0: большинство надёжные).
WITH loan_risk AS MATERIALIZED (
    SELECT loan_id, power(random(), 4) AS risk FROM loans
),
schedule AS (
    SELECT
        l.loan_id,
        (l.issued_at + (n || ' month')::interval)::date AS due_date,
        round(l.amount * (1 + l.rate * l.term_months / 12.0) / l.term_months, 2) AS due_amount,
        r.risk,
        random() AS x,
        random() AS d
    FROM loans l
    JOIN loan_risk r USING (loan_id)
    CROSS JOIN LATERAL generate_series(1, l.term_months) AS n
    WHERE (l.issued_at + (n || ' month')::interval)::date <= DATE '2025-12-31'
)
INSERT INTO payments (loan_id, due_date, due_amount, paid_date, paid_amount)
SELECT
    loan_id, due_date, due_amount,
    CASE
        WHEN x < risk * 0.3 THEN NULL                                    -- не оплатил
        WHEN x < risk * 0.3 + 0.03 + risk * 0.4 THEN                           -- оплатил с задержкой
             CASE WHEN due_date + (4 + floor(d*40))::int > DATE '2025-12-31'
                  THEN NULL ELSE due_date + (4 + floor(d*40))::int END
        ELSE due_date + floor(d*3)::int                                  -- вовремя
    END,
    0
FROM schedule;

UPDATE payments SET paid_amount = due_amount WHERE paid_date IS NOT NULL;
ANALYZE;
