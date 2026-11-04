-- TABELLA: customers 

-- 1. Prime righe: cosa rappresenta una riga (granularità)
-- visualizzo le prime righe
SELECT *
FROM customers 
LIMIT 5;

SELECT customer_unique_id, COUNT(*)
FROM customers
GROUP BY customer_unique_id
HAVING COUNT(*)>1;
---> ogni riga della tabella rappresenta un ordine con i dati del relativo cliente 

-- 2. Conteggio righe e confronto con Kaggle
-- numero di righe della tabella
SELECT COUNT(*)
FROM customers; 
---> 99.441 righe coincide con quello dichiarato in Kaggle

-- 3. Chiave primaria: quale colonna (o combinazione) identifica la riga? 
-- il campo customer_id presenta valori unici
SELECT customer_id, COUNT(*)
FROM customers 
GROUP BY customer_id
HAVING COUNT(*)>1; 
-- verifico che in customer_id non ci siano NULL. 
SELECT COUNT(*)
FROM customers 
WHERE customer_id IS NULL; 
---> customer_id è PK

-- 4. Valori mancanti per colonna: sono giustificati?
-- numero di count per ogni campo
SELECT 
	COUNT(*)-COUNT(customer_id) AS customer_id_null,
	COUNT(*)-COUNT(customer_unique_id) AS customer_unique_id_null,
	COUNT(*)-COUNT(customer_zip_code_prefix) AS customer_zip_code_prefix_null,
	COUNT(*)-COUNT(customer_city) AS customer_city_null,
	COUNT(*)-COUNT(customer_state) AS customer_state_null
FROM customers; 
---> in ogni colonna non sono presenti NULL

-- 5. Duplicati
-- 6. Controlli logici sui valori 
-- 7. Eventuali MIN, MAX, AVG di numeri e date
-- 8. Valori distinti con frequenza nelle colonne di categorie

