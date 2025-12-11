# CMS Run3 蒙特卡洛模拟：LHE到GEN完整流程

## 概述

本指南详细说明如何将Helac-Onia2.0生成的J/ψ+g LHE文件通过自定义Pythia8 shower和CMSSW框架处理，最终产生GEN-SIM文件。

**适用配置：**
- CMSSW: `CMSSW_12_4_14_patch3`
- Global Tag: `124X_mcRun3_2022_realistic_v12`
- 对撞能量: 13.6 TeV (Run3 2022)

## 工作流程图

```
LHE文件 (Helac-Onia: gg→J/ψ+g)
    ↓
[Pythia8 Parton Shower] ← ISR/FSR/MPI
    ↓
Parton Event (暂不强子化)
    ↓
[多次Hadronization试验] ← 重复直到产生φ
    ↓
HepMC文件 (带pT>3的φ介子)
    ↓
[CMSSW处理] ← CMSSW_12_4_14_patch3
    ↓
GEN-SIM ROOT文件
```

**关键技术：Hadron Level Standalone模式**
- 将parton shower和hadronization分离
- 对同一个parton事例可以多次hadronization
- 利用`forceHadronLevel(true)`实现trial机制
- 大幅提高带filter的shower效率

## 环境准备

### 1. 安装依赖

确保已安装：
- Pythia8 (推荐8.309或更新版本)
- HepMC3
- CMSSW_12_4_14_patch3

### 2. 设置CMSSW环境

```bash
cd /your/work/area
cmsrel CMSSW_12_4_14_patch3
cd CMSSW_12_4_14_patch3/src
cmsenv
```

### 3. 准备工作目录

```bash
mkdir -p MC_Production
cd MC_Production

# 创建目录结构
mkdir -p pythia_shower
mkdir -p cmssw_configs
mkdir -p output
```

## 文件准备

将以下文件放入对应目录：

**pythia_shower/**
- `shower_normal.cc` - 普通shower程序（完整shower+hadronization）
- `shower_phi_hadron.cc` - Hadron Level Standalone模式（推荐）
- `shower_phi_advanced.cc` - 高级版本，支持配置文件和更多选项
- `pythia_phi_tune.cmnd` - Pythia8参数配置文件
- `Makefile` - 编译脚本

**cmssw_configs/**
- `hepmc_to_gen_cfg.py` - 普通CMSSW配置
- `hepmc_to_gen_phi_cfg.py` - 带φ filter的CMSSW配置

**根目录：**
- `run_workflow.sh` - 自动化流程脚本

## 详细操作步骤

### 方法一：使用自动化脚本（推荐）

#### 1. 修改配置

编辑 `run_workflow.sh`，修改以下路径：

```bash
PYTHIA8_DIR="/path/to/your/pythia8"
HEPMC3_DIR="/path/to/your/hepmc3"
CMSSW_BASE="/path/to/CMSSW_12_4_14_patch3"
```

#### 2. 赋予执行权限

```bash
chmod +x run_workflow.sh
```

#### 3. 运行流程

**普通workflow（无特殊filter）：**
```bash
./run_workflow.sh your_input.lhe normal
```

**带φ介子filter的workflow：**
```bash
./run_workflow.sh your_input.lhe phi
```

脚本会自动完成：
1. 编译Pythia8程序
2. 运行shower
3. 设置CMSSW环境
4. 运行CMSSW生成GEN文件
5. 验证输出

---

### 方法二：手动逐步执行

#### 第一步：编译Pythia8程序

```bash
cd pythia_shower

# 修改Makefile中的路径
vim Makefile
# 设置 PYTHIA8 和 HEPMC3 的路径

# 编译
make clean
make
```

这会生成可执行文件：
- `shower_normal` - 标准shower
- `shower_phi_hadron` - Hadron Level Standalone（基础版）
- `shower_phi_advanced` - 高级版本

#### 第二步：运行Pythia8 Shower

**选项A：普通shower**

```bash
./shower_normal input.lhe output_normal.hepmc [nEvents]

# 示例：处理所有事例
./shower_normal ../my_jpsi_lhe.lhe ../output/output_normal.hepmc

# 示例：只处理前10000个事例
./shower_normal ../my_jpsi_lhe.lhe ../output/output_normal.hepmc 10000
```

**选项B：Hadron Level Standalone模式（推荐用于φ介子）**

这是效率更高的方法，基于Pythia8的Hadron Level Standalone功能：

**基础版本：**
```bash
./shower_phi_hadron input.lhe output_phi.hepmc [nEvents] [maxRetry] [ptMin] [etaMax]

# 示例：产生10000个带φ(pT>3)的事例
./shower_phi_hadron ../my_jpsi_lhe.lhe ../output/output_phi.hepmc 10000 1000 3.0 2.5
```

**高级版本（推荐）：**
```bash
./shower_phi_advanced input.lhe output.hepmc [options]

# 使用配置文件
./shower_phi_advanced input.lhe output.hepmc -n 10000 -r 1000 -pt 3.0 -eta 2.5 \
    -config pythia_phi_tune.cmnd -verbose

# 完整选项说明：
# -n <N>         : 目标事例数
# -r <N>         : 每个parton事例最多hadronization次数
# -pt <min>      : φ的最小pT (GeV)
# -eta <max>     : φ的最大|η|
# -config <file> : Pythia8配置文件
# -verbose       : 详细输出（显示每个φ的信息）
# -seed <N>      : 随机数种子
```

**工作原理：**
1. **Parton Level处理**：对LHE进行一次标准的ISR/FSR/MPI shower
2. **保存parton事例**：不进行强子化，保存parton配置
3. **多次Hadronization**：对同一个parton事例反复强子化，直到产生符合条件的φ
4. **使用forceHadronLevel(true)**：启用trial模式，允许重复hadronization

**优势：**
- 效率更高：不需要重复整个shower过程
- 更准确：每个parton事例只shower一次，保证一致性
- 符合Pythia8官方推荐做法

**重要说明：**
- Hadron Level Standalone模式效率显著高于完整重复shower
- 典型效率：0.5-2%（取决于运动学配置和参数调整）
- 程序会实时输出效率和速率信息
- 使用配置文件可以fine-tune参数而无需重新编译

#### 第三步：设置CMSSW环境

```bash
cd /path/to/CMSSW_12_4_14_patch3/src
cmsenv
cd -
```

验证环境：
```bash
echo $CMSSW_VERSION
# 应该输出: CMSSW_12_4_14_patch3
```

#### 第四步：修改CMSSW配置文件

根据您的需求选择配置文件并修改：

**对于普通workflow：**
```bash
cd cmssw_configs
cp hepmc_to_gen_cfg.py my_gen_cfg.py
vim my_gen_cfg.py
```

**对于φ workflow：**
```bash
cp hepmc_to_gen_phi_cfg.py my_gen_phi_cfg.py
vim my_gen_phi_cfg.py
```

修改输入输出文件路径：
```python
# 修改输入HepMC文件
fileNames = cms.untracked.vstring('file:/path/to/output_normal.hepmc')

# 修改输出ROOT文件
fileName = cms.untracked.string('file:/path/to/output_GEN.root')
```

#### 第五步：运行CMSSW

```bash
cmsRun my_gen_cfg.py
```

或者使用批处理：
```bash
cmsRun my_gen_cfg.py > gen_production.log 2>&1 &
```

#### 第六步：验证输出

```bash
# 查看文件信息
edmFileUtil -f output_GEN.root

# 查看事例数
edmEventSize -v output_GEN.root

# 使用edmDumpEventContent查看内容
edmDumpEventContent output_GEN.root
```

## 高级选项

### 调整Pythia8参数

**方法1：使用配置文件（推荐）**

创建或编辑 `pythia_phi_tune.cmnd`：

```
! 增强φ介子产生
StringFlav:probStoUD = 0.35      ! s夸克概率（默认0.217）
StringFlav:mesonSvector = 0.70   ! φ增强因子（默认0.55）

! 增加强子化横动量
StringPT:sigma = 0.40            ! 固有pT宽度（默认0.335）
StringPT:enhancedFraction = 0.02
StringPT:enhancedWidth = 2.5

! 可以测试的其他参数
! StringFlav:probQQtoQ = 0.10
! StringZ:aLund = 0.70
! StringZ:bLund = 1.00
```

然后运行：
```bash
./shower_phi_advanced input.lhe output.hepmc -config pythia_phi_tune.cmnd -n 10000
```

**方法2：修改源代码**

如果使用基础版本，编辑 `shower_phi_hadron.cc`：

```cpp
// 在hadron level Pythia配置部分
pythiaHadron.readString("StringFlav:probStoUD = 0.40");  // 进一步提高
pythiaHadron.readString("StringFlav:mesonSvector = 0.75");
```

重新编译：
```bash
make clean && make
```

### 修改Filter条件

**在Pythia层面（推荐用配置文件）：**

编辑 `shower_phi_advanced.cc` 或使用命令行参数：

```bash
# 修改pT和η要求
./shower_phi_advanced input.lhe output.hepmc -pt 2.5 -eta 2.0

# 或修改ParticleFilter类来添加更复杂的条件
```

如需更复杂的filter（例如同时要求J/ψ和φ），修改源码中的 `ParticleFilter` 类或添加多个filter。

**在CMSSW层面（Python）：**

修改 `hepmc_to_gen_phi_cfg.py` 中的filter：

```python
process.phiFilterSimple = cms.EDFilter("PythiaFilter",
    MaxEta = cms.untracked.double(2.5),  # 修改η范围
    MinEta = cms.untracked.double(-2.5),
    MinPt = cms.untracked.double(3.0),   # 修改pT阈值
    ParticleID = cms.untracked.int32(333)
)
```

### 并行处理多个LHE文件

创建批处理脚本：

```bash
#!/bin/bash
# batch_process.sh

LHE_FILES=(
    "file1.lhe"
    "file2.lhe"
    "file3.lhe"
)

for lhe in "${LHE_FILES[@]}"; do
    ./run_workflow.sh "$lhe" phi &
done

wait
echo "All jobs completed!"
```

## 常见问题排查

### 问题1：Pythia8编译失败

**错误：** `fatal error: Pythia8/Pythia.h: No such file or directory`

**解决：**
```bash
# 检查Pythia8路径
export PYTHIA8DATA=/path/to/pythia8/share/Pythia8/xmldoc
export LD_LIBRARY_PATH=/path/to/pythia8/lib:$LD_LIBRARY_PATH

# 在Makefile中正确设置路径
```

### 问题2：Hadronization效率极低

**现象：** 长时间运行但几乎不产生符合条件的事例

**诊断步骤：**
1. 先用verbose模式检查parton事例：
```bash
./shower_phi_advanced input.lhe test.hepmc -n 10 -r 10 -verbose
```

2. 检查LHE文件中胶子的动量分布

3. 尝试降低pT阈值测试：
```bash
./shower_phi_advanced input.lhe test.hepmc -n 100 -pt 1.0
```

**解决方案：**
1. 调整Pythia参数（使用配置文件）：
```
StringFlav:probStoUD = 0.40      ! 显著提高s夸克概率
StringFlav:mesonSvector = 0.80   ! 进一步增强φ
StringPT:sigma = 0.40            ! 增加横动量
```

2. 增加最大重试次数：
```bash
./shower_phi_hadron input.lhe output.hepmc 10000 5000
```

3. 检查是否需要调整初始状态：可能LHE文件的运动学配置本身就不利于产生高pT的φ

### 问题3：CMSSW运行时内存不足

**错误：** `std::bad_alloc`

**解决：**
```python
# 在配置文件中添加
process.options = cms.untracked.PSet(
    wantSummary = cms.untracked.bool(True),
    numberOfThreads = cms.untracked.uint32(1),
    numberOfStreams = cms.untracked.uint32(0)
)
```

### 问题4：GlobalTag错误

**错误：** `GlobalTag not found`

**解决：**
```bash
# 检查CMSSW环境
cmsenv

# 或手动设置
export CMS_PATH=/cvmfs/cms.cern.ch
```

## 性能优化

### 1. Pythia8 Shower优化

**使用Hadron Level Standalone模式（关键！）：**
- 比完整重复shower效率提高10-100倍
- 对同一parton事例多次hadronization
- 参考：https://pythia.org/latest-manual/HadronLevelStandalone.html

**参数调优：**
```bash
# 使用配置文件快速测试不同参数组合
./shower_phi_advanced input.lhe test.hepmc -n 1000 -config tune1.cmnd
./shower_phi_advanced input.lhe test.hepmc -n 1000 -config tune2.cmnd
# 比较效率，选择最优配置
```

**并行处理：**
```bash
# 将LHE文件分割成多个小文件
# 并行运行多个shower job
for i in {1..10}; do
    ./shower_phi_advanced input_${i}.lhe output_${i}.hepmc -n 1000 &
done
wait
```

### 2. CMSSW处理优化

```python
# 启用多线程（如果硬件支持）
process.options.numberOfThreads = cms.untracked.uint32(4)
process.options.numberOfStreams = cms.untracked.uint32(0)
```

### 3. 存储优化

```python
# 只保留必要的分支
process.RAWSIMoutput.outputCommands = cms.untracked.vstring(
    'drop *',
    'keep *_genParticles_*_*',
    'keep GenEventInfoProduct_*_*_*',
    'keep GenRunInfoProduct_*_*_*'
)
```

## 输出文件说明

### HepMC文件
- 格式：HepMC3
- 内容：shower后的完整粒子信息
- 大小：约1-10 MB/1000事例

### GEN ROOT文件
- 格式：EDM ROOT
- 内容：GenParticle集合 + Event info
- 大小：约10-50 MB/1000事例
- 可用工具：ROOT, edmDumpEventContent

## 下一步

GEN文件生成后，您可以继续：
1. SIM步骤：`cmsDriver.py --step SIM`
2. DIGI步骤：`cmsDriver.py --step DIGI`
3. RECO步骤：`cmsDriver.py --step RECO`

或使用完整的cmsDriver命令一次性完成所有步骤。

## 参考资料

- [Pythia8 Manual](https://pythia.org/)
- **[Pythia8 Hadron Level Standalone](https://pythia.org/latest-manual/HadronLevelStandalone.html)** ⭐
- **[Pythia8 Example main261](https://pythia.org/latest-manual/examples/main261.html)** ⭐
- [CMS Simulation Documentation](https://twiki.cern.ch/twiki/bin/view/CMSPublic/WorkBookGeneration)
- [HepMC3 Documentation](https://hepmc.web.cern.ch/hepmc/)
- [CMSSW Reference Manual](https://cmssdt.cern.ch/lxr/)
- [CMS Generator Physics](https://twiki.cern.ch/twiki/bin/view/CMS/GeneratorMain)

## 联系与支持

如遇到问题，请查阅：
- CMS HyperNews: hn-cms-generators
- CMS Talk: generators分类
- CMSSW GitHub Issues

---

**版本信息**
- 文档版本: 1.0
- 更新日期: 2024-12
- 适用CMSSW: 12_4_14_patch3
- 作者: CMS合作组研究者