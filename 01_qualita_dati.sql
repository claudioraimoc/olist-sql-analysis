-- TABELLA: customers 

-- 1. Prime righe: cosa rappresenta una riga (granularità)
-- visualizzo le prime righe
----> ogni riga della tabella rappresenta un ordine con i dati del relativo cliente 
SELECT *
FROM customers 
LIMIT 5;

SELECT customer_unique_id, COUNT(*)
FROM customers
GROUP BY customer_unique_id
HAVING COUNT(*)>1;


-- 2. Conteggio righe e confronto con Kaggle
-- numero di righe della tabella
----> 99.441 righe coincide con quello dichiarato in Kaggle
SELECT COUNT(*)
FROM customers; 


-- 3. Chiave primaria: quale colonna (o combinazione) identifica la riga? 
-- il campo customer_id presenta valori unici
----> customer_id è PK
SELECT customer_id, COUNT(*)
FROM customers 
GROUP BY customer_id
HAVING COUNT(*)>1; 
-- verifico che in customer_id non ci siano NULL. 
SELECT COUNT(*)
FROM customers 
WHERE customer_id IS NULL; 


-- 4. Valori mancanti per colonna: sono giustificati?
-- numero di count per ogni campo
----> in ogni colonna non sono presenti NULL
SELECT 
	COUNT(*)-COUNT(customer_id) AS customer_id_null,
	COUNT(*)-COUNT(customer_unique_id) AS customer_unique_id_null,
	COUNT(*)-COUNT(customer_zip_code_prefix) AS customer_zip_code_prefix_null,
	COUNT(*)-COUNT(customer_city) AS customer_city_null,
	COUNT(*)-COUNT(customer_state) AS customer_state_null
FROM customers; 


-- 5. Duplicati: per l'unicità dei valori di customer_id non posso esistere duplicati
-- 6. Controlli logici sui valori (non applicabile)
-- 7. Eventuali MIN, MAX, AVG di numeri e date (non applicabile)

-- 8. Valori distinti con frequenza nelle colonne di categorie

SELECT COUNT(*)
FROM customers; 

SELECT COUNT(DISTINCT customer_unique_id)
FROM customers;

----> 99441-96096=3345 righe di differenza, questo vuol dire che ci sono clienti che
--- hanno effettuato piu di un ordine. 
----> 27 stati, sigla composta da due lettere, con il 41.98 degli ordini 
-- concentrati in SP.

-- ordini, del cliente, per stato, con percentuale
SELECT 
	customer_state, 
	COUNT(customer_state) AS customer_state_count, 
	ROUND(((COUNT(customer_state)*100.0) / 
			(
		SELECT COUNT(customer_state)
		FROM customers 
			)), 2) AS customer_state_pct
FROM customers 
GROUP BY customer_state
ORDER BY customer_state_pct DESC;  


-- PER LE ALTRE TABELLE SOLO CONTROLLI NON COPERTI DALLA DESCRIZIONE DEL DATABASE
-- IN KAGGLE

-- TABELLA: orders

-- 1. verifica order_id PK
----> non vengono restituiti gruppi con HAVING COUNT(*)>1 e non sono presenti
---- NULL, quindi order_id è una PK.

SELECT order_id, COUNT(*)
FROM orders 
GROUP BY order_id 
HAVING COUNT(*)>1;

SELECT COUNT(*)
FROM orders 
WHERE order_id IS NULL;


-- 2. verifico se customer_id è FK per la tabella customers
-- tutti i record della FK devono trovarsi nella PK in customer
----> tutti i record di o.customer_id si trovano in c.customer_id 
---- quindi o.customer_id è FK. inoltre o.customer_id sappiamo essere unico e sapendo
---- che customers ha 99441 righe allora la corrispondenza è 1:1. 

SELECT COUNT(*)
FROM orders o
WHERE o.customer_id IN (SELECT c.customer_id 
						FROM customers c);


-- 3. coerenza tra le date e controllo sugli stati
-- effettuo un controllo tra le varie coppie di date, la sequenza della logistica 
-- prevede che la prima sia <= della seconda e così via fino a 
-- order_delivered_customer_date. 
-- order_estimated_delivery_date la escludo perchè è una stima, servirà per i ritardi.
----> a seguito del primo controllo risultano 1.383 righe per cui una data che 
---- dovrebbe essere anteriore risulta invece posteriore. 
WITH date_comparison AS (
	SELECT 
		order_id,
		CASE 
			WHEN order_purchase_timestamp > order_approved_at THEN 1
			ELSE 0
		END AS check_1, 
		CASE 
			WHEN order_approved_at > order_delivered_carrier_date THEN 1
			ELSE 0
		END AS check_2, 
		CASE 
			WHEN order_delivered_carrier_date > order_delivered_customer_date THEN 1
			ELSE 0
		END AS check_3
	FROM orders)
SELECT COUNT(*)
FROM date_comparison
WHERE check_1 = 1 OR check_2 = 1 OR check_3 = 1; 


-- controllo per ogni coppia di date quante righe violano la condizione logica: 
----> per check_1=1, per check_2=1359, per check_3=23. 
---- la somma restituisce esattamente 1.383 quindi innanzitutto nessuna violazione
---- si sovrappone contemporaneamente. 

WITH date_comparison AS (
	SELECT 
		order_id,
		order_purchase_timestamp, 
		order_approved_at, 
		order_delivered_carrier_date, 
		order_delivered_customer_date,
		CASE 
			WHEN order_purchase_timestamp > order_approved_at THEN 1
			ELSE 0
		END AS check1, 
		CASE 
			WHEN order_approved_at > order_delivered_carrier_date THEN 1
			ELSE 0
		END AS check_2, 
		CASE 
			WHEN order_delivered_carrier_date > order_delivered_customer_date THEN 1
			ELSE 0
		END AS check_3
	FROM orders)
-- basta cambiare il check_ nel where per vedere il relativo COUNT o SUM
SELECT *
FROM date_comparison
WHERE check_3 = 1; 


-- calcolo per check_2 e check_3 le differenze tra le date anomale
----> per check_3 in definitiva 23 ordini hanno data di consegna al corriere successiva
---- alla data di consegna al cliente con un range che va da circa 23 minuti a 16 giorni.
---- per check_2 1359 ordini presentano anomalia nelle date con rispettivamente 
---- MIN 00:00:21, MAX 171 days 05:15:22, AVG 24:45:07.153053. 

WITH date_comparison AS (
	SELECT 
		order_id,
		order_purchase_timestamp, 
		order_approved_at, 
		order_delivered_carrier_date, 
		order_delivered_customer_date,
		CASE 
			WHEN order_purchase_timestamp > order_approved_at THEN 1
			ELSE 0
		END AS check1, 
		CASE 
			WHEN order_approved_at > order_delivered_carrier_date THEN 1
			ELSE 0
		END AS check_2, 
		CASE 
			WHEN order_delivered_carrier_date > order_delivered_customer_date THEN 1
			ELSE 0
		END AS check_3
	FROM orders)
-- basta cambiare il check_ nel where e i campi delle date
SELECT AVG((order_approved_at - order_delivered_carrier_date)) AS check_2_diff
FROM date_comparison
WHERE check_2 = 1; 


-- controllo su coerenza tra order_status e date
----> la tabella riporta per ogni record l'order_status e i relativi NULL nei campi
---- delle date, per ogni stato quindi va letto l'incrocio con la data di interesse.
---- ad esempio per 'canceled' su 625 stati in totale 619 sono giustamente NULL quindi
---- la differenza di 6 è ciò che risulta anomalo mentre 75 NULL sulla data di consegna 
---- al corriere è plausibile.
---- per delivered 8 NULL sono presenti nella consegna al cliente e 2 al corriere che 
---- è chiaramente un'anomalia. 

SELECT 
	order_status, 
	COUNT(*) AS tot_order_status,
	COUNT(*) - COUNT(order_purchase_timestamp) AS null_order_purchase_timestamp,
	COUNT(*) - COUNT(order_approved_at) AS null_order_approved_at,
	COUNT(*) - COUNT(order_delivered_carrier_date) AS null_order_delivered_carrier_date,
	COUNT(*) - COUNT(order_delivered_customer_date) AS null_order_delivered_customer_date
FROM orders 
GROUP BY order_status;


-- TABELLA: order_items

-- 1. ricerca PK
----> order_id presenta gruppi con piu di un record, ricerca chiave composta. aggiungo order_item_id (che
---- numera ogni articolo di ogni ordine)
---- La combinazione order_id, order_item_id presenta tutti valori unici e nessun NULL in entrambI i campi,
---- la PK è quindi composta da order_id, order_item_id. 
---- Inoltre order_id da solo si ripete (98.666 valori distinti su 112.650 righe), 
---- quindi la descrizione “unique identifier” di Kaggle non vale per questa tabella.

SELECT *
FROM order_items 
LIMIT 5;

-- controllo unicità 
SELECT order_id, order_item_id 
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*)>1;

-- controllo NULL
SELECT order_id, order_item_id
FROM order_items
WHERE order_id IS NULL OR order_item_id IS NULL;

-- 2. controllo: order_id chiave esterna verso orders, i valori dell FK in order_items dovrei ritrovarli 
-- tutti nella PK (order_id) di orders 
----> 112650 record oi.order_id li ritroviamo in o.order_id, dove 112650 è il numero totale di record 
---- oi.order_id, nessuna riga è orfana quindi oi.order_id è una FK che punta a o.order_id 

SELECT COUNT(*)
FROM order_items; 

SELECT COUNT(*)
FROM order_items oi 
WHERE oi.order_id IN (SELECT o.order_id 
					FROM orders o); 


-- 3. cardinalita 
----> dal controllo al punto 1 sul GROUP BY su order_id risultava che ci fossero piu gruppi con piu record 
---- per gruppo per cui lo stesso ordine è presente su piu record; per cui sicuramente la cardinalita 
---- è 1:N. 
-- si verifica se tutti i valori di o.order_id sono presenti in oi.order_id (il NOT IN è sicuro in 
-- questo caso perchè non sono presenti NULL nel relativo campo)
----> ci sono 775 record da o.order_id non presenti in oi.order_id questo vuol dire che la cardinalità è 
---- 1:0...N. 
----> dei 775 ordini dalla seconda query si può vedere come per invoiced shipped rispettivamente ci siano
---- 2 e 1 ordine senza items in oi., questo vuol dire che c'è un'anomalia per questi record; per gli altri
---- è plausibile come l'ordine sia arrivato a non contenere articoli. 

-- conteggio dei record di o.order_id non presenti in oi.order_id
SELECT COUNT(*)
FROM orders o
WHERE o.order_id NOT IN (SELECT oi.order_id 
						FROM order_items oi); 

-- ripartizione per order_status dei 775 ordini non presenti in order_items
SELECT order_status, COUNT(*)
FROM orders o
WHERE o.order_id NOT IN (SELECT oi.order_id 
						FROM order_items oi)
GROUP BY o.order_status; 


-- TABELLA: order_reviews

-- 1. ricerca PK
----> sia review_id che order_id hanno un numero di record minore del numero di record della tabella quindi
---- nessuna delle due chiavi può essere PK. procedo nel controllo della chiave composta:
---- la coppia order_id, review_id non presenta ripetizioni ne NULL, la consideriamo come chiave composta.
---- il fatto che ci siano piu order_id per la stessa review risulta anomalo, non il contrario. 
SELECT *
FROM order_reviews 
LIMIT 5;

-- controllo unicità 
SELECT order_id, review_id
FROM order_reviews
GROUP BY order_id, review_id
HAVING COUNT(*)>1;

-- controllo NULL
SELECT order_id, review_id
FROM order_reviews
WHERE order_id IS NULL OR review_id IS NULL;

-- 2. controllo: controllare se orw.order_id è FK per orders
---->  99.224 righe su 99224 sono presenti in orders, tutti i record orw.order_id li ritroviamo 
---- in o.order_id; quindi orw.order_id è FK.

SELECT COUNT(*)
FROM order_reviews; 

SELECT COUNT(*)
FROM order_reviews orw
WHERE orw.order_id IN (SELECT o.order_id 
					FROM orders o); 

-- 3. cardinalita: in order_reviews alcuni order_id si ripetono, 98.673 distinti su 99.224 record, 
-- mentre in orders sono unici, quindi la cardinalita è 1:N. controllo sui record di differenza: 
----> 99.441 − 98.673 = 768 sono gli ordini "in eccesso" in orders che non hanno nessuna recensione, 
---- essendoci ordini con nessuna recensione allora la cardinalita è 1:0...N che è sensato dato che
---- la recensione non è obbligatoria. 
---- 646 sono delivered tra gli ordini senza recensione ma in percentuale pesano poco rispetto al 
---- complessivo degli ordini consegnati quindi quasi tutti quelli presenti in questa categoria 
---- hanno una recensione.
 

-- conteggio dei record di o.order_id non presenti in orw.order_id
SELECT COUNT(*)
FROM orders o
WHERE o.order_id NOT IN (SELECT orw.order_id 
						FROM order_reviews orw); 

-- ripartizione per order_status dei 768 ordini senza recensione in order_reviews
SELECT order_status, COUNT(*)
FROM orders o
WHERE o.order_id NOT IN (SELECT orw.order_id 
						FROM order_reviews orw)
GROUP BY o.order_status; 


-- 4. coerenza tra le colonne: (1) ci sono review_id su più ordini quando in teoria un review_id 
-- dovrebbe comparire  su un solo ordine. inoltre ci sono anche order_id con più recensioni che però risulta  
-- essere piu plausibile visto che una recensione si puo anche aggiornare su un ordine.
----> delle review che hanno molteplicita (m) maggiore di 1 la maggior parte hanno m=2 e un piccolo cluster
---- m=3. dai controlli a campione in entrambi i casi risulta che l'unica cosa che differisce è order_id,
---- il che può indurre a pensare che ci sia una causa non verificata, bisogna 
---- verificare successivamente se ordini dello stesso gruppo siano associati allo stesso customer_unique_id. 

SELECT review_id, COUNT(*) AS molteplicita
FROM order_reviews
GROUP BY review_id
HAVING COUNT(*)>2; 

-- per guardare i vari gruppi incollo nel where le review_id derivanti dalla query sopra
SELECT *
FROM order_reviews
WHERE review_id = '44e9f871226d8a130de3fc39dfbdf0c5'; 


--TABELLA: order_payments
----> per via della presenza di payment_sequential, che enumera la progressione dei pagamenti, allora possiamo
---- affermare che order_id non è univoco e quindi non può essere PK; verifichiamo che i due campi
---- restituiscono però una chiave composta una volta constatato che in nessuno dei due ci sono NULL.

-- 1. ricerca PK

SELECT *
FROM order_payments 
LIMIT 5;

-- controllo unicità 
SELECT order_id, payment_sequential 
FROM order_payments
GROUP BY order_id, payment_sequential 
HAVING COUNT(*)>1;

-- controllo NULL
SELECT COUNT(*)
FROM order_payments
WHERE order_id IS NULL OR payment_sequential IS NULL;

-- 2. controllo FK:
----> 103.886 righe su 103.886 trovano il loro order_id in orders quindi op.order_id è FK.

SELECT COUNT(*)
FROM order_payments; 

SELECT COUNT(*)
FROM order_payments op
WHERE op.order_id IN (SELECT o.order_id 
					FROM orders o); 

-- 3. cardinalita:
----> quasi tutti gli order_id in orders sono presenti in op.order_id, tutti tranne 1 che ho controllato
---- in order_items: ci sono dei pagamenti che però non risultano regisrati solo per quell'ordine. 
---- in sostanza, a meno di quell'ordine che è chiaramente un'anomalia, la cardinalita è 1:N. 

-- conteggio dei record di o.order_id non presenti in op.order_id
SELECT *
FROM orders o
WHERE o.order_id NOT IN (SELECT op.order_id 
						FROM order_payments op); 
-- controllo dell'id in order items per controllo sui pagamenti, ci sono dei pagamenti effettivamente. 
SELECT *
FROM order_items 
WHERE order_id = 'bfbd0f9bdef84302105ad712db648a6c';

-- 4. controllo su valory payment
----> Su 103.886 pagamenti, 9 hanno importo 0 (6 voucher con payment_sequential maggiore di 1, che sono 
---- pagamenti successivi dentro ordini con più voucher, e 3 not_defined come unico pagamento dell’ordine)
---- e 2 hanno 0 rate (credit_card, secondi pagamenti). Sono valori anomali ma pochissimi; 
---- da tenere presenti nella riconciliazione e nella definizione di ricavo.
SELECT *
FROM order_payments
WHERE payment_installments=0; 

-- TABELLA: products

-- 1. ricerca PK

SELECT *
FROM  
LIMIT 5;

-- controllo unicità 
SELECT order_id, payment_sequential 
FROM 
GROUP BY order_id, payment_sequential 
HAVING COUNT(*)>1;

-- controllo NULL
SELECT COUNT(*)
FROM 
WHERE order_id IS NULL OR payment_sequential IS NULL;

-- 2. controllo FK:
----> 103.886 righe su 103.886 trovano il loro order_id in orders quindi op.order_id è FK.

SELECT COUNT(*)
FROM ; 

SELECT COUNT(*)
FROM  
WHERE .order_id IN (SELECT o.order_id 
					FROM orders o); 