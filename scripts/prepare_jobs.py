#!/usr/bin/env python3
"""Prepare HTCondor job manifests for the Jpsi DPS workflow."""

import argparse
import os
import re
import sys

try:
    import pathlib
except ImportError:
    import pathlib2 as pathlib

DEFAULT_EOS_BASE = "root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
THIS_DIR = pathlib.Path(__file__).resolve().parent
DEFAULT_OUTPUT_PATH = THIS_DIR.parent / "config" / "lhe_jobs.txt"
JOB_LINE_PATTERN = re.compile(r"MC_Jpsi_block_(\d{5})\.lhe$")


def build_from_list(lines, eos_base):
    # type: (list, str) -> list
    """Build job list from a text file with LHE entries."""
    jobs = []
    for raw in lines:
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.startswith("root://") or entry.startswith("srm://"):
            uri = entry
        elif entry.startswith("/eos/"):
            uri = "root://eosuser.cern.ch{0}".format(entry)
        elif entry.startswith("file:"):
            uri = entry
        else:
            uri = "{0}/{1}".format(eos_base.rstrip('/'), entry.lstrip('/'))
        block_match = JOB_LINE_PATTERN.search(uri)
        label = block_match.group(1) if block_match else "job_{0:05d}".format(len(jobs))
        jobs.append(("block_{0}".format(label), uri))
    return jobs


def build_from_range(start, end, step, eos_base):
    # type: (int, int, int, str) -> list
    """Build job list from a numeric range."""
    if start > end:
        raise ValueError("start must be <= end")
    jobs = []
    for value in range(start, end + 1, step):
        label = "{0:05d}".format(value)
        filename = "MC_Jpsi_block_{0}.lhe".format(label)
        uri = "{0}/{1}".format(eos_base.rstrip('/'), filename)
        jobs.append(("block_{0}".format(label), uri))
    return jobs


def write_jobs(jobs, output):
    # type: (list, pathlib.Path) -> None
    """Write job manifest to file."""
    if not output.parent.exists():
        output.parent.mkdir(parents=True, exist_ok=True)
    with open(str(output), "w") as handle:
        for label, uri in jobs:
            handle.write("{0} {1}\n".format(label, uri))


def parse_args():
    # type: () -> argparse.Namespace
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode")

    list_parser = subparsers.add_parser("from-list", help="Use an explicit LHE list file")
    list_parser.add_argument("lhe_list", type=str, help="Text file with one LHE entry per line")
    list_parser.add_argument("--eos-base", default=DEFAULT_EOS_BASE, help="EOS base URI to prefix relative entries")

    range_parser = subparsers.add_parser("from-range", help="Generate filenames from a numeric range")
    range_parser.add_argument("start", type=int, help="First block number (inclusive)")
    range_parser.add_argument("end", type=int, help="Last block number (inclusive)")
    range_parser.add_argument("--step", type=int, default=10, help="Stride between block numbers")
    range_parser.add_argument("--eos-base", default=DEFAULT_EOS_BASE, help="EOS base URI")

    parser.add_argument("--output", type=str, default=str(DEFAULT_OUTPUT_PATH), help="Destination manifest")
    return parser.parse_args()


def main():
    # type: () -> None
    """Main entry point."""
    args = parse_args()
    
    if not args.mode:
        print("Error: Please specify a mode (from-list or from-range)", file=sys.stderr)
        sys.exit(1)
    
    if args.mode == "from-list":
        lhe_list_path = pathlib.Path(args.lhe_list)
        with open(str(lhe_list_path), "r") as f:
            lines = f.read().splitlines()
        jobs = build_from_list(lines, args.eos_base)
    elif args.mode == "from-range":
        jobs = build_from_range(args.start, args.end, args.step, args.eos_base)
    else:
        raise RuntimeError("Unsupported mode {0}".format(args.mode))

    if not jobs:
        print("No jobs generated; check your inputs", file=sys.stderr)
        sys.exit(1)

    output_path = pathlib.Path(args.output)
    write_jobs(jobs, output_path)
    print("Wrote {0} entries to {1}".format(len(jobs), output_path))


if __name__ == "__main__":
    main()
