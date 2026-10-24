
CREATE DATABASE Amazon_BI;
GO

USE Amazon_BI;
GO


-- 1. TABLE DE STAGING (donnees brutes, non nettoyees)

CREATE TABLE Staging_Amazon (
    product_id          VARCHAR(50),
    product_name        NVARCHAR(MAX),
    category            NVARCHAR(MAX),
    discounted_price    VARCHAR(50),
    actual_price         VARCHAR(50),
    discount_percentage VARCHAR(20),
    rating              VARCHAR(20),
    rating_count        VARCHAR(20),
    about_product       NVARCHAR(MAX),
    user_id             NVARCHAR(MAX),
    user_name           NVARCHAR(MAX),
    review_id           NVARCHAR(MAX),
    review_title        NVARCHAR(MAX),
    review_content      NVARCHAR(MAX),
    img_link            NVARCHAR(500),
    product_link        NVARCHAR(500),
    order_date          VARCHAR(50)
);
GO

-- 2. DIMENSIONS

-- Dim_Categorie : 3 niveaux
CREATE TABLE Dim_Categorie (
    id_categorie      INT IDENTITY(1,1) PRIMARY KEY,
    categorie_niveau1 NVARCHAR(200),
    categorie_niveau2 NVARCHAR(200),
    categorie_niveau3 NVARCHAR(200)
);
GO

-- Dim_Produit
CREATE TABLE Dim_Produit (
    product_id     VARCHAR(50) PRIMARY KEY,
    product_name   NVARCHAR(MAX),
    about_product  NVARCHAR(MAX),
    img_link       NVARCHAR(500),
    product_link   NVARCHAR(500),
    id_categorie   INT FOREIGN KEY REFERENCES Dim_Categorie(id_categorie)
);
GO

-- Dim_Client
CREATE TABLE Dim_Client (
    user_id    VARCHAR(100) PRIMARY KEY,
    user_name  NVARCHAR(200)
);
GO

-- Dim_Date
CREATE TABLE Dim_Date (
    id_date        INT IDENTITY(1,1) PRIMARY KEY,
    date_complete  DATE NOT NULL UNIQUE,
    jour           INT,
    mois           INT,
    nom_mois       VARCHAR(20),
    trimestre      INT,
    annee          INT
);
GO

-- 3. TABLE DE FAITS

CREATE TABLE Fait_Ventes (
    id_vente             INT IDENTITY(1,1) PRIMARY KEY,
    product_id           VARCHAR(50) FOREIGN KEY REFERENCES Dim_Produit(product_id),
    user_id              VARCHAR(100) FOREIGN KEY REFERENCES Dim_Client(user_id),
    id_categorie         INT FOREIGN KEY REFERENCES Dim_Categorie(id_categorie),
    id_date              INT FOREIGN KEY REFERENCES Dim_Date(id_date),
    rating               DECIMAL(3,2),
    rating_count         INT,
    discounted_price     DECIMAL(10,2),
    actual_price         DECIMAL(10,2),
    discount_percentage  DECIMAL(5,2),
    montant_economise    DECIMAL(10,2)
);
GO


-- CORRECTIONS APPLIQUEES (apres tests SSIS)

ALTER TABLE Staging_Amazon ALTER COLUMN product_name VARCHAR(500);
ALTER TABLE Staging_Amazon ALTER COLUMN category VARCHAR(500);
ALTER TABLE Staging_Amazon ALTER COLUMN about_product VARCHAR(8000);
ALTER TABLE Staging_Amazon ALTER COLUMN user_id VARCHAR(4000);
ALTER TABLE Staging_Amazon ALTER COLUMN user_name VARCHAR(4000);
ALTER TABLE Staging_Amazon ALTER COLUMN review_id VARCHAR(4000);
ALTER TABLE Staging_Amazon ALTER COLUMN review_title VARCHAR(4000);
ALTER TABLE Staging_Amazon ALTER COLUMN review_content VARCHAR(8000);
ALTER TABLE Staging_Amazon ALTER COLUMN img_link VARCHAR(500);
ALTER TABLE Staging_Amazon ALTER COLUMN product_link VARCHAR(500);
ALTER TABLE Staging_Amazon ALTER COLUMN discount_percentage VARCHAR(50);
ALTER TABLE Staging_Amazon ALTER COLUMN rating VARCHAR(50);
ALTER TABLE Staging_Amazon ALTER COLUMN rating_count VARCHAR(50);
GO


-- CHARGEMENT DES DONNEES (via pipeline SSIS)
-- 1465 lignes chargees dans Staging_Amazon depuis amazon.csv
-- TRANSFORMATION : REMPLISSAGE DE Dim_Categorie

;WITH CategoriesSplit AS (
    SELECT DISTINCT
        category,
        value AS niveau,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY (SELECT NULL)) AS position
    FROM Staging_Amazon
    CROSS APPLY STRING_SPLIT(category, '|')
)
INSERT INTO Dim_Categorie (categorie_niveau1, categorie_niveau2, categorie_niveau3)
SELECT DISTINCT
    MAX(CASE WHEN position = 1 THEN niveau END) AS categorie_niveau1,
    MAX(CASE WHEN position = 2 THEN niveau END) AS categorie_niveau2,
    MAX(CASE WHEN position = 3 THEN niveau END) AS categorie_niveau3
FROM CategoriesSplit
GROUP BY category;
GO



-- TRANSFORMATION : REMPLISSAGE DE Dim_Produit (avec deduplication)

;WITH ProduitsUniques AS (
    SELECT 
        s.product_id,
        s.product_name,
        s.about_product,
        s.img_link,
        s.product_link,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Dim_Produit (product_id, product_name, about_product, img_link, product_link, id_categorie)
SELECT 
    p.product_id,
    p.product_name,
    p.about_product,
    p.img_link,
    p.product_link,
    dc.id_categorie
FROM ProduitsUniques p
INNER JOIN Dim_Categorie dc 
    ON dc.categorie_niveau1 = (
        SELECT MAX(CASE WHEN position = 1 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    )
    AND ISNULL(dc.categorie_niveau2, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 2 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
    AND ISNULL(dc.categorie_niveau3, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 3 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
WHERE p.rn = 1
  AND p.product_id NOT IN (SELECT product_id FROM Dim_Produit);
GO

-- Verification
SELECT COUNT(*) AS nombre_produits FROM Dim_Produit;
SELECT TOP 10 * FROM Dim_Produit;
GO

SELECT COUNT(*) AS nombre_categories FROM Dim_Categorie;
SELECT TOP 10 * FROM Dim_Categorie;


-- TRANSFORMATION : REMPLISSAGE DE Dim_Client


WITH UsersSplit AS (
    SELECT DISTINCT
        TRIM(value) AS user_id_clean
    FROM Staging_Amazon
    CROSS APPLY STRING_SPLIT(user_id, ',')
    WHERE value IS NOT NULL AND TRIM(value) <> ''
)
INSERT INTO Dim_Client (user_id, user_name)
SELECT 
    us.user_id_clean,
    NULL AS user_name
FROM UsersSplit us
WHERE us.user_id_clean NOT IN (SELECT user_id FROM Dim_Client);
GO

-- Verification
SELECT COUNT(*) AS nombre_clients FROM Dim_Client;
SELECT TOP 10 * FROM Dim_Client;
GO


-- TRANSFORMATION : REMPLISSAGE DE Dim_Date

DECLARE @date DATE = '2024-01-01';
WHILE @date <= '2024-12-31'
BEGIN
    INSERT INTO Dim_Date (date_complete, jour, mois, nom_mois, trimestre, annee)
    VALUES (
        @date,
        DAY(@date),
        MONTH(@date),
        DATENAME(MONTH, @date),
        DATEPART(QUARTER, @date),
        YEAR(@date)
    );
    SET @date = DATEADD(DAY, 1, @date);
END
GO

-- Verification
SELECT COUNT(*) AS nombre_dates FROM Dim_Date;
SELECT TOP 10 * FROM Dim_Date;
GO

-- TRANSFORMATION : REMPLISSAGE DE Fait_Ventes 


;WITH DonneesNettoyees AS (
    SELECT 
        s.product_id,
        TRIM(LEFT(s.user_id, CHARINDEX(',', s.user_id + ',') - 1)) AS user_id_clean,
        TRY_CAST(REPLACE(REPLACE(REPLACE(s.discounted_price, '₹', ''), ',', ''), 'â‚¹', '') AS DECIMAL(10,2)) AS discounted_price_clean,
        TRY_CAST(REPLACE(REPLACE(REPLACE(s.actual_price, '₹', ''), ',', ''), 'â‚¹', '') AS DECIMAL(10,2)) AS actual_price_clean,
        TRY_CAST(REPLACE(s.discount_percentage, '%', '') AS DECIMAL(5,2)) AS discount_percentage_clean,
        TRY_CAST(s.rating AS DECIMAL(3,2)) AS rating_clean,
        TRY_CAST(REPLACE(s.rating_count, ',', '') AS INT) AS rating_count_clean,
        s.category
    FROM Staging_Amazon s
)
INSERT INTO Fait_Ventes (
    product_id, user_id, id_categorie, id_date, 
    rating, rating_count, discounted_price, actual_price, 
    discount_percentage, montant_economise
)
SELECT 
    dn.product_id,
    CASE WHEN c.user_id IS NOT NULL THEN dn.user_id_clean ELSE NULL END,
    dp.id_categorie,  -- on reprend directement la categorie deja assignee au produit dans Dim_Produit
    (SELECT TOP 1 id_date FROM Dim_Date ORDER BY NEWID()) AS id_date,
    dn.rating_clean,
    dn.rating_count_clean,
    dn.discounted_price_clean,
    dn.actual_price_clean,
    dn.discount_percentage_clean,
    (dn.actual_price_clean - dn.discounted_price_clean) AS montant_economise
FROM DonneesNettoyees dn
LEFT JOIN Dim_Client c ON c.user_id = dn.user_id_clean
INNER JOIN Dim_Produit dp ON dp.product_id = dn.product_id;
GO

-- Verification
SELECT COUNT(*) AS nombre_ventes FROM Fait_Ventes;
SELECT TOP 10 * FROM Fait_Ventes;
GO

-- NETTOYAGE : vider Fait_Ventes avant de refaire

DELETE FROM Fait_Ventes;
GO

-- TRANSFORMATION : REMPLISSAGE DE Fait_Ventes (version finale, dedupliquee)


;WITH DonneesNettoyees AS (
    SELECT 
        s.product_id,
        TRIM(LEFT(s.user_id, CHARINDEX(',', s.user_id + ',') - 1)) AS user_id_clean,
        TRY_CAST(REPLACE(REPLACE(REPLACE(s.discounted_price, '₹', ''), ',', ''), 'â‚¹', '') AS DECIMAL(10,2)) AS discounted_price_clean,
        TRY_CAST(REPLACE(REPLACE(REPLACE(s.actual_price, '₹', ''), ',', ''), 'â‚¹', '') AS DECIMAL(10,2)) AS actual_price_clean,
        TRY_CAST(REPLACE(s.discount_percentage, '%', '') AS DECIMAL(5,2)) AS discount_percentage_clean,
        TRY_CAST(s.rating AS DECIMAL(3,2)) AS rating_clean,
        TRY_CAST(REPLACE(s.rating_count, ',', '') AS INT) AS rating_count_clean,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Fait_Ventes (
    product_id, user_id, id_categorie, id_date, 
    rating, rating_count, discounted_price, actual_price, 
    discount_percentage, montant_economise
)
SELECT 
    dn.product_id,
    CASE WHEN c.user_id IS NOT NULL THEN dn.user_id_clean ELSE NULL END,
    dp.id_categorie,
    (SELECT TOP 1 id_date FROM Dim_Date ORDER BY NEWID()) AS id_date,
    dn.rating_clean,
    dn.rating_count_clean,
    dn.discounted_price_clean,
    dn.actual_price_clean,
    dn.discount_percentage_clean,
    (dn.actual_price_clean - dn.discounted_price_clean) AS montant_economise
FROM DonneesNettoyees dn
LEFT JOIN Dim_Client c ON c.user_id = dn.user_id_clean
INNER JOIN Dim_Produit dp ON dp.product_id = dn.product_id
WHERE dn.rn = 1;
GO

-- Verification
SELECT COUNT(*) AS nombre_ventes FROM Fait_Ventes;
SELECT TOP 10 * FROM Fait_Ventes;
GO

SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;

UPDATE fv
SET fv.id_date = d.id_date
FROM Fait_Ventes fv
CROSS APPLY (SELECT TOP 1 id_date FROM Dim_Date ORDER BY NEWID()) d;
GO

-- Verification
SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;

UPDATE Fait_Ventes
SET id_date = 1 + ABS(CHECKSUM(NEWID())) % 366;
GO

-- Verification
SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;
GO


USE Amazon_BI;
GO
TRUNCATE TABLE Staging_Amazon;
GO



USE Amazon_BI;
GO

TRUNCATE TABLE Staging_Amazon;
GO


SELECT COUNT(*) FROM Staging_Amazon;

SELECT TOP 10 product_id, discounted_price, actual_price, discount_percentage, rating, rating_count 
FROM Staging_Amazon;




TRUNCATE TABLE Staging_Amazon;
GO

SELECT COUNT(*) FROM Staging_Amazon;

SELECT COUNT(*) FROM Staging_Amazon;


DELETE FROM Fait_Ventes;
DELETE FROM Dim_Produit;
DELETE FROM Dim_Client;
DELETE FROM Dim_Categorie;
DELETE FROM Dim_Date;
GO


;WITH CategoriesSplit AS (
    SELECT DISTINCT
        category,
        value AS niveau,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY (SELECT NULL)) AS position
    FROM Staging_Amazon
    CROSS APPLY STRING_SPLIT(category, '|')
)
INSERT INTO Dim_Categorie (categorie_niveau1, categorie_niveau2, categorie_niveau3)
SELECT DISTINCT
    MAX(CASE WHEN position = 1 THEN niveau END) AS categorie_niveau1,
    MAX(CASE WHEN position = 2 THEN niveau END) AS categorie_niveau2,
    MAX(CASE WHEN position = 3 THEN niveau END) AS categorie_niveau3
FROM CategoriesSplit
GROUP BY category;
GO

SELECT COUNT(*) AS nombre_categories FROM Dim_Categorie;


;WITH ProduitsUniques AS (
    SELECT 
        s.product_id,
        s.product_name,
        s.about_product,
        s.img_link,
        s.product_link,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Dim_Produit (product_id, product_name, about_product, img_link, product_link, id_categorie)
SELECT 
    p.product_id,
    p.product_name,
    p.about_product,
    p.img_link,
    p.product_link,
    dc.id_categorie
FROM ProduitsUniques p
INNER JOIN Dim_Categorie dc 
    ON dc.categorie_niveau1 = (
        SELECT MAX(CASE WHEN position = 1 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    )
    AND ISNULL(dc.categorie_niveau2, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 2 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
    AND ISNULL(dc.categorie_niveau3, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 3 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
WHERE p.rn = 1
  AND p.product_id NOT IN (SELECT product_id FROM Dim_Produit);
GO

SELECT COUNT(*) AS nombre_produits FROM Dim_Produit;

 DELETE FROM Dim_Categorie;
GO
SELECT COUNT(*) FROM Dim_Categorie;

DELETE FROM Dim_Categorie;
GO

DELETE FROM Fait_Ventes;
GO

DELETE FROM Dim_Produit;
GO

DELETE FROM Dim_Categorie;
GO

SELECT COUNT(*) FROM Dim_Categorie;
SELECT COUNT(*) FROM Dim_Produit;
SELECT COUNT(*) FROM Fait_Ventes;

DELETE FROM Dim_Client;
GO

DELETE FROM Dim_Date;
GO

SELECT COUNT(*) FROM Dim_Categorie;
SELECT COUNT(*) FROM Dim_Produit;
SELECT COUNT(*) FROM Dim_Client;
SELECT COUNT(*) FROM Dim_Date;
SELECT COUNT(*) FROM Fait_Ventes;

;WITH CategoriesSplit AS (
    SELECT DISTINCT
        category,
        value AS niveau,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY (SELECT NULL)) AS position
    FROM Staging_Amazon
    CROSS APPLY STRING_SPLIT(category, '|')
)
INSERT INTO Dim_Categorie (categorie_niveau1, categorie_niveau2, categorie_niveau3)
SELECT DISTINCT
    MAX(CASE WHEN position = 1 THEN niveau END) AS categorie_niveau1,
    MAX(CASE WHEN position = 2 THEN niveau END) AS categorie_niveau2,
    MAX(CASE WHEN position = 3 THEN niveau END) AS categorie_niveau3
FROM CategoriesSplit
GROUP BY category;
GO

SELECT COUNT(*) AS nombre_categories FROM Dim_Categorie;

;WITH ProduitsUniques AS (
    SELECT 
        s.product_id,
        s.product_name,
        s.about_product,
        s.img_link,
        s.product_link,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Dim_Produit (product_id, product_name, about_product, img_link, product_link, id_categorie)
SELECT 
    p.product_id,
    p.product_name,
    p.about_product,
    p.img_link,
    p.product_link,
    dc.id_categorie
FROM ProduitsUniques p
INNER JOIN Dim_Categorie dc 
    ON dc.categorie_niveau1 = (
        SELECT MAX(CASE WHEN position = 1 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    )
    AND ISNULL(dc.categorie_niveau2, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 2 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
    AND ISNULL(dc.categorie_niveau3, '') = ISNULL((
        SELECT MAX(CASE WHEN position = 3 THEN niveau END)
        FROM (
            SELECT value AS niveau, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS position
            FROM STRING_SPLIT(p.category, '|')
        ) t
    ), '')
WHERE p.rn = 1
  AND p.product_id NOT IN (SELECT product_id FROM Dim_Produit);
GO

SELECT COUNT(*) AS nombre_produits FROM Dim_Produit;

SELECT product_id, COUNT(*) AS nb
FROM Dim_Produit
GROUP BY product_id
HAVING COUNT(*) > 1;

WITH UsersSplit AS (
    SELECT DISTINCT
        TRIM(value) AS user_id_clean
    FROM Staging_Amazon
    CROSS APPLY STRING_SPLIT(user_id, ',')
    WHERE value IS NOT NULL AND TRIM(value) <> ''
)
INSERT INTO Dim_Client (user_id, user_name)
SELECT 
    us.user_id_clean,
    NULL AS user_name
FROM UsersSplit us
WHERE us.user_id_clean NOT IN (SELECT user_id FROM Dim_Client);
GO

SELECT COUNT(*) AS nombre_clients FROM Dim_Client;

DECLARE @date DATE = '2024-01-01';
WHILE @date <= '2024-12-31'
BEGIN
    INSERT INTO Dim_Date (date_complete, jour, mois, nom_mois, trimestre, annee)
    VALUES (
        @date,
        DAY(@date),
        MONTH(@date),
        DATENAME(MONTH, @date),
        DATEPART(QUARTER, @date),
        YEAR(@date)
    );
    SET @date = DATEADD(DAY, 1, @date);
END
GO

SELECT COUNT(*) AS nombre_dates FROM Dim_Date;

;WITH DonneesNettoyees AS (
    SELECT 
        s.product_id,
        TRIM(LEFT(s.user_id, CHARINDEX(',', s.user_id + ',') - 1)) AS user_id_clean,
        TRY_CAST(s.discounted_price AS DECIMAL(10,2)) AS discounted_price_clean,
        TRY_CAST(s.actual_price AS DECIMAL(10,2)) AS actual_price_clean,
        TRY_CAST(s.discount_percentage AS DECIMAL(5,2)) AS discount_percentage_clean,
        TRY_CAST(s.rating AS DECIMAL(3,2)) AS rating_clean,
        TRY_CAST(s.rating_count AS INT) AS rating_count_clean,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Fait_Ventes (
    product_id, user_id, id_categorie, id_date, 
    rating, rating_count, discounted_price, actual_price, 
    discount_percentage, montant_economise
)
SELECT 
    dn.product_id,
    CASE WHEN c.user_id IS NOT NULL THEN dn.user_id_clean ELSE NULL END,
    dp.id_categorie,
    (1 + ABS(CHECKSUM(NEWID())) % 366) AS id_date,
    dn.rating_clean,
    dn.rating_count_clean,
    dn.discounted_price_clean,
    dn.actual_price_clean,
    dn.discount_percentage_clean,
    (dn.actual_price_clean - dn.discounted_price_clean) AS montant_economise
FROM DonneesNettoyees dn
LEFT JOIN Dim_Client c ON c.user_id = dn.user_id_clean
INNER JOIN Dim_Produit dp ON dp.product_id = dn.product_id
WHERE dn.rn = 1;
GO

SELECT COUNT(*) AS nombre_ventes FROM Fait_Ventes;
SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;

DELETE FROM Dim_Date;
GO

DBCC CHECKIDENT ('Dim_Date', RESEED, 0);
GO

DECLARE @date DATE = '2024-01-01';
WHILE @date <= '2024-12-31'
BEGIN
    INSERT INTO Dim_Date (date_complete, jour, mois, nom_mois, trimestre, annee)
    VALUES (
        @date,
        DAY(@date),
        MONTH(@date),
        DATENAME(MONTH, @date),
        DATEPART(QUARTER, @date),
        YEAR(@date)
    );
    SET @date = DATEADD(DAY, 1, @date);
END
GO

SELECT MIN(id_date) AS min_id, MAX(id_date) AS max_id, COUNT(*) AS total FROM Dim_Date;

;WITH DonneesNettoyees AS (
    SELECT 
        s.product_id,
        TRIM(LEFT(s.user_id, CHARINDEX(',', s.user_id + ',') - 1)) AS user_id_clean,
        TRY_CAST(s.discounted_price AS DECIMAL(10,2)) AS discounted_price_clean,
        TRY_CAST(s.actual_price AS DECIMAL(10,2)) AS actual_price_clean,
        TRY_CAST(s.discount_percentage AS DECIMAL(5,2)) AS discount_percentage_clean,
        TRY_CAST(s.rating AS DECIMAL(3,2)) AS rating_clean,
        TRY_CAST(s.rating_count AS INT) AS rating_count_clean,
        s.category,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY (SELECT NULL)) AS rn
    FROM Staging_Amazon s
)
INSERT INTO Fait_Ventes (
    product_id, user_id, id_categorie, id_date, 
    rating, rating_count, discounted_price, actual_price, 
    discount_percentage, montant_economise
)
SELECT 
    dn.product_id,
    CASE WHEN c.user_id IS NOT NULL THEN dn.user_id_clean ELSE NULL END,
    dp.id_categorie,
    (1 + ABS(CHECKSUM(NEWID())) % 366) AS id_date,
    dn.rating_clean,
    dn.rating_count_clean,
    dn.discounted_price_clean,
    dn.actual_price_clean,
    dn.discount_percentage_clean,
    (dn.actual_price_clean - dn.discounted_price_clean) AS montant_economise
FROM DonneesNettoyees dn
LEFT JOIN Dim_Client c ON c.user_id = dn.user_id_clean
INNER JOIN Dim_Produit dp ON dp.product_id = dn.product_id
WHERE dn.rn = 1;
GO

SELECT COUNT(*) AS nombre_ventes FROM Fait_Ventes;
SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;




USE Amazon_BI;
GO

SELECT COUNT(DISTINCT id_date) AS nombre_dates_differentes FROM Fait_Ventes;