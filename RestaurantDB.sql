CREATE TYPE DishCategory AS ENUM (
	'Appetizer',
	'Main course',
	'Dessert'
);

CREATE TYPE DayOfWeek AS ENUM (
	'Monday',
	'Tuesday',
	'Wednesday',
	'Thursday',
	'Friday',
	'Saturday',
	'Sunday'
);

CREATE TYPE RestaurantJobTitle AS ENUM (
	'Chef',
	'Delivery person',
	'Waiter'
);

CREATE TYPE OrderType AS ENUM (
	'Dine-in',
	'Delivery'
);

CREATE TABLE Cities (
	CityId SERIAL PRIMARY KEY,
	Name VARCHAR(40) NOT NULL UNIQUE,
	CountryName VARCHAR(40) NOT NULL
);

CREATE TABLE Restaurants (
	RestaurantId SERIAL PRIMARY KEY,
	Name VARCHAR(40) NOT NULL,
	CityId INT REFERENCES Cities(CityId) NOT NULL,
	Capacity INT NOT NULL CHECK (Capacity > 0),
	DeliveryOption BOOLEAN NOT NULL
);

CREATE TABLE RestaurantWorkSchedules (
    RestaurantId INT REFERENCES Restaurants(RestaurantId) ON DELETE CASCADE,
    DayOfWeek DayOfWeek NOT NULL,
    OpenTime TIME NOT NULL,
    CloseTime TIME NOT NULL CHECK (CloseTime > OpenTime),
    PRIMARY KEY (RestaurantId, DayOfWeek)
);

CREATE TABLE Dishes (
	DishId SERIAL PRIMARY KEY,
	Name VARCHAR(40) NOT NULL,
	Category DishCategory NOT NULL,
	Calories INT NOT NULL CHECK (Calories >= 0)
);

CREATE TABLE RestaurantDishes (
	RestaurantId INT NOT NULL REFERENCES Restaurants(RestaurantId) ON DELETE CASCADE,
	DishId INT NOT NULL REFERENCES Dishes(DishId) ON DELETE CASCADE,
	PRIMARY KEY(RestaurantId, DishID),
	Price DECIMAL(10, 2) NOT NULL CHECK (Price >= 0),
	Availability BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE Workers (
	WorkerId SERIAL PRIMARY KEY,
	RestaurantId INT REFERENCES Restaurants(RestaurantId) NOT NULL,
	FirstName VARCHAR(40) NOT NULL,
	LastName VARCHAR(40) NOT NULL,
	DateOfBirth DATE NOT NULL CHECK (DateOfBirth < CURRENT_DATE),
	JobTitle RestaurantJobTitle NOT NULL,
	HasDriversLicence BOOLEAN NOT NULL
	CHECK (
        NOT (JobTitle = 'Delivery person' AND HasDriversLicence = FALSE)
    ),
    CHECK (
        NOT (JobTitle = 'Chef' AND DateOfBirth > CURRENT_DATE - INTERVAL '18 years')
    )
);

CREATE TABLE Customers (
	CustomerId SERIAL PRIMARY KEY,
	FirstName VARCHAR(40) NOT NULL,
	LastName VARCHAR(40) NOT NULL,
	DateOfBirth DATE NOT NULL CHECK (DateOfBirth < CURRENT_DATE),
	LoyalMember BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE Orders (
	OrderId SERIAL PRIMARY KEY,
	CustomerId INT REFERENCES Customers(CustomerId) NOT NULL,
	RestaurantId INT REFERENCES Restaurants(RestaurantId) NOT NULL,
	OrderType OrderType NOT NULL,
	DateOfOrder DATE NOT NULL DEFAULT CURRENT_DATE CHECK (DateOfOrder <= CURRENT_DATE),
	TotalAmount DECIMAL(10, 2) NOT NULL CHECK (TotalAmount >= 0)
);

CREATE TABLE Deliveries (
	OrderId INT REFERENCES Orders(OrderId) NOT NULL,
	WorkerId INT REFERENCES Workers(WorkerId) NOT NULL,
	Address VARCHAR(100) NOT NULL,
	CustomerComment VARCHAR(1000),
	PRIMARY KEY(OrderId, WorkerId)
);

CREATE TABLE OrderDishes (
    OrderId INT NOT NULL REFERENCES Orders(OrderId) ON DELETE CASCADE,
    DishId INT NOT NULL REFERENCES Dishes(DishId),
    PRIMARY KEY (OrderId, DishId),
    Quantity INT NOT NULL CHECK (Quantity > 0),
	Price DECIMAL(10, 2) NOT NULL CHECK (Price >= 0)
);

CREATE TABLE DishRatings (
    CustomerId INT REFERENCES Customers(CustomerId) NOT NULL,
    RestaurantId INT,
    DishId INT,
    Score DECIMAL(10, 2) NOT NULL CHECK (Score >= 1 AND Score <= 5),
    Comment VARCHAR(1000),
    FOREIGN KEY (RestaurantId, DishId) REFERENCES RestaurantDishes(RestaurantId, DishId) ON DELETE CASCADE,
	PRIMARY KEY (CustomerId, RestaurantId, DishId)
);

CREATE TABLE DeliveryRatings (
    CustomerId INT REFERENCES Customers(CustomerId) NOT NULL,
    OrderId INT,
    WorkerId INT,
    Score DECIMAL(10, 2) NOT NULL CHECK (Score >= 1 AND Score <= 5),
    Comment VARCHAR(1000),
    FOREIGN KEY (OrderId, WorkerId) REFERENCES Deliveries(OrderId, WorkerId) ON DELETE CASCADE,
	PRIMARY KEY (CustomerId, OrderId, WorkerId)
);

CREATE OR REPLACE FUNCTION check_delivery_option() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.OrderType = 'Delivery' THEN
        IF NOT EXISTS (SELECT 1 FROM Restaurants WHERE RestaurantId = NEW.RestaurantId AND DeliveryOption = TRUE) THEN
            RAISE EXCEPTION 'Restaurant does not offer delivery';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_delivery_option
BEFORE INSERT ON Orders
FOR EACH ROW EXECUTE FUNCTION check_delivery_option();

CREATE OR REPLACE FUNCTION calculate_total_amount() 
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Orders
    SET TotalAmount = (
        SELECT SUM(od.Quantity * od.Price)
        FROM OrderDishes od
        WHERE od.OrderId = NEW.OrderId
    )
    WHERE OrderId = NEW.OrderId;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_total_amount
BEFORE INSERT OR UPDATE ON OrderDishes
FOR EACH ROW EXECUTE FUNCTION calculate_total_amount();

CREATE OR REPLACE FUNCTION check_loyalty_eligibility() 
RETURNS TRIGGER AS $$
DECLARE
    total_orders INT;
    total_spent DECIMAL(10, 2);
BEGIN
    SELECT COUNT(*), SUM(TotalAmount) 
    INTO total_orders, total_spent
    FROM Orders
    WHERE CustomerId = NEW.CustomerId;
    
    IF total_orders >= 15 AND total_spent >= 1000 THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Customer does not meet the criteria for loyalty: 15 orders and total amount >= 1000';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_loyalty_eligibility
BEFORE INSERT OR UPDATE OF LoyalMember
ON Customers
FOR EACH ROW
EXECUTE FUNCTION check_loyalty_eligibility();

CREATE OR REPLACE FUNCTION check_order_type_for_delivery() 
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT OrderType FROM Orders WHERE OrderId = NEW.OrderId) <> 'Delivery' THEN
        RAISE EXCEPTION 'Deliveries are only allowed for orders of type "Delivery"';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_order_type_for_delivery
BEFORE INSERT
ON Deliveries
FOR EACH ROW
EXECUTE FUNCTION check_order_type_for_delivery();

CREATE OR REPLACE FUNCTION check_worker_is_delivery_person() 
RETURNS TRIGGER AS $$ 
BEGIN 
    IF (SELECT JobTitle FROM Workers WHERE WorkerId = NEW.WorkerId) <> 'Delivery person' THEN
        RAISE EXCEPTION 'Only workers with the job title "Delivery person" can be assigned to deliveries';
    END IF;

    IF (SELECT RestaurantId FROM Orders WHERE OrderId = NEW.OrderId) <> 
       (SELECT RestaurantId FROM Workers WHERE WorkerId = NEW.WorkerId) THEN
        RAISE EXCEPTION 'The worker must be from the same restaurant as the order';
    END IF;
    
    RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_worker_is_delivery_person
BEFORE INSERT
ON Deliveries
FOR EACH ROW
EXECUTE FUNCTION check_worker_is_delivery_person();

CREATE OR REPLACE FUNCTION set_order_dish_price()
RETURNS TRIGGER AS $$
BEGIN
    SELECT Price INTO NEW.Price
    FROM RestaurantDishes
    WHERE RestaurantId = NEW.RestaurantId
      AND DishId = NEW.DishId;

    IF NEW.Price IS NULL THEN
        RAISE EXCEPTION 'Price for the dish not found in the restaurant menu';
    END IF;

    NEW.Price := NEW.Price * NEW.Quantity;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_order_dish_price
BEFORE INSERT
ON OrderDishes
FOR EACH ROW
EXECUTE FUNCTION set_order_dish_price();
