-- ============================================================
-- CivicPulse: Reporting Views
-- reporting_views.sql
-- ============================================================

USE CivicPulse;
GO

-- -------------------------------------------------------
-- vw_DonorActivity
-- Flattened donor + donation view for reporting / BI tools
-- -------------------------------------------------------
IF OBJECT_ID('dbo.vw_DonorActivity', 'V') IS NOT NULL DROP VIEW dbo.vw_DonorActivity;
GO

CREATE VIEW dbo.vw_DonorActivity AS
SELECT
    d.DonationID,
    d.DonationDate,
    d.Amount,
    d.DonationType,
    d.PaymentMethod,
    d.IsRefunded,
    v.VoterID,
    v.FirstName + ' ' + v.LastName  AS DonorName,
    v.PartyAffiliation              AS DonorParty,
    v.StateCode                     AS DonorState,
    v.ZipCode                       AS DonorZip,
    c.CandidateID,
    c.FirstName + ' ' + c.LastName  AS CandidateName,
    c.Party                         AS CandidateParty,
    c.OfficeSought,
    c.StateCode                     AS CandidateState,
    c.ElectionCycle
FROM dbo.Donations d
INNER JOIN dbo.Voters     v ON v.VoterID     = d.VoterID
INNER JOIN dbo.Candidates c ON c.CandidateID = d.CandidateID;
GO


-- -------------------------------------------------------
-- vw_ElectionResultsSummary
-- Aggregated results by election × candidate with vote share
-- -------------------------------------------------------
IF OBJECT_ID('dbo.vw_ElectionResultsSummary', 'V') IS NOT NULL DROP VIEW dbo.vw_ElectionResultsSummary;
GO

CREATE VIEW dbo.vw_ElectionResultsSummary AS
SELECT
    e.ElectionID,
    e.ElectionName,
    e.ElectionDate,
    e.ElectionType,
    e.ElectionCycle,
    e.StateCode                     AS ElectionState,
    c.CandidateID,
    c.FirstName + ' ' + c.LastName  AS CandidateName,
    c.Party,
    c.OfficeSought,
    SUM(er.VotesCast)               AS TotalVotes,
    SUM(SUM(er.VotesCast)) OVER (PARTITION BY e.ElectionID)
                                    AS ElectionTotalVotes,
    CAST(
        SUM(er.VotesCast) * 100.0
        / NULLIF(SUM(SUM(er.VotesCast)) OVER (PARTITION BY e.ElectionID), 0)
    AS DECIMAL(5,2))                AS VoteSharePct
FROM dbo.ElectionResults er
INNER JOIN dbo.Elections  e ON e.ElectionID  = er.ElectionID
INNER JOIN dbo.Candidates c ON c.CandidateID = er.CandidateID
GROUP BY
    e.ElectionID, e.ElectionName, e.ElectionDate, e.ElectionType,
    e.ElectionCycle, e.StateCode,
    c.CandidateID, c.FirstName, c.LastName, c.Party, c.OfficeSought;
GO


-- -------------------------------------------------------
-- vw_VoterRegistrationSummary
-- Party breakdown by state and precinct
-- -------------------------------------------------------
IF OBJECT_ID('dbo.vw_VoterRegistrationSummary', 'V') IS NOT NULL DROP VIEW dbo.vw_VoterRegistrationSummary;
GO

CREATE VIEW dbo.vw_VoterRegistrationSummary AS
SELECT
    p.StateCode,
    p.County,
    p.PrecinctID,
    p.PrecinctName,
    COUNT(v.VoterID)                                            AS TotalRegistered,
    SUM(CASE WHEN v.PartyAffiliation = 'DEM' THEN 1 ELSE 0 END) AS DemCount,
    SUM(CASE WHEN v.PartyAffiliation = 'REP' THEN 1 ELSE 0 END) AS RepCount,
    SUM(CASE WHEN v.PartyAffiliation = 'IND' THEN 1 ELSE 0 END) AS IndCount,
    SUM(CASE WHEN v.PartyAffiliation NOT IN ('DEM','REP','IND') THEN 1 ELSE 0 END) AS OtherCount,
    SUM(CASE WHEN v.RegistrationStatus = 'ACTIVE' THEN 1 ELSE 0 END)   AS ActiveCount,
    SUM(CASE WHEN v.RegistrationStatus = 'INACTIVE' THEN 1 ELSE 0 END) AS InactiveCount
FROM dbo.Precincts p
LEFT JOIN dbo.Voters v ON v.PrecinctID = p.PrecinctID
GROUP BY p.StateCode, p.County, p.PrecinctID, p.PrecinctName;
GO

PRINT 'All views created successfully.';
GO
