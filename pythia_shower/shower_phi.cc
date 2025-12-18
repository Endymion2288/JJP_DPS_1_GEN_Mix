// shower_phi.cc - 增强φ介子产生的Pythia8 shower处理
// 基于Pythia8官方 main361.cc 的 save/restore 机制
// 通过多次重试hadronization来富集含φ事例
//
// 关键发现：φ介子因为立即衰变，其状态码为 -83 或 -84
// 因此检测时需要用 (status < 0) || isFinal()

#include "Pythia8/Pythia.h"
#include "Pythia8Plugins/HepMC3.h"

#include <iostream>
#include <string>

using namespace Pythia8;
using namespace std;

// 检查事件中是否有满足条件的φ介子
// φ介子衰变后状态码为负数（-83, -84等），所以需要检查所有粒子
bool hasPhiMeson(Event& event, double minPt = 0.0) {
    for (int i = 0; i < event.size(); ++i) {
        int pid = abs(event[i].id());
        if (pid == 333) { // phi meson
            int status = event[i].status();
            // φ介子通常已衰变（status < 0），或者是末态粒子
            if ((status < 0) || event[i].isFinal()) {
                if (event[i].pT() > minPt) {
                    return true;
                }
            }
        }
    }
    return false;
}

// 统计事件中的关键粒子
void countParticles(Event& event, int& nJpsi, int& nPhi, int& nMuon) {
    nJpsi = 0;
    nPhi = 0;
    nMuon = 0;
    
    for (int i = 0; i < event.size(); ++i) {
        int pid = abs(event[i].id());
        int status = event[i].status();
        
        // 使用相同的检测逻辑
        if ((status < 0) || event[i].isFinal()) {
            if (pid == 443) nJpsi++;
            else if (pid == 333) nPhi++;
            else if (pid == 13) nMuon++;
        }
    }
}

int main(int argc, char* argv[]) {
    
    if (argc < 3) {
        cerr << "\n====== Phi-Enriched Shower Processing ======" << endl;
        cerr << "Usage: " << argv[0] << " input.lhe output.hepmc [nEvents] [minPhiPt] [maxRetry]" << endl;
        cerr << "\nArguments:" << endl;
        cerr << "  input.lhe   : Input LHE file from HELAC-Onia" << endl;
        cerr << "  output.hepmc: Output HepMC file" << endl;
        cerr << "  nEvents     : Number of events to process (default: -1, all)" << endl;
        cerr << "  minPhiPt    : Minimum phi pT in GeV (default: 0)" << endl;
        cerr << "  maxRetry    : Maximum hadronization retries (default: 100)" << endl;
        cerr << "\nExample:" << endl;
        cerr << "  ./shower_phi jpsi_jpsi.lhe phi_enriched.hepmc 1000 3.0 100" << endl;
        return 1;
    }
    
    string inputFile = argv[1];
    string outputFile = argv[2];
    int nEvents = (argc > 3) ? atoi(argv[3]) : -1;
    double minPhiPt = (argc > 4) ? atof(argv[4]) : 0.0;
    int maxRetry = (argc > 5) ? atoi(argv[5]) : 100;
    
    cout << "\n====== Phi-Enriched Shower Processing ======" << endl;
    cout << "Input LHE:    " << inputFile << endl;
    cout << "Output HepMC: " << outputFile << endl;
    cout << "Events:       " << (nEvents > 0 ? to_string(nEvents) : "all") << endl;
    cout << "Min phi pT:   " << minPhiPt << " GeV" << endl;
    cout << "Max retries:  " << maxRetry << endl;
    cout << "=============================================\n" << endl;
    
    // 初始化 Pythia
    Pythia pythia;
    
    // 基本设置
    pythia.readString("Beams:frameType = 4");  // 从 LHEF 读取
    pythia.readString("Beams:LHEF = " + inputFile);
    
    // Run3 能量
    pythia.readString("Beams:eCM = 13600.");
    
    // Parton shower 设置
    pythia.readString("PartonLevel:ISR = on");
    pythia.readString("PartonLevel:FSR = on");
    pythia.readString("PartonLevel:MPI = on");
    
    // 关闭自动hadronization，我们手动控制
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
    
    // CP5 tune
    pythia.readString("Tune:pp = 14");
    pythia.readString("Tune:ee = 7");
    pythia.readString("MultipartonInteractions:pT0Ref = 2.4024");
    pythia.readString("MultipartonInteractions:ecmPow = 0.25208");
    pythia.readString("MultipartonInteractions:expPow = 1.6");
    
    // 增加奇异夸克产生（增强φ介子产生）
    pythia.readString("StringFlav:probStoUD = 0.30");  // 默认0.217，增加s夸克比例
    pythia.readString("StringFlav:mesonUDvector = 0.60");  // 增加矢量介子
    pythia.readString("StringFlav:mesonSvector = 0.60");
    
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
    
    // HepMC3 输出接口
    Pythia8::Pythia8ToHepMC toHepMC(outputFile);
    
    // 统计变量
    int iEvent = 0;
    int iAbort = 0;
    int maxAbort = 10;
    int totalRetries = 0;
    int successWithPhi = 0;
    int failedToFindPhi = 0;
    
    // 粒子统计
    int totalJpsi = 0, totalPhi = 0, totalMuon = 0;
    
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
        
        // 尝试多次 hadronization 直到找到含φ的事例
        bool foundPhi = false;
        int nRetry = 0;
        
        for (nRetry = 0; nRetry < maxRetry; ++nRetry) {
            // 恢复 parton level 状态
            pythia.event = savedEvent;
            pythia.partonSystems = savedPartonSystems;
            
            // 进行 hadronization
            if (!pythia.forceHadronLevel()) {
                continue;  // hadronization 失败，重试
            }
            
            // 检查是否有满足条件的φ介子
            if (hasPhiMeson(pythia.event, minPhiPt)) {
                foundPhi = true;
                break;
            }
        }
        
        totalRetries += nRetry + 1;
        
        if (foundPhi) {
            successWithPhi++;
            
            // 统计粒子
            int nJpsi, nPhi, nMuon;
            countParticles(pythia.event, nJpsi, nPhi, nMuon);
            totalJpsi += nJpsi;
            totalPhi += nPhi;
            totalMuon += nMuon;
            
            // 只有找到满足条件的phi时才写入HepMC文件
            toHepMC.writeNextEvent(pythia);
        } else {
            failedToFindPhi++;
            // 如果达到最大重试次数仍未找到满足pT条件的phi，跳过此事例
            // 不写入输出文件，以确保输出中的每个事例都有pT>minPhiPt的phi
        }
        
        ++iEvent;
        if (iEvent % 100 == 0) {
            double efficiency = 100.0 * successWithPhi / iEvent;
            double avgRetry = (double)totalRetries / iEvent;
            cout << "Processed " << iEvent << " events, "
                 << "phi efficiency: " << efficiency << "%, "
                 << "avg retries: " << avgRetry << endl;
        }
    }
    
    // 统计信息
    pythia.stat();
    
    cout << "\n======================================================" << endl;
    cout << "Processing Summary:" << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Total LHE events processed:  " << iEvent << endl;
    cout << "Events written (pT>" << minPhiPt << " phi): " << successWithPhi 
         << " (" << 100.0*successWithPhi/max(1,iEvent) << "%)" << endl;
    cout << "Events skipped (no phi):     " << failedToFindPhi << endl;
    cout << "Total hadronization tries:   " << totalRetries << endl;
    cout << "Average retries per event:   " << (double)totalRetries/max(1,iEvent) << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Particle counts (in written events):" << endl;
    cout << "  Total J/psi: " << totalJpsi << endl;
    cout << "  Total phi:   " << totalPhi << endl;
    cout << "  Total muons: " << totalMuon << endl;
    cout << "------------------------------------------------------" << endl;
    cout << "Output events: " << successWithPhi << endl;
    cout << "Output file:   " << outputFile << endl;
}
