#!/bin/bash
# HTCondor worker wrapper for the Jpsi DPS production chain.
# This script runs inside the el8 Singularity container.

# Note: We don't use 'set -u' because cmsset_default.sh uses unbound variables
set -eo pipefail
IFS=$'\n\t'

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <job_label> <lhe_uri>" >&2
  exit 64
fi

job_label="$1"
input_lhe_uri="$2"

# Check required environment variables with defaults
EOS_OUTPUT_BASE="${EOS_OUTPUT_BASE:-}"
LOG_OUTPUT_BASE="${LOG_OUTPUT_BASE:-}"

if [[ -z "${EOS_OUTPUT_BASE}" ]]; then
  echo "Missing EOS_OUTPUT_BASE in environment" >&2
  exit 64
fi

if [[ -z "${LOG_OUTPUT_BASE}" ]]; then
  echo "Missing LOG_OUTPUT_BASE in environment" >&2
  exit 64
fi

cmssw_base="${CMSSW_BASE_DIR:-}"
cmssw_tarball="${CMSSW_TARBALL:-}"

if [[ -z "${cmssw_base}" && -z "${cmssw_tarball}" ]]; then
  echo "Either CMSSW_BASE_DIR or CMSSW_TARBALL must be defined" >&2
  exit 64
fi

copy_intermediate="${COPY_INTERMEDIATE:-0}"
job_log_level="${JOB_LOG_LEVEL:-INFO}"

# CMSSW_12_4_14_patch3 uses el8_amd64_gcc10
export SCRAM_ARCH="${SCRAM_ARCH:-el8_amd64_gcc10}"

# Set CMS environment variables that cmsset_default.sh expects
export VO_CMS_SW_DIR="/cvmfs/cms.cern.ch"
export CMS_PATH="/cvmfs/cms.cern.ch"

# Source CMS environment
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Print environment info
echo "[$(date '+%F %T')] Starting job ${job_label}" >&2
echo "OS: $(cat /etc/redhat-release 2>/dev/null || echo 'unknown')" >&2
echo "SCRAM_ARCH: ${SCRAM_ARCH}" >&2
echo "CMSSW_BASE_DIR: ${cmssw_base}" >&2

workdir="$(pwd)"
# Create scratch directory - prefer TMPDIR, fallback to current directory
scratch_base="${TMPDIR:-${workdir}}"
scratch_dir=$(mktemp -d "${scratch_base}/condor_${job_label}_XXXXXX" 2>/dev/null) || \
  scratch_dir=$(mktemp -d "${workdir}/condor_${job_label}_XXXXXX")

if [[ ! -d "${scratch_dir}" ]]; then
  echo "Failed to create scratch directory" >&2
  exit 73
fi
echo "[$(date '+%F %T')] Created scratch directory: ${scratch_dir}" >&2

# Setup cleanup trap
cleanup() {
  local exit_code=$?
  cd "${workdir}" 2>/dev/null || true
  rm -rf "${scratch_dir}" 2>/dev/null || true
  exit ${exit_code}
}
trap cleanup EXIT INT TERM

cd "${scratch_dir}"

# Initialize log files early
full_log="${scratch_dir}/job_${job_label}_full.log"
summary_log="${scratch_dir}/job_${job_label}_summary.log"
touch "${full_log}" "${summary_log}"

# Route all stdout/stderr to the full log while keeping console output for Condor.
exec > >(tee -a "${full_log}") 2>&1

echo "[$(date '+%F %T')] Starting job ${job_label}" | tee -a "${summary_log}"
echo "OS: $(cat /etc/redhat-release 2>/dev/null || echo 'unknown')" | tee -a "${summary_log}"
echo "SCRAM_ARCH: ${SCRAM_ARCH}" | tee -a "${summary_log}"

# Handle CMSSW tarball if provided
if [[ -n "${cmssw_tarball}" ]]; then
  echo "[$(date '+%F %T')] Staging CMSSW tarball" | tee -a "${summary_log}"
  tarball_path="${scratch_dir}/cmssw_area.tgz"
  if [[ "${cmssw_tarball}" == root://* ]]; then
    xrdcp --nopbar -f "${cmssw_tarball}" "${tarball_path}"
  else
    cp -f "${cmssw_tarball}" "${tarball_path}"
  fi
  mkdir -p "${scratch_dir}/cmssw"
  tar -xzf "${tarball_path}" -C "${scratch_dir}/cmssw"
  cmssw_base_candidate=$(find "${scratch_dir}/cmssw" -maxdepth 1 -mindepth 1 -type d | head -n 1)
  if [[ -z "${cmssw_base_candidate}" ]]; then
    echo "Failed to unpack CMSSW tarball ${cmssw_tarball}" | tee -a "${summary_log}"
    exit 70
  fi
  cmssw_base="${cmssw_base_candidate}"
fi

if [[ -z "${cmssw_base}" ]]; then
  echo "CMSSW base directory could not be resolved" | tee -a "${summary_log}"
  exit 64
fi

# Setup CMSSW environment
echo "[$(date '+%F %T')] Setting up CMSSW environment" | tee -a "${summary_log}"
pushd "${cmssw_base}/src" >/dev/null
eval "$(scramv1 runtime -sh)"
popd >/dev/null
echo "CMSSW_BASE: ${CMSSW_BASE}" | tee -a "${summary_log}"

echo "CMSSW: ${cmssw_base}" | tee -a "${summary_log}"
echo "Input LHE: ${input_lhe_uri}" | tee -a "${summary_log}"

# Copy LHE input file
echo "[$(date '+%F %T')] Copying LHE input" | tee -a "${summary_log}"
local_lhe="${scratch_dir}/input_${job_label}.lhe"
if [[ "${input_lhe_uri}" == file:* ]]; then
  cp -v "${input_lhe_uri#file:}" "${local_lhe}"
else
  xrdcp --nopbar -f "${input_lhe_uri}" "${local_lhe}"
fi

if [[ ! -s "${local_lhe}" ]]; then
  echo "Failed to stage LHE file ${input_lhe_uri}" | tee -a "${summary_log}"
  exit 74
fi

echo "Local LHE path: ${local_lhe}" | tee -a "${summary_log}"

# Function to run a processing step with logging
run_step() {
  local step_name="$1"
  local config="$2"
  shift 2
  local env_vars=("$@")
  
  local log_file="${scratch_dir}/${step_name}.log"
  local start_ts
  start_ts=$(date +%s)
  
  echo "[$(date '+%F %T')] >>> ${step_name}" | tee -a "${summary_log}"
  
  # Set environment variables
  for var in "${env_vars[@]}"; do
    export "${var}"
  done
  
  set +e
  cmsRun "${config}" 2>&1 | tee "${log_file}"
  local cmd_status=${PIPESTATUS[0]}
  set -e
  
  local end_ts
  end_ts=$(date +%s)
  local runtime=$((end_ts - start_ts))
  
  # Extract statistics from log
  local trig_report
  trig_report=$(grep -E 'TrigReport|events total' "${log_file}" | tail -n 1 || true)
  local filter_line
  filter_line=$(grep -Ei 'filter (efficiency|efficienc)' "${log_file}" | tail -n 1 || true)
  local events_processed
  events_processed=$(grep -oE 'Events total = [0-9]+|TotalEvents = [0-9]+' "${log_file}" | tail -n 1 || true)
  
  {
    echo "step=${step_name}"
    echo "status=${cmd_status}"
    echo "runtime_s=${runtime}"
    [[ -n "${events_processed}" ]] && echo "events_info=${events_processed}"
    [[ -n "${trig_report}" ]] && echo "events=${trig_report}"
    [[ -n "${filter_line}" ]] && echo "filter=${filter_line}"
    echo "---"
  } >>"${summary_log}"
  
  if [[ "${job_log_level}" == "DEBUG" ]]; then
    sed 's/^/[DEBUG] /' "${log_file}" >>"${summary_log}"
    echo "---" >>"${summary_log}"
  fi
  
  if [[ ${cmd_status} -ne 0 ]]; then
    echo "Step ${step_name} failed with exit code ${cmd_status}" | tee -a "${summary_log}"
    # Copy logs before failing
    mkdir -p "${LOG_OUTPUT_BASE}" 2>/dev/null || true
    cp -f "${full_log}" "${LOG_OUTPUT_BASE}/job_${job_label}_full.log" 2>/dev/null || true
    cp -f "${summary_log}" "${LOG_OUTPUT_BASE}/job_${job_label}_summary.log" 2>/dev/null || true
    return "${cmd_status}"
  fi
  
  return 0
}

# Define paths for Python configs
config_base="${cmssw_base}/src/JJP_DPS_1_GEN_Mix"

# ============ Processing Steps ============

# Step 1: GEN_STANDARD - Standard shower
run_step GEN_STANDARD "${config_base}/JpsiG_GEN_standard.py" \
  "LHE_LIST_STANDARD=file:${local_lhe}"
mv -f JpsiG_GEN_standard.root "GEN_standard_${job_label}.root"

# Step 2: GEN_PHI - Phi shower
run_step GEN_PHI "${config_base}/JpsiG_GEN_phi.py" \
  "LHE_LIST_PHI=file:${local_lhe}"
mv -f JpsiG_GEN_phi.root "GEN_phi_${job_label}.root"

# Step 3: DPS_MIX - Mix two SPS events to form DPS
run_step DPS_MIX "${config_base}/JpsiG_GEN_DPS.py" \
  "GEN_DPS_PHI_INPUT=file:${scratch_dir}/GEN_phi_${job_label}.root" \
  "GEN_DPS_STD_INPUT=file:${scratch_dir}/GEN_standard_${job_label}.root" \
  "GEN_DPS_OUTPUT=file:JpsiG_GEN_DPS.root"
mv -f JpsiG_GEN_DPS.root "GEN_DPS_${job_label}.root"

# Step 4: SIM - Detector simulation
run_step SIM "${config_base}/JpsiG_DPS_SIM.py" \
  "SIM_INPUT=file:${scratch_dir}/GEN_DPS_${job_label}.root" \
  "SIM_OUTPUT=file:JpsiG_DPS_GENSIM.root"
mv -f JpsiG_DPS_GENSIM.root "SIM_${job_label}.root"

# Step 5: DIGI - Digitization and HLT
run_step DIGI "${config_base}/JpsiG_DPS_DIGI.py" \
  "DIGI_INPUT=file:${scratch_dir}/SIM_${job_label}.root" \
  "DIGI_OUTPUT=file:JpsiG_DPS_DIGIHLT.root"
mv -f JpsiG_DPS_DIGIHLT.root "DIGI_${job_label}.root"

# Step 6: RECO - Reconstruction
run_step RECO "${config_base}/JpsiG_DPS_RECO.py" \
  "RECO_INPUT=file:${scratch_dir}/DIGI_${job_label}.root" \
  "RECO_OUTPUT=file:JpsiG_DPS_AODSIM.root"
mv -f JpsiG_DPS_AODSIM.root "RECO_${job_label}.root"

# Step 7: MINIAOD - MiniAOD production
run_step MINIAOD "${config_base}/JpsiG_DPS_MINIAOD.py" \
  "MINIAOD_INPUT=file:${scratch_dir}/RECO_${job_label}.root" \
  "MINIAOD_OUTPUT=file:JpsiG_DPS_MINIAOD.root"
mv -f JpsiG_DPS_MINIAOD.root "MINIAOD_${job_label}.root"

# ============ Copy Outputs ============

echo "[$(date '+%F %T')] Copying outputs" | tee -a "${summary_log}"

# Create log output directory
mkdir -p "${LOG_OUTPUT_BASE}"
cp -f "${full_log}" "${LOG_OUTPUT_BASE}/job_${job_label}_full.log"
cp -f "${summary_log}" "${LOG_OUTPUT_BASE}/job_${job_label}_summary.log"

# Parse EOS output path
eos_base_uri="${EOS_OUTPUT_BASE%/}"
eos_host=""
eos_path=""

if [[ "${eos_base_uri}" == root://* ]]; then
  eos_host="${eos_base_uri#root://}"
  eos_host="${eos_host%%/*}"
  eos_path="${eos_base_uri#root://${eos_host}}"
  [[ "${eos_path}" == /* ]] || eos_path="/${eos_path}"
else
  eos_path="${eos_base_uri}"
fi

# Create remote directory
if [[ -n "${eos_host}" ]]; then
  if command -v xrdfs >/dev/null 2>&1; then
    xrdfs "${eos_host}" mkdir -p "${eos_path}/${job_label}" 2>/dev/null || true
  fi
else
  mkdir -p "${eos_path}/${job_label}"
fi

# Copy final MINIAOD file
final_miniaod="MINIAOD_${job_label}.root"
echo "[$(date '+%F %T')] Copying ${final_miniaod} to ${eos_base_uri}/${job_label}/" | tee -a "${summary_log}"

if [[ -n "${eos_host}" ]]; then
  xrdcp --nopbar -f "${final_miniaod}" "${eos_base_uri}/${job_label}/${final_miniaod}"
else
  cp -f "${final_miniaod}" "${eos_base_uri}/${job_label}/"
fi

# Optionally copy intermediate files
if [[ "${copy_intermediate}" == "1" ]]; then
  echo "[$(date '+%F %T')] Copying intermediate files" | tee -a "${summary_log}"
  for artifact in GEN_standard GEN_phi GEN_DPS SIM DIGI RECO; do
    fname="${artifact}_${job_label}.root"
    [[ -f "${fname}" ]] || continue
    if [[ -n "${eos_host}" ]]; then
      xrdcp --nopbar -f "${fname}" "${eos_base_uri}/${job_label}/${fname}"
    else
      cp -f "${fname}" "${eos_base_uri}/${job_label}/"
    fi
  done
fi

# Copy summary log to EOS
summary_remote="${job_label}_summary.log"
if [[ -n "${eos_host}" ]]; then
  xrdcp --nopbar -f "${summary_log}" "${eos_base_uri}/${job_label}/${summary_remote}"
else
  cp -f "${summary_log}" "${eos_base_uri}/${job_label}/${summary_remote}"
fi

echo "[$(date '+%F %T')] Job ${job_label} completed successfully" | tee -a "${summary_log}"
