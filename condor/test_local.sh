#!/bin/bash
# test_local.sh - 本地测试单个作业
# 用于在提交到集群前验证完整工作流程
#
# 用法: ./test_local.sh <lhe_block> [nevents]
# 例如: ./test_local.sh 00010 10

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LHE_BLOCK="${1:-00010}"
NEVENTS="${2:--1}"

echo "=========================================="
echo "Local Test Run"
echo "=========================================="
echo "LHE Block: ${LHE_BLOCK}"
echo "Events: ${NEVENTS}"
echo ""

# 检查LHE文件是否存在
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
LHE_FILE="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK}.lhe"

if [ ! -f "${LHE_FILE}" ]; then
    echo "ERROR: LHE file not found: ${LHE_FILE}"
    exit 1
fi

# 创建测试输出目录
TEST_OUTPUT="${SCRIPT_DIR}/test_output"
mkdir -p "${TEST_OUTPUT}"

# 设置环境变量以使用测试目录
export TEST_MODE="true"
export TEST_NEVENTS="${NEVENTS}"

# 检查程序是否已编译
WORK_BASE="$(dirname "${SCRIPT_DIR}")"
if [ ! -f "${WORK_BASE}/pythia_shower/shower_normal" ] || \
   [ ! -f "${WORK_BASE}/pythia_shower/shower_phi" ] || \
   [ ! -f "${WORK_BASE}/pythia_shower/event_mixer_hepmc2" ]; then
    echo "Programs not compiled. Running setup first..."
    source "${SCRIPT_DIR}/setup.sh"
fi

# 运行测试 - 使用简化版本进行快速测试
echo ""
echo "Running test workflow..."
echo ""

# 设置环境
CMSSW_BASE="$(dirname "$(dirname "${WORK_BASE}")")"
PYTHIA8_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/pythia8/306-494ded5c626b685d055d5b022e918c0c"
HEPMC3_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc3/3.2.5-c3cd50aeecf06b194814f1a75bf7872e"
HEPMC2_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc/2.06.10-46867a6dcc6e5712b7953fe57085fcbd"

export LD_LIBRARY_PATH="${PYTHIA8_BASE}/lib:${HEPMC3_BASE}/lib64:${HEPMC2_BASE}/lib:${LD_LIBRARY_PATH}"
export PYTHIA8DATA="${PYTHIA8_BASE}/share/Pythia8/xmldoc"

cd "${CMSSW_BASE}/src"
source /cvmfs/cms.cern.ch/cmsset_default.sh
eval $(scramv1 runtime -sh)
cd "${TEST_OUTPUT}"

BASENAME="test_block_${LHE_BLOCK}"
HEPMC_NORMAL="${TEST_OUTPUT}/${BASENAME}_normal.hepmc"
HEPMC_PHI="${TEST_OUTPUT}/${BASENAME}_phi.hepmc"
HEPMC_MIXED="${TEST_OUTPUT}/${BASENAME}_mixed.hepmc"

# Step 1: Normal Shower
echo "Step 1: Normal Shower..."
"${WORK_BASE}/pythia_shower/shower_normal" "${LHE_FILE}" "${HEPMC_NORMAL}" ${NEVENTS}
echo "  Output: ${HEPMC_NORMAL}"
ls -lh "${HEPMC_NORMAL}"

# Step 2: Phi-enriched Shower
echo ""
echo "Step 2: Phi-enriched Shower..."
"${WORK_BASE}/pythia_shower/shower_phi" "${LHE_FILE}" "${HEPMC_PHI}" ${NEVENTS} 0.0 100
echo "  Output: ${HEPMC_PHI}"
ls -lh "${HEPMC_PHI}"

# Step 3: Mixing
echo ""
echo "Step 3: Event Mixing..."
"${WORK_BASE}/pythia_shower/event_mixer_hepmc2" "${HEPMC_NORMAL}" "${HEPMC_PHI}" "${HEPMC_MIXED}"
echo "  Output: ${HEPMC_MIXED}"
ls -lh "${HEPMC_MIXED}"

# Step 4: HepMC -> GEN (只处理少量事例)
echo ""
echo "Step 4: HepMC -> GEN..."
GEN_FILE="${TEST_OUTPUT}/${BASENAME}_GEN.root"
cmsRun "${WORK_BASE}/cmssw_configs/hepmc_to_GENSIM.py" \
    inputFiles="file:${HEPMC_MIXED}" \
    outputFile="file:${GEN_FILE}" \
    maxEvents=${NEVENTS}
echo "  Output: ${GEN_FILE}"
ls -lh "${GEN_FILE}"

echo ""
echo "=========================================="
echo "Test Completed Successfully!"
echo "=========================================="
echo ""
echo "Output files in: ${TEST_OUTPUT}"
ls -la "${TEST_OUTPUT}"
echo ""
echo "To verify GEN file content:"
echo "  edmDumpEventContent ${GEN_FILE}"
echo ""
echo "If test passes, submit to HTCondor:"
echo "  condor_submit condor_submit.sub"
echo "=========================================="
