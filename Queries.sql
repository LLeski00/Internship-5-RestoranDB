SELECT DISTINCT dish.Name, restaurantdish.Price
FROM Dishes dish
JOIN RestaurantDishes restaurantdish ON dish.DishId = restaurantdish.DishId
WHERE restaurantdish.Price < 15;

SELECT OrderId, DateOfOrder, TotalAmount
FROM Orders 
WHERE EXTRACT(YEAR FROM DateOfOrder) = 2023 AND TotalAmount > 50;

SELECT WorkerId, COUNT(*) AS SuccessfulDeliveries
FROM Deliveries
GROUP BY WorkerId
HAVING COUNT(*) > 100;

SELECT w.FirstName, w.LastName, r.Name AS RestaurantName
FROM Workers w
JOIN Restaurants r ON w.RestaurantId = r.RestaurantId
JOIN Cities c ON r.CityId = c.CityId
WHERE w.JobTitle = 'Chef' AND c.Name = 'Zagreb';

SELECT r.Name AS RestaurantName, COUNT(o.OrderId) AS NumberOfOrders
FROM Restaurants r
JOIN Cities c ON r.CityId = c.CityId
JOIN Orders o ON r.RestaurantId = o.RestaurantId
WHERE c.Name = 'Split'
  AND EXTRACT(YEAR FROM o.DateOfOrder) = 2023
GROUP BY r.Name
ORDER BY NumberOfOrders DESC;

SELECT d.DishId, d.Name SUM(od.Quantity) AS TotalQuantity
FROM Dishes d
JOIN OrderDishes od ON d.DishId = od.DishId
JOIN Orders o ON od.OrderId = o.OrderId
WHERE d.Category = 'Dessert'
AND o.DateOfOrder BETWEEN '2023-12-01' AND '2023-12-31'
GROUP BY d.Name
HAVING SUM(od.Quantity) > 10;

SELECT c.LastName, COUNT(o.OrderId) AS NumberOfOrders
FROM Customers c
JOIN Orders o ON c.CustomerId = o.CustomerId
WHERE c.LastName LIKE 'M%'
GROUP BY c.LastName;

SELECT r.Name AS RestaurantName, ROUND(AVG(dr.Score), 2) AS AverageScore
FROM Restaurants r
JOIN Cities c ON r.CityId = c.CityId
JOIN DishRatings dr ON r.RestaurantId = dr.RestaurantId
WHERE c.Name = 'Rijeka'
GROUP BY r.RestaurantId;

SELECT r.RestaurantId, r.Name 
FROM Restaurants r
WHERE r.Capacity > 30 AND r.DeliveryOption = TRUE;

DELETE FROM RestaurantDishes
WHERE (RestaurantId, DishId) IN (
    SELECT rd.RestaurantId, rd.DishId
    FROM RestaurantDishes rd
    LEFT JOIN OrderDishes od ON rd.DishId = od.DishId
    LEFT JOIN Orders o ON od.OrderId = o.OrderId
    WHERE o.OrderId IS NULL OR o.DateOfOrder <= CURRENT_DATE - INTERVAL '2 years'
);

UPDATE Customers
SET LoyalMember = FALSE
WHERE CustomerId IN (
    SELECT DISTINCT c.CustomerId
    FROM Customers c
    LEFT JOIN Orders o ON c.CustomerId = o.CustomerId
    GROUP BY c.CustomerId
    HAVING MAX(o.DateOfOrder) < CURRENT_DATE - INTERVAL '1 year' OR MAX(o.DateOfOrder) IS NULL
);
