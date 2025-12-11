# Makefile for Pythia8 shower programs

PYTHIA8 = /eos/user/x/xcheng/pythia8316
HEPMC3 = /eos/user/x/xcheng/HepMC3/HepMC3-3.3.1/build
HEPMC2 = /eos/user/x/xcheng/HepMC/install

CXX = g++
CXXFLAGS = -std=c++11 -O2 -pedantic -W -Wall -Wshadow -fPIC
INCLUDE = -I$(PYTHIA8)/include -I$(HEPMC3)/include
LDFLAGS = -L$(PYTHIA8)/lib -L$(HEPMC3)/lib64 -Wl,-rpath,$(PYTHIA8)/lib -Wl,-rpath,$(HEPMC3)/lib64
LIBS = -lpythia8 -lHepMC3

# 所有可执行文件
TARGETS = shower_normal shower_phi event_mixer_hepmc2

all: $(TARGETS)

shower_normal: shower_normal.cc
	$(CXX) $(CXXFLAGS) $(INCLUDE) -o $@ $< $(LDFLAGS) $(LIBS)

shower_phi: shower_phi.cc
	$(CXX) $(CXXFLAGS) $(INCLUDE) -o $@ $< $(LDFLAGS) $(LIBS)

# event_mixer_hepmc2 需要 HepMC3（读取）和 HepMC2（输出）
event_mixer_hepmc2: event_mixer_hepmc2.cc
	$(CXX) $(CXXFLAGS) -I$(HEPMC3)/include -I$(HEPMC2)/include -o $@ $< \
		-L$(HEPMC3)/lib64 -L$(HEPMC2)/lib -Wl,-rpath,$(HEPMC3)/lib64 -Wl,-rpath,$(HEPMC2)/lib \
		-lHepMC3 -lHepMC

clean:
	rm -f $(TARGETS) *.o

.PHONY: all clean