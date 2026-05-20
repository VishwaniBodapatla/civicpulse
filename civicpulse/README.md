# CivicPulse – Political Campaign & Donor Analytics Pipeline

A SQL Server-based data engineering project simulating a real-world political data platform — covering voter registration, campaign donations, and election results. Built to demonstrate relational schema design, T-SQL stored procedures, ETL pipelines, and reporting-ready data models typical of progressive advocacy and campaign technology platforms.

---

## Project Overview

| Layer | Technology |
|-------|------------|
| Database | SQL Server / PostgreSQL compatible |
| Schema | Relational model — voters, candidates, donations, precincts, elections |
| Stored Procedures | T-SQL — aggregation, reporting, data quality |
| ETL | Python (Faker, Pandas, pyodbc / psycopg2) |
| Data Generation | ~100K synthetic rows across 6 tables |

---

## Schema

```
voters ──────────┐
                 ▼
precincts ──► election_results ◄── elections ◄── candidates
                                                      ▲
donations ───────────────────────────────────────────┘
```

### Tables

- **voters** — registered voters with party affiliation, precinct, state
- **precincts** — geographic units with county and state
- **candidates** — office-seekers with party and election cycle
- **elections** — federal/state/local election events
- **donations** — FEC-style contribution records linked to donors and candidates
- **election_results** — vote tallies by candidate × precinct × election

---

## Stored Procedures

| Procedure | Description |
|-----------|-------------|
| `usp_GetDonorSummaryByCandidate` | Total raised, avg donation, donor count per candidate |
| `usp_GetVoterTurnoutByPrecinct` | Turnout rate by precinct for a given election |
| `usp_GetTopDonorsByState` | Top N donors per state with cumulative totals |
| `usp_GetCandidateFundingBreakdown` | Funding by donation type (individual, PAC, small-dollar) |
| `usp_RefreshReportingAggregates` | Batch job to refresh summary/reporting tables |
| `usp_ValidateDataQuality` | Row-level checks: nulls, orphan FKs, out-of-range amounts |

---

## ETL Pipeline

```
generate_data.py  →  synthetic CSVs  →  load_to_db.py  →  SQL Server / PostgreSQL
```

1. `generate_data.py` — creates realistic synthetic data using Faker (names, addresses, FEC-style amounts)
2. `load_to_db.py` — schema-aware bulk loader with validation, upsert logic, and error logging
3. `run_pipeline.py` — orchestrates end-to-end: generate → validate → load → refresh aggregates

---

## Getting Started

### Prerequisites

```bash
pip install -r requirements.txt
```

### 1. Set up the database

```bash
# SQL Server
sqlcmd -S localhost -d master -i sql/schema/01_create_database.sql
sqlcmd -S localhost -d CivicPulse -i sql/schema/02_create_tables.sql
sqlcmd -S localhost -d CivicPulse -i sql/procedures/stored_procedures.sql
sqlcmd -S localhost -d CivicPulse -i sql/views/reporting_views.sql

# PostgreSQL
psql -U postgres -f sql/schema/01_create_database.sql
psql -U postgres -d civicpulse -f sql/schema/02_create_tables.sql
```

### 2. Generate synthetic data

```bash
python etl/generate_data.py --voters 50000 --donations 30000 --output data/
```

### 3. Load into database

```bash
# Configure connection in .env (see .env.example)
python etl/run_pipeline.py
```

### 4. Run reporting queries

```bash
sqlcmd -S localhost -d CivicPulse -Q "EXEC usp_GetDonorSummaryByCandidate @ElectionYear=2024"
```

---

## Sample Output

```
Candidate                  | Party | Total Raised  | Avg Donation | Donors
---------------------------|-------|---------------|--------------|-------
Alexandra Rivera (CA-12)   | D     | $1,842,310    | $87.42       | 21,073
Marcus Webb (TX-05)        | D     | $1,204,885    | $62.15       | 19,390
...
```

---

## Data Model Notes

- Donation amounts follow FEC individual contribution limits ($3,300 max for primaries)
- Voter party affiliation uses realistic state-level distribution weights
- Precinct sizes seeded from real US Census county data ranges
- No real PII — all names, addresses, and IDs are synthetic

---

## Skills Demonstrated

- Relational schema design with referential integrity, composite keys, and constraints
- T-SQL stored procedures with parameterization, error handling (`TRY/CATCH`), and transaction management
- Index strategy: clustered on PKs, non-clustered on high-cardinality FK and filter columns
- Bulk ETL with batch validation, deduplication, and error logging
- Data quality checks built into the pipeline

---

## License

MIT
