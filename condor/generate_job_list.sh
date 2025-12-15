#!/bin/bash
# generate_job_list.sh - 生成HTCondor作业列表
# 根据LHE文件目录生成对应的block编号列表
#
# 用法: ./generate_job_list.sh [output_file]

LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
OUTPUT_FILE="${1:-job_list.txt}"

echo "Generating job list from: ${LHE_DIR}"
echo "Output file: ${OUTPUT_FILE}"

# 清空或创建输出文件
> "${OUTPUT_FILE}"

# 遍历所有LHE文件，提取block编号
count=0
for lhe_file in "${LHE_DIR}"/MC_Jpsi_block_*.lhe; do
    if [ -f "$lhe_file" ]; then
        # 提取block编号 (例如: 00010, 00020, ...)
        basename=$(basename "$lhe_file")
        block_num=$(echo "$basename" | sed 's/MC_Jpsi_block_\([0-9]*\)\.lhe/\1/')
        echo "$block_num" >> "${OUTPUT_FILE}"
        ((count++))
    fi
done

echo "Generated ${count} jobs"
echo "Job list saved to: ${OUTPUT_FILE}"

# 显示前几个和后几个
echo ""
echo "First 5 blocks:"
head -5 "${OUTPUT_FILE}"
echo "..."
echo "Last 5 blocks:"
tail -5 "${OUTPUT_FILE}"
