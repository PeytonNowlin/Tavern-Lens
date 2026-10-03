#!/usr/bin/env python3
"""Compare search benchmarks and fail if their workloads or exact outputs differ."""
import argparse
import json
import math
import statistics
from pathlib import Path


def compare(before, after):
    for field in ("schemaVersion", "depth", "width", "maximumExpansions", "repetitions"):
        if before[field] != after[field]:
            raise ValueError(f"Benchmark setting changed: {field}")

    def rows(report):
        indexed = {(row["caseID"], row["policy"]): row for row in report["rows"]}
        if not indexed or len(indexed) != len(report["rows"]):
            raise ValueError("Benchmark cases must be nonempty and unique")
        return indexed

    old, new = rows(before), rows(after)
    if old.keys() != new.keys():
        raise ValueError("Benchmark case identities or policies changed")
    comparisons = []
    for key in sorted(old):
        left, right = old[key], new[key]
        for field in ("expanded", "retainedPlans", "behaviorSHA256"):
            if left[field] != right[field]:
                raise ValueError(f"Behavior changed for {key}: {field}")
        prior = left["timing"]["warmMedianMS"]
        current = right["timing"]["warmMedianMS"]
        if not math.isfinite(prior) or not math.isfinite(current) or prior <= 0 or current <= 0:
            raise ValueError("Search timings must be finite and positive")
        comparisons.append({"caseID": key[0], "policy": key[1],
                            "beforeMS": prior, "afterMS": current,
                            "reductionPercent": 100 * (1 - current / prior)})
    total_before = sum(row["beforeMS"] for row in comparisons)
    total_after = sum(row["afterMS"] for row in comparisons)
    return {"scope": "Paired release search timings, not live app latency",
            "identicalBehaviorCases": len(comparisons),
            "sumOfCaseMediansBeforeMS": total_before,
            "sumOfCaseMediansAfterMS": total_after,
            "totalReductionPercent": 100 * (1 - total_after / total_before),
            "medianCaseReductionPercent": statistics.median(
                row["reductionPercent"] for row in comparisons),
            "cases": comparisons}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    try:
        result = compare(json.loads(args.before.read_text()), json.loads(args.after.read_text()))
    except (ValueError, KeyError) as error:
        parser.exit(1, f"Comparison failed: {error}\n")
    print(json.dumps(result, indent=2, sort_keys=True))
