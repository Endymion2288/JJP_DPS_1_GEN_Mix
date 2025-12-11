#!/bin/bash
# run_step_by_step.sh - 分步执行MC生产链
#
# 用法:
#   ./run_step_by_step.sh <step> <input> <output> [options]
#
# 步骤:
#   merge      - 合并两个HepMC文件 (需要两个输入文件)
#   hepmc2gen  - HepMC2 -> GEN (cmsRun hepmc2gen_cfg.py)
#   sim        - GEN -> GEN-SIM (Geant4)
#   raw        - GEN-SIM -> RAW (DIGI+HLT with pileup)
#   reco       - RAW -> AOD
#   miniaod    - AOD -> MiniAOD
#
# 示例:
#   ./run_step_by_step.sh merge input1.hepmc,input2.hepmc merged.hepmc -n 1000
#   ./run_step_by_step.sh hepmc2gen merged.hepmc output_GEN.root -n 1000
#   ./run_step_by_step.sh sim output_GEN.root output_GENSIM.root -n 1000
#   ./run_step_by_step.sh raw output_GENSIM.root output_RAW.root
#   ./run_step_by_step.sh reco output_RAW.root output_AOD.root
#   ./run_step_by_step.sh miniaod output_AOD.root output_MiniAOD.root

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default to the CMSSW release that lives two levels above this script; override with
# CMSSW_BASE_PATH in the environment if you want to point elsewhere.
CMSSW_BASE_PATH="${CMSSW_BASE_PATH:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
CMSSW_TARGET_VERSION="$(basename "${CMSSW_BASE_PATH}")"

# 函数：设置CMSSW环境
setup_cmssw() {
    # Only (re)initialise when the loaded release does not match the target release.
    if [[ "$CMSSW_VERSION" == "$CMSSW_TARGET_VERSION" && "$CMSSW_BASE" == "$CMSSW_BASE_PATH" ]]; then
        return
    fi

    cd "${CMSSW_BASE_PATH}/src"
    source /cvmfs/cms.cern.ch/cmsset_default.sh
    eval `scramv1 runtime -sh`
    cd - > /dev/null

    echo "CMSSW environment set: $CMSSW_VERSION (base: $CMSSW_BASE_PATH)"
}

# 函数：合并HepMC
run_merge() {
    local inputs="$1"
    local output="$2"
    shift 2
    
    # 解析inputs (格式: file1,file2)
    IFS=',' read -ra INPUT_FILES <<< "$inputs"
    if [ ${#INPUT_FILES[@]} -ne 2 ]; then
        echo -e "${RED}Error: merge step requires exactly 2 input files (comma-separated)${NC}"
        exit 1
    fi
    
    local input1="${INPUT_FILES[0]}"
    local input2="${INPUT_FILES[1]}"
    
    # 解析额外参数
    local nevents="-1"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo -e "${YELLOW}=== Merging HepMC Files ===${NC}"
    echo "Input 1: $input1"
    echo "Input 2: $input2"
    echo "Output:  $output"
    echo "Events:  $nevents"
    
    cd "${SCRIPT_DIR}/pythia_shower"
    
    # 编译event_mixer（如果需要）
    if [ ! -f "event_mixer_hepmc2" ]; then
        echo "Compiling event_mixer_hepmc2..."
        make event_mixer_hepmc2
    fi
    
    # 运行合并
    local args="$input1 $input2 $output"
    if [ "$nevents" != "-1" ]; then
        args="$args $nevents"
    fi
    # args="$args --hepmc2"
    
    ./event_mixer_hepmc2 $args
    
    echo -e "${GREEN}Merge completed: $output${NC}"
}

# 函数：GEN-SIM步骤
run_hepmc2gen() {
    local input="$1"
    local output="$2"
    shift 2

    local nevents="-1"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo -e "${YELLOW}=== Converting HepMC2 -> GEN ===${NC}"
    echo "Input:   $input"
    echo "Output:  $output"
    echo "Events:  $nevents"

    setup_cmssw

    cmsRun "${SCRIPT_DIR}/cmssw_configs/hepmc_to_GENSIM.py" \
        inputFiles="file:${input}" \
        outputFile="file:${output}" \
        maxEvents=${nevents}

    echo -e "${GREEN}GEN file created: $output${NC}"
}

run_sim() {
    local input="$1"
    local output="$2"
    shift 2

    local nevents="-1"
    local nthreads="4"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            -t|--threads)
                nthreads="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo -e "${YELLOW}=== Running SIM (GEN -> GEN-SIM) ===${NC}"
    echo "Input:   $input"
    echo "Output:  $output"
    echo "Events:  $nevents"
    echo "Threads: $nthreads"

    setup_cmssw

    # local cfg_file=$(mktemp --suffix=_sim_cfg.py)

    # cmsDriver.py step1 \
    #     --mc --no_exec \
    #     --python_filename "${cfg_file}" \
    #     --eventcontent RAWSIM \
    #     --step SIM \
    #     --datatier GEN-SIM \
    #     --conditions 124X_mcRun3_2022_realistic_v12 \
    #     --beamspot Realistic25ns13p6TeVEarly2022Collision \
    #     --era Run3 \
    #     --geometry DB:Extended \
    #     -n ${nevents} \
    #     --customise Configuration/DataProcessing/Utils.addMonitoring \
    #     --customise_commands "process.g4SimHits.Generator.HepMCProductLabel = 'generatorSmeared'" \
    #     --nThreads ${nthreads} --nStreams ${nthreads} \
    #     --filein "file:${input}" \
    #     --fileout "file:${output}"

    local cfg_file=$(mktemp --suffix=_sim_cfg.py)

    # 1. 运行 cmsDriver 生成基础配置文件
    # 注意：这里去掉了 --customise fix_sim_input...，也不用 custom commands
    cmsDriver.py step1 \
        --mc --no_exec \
        --python_filename "${cfg_file}" \
        --eventcontent RAWSIM \
        --step SIM \
        --datatier GEN-SIM \
        --conditions 124X_mcRun3_2022_realistic_v12 \
        --beamspot Realistic25ns13p6TeVEarly2022Collision \
        --era Run3 \
        --geometry DB:Extended \
        -n ${nevents} \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --nThreads ${nthreads} --nStreams ${nthreads} \
        --filein "file:${input}" \
        --fileout "file:${output}" \
        --customise_commands "del process.LHCTransport; process.g4SimHits.Generator.HepMCProductLabel = cms.InputTag('source','generator','GEN')"

    cmsRun "${cfg_file}"
    # rm -f "${cfg_file}"

    echo -e "${GREEN}SIM completed: $output${NC}"
}

# 函数：RAW步骤 (DIGI+HLT+pileup)
run_raw() {
    local input="$1"
    local output="$2"
    shift 2
    
    local nevents="-1"
    local nthreads="1"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            -t|--threads)
                nthreads="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo -e "${YELLOW}=== Running DIGI-RAW (with pileup) ===${NC}"
    echo "Input:   $input"
    echo "Output:  $output"
    echo "Events:  $nevents"
    
    setup_cmssw
    
    local cfg_file=$(mktemp --suffix=_raw_cfg.py)
    
    cmsDriver.py step2 \
        --mc --no_exec \
        --python_filename "${cfg_file}" \
        --eventcontent PREMIXRAW \
        --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2022v12 \
        --procModifiers premix_stage2,siPixelQualityRawToDigi \
        --datamix PreMix \
        --datatier GEN-SIM-RAW \
        --conditions 124X_mcRun3_2022_realistic_v12 \
        --beamspot Realistic25ns13p6TeVEarly2022Collision \
        --era Run3 \
        --geometry DB:Extended \
        -n ${nevents} \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --nThreads ${nthreads} --nStreams ${nthreads} \
        --pileup_input "filelist:/cvmfs/cms.cern.ch/offcomp-prod/premixPUlist/PREMIX-Run3Summer22DRPremix.txt" \
        --filein "file:${input}" \
        --fileout "file:${output}"
    
    cmsRun "${cfg_file}"
    rm -f "${cfg_file}"
    
    echo -e "${GREEN}RAW completed: $output${NC}"
}

# 函数：RECO步骤
run_reco() {
    local input="$1"
    local output="$2"
    shift 2
    
    local nevents="-1"
    local nthreads="1"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            -t|--threads)
                nthreads="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo -e "${YELLOW}=== Running RECO ===${NC}"
    echo "Input:   $input"
    echo "Output:  $output"
    echo "Events:  $nevents"
    
    setup_cmssw
    
    local cfg_file=$(mktemp --suffix=_reco_cfg.py)
    
    cmsDriver.py step3 \
        --mc --no_exec \
        --python_filename "${cfg_file}" \
        --eventcontent AODSIM \
        --step RAW2DIGI,L1Reco,RECO,RECOSIM \
        --procModifiers siPixelQualityRawToDigi \
        --datatier AODSIM \
        --conditions 124X_mcRun3_2022_realistic_v12 \
        --beamspot Realistic25ns13p6TeVEarly2022Collision \
        --era Run3 \
        --geometry DB:Extended \
        -n ${nevents} \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --nThreads ${nthreads} --nStreams ${nthreads} \
        --filein "file:${input}" \
        --fileout "file:${output}"
    
    cmsRun "${cfg_file}"
    rm -f "${cfg_file}"
    
    echo -e "${GREEN}RECO completed: $output${NC}"
}

# 函数：MiniAOD步骤
run_miniaod() {
    local input="$1"
    local output="$2"
    shift 2
    
    local nevents="-1"
    local nthreads="1"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nevents)
                nevents="$2"
                shift 2
                ;;
            -t|--threads)
                nthreads="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo -e "${YELLOW}=== Running MiniAOD ===${NC}"
    echo "Input:   $input"
    echo "Output:  $output"
    echo "Events:  $nevents"
    
    setup_cmssw
    
    local cfg_file=$(mktemp --suffix=_miniaod_cfg.py)
    
    cmsDriver.py step4 \
        --mc --no_exec \
        --python_filename "${cfg_file}" \
        --eventcontent MINIAODSIM \
        --step PAT \
        --datatier MINIAODSIM \
        --conditions 124X_mcRun3_2022_realistic_v12 \
        --era Run3 \
        --geometry DB:Extended \
        -n ${nevents} \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --nThreads ${nthreads} --nStreams ${nthreads} \
        --filein "file:${input}" \
        --fileout "file:${output}"
    
    cmsRun "${cfg_file}"
    rm -f "${cfg_file}"
    
    echo -e "${GREEN}MiniAOD completed: $output${NC}"
}

    # One-shot chain: GEN-SIM -> RAW -> AOD -> MINIAOD
    run_chain_from_gensim() {
        local gensim_input="$1"
        local prefix="$2"
        shift 2

        if [ ! -f "$gensim_input" ]; then
            echo -e "${RED}Error: input GEN-SIM file not found: $gensim_input${NC}"
            exit 1
        fi

        local nevents="-1"
        local nthreads="1"
        while [[ $# -gt 0 ]]; do
            case $1 in
                -n|--nevents)
                    nevents="$2"
                    shift 2
                    ;;
                -t|--threads)
                    nthreads="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        local raw_out="${prefix}_RAW.root"
        local reco_out="${prefix}_AOD.root"
        local mini_out="${prefix}_MINIAOD.root"

        run_raw "$gensim_input" "$raw_out" -n "$nevents" -t "$nthreads"
        run_reco "$raw_out" "$reco_out" -n "$nevents" -t "$nthreads"
        run_miniaod "$reco_out" "$mini_out" -n "$nevents" -t "$nthreads"

        echo -e "${GREEN}Full chain completed${NC}"
        echo "RAW:     $raw_out"
        echo "AOD:     $reco_out"
        echo "MiniAOD: $mini_out"
    }

# ============ 主程序 ============
usage() {
    echo "Usage: $0 <step> <input> <output> [options]"
    echo ""
    echo "Steps:"
    echo "  merge      - Merge two HepMC files (input: file1,file2)"
    echo "  hepmc2gen  - HepMC2 -> GEN (cmsRun hepmc2gen_cfg.py)"
    echo "  sim        - GEN -> GEN-SIM"
    echo "  raw        - GEN-SIM -> RAW"
    echo "  reco       - RAW -> AOD"
    echo "  miniaod    - AOD -> MiniAOD"
    echo "  chain      - GEN-SIM -> RAW -> AOD -> MINIAOD (output prefix as 2nd arg)"
    echo ""
    echo "Options:"
    echo "  -n, --nevents   Number of events (default: all)"
    echo "  -t, --threads   Number of threads (default: 4 for sim, 1 for others)"
    echo ""
    echo "Examples:"
    echo "  $0 merge input1.hepmc,input2.hepmc merged.hepmc -n 1000"
    echo "  $0 gensim merged.hepmc output_GENSIM.root -n 1000"
    echo "  $0 chain test_mixed_GENSIM.root output/test_mixed -n 500"
    exit 1
}

if [ "$#" -lt 3 ]; then
    usage
fi

STEP="$1"
INPUT="$2"
OUTPUT="$3"
shift 3

case "$STEP" in
    merge)
        run_merge "$INPUT" "$OUTPUT" "$@"
        ;;
    hepmc2gen)
        run_hepmc2gen "$INPUT" "$OUTPUT" "$@"
        ;;
    sim|gensim)
        run_sim "$INPUT" "$OUTPUT" "$@"
        ;;
    raw)
        run_raw "$INPUT" "$OUTPUT" "$@"
        ;;
    reco)
        run_reco "$INPUT" "$OUTPUT" "$@"
        ;;
    miniaod)
        run_miniaod "$INPUT" "$OUTPUT" "$@"
        ;;
    chain)
        run_chain_from_gensim "$INPUT" "$OUTPUT" "$@"
        ;;
    *)
        echo -e "${RED}Error: Unknown step: $STEP${NC}"
        usage
        ;;
esac
