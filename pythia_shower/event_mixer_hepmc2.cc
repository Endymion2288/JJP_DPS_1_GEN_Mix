// event_mixer_hepmc2.cc - 使用HepMC2库输出
// 将两个HepMC3 SPS文件合并成DPS事件，输出为CMSSW兼容的HepMC2格式
//
// 编译: g++ -std=c++11 -O2 event_mixer_hepmc2.cc -o event_mixer_hepmc2 \
//       -I$HEPMC3/include -I$HEPMC2/include \
//       -L$HEPMC3/lib64 -L$HEPMC2/lib -Wl,-rpath,$HEPMC3/lib64 -Wl,-rpath,$HEPMC2/lib \
//       -lHepMC3 -lHepMC
//
// 用法: ./event_mixer_hepmc2 input1.hepmc input2.hepmc output.hepmc [nEvents]

#include "HepMC3/GenEvent.h"
#include "HepMC3/GenParticle.h"
#include "HepMC3/GenVertex.h"
#include "HepMC3/ReaderAscii.h"
#include "HepMC3/Print.h"

#include "HepMC/GenEvent.h"
#include "HepMC/GenParticle.h"
#include "HepMC/GenVertex.h"
#include "HepMC/IO_GenEvent.h"

#include <iostream>
#include <fstream>
#include <map>
#include <vector>
#include <memory>

using namespace std;

// 将HepMC3事件转换为HepMC2事件
HepMC::GenEvent* convertToHepMC2(const HepMC3::GenEvent& evt3, int eventNumber) {
    // 创建HepMC2事件
    HepMC::GenEvent* evt2 = new HepMC::GenEvent();
    evt2->set_event_number(eventNumber);
    evt2->set_signal_process_id(0);
    
    // 设置权重
    if (evt3.weights().size() > 0) {
        evt2->weights().push_back(evt3.weights()[0]);
    } else {
        evt2->weights().push_back(1.0);
    }
    
    // 映射: HepMC3粒子ID -> HepMC2粒子指针
    map<int, HepMC::GenParticle*> particleMap;
    
    // 先创建所有粒子
    for (const auto& p3 : evt3.particles()) {
        HepMC::FourVector mom(p3->momentum().px(), 
                              p3->momentum().py(),
                              p3->momentum().pz(),
                              p3->momentum().e());
        HepMC::GenParticle* p2 = new HepMC::GenParticle(mom, p3->pid(), p3->status());
        p2->suggest_barcode(p3->id());
        particleMap[p3->id()] = p2;
    }
    
    // 创建顶点并连接粒子
    map<int, HepMC::GenVertex*> vertexMap;
    
    for (const auto& v3 : evt3.vertices()) {
        HepMC::FourVector pos(v3->position().x(),
                              v3->position().y(),
                              v3->position().z(),
                              v3->position().t());
        HepMC::GenVertex* v2 = new HepMC::GenVertex(pos);
        v2->suggest_barcode(v3->id());
        
        // 添加输入粒子
        for (const auto& p3_in : v3->particles_in()) {
            if (particleMap.count(p3_in->id())) {
                v2->add_particle_in(particleMap[p3_in->id()]);
            }
        }
        
        // 添加输出粒子
        for (const auto& p3_out : v3->particles_out()) {
            if (particleMap.count(p3_out->id())) {
                v2->add_particle_out(particleMap[p3_out->id()]);
            }
        }
        
        evt2->add_vertex(v2);
        vertexMap[v3->id()] = v2;
    }
    
    return evt2;
}

// 合并两个HepMC3事件，返回一个HepMC2事件
HepMC::GenEvent* mergeAndConvert(const HepMC3::GenEvent& evt1, 
                                  const HepMC3::GenEvent& evt2, 
                                  int eventNumber) {
    // 创建合并的HepMC2事件
    HepMC::GenEvent* merged = new HepMC::GenEvent();
    merged->set_event_number(eventNumber);
    merged->set_signal_process_id(0);
    
    // 设置权重 - 合并两个事件的权重
    double w1 = evt1.weights().size() > 0 ? evt1.weights()[0] : 1.0;
    double w2 = evt2.weights().size() > 0 ? evt2.weights()[0] : 1.0;
    merged->weights().push_back(w1 * w2);
    
    // 粒子barcode偏移量，避免第二个事件的粒子ID冲突
    int barcodeOffset = 100000;
    
    // 处理第一个事件
    map<int, HepMC::GenParticle*> particleMap1;
    for (const auto& p3 : evt1.particles()) {
        HepMC::FourVector mom(p3->momentum().px(), 
                              p3->momentum().py(),
                              p3->momentum().pz(),
                              p3->momentum().e());
        HepMC::GenParticle* p2 = new HepMC::GenParticle(mom, p3->pid(), p3->status());
        p2->suggest_barcode(p3->id());
        particleMap1[p3->id()] = p2;
    }
    
    for (const auto& v3 : evt1.vertices()) {
        HepMC::FourVector pos(v3->position().x(),
                              v3->position().y(),
                              v3->position().z(),
                              v3->position().t());
        HepMC::GenVertex* v2 = new HepMC::GenVertex(pos);
        v2->suggest_barcode(v3->id());
        
        for (const auto& p3_in : v3->particles_in()) {
            if (particleMap1.count(p3_in->id())) {
                v2->add_particle_in(particleMap1[p3_in->id()]);
            }
        }
        for (const auto& p3_out : v3->particles_out()) {
            if (particleMap1.count(p3_out->id())) {
                v2->add_particle_out(particleMap1[p3_out->id()]);
            }
        }
        merged->add_vertex(v2);
    }
    
    // 处理第二个事件（使用偏移的barcode）
    map<int, HepMC::GenParticle*> particleMap2;
    for (const auto& p3 : evt2.particles()) {
        HepMC::FourVector mom(p3->momentum().px(), 
                              p3->momentum().py(),
                              p3->momentum().pz(),
                              p3->momentum().e());
        HepMC::GenParticle* p2 = new HepMC::GenParticle(mom, p3->pid(), p3->status());
        p2->suggest_barcode(p3->id() + barcodeOffset);
        particleMap2[p3->id()] = p2;
    }
    
    for (const auto& v3 : evt2.vertices()) {
        HepMC::FourVector pos(v3->position().x(),
                              v3->position().y(),
                              v3->position().z(),
                              v3->position().t());
        HepMC::GenVertex* v2 = new HepMC::GenVertex(pos);
        v2->suggest_barcode(v3->id() - barcodeOffset); // 负barcode避免冲突
        
        for (const auto& p3_in : v3->particles_in()) {
            if (particleMap2.count(p3_in->id())) {
                v2->add_particle_in(particleMap2[p3_in->id()]);
            }
        }
        for (const auto& p3_out : v3->particles_out()) {
            if (particleMap2.count(p3_out->id())) {
                v2->add_particle_out(particleMap2[p3_out->id()]);
            }
        }
        merged->add_vertex(v2);
    }
    
    return merged;
}

// 统计事件中的特定粒子
void countParticles(const HepMC::GenEvent* evt, int& nJpsi, int& nPhi, int& nTotal) {
    nJpsi = 0;
    nPhi = 0;
    nTotal = 0;
    
    for (HepMC::GenEvent::particle_const_iterator p = evt->particles_begin();
         p != evt->particles_end(); ++p) {
        nTotal++;
        if (abs((*p)->pdg_id()) == 443) nJpsi++;  // J/psi
        if (abs((*p)->pdg_id()) == 333) nPhi++;   // phi
    }
}

int main(int argc, char* argv[]) {
    
    if (argc < 4) {
        cerr << "\n====== HepMC Event Mixer (HepMC2 Output) ======" << endl;
        cerr << "Usage: " << argv[0] << " input1.hepmc input2.hepmc output.hepmc [nEvents]" << endl;
        cerr << "\nThis version outputs in HepMC2 format compatible with CMSSW MCFileSource" << endl;
        return 1;
    }
    
    string input1 = argv[1];
    string input2 = argv[2];
    string output = argv[3];
    int nEvents = (argc > 4) ? atoi(argv[4]) : -1;
    
    cout << "\n====== HepMC Event Mixer (HepMC2 Output) ======" << endl;
    cout << "Input 1 (SPS): " << input1 << endl;
    cout << "Input 2 (SPS): " << input2 << endl;
    cout << "Output (DPS):  " << output << endl;
    cout << "Output format: HepMC2 (CMSSW MCFileSource compatible)" << endl;
    cout << "Target events: " << (nEvents > 0 ? to_string(nEvents) : "all") << endl;
    cout << "=================================================" << endl << endl;
    
    // 打开HepMC3输入文件
    HepMC3::ReaderAscii reader1(input1);
    if (reader1.failed()) {
        cerr << "Error: Cannot open input file 1: " << input1 << endl;
        return 1;
    }
    
    HepMC3::ReaderAscii reader2(input2);
    if (reader2.failed()) {
        cerr << "Error: Cannot open input file 2: " << input2 << endl;
        return 1;
    }
    
    // 打开HepMC2输出文件
    HepMC::IO_GenEvent writer(output, ios::out);
    
    // 统计变量
    int nMerged = 0;
    int totalJpsi = 0;
    int totalPhi = 0;
    int totalParticles = 0;
    
    // 主循环
    while (true) {
        if (nEvents > 0 && nMerged >= nEvents) break;
        
        // 读取两个HepMC3事件
        HepMC3::GenEvent evt1, evt2;
        
        bool ok1 = reader1.read_event(evt1);
        bool ok2 = reader2.read_event(evt2);
        
        if (!ok1 || reader1.failed()) {
            cout << "\nReached end of input file 1" << endl;
            break;
        }
        if (!ok2 || reader2.failed()) {
            cout << "\nReached end of input file 2" << endl;
            break;
        }
        
        if (evt1.particles().empty() || evt2.particles().empty()) {
            cerr << "Warning: Empty event encountered, skipping..." << endl;
            continue;
        }
        
        // 合并并转换为HepMC2
        HepMC::GenEvent* merged = mergeAndConvert(evt1, evt2, nMerged + 1);
        
        // 统计粒子
        int nJpsi, nPhi, nTotal;
        countParticles(merged, nJpsi, nPhi, nTotal);
        totalJpsi += nJpsi;
        totalPhi += nPhi;
        totalParticles += nTotal;
        
        // 写出HepMC2事件
        writer.write_event(merged);
        delete merged;
        
        nMerged++;
        
        if (nMerged % 100 == 0) {
            cout << "Merged " << nMerged << " events, "
                 << "avg particles: " << totalParticles / nMerged
                 << ", J/psi: " << totalJpsi << ", phi: " << totalPhi << endl;
        }
    }
    
    reader1.close();
    reader2.close();
    
    cout << "\n=================================================" << endl;
    cout << "=== Mixing Complete ===" << endl;
    cout << "=================================================" << endl;
    cout << "Total DPS events created: " << nMerged << endl;
    cout << "Total particles:          " << totalParticles << endl;
    cout << "Average particles/event:  " << (nMerged > 0 ? totalParticles / nMerged : 0) << endl;
    cout << "Total J/psi count:        " << totalJpsi << endl;
    cout << "Total phi count:          " << totalPhi << endl;
    cout << "Output file: " << output << endl;
    cout << "=================================================" << endl << endl;
    
    return 0;
}
