#!/bin/bash
# generate_job_list.sh - 生成HTCondor作业列表
# 生成成对的LHE块编号，确保normal和phi shower使用不同的LHE文件
#
# 策略: 将LHE文件分成两组（奇数和偶数），
#       奇数组用于normal shower，偶数组用于phi shower
#       这样可以最大化利用所有LHE文件
#
# 用法: ./generate_job_list.sh [output_file]

# LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
LHE_DIR="/eos/user/x/xcheng/learn_MC/ggJpsig_Jpsi_pt6_g_pt4"
OUTPUT_FILE="${1:-job_list.txt}"

echo "Generating job list from: ${LHE_DIR}"
echo "Output file: ${OUTPUT_FILE}"
echo ""
echo "Strategy: Pair LHE files for normal and phi showers"
echo "          (using different files to avoid correlation)"

# 收集并数值排序block编号（使用find+sed比逐文件循环快）
mapfile -t sorted_blocks < <(
    find "${LHE_DIR}" -maxdepth 1 -name 'MC_Jpsi_block_*.lhe' -printf '%f\n' \
    | sed -E 's/MC_Jpsi_block_([0-9]+)\.lhe/\1/' \
    | sort -n
)

total_blocks=${#sorted_blocks[@]}
echo "Total LHE files found: ${total_blocks}"

# 清空或创建输出文件
> "${OUTPUT_FILE}"

# 将blocks分成两组配对
# 方法: 前半部分用于normal，后半部分用于phi
half=$((total_blocks / 2))

count=0
for ((i=0; i<half; i++)); do
    normal_block="${sorted_blocks[$i]}"
    phi_block="${sorted_blocks[$((i + half))]}"
    echo "${normal_block} ${phi_block}" >> "${OUTPUT_FILE}"
    ((count++))
done

echo ""
echo "Generated ${count} job pairs"
echo "Job list saved to: ${OUTPUT_FILE}"
echo ""
echo "Format: <lhe_block_normal> <lhe_block_phi>"

# 显示前几个和后几个
echo ""
echo "First 5 pairs:"
head -5 "${OUTPUT_FILE}"
echo "..."
echo "Last 5 pairs:"
tail -5 "${OUTPUT_FILE}"
