#!/bin/bash
# analyze_efficiency.sh - 分析MC生产各步骤的效率
#
# 功能:
# 1. 从Condor日志中提取各步骤的事例统计信息
# 2. 计算每步的效率（成功率）
# 3. 生成汇总报告
#
# 用法: ./analyze_efficiency.sh [log_dir]
#       默认日志目录: ./logs

# ============== 参数和配置 ==============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${1:-${SCRIPT_DIR}/logs}"
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"

# 统计变量
declare -A step_success
declare -A step_failed
declare -A step_events_in
declare -A step_events_out

# 初始化
for step in LHE SHOWER_NORMAL SHOWER_PHI MIX GENSIM RAW AOD MINIAOD; do
    step_success[$step]=0
    step_failed[$step]=0
    step_events_in[$step]=0
    step_events_out[$step]=0
done

echo "=========================================="
echo "  JJP DPS MC 生产效率分析"
echo "=========================================="
echo "分析时间: $(date)"
echo "日志目录: ${LOG_DIR}"
echo "输出目录: ${OUTPUT_BASE}"
echo ""

# ============== 检查输入 ==============
if [ ! -d "${LOG_DIR}" ]; then
    echo "警告: 日志目录不存在: ${LOG_DIR}"
    echo "请先运行一些作业再分析效率"
fi

# ============== 统计LHE输入 ==============
echo "=========================================="
echo "Step 0: LHE 输入文件"
echo "=========================================="
n_lhe=$(ls ${LHE_DIR}/MC_Jpsi_block_*.lhe 2>/dev/null | wc -l)
echo "LHE文件总数: ${n_lhe}"
step_events_in[LHE]=${n_lhe}
step_events_out[LHE]=${n_lhe}
step_success[LHE]=${n_lhe}

# ============== 分析Condor日志 ==============
echo ""
echo "=========================================="
echo "分析Condor作业日志..."
echo "=========================================="

# 统计从日志中提取的信息
n_jobs_total=0
n_jobs_completed=0
n_jobs_failed=0

if [ -d "${LOG_DIR}" ]; then
    shopt -s nullglob
    for logfile in "${LOG_DIR}"/*.stdout; do
        [ -f "$logfile" ] || continue
        n_jobs_total=$((n_jobs_total + 1))
        
        # 检查作业是否成功完成
        if grep -q "Job Completed Successfully" "$logfile" 2>/dev/null; then
            n_jobs_completed=$((n_jobs_completed + 1))
            
            # 提取各步骤的统计信息
            # Normal shower
            if grep -q "Normal shower completed" "$logfile"; then
                step_success[SHOWER_NORMAL]=$((${step_success[SHOWER_NORMAL]} + 1))
            fi
            
            # Phi shower (提取生成的事例数)
            if grep -q "Phi-enriched shower completed" "$logfile"; then
                step_success[SHOWER_PHI]=$((${step_success[SHOWER_PHI]} + 1))
            fi
            
            # Mixing (提取混合的事例数)
            if grep -q "Event mixing completed" "$logfile"; then
                step_success[MIX]=$((${step_success[MIX]} + 1))
                # 尝试提取DPS事例数
                n_dps=$(grep -oP "Total DPS events created: \K\d+" "$logfile" 2>/dev/null | tail -1)
                if [ -n "$n_dps" ]; then
                    step_events_out[MIX]=$((${step_events_out[MIX]} + n_dps))
                fi
            fi
            
            # GEN-SIM
            if grep -q "GEN-SIM step completed" "$logfile"; then
                step_success[GENSIM]=$((${step_success[GENSIM]} + 1))
            fi
            
            # RAW
            if grep -q "RAW step completed" "$logfile"; then
                step_success[RAW]=$((${step_success[RAW]} + 1))
            fi
            
            # AOD
            if grep -q "RECO step completed" "$logfile"; then
                step_success[AOD]=$((${step_success[AOD]} + 1))
            fi
            
            # MiniAOD
            if grep -q "MiniAOD step completed" "$logfile"; then
                step_success[MINIAOD]=$((${step_success[MINIAOD]} + 1))
            fi
            
        else
            n_jobs_failed=$((n_jobs_failed + 1))
            
            # 找出失败的步骤
            if ! grep -q "Normal shower completed" "$logfile" 2>/dev/null; then
                step_failed[SHOWER_NORMAL]=$((${step_failed[SHOWER_NORMAL]} + 1))
            elif ! grep -q "Phi-enriched shower completed" "$logfile" 2>/dev/null; then
                step_failed[SHOWER_PHI]=$((${step_failed[SHOWER_PHI]} + 1))
            elif ! grep -q "Event mixing completed" "$logfile" 2>/dev/null; then
                step_failed[MIX]=$((${step_failed[MIX]} + 1))
            elif ! grep -q "GEN-SIM step completed" "$logfile" 2>/dev/null; then
                step_failed[GENSIM]=$((${step_failed[GENSIM]} + 1))
            elif ! grep -q "RAW step completed" "$logfile" 2>/dev/null; then
                step_failed[RAW]=$((${step_failed[RAW]} + 1))
            elif ! grep -q "RECO step completed" "$logfile" 2>/dev/null; then
                step_failed[AOD]=$((${step_failed[AOD]} + 1))
            elif ! grep -q "MiniAOD step completed" "$logfile" 2>/dev/null; then
                step_failed[MINIAOD]=$((${step_failed[MINIAOD]} + 1))
            fi
        fi
    done
fi

echo "作业统计:"
echo "  总作业数:   ${n_jobs_total}"
echo "  完成:       ${n_jobs_completed}"
echo "  失败:       ${n_jobs_failed}"
if [ $n_jobs_total -gt 0 ]; then
    pct=$(echo "scale=1; 100 * $n_jobs_completed / $n_jobs_total" | bc)
    echo "  成功率:     ${pct}%"
fi

# ============== 统计输出文件 ==============
echo ""
echo "=========================================="
echo "统计输出文件..."
echo "=========================================="

# 只统计MINIAOD (其他中间文件不再保存)
n_miniaod=0
if [ -d "${OUTPUT_BASE}/MINIAOD" ]; then
    n_miniaod=$(ls ${OUTPUT_BASE}/MINIAOD/*.root 2>/dev/null | wc -l)
fi

echo "输出文件统计:"
echo "  MINIAOD:    ${n_miniaod} 文件"

# ============== 从单个日志提取详细效率信息 ==============
echo ""
echo "=========================================="
echo "Phi Shower 效率分析 (从日志提取)"
echo "=========================================="

total_lhe_events=0
total_normal_events=0
total_phi_events=0
total_phi_success=0
total_dps_events=0

if [ -d "${LOG_DIR}" ]; then
    shopt -s nullglob
    for logfile in "${LOG_DIR}"/*.stdout; do
        [ -f "$logfile" ] || continue
        
        # 提取normal shower的统计
        normal_processed=$(grep -oP "Total events processed:\s*\K\d+" "$logfile" 2>/dev/null | head -1)
        
        # 提取phi shower的统计 (Total LHE events processed)
        phi_processed=$(grep -oP "Total LHE events processed:\s*\K\d+" "$logfile" 2>/dev/null | tail -1)
        
        # 提取phi成功事例数 (Events written / Output events)
        phi_success=$(grep -oP "Output events:\s*\K\d+" "$logfile" 2>/dev/null | tail -1)
        
        # 从mixer提取统计
        normal_read=$(grep -oP "Normal events read:\s*\K\d+" "$logfile" 2>/dev/null | tail -1)
        phi_read=$(grep -oP "Phi events read:\s*\K\d+" "$logfile" 2>/dev/null | tail -1)
        dps_created=$(grep -oP "Total DPS events created:\s*\K\d+" "$logfile" 2>/dev/null | tail -1)
        
        if [ -n "$normal_processed" ]; then
            total_normal_events=$((total_normal_events + normal_processed))
        fi
        if [ -n "$phi_success" ]; then
            total_phi_success=$((total_phi_success + phi_success))
        fi
        if [ -n "$phi_read" ]; then
            total_phi_events=$((total_phi_events + phi_read))
        fi
        if [ -n "$dps_created" ]; then
            total_dps_events=$((total_dps_events + dps_created))
        fi
    done
fi

if [ $total_phi_success -gt 0 ] || [ $total_normal_events -gt 0 ]; then
    echo "事例统计 (从已完成的作业):"
    echo "  LHE 输入事例总数:         ${total_normal_events}"
    echo "  Normal shower 输出事例:   ${total_normal_events}"
    echo "  Phi shower 成功事例:      ${total_phi_success}"
    echo "  DPS 混合事例数:           ${total_dps_events}"
    
    if [ $total_normal_events -gt 0 ] && [ $total_phi_success -gt 0 ]; then
        phi_eff=$(echo "scale=2; 100 * $total_phi_success / $total_normal_events" | bc)
        echo ""
        echo "  Phi shower 效率 (pT>3):   ${phi_eff}%"
        echo "  (每 ${total_normal_events} 个LHE事例产生 ${total_phi_success} 个phi事例)"
    fi
else
    echo "暂无已完成作业的详细统计数据"
fi

# ============== 生成汇总表格 ==============
echo ""
echo "=========================================="
echo "各步骤效率汇总"
echo "=========================================="

printf "%-15s %10s %10s %10s\n" "步骤" "成功" "失败" "成功率"
printf "%-15s %10s %10s %10s\n" "---------------" "----------" "----------" "----------"

for step in SHOWER_NORMAL SHOWER_PHI MIX GENSIM RAW AOD MINIAOD; do
    succ=${step_success[$step]}
    fail=${step_failed[$step]}
    total=$((succ + fail))
    if [ $total -gt 0 ]; then
        rate=$(echo "scale=1; 100 * $succ / $total" | bc)
        printf "%-15s %10d %10d %9.1f%%\n" "$step" "$succ" "$fail" "$rate"
    else
        printf "%-15s %10d %10d %10s\n" "$step" "$succ" "$fail" "N/A"
    fi
done

# ============== 预计总产量 ==============
echo ""
echo "=========================================="
echo "预计产量"
echo "=========================================="

if [ $n_jobs_completed -gt 0 ] && [ $total_dps_events -gt 0 ]; then
    avg_events_per_job=$(echo "scale=0; $total_dps_events / $n_jobs_completed" | bc)
    echo "平均每个作业产出事例数: ${avg_events_per_job}"
    
    # 假设所有LHE文件都能成功处理
    estimated_total=$(echo "scale=0; $n_lhe * $avg_events_per_job" | bc)
    echo "预计总产量 (基于 ${n_lhe} 个LHE文件): ~${estimated_total} DPS事例"
    
    # 考虑phi shower的效率
    if [ $total_normal_events -gt 0 ] && [ $total_phi_success -gt 0 ]; then
        phi_eff_frac=$(echo "scale=4; $total_phi_success / $total_normal_events" | bc)
        echo "Phi shower选择效率 (pT>3): $(echo "scale=1; $phi_eff_frac * 100" | bc)%"
    fi
fi

# ============== 失败作业列表 ==============
if [ $n_jobs_failed -gt 0 ]; then
    echo ""
    echo "=========================================="
    echo "失败作业列表 (前10个)"
    echo "=========================================="
    
    count=0
    shopt -s nullglob
    for logfile in "${LOG_DIR}"/*.stdout; do
        [ -f "$logfile" ] || continue
        if ! grep -q "Job Completed Successfully" "$logfile" 2>/dev/null; then
            basename "$logfile"
            # 显示最后几行错误信息
            tail -5 "$logfile" 2>/dev/null | head -3
            echo "---"
            count=$((count + 1))
            [ $count -ge 10 ] && break
        fi
    done
fi

# ============== 保存报告 ==============
REPORT_FILE="${SCRIPT_DIR}/efficiency_report_$(date +%Y%m%d_%H%M%S).txt"
echo ""
echo "=========================================="
echo "报告已保存"
echo "=========================================="

# 重新运行并保存到文件
{
    echo "JJP DPS MC 生产效率报告"
    echo "生成时间: $(date)"
    echo ""
    echo "LHE输入文件数: ${n_lhe}"
    echo "作业总数: ${n_jobs_total}"
    echo "完成作业: ${n_jobs_completed}"
    echo "失败作业: ${n_jobs_failed}"
    echo ""
    echo "事例统计:"
    echo "  LHE输入事例: ${total_normal_events}"
    echo "  Phi shower成功事例: ${total_phi_success}"
    echo "  DPS混合事例: ${total_dps_events}"
    echo ""
    echo "输出文件:"
    echo "  MINIAOD: ${n_miniaod}"
} > "${REPORT_FILE}"

echo "报告保存至: ${REPORT_FILE}"
echo ""
echo "=========================================="
echo "分析完成"
echo "=========================================="
