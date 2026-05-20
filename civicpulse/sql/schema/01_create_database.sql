-- ============================================================
-- CivicPulse: Political Campaign & Donor Analytics Platform
-- 01_create_database.sql
-- Compatible with SQL Server 2019+ and PostgreSQL 14+
-- ============================================================

-- SQL Server
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'CivicPulse')
BEGIN
    CREATE DATABASE CivicPulse
    COLLATE SQL_Latin1_General_CP1_CI_AS;
END
GO

USE CivicPulse;
GO
