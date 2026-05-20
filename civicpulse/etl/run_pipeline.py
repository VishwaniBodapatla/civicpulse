"""
CivicPulse: Pipeline Orchestrator
run_pipeline.py

End-to-end: generate → validate → load → refresh aggregates

Usage:
    python etl/run_pipeline.py
    python etl/run_pipeline.py --voters 10000 --donations 5000 --skip-generate
"""

import argparse
import logging
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("civicpulse.pipeline")


def run_step(label: str, cmd: list[str]) -> bool:
    log.info(f"{'─'*50}")
    log.info(f"STEP: {label}")
    log.info(f"{'─'*50}")
    t0 = time.time()
    result = subprocess.run(cmd, capture_output=False)
    elapsed = time.time() - t0
    if result.returncode == 0:
        log.info(f"  ✓  {label} completed in {elapsed:.1f}s")
        return True
    else:
        log.error(f"  ✗  {label} failed (exit {result.returncode})")
        return False


def main():
    parser = argparse.ArgumentParser(description="CivicPulse pipeline orchestrator")
    parser.add_argument("--voters",        type=int, default=50_000)
    parser.add_argument("--donations",     type=int, default=30_000)
    parser.add_argument("--precincts",     type=int, default=200)
    parser.add_argument("--db-type",       default="sqlserver")
    parser.add_argument("--skip-generate", action="store_true")
    args = parser.parse_args()

    log.info("=" * 55)
    log.info("  CivicPulse Pipeline Starting")
    log.info("=" * 55)

    steps = []

    if not args.skip_generate:
        steps.append((
            "Generate synthetic data",
            [
                sys.executable, "etl/generate_data.py",
                "--voters",    str(args.voters),
                "--donations", str(args.donations),
                "--precincts", str(args.precincts),
                "--output",    "data/",
            ],
        ))

    steps.append((
        "Load data to database",
        [
            sys.executable, "etl/load_to_db.py",
            "--db-type", args.db_type,
            "--data-dir", "data/",
        ],
    ))

    failures = []
    for label, cmd in steps:
        ok = run_step(label, cmd)
        if not ok:
            failures.append(label)

    log.info("=" * 55)
    if failures:
        log.error(f"Pipeline completed with {len(failures)} failure(s): {failures}")
        sys.exit(1)
    else:
        log.info("  Pipeline completed successfully.")
    log.info("=" * 55)


if __name__ == "__main__":
    main()
