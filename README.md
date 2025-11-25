## 项目目标
我是CMS合作组的研究者，现在要在CMSSW框架下产生蒙特卡洛模拟文件。
我希望从已有的LHE文件做两个不同的shower过程，一个就是普通的过程，一个是让事例的出射胶子中shower出一个phi。此后，两种SPS事例一对一混合后成为DPS事例，再逐步经过后处理过程最后得到MINIAOD文件。

我现在已有逐步处理的程序和批量的LHE文件，想要生成HTCondor脚本提交到集群进行批量生产。

## 已有LHE文件
我现在有Helac-Onia2.0产生的单部分子散射过程的LHE文件，是g g > jpsi + g，模拟Run 3的2022年数据,使用 CMSSW_12_4_14_patch3和124X_mcRun3_2022_realistic_v12。

配置命令供参考：
cmsDriver.py \
Configuration/Generator/python/Hadronizer_TuneCP5_13TeV_MLM_5f_max4j_LHE_pythia8_cff.py \
--mc --no_exec \
--python_filename JJY1S_TPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM.py \
--eventcontent RAWSIM --step GEN,SIM --datatier GEN-SIM \
--conditions 124X_mcRun3_2022_realistic_v12 \
--beamspot Realistic25ns13p6TeVEarly2022Collision \
--era Run3 --geometry DB:Extended -n -1 \
--customise Configuration/DataProcessing/Utils.addMonitoring \
--nThreads 8 --nStreams 8 \
--filein file:JJY_TPS_test.lhe \
--fileout file:JJY1S_TPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM.root


from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.Pythia8aMCatNLOSettings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *
from Configuration.Generator.MCTunesRun3ECM13p6TeV.PythiaCP5Settings_cfi import *

process.generator = cms.EDFilter("Pythia8ConcurrentHadronizerFilter",
    PythiaParameters = cms.PSet(
        pythia8CommonSettingsBlock,       # Common Pythia8 settings  
        pythia8CP5SettingsBlock,          # CMS CP5 tune for Pythia8 
        pythia8aMCatNLOSettingsBlock,     # Settings for aMC@NLO matching  
        pythia8PSweightsSettingsBlock,    # Settings for parton shower (PS) weights  

        processParameters = cms.vstring(
            "TimeShower:nPartonsInBorn = -1",     # Number of partons in Born process (-1 = auto)  
            "TimeShower:mMaxGamma = 4",           # Maximum photon energy in final-state QED shower (GeV)  
            "PDF:pSet = 7",                       # Use PDF set ID 7   
            
            # Decay mode settings
            "23:onMode = 0",                      # Disable all decays of Z boson  
            "23:onIfMatch = 13 -13",              # Allow only Z to mu+mu-
            "443:onMode = 0",                     # Disable all decays of Jpsi 
            "443:onIfMatch = 13 -13",             # Allow only Jpsi to mu+mu- decay
            "20443:onMode = 0",                   # Disable all decays of Chi_c1  
            "20443:onIfAny = 443",                # Allow Chi_c1 to Jpsi decay  
            "445:onMode = 0",                     # Disable all decays of Chi_c2  
            "445:onIfAny = 443",                  # Allow Chi_c2 to Jpsi decay  
            "10441:onMode=0",                     # Disablealldecaysofh_c
            "10441:onIfAny = 443",                # Allow h_c to Jpsi decay  
            "100443:onMode = 0",                  # Disable all decays of psi(2S)  
            "100443:onIfAny = 443",               # Allow psi(2S) to Jpsi decay 
            "553:onMode = 0",                     # Disable all decays of Upsilon(1S)
            "553:onIfMatch = 13 -13",             # Allow Upsilon(1S) to mu+mu- decay
            "100553:onMode = 0",                  # Disable all decays of Upsilon(2S)
            "100553:onIfMatch = 13 -13",          # Allow Upsilon(2S) to mu+mu- decay
            "200553:onMode = 0",                  # Disable all decays of Upsilon(3S)
            "200553:onIfMatch = 13 -13",          # Allow Upsilon(3S) to mu+mu- decay
        ),

        parameterSets = cms.vstring(
            "pythia8CommonSettings",      
            "pythia8CP5Settings",         
            "pythia8aMCatNLOSettings",    
            "processParameters",          
            "pythia8PSweightsSettings"    
        )
    ),
    comEnergy = cms.double(13600),                    # Collision energy, needs to be same as the setting in HELAC-Onia.
    maxEventsToPrint = cms.untracked.int32(0),        # Do not print event details  
    pythiaHepMCVerbosity = cms.untracked.bool(False), # Disable HepMC event output verbosity  
    pythiaPylistVerbosity = cms.untracked.int32(0),   # Disable Pythia event listing output  
    filterEfficiency = cms.untracked.double(1.0),     # Set filter efficiency to 1.0 (all events pass)  
)

文件位于/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks

文件名为MC_Jpsi_block_00010.lhe至MC_Jpsi_block_6520.lhe。

## 已有过程程序
已有过程处理程序位于/eos/user/x/xcheng/learn_MC/project_gg_JJg_JJP/pythia_run/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN_Mix

shower程序为：JpsiG_GEN_standard.py和JpsiG_GEN_phi.py

mix程序为：JpsiG_GEN_DPS.py

后面处理的程序为JpsiG_DPS_SIM.py, JpsiG_DPS_DIGI.py, JpsiG_DPS_RECO.py, JpsiG_DPS_MINIAOD.py

## 编写HTCondor脚本要求
condor脚本需在/afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor目录下提交

最后生成的MINIAOD文件保存在/eos/user/x/xcheng/learn_MC的新建的文件夹中

在Condor过程中收集每一步的效率和出现的问题，汇总为一个全部的日志文件和一个总结性的日志文件。

