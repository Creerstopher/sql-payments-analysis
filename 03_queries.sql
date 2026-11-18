-- Аналитические запросы. Дата среза: 2025-12-31.
-- Определения:
--   «открытая просрочка» = платёж, который должен был пройти, но не оплачен на дату среза
--   «оплачен с задержкой» = paid_date - due_date > 3 дней

-- Q1. Структура портфеля по продуктам
-- Вопрос бизнеса: сколько выдали и какой средний чек по каждому продукту?
SELECT product,
       count(*)                      AS loans,
       round(sum(amount) / 1e6, 1)   AS issued_mln,
       round(avg(amount))            AS avg_amount
FROM loans
GROUP BY product
ORDER BY issued_mln DESC;

-- Q2. Доля просроченных платежей по продуктам (JOIN + FILTER)
-- Вопрос: какой продукт «проблемнее» всего?
SELECT l.product,
       count(*)                                                        AS payments,
       round(100.0 * count(*) FILTER (WHERE p.paid_date IS NULL) / count(*), 2)             AS open_overdue_pct,
       round(100.0 * count(*) FILTER (WHERE p.paid_date - p.due_date > 3) / count(*), 2)    AS late_paid_pct
FROM payments p
JOIN loans l USING (loan_id)
GROUP BY l.product
ORDER BY open_overdue_pct DESC;

-- Q3. Корзины просрочки (aging) по открытым платежам (CASE)
-- Вопрос: как распределён долг по возрасту просрочки?
SELECT CASE
           WHEN DATE '2025-12-31' - due_date <= 30 THEN '1-30'
           WHEN DATE '2025-12-31' - due_date <= 60 THEN '31-60'
           WHEN DATE '2025-12-31' - due_date <= 90 THEN '61-90'
           ELSE '90+'
       END                              AS bucket,
       count(*)                         AS payments,
       round(sum(due_amount) / 1e6, 2)  AS debt_mln
FROM payments
WHERE paid_date IS NULL
GROUP BY 1
ORDER BY min(DATE '2025-12-31' - due_date);

-- Q4. Топ-10 клиентов по сумме открытой задолженности (JOIN, GROUP BY, HAVING)
SELECT c.client_id, c.region, c.segment,
       count(*)                  AS open_payments,
       round(sum(p.due_amount))  AS debt
FROM payments p
JOIN loans   l ON l.loan_id   = p.loan_id
JOIN clients c ON c.client_id = l.client_id
WHERE p.paid_date IS NULL
GROUP BY c.client_id, c.region, c.segment
HAVING sum(p.due_amount) > 50000
ORDER BY debt DESC
LIMIT 10;

-- Q5. CTE: клиенты, чей долг выше среднего по их региону
-- Вопрос: кого в первую очередь брать в работу в каждом регионе?
WITH client_debt AS (
    SELECT c.client_id, c.region, sum(p.due_amount) AS debt
    FROM payments p
    JOIN loans   l ON l.loan_id   = p.loan_id
    JOIN clients c ON c.client_id = l.client_id
    WHERE p.paid_date IS NULL
    GROUP BY c.client_id, c.region
),
region_avg AS (
    SELECT region, avg(debt) AS avg_debt FROM client_debt GROUP BY region
)
SELECT cd.region,
       count(*)                       AS clients_above_avg,
       round(avg(cd.debt))            AS avg_debt_of_them,
       round(max(ra.avg_debt))        AS region_avg_debt
FROM client_debt cd
JOIN region_avg ra USING (region)
WHERE cd.debt > ra.avg_debt
GROUP BY cd.region
ORDER BY clients_above_avg DESC;

-- Q6. Оконная функция: топ-3 должника в каждом регионе (ROW_NUMBER + PARTITION BY)
WITH client_debt AS (
    SELECT c.client_id, c.region, sum(p.due_amount) AS debt
    FROM payments p
    JOIN loans   l ON l.loan_id   = p.loan_id
    JOIN clients c ON c.client_id = l.client_id
    WHERE p.paid_date IS NULL
    GROUP BY c.client_id, c.region
)
SELECT region, client_id, round(debt) AS debt, rn
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY region ORDER BY debt DESC) AS rn
    FROM client_debt
) t
WHERE rn <= 3
ORDER BY region, rn;

-- Q7. Динамика доли просрочки по месяцам и изменение к прошлому месяцу (LAG)
-- Вопрос: портфель ухудшается или улучшается?
WITH monthly AS (
    SELECT date_trunc('month', due_date)::date AS month,
           count(*) AS payments,
           100.0 * count(*) FILTER (WHERE paid_date IS NULL OR paid_date - due_date > 3) / count(*) AS bad_pct
    FROM payments
    WHERE due_date >= DATE '2025-01-01'
    GROUP BY 1
)
SELECT month, payments,
       round(bad_pct, 2)                                    AS bad_pct,
       round(bad_pct - LAG(bad_pct) OVER (ORDER BY month), 2) AS delta_vs_prev
FROM monthly
ORDER BY month;

-- Q8. Нарастающий итог выдач по месяцам (SUM OVER)
WITH monthly AS (
    SELECT date_trunc('month', issued_at)::date AS month,
           sum(amount)                          AS issued
    FROM loans
    GROUP BY 1
)
SELECT month,
       round(issued / 1e6, 1)                            AS issued_mln,
       round(sum(issued) OVER (ORDER BY month) / 1e6, 1) AS cumulative_mln
FROM monthly
ORDER BY month;

-- Q9. Когорты (vintage): доля договоров с открытой просрочкой по кварталу выдачи
-- Вопрос: какие «урожаи» кредитов оказались хуже остальных?
SELECT date_trunc('quarter', l.issued_at)::date                     AS cohort,
       count(DISTINCT l.loan_id)                                    AS loans,
       count(DISTINCT l.loan_id) FILTER (WHERE p.paid_date IS NULL) AS loans_with_open_overdue,
       round(100.0 * count(DISTINCT l.loan_id) FILTER (WHERE p.paid_date IS NULL)
             / count(DISTINCT l.loan_id), 1)                        AS pct
FROM loans l
JOIN payments p USING (loan_id)
GROUP BY 1
ORDER BY 1;

-- Q10. Сегментация должников на квартили по сумме долга (NTILE)
WITH client_debt AS (
    SELECT l.client_id, sum(p.due_amount) AS debt
    FROM payments p JOIN loans l USING (loan_id)
    WHERE p.paid_date IS NULL
    GROUP BY l.client_id
)
SELECT quartile,
       count(*)                  AS clients,
       round(min(debt))          AS min_debt,
       round(max(debt))          AS max_debt,
       round(sum(debt) / 1e6, 2) AS total_mln
FROM (SELECT *, NTILE(4) OVER (ORDER BY debt DESC) AS quartile FROM client_debt) t
GROUP BY quartile
ORDER BY quartile;
