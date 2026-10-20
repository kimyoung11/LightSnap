#include "core.hpp"
#include <iostream>
#include <cstdlib>
using namespace lightsnap;
static int checks=0;
static void check(bool ok,const char*why){++checks;if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
int main(){
    for(Rect screen: {Rect{0,0,1920,1040},Rect{-1537,-451,1537,863},Rect{1920,0,2561,1401}}){
        auto l=layout(0,screen),r=layout(1,screen);check(l.x+l.w==r.x,"halves gap");check(r.x+r.w==screen.x+screen.w,"right edge");
        for(int row=0;row<2;++row){int x=screen.x;for(int col=0;col<3;++col){auto c=layout(13+row*3+col,screen);check(c.x==x,"grid gap");x+=c.w;check(c.w>0&&c.h>0,"empty grid");}check(x==screen.x+screen.w,"grid final edge");}
        check(layout(19,screen)==screen,"maximize work area");
        for(int a=0;a<20;++a){auto f=layout(a,screen);check(f.x>=screen.x&&f.y>=screen.y&&f.x+f.w<=screen.x+screen.w&&f.y+f.h<=screen.y+screen.h,"layout out of bounds");}
    }
    auto s=defaults();check(serialize(parse(serialize(s)))==serialize(s),"round trip");
    check(!parse("version=1\ncycle=1\nleft=37,3\n").bindings[1].key,"missing binding must stay disabled");
    for(auto text:{"version=2\ncycle=1\n","version=1\ncycle=1\nleft=37,3\nright=37,3\n","version=1\ncycle=1\nleft=37,0\n","version=1\ncycle=1\nleft=37,3\nleft=39,3\n","version=1\ncycle=1\nleft=-1,3\n","version=1\ncycle=1\nleft=65536,3\n"}){bool failed=false;try{parse(text);}catch(...){failed=true;}check(failed,"unsafe settings accepted");}
    s.bindings[0]={};check(!parse(serialize(s)).bindings[0].key,"disabled lost");
    Cycle c;Rect screen{0,0,1920,1040};auto frame=layout(0,screen);c.commit(1,0,screen,frame,0);
    check(c.next(1,0,screen,frame,true)==1,"cycle repeat");check(c.next(2,0,screen,frame,true)==0,"wrong window cycle");check(c.next(1,1,screen,frame,true)==0,"wrong action cycle");check(c.next(1,0,screen,Rect{10,0,960,1040},true)==0,"manual move resets cycle");check(c.next(1,0,screen,frame,false)==0,"cycle disabled");
    auto moved=transfer({-2000,-500,3000,1800},{-1920,0,1920,1080},{0,-1440,2560,1440});check(moved==Rect{0,-1440,2560,1440},"removed screen clamp");
    moved=transfer({0,0,960,1040},{0,0,1920,1040},{1920,0,2560,1400});check(moved==Rect{1920,0,1280,1400},"proportional screen transfer");
    std::cout<<checks<<" Windows core checks passed\n";
}
