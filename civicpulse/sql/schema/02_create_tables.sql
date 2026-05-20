-- ============================================================
-- CivicPulse: Political Campaign & Donor Analytics Platform
-- 02_create_tables.sql
-- ============================================================

USE CivicPulse;
GO

-- -------------------------------------------------------
-- PRECINCTS
-- -------------------------------------------------------
IF OBJECT_ID('dbo.Precincts', 'U') IS NOT NULL DROP TABLE dbo.Precincts;
GO

CREATE TABLE dbo.Precincts (
    PrecinctID        INT           IDENTITY(1,1)   NOT NULL,
    PrecinctCode      VARCHAR(20)   NOT NULL,
    PrecinctName      NVARCHAR(100) NOT NULL,
    County            NVARCHAR(100) NOT NULL,
    StateCode         CHAR(2)       NOT NULL,
    RegisteredVoters  INT           NOT NULL DEFAULT 0,
    CreatedAt         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Precincts PRIMARY KEY CLUSTERED (PrecinctID),
    CONSTRAINT UQ_Precincts_Code UNIQUE (PrecinctCode),
    CONSTRAINT CK_Precincts_StateCode CHECK (LEN(StateCode) = 2),
    CONSTRAINT CK_Precincts_RegisteredVoters CHECK (RegisteredVoters >= 0)
);

CREATE NONCLUSTERED INDEX IX_Precincts_State ON dbo.Precincts (StateCode);
CREATE NONCLUSTERED INDEX IX_Precincts_County ON dbo.Precincts (County, StateCode);
GO

-- -------------------------------------------------------
-- VOTERS
-- -------------------------------------------------------
IF OBJECT_ID('dbo.Voters', 'U') IS NOT NULL DROP TABLE dbo.Voters;
GO

CREATE TABLE dbo.Voters (
    VoterID             BIGINT        IDENTITY(1,1)   NOT NULL,
    StateVoterID        VARCHAR(20)   NOT NULL,
    FirstName           NVARCHAR(100) NOT NULL,
    LastName            NVARCHAR(100) NOT NULL,
    DateOfBirth         DATE          NOT NULL,
    PartyAffiliation    VARCHAR(3)    NOT NULL,   -- DEM, REP, IND, GRN, LIB, OTH
    RegistrationDate    DATE          NOT NULL,
    RegistrationStatus  VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE, INACTIVE, PURGED
    PrecinctID          INT           NOT NULL,
    AddressLine1        NVARCHAR(200) NOT NULL,
    City                NVARCHAR(100) NOT NULL,
    StateCode           CHAR(2)       NOT NULL,
    ZipCode             VARCHAR(10)   NOT NULL,
    Email               VARCHAR(254)  NULL,
    Phone               VARCHAR(20)   NULL,
    CreatedAt           DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt           DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Voters PRIMARY KEY CLUSTERED (VoterID),
    CONSTRAINT UQ_Voters_StateVoterID UNIQUE (StateCode, StateVoterID),
    CONSTRAINT FK_Voters_Precinct FOREIGN KEY (PrecinctID) REFERENCES dbo.Precincts(PrecinctID),
    CONSTRAINT CK_Voters_Party CHECK (PartyAffiliation IN ('DEM', 'REP', 'IND', 'GRN', 'LIB', 'OTH')),
    CONSTRAINT CK_Voters_Status CHECK (RegistrationStatus IN ('ACTIVE', 'INACTIVE', 'PURGED')),
    CONSTRAINT CK_Voters_DOB CHECK (DateOfBirth <= CAST(GETDATE() AS DATE))
);

CREATE NONCLUSTERED INDEX IX_Voters_Precinct    ON dbo.Voters (PrecinctID) INCLUDE (PartyAffiliation, RegistrationStatus);
CREATE NONCLUSTERED INDEX IX_Voters_State       ON dbo.Voters (StateCode, PartyAffiliation);
CREATE NONCLUSTERED INDEX IX_Voters_LastName    ON dbo.Voters (LastName, FirstName);
CREATE NONCLUSTERED INDEX IX_Voters_ZipCode     ON dbo.Voters (ZipCode);
GO

-- -------------------------------------------------------
-- ELECTIONS
-- -------------------------------------------------------
IF OBJECT_ID('dbo.Elections', 'U') IS NOT NULL DROP TABLE dbo.Elections;
GO

CREATE TABLE dbo.Elections (
    ElectionID      INT           IDENTITY(1,1) NOT NULL,
    ElectionName    NVARCHAR(200) NOT NULL,
    ElectionDate    DATE          NOT NULL,
    ElectionType    VARCHAR(20)   NOT NULL,   -- GENERAL, PRIMARY, RUNOFF, SPECIAL
    ElectionCycle   SMALLINT      NOT NULL,   -- e.g. 2022, 2024
    StateCode       CHAR(2)       NOT NULL,
    IsNational      BIT           NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Elections PRIMARY KEY CLUSTERED (ElectionID),
    CONSTRAINT CK_Elections_Type CHECK (ElectionType IN ('GENERAL', 'PRIMARY', 'RUNOFF', 'SPECIAL')),
    CONSTRAINT CK_Elections_Cycle CHECK (ElectionCycle BETWEEN 2000 AND 2100)
);

CREATE NONCLUSTERED INDEX IX_Elections_Cycle ON dbo.Elections (ElectionCycle, StateCode);
GO

-- -------------------------------------------------------
-- CANDIDATES
-- -------------------------------------------------------
IF OBJECT_ID('dbo.Candidates', 'U') IS NOT NULL DROP TABLE dbo.Candidates;
GO

CREATE TABLE dbo.Candidates (
    CandidateID     INT           IDENTITY(1,1) NOT NULL,
    FECCandidateID  VARCHAR(20)   NULL,           -- Federal Election Commission ID
    FirstName       NVARCHAR(100) NOT NULL,
    LastName        NVARCHAR(100) NOT NULL,
    Party           VARCHAR(3)    NOT NULL,
    OfficeSought    NVARCHAR(100) NOT NULL,        -- e.g. 'U.S. Senate', 'State Assembly'
    District        VARCHAR(50)   NULL,
    StateCode       CHAR(2)       NOT NULL,
    ElectionCycle   SMALLINT      NOT NULL,
    IsIncumbent     BIT           NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Candidates PRIMARY KEY CLUSTERED (CandidateID),
    CONSTRAINT CK_Candidates_Party CHECK (Party IN ('DEM', 'REP', 'IND', 'GRN', 'LIB', 'OTH'))
);

CREATE NONCLUSTERED INDEX IX_Candidates_State  ON dbo.Candidates (StateCode, ElectionCycle);
CREATE NONCLUSTERED INDEX IX_Candidates_Party  ON dbo.Candidates (Party, ElectionCycle);
GO

-- -------------------------------------------------------
-- DONATIONS
-- -------------------------------------------------------
IF OBJECT_ID('dbo.Donations', 'U') IS NOT NULL DROP TABLE dbo.Donations;
GO

CREATE TABLE dbo.Donations (
    DonationID      BIGINT          IDENTITY(1,1) NOT NULL,
    VoterID         BIGINT          NOT NULL,         -- donor (linked to voter registry)
    CandidateID     INT             NOT NULL,
    DonationDate    DATE            NOT NULL,
    Amount          DECIMAL(10,2)   NOT NULL,
    DonationType    VARCHAR(20)     NOT NULL,          -- INDIVIDUAL, PAC, SMALL_DOLLAR, IN_KIND
    PaymentMethod   VARCHAR(20)     NULL,              -- CREDIT, CHECK, WIRE, ONLINE
    IsRefunded      BIT             NOT NULL DEFAULT 0,
    Notes           NVARCHAR(500)   NULL,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Donations PRIMARY KEY CLUSTERED (DonationID),
    CONSTRAINT FK_Donations_Voter     FOREIGN KEY (VoterID)     REFERENCES dbo.Voters(VoterID),
    CONSTRAINT FK_Donations_Candidate FOREIGN KEY (CandidateID) REFERENCES dbo.Candidates(CandidateID),
    CONSTRAINT CK_Donations_Amount   CHECK (Amount > 0 AND Amount <= 999999.99),
    CONSTRAINT CK_Donations_Type     CHECK (DonationType IN ('INDIVIDUAL', 'PAC', 'SMALL_DOLLAR', 'IN_KIND'))
);

CREATE NONCLUSTERED INDEX IX_Donations_Candidate  ON dbo.Donations (CandidateID, DonationDate) INCLUDE (Amount, DonationType);
CREATE NONCLUSTERED INDEX IX_Donations_Voter      ON dbo.Donations (VoterID, DonationDate);
CREATE NONCLUSTERED INDEX IX_Donations_Date       ON dbo.Donations (DonationDate);
GO

-- -------------------------------------------------------
-- ELECTION RESULTS
-- -------------------------------------------------------
IF OBJECT_ID('dbo.ElectionResults', 'U') IS NOT NULL DROP TABLE dbo.ElectionResults;
GO

CREATE TABLE dbo.ElectionResults (
    ResultID        BIGINT  IDENTITY(1,1) NOT NULL,
    ElectionID      INT     NOT NULL,
    CandidateID     INT     NOT NULL,
    PrecinctID      INT     NOT NULL,
    VotesCast       INT     NOT NULL DEFAULT 0,
    RegisteredCount INT     NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_ElectionResults PRIMARY KEY CLUSTERED (ResultID),
    CONSTRAINT FK_Results_Election  FOREIGN KEY (ElectionID)  REFERENCES dbo.Elections(ElectionID),
    CONSTRAINT FK_Results_Candidate FOREIGN KEY (CandidateID) REFERENCES dbo.Candidates(CandidateID),
    CONSTRAINT FK_Results_Precinct  FOREIGN KEY (PrecinctID)  REFERENCES dbo.Precincts(PrecinctID),
    CONSTRAINT UQ_Results_Combo     UNIQUE (ElectionID, CandidateID, PrecinctID),
    CONSTRAINT CK_Results_Votes     CHECK (VotesCast >= 0),
    CONSTRAINT CK_Results_Registered CHECK (RegisteredCount >= 0)
);

CREATE NONCLUSTERED INDEX IX_Results_Election   ON dbo.ElectionResults (ElectionID, PrecinctID);
CREATE NONCLUSTERED INDEX IX_Results_Candidate  ON dbo.ElectionResults (CandidateID, ElectionID);
GO

-- -------------------------------------------------------
-- PIPELINE AUDIT LOG
-- -------------------------------------------------------
IF OBJECT_ID('dbo.PipelineAuditLog', 'U') IS NOT NULL DROP TABLE dbo.PipelineAuditLog;
GO

CREATE TABLE dbo.PipelineAuditLog (
    LogID           BIGINT        IDENTITY(1,1) NOT NULL,
    RunID           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    PipelineStep    VARCHAR(100)  NOT NULL,
    TableName       VARCHAR(100)  NULL,
    RowsProcessed   INT           NULL,
    RowsFailed      INT           NULL DEFAULT 0,
    Status          VARCHAR(20)   NOT NULL,   -- STARTED, SUCCESS, FAILED, SKIPPED
    ErrorMessage    NVARCHAR(MAX) NULL,
    StartedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CompletedAt     DATETIME2     NULL,

    CONSTRAINT PK_PipelineAuditLog PRIMARY KEY CLUSTERED (LogID)
);
GO

PRINT 'All tables created successfully.';
GO
