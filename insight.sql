-- 1. quanto avrebbe dovuto pagare ogni cliente per ogni ordine in base agli 
-- articoli e quanto ha pagato davvero
----> 

SELECT *
FROM order_payments 
LIMIT 5; 

SELECT *
FROM order_items 
LIMIT 5; 

-- creo una view per fissare la tabella di partenza per le domande successive: 
CREATE OR REPLACE VIEW order_id_payments_view AS
-- prima in ognuna delle due tabelle facciamo group by su order_id, dato che si ripete, e rispettivamente
-- consideriamo poi una sum su payment_value e una sum su price+freight_value; a seguire il join 
WITH order_payments_grouped AS (
	SELECT order_id, SUM(payment_value) AS payment_value_per_order_id 
	FROM order_payments 
	GROUP BY order_id 
),
order_items_grouped AS (
	SELECT order_id, SUM(price+freight_value) AS tot_value_order_id
	FROM order_items 
	GROUP BY order_id 
),
-- voglio mantenere tutti gli order_id, nel farlo bisogna tener conto che sono presenti anche i due gruppi
-- di order_id anomali riscontrati in orders, cioè i 775 ordini senza articoli e 1 ordine senza 
-- pagamento registrato. 
-- ai fini del conteggio mantengo tutti i 776 ordini dei quali vanno però gestiti i NULL, altrimenti
-- nella differenza quei record vengono ignorati. 
order_id_payments AS (
	SELECT 
		COALESCE(opg.order_id, oig.order_id) AS order_ids, 
		payment_value_per_order_id, 
		tot_value_order_id
	FROM order_payments_grouped opg
	FULL JOIN order_items_grouped oig ON opg.order_id = oig.order_id 
)
-- ritroviamo 99441 record, cioè il totale, e i 775+1 è verificato con un filtro tramite where che sono
-- presenti
SELECT 
	order_ids,
	COALESCE(payment_value_per_order_id, 0) AS payment_value_per_order_ids,
	COALESCE(tot_value_order_id, 0) AS tot_value_order_ids,
	COALESCE(tot_value_order_id, 0) - COALESCE(payment_value_per_order_id, 0) AS amount_diff
FROM order_id_payments; 

-- percentuali di ordini pagati vs non pagati interamente vs con importo piu alto del dovuto
SELECT 
	(SELECT COUNT(*) FROM order_id_payments_view WHERE amount_diff>0)*100.0 / (SELECT COUNT(*) FROM order_id_payments_view) AS pct_unpaid_orders,
	(SELECT COUNT(*) FROM order_id_payments_view WHERE amount_diff=0)*100.0 / (SELECT COUNT(*) FROM order_id_payments_view) AS pct_paid_orders, 
	(SELECT COUNT(*) FROM order_id_payments_view WHERE amount_diff<0)*100.0 / (SELECT COUNT(*) FROM order_id_payments_view) AS pct_overpaid_orders; 

-- controllo di quei 1139 quanti dei 775 ordini vi si ritrovano perchè questi ultimi hanno importo 
-- dovuto pari a 0 per costruzione, per questo risultano overpaid. i rimanenti invece sono sovrapagati
-- realmente ed è questi ultimi che sono anomali veramente e vogliamo andare ad analizzare.
----> Dei 775 ordini senza articoli 772 hanno differenza negativa ed è dovuto al fatto che per 
---- costruzione il totale è 0 mentre i pagamenti ci sono, quindi non sono veri pagamenti in eccesso
---- ma un dovuto non calcolabile. 
---- i restanti 3 hanno dovuto e pagato entrambi a 0 con amount_diff = 0 per questo non ricadono 
---- nell'ultima categoria: risultano saldati ma non hanno articoli né pagamenti reali. 
SELECT COUNT(*)
FROM (SELECT *
	FROM order_id_payments_view
	WHERE amount_diff < 0) oidv	
WHERE tot_value_order_ids = 0; 

SELECT *
FROM order_id_payments_view
WHERE tot_value_order_ids = 0 AND amount_diff = 0; 

-- i pagati in eccesso reali sono 1.139 − 772 = 367 e vanno analizzati
SELECT *
FROM order_id_payments_view 
WHERE amount_diff < 0 AND tot_value_order_ids <> 0; 

-- estrapolo da order_payments i 367 order_id appena trovati usando come filtro la query precedente,
-- l'ipotesi è che l'amount diff possa venire da eventuali rate. 
SELECT order_id, payment_type, MAX(payment_installments), SUM(payment_value)
FROM order_payments
WHERE order_id IN 
	(SELECT order_ids 
	FROM order_id_payments_view 
	WHERE amount_diff < 0 AND tot_value_order_ids <> 0)
GROUP BY order_id, payment_type
ORDER BY order_id ; 

-- sulla tabella che riporta, per ognuno dei 367 ordini; il dovuto, il pagato e il numero di rate 
-- per ogni ordine valuto nella stessa SELECT ESTERNA
----> se ordinando per amount diff in cima troviamo un numero di rate alto: effettivamente ci sono
---- per le differenze piu elevate numeri di rate almeno pari a 10 nelle prime righe 
----> se raggruppando per numero di rate la media di amount_diff cresce: la colonna avg_pct_amount_diff
---- la si legge come percentuale di pagamento in eccesso per piano di pagamento con 'n' rate, ad esempio
---- per il piano a 3 rate, in questo campione di 367 ordini, c'è stato un sovrapagamento del 4.91%.

----> in linea generali notiamo come ci sia una tendenza nella crescita del numero di rate e l'eccesso
---- in percentuale aumenta con il numero delle rate stesse quindi è una plausibile spiegazione del motivo
---- per cui esistono 367 ordini con pagamento in eccesso rispetto al dovuto.
WITH installments_per_order AS (
	SELECT order_id, MAX(payment_installments) AS payment_installments_max
	FROM order_payments
	GROUP BY order_id
),
order_id_overpaid AS (
	SELECT *
	FROM order_id_payments_view 
	WHERE amount_diff < 0 AND tot_value_order_ids <> 0
),
order_id_join AS (
	SELECT order_ids, payment_value_per_order_ids, tot_value_order_ids, amount_diff, payment_installments_max
	FROM order_id_overpaid oo
	JOIN installments_per_order ot ON order_ids=order_id
)
SELECT 
	payment_installments_max, 
	AVG(-amount_diff * 100.0 / tot_value_order_ids) AS avg_pct_amount_diff, 
	COUNT(order_ids)
FROM order_id_join
GROUP BY payment_installments_max
ORDER BY payment_installments_max; 

----> 1. CONCLUSIONE:
---- Su 99.441 ordini, 98.092 (98,64%) hanno pagato esattamente il dovuto (prezzo + spedizione); di questi, 3 sono
---- falsi saldati (senza articoli e senza pagamenti reali, 0 − 0).
---- 210 ordini (0,21%) hanno pagato meno del dovuto: comprendono l'ordine senza pagamenti registrati e,
---- verosimilmente, pagamenti parziali (da distinguere). Non analizzati in questa domanda: da verificare.
---- 1.139 ordini (1,15%) hanno pagato più del dovuto: 772 sono ordini senza articoli, quindi dovuto non
---- calcolabile e non un vero eccesso; i restanti 367 hanno articoli e un pagato superiore al dovuto.
---- Nei 367 l'eccesso medio cresce con il numero di rate (circa 0,3% con 1 rata, 5% con 3, oltre 20% con 13 o più):
---- coerente con un costo aggiuntivo sulle rate, non dimostrato perché il dataset non ha dati sugli interessi.
---- Un'eccezione ad esempio sono i piani a  10 rate, per un totale di 61 ordini, che hanno una media più bassa (7,8%); 
---- le classi con 13 o più rate hanno 1-2 ordini.


-- 2. Tempo di consegna medio per stato geografico: 
-- esclusi tutti gli ordini che non sono delivered, compresi anche i 6 canceled che hanno una
-- data di consegna. dei 1383 ordini che abbiamo visto avere date anomale a due a due, 
-- consideriamo da escludere solo le coppie per cui order_purchase_timestamp>order_delivered_customer_date
-- visto che come intervallo di tempo consideriamo ciò che intercorre tra l'ordine effettuato e la consegna al cliente. 

-- numero di 'delivered' totali, da questi ne sono stati tolti esattamente 8 dalla CTE successiva, 
-- cioè quelli che abbiamo visto non avere data di consegna. 
SELECT COUNT(*)
FROM orders 
WHERE order_status='delivered';

WITH orders_delivered AS (
	SELECT customer_id, order_purchase_timestamp, order_delivered_customer_date
	FROM orders 
	WHERE 
		order_purchase_timestamp < order_delivered_customer_date AND 
		order_status = 'delivered'
),
orders_delivered_state AS (
	SELECT od.customer_id, od.order_purchase_timestamp, od.order_delivered_customer_date, c.customer_state 
	FROM orders_delivered od
	JOIN customers c ON c.customer_id = od.customer_id
)
SELECT 
	customer_state, 
	AVG(order_delivered_customer_date-order_purchase_timestamp) AS avg_delivery_time,
	ROUND(AVG(EXTRACT(epoch FROM order_delivered_customer_date-order_purchase_timestamp)) / (60*60*24), 2) AS avg_day, 
	COUNT(*)
FROM orders_delivered_state
GROUP BY customer_state
ORDER BY avg_day; 

----> 2. CONCLUSIONE: nessun delivered ha la data di acquisto successiva alla consegna. 
---- il tempo medio di consegna nello stato del cliente va da 8,8 giorni per SP a 29,4 per RR, 
---- 9 stati superano le tre settimane: i più lenti nell'arrivo degli ordini sono RR, AP, AM. 
---- calcolo effettuato su 96.470 ordini delivered. 




-- 3. Clienti che effettuano almeno un secondo acquisto

-- immagino sempre un join tra orders e customers per far corrispondere a customers i vari ordini
-- e vedere quanti di questi ne hanno piu di uno facendo un group by

WITH orders_with_customers AS (
	SELECT 
		c.customer_unique_id, o.order_id, o.order_status, o.order_purchase_timestamp,
		ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp ASC) AS rn_customers
	FROM orders o
	JOIN customers c ON c.customer_id = o.customer_id
),
customers_rn2 AS (
	SELECT *
	FROM orders_with_customers
	WHERE rn_customers >= 2
),
customer_unique_id_grouped AS (
	SELECT customer_unique_id, COUNT(rn_customers)+1 AS fasce_acquisti
	FROM customers_rn2
	GROUP BY customer_unique_id
)
SELECT 
	fasce_acquisti, 
	COUNT(customer_unique_id) AS n_clienti,
	ROUND(COUNT(customer_unique_id) *100.0 / 2997, 2) AS pct_clienti
FROM customer_unique_id_grouped
GROUP BY fasce_acquisti
ORDER BY fasce_acquisti; 

----> 3. CONCLUSIONE: il cliente è customer_unique_id e per "acquisto" conto ogni ordine, in tutti gli stati.
---- 2.997 clienti su 96.096 (circa il 3,1%) hanno fatto almeno un secondo ordine. Tra questi,
---- il 91,6% ne ha fatti 2, il 6,8% ne ha fatti 3, il massimo è 17 (un cliente, non controllato).
---- Quasi tutta la clientela compra una sola volta.
---- Limite: gli stati non sono filtrati, quindi il 3,1% può includere secondi ordini cancellati.















