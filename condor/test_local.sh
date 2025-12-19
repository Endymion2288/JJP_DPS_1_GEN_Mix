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
# LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
LHE_DIR="/eos/user/x/xcheng/learn_MC/ggJpsig_Jpsi_pt6_g_pt4"
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

# ============== 清理函数 ==============
cleanup() {
    echo ""
    echo "=========================================="
    echo "Cleaning up intermediate files..."
    echo "=========================================="
    # 在本地测试中，默认不自动删除中间文件，方便调试
    # 如果需要清理，可以取消下面行的注释
    # rm -f "${TEST_OUTPUT}"/*.hepmc "${TEST_OUTPUT}"/*.root "${TEST_OUTPUT}"/*.py
    echo "Cleanup skipped in local test. Manually remove ${TEST_OUTPUT} if needed."
}
# trap cleanup EXIT

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

# ============== 检查VOMS代理 ==============
echo ""
echo "Checking VOMS proxy..."
if [ -n "$X509_USER_PROXY" ] && [ -f "$X509_USER_PROXY" ]; then
    echo "Using X509_USER_PROXY: $X509_USER_PROXY"
elif [ -f "/tmp/x509up_u$(id -u)" ]; then
    export X509_USER_PROXY="/tmp/x509up_u$(id -u)"
    echo "Using default proxy: $X509_USER_PROXY"
fi

if voms-proxy-info --exists 2>/dev/null; then
    echo "VOMS proxy is valid:"
    voms-proxy-info --timeleft 2>/dev/null || true
else
    echo "WARNING: No valid VOMS proxy found!"
    echo "This may cause failures when accessing remote pileup files."
fi

BASENAME="test_N${LHE_BLOCK_NORMAL}_P${LHE_BLOCK_PHI}"
HEPMC_NORMAL="${TEST_OUTPUT}/${BASENAME}_normal.hepmc"
HEPMC_PHI="${TEST_OUTPUT}/${BASENAME}_phi.hepmc"
HEPMC_MIXED="${TEST_OUTPUT}/${BASENAME}_mixed.hepmc"
GENSIM_FILE="${TEST_OUTPUT}/${BASENAME}_GENSIM.root"
RAW_FILE="${TEST_OUTPUT}/${BASENAME}_RAW.root"
AOD_FILE="${TEST_OUTPUT}/${BASENAME}_AOD.root"
MINIAOD_FILE="${TEST_OUTPUT}/${BASENAME}_MINIAOD.root"

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
"${WORK_BASE}/pythia_shower/shower_phi" "${LHE_FILE_PHI}" "${HEPMC_PHI}" ${NEVENTS} 4.0 2.5 2.4 5000
echo "  Output: ${HEPMC_PHI}"
ls -lh "${HEPMC_PHI}"

# Step 3: Mixing
echo ""
echo "Step 3: Event Mixing..."
"${WORK_BASE}/pythia_shower/event_mixer_hepmc2" "${HEPMC_NORMAL}" "${HEPMC_PHI}" "${HEPMC_MIXED}"
echo "  Output: ${HEPMC_MIXED}"
ls -lh "${HEPMC_MIXED}"

# Step 4: HepMC -> GEN-SIM
echo ""
echo "Step 4: Converting HepMC to GEN-SIM..."
cmsRun "${WORK_BASE}/cmssw_configs/hepmc_to_GENSIM.py" \
    inputFiles="file:${HEPMC_MIXED}" \
    outputFile="file:${GENSIM_FILE}" \
    maxEvents=${NEVENTS}
echo "  Output: ${GENSIM_FILE}"
ls -lh "${GENSIM_FILE}"

# Step 5: GEN-SIM -> RAW
echo ""
echo "Step 5: Running DIGI-RAW (with pileup)..."
RAW_CFG="${TEST_OUTPUT}/raw_cfg.py"
cmsDriver.py step2 \
    --mc --no_exec \
    --python_filename "${RAW_CFG}" \
    --eventcontent PREMIXRAW \
    --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2022v12 \
    --procModifiers premix_stage2,siPixelQualityRawToDigi \
    --datamix PreMix \
    --datatier GEN-SIM-RAW \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --beamspot Realistic25ns13p6TeVEarly2022Collision \
    --era Run3 \
    --geometry DB:Extended \
    -n ${NEVENTS} \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --pileup_input "filelist:/cvmfs/cms.cern.ch/offcomp-prod/premixPUlist/PREMIX-Run3Summer22DRPremix.txt" \
    --filein "file:${GENSIM_FILE}" \
    --fileout "file:${RAW_FILE}"

cmsRun "${RAW_CFG}"
echo "  Output: ${RAW_FILE}"
ls -lh "${RAW_FILE}"

# Step 6: RAW -> AOD
echo ""
echo "Step 6: Running RECO (RAW -> AOD)..."
RECO_CFG="${TEST_OUTPUT}/reco_cfg.py"
cmsDriver.py step3 \
    --mc --no_exec \
    --python_filename "${RECO_CFG}" \
    --eventcontent AODSIM \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM \
    --procModifiers siPixelQualityRawToDigi \
    --datatier AODSIM \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --beamspot Realistic25ns13p6TeVEarly2022Collision \
    --era Run3 \
    --geometry DB:Extended \
    -n ${NEVENTS} \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --filein "file:${RAW_FILE}" \
    --fileout "file:${AOD_FILE}"

cmsRun "${RECO_CFG}"
echo "  Output: ${AOD_FILE}"
ls -lh "${AOD_FILE}"

# Step 7: AOD -> MiniAOD
echo ""
echo "Step 7: Running MiniAOD..."
MINIAOD_CFG="${TEST_OUTPUT}/miniaod_cfg.py"
cmsDriver.py step4 \
    --mc --no_exec \
    --python_filename "${MINIAOD_CFG}" \
    --eventcontent MINIAODSIM \
    --step PAT \
    --datatier MINIAODSIM \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --era Run3 \
    --geometry DB:Extended \
    -n ${NEVENTS} \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --filein "file:${AOD_FILE}" \
    --fileout "file:${MINIAOD_FILE}"

cmsRun "${MINIAOD_CFG}"
echo "  Output: ${MINIAOD_FILE}"
ls -lh "${MINIAOD_FILE}"

echo ""
echo "=========================================="
echo "Test Completed Successfully!"
echo "=========================================="
echo ""
echo "Output files in: ${TEST_OUTPUT}"
ls -la "${TEST_OUTPUT}"
echo ""
echo "To verify MiniAOD file content:"
echo "  edmDumpEventContent ${MINIAOD_FILE}"
echo ""
echo "If test passes, submit to HTCondor:"
echo "  condor_submit condor_submit.sub"
echo "=========================================="
