-- ============================================================
-- CivicPulse: Stored Procedures
-- stored_procedures.sql
-- ============================================================

USE CivicPulse;
GO

-- -------------------------------------------------------
-- 1. DONOR SUMMARY BY CANDIDATE
-- Returns total raised, avg donation, unique donor count
-- for a given election cycle (or all cycles if NULL)
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetDonorSummaryByCandidate', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetDonorSummaryByCandidate;
GO

CREATE PROCEDURE dbo.usp_GetDonorSummaryByCandidate
    @ElectionCycle  SMALLINT = NULL,
    @Party          VARCHAR(3) = NULL,
    @StateCode      CHAR(2) = NULL,
    @TopN           INT = 25
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @TopN <= 0 OR @TopN > 1000
            RAISERROR('TopN must be between 1 and 1000.', 16, 1);

        SELECT TOP (@TopN)
            c.CandidateID,
            c.FirstName + ' ' + c.LastName               AS CandidateName,
            c.Party,
            c.OfficeSought,
            c.StateCode,
            c.ElectionCycle,
            COUNT(DISTINCT d.VoterID)                    AS UniqueDonors,
            COUNT(d.DonationID)                          AS TotalDonations,
            SUM(CASE WHEN d.IsRefunded = 0 THEN d.Amount ELSE 0 END)
                                                         AS TotalRaised,
            AVG(CASE WHEN d.IsRefunded = 0 THEN d.Amount END)
                                                         AS AvgDonationAmount,
            MIN(d.DonationDate)                          AS FirstDonationDate,
            MAX(d.DonationDate)                          AS LastDonationDate,
            SUM(CASE WHEN d.DonationType = 'SMALL_DOLLAR' AND d.IsRefunded = 0 THEN d.Amount ELSE 0 END)
                                                         AS SmallDollarTotal,
            SUM(CASE WHEN d.DonationType = 'PAC' AND d.IsRefunded = 0 THEN d.Amount ELSE 0 END)
                                                         AS PACTotal
        FROM dbo.Candidates c
        INNER JOIN dbo.Donations d ON d.CandidateID = c.CandidateID
        WHERE (@ElectionCycle IS NULL OR c.ElectionCycle = @ElectionCycle)
          AND (@Party         IS NULL OR c.Party          = @Party)
          AND (@StateCode     IS NULL OR c.StateCode      = @StateCode)
        GROUP BY
            c.CandidateID, c.FirstName, c.LastName, c.Party,
            c.OfficeSought, c.StateCode, c.ElectionCycle
        ORDER BY TotalRaised DESC;

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSev INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSev, 1);
    END CATCH
END;
GO


-- -------------------------------------------------------
-- 2. VOTER TURNOUT BY PRECINCT
-- Calculates turnout rate per precinct for a given election
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetVoterTurnoutByPrecinct', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetVoterTurnoutByPrecinct;
GO

CREATE PROCEDURE dbo.usp_GetVoterTurnoutByPrecinct
    @ElectionID     INT,
    @StateCode      CHAR(2) = NULL,
    @MinTurnoutPct  DECIMAL(5,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Elections WHERE ElectionID = @ElectionID)
            RAISERROR('ElectionID %d not found.', 16, 1, @ElectionID);

        SELECT
            p.PrecinctID,
            p.PrecinctCode,
            p.PrecinctName,
            p.County,
            p.StateCode,
            p.RegisteredVoters,
            SUM(er.VotesCast)                                        AS TotalVotesCast,
            CASE
                WHEN p.RegisteredVoters > 0
                THEN CAST(SUM(er.VotesCast) AS DECIMAL(10,2))
                     / p.RegisteredVoters * 100
                ELSE 0
            END                                                      AS TurnoutPct,
            COUNT(DISTINCT er.CandidateID)                          AS CandidatesOnBallot
        FROM dbo.Precincts p
        INNER JOIN dbo.ElectionResults er ON er.PrecinctID = p.PrecinctID
                                          AND er.ElectionID = @ElectionID
        WHERE (@StateCode IS NULL OR p.StateCode = @StateCode)
        GROUP BY
            p.PrecinctID, p.PrecinctCode, p.PrecinctName,
            p.County, p.StateCode, p.RegisteredVoters
        HAVING (@MinTurnoutPct IS NULL
            OR (CASE WHEN p.RegisteredVoters > 0
                     THEN CAST(SUM(er.VotesCast) AS DECIMAL(10,2)) / p.RegisteredVoters * 100
                     ELSE 0 END) >= @MinTurnoutPct)
        ORDER BY TurnoutPct DESC;

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSev INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSev, 1);
    END CATCH
END;
GO


-- -------------------------------------------------------
-- 3. TOP DONORS BY STATE
-- Returns highest-contributing donors with cumulative totals
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetTopDonorsByState', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTopDonorsByState;
GO

CREATE PROCEDURE dbo.usp_GetTopDonorsByState
    @StateCode      CHAR(2),
    @ElectionCycle  SMALLINT = NULL,
    @TopN           INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SELECT TOP (@TopN)
            v.VoterID,
            v.FirstName + ' ' + v.LastName              AS DonorName,
            v.City,
            v.StateCode,
            v.ZipCode,
            v.PartyAffiliation,
            COUNT(d.DonationID)                         AS NumberOfDonations,
            SUM(d.Amount)                               AS TotalContributed,
            AVG(d.Amount)                               AS AvgDonation,
            MAX(d.Amount)                               AS LargestSingleDonation,
            MIN(d.DonationDate)                         AS FirstDonation,
            MAX(d.DonationDate)                         AS MostRecentDonation,
            COUNT(DISTINCT d.CandidateID)               AS CandidatesSupported,
            SUM(SUM(d.Amount)) OVER ()                  AS StateGrandTotal,
            SUM(d.Amount) / SUM(SUM(d.Amount)) OVER () * 100
                                                        AS PctOfStateTotal
        FROM dbo.Voters v
        INNER JOIN dbo.Donations d ON d.VoterID = v.VoterID
        INNER JOIN dbo.Candidates c ON c.CandidateID = d.CandidateID
        WHERE v.StateCode = @StateCode
          AND d.IsRefunded = 0
          AND (@ElectionCycle IS NULL OR c.ElectionCycle = @ElectionCycle)
        GROUP BY
            v.VoterID, v.FirstName, v.LastName,
            v.City, v.StateCode, v.ZipCode, v.PartyAffiliation
        ORDER BY TotalContributed DESC;

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSev INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSev, 1);
    END CATCH
END;
GO


-- -------------------------------------------------------
-- 4. CANDIDATE FUNDING BREAKDOWN
-- Breaks down funding by type (individual, PAC, small-dollar)
-- with monthly trend
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetCandidateFundingBreakdown', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetCandidateFundingBreakdown;
GO

CREATE PROCEDURE dbo.usp_GetCandidateFundingBreakdown
    @CandidateID    INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Candidates WHERE CandidateID = @CandidateID)
            RAISERROR('CandidateID %d not found.', 16, 1, @CandidateID);

        -- Summary by donation type
        SELECT
            c.FirstName + ' ' + c.LastName  AS CandidateName,
            c.Party,
            c.OfficeSought,
            c.StateCode,
            c.ElectionCycle,
            d.DonationType,
            COUNT(d.DonationID)             AS DonationCount,
            SUM(d.Amount)                   AS TotalAmount,
            AVG(d.Amount)                   AS AvgAmount,
            MIN(d.Amount)                   AS MinAmount,
            MAX(d.Amount)                   AS MaxAmount
        FROM dbo.Candidates c
        INNER JOIN dbo.Donations d ON d.CandidateID = c.CandidateID
        WHERE c.CandidateID = @CandidateID
          AND d.IsRefunded = 0
        GROUP BY
            c.FirstName, c.LastName, c.Party, c.OfficeSought,
            c.StateCode, c.ElectionCycle, d.DonationType
        ORDER BY TotalAmount DESC;

        -- Monthly fundraising trend
        SELECT
            YEAR(d.DonationDate)        AS DonationYear,
            MONTH(d.DonationDate)       AS DonationMonth,
            FORMAT(d.DonationDate, 'MMM yyyy') AS MonthLabel,
            COUNT(d.DonationID)         AS DonationCount,
            SUM(d.Amount)               AS MonthlyTotal,
            SUM(SUM(d.Amount)) OVER (
                ORDER BY YEAR(d.DonationDate), MONTH(d.DonationDate)
                ROWS UNBOUNDED PRECEDING
            )                           AS CumulativeTotal
        FROM dbo.Donations d
        WHERE d.CandidateID = @CandidateID
          AND d.IsRefunded = 0
        GROUP BY YEAR(d.DonationDate), MONTH(d.DonationDate),
                 FORMAT(d.DonationDate, 'MMM yyyy')
        ORDER BY DonationYear, DonationMonth;

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSev INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSev, 1);
    END CATCH
END;
GO


-- -------------------------------------------------------
-- 5. REFRESH REPORTING AGGREGATES
-- Batch job to refresh summary tables; logs to audit table
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_RefreshReportingAggregates', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshReportingAggregates;
GO

CREATE PROCEDURE dbo.usp_RefreshReportingAggregates
    @RunID      UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @RunID IS NULL SET @RunID = NEWID();

    DECLARE @LogID      BIGINT;
    DECLARE @RowCount   INT;
    DECLARE @StepStart  DATETIME2;

    BEGIN TRY
        -- Log pipeline start
        INSERT INTO dbo.PipelineAuditLog (RunID, PipelineStep, Status, StartedAt)
        VALUES (@RunID, 'usp_RefreshReportingAggregates', 'STARTED', SYSUTCDATETIME());

        -- STEP 1: Update Precincts registered voter counts from Voters table
        SET @StepStart = SYSUTCDATETIME();

        UPDATE p
        SET p.RegisteredVoters = v.ActiveCount
        FROM dbo.Precincts p
        INNER JOIN (
            SELECT PrecinctID, COUNT(*) AS ActiveCount
            FROM dbo.Voters
            WHERE RegistrationStatus = 'ACTIVE'
            GROUP BY PrecinctID
        ) v ON v.PrecinctID = p.PrecinctID;

        SET @RowCount = @@ROWCOUNT;

        INSERT INTO dbo.PipelineAuditLog (RunID, PipelineStep, TableName, RowsProcessed, Status, StartedAt, CompletedAt)
        VALUES (@RunID, 'UpdatePrecinctCounts', 'Precincts', @RowCount, 'SUCCESS', @StepStart, SYSUTCDATETIME());

        -- Log overall completion
        UPDATE dbo.PipelineAuditLog
        SET Status = 'SUCCESS', CompletedAt = SYSUTCDATETIME()
        WHERE RunID = @RunID AND PipelineStep = 'usp_RefreshReportingAggregates';

        SELECT @RunID AS RunID, 'SUCCESS' AS Status,
               SYSUTCDATETIME() AS CompletedAt;

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();

        UPDATE dbo.PipelineAuditLog
        SET Status = 'FAILED', ErrorMessage = @ErrMsg, CompletedAt = SYSUTCDATETIME()
        WHERE RunID = @RunID AND PipelineStep = 'usp_RefreshReportingAggregates';

        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END;
GO


-- -------------------------------------------------------
-- 6. DATA QUALITY VALIDATION
-- Row-level checks: nulls, orphaned FKs, out-of-range values
-- -------------------------------------------------------
IF OBJECT_ID('dbo.usp_ValidateDataQuality', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ValidateDataQuality;
GO

CREATE PROCEDURE dbo.usp_ValidateDataQuality
    @TableName  VARCHAR(100) = NULL   -- NULL = check all tables
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #QualityIssues (
        CheckName       VARCHAR(200),
        TableName       VARCHAR(100),
        IssueCount      INT,
        SeverityLevel   VARCHAR(10),   -- HIGH, MEDIUM, LOW
        Description     NVARCHAR(500)
    );

    -- VOTERS checks
    IF @TableName IS NULL OR @TableName = 'Voters'
    BEGIN
        -- Orphaned precinct references
        INSERT INTO #QualityIssues
        SELECT 'OrphanedPrecinctFK', 'Voters',
               COUNT(*), 'HIGH',
               'Voters referencing non-existent PrecinctIDs'
        FROM dbo.Voters v
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Precincts p WHERE p.PrecinctID = v.PrecinctID);

        -- Future registration dates
        INSERT INTO #QualityIssues
        SELECT 'FutureRegistrationDate', 'Voters',
               COUNT(*), 'HIGH',
               'Voters with RegistrationDate in the future'
        FROM dbo.Voters
        WHERE RegistrationDate > CAST(GETDATE() AS DATE);

        -- Missing zip codes
        INSERT INTO #QualityIssues
        SELECT 'MissingZipCode', 'Voters',
               COUNT(*), 'MEDIUM',
               'Voters with NULL or blank ZipCode'
        FROM dbo.Voters
        WHERE ZipCode IS NULL OR ZipCode = '';
    END

    -- DONATIONS checks
    IF @TableName IS NULL OR @TableName = 'Donations'
    BEGIN
        -- Donations exceeding FEC limit
        INSERT INTO #QualityIssues
        SELECT 'ExceedsFECLimit', 'Donations',
               COUNT(*), 'HIGH',
               'Individual donations exceeding $3,300 FEC contribution limit'
        FROM dbo.Donations
        WHERE DonationType = 'INDIVIDUAL' AND Amount > 3300;

        -- Orphaned voter references
        INSERT INTO #QualityIssues
        SELECT 'OrphanedVoterFK', 'Donations',
               COUNT(*), 'HIGH',
               'Donations with VoterID not in Voters table'
        FROM dbo.Donations d
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Voters v WHERE v.VoterID = d.VoterID);

        -- Future donation dates
        INSERT INTO #QualityIssues
        SELECT 'FutureDonationDate', 'Donations',
               COUNT(*), 'MEDIUM',
               'Donations dated in the future'
        FROM dbo.Donations
        WHERE DonationDate > CAST(GETDATE() AS DATE);
    END

    -- ELECTION RESULTS checks
    IF @TableName IS NULL OR @TableName = 'ElectionResults'
    BEGIN
        -- Results where votes exceed registered voters
        INSERT INTO #QualityIssues
        SELECT 'VotesExceedRegistered', 'ElectionResults',
               COUNT(*), 'HIGH',
               'Precincts where votes cast exceed registered voter count'
        FROM dbo.ElectionResults er
        INNER JOIN dbo.Precincts p ON p.PrecinctID = er.PrecinctID
        WHERE er.VotesCast > p.RegisteredVoters AND p.RegisteredVoters > 0;
    END

    SELECT CheckName, TableName, IssueCount, SeverityLevel, Description
    FROM #QualityIssues
    ORDER BY
        CASE SeverityLevel WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
        IssueCount DESC;

    DROP TABLE #QualityIssues;
END;
GO

PRINT 'All stored procedures created successfully.';
GO
