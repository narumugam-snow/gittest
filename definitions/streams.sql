-- Streams for Change Data Capture (CDC)

-- Stream on orders table to capture all changes
CREATE OR REPLACE STREAM DEMO_INGEST_DB.RAW.ORDERS_STREAM
    ON TABLE DEMO_INGEST_DB.RAW.ORDERS_RAW
    SHOW_INITIAL_ROWS = FALSE
    APPEND_ONLY = FALSE
    COMMENT = 'Captures INSERT, UPDATE, DELETE on orders';

-- Stream on customers table
CREATE OR REPLACE STREAM DEMO_INGEST_DB.RAW.CUSTOMERS_STREAM
    ON TABLE DEMO_INGEST_DB.RAW.CUSTOMERS_RAW
    SHOW_INITIAL_ROWS = FALSE
    APPEND_ONLY = FALSE
    COMMENT = 'Captures changes to customer records';

-- Append-only stream for events (more efficient for insert-only tables)
CREATE OR REPLACE STREAM DEMO_INGEST_DB.RAW.CUSTOMER_EVENTS_STREAM
    ON TABLE DEMO_INGEST_DB.RAW.CUSTOMER_EVENTS
    SHOW_INITIAL_ROWS = FALSE
    APPEND_ONLY = TRUE
    COMMENT = 'Append-only stream for event data';
