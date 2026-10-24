# Analyse des ventes Amazon : ETL et tableaux de bord décisionnels

> De la donnée brute au tableau de bord décisionnel : pipeline ETL (SSIS), entrepôt de données en schéma en étoile (SQL Server), tableaux de bord interactifs (Power BI) et reporting (SSRS).

Projet académique réalisé dans le cadre du module **Outils d'analyse des données**, Master Intelligence Artificielle pour l'Économie Numérique et la Gestion (Faculté des Sciences Juridiques, Économiques et Sociales de Tanger, Université Abdelmalek Essaâdi, 2025-2026).

**Réalisé par :** Fatima Rafiai et Fatima Zohra El Ouahabi
**Encadré par :** Pr. Anas Bennani

## Objectif

Construire une chaîne décisionnelle complète à partir d'une source brute et imparfaite, afin de répondre à des questions métier :

- Quelles catégories de produits génèrent le plus de chiffre d'affaires ?
- Comment évoluent les ventes dans le temps ?
- Quel est le niveau de satisfaction client par catégorie ?
- Quelle est la politique de remise et quelles économies les clients réalisent-ils ?

## Outils utilisés

| Étape | Outil |
|---|---|
| Extraction et transformation (ETL) | SQL Server Integration Services (SSIS) |
| Stockage et modélisation | SQL Server / SSMS (T-SQL) |
| Tableaux de bord | Power BI Desktop, DAX |
| Reporting (rapports paginés) | SQL Server Reporting Services (SSRS) |

## Données

Dataset **Amazon Sales** (Kaggle) : 1 465 lignes, 16 colonnes (produits vendus sur Amazon Inde et avis clients).

Problèmes de qualité traités : prix en texte (symbole ₹, séparateurs de milliers), catégories empilées dans une seule colonne (séparées par `|`), identifiants clients concaténés, doublons de `product_id`, problèmes d'encodage, absence de dimension temporelle.

## Architecture

```
amazon.csv ──► SSIS (Flat File Source → Derived Column → OLE DB Destination)
                          │
                          ▼
                  Staging_Amazon (1 465 lignes)
                          │  T-SQL (STRING_SPLIT, ROW_NUMBER)
                          ▼
   Dim_Categorie · Dim_Produit · Dim_Client · Dim_Date ──► Fait_Ventes
                          │
                          ├──► Power BI (3 pages de tableaux de bord)
                          └──► SSRS (rapports paginés) : en cours
```

### Modèle en étoile

- **Table de faits :** `Fait_Ventes` (1 345 lignes)
- **Dimensions :** `Dim_Produit` (1 345 produits uniques), `Dim_Categorie` (78 catégories), `Dim_Client` (9 050 clients), `Dim_Date` (année 2024)

## Pipeline ETL (SSIS)

Un Data Flow Task avec trois composants en série :

1. **Flat File Source** : lecture de `amazon.csv` (Code Page 65001, UTF-8).
2. **Derived Column** : nettoyage des prix (suppression de ₹ et des séparateurs), du pourcentage de remise (suppression de %), de la note et du nombre d'avis.
3. **OLE DB Destination** : chargement dans `Staging_Amazon`.

Résultat : 1 465 lignes en entrée, 1 465 lignes chargées.

## Transformation SQL

- `Dim_Categorie` : extraction des niveaux hiérarchiques avec `STRING_SPLIT`.
- `Dim_Produit` : déduplication avec `ROW_NUMBER()`.
- `Dim_Client` : séparation des identifiants concaténés avec `STRING_SPLIT`.
- `Dim_Date` : dimension temporelle générée pour 2024 ; une date est attribuée à chaque vente avec `CHECKSUM(NEWID())` pour garantir une évaluation ligne par ligne.

## Tableaux de bord Power BI

### Mesures DAX

```dax
CA_Total        = SUM(Fait_Ventes[discounted_price])
Note_Moyenne    = AVERAGE(Fait_Ventes[rating])
Remise_Moyenne  = AVERAGE(Fait_Ventes[discount_percentage])
Nombre_Ventes   = COUNTROWS(Fait_Ventes)
Economie_Totale = SUM(Fait_Ventes[montant_economise])
Prix_Moyen      = AVERAGE(Fait_Ventes[discounted_price])
```

### Pages des tableaux de bord

1. **Vue d'ensemble des ventes** : 4 cartes KPI, CA par catégorie, évolution mensuelle du CA, satisfaction par catégorie. La catégorie *Electronics* domine nettement le chiffre d'affaires.
2. **Analyse produits et clients** : slicers par catégorie et par mois, ventes par produit, tableaux Top N des produits et des clients.
3. **Analyse des remises** : remise moyenne par catégorie, évolution mensuelle des économies, distribution des ventes par pourcentage de remise.

Le cross-filtering est actif : sélectionner une catégorie met à jour tous les visuels de la page.

### Aperçu

![Page 1 : Vue d'ensemble des ventes](Screenshot%202026-10-24%20213216.png)
![Page 2 : Analyse produits et clients](Screenshot%202026-10-24%20213241.png)
![Page 3 : Analyse des remises](Screenshot%202026-10-24%20213259.png)

## Reporting SSRS

> 🚧 **En cours de réalisation.** Cette section sera complétée une fois les rapports terminés.

Rapports paginés conçus avec SQL Server Reporting Services à partir de la base `Amazon_BI`.

<!-- À compléter :
- Liste des rapports (nom + objectif de chaque rapport)
- Datasets / requêtes utilisés
- Paramètres (filtres) et exports (PDF, Excel)
- Captures d'écran des rapports
-->

## Difficultés rencontrées et solutions

| Problème | Solution |
|---|---|
| Encodage du symbole ₹ (affiché « â‚¹ ») | Code Page 65001 dans le Flat File Connection Manager |
| Conflit Unicode / non-Unicode | Colonnes de `Staging_Amazon` alignées sur `VARCHAR` |
| Troncature des avis (jusqu'à 18 547 caractères) | Gestion d'erreur du composant source réglée sur « Ignore failure » |
| Doublons de `product_id` | Déduplication avec `ROW_NUMBER()` |
| Même date pour toutes les lignes | `CHECKSUM(NEWID())` dans la clause `SET` |
| Chemins ambigus dans le modèle Power BI | Relation directe `Dim_Produit` / `Dim_Categorie` désactivée |

## Limites et pistes d'amélioration

- `Dim_Date` est **simulée** : le dataset source ne contient aucune date, les évolutions temporelles sont donc illustratives et non réelles.
- La correspondance `user_id` / `user_name` n'a pas pu être validée ; les analyses clients reposent sur l'identifiant.
- Piste : enrichir le modèle avec une dimension géographique si une source supplémentaire est disponible.

## Contenu du dépôt

- `PROJET_Amazon_BI.sql` : création de la base, des tables et peuplement du modèle en étoile
- `SQLQuery3.sql` : requêtes de vérification
- `power BI PFA.pbix` : tableaux de bord Power BI
- `Rapport_Projet_Decisionnel_Amazon_version_finale.pdf` : rapport complet du projet
- `Screenshot ... .png` : captures d'écran des tableaux de bord
- `README.md` : ce fichier

## Reproduire le projet

1. Créer la base `Amazon_BI` et exécuter `PROJET_Amazon_BI.sql` pour créer les tables.
2. Télécharger le dataset *Amazon Sales* sur Kaggle (`amazon.csv`).
3. Créer le package SSIS (Flat File Source → Derived Column → OLE DB Destination) vers `Staging_Amazon`.
4. Exécuter les requêtes T-SQL de peuplement des dimensions puis de `Fait_Ventes`.
5. Ouvrir `power BI PFA.pbix` dans Power BI Desktop et mettre à jour la source de données vers votre serveur SQL local.

## Contact

Fatima Rafiai · fatimarafiai0101@gmail.com · Tanger, Maroc
