#!/bin/bash
# HTCondor worker wrapper for the Jpsi DPS production chain.
set -euo pipefail
IFS=$'\n\t'

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <job_label> <lhe_uri>" >&2
  exit 64
fi

job_label="$1"
input_lhe_uri="$2"

: "${EOS_OUTPUT_BASE:?Missing EOS_OUTPUT_BASE in environment}"
: "${LOG_OUTPUT_BASE:?Missing LOG_OUTPUT_BASE in environment}"

cmssw_base="${CMSSW_BASE_DIR:-}"
cmssw_tarball="${CMSSW_TARBALL:-}"

if [[ -z "${cmssw_base}" && -z "${cmssw_tarball}" ]]; then
  echo "Either CMSSW_BASE_DIR or CMSSW_TARBALL must be defined" >&2
  exit 64
fi

copy_intermediate="${COPY_INTERMEDIATE:-0}"
job_log_level="${JOB_LOG_LEVEL:-INFO}"

export SCRAM_ARCH="${SCRAM_ARCH:-el9_amd64_gcc11}"
source /cvmfs/cms.cern.ch/cmsset_default.sh

workdir="$(pwd)"
scratch_dir="$(mktemp -d "condor_${job_label}_XXXXXX")"
trap 'rm -rf "${scratch_dir}"' EXIT
cd "${scratch_dir}"

# Handle CMSSW tarball if provided
if [[ -n "${cmssw_tarball}" ]]; then
  echo "[$(date '+%F %T')] Staging CMSSW tarball" >&2
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
    echo "Failed to unpack CMSSW tarball ${cmssw_tarball}" >&2
    exit 70
  fi
  cmssw_base="${cmssw_base_candidate}"
fi

if [[ -z "${cmssw_base}" ]]; then
  echo "CMSSW base directory could not be resolved" >&2
  exit 64
fi

export CMSSW_BASE_DIR="${cmssw_base}"

pushd "${cmssw_base}/src" >/dev/null
# shellcheck disable=SC2046
eval "$(scramv1 runtime -sh)"
popd >/dev/null

full_log="${scratch_dir}/job_${job_label}_full.log"
summary_log="${scratch_dir}/job_${job_label}_summary.log"
touch "${full_log}" "${summary_log}"

# Route all stdout/stderr to the full log while keeping console output for Condor.
exec > >(tee -a "${full_log}") 2>&1
set -o pipefail

echo "[$(date '+%F %T')] Starting job ${job_label}" | tee -a "${summary_log}"
echo "CMSSW: ${cmssw_base}" | tee -a "${summary_log}"
echo "Input LHE: ${input_lhe_uri}" | tee -a "${summary_log}"

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

run_step() {
  local step_name="$1"
  shift
  local log_file="${scratch_dir}/${step_name}.log"
  local start_ts
  start_ts=$(date +%s)
  echo "[$(date '+%F %T')] >>> ${step_name}" | tee -a "${summary_log}"
  set +e
  "$@" 2>&1 | tee "${log_file}"
  local cmd_status
  cmd_status=${PIPESTATUS[0]}
  set -e
  local end_ts
  end_ts=$(date +%s)
  local runtime
  runtime=$((end_ts - start_ts))
  local trig_report
  trig_report=$(grep -E 'TrigReport|events total' "${log_file}" | tail -n 1 || true)
  local filter_line
  filter_line=$(grep -Ei 'filter (efficiency|efficienc)' "${log_file}" | tail -n 1 || true)
  {
    echo "step=${step_name}"
    echo "status=${cmd_status}"
    echo "runtime_s=${runtime}"
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
    return "${cmd_status}"
  fi
  return 0
}

standard_lhe_uri="file:${local_lhe}"
phi_lhe_uri="file:${local_lhe}"

run_step GEN_STANDARD env LHE_LIST_STANDARD="${standard_lhe_uri}" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_GEN_standard.py"

mv -f JpsiG_GEN_standard.root "GEN_standard_${job_label}.root"

run_step GEN_PHI env LHE_LIST_PHI="${phi_lhe_uri}" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_GEN_phi.py"

mv -f JpsiG_GEN_phi.root "GEN_phi_${job_label}.root"

run_step DPS_MIX env \
  GEN_DPS_PHI_INPUT="file:${PWD}/GEN_phi_${job_label}.root" \
  GEN_DPS_STD_INPUT="file:${PWD}/GEN_standard_${job_label}.root" \
  GEN_DPS_OUTPUT="file:JpsiG_GEN_DPS.root" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_GEN_DPS.py"

mv -f JpsiG_GEN_DPS.root "GEN_DPS_${job_label}.root"

run_step SIM env \
  SIM_INPUT="file:${PWD}/GEN_DPS_${job_label}.root" \
  SIM_OUTPUT="file:JpsiG_DPS_GENSIM.root" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_DPS_SIM.py"

mv -f JpsiG_DPS_GENSIM.root "SIM_${job_label}.root"

run_step DIGI env \
  DIGI_INPUT="file:${PWD}/SIM_${job_label}.root" \
  DIGI_OUTPUT="file:JpsiG_DPS_DIGIHLT.root" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_DPS_DIGI.py"

mv -f JpsiG_DPS_DIGIHLT.root "DIGI_${job_label}.root"

run_step RECO env \
  RECO_INPUT="file:${PWD}/DIGI_${job_label}.root" \
  RECO_OUTPUT="file:JpsiG_DPS_AODSIM.root" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_DPS_RECO.py"

mv -f JpsiG_DPS_AODSIM.root "RECO_${job_label}.root"

run_step MINIAOD env \
  MINIAOD_INPUT="file:${PWD}/RECO_${job_label}.root" \
  MINIAOD_OUTPUT="file:JpsiG_DPS_MINIAOD.root" \
  cmsRun "${CMSSW_BASE_DIR}/src/JJP_DPS_1_GEN_Mix/JpsiG_DPS_MINIAOD.py"

mv -f JpsiG_DPS_MINIAOD.root "MINIAOD_${job_label}.root"

echo "[$(date '+%F %T')] Copying outputs" | tee -a "${summary_log}"
mkdir -p "${LOG_OUTPUT_BASE}"

log_dest_full="${LOG_OUTPUT_BASE}/job_${job_label}_full.log"
log_dest_summary="${LOG_OUTPUT_BASE}/job_${job_label}_summary.log"
cp -f "${full_log}" "${log_dest_full}"
cp -f "${summary_log}" "${log_dest_summary}"

eos_base_uri="${EOS_OUTPUT_BASE%/}"
miniaod_target="${job_label}/"

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

# Ensure remote directory exists.
if [[ -n "${eos_host}" ]]; then
  if command -v xrdfs >/dev/null 2>&1; then
    xrdfs "${eos_host}" mkdir -p "${eos_path}/${job_label}"
  else
    echo "Warning: xrdfs not found, skipping remote directory creation" | tee -a "${summary_log}"
  fi
else
  mkdir -p "${eos_path}/${job_label}"
fi

final_miniaod="MINIAOD_${job_label}.root"
if [[ -n "${eos_host}" ]]; then
  xrdcp --nopbar -f "${final_miniaod}" "${eos_base_uri}/${job_label}/${final_miniaod}"
else
  mkdir -p "${eos_base_uri}/${job_label}"
  cp -f "${final_miniaod}" "${eos_base_uri}/${job_label}/"
fi

if [[ "${copy_intermediate}" == "1" ]]; then
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

echo "[$(date '+%F %T')] Job ${job_label} completed" | tee -a "${summary_log}"

# Persist summary next to MINIAOD for bookkeeping.
summary_remote="${job_label}_summary.log"
if [[ -n "${eos_host}" ]]; then
  xrdcp --nopbar -f "${summary_log}" "${eos_base_uri}/${job_label}/${summary_remote}"
else
  cp -f "${summary_log}" "${eos_base_uri}/${job_label}/${summary_remote}"
fi

cd "${workdir}"
rm -rf "${scratch_dir}"
trap - EXIT
