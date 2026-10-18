CREATE TABLE IF NOT EXISTS receipt_image_transactions (
    receipt_image_id INTEGER NOT NULL REFERENCES analyzed_receipt_images(id),
    transaction_id INTEGER NOT NULL REFERENCES transactions(id),
    PRIMARY KEY (receipt_image_id, transaction_id)
);

INSERT INTO receipt_image_transactions (receipt_image_id, transaction_id)
SELECT id, transaction_id FROM analyzed_receipt_images WHERE transaction_id IS NOT NULL;

ALTER TABLE analyzed_receipt_images DROP COLUMN transaction_id;
