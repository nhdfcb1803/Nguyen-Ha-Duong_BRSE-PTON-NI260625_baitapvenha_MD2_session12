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