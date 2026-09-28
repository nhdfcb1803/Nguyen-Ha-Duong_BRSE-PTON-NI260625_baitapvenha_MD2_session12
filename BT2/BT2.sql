CREATE DATABASE ecommerce;
USE ecommerce;
-- 1. Bảng customers (Khách hàng)
CREATE TABLE customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Bảng orders (Đơn hàng)
CREATE TABLE orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) DEFAULT 0,
    status ENUM('Pending', 'Completed', 'Cancelled') DEFAULT 'Pending',
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- 3. Bảng products (Sản phẩm)
CREATE TABLE products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Bảng order_items (Chi tiết đơn hàng)
CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- 5. Bảng inventory (Kho hàng)
CREATE TABLE inventory (
    product_id INT PRIMARY KEY,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
);

-- 6. Bảng payments (Thanh toán)
CREATE TABLE payments (
    payment_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2) NOT NULL,
    payment_method ENUM('Credit Card', 'PayPal', 'Bank Transfer', 'Cash') NOT NULL,
    status ENUM('Pending', 'Completed', 'Failed') DEFAULT 'Pending',
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);


DELIMITER $$

CREATE TRIGGER before_insert_order_item
BEFORE INSERT ON order_items
FOR EACH ROW

BEGIN
    DECLARE current_stock INT;
    SELECT stock_quantity
    INTO current_stock
    FROM inventory
    WHERE product_id = NEW.product_id;

    IF current_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sản phẩm không tồn tại trong kho';
    ELSEIF current_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Số lượng sản phẩm trong kho không đủ';
    ELSE
        UPDATE inventory
        SET stock_quantity = stock_quantity - NEW.quantity
        WHERE product_id = NEW.product_id;
    END IF;
END $$
DELIMITER ;

DELIMITER $$

CREATE TRIGGER after_insert_order_item
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = total_amount + (NEW.quantity * NEW.price)
    WHERE order_id = NEW.order_id;
END $$
DELIMITER ;

DELIMITER $$

CREATE TRIGGER before_update_order_item
BEFORE UPDATE ON order_items
FOR EACH ROW
BEGIN
    DECLARE current_stock INT;
    IF NEW.quantity > OLD.quantity THEN
        SELECT stock_quantity
        INTO current_stock
        FROM inventory
        WHERE product_id = NEW.product_id;
        IF current_stock < (NEW.quantity - OLD.quantity) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Số lượng sản phẩm trong kho không đủ';
        ELSE
            UPDATE inventory
            SET stock_quantity = stock_quantity - (NEW.quantity - OLD.quantity)
            WHERE product_id = NEW.product_id;
        END IF;
    ELSEIF NEW.quantity < OLD.quantity THEN
        UPDATE inventory
        SET stock_quantity = stock_quantity + (OLD.quantity - NEW.quantity)
        WHERE product_id = NEW.product_id;
    END IF;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER after_update_order_item
AFTER UPDATE ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = total_amount
                         - (OLD.quantity * OLD.price)
                         + (NEW.quantity * NEW.price)
    WHERE order_id = NEW.order_id;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER before_delete_order
BEFORE DELETE ON orders
FOR EACH ROW

BEGIN
    IF OLD.status = 'Completed' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Không thể xóa đơn hàng đã hoàn thành';
    END IF;
END $$
DELIMITER ;

DELIMITER $$

CREATE TRIGGER after_delete_order_item
AFTER DELETE ON order_items
FOR EACH ROW
BEGIN
    UPDATE inventory
    SET stock_quantity = stock_quantity + OLD.quantity
    WHERE product_id = OLD.product_id;
    UPDATE orders
    SET total_amount = total_amount - (OLD.quantity * OLD.price)
    WHERE order_id = OLD.order_id;
END $$
DELIMITER ;

DROP TRIGGER before_insert_order_item;
DROP TRIGGER after_insert_order_item;
DROP TRIGGER before_update_order_item;
DROP TRIGGER after_update_order_item;
DROP TRIGGER before_delete_order;
DROP TRIGGER after_delete_order_item;

DELIMITER $$

CREATE PROCEDURE sp_create_order(
    IN p_customer_id INT,
    IN p_product_id INT,
    IN p_quantity INT,
    IN p_price DECIMAL(10,2)
)
BEGIN
    DECLARE v_stock INT;
    DECLARE v_order_id INT;
    START TRANSACTION;
    
    SELECT stock_quantity
    INTO v_stock
    FROM inventory
    WHERE product_id = p_product_id;

    IF v_stock IS NULL OR v_stock < p_quantity THEN
        ROLLBACK;
        SELECT 'Số lượng tồn kho không đủ' AS message;
    ELSE

        INSERT INTO orders (
            customer_id,
            total_amount,
            status
        )
        VALUES (
            p_customer_id,
            p_quantity * p_price,
            'Pending'
        );

        SET v_order_id = LAST_INSERT_ID();

        INSERT INTO order_items (
            order_id,
            product_id,
            quantity,
            price
        )
        VALUES (
            v_order_id,
            p_product_id,
            p_quantity,
            p_price
        );

        UPDATE inventory
        SET stock_quantity = stock_quantity - p_quantity
        WHERE product_id = p_product_id;

        COMMIT;

        SELECT 'Tạo đơn hàng thành công' AS message,
               v_order_id AS order_id;
    END IF;
END $$

DELIMITER ;

DELIMITER $$

CREATE PROCEDURE sp_pay_order(
    IN p_order_id INT,
    IN p_payment_method VARCHAR(50)
)
BEGIN

    DECLARE v_status VARCHAR(50);
    DECLARE v_total_amount DECIMAL(10,2);

    START TRANSACTION;

    SELECT status, total_amount
    INTO v_status, v_total_amount
    FROM orders
    WHERE order_id = p_order_id;

    IF v_status IS NULL THEN
        ROLLBACK;
        SELECT 'Đơn hàng không tồn tại' AS message;

    ELSEIF v_status <> 'Pending' THEN
        ROLLBACK;
        SELECT 'Đơn hàng không ở trạng thái Pending' AS message;
    ELSE

        INSERT INTO payments (
            order_id,
            amount,
            payment_method,
            status
        )
        VALUES (
            p_order_id,
            v_total_amount,
            p_payment_method,
            'Completed'
        );

        UPDATE orders
        SET status = 'Completed'
        WHERE order_id = p_order_id;

        COMMIT;
        SELECT 'Thanh toán thành công' AS message;
    END IF;
END $$

DELIMITER ;

DELIMITER $$

CREATE PROCEDURE sp_cancel_order(
    IN p_order_id INT
)
BEGIN

    DECLARE v_status VARCHAR(50);

    START TRANSACTION;

    SELECT status
    INTO v_status
    FROM orders
    WHERE order_id = p_order_id;

    IF v_status IS NULL THEN
        ROLLBACK;
        SELECT 'Đơn hàng không tồn tại' AS message;
    ELSEIF v_status <> 'Pending' THEN
        ROLLBACK;
        SELECT 'Chỉ có thể hủy đơn hàng đang ở trạng thái Pending' AS message;

    ELSE
        UPDATE inventory AS i
        INNER JOIN order_items AS oi
            ON i.product_id = oi.product_id
        SET i.stock_quantity = i.stock_quantity + oi.quantity
        WHERE oi.order_id = p_order_id;
        DELETE FROM order_items
        WHERE order_id = p_order_id;
        UPDATE orders
        SET status = 'Cancelled'
        WHERE order_id = p_order_id;
        COMMIT;
        SELECT 'Hủy đơn hàng thành công' AS message;
    END IF;

END $$
DELIMITER ;

DROP PROCEDURE sp_create_order;
DROP PROCEDURE sp_pay_order;
DROP PROCEDURE sp_cancel_order;