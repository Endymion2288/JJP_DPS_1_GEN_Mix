# Auto generated configuration file
# using: 
# Revision: 1.19 
# Source: /local/reps/CMSSW/CMSSW/Configuration/Applications/python/ConfigBuilder.py,v 
# with command line options: --mc --no_exec --python_filename JJY1S_Y1S-Octet_SPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_SIM.py --eventcontent RAWSIM --step GEN,SIM --datatier GEN-SIM --conditions 124X_mcRun3_2022_realistic_v12 --beamspot Realistic25ns13p6TeVEarly2022Collision --era Run3 --geometry DB:Extended -n -1 --customise Configuration/DataProcessing/Utils.addMonitoring --nThreads 8 --nStreams 8 --filein file:test_Jpsi1Jpsi1Y8.dat --fileout file:JJY1S_Y1S-Octet_SPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM.root
import FWCore.ParameterSet.Config as cms

from Configuration.Eras.Era_Run3_cff import Run3

process = cms.Process('SIM',Run3)

# import of standard configurations
process.load('Configuration.StandardSequences.Services_cff')
process.load('SimGeneral.HepPDTESSource.pythiapdt_cfi')
process.load('FWCore.MessageService.MessageLogger_cfi')
process.load('Configuration.EventContent.EventContent_cff')
process.load('SimGeneral.MixingModule.mixNoPU_cfi')
process.load('Configuration.StandardSequences.GeometryRecoDB_cff')
process.load('Configuration.StandardSequences.GeometrySimDB_cff')
process.load('Configuration.StandardSequences.MagneticField_cff')
process.load('Configuration.StandardSequences.Generator_cff')
process.load('GeneratorInterface.Core.genFilterSummary_cff')
process.load('Configuration.StandardSequences.SimIdeal_cff')
process.load('Configuration.StandardSequences.EndOfProcess_cff')
process.load('Configuration.StandardSequences.FrontierConditions_GlobalTag_cff')

process.maxEvents = cms.untracked.PSet(
    input = cms.untracked.int32(-1),
    output = cms.optional.untracked.allowed(cms.int32,cms.PSet)
)

# Input source
process.source = cms.Source("MCFileSource",
    fileNames = cms.untracked.vstring('file:/eos/user/x/xcheng/learn_MC/loopmix_pythia/CMSSW_14_0_18/src/JJP_DPS_1_GENMix/output/test_mixed.hepmc'),
    firstLuminosityBlockForEachRun = cms.untracked.VLuminosityBlockID([]),
    # fileNames = cms.untracked.vstring('file:/tmp/'+os.environ['USER']+'/hepmc10K.dat'),
)

process.options = cms.untracked.PSet(
    IgnoreCompletely = cms.untracked.vstring(),
    Rethrow = cms.untracked.vstring(),
    accelerators = cms.untracked.vstring('*'),
    allowUnscheduled = cms.obsolete.untracked.bool,
    canDeleteEarly = cms.untracked.vstring(),
    deleteNonConsumedUnscheduledModules = cms.untracked.bool(True),
    dumpOptions = cms.untracked.bool(False),
    emptyRunLumiMode = cms.obsolete.untracked.string,
    eventSetup = cms.untracked.PSet(
        forceNumberOfConcurrentIOVs = cms.untracked.PSet(
            allowAnyLabel_=cms.required.untracked.uint32
        ),
        numberOfConcurrentIOVs = cms.untracked.uint32(0)
    ),
    fileMode = cms.untracked.string('FULLMERGE'),
    forceEventSetupCacheClearOnNewRun = cms.untracked.bool(False),
    makeTriggerResults = cms.obsolete.untracked.bool,
    numberOfConcurrentLuminosityBlocks = cms.untracked.uint32(0),
    numberOfConcurrentRuns = cms.untracked.uint32(1),
    numberOfStreams = cms.untracked.uint32(0),
    numberOfThreads = cms.untracked.uint32(1),
    printDependencies = cms.untracked.bool(False),
    sizeOfStackForThreadsInKB = cms.optional.untracked.uint32,
    throwIfIllegalParameter = cms.untracked.bool(True),
    wantSummary = cms.untracked.bool(False)
)

# Production Info
process.configurationMetadata = cms.untracked.PSet(
    annotation = cms.untracked.string('HepMC from Pythia8 full shower, nevts=-1'),
    name = cms.untracked.string('Applications'),
    version = cms.untracked.string('$Revision: 1.19 $')
)

# Output definition

process.RAWSIMoutput = cms.OutputModule("PoolOutputModule",
    SelectEvents = cms.untracked.PSet(
        SelectEvents = cms.vstring('generation_step')
    ),
    compressionAlgorithm = cms.untracked.string('LZMA'),
    compressionLevel = cms.untracked.int32(1),
    dataset = cms.untracked.PSet(
        dataTier = cms.untracked.string('GEN-SIM'),
        filterName = cms.untracked.string('')
    ),
    eventAutoFlushCompressedSize = cms.untracked.int32(20971520),
    fileName = cms.untracked.string('file:/eos/user/x/xcheng/learn_MC/loopmix_pythia/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN2MINIAOD/output/test_mixed_GENSIM.root'),
    outputCommands = process.RAWSIMEventContent.outputCommands,
    splitLevel = cms.untracked.int32(0)
)

# Additional output definition

# Other statements
if hasattr(process, "XMLFromDBSource"): process.XMLFromDBSource.label="Extended"
if hasattr(process, "DDDetectorESProducerFromDB"): process.DDDetectorESProducerFromDB.label="Extended"
process.genstepfilter.triggerConditions=cms.vstring("generation_step")
from Configuration.AlCa.GlobalTag import GlobalTag
process.GlobalTag = GlobalTag(process.GlobalTag, '124X_mcRun3_2022_realistic_v12', '')

# Path and EndPath definitions
process.generation_step = cms.Path(process.pgen)
process.simulation_step = cms.Path(process.psim)
process.genfiltersummary_step = cms.EndPath(process.genFilterSummary)
process.endjob_step = cms.EndPath(process.endOfProcess)
process.RAWSIMoutput_step = cms.EndPath(process.RAWSIMoutput)

# Schedule definition
process.schedule = cms.Schedule(process.generation_step,process.genfiltersummary_step,process.simulation_step,process.endjob_step,process.RAWSIMoutput_step)
from PhysicsTools.PatAlgos.tools.helpers import associatePatAlgosToolsTask
associatePatAlgosToolsTask(process)

#Setup FWK for multithreaded
process.options.numberOfThreads = 8
process.options.numberOfStreams = 8

# customisation of the process.

# Automatic addition of the customisation function from Configuration.DataProcessing.Utils
from Configuration.DataProcessing.Utils import addMonitoring
from IOMC.EventVertexGenerators.VtxSmearedParameters_cfi import Realistic25ns13p6TeVEarly2022CollisionVtxSmearingParameters, VtxSmearedCommon

def addVertexSmeared(process, seed=1243987, engine='TRandom3'):
    # Generator interface
    process.genParticles.src = cms.InputTag("source","generator")
    VtxSmearedCommon.src = cms.InputTag("source","generator")
    RandCommonParam = cms.PSet(
        initialSeed = cms.untracked.uint32(seed),
        engineName = cms.untracked.string(engine),
    )
    process.RandomNumberGeneratorService.VtxSmeared = RandCommonParam
    process.RandomNumberGeneratorService.generatorSmeared = RandCommonParam
    process.VtxSmeared = cms.EDProducer("BetafuncEvtVtxGenerator",
        Realistic25ns13p6TeVEarly2022CollisionVtxSmearingParameters,
        VtxSmearedCommon
    )
    process.generatorSmeared = process.VtxSmeared.clone()
    return process


#call to customisation function addMonitoring imported from Configuration.DataProcessing.Utils
process = addMonitoring(process)
process = addVertexSmeared(process)

# End of customisation functions


# Customisation from command line

# Add early deletion of temporary data products to reduce peak memory need
from Configuration.StandardSequences.earlyDeleteSettings_cff import customiseEarlyDelete
process = customiseEarlyDelete(process)
# End adding early deletion