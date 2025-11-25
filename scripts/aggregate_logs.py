#!/usr/bin/env python3
"""Aggregate and summarize job logs from the Jpsi DPS production."""
from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


@dataclass
class StepResult:
    name: str
    status: int = -1
    runtime_s: int = 0
    events: str = ""
    filter_info: str = ""


@dataclass
class JobResult:
    label: str
    steps: List[StepResult] = field(default_factory=list)
    success: bool = False
    total_runtime_s: int = 0


STEP_BLOCK_RE = re.compile(
    r"step=(\w+)\nstatus=(\d+)\nruntime_s=(\d+)",
    re.MULTILINE,
)


def parse_summary_log(path: pathlib.Path) -> Optional[JobResult]:
    """Parse a single job summary log."""
    if not path.exists():
        return None
    content = path.read_text(encoding="utf-8", errors="replace")
    label_match = re.search(r"job_(\S+)_summary\.log", path.name)
    label = label_match.group(1) if label_match else path.stem

    result = JobResult(label=label)
    for match in STEP_BLOCK_RE.finditer(content):
        step = StepResult(
            name=match.group(1),
            status=int(match.group(2)),
            runtime_s=int(match.group(3)),
        )
        # Optionally capture events line
        events_match = re.search(rf"step={step.name}.*?events=([^\n]+)", content, re.DOTALL)
        if events_match:
            step.events = events_match.group(1).strip()
        result.steps.append(step)
        result.total_runtime_s += step.runtime_s

    result.success = all(s.status == 0 for s in result.steps) and len(result.steps) > 0
    return result


def aggregate_logs(log_dir: pathlib.Path) -> List[JobResult]:
    """Aggregate all summary logs in a directory."""
    results: List[JobResult] = []
    for log_file in sorted(log_dir.glob("job_*_summary.log")):
        job = parse_summary_log(log_file)
        if job:
            results.append(job)
    return results


def generate_summary(results: List[JobResult], output: pathlib.Path) -> None:
    """Generate a summary report."""
    total = len(results)
    success = sum(1 for r in results if r.success)
    failed = total - success

    step_stats: Dict[str, Dict[str, int]] = defaultdict(lambda: {"total": 0, "ok": 0, "fail": 0, "runtime": 0})

    for job in results:
        for step in job.steps:
            step_stats[step.name]["total"] += 1
            step_stats[step.name]["runtime"] += step.runtime_s
            if step.status == 0:
                step_stats[step.name]["ok"] += 1
            else:
                step_stats[step.name]["fail"] += 1

    lines: List[str] = []
    lines.append("=" * 60)
    lines.append("JJP DPS Production Summary")
    lines.append("=" * 60)
    lines.append(f"Total Jobs:     {total}")
    lines.append(f"Successful:     {success}")
    lines.append(f"Failed:         {failed}")
    lines.append("")
    lines.append("Step Statistics:")
    lines.append("-" * 60)
    lines.append(f"{'Step':<15} {'Total':>8} {'OK':>8} {'Fail':>8} {'Avg Time':>12}")
    lines.append("-" * 60)

    step_order = ["GEN_STANDARD", "GEN_PHI", "DPS_MIX", "SIM", "DIGI", "RECO", "MINIAOD"]
    for step_name in step_order:
        if step_name not in step_stats:
            continue
        stats = step_stats[step_name]
        avg_time = stats["runtime"] / stats["total"] if stats["total"] > 0 else 0
        lines.append(f"{step_name:<15} {stats['total']:>8} {stats['ok']:>8} {stats['fail']:>8} {avg_time:>10.1f}s")

    lines.append("-" * 60)
    lines.append("")

    if failed > 0:
        lines.append("Failed Jobs:")
        lines.append("-" * 60)
        for job in results:
            if not job.success:
                failed_steps = [s.name for s in job.steps if s.status != 0]
                lines.append(f"  {job.label}: {', '.join(failed_steps)}")
        lines.append("")

    lines.append("=" * 60)

    report = "\n".join(lines)
    print(report)

    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(report, encoding="utf-8")
        print(f"\nSummary written to {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_dir", type=pathlib.Path, help="Directory containing job summary logs")
    parser.add_argument(
        "--output",
        "-o",
        type=pathlib.Path,
        default=None,
        help="Output file for summary report",
    )
    args = parser.parse_args()

    if not args.log_dir.is_dir():
        print(f"Error: {args.log_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    results = aggregate_logs(args.log_dir)
    if not results:
        print(f"No job logs found in {args.log_dir}", file=sys.stderr)
        sys.exit(1)

    output_path = args.output or args.log_dir / "production_summary.txt"
    generate_summary(results, output_path)


if __name__ == "__main__":
    main()
