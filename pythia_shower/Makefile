# Makefile for Pythia8 shower programs
# 使用CMSSW自带的Pythia8和HepMC库 (需要先 cmsenv)

# CMSSW提供的库路径
PYTHIA8_BASE = /cvmfs/cms.cern.ch/el8_amd64_gcc10/external/pythia8/306-494ded5c626b685d055d5b022e918c0c
HEPMC3_BASE = /cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc3/3.2.5-c3cd50aeecf06b194814f1a75bf7872e
HEPMC2_BASE = /cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc/2.06.10-46867a6dcc6e5712b7953fe57085fcbd

CXX = g++
CXXFLAGS = -std=c++17 -O2 -pedantic -W -Wall -Wshadow -fPIC

# Pythia8 + HepMC3 for shower programs
INCLUDE_PYTHIA = -I$(PYTHIA8_BASE)/include -I$(HEPMC3_BASE)/include
LDFLAGS_PYTHIA = -L$(PYTHIA8_BASE)/lib -L$(HEPMC3_BASE)/lib64 \
                 -Wl,-rpath,$(PYTHIA8_BASE)/lib -Wl,-rpath,$(HEPMC3_BASE)/lib64
LIBS_PYTHIA = -lpythia8 -lHepMC3

# HepMC3 + HepMC2 for event mixer
INCLUDE_MIXER = -I$(HEPMC3_BASE)/include -I$(HEPMC2_BASE)/include
LDFLAGS_MIXER = -L$(HEPMC3_BASE)/lib64 -L$(HEPMC2_BASE)/lib \
                -Wl,-rpath,$(HEPMC3_BASE)/lib64 -Wl,-rpath,$(HEPMC2_BASE)/lib
LIBS_MIXER = -lHepMC3 -lHepMC

# 所有可执行文件
TARGETS = shower_normal shower_phi event_mixer_hepmc2

all: $(TARGETS)

shower_normal: shower_normal.cc
	$(CXX) $(CXXFLAGS) $(INCLUDE_PYTHIA) -o $@ $< $(LDFLAGS_PYTHIA) $(LIBS_PYTHIA)

shower_phi: shower_phi.cc
	$(CXX) $(CXXFLAGS) $(INCLUDE_PYTHIA) -o $@ $< $(LDFLAGS_PYTHIA) $(LIBS_PYTHIA)

# event_mixer_hepmc2 需要 HepMC3（读取）和 HepMC2（输出）
event_mixer_hepmc2: event_mixer_hepmc2.cc
	$(CXX) $(CXXFLAGS) $(INCLUDE_MIXER) -o $@ $< $(LDFLAGS_MIXER) $(LIBS_MIXER)

clean:
	rm -f $(TARGETS) *.o

.PHONY: all clean