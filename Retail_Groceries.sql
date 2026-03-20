/* =========================================================
   Retail Grocery — Real Product & Store Names
   Permanent tables: Numbers, Customers, Products, Sales, Stores, Suppliers
   - Products = real grocery items (brands/SKUs)
   - Stores   = real retail chains combined with city labels
   - Sales    = transactions (with NULLs & duplicates)
   - City weighting to vary "Orders by City"
   - No foreign keys (per your original requirement)
   Authored by Namaxee
   ========================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ---------- (Re)Create database ---------- */
IF DB_ID('RetailGrocery_Staging') IS NOT NULL
BEGIN
    ALTER DATABASE RetailGrocery_Staging SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RetailGrocery_Staging;
END;
CREATE DATABASE RetailGrocery_Staging;
GO

USE RetailGrocery_Staging;
/* Keep everything below in ONE batch (no more GO) */

/* ---------- Sizing knobs ---------- */
DECLARE @Customers            int = 50000;
DECLARE @Products             int = 1200;
DECLARE @Stores               int = 150;
DECLARE @Suppliers            int = 50;
DECLARE @Sales                int = 160000;   -- keep >= 100000
DECLARE @DuplicateCustomers   int = 2500;
DECLARE @DuplicateSales       int = 5000;

/* ---------- Numbers table (1..900000) ---------- */
IF OBJECT_ID('dbo.Numbers','U') IS NOT NULL DROP TABLE dbo.Numbers;
CREATE TABLE dbo.Numbers(n int not null primary key);
;WITH src AS
(
    SELECT TOP (900000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Numbers(n) SELECT rn FROM src;

/* ---------- Permanent base tables (no foreign keys) ---------- */
IF OBJECT_ID('dbo.Customers','U') IS NOT NULL DROP TABLE dbo.Customers;
CREATE TABLE dbo.Customers
(
    CustomerID  int identity(1,1) primary key,
    FirstName   nvarchar(50)  null,
    LastName    nvarchar(50)  null,
    Email       nvarchar(120) null,
    Phone       nvarchar(30)  null,
    Gender      nvarchar(10)  null,
    BirthDate   date          null,
    City        nvarchar(60)  null,
    State       nvarchar(60)  null,
    Country     nvarchar(60)  null,
    SignupDate  date          null
);

IF OBJECT_ID('dbo.Suppliers','U') IS NOT NULL DROP TABLE dbo.Suppliers;
CREATE TABLE dbo.Suppliers
(
    SupplierID   int identity(1,1) primary key,
    SupplierName nvarchar(120) not null,
    Country      nvarchar(60)  null
);

IF OBJECT_ID('dbo.Stores','U') IS NOT NULL DROP TABLE dbo.Stores;
CREATE TABLE dbo.Stores
(
    StoreID   int identity(1,1) primary key,
    StoreName nvarchar(120) not null,
    City      nvarchar(60)  null,
    State     nvarchar(60)  null,
    Country   nvarchar(60)  null,
    StoreType nvarchar(30)  null,    -- Retail / Outlet / Express / Flagship
    OpenDate  date          null
);

IF OBJECT_ID('dbo.Products','U') IS NOT NULL DROP TABLE dbo.Products;
CREATE TABLE dbo.Products
(
    ProductID      int identity(1,1) primary key,
    SKU            nvarchar(30)  not null,
    ProductName    nvarchar(200) not null,   -- real grocery items
    Category       nvarchar(60)  not null,   -- Produce, Dairy, Pantry, Snacks, Beverages, Meat, Seafood, Frozen, Household, Baby, Bakery, Breakfast, etc.
    Subcategory    nvarchar(60)  null,
    Brand          nvarchar(60)  null,       -- some NULLs on purpose
    Model          nvarchar(60)  null,       -- pack/variant (optional)
    LaunchDate     date          null,
    UnitPrice      decimal(10,2) null,
    CostPrice      decimal(10,2) null,
    WarrantyMonths int           null,       -- placeholder for schema consistency
    SupplierID     int           null
);

IF OBJECT_ID('dbo.Sales','U') IS NOT NULL DROP TABLE dbo.Sales;
CREATE TABLE dbo.Sales
(
    SalesID       bigint identity(1,1) primary key,
    OrderDate     date          not null,
    ShipDate      date          null,
    CustomerID    int           null,
    StoreID       int           null,
    ProductID     int           null,
    Quantity      int           not null,
    UnitPrice     decimal(10,2) null,
    Discount      decimal(5,2)  null,
    TotalAmount   decimal(12,2) null,
    PaymentMethod nvarchar(30)  null,   -- Credit Card / Debit Card / E-Wallet / Bank Transfer / Cash
    Channel       nvarchar(30)  null,   -- Online / In-Store / Marketplace
    OrderStatus   nvarchar(20)  null    -- Completed / Cancelled / Returned / Pending
);

/* =========================================================
   Helper lists as TABLE VARIABLES (no permanent extras)
   ========================================================= */

/* --- Real FMCG / grocery suppliers (manufacturers/distributors) --- */
DECLARE @SupplierNames TABLE
(
    RowID int identity(1,1) primary key,
    SupplierName nvarchar(120),
    Country nvarchar(60)
);
INSERT @SupplierNames(SupplierName, Country) VALUES
('Nestlé','Switzerland'),
('F&N Beverages (Etika)','Malaysia'),
('Coca-Cola Beverages Malaysia','Malaysia'),
('PepsiCo / Etika','Malaysia'),
('Mondelez International','USA'),
('Danone','France'),
('Dutch Lady (FrieslandCampina)','Netherlands'),
('Fonterra (Anchor)','New Zealand'),
('Yeo''s','Singapore'),
('Ayam Brand','Malaysia'),
('Mamee-Double Decker','Malaysia'),
('Gardenia Bakeries (KL)','Malaysia'),
('The Italian Baker (Massimo)','Malaysia'),
('San Remo','Australia'),
('Heinz / ABC','USA'),
('Kimball','Malaysia'),
('Maggi (Nestlé)','Switzerland'),
('Prego (Campbell)','USA'),
('Colgate-Palmolive','USA'),
('Unilever','UK'),
('Procter & Gamble (P&G)','USA'),
('Reckitt','UK'),
('Kimberly-Clark','USA'),
('SC Johnson','USA'),
('Johnson & Johnson','USA'),
('Spritzer','Malaysia'),
('Cap Kipas Udang (Tepung)','Malaysia'),
('Lee Kum Kee','Hong Kong'),
('Pran / Radhuni','Bangladesh'),
('CP Foods','Thailand'),
('Brahim''s','Malaysia'),
('Baba''s','Malaysia'),
('Adabi','Malaysia'),
('MILO (Nestlé)','Switzerland'),
('Nescafé (Nestlé)','Switzerland'),
('Oreo (Mondelez)','USA'),
('Huggies (Kimberly-Clark)','USA'),
('Drypers (SCA)','Sweden'),
('Dynamo (P&G)','USA'),
('Breeze (Unilever)','UK');

INSERT dbo.Suppliers(SupplierName, Country)
SELECT TOP (@Suppliers) SupplierName, Country
FROM @SupplierNames
ORDER BY RowID;

/* --- Realistic store/chain brand names (declare BEFORE CTE) --- */
DECLARE @StoreBrands TABLE
(
    BrandID int identity(1,1) primary key,
    BrandName nvarchar(80)
);
INSERT @StoreBrands(BrandName) VALUES
('Lotus''s'),('AEON'),('AEON Big'),('Giant'),('Mydin'),
('Jaya Grocer'),('Village Grocer'),('Mercato'),('Cold Storage'),('Econsave'),
('NSK'),('99 Speedmart'),('The Store'),('HeroMarket'),('TF Value-Mart'),
('Ben''s Independent Grocer (B.I.G.)'),('IKEA Swedish Food Market'),('FamilyMart'),('7-Eleven'),('KK Super Mart');

DECLARE @StoreBrandCount int = (SELECT COUNT(*) FROM @StoreBrands);

/* --- Cities reference CTE (must be followed immediately by INSERT) --- */
;WITH cities AS
(
    SELECT * FROM (VALUES
    ('Kuala Lumpur','Federal Territory','Malaysia'),
    ('Petaling Jaya','Selangor','Malaysia'),
    ('Shah Alam','Selangor','Malaysia'),
    ('Johor Bahru','Johor','Malaysia'),
    ('George Town','Penang','Malaysia'),
    ('Ipoh','Perak','Malaysia'),
    ('Kuching','Sarawak','Malaysia'),
    ('Kota Kinabalu','Sabah','Malaysia'),
    ('Melaka','Melaka','Malaysia'),
    ('Seremban','Negeri Sembilan','Malaysia'),
    ('Kuantan','Pahang','Malaysia'),
    ('Alor Setar','Kedah','Malaysia'),
    ('Miri','Sarawak','Malaysia'),
    ('Sandakan','Sabah','Malaysia'),
    ('Sibu','Sarawak','Malaysia')
    ) c(City,State,Country)
),
cities_n AS
(
    SELECT City, State, Country,
           ROW_NUMBER() OVER (ORDER BY City) AS rn,
           15 AS total
    FROM cities
)
/* ---------- Stores (even across cities; realistic chain + city) ---------- */
INSERT dbo.Stores(StoreName, City, State, Country, StoreType, OpenDate)
SELECT TOP (@Stores)
       CONCAT(sb.BrandName, ' - ', cn.City, ' ', ((t.n%3)+1)) AS StoreName,  -- e.g., "Lotus's - Johor Bahru 2"
       cn.City, cn.State, cn.Country,
       CHOOSE( (t.n%5)+1, 'Retail','Retail','Outlet','Express','Flagship') AS StoreType,
       DATEADD(DAY, - (t.n%3650), CAST(GETDATE() AS date)) AS OpenDate
FROM dbo.Numbers t
JOIN cities_n cn
  ON ((t.n - 1) % cn.total) + 1 = cn.rn
JOIN @StoreBrands sb
  ON (((t.n - 1) % @StoreBrandCount) + 1) = sb.BrandID
ORDER BY t.n;

/* --- Name pairs (aligned FirstName + LastName) --- */
DECLARE @NamePairs TABLE
(
    RowID    int identity(1,1) primary key,
    LastName nvarchar(50),
    FirstName nvarchar(50)
);
/* Chinese-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Lee','Wei'),('Lee','Jia'),('Lee','Mei'),('Lee','Yong'),('Lee','Hui'),
('Tan','Wei'),('Tan','Li'),('Tan','Jia'),('Tan','Mei'),('Tan','Hui'),
('Lim','Wei'),('Lim','Li'),('Lim','Jia'),('Lim','Mei'),('Lim','Yong'),
('Chen','Wei'),('Chen','Li'),('Chen','Hui'),('Chen','Jia'),('Chen','Mei'),
('Goh','Wei'),('Goh','Li'),('Goh','Jia'),('Goh','Mei'),('Goh','Hui');
/* Malay-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Rahman','Muhammad'),('Rahman','Ahmad'),('Rahman','Aisyah'),('Rahman','Nurul'),('Rahman','Siti'),
('Abdullah','Muhammad'),('Abdullah','Amin'),('Abdullah','Farah'),('Abdullah','Haziq'),('Abdullah','Aqil'),
('Hassan','Khairul'),('Hassan','Nadia'),('Ismail','Syafiq'),('Ismail','Nisa');
/* Indian-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Kumar','Arjun'),('Kumar','Priya'),('Kumar','Ravi'),('Kumar','Deepa'),
('Singh','Vijay'),('Singh','Neha'),('Nair','Rahul'),('Iyer','Anita');
/* Western-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Smith','James'),('Smith','Mary'),('Johnson','John'),('Johnson','Patricia'),
('Williams','Robert'),('Williams','Jennifer'),('Brown','Michael'),('Brown','Sarah'),
('Davis','William'),('Miller','Elizabeth'),('Wilson','David'),('Taylor','Emily');

DECLARE @NamePairCount int = (SELECT COUNT(*) FROM @NamePairs);

/* --- Real grocery product catalog (brand + item + pack) --- */
DECLARE @ProductCatalog TABLE
(
    CatalogID   int identity(1,1) primary key,
    Category    nvarchar(60)  not null,
    Subcategory nvarchar(60)  null,
    Brand       nvarchar(60)  not null,
    ProductName nvarchar(200) not null,
    Model       nvarchar(60)  null,
    BasePrice   decimal(10,2) not null
);

/* Produce & Vegetables */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Produce','Fruit','Imported','Bananas Cavendish (1kg)',NULL,6.90),
('Produce','Fruit','Imported','Apples Fuji (1kg)',NULL,10.90),
('Produce','Fruit','Imported','Oranges Navel (1kg)',NULL,9.90),
('Produce','Vegetable','Local Farm','Broccoli (per head)',NULL,5.90),
('Produce','Vegetable','Local Farm','Spinach (200g)',NULL,2.90),
('Produce','Vegetable','Local Farm','Cameron Lettuce (1 head)',NULL,3.90);

/* Dairy & Chilled */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Dairy','Milk','Dutch Lady','Full Cream Milk 1L',NULL,7.50),
('Dairy','Milk','Farm Fresh','Fresh Milk 1L',NULL,8.50),
('Dairy','Yogurt','Nestlé','LC1 Yogurt 135g',NULL,2.90),
('Dairy','Butter','Anchor','Salted Butter 227g',NULL,13.90),
('Dairy','Cheese','Kraft','Singles 200g',NULL,11.90);

/* Bakery & Breakfast */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Bakery','Bread','Gardenia','Original Classic 400g',NULL,4.40),
('Bakery','Bread','Massimo','Sandwich Loaf 400g',NULL,4.10),
('Breakfast','Cereal','Kellogg''s','Corn Flakes 500g',NULL,10.90),
('Breakfast','Malt','Nestlé','MILO 2kg Softpack',NULL,39.90),
('Breakfast','Coffee','Nescafé','Classic 200g',NULL,23.90);

/* Pantry (Canned / Cooking / Pasta) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Pantry','Canned Fish','Ayam Brand','Sardines in Tomato 425g',NULL,12.90),
('Pantry','Instant Noodles','Maggi','2-Minute Curry 5x79g',NULL,6.90),
('Pantry','Pasta','San Remo','Spaghetti 500g',NULL,6.50),
('Pantry','Pasta Sauce','Prego','Traditional 680g',NULL,13.90),
('Pantry','Soy Sauce','Lee Kum Kee','Premium Soy Sauce 500ml',NULL,9.90),
('Pantry','Cooking Paste','Brahim''s','Rendang Sauce 180g',NULL,6.90),
('Pantry','Spices','Baba''s','Meat Curry Powder 250g',NULL,7.90);

/* Snacks & Confectionery */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Snacks','Chips','Mister Potato','Original 160g',NULL,5.90),
('Snacks','Noodles Snack','Mamee','Monster Snack 8x25g',NULL,4.90),
('Snacks','Biscuits','Mondelez','Oreo Original 137g',NULL,3.90),
('Confectionery','Chocolate','Nestlé','KitKat 4-Finger 35g',NULL,2.50),
('Confectionery','Chocolate','Cadbury','Dairy Milk 165g',NULL,8.90);

/* Beverages */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Beverages','Soft Drink','Coca-Cola','Coca-Cola 1.5L',NULL,4.50),
('Beverages','Isotonic','F&N 100PLUS','100PLUS 1.5L',NULL,4.30),
('Beverages','Cordials','Sunquick','Orange Cordial 840ml',NULL,12.90),
('Beverages','Tea','BOH','Cameron Highlands Tea 50s',NULL,8.90),
('Beverages','Coffee','OldTown','White Coffee 3-in-1 15x38g',NULL,16.90);

/* Meat & Seafood / Frozen */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Meat','Poultry','Local Farm','Chicken Breast (1kg)',NULL,12.90),
('Meat','Beef','Local Farm','Minced Beef (500g)',NULL,16.90),
('Seafood','Fish','Local Fishery','Salmon Fillet (200g)',NULL,14.90),
('Frozen','Nuggets','CP Foods','Chicken Nuggets 1kg',NULL,19.90),
('Frozen','Fries','McCain','Straight Cut Fries 1kg',NULL,12.90);

/* Household & Personal Care */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Household','Laundry','Dynamo','Power Gel 2.7kg',NULL,31.90),
('Household','Laundry','Breeze','Liquid Detergent 3.6kg',NULL,29.90),
('Personal Care','Oral','Colgate','Total Toothpaste 150g',NULL,12.90),
('Personal Care','Shampoo','Sunsilk','Smooth & Manageable 650ml',NULL,18.90),
('Household','Tissue','Kleenex','Facial Tissue 3-ply 4x120s',NULL,12.90);

/* Baby & Kids */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Baby','Diapers','Drypers','Wee Wee Dry M60',NULL,33.90),
('Baby','Diapers','Huggies','Dry XL48',NULL,35.90),
('Baby','Formula','Nestlé','NAN Optipro 1 800g',NULL,99.90);

/* Water & Misc */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Beverages','Water','Spritzer','Mineral Water 1.5L',NULL,2.80),
('Bakery','Bun','Gardenia','Butterscotch 400g',NULL,5.50),
('Pantry','Cooking Oil','Knife','Blended Cooking Oil 2kg',NULL,16.90);

DECLARE @CatalogCount int = (SELECT COUNT(*) FROM @ProductCatalog);

/* --- City weights (skew orders by city) --- */
DECLARE @CityWeights TABLE(City nvarchar(60) primary key, Weight int not null);
INSERT @CityWeights(City,Weight) VALUES
('Kuala Lumpur',20),('Petaling Jaya',12),('Johor Bahru',10),('George Town',9),('Shah Alam',8),
('Kuching',7),('Kota Kinabalu',7),('Ipoh',6),('Melaka',5),('Seremban',4),
('Kuantan',4),('Alor Setar',3),('Miri',3),('Sandakan',1),('Sibu',1);

/* Expand stores by weight into a table variable for fast picking */
DECLARE @WeightedStores TABLE(rn int identity(1,1) primary key, StoreID int not null);
INSERT @WeightedStores(StoreID)
SELECT s.StoreID
FROM dbo.Stores s
JOIN @CityWeights w ON w.City = s.City
JOIN dbo.Numbers n ON n.n <= w.Weight;
DECLARE @WeightedStoreCount int = (SELECT COUNT(*) FROM @WeightedStores);

/* =========================================================
   Data population
   ========================================================= */

/* ---------- Products (repeat catalog to @Products; preserve NULLs) ---------- */
INSERT dbo.Products
(SKU, ProductName, Category, Subcategory, Brand, Model, LaunchDate, UnitPrice, CostPrice, WarrantyMonths, SupplierID)
SELECT TOP (@Products)
    CONCAT('GRC', RIGHT('000000' + CAST(t.n AS varchar(6)), 6)) AS SKU,
    pc.ProductName,
    pc.Category,
    pc.Subcategory,
    CASE WHEN t.n%20=0 THEN NULL ELSE pc.Brand END,        -- ~5% NULL Brand
    pc.Model,
    DATEADD(DAY, -(t.n%1800), CAST(GETDATE() AS date)) AS LaunchDate,
    /* ~1% NULL price; else BasePrice ± ~10% */
    CASE WHEN t.n%100=0 THEN NULL ELSE
         CAST(ROUND(pc.BasePrice * (0.95 + ((t.n%11)/100.0)), 2) AS decimal(10,2)) END AS UnitPrice,
    /* cost proxy: 60–85% of base */
    CAST(ROUND((0.60 + ((t.n%26)/100.0)) * pc.BasePrice, 2) AS decimal(10,2)) AS CostPrice,
    (3 + (t.n%10)) AS WarrantyMonths,                       -- placeholder 3–12
    ((t.n%@Suppliers)+1) AS SupplierID
FROM dbo.Numbers t
JOIN @ProductCatalog pc
  ON (((t.n - 1) % @CatalogCount) + 1) = pc.CatalogID
ORDER BY t.n;

/* ---------- Customers (aligned first+last names; varied cities) ---------- */
INSERT dbo.Customers
(FirstName, LastName, Email, Phone, Gender, BirthDate, City, State, Country, SignupDate)
SELECT TOP (@Customers)
    np.FirstName,
    np.LastName,
    CASE WHEN t.n%20=0 THEN NULL ELSE CONCAT('cust', t.n, '@mail.com') END AS Email,
    CASE WHEN t.n%10=0 THEN NULL ELSE CONCAT('01', RIGHT('000000000' + CAST(t.n AS varchar(9)), 9)) END AS Phone,
    CASE WHEN t.n%2=0 THEN 'Male' ELSE 'Female' END AS Gender,
    CASE WHEN t.n%33=0 THEN NULL ELSE DATEADD(DAY, - (18*365 + (t.n%(42*365))), CAST(GETDATE() AS date)) END AS BirthDate,
    CHOOSE((t.n%12)+1,'Kuala Lumpur','Petaling Jaya','Shah Alam','Johor Bahru','George Town','Ipoh','Kuching','Kota Kinabalu','Melaka','Seremban','Kuantan','Alor Setar') AS City,
    CHOOSE((t.n%12)+1,'Federal Territory','Selangor','Selangor','Johor','Penang','Perak','Sarawak','Sabah','Melaka','Negeri Sembilan','Pahang','Kedah') AS State,
    'Malaysia' AS Country,
    DATEADD(DAY, -(t.n%2500), CAST(GETDATE() AS date)) AS SignupDate
FROM dbo.Numbers t
JOIN @NamePairs np
  ON (((t.n - 1) % @NamePairCount) + 1) = np.RowID
ORDER BY t.n;

/* ---------- Duplicate some customers ---------- */
INSERT dbo.Customers (FirstName, LastName, Email, Phone, Gender, BirthDate, City, State, Country, SignupDate)
SELECT TOP (@DuplicateCustomers)
       c.FirstName, c.LastName, c.Email, c.Phone, c.Gender, c.BirthDate, c.City, c.State, c.Country, c.SignupDate
FROM dbo.Customers c
JOIN dbo.Numbers nn ON c.CustomerID = nn.n
WHERE c.CustomerID % 17 = 0;

/* ---------- Sales (weighted Store pick; preserve NULLs & totals inline) ---------- */
DECLARE @CustCount  int = (SELECT COUNT(*) FROM dbo.Customers);
DECLARE @ProdCount  int = (SELECT COUNT(*) FROM dbo.Products);
DECLARE @StoreCount int = (SELECT COUNT(*) FROM dbo.Stores);

INSERT dbo.Sales
(OrderDate, ShipDate, CustomerID, StoreID, ProductID, Quantity, UnitPrice, Discount, TotalAmount,
 PaymentMethod, Channel, OrderStatus)
SELECT TOP (@Sales)
    DATEADD(DAY, (x.n%1370), CONVERT(date,'2022-01-01')) AS OrderDate,
    CASE WHEN x.n%9=0 THEN NULL ELSE DATEADD(DAY, (x.n%7),
         DATEADD(DAY, (x.n%1370), CONVERT(date,'2022-01-01'))) END AS ShipDate,
    /* ~0.5% NULL customer inline */
    CASE WHEN x.n%200=0 THEN NULL ELSE ((x.n%@CustCount)+1) END AS CustomerID,
    /* ~1% NULL store inline, else weighted store pick */
    CASE WHEN x.n%100=0 THEN NULL ELSE ws.StoreID END AS StoreID,
    ((x.n%@ProdCount)+1) AS ProductID,
    /* grocery baskets: often >1 */
    CASE WHEN x.n%5 IN (0,1,2) THEN 1 WHEN x.n%5=3 THEN 2 ELSE 3 + (x.n%2) END AS Quantity,
    /* ~0.7% NULL price; else product price ± ~10% */
    CASE WHEN x.n%150=0 THEN NULL ELSE
      CAST(ROUND(
        (SELECT UnitPrice FROM dbo.Products WHERE ProductID = ((x.n%@ProdCount)+1)) *
        (0.95 + ((x.n%11)/100.0)), 2) AS decimal(10,2)) END AS UnitPrice,
    CAST(CASE WHEN x.n%3=0 THEN 0 ELSE ROUND(((x.n%31)/100.0),2) END AS decimal(5,2)) AS Discount,
    CAST(ROUND(
        (CASE WHEN x.n%150=0 THEN 0 ELSE
          (CASE WHEN x.n%5 IN (0,1,2) THEN 1 WHEN x.n%5=3 THEN 2 ELSE 3 + (x.n%2) END) *
          (SELECT COALESCE(UnitPrice,0) FROM dbo.Products WHERE ProductID=((x.n%@ProdCount)+1)) *
          (1 - (CASE WHEN x.n%3=0 THEN 0 ELSE ((x.n%31)/100.0) END))
        END), 2) AS decimal(12,2)) AS TotalAmount,
    CASE WHEN x.n%100=0 THEN NULL ELSE CHOOSE((x.n%5)+1,'Credit Card','Debit Card','E-Wallet','Bank Transfer','Cash') END AS PaymentMethod,
    CHOOSE((x.n%3)+1,'Online','In-Store','Marketplace') AS Channel,
    CHOOSE((x.n%10)+1,'Cancelled','Returned','Pending','Completed','Completed','Completed','Completed','Completed','Completed','Completed') AS OrderStatus
FROM dbo.Numbers x
CROSS APPLY
(
    SELECT StoreID
    FROM @WeightedStores
    WHERE rn = ((x.n % @WeightedStoreCount) + 1)
) AS ws
ORDER BY x.n;

/* ---------- Duplicate some Sales ---------- */
INSERT dbo.Sales
(OrderDate, ShipDate, CustomerID, StoreID, ProductID, Quantity, UnitPrice, Discount, TotalAmount, PaymentMethod, Channel, OrderStatus)
SELECT TOP (@DuplicateSales)
       s.OrderDate, s.ShipDate, s.CustomerID, s.StoreID, s.ProductID, s.Quantity,
       s.UnitPrice, s.Discount, s.TotalAmount, s.PaymentMethod, s.Channel, s.OrderStatus
FROM dbo.Sales s
JOIN dbo.Numbers nn ON s.SalesID = nn.n
WHERE s.SalesID % 23 = 0;

/* ---------- Row counts ---------- */
SELECT 'Customers' AS TableName, COUNT(*) AS Rows FROM dbo.Customers
UNION ALL SELECT 'Suppliers', COUNT(*) FROM dbo.Suppliers
UNION ALL SELECT 'Stores', COUNT(*)  FROM dbo.Stores
UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Sales', COUNT(*) FROM dbo.Sales;
