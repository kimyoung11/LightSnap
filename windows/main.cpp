#include "core.hpp"
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <dwmapi.h>
#include <psapi.h>
#include <atomic>
#include <chrono>
#include <deque>
#include <mutex>
#include <set>
#include <thread>
using namespace lightsnap;
namespace {
constexpr UINT WM_TRAY=WM_APP+1, WM_RESULT=WM_APP+2, WM_SHOW=WM_APP+3;
constexpr int ID_ACTION=101,ID_KEY=102,ID_SAVE=103,ID_DISABLE=104,ID_DEFAULT=105,ID_CYCLE=106,ID_STARTUP=107,ID_PAUSE=108,ID_DIAG=109,ID_QUIT=110;
const wchar_t* names[]={L"왼쪽",L"오른쪽",L"위쪽",L"아래쪽",L"왼쪽 위",L"오른쪽 위",L"왼쪽 아래",L"오른쪽 아래",L"첫 번째 1/3",L"가운데 1/3",L"마지막 1/3",L"왼쪽 2/3",L"오른쪽 2/3",L"격자 1",L"격자 2",L"격자 3",L"격자 4",L"격자 5",L"격자 6",L"작업 영역 최대화",L"원래 배치 복원",L"다음 모니터"};
HWND ui{},combo{},keyControl{},statusControl{},bindingControl{},cycleControl{},startupControl{},pauseControl{};
HFONT font{};HINSTANCE instance{};NOTIFYICONDATAW tray{};UINT taskbarCreated{};HWINEVENTHOOK foregroundHook{},destroyHook{};
std::atomic<HWND> lastExternal{};
Settings settings=defaults();bool paused=false,editing=false,readOnly=false;
std::array<bool,22> registered{};
std::wstring configPath,loadWarning;
std::thread worker;std::atomic<bool> busy=false;
std::mutex resultMutex,destroyMutex;std::wstring pendingResult;bool pendingSuccess=false;double pendingLatency=0;
std::set<HWND> destroyed;bool historyInvalidated=false;
std::deque<double> latencies;unsigned long long received=0,successful=0,failed=0;
std::wstring lastStatus=L"준비됨 · 외부 앱 창에서 Ctrl+Alt+방향키를 누르세요.";
struct Monitor { HMONITOR handle;Rect work,full; };
Rect rect(RECT r){return {r.left,r.top,r.right-r.left,r.bottom-r.top};}
BOOL CALLBACK enumMonitor(HMONITOR handle,HDC,LPRECT,LPARAM data){
    MONITORINFO info{};info.cbSize=sizeof(info);if(GetMonitorInfoW(handle,&info))reinterpret_cast<std::vector<Monitor>*>(data)->push_back({handle,rect(info.rcWork),rect(info.rcMonitor)});return TRUE;
}
std::vector<Monitor> monitors(){std::vector<Monitor> out;EnumDisplayMonitors(nullptr,nullptr,enumMonitor,reinterpret_cast<LPARAM>(&out));
    std::sort(out.begin(),out.end(),[](const Monitor&a,const Monitor&b){return a.work.x==b.work.x?a.work.y<b.work.y:a.work.x<b.work.x;});
    out.erase(std::unique(out.begin(),out.end(),[](const Monitor&a,const Monitor&b){return a.work==b.work;}),out.end());return out;
}
void status(const std::wstring&s){lastStatus=s;if(statusControl)SetWindowTextW(statusControl,s.c_str());}
std::wstring exePath(){std::vector<wchar_t>b(32768);DWORD n=GetModuleFileNameW(nullptr,b.data(),static_cast<DWORD>(b.size()));return n&&n<b.size()?std::wstring(b.data(),n):L"";}
std::wstring bindingName(Binding b){
    if(!b.key)return L"해제됨";std::wstring out;if(b.mods&2)out+=L"Ctrl+";if(b.mods&1)out+=L"Alt+";if(b.mods&4)out+=L"Shift+";
    wchar_t buffer[128]{};UINT scan=MapVirtualKeyW(b.key,MAPVK_VK_TO_VSC);LONG param=static_cast<LONG>(scan<<16);
    if(b.key>=VK_PRIOR&&b.key<=VK_DOWN)param|=1<<24;
    if(GetKeyNameTextW(param,buffer,128))out+=buffer;else out+=std::to_wstring(b.key);return out;
}
void unregisterKeys(){for(int i=0;i<22;++i){if(registered[i])UnregisterHotKey(ui,1000+i);registered[i]=false;}}
int registerKeys(){unregisterKeys();if(paused||editing)return 0;int failures=0;
    for(int i=0;i<22;++i){auto b=settings.bindings[i];if(b.key){registered[i]=RegisterHotKey(ui,1000+i,b.mods|MOD_NOREPEAT,b.key)!=FALSE;if(!registered[i])++failures;}}return failures;
}
void refreshBinding(){int i=static_cast<int>(SendMessageW(combo,CB_GETCURSEL,0,0));if(i<0||i>=22)return;
    auto b=settings.bindings[i];WORD mods=static_cast<WORD>(((b.mods&2)?HOTKEYF_CONTROL:0)|((b.mods&1)?HOTKEYF_ALT:0)|((b.mods&4)?HOTKEYF_SHIFT:0));
    SendMessageW(keyControl,HKM_SETHOTKEY,MAKEWORD(b.key,mods),0);
    std::wstring text=L"현재: "+bindingName(b);if(b.key&&!registered[i]&&!paused&&!editing)text+=L" · 등록 실패 (다른 앱 사용 여부 확인)";SetWindowTextW(bindingControl,text.c_str());
}
int registrationStatus(){int n=registerKeys();refreshBinding();if(n)status(L"단축키 "+std::to_wstring(n)+L"개 등록 실패 · 각 조합을 확인하세요.");return n;}
void endEditing(){if(editing){editing=false;registerKeys();}}
LRESULT CALLBACK hotkeyProc(HWND w,UINT msg,WPARAM wp,LPARAM lp,UINT_PTR,DWORD_PTR){
    if(msg==WM_SETFOCUS){editing=true;unregisterKeys();status(L"단축키 편집 중 · Ctrl이 포함된 조합을 입력하고 저장하세요.");}
    if(msg==WM_KILLFOCUS)PostMessageW(ui,WM_APP+4,0,0);
    return DefSubclassProc(w,msg,wp,lp);
}
bool save(const Settings&candidate){
    if(readOnly){status(L"설정 파일을 보존 중입니다. 파일을 확인한 뒤 앱을 다시 실행하세요.");return false;}
    std::wstring temp=configPath+L".tmp";auto bytes=serialize(candidate);HANDLE file=CreateFileW(temp.c_str(),GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE){status(L"설정 파일을 열 수 없습니다. 이전 설정을 유지합니다.");return false;}
    DWORD written=0;bool ok=WriteFile(file,bytes.data(),static_cast<DWORD>(bytes.size()),&written,nullptr)&&written==bytes.size()&&FlushFileBuffers(file);CloseHandle(file);
    if(ok)ok=MoveFileExW(temp.c_str(),configPath.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=FALSE;
    if(!ok){DeleteFileW(temp.c_str());status(L"설정 저장 실패 · 이전 설정을 유지합니다.");return false;}settings=candidate;return true;
}
void load(){
    PWSTR base=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&base))){readOnly=true;loadWarning=L"사용자 설정 경로를 찾지 못했습니다. 변경은 저장하지 않습니다.";return;}
    configPath=std::wstring(base)+L"\\LightSnap";CoTaskMemFree(base);
    if(!CreateDirectoryW(configPath.c_str(),nullptr)&&GetLastError()!=ERROR_ALREADY_EXISTS){readOnly=true;loadWarning=L"설정 폴더를 만들지 못했습니다.";}
    configPath+=L"\\settings.ini";
    HANDLE file=CreateFileW(configPath.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE){if(GetLastError()!=ERROR_FILE_NOT_FOUND){readOnly=true;loadWarning=L"설정을 읽을 수 없어 변경을 저장하지 않습니다.";}return;}
    LARGE_INTEGER size{};DWORD count=0;bool ok=GetFileSizeEx(file,&size)&&size.QuadPart>=0&&size.QuadPart<=65536;
    std::string bytes(ok?static_cast<size_t>(size.QuadPart):0,'\0');if(ok)ok=ReadFile(file,bytes.data(),static_cast<DWORD>(bytes.size()),&count,nullptr)&&count==bytes.size();CloseHandle(file);
    try{if(!ok)throw std::runtime_error("read failed");settings=parse(bytes);}catch(...){readOnly=true;loadWarning=L"설정 형식이 손상되었거나 더 새 버전입니다. 원본을 보존하며 기본값으로 실행합니다.";}
}
const wchar_t* runKey=L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
bool startupEnabled(){HKEY key{};if(RegOpenKeyExW(HKEY_CURRENT_USER,runKey,0,KEY_QUERY_VALUE,&key)!=ERROR_SUCCESS)return false;
    wchar_t value[32768]{};DWORD type=0,size=sizeof(value);auto result=RegQueryValueExW(key,L"LightSnap",nullptr,&type,reinterpret_cast<BYTE*>(value),&size);RegCloseKey(key);value[32767]=0;
    return result==ERROR_SUCCESS&&type==REG_SZ&&std::wstring(value)==L"\""+exePath()+L"\" --background";
}
bool setStartup(bool enabled){HKEY key{};LONG result=RegCreateKeyExW(HKEY_CURRENT_USER,runKey,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr);
    if(result==ERROR_SUCCESS){if(enabled){auto path=exePath();if(path.empty()){RegCloseKey(key);return false;}std::wstring command=L"\""+path+L"\" --background";result=RegSetValueExW(key,L"LightSnap",0,REG_SZ,reinterpret_cast<const BYTE*>(command.c_str()),static_cast<DWORD>((command.size()+1)*sizeof(wchar_t)));}
    else{result=RegDeleteValueW(key,L"LightSnap");if(result==ERROR_FILE_NOT_FOUND)result=ERROR_SUCCESS;}RegCloseKey(key);}return result==ERROR_SUCCESS;
}
bool eligible(HWND w){if(!w||!IsWindow(w)||w==ui||w==GetDesktopWindow()||w==GetShellWindow()||!IsWindowVisible(w)||IsIconic(w))return false;
    DWORD pid=0;GetWindowThreadProcessId(w,&pid);if(pid==GetCurrentProcessId())return false;
    wchar_t cls[128]{};GetClassNameW(w,cls,128);if(!wcscmp(cls,L"Shell_TrayWnd")||!wcscmp(cls,L"Shell_SecondaryTrayWnd"))return false;
    DWORD cloaked=0;if(SUCCEEDED(DwmGetWindowAttribute(w,DWMWA_CLOAKED,&cloaked,sizeof(cloaked)))&&cloaked)return false;
    return GetAncestor(w,GA_ROOT)==w;
}
void CALLBACK onForeground(HWINEVENTHOOK,DWORD,HWND w,LONG,LONG,DWORD,DWORD){if(eligible(w))lastExternal=w;}
void CALLBACK onDestroy(HWINEVENTHOOK,DWORD,HWND w,LONG object,LONG child,DWORD,DWORD){if(object==OBJID_WINDOW&&child==0&&w){std::lock_guard<std::mutex> lock(destroyMutex);if(destroyed.size()<512)destroyed.insert(w);else historyInvalidated=true;}}
bool visibleFrame(HWND w,Rect&out){RECT r{};if(SUCCEEDED(DwmGetWindowAttribute(w,DWMWA_EXTENDED_FRAME_BOUNDS,&r,sizeof(r)))){out=rect(r);return out.w>0&&out.h>0;}if(GetWindowRect(w,&r)){out=rect(r);return out.w>0&&out.h>0;}return false;}
struct Saved { HWND window;DWORD pid,thread;WINDOWPLACEMENT placement;Rect visible,screen; };
std::deque<Saved> history;Cycle cycle;
void pruneHistory(){std::set<HWND> gone;{std::lock_guard<std::mutex>lock(destroyMutex);gone.swap(destroyed);if(historyInvalidated){history.clear();cycle.reset();historyInvalidated=false;}}if(gone.count(reinterpret_cast<HWND>(cycle.window)))cycle.reset();history.erase(std::remove_if(history.begin(),history.end(),[&](const Saved&s){DWORD pid=0;auto tid=GetWindowThreadProcessId(s.window,&pid);return gone.count(s.window)||!IsWindow(s.window)||pid!=s.pid||tid!=s.thread;}),history.end());}
bool waitFrame(HWND w,Rect target){for(int i=0;i<24;++i){Rect actual;if(visibleFrame(w,actual)&&closeTo(actual,target))return true;Sleep(10);}return false;}
bool moveFrame(HWND w,Rect target){
    if(IsZoomed(w)){ShowWindowAsync(w,SW_RESTORE);for(int i=0;i<20&&IsZoomed(w);++i)Sleep(10);if(IsZoomed(w))return false;}
    // A cross-monitor move can change invisible frame margins at the destination DPI.
    for(int attempt=0;attempt<2;++attempt){
        RECT outer{};Rect current{};if(!GetWindowRect(w,&outer)||!visibleFrame(w,current))return false;
        int left=current.x-outer.left,top=current.y-outer.top,right=outer.right-current.x-current.w,bottom=outer.bottom-current.y-current.h;
        if(!SetWindowPos(w,nullptr,target.x-left,target.y-top,target.w+left+right,target.h+top+bottom,SWP_NOZORDER|SWP_NOACTIVATE|SWP_ASYNCWINDOWPOS))return false;
        if(waitFrame(w,target))return true;
    }
    return false;
}
void complete(std::wstring text,bool success,double ms){
    {std::lock_guard<std::mutex>lock(resultMutex);pendingResult=std::move(text);pendingSuccess=success;pendingLatency=ms;}
    PostMessageW(ui,WM_RESULT,0,0);
}
void snap(HWND w,int action,std::vector<Monitor> screens,bool cycling){
    auto start=std::chrono::steady_clock::now();bool ok=false;std::wstring message;
    try{
        pruneHistory();if(!eligible(w)||screens.empty())throw std::runtime_error("target");
        Rect current;if(!visibleFrame(w,current))throw std::runtime_error("frame");
        HMONITOR hm=MonitorFromWindow(w,MONITOR_DEFAULTTONEAREST);auto at=std::find_if(screens.begin(),screens.end(),[&](const Monitor&m){return m.handle==hm;});if(at==screens.end())at=screens.begin();
        LONG_PTR style=GetWindowLongPtrW(w,GWL_STYLE);
        if(!(style&WS_THICKFRAME)||(!(style&WS_CAPTION)&&closeTo(current,at->full)))throw std::runtime_error("unsupported");
        auto found=std::find_if(history.begin(),history.end(),[&](const Saved&s){return s.window==w;});
        if(action==20){
            if(found==history.end()){cycle.reset();complete(L"복원할 배치가 없습니다. 먼저 이 창을 스냅하세요.",false,0);return;}
            Saved original=*found;auto originalScreen=std::find_if(screens.begin(),screens.end(),[&](const Monitor&m){return m.work==original.screen;});
            if(originalScreen!=screens.end()){
                WINDOWPLACEMENT placement=original.placement;placement.flags|=WPF_ASYNCWINDOWPLACEMENT;
                if(SetWindowPlacement(w,&placement)){
                    if(placement.showCmd==SW_SHOWMAXIMIZED){for(int i=0;i<24;++i){Rect restored{};if(IsZoomed(w)&&visibleFrame(w,restored)&&closeTo(restored,original.visible)){ok=true;break;}Sleep(10);}}
                    else ok=waitFrame(w,original.visible);
                }
            }else {Rect target=transfer(original.visible,original.screen,at->work);ok=moveFrame(w,target);}
            if(ok)history.erase(found);cycle.reset();message=ok?L"원래 배치 복원 완료":L"복원을 확인하지 못했습니다. 이력을 유지합니다.";
        }else{
            if(found==history.end()){
                Saved original{};original.window=w;original.thread=GetWindowThreadProcessId(w,&original.pid);original.placement.length=sizeof(WINDOWPLACEMENT);
                if(!GetWindowPlacement(w,&original.placement))throw std::runtime_error("placement");original.visible=current;original.screen=at->work;
                if(history.size()>=128)history.pop_front();history.push_back(original);
            }
            int step=cycle.next(reinterpret_cast<uintptr_t>(w),action,at->work,current,cycling);Rect target;
            if(action==21){if(screens.size()<2){cycle.reset();complete(L"연결된 모니터가 하나입니다.",false,0);return;}auto index=(static_cast<size_t>(at-screens.begin())+1)%screens.size();target=transfer(current,at->work,screens[index].work);}
            else target=layout(action,at->work,step);
            ok=moveFrame(w,target);Rect actual;if(ok&&visibleFrame(w,actual))cycle.commit(reinterpret_cast<uintptr_t>(w),action,at->work,actual,step);else cycle.reset();
            message=ok?std::wstring(names[action])+L" 완료":L"창 배치 확인 실패 · 최소 크기 제한, 관리자 앱 또는 창 상태를 확인하세요. 복원 이력은 유지합니다.";
        }
    }catch(...){cycle.reset();message=L"이 창은 제어할 수 없습니다. 일반 데스크톱 앱의 크기 조절 가능한 창을 선택하세요.";}
    double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();complete(message,ok,ms);
}
void requestSnap(int action){if(paused||editing||action<0||action>=22)return;++received;
    if(busy.exchange(true)){status(L"이전 창 배치를 처리 중입니다.");return;}
    if(worker.joinable())worker.join();HWND target=GetForegroundWindow();DWORD foregroundPID=0;GetWindowThreadProcessId(target,&foregroundPID);if(foregroundPID==GetCurrentProcessId())target=lastExternal.load();auto screens=monitors();bool cycling=settings.cycle;
    worker=std::thread([=]{snap(target,action,screens,cycling);});
}
void diagnostics(){PROCESS_MEMORY_COUNTERS_EX m{};m.cb=sizeof(m);GetProcessMemoryInfo(GetCurrentProcess(),reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&m),sizeof(m));
    auto sorted=std::vector<double>(latencies.begin(),latencies.end());std::sort(sorted.begin(),sorted.end());
    std::wstring text=L"LightSnap Windows 0.1.1 (x64)\n";
    text+=L"작업 집합: "+std::to_wstring(m.WorkingSetSize/1024/1024)+L" MiB\n전용 메모리: "+std::to_wstring(m.PrivateUsage/1024/1024)+L" MiB\n";
    text+=L"단축키 수신: "+std::to_wstring(received)+L" · 완료: "+std::to_wstring(successful)+L" · 실패: "+std::to_wstring(failed)+L"\n";
    if(!sorted.empty())text+=L"최근 성공 "+std::to_wstring(sorted.size())+L"건 p95: "+std::to_wstring(static_cast<int>(std::ceil(sorted[static_cast<size_t>(std::ceil(sorted.size()*.95))-1])))+L" ms\n";
    int n=0;for(int i=0;i<22;++i)if(settings.bindings[i].key&&!registered[i])++n;text+=L"현재 미등록 단축키: "+std::to_wstring(n)+L" (일시 정지·편집 중에는 등록 해제)\n\n"+lastStatus;
    text+=L"\n\n진단은 요청할 때만 수집합니다. 파일 저장·서버 전송은 하지 않습니다.";MessageBoxW(ui,text.c_str(),L"LightSnap 진단",MB_OK);
}
void addTray(){tray={};tray.cbSize=sizeof(tray);tray.hWnd=ui;tray.uID=1;tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;tray.uCallbackMessage=WM_TRAY;tray.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));if(!tray.hIcon)tray.hIcon=LoadIconW(nullptr,IDI_APPLICATION);wcscpy_s(tray.szTip,L"LightSnap · Ctrl+Alt+방향키");Shell_NotifyIconW(NIM_ADD,&tray);tray.uVersion=NOTIFYICON_VERSION_4;Shell_NotifyIconW(NIM_SETVERSION,&tray);}
void show(){ShowWindow(ui,SW_SHOWNORMAL);SetForegroundWindow(ui);}
void trayMenu(){HMENU menu=CreatePopupMenu();AppendMenuW(menu,MF_STRING,1,L"설정 열기");AppendMenuW(menu,MF_STRING,2,paused?L"스냅 다시 시작":L"스냅 일시 정지");AppendMenuW(menu,MF_STRING,3,L"진단");AppendMenuW(menu,MF_SEPARATOR,0,nullptr);AppendMenuW(menu,MF_STRING,4,L"종료");POINT p{};GetCursorPos(&p);SetForegroundWindow(ui);int choice=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,p.x,p.y,0,ui,nullptr);DestroyMenu(menu);PostMessageW(ui,WM_NULL,0,0);
    if(choice==1)show();if(choice==2)SendMessageW(ui,WM_COMMAND,ID_PAUSE,0);if(choice==3)diagnostics();if(choice==4)SendMessageW(ui,WM_COMMAND,ID_QUIT,0);
}
HWND control(const wchar_t*cls,const wchar_t*text,DWORD style,int id){return CreateWindowExW(0,cls,text,WS_CHILD|WS_VISIBLE|style,0,0,10,10,ui,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),instance,nullptr);}
void arrange(){UINT dpi=GetDpiForWindow(ui);auto px=[&](int n){return MulDiv(n,static_cast<int>(dpi),96);};
    if(font)DeleteObject(font);font=CreateFontW(-px(15),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    EnumChildWindows(ui,[](HWND child,LPARAM data)->BOOL{SendMessageW(child,WM_SETFONT,static_cast<WPARAM>(data),TRUE);return TRUE;},reinterpret_cast<LPARAM>(font));
    auto pos=[&](int id,int x,int y,int w,int h){MoveWindow(GetDlgItem(ui,id),px(x),px(y),px(w),px(h),TRUE);};
    pos(201,24,20,590,28);pos(202,24,54,590,48);pos(ID_ACTION,24,112,260,350);pos(ID_KEY,300,112,230,30);pos(203,24,158,580,26);
    pos(ID_SAVE,24,194,140,32);pos(ID_DISABLE,176,194,140,32);pos(ID_DEFAULT,328,194,200,32);
    pos(ID_CYCLE,24,250,590,26);pos(ID_STARTUP,24,286,590,26);pos(204,24,320,590,46);pos(205,24,380,590,65);
    pos(ID_PAUSE,24,470,180,34);pos(ID_DIAG,216,470,140,34);pos(ID_QUIT,448,470,140,34);
}
LRESULT CALLBACK wndproc(HWND w,UINT msg,WPARAM wp,LPARAM lp){
    if(msg==taskbarCreated&&taskbarCreated){addTray();return 0;}
    switch(msg){
    case WM_CREATE:{ui=w;
        control(L"STATIC",L"LightSnap Windows · 0.1.1",0,201);control(L"STATIC",L"Ctrl+Alt+방향키로 창 배치 · 설정을 닫아도 트레이에서 실행됩니다.",0,202);
        combo=control(WC_COMBOBOXW,L"",CBS_DROPDOWNLIST|WS_TABSTOP|WS_VSCROLL,ID_ACTION);for(auto name:names)SendMessageW(combo,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(name));SendMessageW(combo,CB_SETCURSEL,0,0);
        keyControl=control(HOTKEY_CLASSW,L"",WS_BORDER|WS_TABSTOP,ID_KEY);SetWindowSubclass(keyControl,hotkeyProc,1,0);
        bindingControl=control(L"STATIC",L"",0,203);control(L"BUTTON",L"단축키 저장",WS_TABSTOP,ID_SAVE);control(L"BUTTON",L"이 동작 해제",WS_TABSTOP,ID_DISABLE);control(L"BUTTON",L"전체 단축키 기본값",WS_TABSTOP,ID_DEFAULT);
        cycleControl=control(L"BUTTON",L"같은 좌우 단축키 반복: 1/2 → 2/3 → 1/3",BS_AUTOCHECKBOX|WS_TABSTOP,ID_CYCLE);SendMessageW(cycleControl,BM_SETCHECK,settings.cycle?BST_CHECKED:BST_UNCHECKED,0);
        startupControl=control(L"BUTTON",L"로그인할 때 실행 (현재 EXE 경로로 등록)",BS_AUTOCHECKBOX|WS_TABSTOP,ID_STARTUP);SendMessageW(startupControl,BM_SETCHECK,startupEnabled()?BST_CHECKED:BST_UNCHECKED,0);
        control(L"STATIC",L"Windows 시작 앱에서 차단한 경우 별도 허용이 필요합니다.\nEXE를 옮기면 자동 실행을 다시 등록하세요.",0,204);
        statusControl=control(L"STATIC",lastStatus.c_str(),0,205);pauseControl=control(L"BUTTON",L"일시 정지",WS_TABSTOP,ID_PAUSE);control(L"BUTTON",L"진단 보기",WS_TABSTOP,ID_DIAG);control(L"BUTTON",L"종료",WS_TABSTOP,ID_QUIT);
        arrange();return 0;}
    case WM_DPICHANGED:{RECT*r=reinterpret_cast<RECT*>(lp);SetWindowPos(w,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE);arrange();return 0;}
    case WM_SHOW:endEditing();show();return 0;
    case WM_CLOSE:ShowWindow(w,SW_HIDE);endEditing();return 0;
    case WM_APP+4:if(GetFocus()!=keyControl)endEditing();return 0;
    case WM_HOTKEY:requestSnap(static_cast<int>(wp)-1000);return 0;
    case WM_RESULT:{if(worker.joinable())worker.join();busy=false;std::lock_guard<std::mutex>lock(resultMutex);status(pendingResult);if(pendingSuccess){++successful;latencies.push_back(pendingLatency);if(latencies.size()>100)latencies.pop_front();}else ++failed;return 0;}
    case WM_TRAY:{auto event=LOWORD(lp);if(event==WM_CONTEXTMENU||event==WM_RBUTTONUP)trayMenu();else if(event==NIN_SELECT||event==NIN_KEYSELECT||event==WM_LBUTTONDBLCLK)show();return 0;}
    case WM_COMMAND:{int id=LOWORD(wp);
        if(id==ID_ACTION&&HIWORD(wp)==CBN_SELCHANGE){endEditing();refreshBinding();return 0;}
        if(id==ID_SAVE||id==ID_DISABLE){int i=static_cast<int>(SendMessageW(combo,CB_GETCURSEL,0,0));if(i<0||i>=22)return 0;
            WORD raw=static_cast<WORD>(SendMessageW(keyControl,HKM_GETHOTKEY,0,0));unsigned f=HIBYTE(raw);Binding b{id==ID_DISABLE?0u:static_cast<unsigned>(LOBYTE(raw)),id==ID_DISABLE?0u:((f&HOTKEYF_CONTROL)?2u:0u)|((f&HOTKEYF_ALT)?1u:0u)|((f&HOTKEYF_SHIFT)?4u:0u)};
            if(!valid(b)){status(L"Ctrl이 포함된 조합을 입력하세요. Windows 키 조합은 지원하지 않습니다.");return 0;}
            if(conflicts(settings,static_cast<size_t>(i),b)){status(L"다른 동작에 사용 중인 조합입니다. 기존 설정을 유지합니다.");return 0;}
            auto candidate=settings;candidate.bindings[i]=b;editing=false;unregisterKeys();
            if(b.key&&!RegisterHotKey(ui,2000,b.mods|MOD_NOREPEAT,b.key)){registrationStatus();status(L"다른 앱이 사용 중인 단축키입니다. 기존 설정을 유지합니다.");return 0;}UnregisterHotKey(ui,2000);
            if(save(candidate)){if(registrationStatus()==0)status(L"단축키 저장 완료");}else registrationStatus();return 0;
        }
        if(id==ID_DEFAULT){if(MessageBoxW(ui,L"모든 단축키를 기본값으로 바꿀까요?",L"LightSnap",MB_YESNO|MB_ICONQUESTION)==IDYES){auto candidate=defaults();candidate.cycle=settings.cycle;if(save(candidate)){endEditing();registrationStatus();}}return 0;}
        if(id==ID_CYCLE){auto candidate=settings;candidate.cycle=SendMessageW(cycleControl,BM_GETCHECK,0,0)==BST_CHECKED;if(!save(candidate))SendMessageW(cycleControl,BM_SETCHECK,settings.cycle?BST_CHECKED:BST_UNCHECKED,0);return 0;}
        if(id==ID_STARTUP){bool enabled=SendMessageW(startupControl,BM_GETCHECK,0,0)==BST_CHECKED;bool ok=setStartup(enabled);SendMessageW(startupControl,BM_SETCHECK,startupEnabled()?BST_CHECKED:BST_UNCHECKED,0);status(ok?(enabled?L"자동 실행 등록됨 · Windows 시작 앱 설정의 차단 상태도 확인하세요.":L"자동 실행 해제됨"):L"자동 실행 변경 실패 · 사용자 레지스트리 접근을 확인하세요.");return 0;}
        if(id==ID_PAUSE){paused=!paused;SetWindowTextW(pauseControl,paused?L"다시 시작":L"일시 정지");endEditing();int failures=registrationStatus();if(paused||failures==0)status(paused?L"스냅 일시 정지됨":L"스냅 다시 시작됨");return 0;}
        if(id==ID_DIAG){diagnostics();return 0;}
        if(id==ID_QUIT){unregisterKeys();if(foregroundHook)UnhookWinEvent(foregroundHook);if(destroyHook)UnhookWinEvent(destroyHook);if(worker.joinable())worker.join();Shell_NotifyIconW(NIM_DELETE,&tray);DestroyWindow(w);return 0;}break;}
    case WM_DESTROY:if(font)DeleteObject(font);PostQuitMessage(0);return 0;
    }return DefWindowProcW(w,msg,wp,lp);
}
}
int WINAPI wWinMain(HINSTANCE inst,HINSTANCE,PWSTR command,int){
    instance=inst;
    // Does not create UI, touch settings/registry, or register global hotkeys.
    if(command&&wcscmp(command,L"--self-test")==0){
        try{
            if(serialize(parse(serialize(defaults())))!=serialize(defaults()))return 1;
            HWND test=CreateWindowExW(0,L"STATIC",L"LightSnap isolated self-test",WS_OVERLAPPEDWINDOW,0,0,100,100,nullptr,nullptr,inst,nullptr);
            if(!test)return 2;
            RECT actual{};bool ok=SetWindowPos(test,nullptr,50,60,700,500,SWP_NOZORDER|SWP_NOACTIVATE)&&GetWindowRect(test,&actual);
            ok=ok&&rect(actual)==Rect{50,60,700,500};DestroyWindow(test);if(!ok)return 3;
            wchar_t temp[MAX_PATH]{},path[MAX_PATH]{};
            if(!GetTempPathW(MAX_PATH,temp)||!GetTempFileNameW(temp,L"lsn",0,path))return 4;
            configPath=path;auto candidate=defaults();candidate.bindings[0]={};
            ok=save(candidate);HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
            char bytes[4096]{};DWORD count=0;ok=ok&&f!=INVALID_HANDLE_VALUE;
            if(f!=INVALID_HANDLE_VALUE){ok=ok&&ReadFile(f,bytes,sizeof(bytes),&count,nullptr);CloseHandle(f);}
            DeleteFileW(path);if(!ok)return 5;
            return parse(std::string(bytes,count)).bindings[0].key==0?0:6;
        }catch(...){return 7;}
    }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HANDLE singleton=CreateMutexW(nullptr,FALSE,L"Local\\LightSnap.Windows.0.1");if(!singleton)return 1;
    if(GetLastError()==ERROR_ALREADY_EXISTS){HWND existing=FindWindowW(L"LightSnapWindows",nullptr);if(existing)PostMessageW(existing,WM_SHOW,0,0);CloseHandle(singleton);return 0;}
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_WIN95_CLASSES};InitCommonControlsEx(&common);load();
    WNDCLASSEXW cls{};cls.cbSize=sizeof(cls);cls.lpfnWndProc=wndproc;cls.hInstance=instance;cls.lpszClassName=L"LightSnapWindows";cls.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);cls.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);
    if(!RegisterClassExW(&cls)){CloseHandle(singleton);return 1;}
    UINT dpi=GetDpiForSystem();RECT bounds{0,0,MulDiv(640,dpi,96),MulDiv(535,dpi,96)};AdjustWindowRectExForDpi(&bounds,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,FALSE,0,dpi);
    ui=CreateWindowExW(0,cls.lpszClassName,L"LightSnap Windows",WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,CW_USEDEFAULT,CW_USEDEFAULT,bounds.right-bounds.left,bounds.bottom-bounds.top,nullptr,nullptr,instance,nullptr);
    if(!ui){CloseHandle(singleton);return 1;}taskbarCreated=RegisterWindowMessageW(L"TaskbarCreated");addTray();
    foregroundHook=SetWinEventHook(EVENT_SYSTEM_FOREGROUND,EVENT_SYSTEM_FOREGROUND,nullptr,onForeground,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    destroyHook=SetWinEventHook(EVENT_OBJECT_DESTROY,EVENT_OBJECT_DESTROY,nullptr,onDestroy,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    HWND current=GetForegroundWindow();if(eligible(current))lastExternal=current;registrationStatus();
    if(!foregroundHook||!destroyHook)status(L"창 이벤트 감시 등록 실패 · 외부 앱에서 단축키를 실행하세요. 앱을 다시 시작해 주세요.");
    if(!loadWarning.empty())status(loadWarning);
    if(!command||wcscmp(command,L"--background")!=0)show();
    MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){if(!IsDialogMessageW(ui,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}}
    CloseHandle(singleton);return 0;
}
