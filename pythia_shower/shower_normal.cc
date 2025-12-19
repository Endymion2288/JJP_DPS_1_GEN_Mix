// shower_normal.cc - 标准Pythia8 shower处理
// 完整的parton shower + hadronization
// 包含对J/psi衰变muon的动力学筛选
#include "Pythia8/Pythia.h"
#include "Pythia8Plugins/HepMC3.h"

#include <iostream>
#include <string>

using namespace Pythia8;
using namespace std;

// 检查J/psi衰变产生的muon是否满足动力学条件
// 要求两个muon都满足 pT > minPt 且 |eta| < maxEta
bool hasValidJpsiMuons(Event& event, double minPt = 2.5, double maxEta = 2.4) {
    // 找到所有J/psi并检查其衰变产物
    for (int i = 0; i < event.size(); ++i) {
        if (abs(event[i].id()) != 443) continue; // 只看J/psi
        
        int status = event[i].status();
        if (status >= 0 && !event[i].isFinal()) continue; // 跳过未衰变的
        
        // 获取J/psi的衰变产物
        int d1 = event[i].daughter1();
        int d2 = event[i].daughter2();
        
        if (d1 <= 0 || d2 <= 0) continue;
        
        // 检查是否衰变到mu+ mu-
        bool foundMuPlus = false, foundMuMinus = false;
        bool muPlusValid = false, muMinusValid = false;
        
        for (int j = d1; j <= d2; ++j) {
            int pid = event[j].id();
            if (pid == 13) { // mu-
                foundMuMinus = true;
                if (event[j].pT() > minPt && abs(event[j].eta()) < maxEta) {
                    muMinusValid = true;
                }
            } else if (pid == -13) { // mu+
                foundMuPlus = true;
                if (event[j].pT() > minPt && abs(event[j].eta()) < maxEta) {
                    muPlusValid = true;
                }
            }
        }
        
        // 如果找到了J/psi -> mu+ mu-衰变，检查两个muon是否都满足条件
        if (foundMuPlus && foundMuMinus) {
            if (muPlusValid && muMinusValid) {
                return true;
            }
        }
    }
    return false;
}

int main(int argc, char* argv[]) {
    
    if (argc < 3) {
        cerr << "\n=== Pythia8 Standard Shower Processing ===" << endl;
        cerr << "Usage: " << argv[0] << " input.lhe output.hepmc [nEvents] [minMuonPt] [maxMuonEta] [maxRetry]" << endl;
        cerr << "\nArguments:" << endl;
        cerr << "  input.lhe   : Input LHE file" << endl;
        cerr << "  output.hepmc: Output HepMC file" << endl;
        cerr << "  nEvents     : Number of events to process (default: -1, all)" << endl;
        cerr << "  minMuonPt   : Minimum muon pT in GeV (default: 2.5)" << endl;
        cerr << "  maxMuonEta  : Maximum muon |eta| (default: 2.4)" << endl;
        cerr << "  maxRetry    : Maximum hadronization retries (default: 100)" << endl;
        cerr << "\nExample:" << endl;
        cerr << "  ./shower_normal jpsi_jpsi.lhe output.hepmc 1000 2.5 2.4 100" << endl;
        return 1;
    }
    
    string inputFile = argv[1];
    string outputFile = argv[2];
    int nEvents = (argc > 3) ? atoi(argv[3]) : -1;
    double minMuonPt = (argc > 4) ? atof(argv[4]) : 2.5;
    double maxMuonEta = (argc > 5) ? atof(argv[5]) : 2.4;
    int maxRetry = (argc > 6) ? atoi(argv[6]) : 1000;
    
    cout << "\n=== Pythia8 Standard Shower Processing ===" << endl;
    cout << "Input LHE:    " << inputFile << endl;
    cout << "Output HepMC: " << outputFile << endl;
    cout << "Events:       " << (nEvents > 0 ? to_string(nEvents) : "all") << endl;
    cout << "Min muon pT:  " << minMuonPt << " GeV" << endl;
    cout << "Max muon eta: " << maxMuonEta << endl;
    cout << "Max retries:  " << maxRetry << endl;
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
    
    // 关闭自动hadronization，我们手动控制以便重试
    pythia.readString("HadronLevel:all = off");
    
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
    
    // 统计变量
    int iEvent = 0;
    int iAbort = 0;
    int maxAbort = 10;
    int totalRetries = 0;
    int successWithMuons = 0;
    int failedToFindMuons = 0;
    
    cout << "Starting event processing..." << endl;
    
    while (true) {
        if (nEvents > 0 && iEvent >= nEvents) break;
        
        // 运行 parton level（不含 hadronization）
        if (!pythia.next()) {
            if (pythia.info.atEndOfFile()) {
                cout << "Reached end of LHE file." << endl;
                break;
            }
            if (++iAbort < maxAbort) continue;
            cout << "Event generation aborted prematurely!" << endl;
            break;
        }
        
        // 保存 parton level 状态
        Event savedEvent = pythia.event;
        PartonSystems savedPartonSystems = pythia.partonSystems;
        
        // 尝试多次 hadronization 直到找到满足muon条件的事例
        bool foundValid = false;
        int nRetry = 0;
        
        for (nRetry = 0; nRetry < maxRetry; ++nRetry) {
            // 恢复 parton level 状态
            pythia.event = savedEvent;
            pythia.partonSystems = savedPartonSystems;
            
            // 进行 hadronization
            if (!pythia.forceHadronLevel()) {
                continue;  // hadronization 失败，重试
            }
            
            // 检查J/psi衰变的muon是否满足动力学条件
            if (hasValidJpsiMuons(pythia.event, minMuonPt, maxMuonEta)) {
                foundValid = true;
                break;
            }
        }
        
        totalRetries += nRetry + 1;
        
        if (foundValid) {
            successWithMuons++;
            // 写出到HepMC
            toHepMC.writeNextEvent(pythia);
        } else {
            failedToFindMuons++;
            // 如果达到最大重试次数仍未找到满足muon条件的事例，跳过
        }
        
        ++iEvent;
        if (iEvent % 100 == 0) {
            double efficiency = 100.0 * successWithMuons / iEvent;
            double avgRetry = (double)totalRetries / iEvent;
            cout << "Processed " << iEvent << " events, "
                 << "muon cut efficiency: " << efficiency << "%, "
                 << "avg retries: " << avgRetry << endl;
        }
    }
    
    // 统计信息
    pythia.stat();
    
    cout << "\n======================================================" << endl;
    cout << "Processing Summary:" << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Selection criteria:" << endl;
    cout << "  Muon pT > " << minMuonPt << " GeV, |eta| < " << maxMuonEta << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Total LHE events processed:  " << iEvent << endl;
    cout << "Events written (muon cuts):  " << successWithMuons 
         << " (" << 100.0*successWithMuons/max(1,iEvent) << "%)" << endl;
    cout << "Events skipped (failed cuts): " << failedToFindMuons << endl;
    cout << "Total hadronization tries:   " << totalRetries << endl;
    cout << "Average retries per event:   " << (double)totalRetries/max(1,iEvent) << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Output events: " << successWithMuons << endl;
    cout << "Output file:   " << outputFile << endl;
    cout << "======================================================" << endl;
    
    return 0;
}