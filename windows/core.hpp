#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace lightsnap {
struct Rect {
    int x{}, y{}, w{}, h{};
    bool operator==(const Rect& b) const { return x==b.x && y==b.y && w==b.w && h==b.h; }
};
inline bool closeTo(Rect a, Rect b, int tolerance=3) {
    return std::abs(a.x-b.x)<=tolerance && std::abs(a.y-b.y)<=tolerance &&
           std::abs(a.w-b.w)<=tolerance && std::abs(a.h-b.h)<=tolerance;
}
inline constexpr std::array<const char*,22> ids = {"left","right","top","bottom","topLeft","topRight","bottomLeft","bottomRight","firstThird","middleThird","lastThird","leftTwoThirds","rightTwoThirds","cell1","cell2","cell3","cell4","cell5","cell6","maximize","restore","nextDisplay"};
inline Rect fraction(Rect r, int col, int cols, int row=0, int rows=1, int span=1) {
    auto edge=[](int size,int n,int total) {return static_cast<int>(std::lround(double(size)*n/total));};
    int l=edge(r.w,col,cols),t=edge(r.h,row,rows);
    return {r.x+l,r.y+t,edge(r.w,col+span,cols)-l,edge(r.h,row+1,rows)-t};
}
inline Rect layout(int action, Rect r, int cycle=0) {
    if(action==0 || action==1) {
        if(cycle==1) return fraction(r,action==0?0:1,3,0,1,2);
        if(cycle==2) return fraction(r,action==0?0:2,3);
        return fraction(r,action,2);
    }
    if(action==2 || action==3) return fraction(r,0,1,action-2,2);
    if(action>=4 && action<=7) return fraction(r,(action-4)%2,2,(action-4)/2,2);
    if(action>=8 && action<=10) return fraction(r,action-8,3);
    if(action==11 || action==12) return fraction(r,action-11,3,0,1,2);
    if(action>=13 && action<=18) return fraction(r,(action-13)%3,3,(action-13)/3,2);
    if(action==19) return r;
    throw std::invalid_argument("Action has no static layout");
}
inline Rect transfer(Rect r,Rect from,Rect to) {
    int w=std::clamp(static_cast<int>(std::lround(double(r.w)*to.w/std::max(1,from.w))),1,to.w);
    int h=std::clamp(static_cast<int>(std::lround(double(r.h)*to.h/std::max(1,from.h))),1,to.h);
    int x=to.x+static_cast<int>(std::lround(double(r.x-from.x)*to.w/std::max(1,from.w)));
    int y=to.y+static_cast<int>(std::lround(double(r.y-from.y)*to.h/std::max(1,from.h)));
    return {std::clamp(x,to.x,to.x+to.w-w),std::clamp(y,to.y,to.y+to.h-h),w,h};
}
struct Binding { unsigned key{},mods{}; bool operator==(Binding b)const{return key==b.key&&mods==b.mods;} };
struct Settings { bool cycle=true; std::array<Binding,22> bindings{}; };
inline Settings defaults() {
    Settings s; const unsigned keys[]={0x25,0x27,0x26,0x28,'U','I','J','K','D','F','G','E','T','1','2','3','4','5','6',0x0D,0x08,0x27};
    for(size_t i=0;i<22;++i) s.bindings[i]={keys[i], i==21?7u:3u}; // Win32 ALT=1, CONTROL=2, SHIFT=4
    return s;
}
inline bool valid(Binding b) {
    if(!b.key) return b.mods==0;
    // Match the native hotkey editor: Ctrl plus optional Alt/Shift, no bare/system keys.
    return b.key<=254 && b.key!=0x10 && b.key!=0x11 && b.key!=0x12 &&
           b.key!=0x5B && b.key!=0x5C && (b.mods&2) && !(b.mods&~7u);
}
inline bool conflicts(const Settings&s,size_t index,Binding b) {
    if(!b.key) return false;
    for(size_t i=0;i<s.bindings.size();++i) if(i!=index && s.bindings[i]==b) return true;
    return false;
}
inline std::string serialize(const Settings&s) {
    std::ostringstream out;out<<"version=1\ncycle="<<(s.cycle?1:0)<<'\n';
    for(size_t i=0;i<22;++i)out<<ids[i]<<'='<<s.bindings[i].key<<','<<s.bindings[i].mods<<'\n';
    return out.str();
}
inline unsigned number(const std::string&text) {
    if(text.empty() || text.find_first_not_of("0123456789")!=std::string::npos) throw std::invalid_argument("Invalid number");
    auto n=std::stoul(text);if(n>65535)throw std::invalid_argument("Number out of range");return static_cast<unsigned>(n);
}
inline Settings parse(const std::string&text) {
    std::istringstream in(text);std::string line;std::map<std::string,std::string> values;
    while(std::getline(in,line)) {
        if(!line.empty()&&line.back()=='\r')line.pop_back(); if(line.empty())continue;
        auto p=line.find('=');if(p==std::string::npos || !values.emplace(line.substr(0,p),line.substr(p+1)).second)throw std::invalid_argument("Malformed/duplicate setting");
    }
    if(values["version"]!="1")throw std::invalid_argument("Unsupported settings version");
    if(values["cycle"]!="0"&&values["cycle"]!="1")throw std::invalid_argument("Invalid cycle");
    Settings s;s.cycle=values["cycle"]=="1";
    for(size_t i=0;i<22;++i) {
        auto it=values.find(ids[i]);if(it==values.end())continue; // Missing means disabled, never restore defaults here.
        auto p=it->second.find(',');if(p==std::string::npos)throw std::invalid_argument("Invalid binding");
        Binding b{number(it->second.substr(0,p)),number(it->second.substr(p+1))};
        if(!valid(b)||conflicts(s,i,b))throw std::invalid_argument("Invalid/duplicate binding");s.bindings[i]=b;
    }
    for(const auto&v:values)if(v.first!="version"&&v.first!="cycle"&&std::find_if(ids.begin(),ids.end(),[&](const char*id){return v.first==id;})==ids.end())throw std::invalid_argument("Unknown setting");
    return s;
}
struct Cycle {
    uintptr_t window{};int action=-1,index=0;Rect screen{},actual{};
    int next(uintptr_t w,int a,Rect s,Rect current,bool enabled)const {
        return enabled&&(a==0||a==1)&&window==w&&action==a&&screen==s&&closeTo(current,actual)?(index+1)%3:0;
    }
    void commit(uintptr_t w,int a,Rect s,Rect r,int i){window=w;action=a;screen=s;actual=r;index=i;}
    void reset(){*this=Cycle{};}
};
}
