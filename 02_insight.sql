-- 1. quanto avrebbe dovuto pagare ogni cliente per ogni ordine in base agli 
-- articoli e quanto ha pagato davvero

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


/*
----> 1. CONCLUSIONE:
Su 99.441 ordini, 98.092 (98,64%) hanno pagato esattamente il dovuto (prezzo + spedizione); di questi, 3 sono
falsi saldati (senza articoli e senza pagamenti reali, 0 − 0).
210 ordini (0,21%) hanno pagato meno del dovuto: comprendono l'ordine senza pagamenti registrati e,
verosimilmente, pagamenti parziali (da distinguere). Non analizzati in questa domanda: da verificare.
1.139 ordini (1,15%) hanno pagato più del dovuto: 772 sono ordini senza articoli, quindi dovuto non
calcolabile e non un vero eccesso; i restanti 367 hanno articoli e un pagato superiore al dovuto.
Nei 367 l'eccesso medio cresce con il numero di rate (circa 0,3% con 1 rata, 5% con 3, oltre 20% con 13 o più):
coerente con un costo aggiuntivo sulle rate, non dimostrato perché il dataset non ha dati sugli interessi.
Un'eccezione ad esempio sono i piani a  10 rate, per un totale di 61 ordini, che hanno una media più bassa (7,8%); 
le classi con 13 o più rate hanno 1-2 ordini.
 */


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

/*
----> 2. CONCLUSIONE: nessun delivered ha la data di acquisto successiva alla consegna. 
il tempo medio di consegna nello stato del cliente va da 8,8 giorni per SP a 29,4 per RR, 
9 stati superano le tre settimane: i più lenti nell'arrivo degli ordini sono RR, AP, AM. 
calcolo effettuato su 96.470 ordini delivered. 
 */



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

/*
 ----> 3. CONCLUSIONE: il cliente è customer_unique_id e per "acquisto" conto ogni ordine, in tutti gli stati.
2.997 clienti su 96.096 (circa il 3,1%) hanno fatto almeno un secondo ordine. Tra questi,
il 91,6% ne ha fatti 2, il 6,8% ne ha fatti 3, il massimo è 17 (un cliente, non controllato).
Quasi tutta la clientela compra una sola volta.
Limite: gli stati non sono filtrati, quindi il 3,1% può includere secondi ordini cancellati.
 */

-- CREAZIONE VIEW --
-- servirà per l'analisi dei successivi tre insight che prevedono l'unione delle stesse 4 tabelle, 
-- considerandone tutte le colonne del caso
CREATE VIEW delivered_items_view AS
-- LEFT JOIN tra products e traduzioni per non perdere nessun product_id
WITH products_with_category_english AS (
	SELECT p.product_id, p.product_category_name, pt.product_category_name_english 
	FROM products p
	LEFT JOIN product_category_name_translation pt ON p.product_category_name = pt.product_category_name  
),
-- JOIN tra order_items e orders per filtrare su order status delivered e mantenerne solo i relativi product_id
product_id_delivered AS (
	SELECT o.order_id, oi.product_id, oi.seller_id, oi.price, o.order_purchase_timestamp   
	FROM order_items oi
	JOIN orders o ON o.order_id = oi.order_id AND o.order_status = 'delivered'
),
-- JOIN tra le prime due CTE
products_price_cat_name AS (
	SELECT 
		order_id,
		pwce.product_id, 
		pid.seller_id, 
		pid.price,
		COALESCE(product_category_name_english, product_category_name, 'senza_categoria') AS cat_name,
		pid.order_purchase_timestamp
	FROM products_with_category_english pwce
	JOIN product_id_delivered pid ON pid.product_id = pwce.product_id
)
SELECT *
FROM products_price_cat_name;


-- 4. Top 3 prodotti per ricavi in ogni categoria, presa la view precedentemente costruita: 
-- da order_items consideriamo i vari "product_id" e e i loro ricavi dati da "price"
-- da orders ci teniamo solo i prodotti con "order_status" delivered, che hanno portato quindi effettivamente ad un ricavo
-- da products invece consideriamo "product_category_name" 
-- e da product_category_name_translation la corrispettiva traduzione

-- items raggruppati
WITH delivered_items_grouped AS (
	SELECT
		product_id,
		cat_name,
		SUM(price) AS tot_price
	FROM delivered_items_view
	GROUP BY product_id, cat_name
),
-- aggiunta del rank
dr_delivered_items AS (
	SELECT 
		product_id,
		cat_name,
		tot_price,
		dense_rank() OVER(PARTITION BY cat_name ORDER BY tot_price DESC) AS dense_rank_products
	FROM delivered_items_grouped
)
SELECT *
FROM dr_delivered_items
WHERE dense_rank_products <= 3
ORDER BY cat_name, dense_rank_products;

-- categorie con più di 3 righe cioè pareggi di ricavo con DENSE_RANK:
-- sono due categorie cioè fashion_childrens_clothes (4) e furniture_mattress_and_upholstery (4)
WITH delivered_items_grouped AS (
	SELECT product_id, cat_name, SUM(price) AS tot_price
	FROM delivered_items_view
	GROUP BY product_id, cat_name
),
dr_delivered_items AS (
	SELECT product_id, cat_name, tot_price,
		dense_rank() OVER(PARTITION BY cat_name ORDER BY tot_price DESC) AS dense_rank_products
	FROM delivered_items_grouped
),
selct_finale AS (
	SELECT *
	FROM dr_delivered_items
	WHERE dense_rank_products <= 3
)
SELECT cat_name, COUNT(*)
FROM selct_finale
GROUP BY cat_name
HAVING COUNT(*) > 3;

-- categorie con meno di 3 righe cioè con meno di 3 prodotti venduti: 
-- cds_dvds_musicals (un prodotto), pc_gamer e security_and_services entrambe con due prodotti
WITH delivered_items_grouped AS (
	SELECT product_id, cat_name, SUM(price) AS tot_price
	FROM delivered_items_view
	GROUP BY product_id, cat_name
),
dr_delivered_items AS (
	SELECT product_id, cat_name, tot_price,
		dense_rank() OVER(PARTITION BY cat_name ORDER BY tot_price DESC) AS dense_rank_products
	FROM delivered_items_grouped
),
selct_finale AS (
	SELECT *
	FROM dr_delivered_items
	WHERE dense_rank_products <= 3
)
SELECT cat_name, COUNT(*)
FROM selct_finale
GROUP BY cat_name
HAVING COUNT(*) < 3;

/*
----> 4. CONCLUSIONE ricavo = somma di price (senza spedizione) sugli articoli di ordini delivered. Classifica per prodotto
dentro ogni categoria: 74 categorie (comprese le 610 referenze senza categoria, tenute insieme come "senza_categoria"), 220 righe.
Con DENSE_RANK 2 categorie hanno 4 prodotti per un pareggio, 3 ne hanno meno di 3.
Il primo prodotto di ogni categoria va da 180 reais (fashion_childrens_clothes) a 63.560 (health_beauty);
metà delle categorie ha un primo prodotto sotto i 5.000 e 28 sopra i 10.000. In testa ci sono health_beauty,
computers, computers_accessories, bed_bath_table e baby.
"senza_categoria" è all'undicesimo posto per ricavo del primo prodotto, cioè 23.368.
*/

-- 5. Venditori con ricavi sopra la media della loro categoria: 
-- legge dalla view "delivered_items_view": 

-- raggruppo per venditori sommandone i ricavi 
-- confronto per ricavi venditore > media venditore per categoria

-- raggruppo per categoria e venditore calcolandone il ricavato 
WITH seller_revenue_per_cat AS (
	SELECT seller_id, cat_name, SUM(price) AS tot_seller_cat
	FROM delivered_items_view
	GROUP BY seller_id, cat_name 
),
avg_revenue_per_cat AS (
	SELECT cat_name, AVG(tot_seller_cat) AS avg_cat
	FROM seller_revenue_per_cat 
	GROUP BY cat_name 
),
-- unione delle due tabelle per confronto successivo
seller_revenue_avg_per_cat AS (
	SELECT src.seller_id, src.cat_name, src.tot_seller_cat, arc.avg_cat 
	FROM seller_revenue_per_cat src
	JOIN avg_revenue_per_cat arc ON arc.cat_name = src.cat_name
),
-- colonna in aggiunta per identificare i venditori con ricavato al di sopra della media, in modo da poter utilizzare
-- la select esterna dopo
sellers_avg_over AS (
	SELECT 
		seller_id, cat_name, tot_seller_cat, avg_cat, 
		CASE 
			WHEN tot_seller_cat > avg_cat THEN 'OVER'
			ELSE 'NON_OVER'
		END AS seller_check
	FROM seller_revenue_avg_per_cat
) 
SELECT seller_check, COUNT(*) AS n_coppie
FROM sellers_avg_over
GROUP BY seller_check;

/*
----> 5. CONCLUSIONE: Confronto tra il ricavo di ogni venditore in una categoria (somma di price, ordini delivered) e 
la media dei ricavi dei venditori di quella categoria.
Su 6.398 coppie venditore-categoria 1.298, circa il 20,3%, sono sopra la media: la maggior parte dei venditori è al di sotto
perché i pochi venditori grandi tirano su la media.
"senza_categoria" è inclusa nel confronto con 247 coppie, ovvero il 3,9% del totale, anche se raggruppa prodotti diversi.
le categorie con un solo venditore non compaiono.
*/

-- 6. Ordini e ricavi per mese, con variazione sul mese precedente
-- tabella da view "delivered_items_view"

SELECT *
FROM delivered_items_view
LIMIT 5;


WITH date_management AS (
	SELECT 
		order_id, product_id, seller_id, price, cat_name,
		date_trunc('month', order_purchase_timestamp) AS dt_order_purchase
	FROM delivered_items_view
),
items_grouped_by_month AS (
	SELECT 
		dt_order_purchase, 
		COUNT(DISTINCT order_id) AS n_orders_per_month, 
		SUM(price) AS tot_revenue_per_month
	FROM date_management
	GROUP BY dt_order_purchase
)
-- il CASE WHEN lo utilizzo per far considerare null la variazione rispetto ad un eventuale mese assente nell'elenco
SELECT 
	dt_order_purchase, 
	n_orders_per_month, 
	tot_revenue_per_month,
	CASE 
		WHEN lag(dt_order_purchase, 1) OVER(ORDER BY dt_order_purchase) = dt_order_purchase - INTERVAL '1 month'
			THEN tot_revenue_per_month - LAG(tot_revenue_per_month, 1) OVER(ORDER BY dt_order_purchase)
	END AS rev_delta,
		CASE 
		WHEN lag(dt_order_purchase, 1) OVER(ORDER BY dt_order_purchase) = dt_order_purchase - INTERVAL '1 month'
			THEN ROUND((tot_revenue_per_month - LAG(tot_revenue_per_month, 1) OVER(ORDER BY dt_order_purchase)) * 100.0 / NULLIF(LAG(tot_revenue_per_month, 1) OVER(ORDER BY dt_order_purchase), 0), 2)
	END AS pct_delta
FROM items_grouped_by_month
ORDER BY dt_order_purchase; 


/*
----> 6. CONCLUSIONE: Ordini e ricavi per mese (solo ordini delivered, con mese considerato quello di acquisto) e variazione sul mese precedente.
la serie va da settembre 2016 ad agosto 2018 per un totale di 23 mesi ma manca novembre 2016 quindi la variazione di 
dicembre 2016 per costruzione della query è lasciata vuota.
I ricavi crescono da 111.798 reais a gennaio 2017 a 924.645 a gennaio 2018, e il picco è novembre 2017 con 7.289 ordini per un totale di 
987.765 reais e un +52,4% su ottobre), seguito da dicembre 2017 (-26,5%). nel 2018 i ricavi restano stabili tra 826.000 e 977.000 al mese.
le variazioni percentuali dei mesi di ottobre 2016 e gennaio 2017 sono calcolate su ricavi piccoli.
*/


-- 7. Ordini consegnati in ritardo e punteggio delle recensioni 
-- tra i vari ordini in orders considero quelli per cui order_delivered_customer_date > order_estimated_delivery_date
-- di questi in ritardo considero i review_score in order_reviews

-- innanzitutto filtro gli ordini per 'delivered' e inoltre non considero quelli che hanno NULL
-- nelle due colonne timestamp considerate dato che a quel punto non si può sapere se gli ordini
-- sono stati consegnati in tempo o meno. 
-- controllato con un WHERE nella SELECT esterna: delivered=96478, delivered con 
-- entrambe le date = 96470; puntuali = 88644, in ritardo = 7826
WITH order_delivered_timestamp AS (
	SELECT 
		order_id,
		CASE 
			WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'puntuale'
			ELSE 'non puntuale'
		END AS consegna_ordine
	FROM orders 
	WHERE 
		order_status = 'delivered' 
		AND order_delivered_customer_date IS NOT NULL
		AND order_estimated_delivery_date IS NOT NULL
),
order_id_grouped_avg AS (
	SELECT order_id, COUNT(review_id) AS n_review_id, AVG(review_score) AS avg_review_score_per_order
	FROM order_reviews 
	GROUP BY order_id 
),
-- 646 ordini escono dalla JOIN perchè senza review
order_review_id AS (
	SELECT odt.order_id, odt.consegna_ordine, oiga.n_review_id, oiga.avg_review_score_per_order 
	FROM order_delivered_timestamp odt
	JOIN order_id_grouped_avg oiga ON oiga.order_id = odt.order_id 
)
SELECT consegna_ordine, COUNT(*) AS n_orders, AVG(avg_review_score_per_order) AS avg_review_score
FROM order_review_id
GROUP BY consegna_ordine;

/*
----> 7. CONCLUSIONE Ordini consegnati in ritardo e punteggio delle recensioni
il ritardo è dato dalla data di consegna al cliente successiva alla data stimata, nella query <= sarebbe un ordine puntuale. 
analizzati 95.824 ordini delivered di cui esclusi 8 senza data di consegna e 646 senza recensione.
Per gli ordini con più recensioni il punteggio è la media delle loro recensioni visto che in order_reviews la chiave è composta.
gli ordini in ritardo sono 7.661, ovvero l'8,0%, con punteggio medio della review di 2,57 mentre i puntuali sono 88.163 ordini
con punteggio medio di 4,29.
la differenza è di 1,73 punti con i ritardi associati a recensioni molto più basse ma è un'associazione, non una prova che ne
sia la causa.
*/











