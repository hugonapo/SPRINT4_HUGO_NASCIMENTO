-- NIVEL 1

-- EJ.1

SELECT 
    t.transaction_id,
    t.timestamp,
    t.amount,
    c.company_name,
    c.country
FROM `sprint3-analytics-hugo-silva.sprint3_silver.transactions_clean` AS t
JOIN `sprint3-analytics-hugo-silva.sprint3_silver.companies_clean` AS c 
    ON t.business_id = c.company_id
WHERE DATE(t.timestamp) = '2022-03-12'
    AND c.country = 'Germany'
    
-- EJ.2

-- PASO 1

CREATE OR REPLACE TABLE `sprint3-analytics-hugo-silva.sprint3_silver.transactions_recent`
AS
SELECT 
    * EXCEPT (timestamp),
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL CAST(FLOOR(RAND() * 50) AS INT64) DAY) AS timestamp
FROM `sprint3-analytics-hugo-silva.sprint3_silver.transactions_clean`

-- PASO 2

CREATE OR REPLACE TABLE `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized`
PARTITION BY DATE(timestamp) 
CLUSTER BY business_id
AS
SELECT * FROM `sprint3-analytics-hugo-silva.sprint3_silver.transactions_recent`;

-- EJ.3


-- PASO 1

SELECT *
FROM `sprint3-analytics-hugo-silva.sprint3_silver.transactions_recent`
WHERE DATE(timestamp) >= '2026-04-26'

-- PASO 2

SELECT *
FROM `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized`
WHERE DATE(timestamp) >= '2026-04-26'

-- EJ.4

CREATE OR REPLACE MATERIALIZED VIEW `sprint3-analytics-hugo-silva.sprint3_gold.mv_daily_sales`
AS
SELECT 
    DATE(timestamp) AS fecha_venta,
    SUM(amount) AS ventas_totales,
    COUNT(*) AS total_transacciones
FROM `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized`
WHERE declined = 0
GROUP BY 1;

-- CONSULTA 

SELECT * FROM `sprint3-analytics-hugo-silva.sprint3_gold.mv_daily_sales` ORDER BY fecha_venta DESC;

-- NIVEL 2

-- EJ.1

WITH VIP_Stats AS (
    SELECT 
        user_id,
        ROUND(SUM(amount), 2) AS total_gastado,
        COUNT(transaction_id) AS num_compras,
        ROUND(AVG(amount), 2) AS ticket_medio,
        ROUND(MAX(amount), 2) AS compra_maxima
    FROM `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized`
    WHERE declined = 0
    GROUP BY user_id
    HAVING total_gastado > 500
)
SELECT 
    v.user_id,
    CONCAT(u.name, ' ', u.surname) AS nombre_completo,
    u.email,
    v.num_compras,
    v.ticket_medio,
    v.compra_maxima,
    v.total_gastado
FROM VIP_Stats v
JOIN `sprint3-analytics-hugo-silva.sprint3_silver.users_combined` u 
    ON v.user_id = u.id
ORDER BY total_gastado DESC;

-- EJ.2

SELECT
  fecha_venta AS fecha,
  ROUND(ventas_totales, 2) AS ventas_hoy,
  ROUND(LAG(ventas_totales) OVER (ORDER BY fecha_venta), 2) AS ventas_ayer,
  ROUND(
    SAFE_DIVIDE(
      ventas_totales - LAG(ventas_totales) OVER (ORDER BY fecha_venta),
      LAG(ventas_totales) OVER (ORDER BY fecha_venta))
      * 100,
    2)
    AS diferencia_porcentual
FROM `sprint3-analytics-hugo-silva.sprint3_gold.mv_daily_sales`
ORDER BY fecha_venta DESC;

-- EJ.3

SELECT
  fecha_venta AS fecha,
  ROUND(ventas_totales, 2) AS ventas_del_dia,
  ROUND(
    SUM(ventas_totales)
      OVER (
        PARTITION BY EXTRACT(YEAR FROM fecha_venta)
        ORDER BY fecha_venta
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
    2)
    AS ventas_acumuladas_ytd
FROM `sprint3-analytics-hugo-silva.sprint3_gold.mv_daily_sales`
ORDER BY fecha DESC;


-- EJ.4

WITH
  transacciones_numeradas AS (
    SELECT
      user_id,
      timestamp AS fecha_tercera_compra,
      amount,
      ROW_NUMBER()
        OVER (PARTITION BY user_id ORDER BY timestamp ASC) AS numero_compra,
      AVG(amount)
        OVER (
          PARTITION BY user_id
          ORDER BY timestamp ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
        AS promedio_primeras_tres
    FROM `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized`
    WHERE declined = 0
    QUALIFY numero_compra <= 3
  )
SELECT
  t.user_id,
  CONCAT(u.name, ' ', u.surname) AS nombre_completo,
  u.email,
  t.fecha_tercera_compra,
  ROUND(t.amount, 2) AS importe_tercera_compra,
  ROUND(t.promedio_primeras_tres, 2) AS promedio_tres_primeras
FROM transacciones_numeradas t
JOIN `sprint3-analytics-hugo-silva.sprint3_silver.users_combined` u
  ON t.user_id = u.user_id
WHERE t.numero_compra = 3
ORDER BY promedio_tres_primeras DESC;

-- NIVEL 3

-- EJ.1

CREATE OR REPLACE TABLE `sprint3-analytics-hugo-silva.sprint3_gold.dim_transactions_flat`
AS
SELECT
  t.transaction_id,
  t.timestamp,
  t.amount AS total_ticket_global,
  p.product_id AS product_sku,
  p.name AS product_name,
  p.price AS product_price
FROM
  `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized` AS t,
  UNNEST(t.product_ids) AS id_producto_unid
JOIN `sprint3-analytics-hugo-silva.sprint3_silver.products_clean` AS p
  ON id_producto_unid = p.product_id
WHERE t.declined = 0;

-- EJ.2

SELECT 
    product_name, 
    COUNT(*) AS unidades_vendidas
FROM `sprint3-analytics-hugo-silva.sprint3_gold.dim_transactions_flat`
GROUP BY product_name
ORDER BY unidades_vendidas DESC
LIMIT 5;

-- EJ.3

-- CREACION DE LA UDF

CREATE OR REPLACE FUNCTION `sprint3-analytics-hugo-silva.sprint3_gold.calculate_tax`(amount FLOAT64) 
RETURNS FLOAT64 AS (
  amount * 1.21
);
 
 
 -- CREACION DE LA TABLA 
 
 CREATE OR REPLACE TABLE `sprint3-analytics-hugo-silva.sprint3_gold.dim_transactions_flat` AS
SELECT
  t.transaction_id,
  t.timestamp,
  t.amount AS total_ticket_global,
  p.product_id AS product_sku,
  p.name AS product_name,
  p.price AS product_unit_price,
  `sprint3-analytics-hugo-silva.sprint3_gold.calculate_tax`(p.price) AS product_price_tax_inc
FROM
  `sprint3-analytics-hugo-silva.sprint3_gold.fact_transactions_optimized` AS t,
  UNNEST(t.product_ids) AS id_producto_unid
JOIN
  `sprint3-analytics-hugo-silva.sprint3_silver.products_clean` AS p
ON
  id_producto_unid = p.product_id
WHERE
  t.declined = 0;

