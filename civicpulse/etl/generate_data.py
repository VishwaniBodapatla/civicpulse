"""
CivicPulse: Synthetic Political Data Generator
generate_data.py

Generates realistic synthetic data for:
  - Precincts, Voters, Candidates, Elections, Donations, ElectionResults

Usage:
    python etl/generate_data.py --voters 50000 --donations 30000 --output data/
"""

import argparse
import csv
import os
import random
from datetime import date, timedelta
from faker import Faker

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

# ── Configuration ─────────────────────────────────────────────────────────────

STATES = ["CA", "TX", "FL", "NY", "PA", "OH", "GA", "NC", "MI", "AZ",
          "WA", "CO", "MN", "OR", "WI", "NV", "IL", "VA", "NJ", "MA"]

# Realistic party distribution by state lean
PARTY_WEIGHTS = {
    "CA": {"DEM": 55, "REP": 20, "IND": 20, "GRN": 3, "LIB": 2},
    "TX": {"DEM": 30, "REP": 50, "IND": 15, "GRN": 1, "LIB": 4},
    "FL": {"DEM": 38, "REP": 42, "IND": 16, "GRN": 2, "LIB": 2},
    "NY": {"DEM": 52, "REP": 25, "IND": 18, "GRN": 3, "LIB": 2},
    "CO": {"DEM": 40, "REP": 35, "IND": 20, "GRN": 2, "LIB": 3},
    "GA": {"DEM": 42, "REP": 45, "IND": 10, "GRN": 1, "LIB": 2},
}
DEFAULT_PARTY_WEIGHTS = {"DEM": 38, "REP": 36, "IND": 20, "GRN": 3, "LIB": 3}

OFFICES = [
    "U.S. Senate", "U.S. House of Representatives",
    "Governor", "Lieutenant Governor",
    "State Senate", "State Assembly",
    "Attorney General", "Secretary of State",
    "County Commissioner", "City Council",
]

DONATION_TYPES = ["INDIVIDUAL", "INDIVIDUAL", "INDIVIDUAL", "SMALL_DOLLAR", "PAC", "IN_KIND"]
PAYMENT_METHODS = ["CREDIT", "CHECK", "ONLINE", "WIRE"]

# FEC-style amount buckets (individual limit: $3,300 primary)
AMOUNT_BUCKETS = [
    (25, 0.30),
    (50, 0.20),
    (100, 0.15),
    (250, 0.12),
    (500, 0.10),
    (1000, 0.07),
    (2500, 0.04),
    (3300, 0.02),
]


def weighted_party(state: str) -> str:
    weights = PARTY_WEIGHTS.get(state, DEFAULT_PARTY_WEIGHTS)
    parties = list(weights.keys())
    wts = list(weights.values())
    return random.choices(parties, weights=wts, k=1)[0]


def random_amount() -> float:
    buckets, probs = zip(*AMOUNT_BUCKETS)
    base = random.choices(buckets, weights=probs, k=1)[0]
    jitter = random.uniform(-base * 0.1, base * 0.1)
    return round(max(1.0, base + jitter), 2)


def random_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


# ── Generators ────────────────────────────────────────────────────────────────

def generate_precincts(n: int = 200) -> list[dict]:
    precincts = []
    for i in range(1, n + 1):
        state = random.choice(STATES)
        precincts.append({
            "PrecinctID": i,
            "PrecinctCode": f"{state}-{i:05d}",
            "PrecinctName": f"{fake.last_name()} {random.choice(['Township', 'District', 'Ward', 'Division'])}",
            "County": fake.last_name() + " County",
            "StateCode": state,
            "RegisteredVoters": 0,  # updated after voters generated
        })
    return precincts


def generate_voters(n: int, precincts: list[dict]) -> list[dict]:
    voters = []
    precinct_ids = [p["PrecinctID"] for p in precincts]
    for i in range(1, n + 1):
        state = random.choice(STATES)
        precinct = random.choice([p for p in precincts if p["StateCode"] == state] or precincts)
        dob = fake.date_of_birth(minimum_age=18, maximum_age=90)
        reg_date = random_date(date(2000, 1, 1), date(2024, 11, 1))
        voters.append({
            "VoterID": i,
            "StateVoterID": f"{state}{i:08d}",
            "FirstName": fake.first_name(),
            "LastName": fake.last_name(),
            "DateOfBirth": dob.isoformat(),
            "PartyAffiliation": weighted_party(state),
            "RegistrationDate": reg_date.isoformat(),
            "RegistrationStatus": random.choices(
                ["ACTIVE", "INACTIVE", "PURGED"], weights=[85, 12, 3]
            )[0],
            "PrecinctID": precinct["PrecinctID"],
            "AddressLine1": fake.street_address(),
            "City": fake.city(),
            "StateCode": state,
            "ZipCode": fake.zipcode(),
            "Email": fake.email() if random.random() < 0.6 else "",
            "Phone": fake.phone_number() if random.random() < 0.5 else "",
        })
    return voters


def generate_elections(n: int = 12) -> list[dict]:
    elections = []
    eid = 1
    for cycle in [2020, 2022, 2024]:
        for etype, edate in [
            ("PRIMARY", date(cycle, 6, 15)),
            ("GENERAL", date(cycle, 11, 5)),
        ]:
            for state in random.sample(STATES, k=4):
                elections.append({
                    "ElectionID": eid,
                    "ElectionName": f"{cycle} {state} {etype.capitalize()} Election",
                    "ElectionDate": edate.isoformat(),
                    "ElectionType": etype,
                    "ElectionCycle": cycle,
                    "StateCode": state,
                    "IsNational": 0,
                })
                eid += 1
                if eid > n:
                    return elections
    return elections


def generate_candidates(elections: list[dict], per_election: int = 3) -> list[dict]:
    candidates = []
    cid = 1
    for e in elections:
        parties = random.sample(["DEM", "REP", "IND"], k=min(per_election, 3))
        for party in parties:
            candidates.append({
                "CandidateID": cid,
                "FECCandidateID": f"P{cid:08d}",
                "FirstName": fake.first_name(),
                "LastName": fake.last_name(),
                "Party": party,
                "OfficeSought": random.choice(OFFICES),
                "District": f"District {random.randint(1, 52)}" if random.random() < 0.6 else "",
                "StateCode": e["StateCode"],
                "ElectionCycle": e["ElectionCycle"],
                "IsIncumbent": int(random.random() < 0.3),
            })
            cid += 1
    return candidates


def generate_donations(n: int, voters: list[dict], candidates: list[dict]) -> list[dict]:
    donations = []
    active_voters = [v for v in voters if v["RegistrationStatus"] == "ACTIVE"]
    for i in range(1, n + 1):
        voter = random.choice(active_voters)
        candidate = random.choice(candidates)
        dtype = random.choice(DONATION_TYPES)
        amount = random_amount()
        if dtype == "SMALL_DOLLAR":
            amount = round(random.uniform(1, 200), 2)
        elif dtype == "PAC":
            amount = round(random.uniform(500, 10000), 2)
        donations.append({
            "DonationID": i,
            "VoterID": voter["VoterID"],
            "CandidateID": candidate["CandidateID"],
            "DonationDate": random_date(date(2020, 1, 1), date(2025, 1, 1)).isoformat(),
            "Amount": amount,
            "DonationType": dtype,
            "PaymentMethod": random.choice(PAYMENT_METHODS),
            "IsRefunded": int(random.random() < 0.02),
            "Notes": "",
        })
    return donations


def generate_election_results(
    elections: list[dict],
    candidates: list[dict],
    precincts: list[dict],
) -> list[dict]:
    results = []
    rid = 1
    for e in elections:
        state_candidates = [c for c in candidates
                            if c["StateCode"] == e["StateCode"]
                            and c["ElectionCycle"] == e["ElectionCycle"]]
        state_precincts = [p for p in precincts if p["StateCode"] == e["StateCode"]]
        if not state_candidates or not state_precincts:
            continue
        for precinct in random.sample(state_precincts, k=min(5, len(state_precincts))):
            reg = precinct["RegisteredVoters"] or random.randint(500, 5000)
            total_votes = int(reg * random.uniform(0.45, 0.75))
            vote_splits = [random.random() for _ in state_candidates]
            total_split = sum(vote_splits)
            for idx, candidate in enumerate(state_candidates):
                votes = int(total_votes * vote_splits[idx] / total_split)
                results.append({
                    "ResultID": rid,
                    "ElectionID": e["ElectionID"],
                    "CandidateID": candidate["CandidateID"],
                    "PrecinctID": precinct["PrecinctID"],
                    "VotesCast": votes,
                    "RegisteredCount": reg,
                })
                rid += 1
    return results


# ── Writers ───────────────────────────────────────────────────────────────────

def write_csv(rows: list[dict], path: str) -> None:
    if not rows:
        print(f"  [WARN] No rows for {path}")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"  ✓  {len(rows):>7,} rows → {path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="CivicPulse synthetic data generator")
    parser.add_argument("--voters",    type=int, default=50_000)
    parser.add_argument("--donations", type=int, default=30_000)
    parser.add_argument("--precincts", type=int, default=200)
    parser.add_argument("--output",    type=str, default="data/")
    args = parser.parse_args()

    print(f"\n{'='*55}")
    print(f"  CivicPulse Data Generator")
    print(f"  Voters: {args.voters:,}   Donations: {args.donations:,}")
    print(f"{'='*55}\n")

    print("Generating precincts...")
    precincts = generate_precincts(args.precincts)

    print("Generating voters...")
    voters = generate_voters(args.voters, precincts)

    # Back-fill registered voter counts into precincts
    counts: dict[int, int] = {}
    for v in voters:
        if v["RegistrationStatus"] == "ACTIVE":
            counts[v["PrecinctID"]] = counts.get(v["PrecinctID"], 0) + 1
    for p in precincts:
        p["RegisteredVoters"] = counts.get(p["PrecinctID"], 0)

    print("Generating elections...")
    elections = generate_elections(n=20)

    print("Generating candidates...")
    candidates = generate_candidates(elections)

    print("Generating donations...")
    donations = generate_donations(args.donations, voters, candidates)

    print("Generating election results...")
    results = generate_election_results(elections, candidates, precincts)

    print("\nWriting CSVs...\n")
    write_csv(precincts,  os.path.join(args.output, "precincts.csv"))
    write_csv(voters,     os.path.join(args.output, "voters.csv"))
    write_csv(elections,  os.path.join(args.output, "elections.csv"))
    write_csv(candidates, os.path.join(args.output, "candidates.csv"))
    write_csv(donations,  os.path.join(args.output, "donations.csv"))
    write_csv(results,    os.path.join(args.output, "election_results.csv"))

    print(f"\n{'='*55}")
    print("  Data generation complete.")
    print(f"{'='*55}\n")


if __name__ == "__main__":
    main()
