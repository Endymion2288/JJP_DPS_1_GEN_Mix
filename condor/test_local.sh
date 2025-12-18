#!/bin/bash
# test_local.sh - 本地测试单个作业
# 用于在提交到集群前验证完整工作流程
#
# 注意: 测试时使用两个不同的LHE文件，与正式作业一致
#
# 用法: ./test_local.sh <lhe_block_normal> <lhe_block_phi> [nevents]
# 例如: ./test_local.sh 00010 00020 10

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LHE_BLOCK_NORMAL="${1:-00010}"
LHE_BLOCK_PHI="${2:-00020}"
NEVENTS="${3:--1}"

echo "=========================================="
echo "Local Test Run"
echo "=========================================="
echo "LHE Block (Normal): ${LHE_BLOCK_NORMAL}"
echo "LHE Block (Phi):    ${LHE_BLOCK_PHI}"
echo "Events: ${NEVENTS}"
echo ""

# 检查LHE文件是否存在
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
LHE_FILE_NORMAL="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK_NORMAL}.lhe"
LHE_FILE_PHI="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK_PHI}.lhe"

if [ ! -f "${LHE_FILE_NORMAL}" ]; then
    echo "ERROR: LHE file (normal) not found: ${LHE_FILE_NORMAL}"
    exit 1
fi
if [ ! -f "${LHE_FILE_PHI}" ]; then
    echo "ERROR: LHE file (phi) not found: ${LHE_FILE_PHI}"
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

BASENAME="test_N${LHE_BLOCK_NORMAL}_P${LHE_BLOCK_PHI}"
HEPMC_NORMAL="${TEST_OUTPUT}/${BASENAME}_normal.hepmc"
HEPMC_PHI="${TEST_OUTPUT}/${BASENAME}_phi.hepmc"
HEPMC_MIXED="${TEST_OUTPUT}/${BASENAME}_mixed.hepmc"

# Step 1: Normal Shower (使用第一个LHE文件)
echo "Step 1: Normal Shower..."
echo "  Input: ${LHE_FILE_NORMAL}"
"${WORK_BASE}/pythia_shower/shower_normal" "${LHE_FILE_NORMAL}" "${HEPMC_NORMAL}" ${NEVENTS}
echo "  Output: ${HEPMC_NORMAL}"
ls -lh "${HEPMC_NORMAL}"

# Step 2: Phi-enriched Shower (使用第二个LHE文件)
echo ""
echo "Step 2: Phi-enriched Shower..."
echo "  Input: ${LHE_FILE_PHI}"
"${WORK_BASE}/pythia_shower/shower_phi" "${LHE_FILE_PHI}" "${HEPMC_PHI}" ${NEVENTS} 3.0 1000
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
