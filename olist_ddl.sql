-- Il file contiene la struttura delle nove tabelle del Brazilian E-Commerce Public Dataset by Olist, 
-- proveniente da Kaggle; lo script è stato generato da DBeaver dopo l'import
-- con le modifiche sui tipi di dato effettuate come riportato in README.md

-- public.customers definition

-- Drop table

-- DROP TABLE public.customers;

CREATE TABLE public.customers (
	customer_id varchar(50) NULL,
	customer_unique_id varchar(50) NULL,
	customer_zip_code_prefix varchar(10) NULL,
	customer_city varchar(50) NULL,
	customer_state varchar(50) NULL
);


-- public.geolocation definition

-- Drop table

-- DROP TABLE public.geolocation;

CREATE TABLE public.geolocation (
	geolocation_zip_code_prefix varchar(10) NULL,
	geolocation_lat float8 NULL,
	geolocation_lng float8 NULL,
	geolocation_city varchar(50) NULL,
	geolocation_state varchar(50) NULL
);


-- public.order_items definition

-- Drop table

-- DROP TABLE public.order_items;

CREATE TABLE public.order_items (
	order_id varchar(50) NULL,
	order_item_id int4 NULL,
	product_id varchar(50) NULL,
	seller_id varchar(50) NULL,
	shipping_limit_date timestamp NULL,
	price numeric(10, 2) NULL,
	freight_value numeric(10, 2) NULL
);


-- public.order_payments definition

-- Drop table

-- DROP TABLE public.order_payments;

CREATE TABLE public.order_payments (
	order_id varchar(50) NULL,
	payment_sequential int4 NULL,
	payment_type varchar(50) NULL,
	payment_installments int4 NULL,
	payment_value numeric(10, 2) NULL
);


-- public.order_reviews definition

-- Drop table

-- DROP TABLE public.order_reviews;

CREATE TABLE public.order_reviews (
	review_id varchar(50) NULL,
	order_id varchar(50) NULL,
	review_score int4 NULL,
	review_comment_title text NULL,
	review_comment_message text NULL,
	review_creation_date timestamp NULL,
	review_answer_timestamp timestamp NULL
);


-- public.orders definition

-- Drop table

-- DROP TABLE public.orders;

CREATE TABLE public.orders (
	order_id varchar(50) NULL,
	customer_id varchar(50) NULL,
	order_status varchar(50) NULL,
	order_purchase_timestamp timestamp NULL,
	order_approved_at timestamp NULL,
	order_delivered_carrier_date timestamp NULL,
	order_delivered_customer_date timestamp NULL,
	order_estimated_delivery_date timestamp NULL
);


-- public.product_category_name_translation definition

-- Drop table

-- DROP TABLE public.product_category_name_translation;

CREATE TABLE public.product_category_name_translation (
	product_category_name varchar(50) NULL,
	product_category_name_english varchar(50) NULL
);


-- public.products definition

-- Drop table

-- DROP TABLE public.products;

CREATE TABLE public.products (
	product_id varchar(50) NULL,
	product_category_name varchar(50) NULL,
	product_name_lenght int4 NULL,
	product_description_lenght int4 NULL,
	product_photos_qty int4 NULL,
	product_weight_g int4 NULL,
	product_length_cm int4 NULL,
	product_height_cm int4 NULL,
	product_width_cm int4 NULL
);


-- public.sellers definition

-- Drop table

-- DROP TABLE public.sellers;

CREATE TABLE public.sellers (
	seller_id varchar(50) NULL,
	seller_zip_code_prefix varchar(10) NULL,
	seller_city varchar(50) NULL,
	seller_state varchar(50) NULL
);