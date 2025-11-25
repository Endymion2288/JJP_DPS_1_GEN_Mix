#!/bin/bash
# Master script to prepare and submit HTCondor jobs for the Jpsi DPS production.
# Run from the JJP_DPS_1_GEN_Mix_Condor directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============ Configuration ============
# Adjust these paths as needed

# CMSSW base directory (on shared filesystem)
CMSSW_BASE_DIR="${CMSSW_BASE_DIR:-/afs/cern.ch/user/x/xcheng/cernbox/learn_MC/project_gg_JJg_JJP/pythia_run/CMSSW_12_4_14_patch3}"

# EOS output base for MINIAOD files
EOS_OUTPUT_BASE="${EOS_OUTPUT_BASE:-root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/JJP_DPS_MINIAOD}"

# Log output directory (AFS or EOS)
LOG_OUTPUT_BASE="${LOG_OUTPUT_BASE:-/afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/logs}"

# Condor log directory for stdout/err/log
CONDOR_LOG_DIR="${CONDOR_LOG_DIR:-/afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/condor_logs}"

# Job manifest file
JOB_MANIFEST="${JOB_MANIFEST:-${BASE_DIR}/config/lhe_jobs.txt}"

# SCRAM architecture
SCRAM_ARCH="${SCRAM_ARCH:-el9_amd64_gcc11}"

# Whether to copy intermediate files (0 or 1)
COPY_INTERMEDIATE="${COPY_INTERMEDIATE:-0}"

# Log level (INFO or DEBUG)
JOB_LOG_LEVEL="${JOB_LOG_LEVEL:-INFO}"

# ============ End Configuration ============

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --manifest FILE       Job manifest file (default: ${JOB_MANIFEST})
  --cmssw-base DIR      CMSSW base directory (default: ${CMSSW_BASE_DIR})
  --eos-output URI      EOS output base URI (default: ${EOS_OUTPUT_BASE})
  --log-output DIR      Log output directory (default: ${LOG_OUTPUT_BASE})
  --condor-log DIR      Condor log directory (default: ${CONDOR_LOG_DIR})
  --copy-intermediate   Copy intermediate ROOT files to EOS
  --debug               Enable debug logging
  --dry-run             Show what would be submitted without submitting
  -h, --help            Show this help message

Example:
  $0 --manifest config/lhe_jobs.txt --eos-output root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/JJP_DPS_MINIAOD
EOF
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)
            JOB_MANIFEST="$2"
            shift 2
            ;;
        --cmssw-base)
            CMSSW_BASE_DIR="$2"
            shift 2
            ;;
        --eos-output)
            EOS_OUTPUT_BASE="$2"
            shift 2
            ;;
        --log-output)
            LOG_OUTPUT_BASE="$2"
            shift 2
            ;;
        --condor-log)
            CONDOR_LOG_DIR="$2"
            shift 2
            ;;
        --copy-intermediate)
            COPY_INTERMEDIATE=1
            shift
            ;;
        --debug)
            JOB_LOG_LEVEL="DEBUG"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ ! -f "${JOB_MANIFEST}" ]]; then
    echo "Error: Job manifest file not found: ${JOB_MANIFEST}" >&2
    exit 1
fi

if [[ ! -d "${CMSSW_BASE_DIR}/src" ]]; then
    echo "Error: CMSSW base directory not valid: ${CMSSW_BASE_DIR}" >&2
    exit 1
fi

# Create directories
mkdir -p "${LOG_OUTPUT_BASE}"
mkdir -p "${CONDOR_LOG_DIR}"

# Count jobs
num_jobs=$(grep -cve '^\s*#' -e '^\s*$' "${JOB_MANIFEST}" || echo 0)
if [[ "${num_jobs}" -eq 0 ]]; then
    echo "Error: No jobs found in manifest ${JOB_MANIFEST}" >&2
    exit 1
fi

echo "========================================"
echo "HTCondor Submission for Jpsi DPS Chain"
echo "========================================"
echo "CMSSW Base:        ${CMSSW_BASE_DIR}"
echo "EOS Output:        ${EOS_OUTPUT_BASE}"
echo "Log Output:        ${LOG_OUTPUT_BASE}"
echo "Condor Log:        ${CONDOR_LOG_DIR}"
echo "Job Manifest:      ${JOB_MANIFEST}"
echo "Number of Jobs:    ${num_jobs}"
echo "Copy Intermediate: ${COPY_INTERMEDIATE}"
echo "Log Level:         ${JOB_LOG_LEVEL}"
echo "========================================"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY RUN] Would submit ${num_jobs} jobs"
    echo "First 5 jobs:"
    head -n 5 "${JOB_MANIFEST}" | while read -r label uri; do
        echo "  - ${label}: ${uri}"
    done
    exit 0
fi

# Make wrapper executable
chmod +x "${BASE_DIR}/scripts/job_wrapper.sh"

# Submit to condor
echo "Submitting ${num_jobs} jobs to HTCondor..."

condor_submit \
    -append "SCRIPTS_DIR=${BASE_DIR}/scripts" \
    -append "CMSSW_BASE_DIR=${CMSSW_BASE_DIR}" \
    -append "EOS_OUTPUT_BASE=${EOS_OUTPUT_BASE}" \
    -append "LOG_OUTPUT_BASE=${LOG_OUTPUT_BASE}" \
    -append "CONDOR_LOG_DIR=${CONDOR_LOG_DIR}" \
    -append "SCRAM_ARCH=${SCRAM_ARCH}" \
    -append "COPY_INTERMEDIATE=${COPY_INTERMEDIATE}" \
    -append "JOB_LOG_LEVEL=${JOB_LOG_LEVEL}" \
    -append "JOB_MANIFEST=${JOB_MANIFEST}" \
    "${BASE_DIR}/condor/submit.sub"

echo "Submission complete. Monitor with: condor_q"
