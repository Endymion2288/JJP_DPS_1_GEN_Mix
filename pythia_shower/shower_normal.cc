// shower_normal.cc - 标准Pythia8 shower处理
// 完整的parton shower + hadronization
#include "Pythia8/Pythia.h"
#include "Pythia8Plugins/HepMC3.h"

using namespace Pythia8;

int main(int argc, char* argv[]) {
    
    if (argc < 3) {
        cerr << "Usage: " << argv[0] << " input.lhe output.hepmc [nEvents]" << endl;
        cerr << "  nEvents: number of events to process (default: -1, all)" << endl;
        return 1;
    }
    
    string inputFile = argv[1];
    string outputFile = argv[2];
    int nEvents = (argc > 3) ? atoi(argv[3]) : -1;
    
    cout << "\n=== Pythia8 Standard Shower Processing ===" << endl;
    cout << "Input LHE:    " << inputFile << endl;
    cout << "Output HepMC: " << outputFile << endl;
    cout << "Events:       " << (nEvents > 0 ? to_string(nEvents) : "all") << endl;
    cout << "==========================================\n" << endl;
    
    // 初始化Pythia
    Pythia pythia;
    
    // 基本设置
    pythia.readString("Beams:frameType = 4"); // 从LHEF读取
    pythia.readString("Beams:LHEF = " + inputFile);
    
    // Run3 2022能量设置
    pythia.readString("Beams:eCM = 13600."); // 13.6 TeV
    
    // Shower设置
    pythia.readString("PartonLevel:ISR = on");
    pythia.readString("PartonLevel:FSR = on");
    pythia.readString("PartonLevel:MPI = on");
    pythia.readString("HadronLevel:all = on");
    
    // 色重联设置（CMS tune）
    pythia.readString("ColourReconnection:reconnect = on");
    pythia.readString("ColourReconnection:mode = 1");
    pythia.readString("ColourReconnection:allowDoubleJunRem = off");
    pythia.readString("ColourReconnection:m0 = 0.3");
    pythia.readString("ColourReconnection:allowJunctions = on");
    pythia.readString("ColourReconnection:junctionCorrection = 1.20");
    pythia.readString("ColourReconnection:timeDilationMode = 2");
    pythia.readString("ColourReconnection:timeDilationPar = 0.18");
    
    // CP5 tune相关设置
    pythia.readString("Tune:pp = 14");
    pythia.readString("Tune:ee = 7");
    pythia.readString("MultipartonInteractions:pT0Ref = 2.4024");
    pythia.readString("MultipartonInteractions:ecmPow = 0.25208");
    pythia.readString("MultipartonInteractions:expPow = 1.6");
    
    // ========== 强制衰变设置 ==========
    // J/psi (443) -> mu+ mu- (13, -13)
    // 先关闭所有J/psi衰变道，然后只开启mu mu道
    pythia.readString("443:onMode = off");           // 关闭所有衰变道
    pythia.readString("443:onIfMatch = 13 -13");     // 只开启 J/psi -> mu+ mu-
    
    // phi (333) -> K+ K- (321, -321)
    // 先关闭所有phi衰变道，然后只开启K K道
    pythia.readString("333:onMode = off");           // 关闭所有衰变道
    pythia.readString("333:onIfMatch = 321 -321");   // 只开启 phi -> K+ K-
    // ===================================
    
    // 初始化
    if (!pythia.init()) {
        cerr << "Pythia initialization failed!" << endl;
        return 1;
    }
    
    // HepMC3输出接口
    Pythia8::Pythia8ToHepMC toHepMC(outputFile);
    
    // 事例循环
    int iEvent = 0;
    int iAbort = 0;
    int maxAbort = 10;
    
    while (true) {
        if (nEvents > 0 && iEvent >= nEvents) break;
        
        if (!pythia.next()) {
            if (++iAbort < maxAbort) continue;
            cout << "Event generation aborted prematurely!" << endl;
            break;
        }
        
        // 写出到HepMC
        toHepMC.writeNextEvent(pythia);
        
        ++iEvent;
        if (iEvent % 1000 == 0) {
            cout << "Processed " << iEvent << " events" << endl;
        }
    }
    
    // 统计信息
    pythia.stat();
    
    cout << "\n========================================================" << endl;
    cout << "Total events processed: " << iEvent << endl;
    cout << "Output file: " << outputFile << endl;
    cout << "========================================================" << endl;
    
    return 0;
}