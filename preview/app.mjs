import {layouts,titles,createState,selectWindow,setDisplays,setCycling,applyAction} from './model.mjs';
let state=createState(),group='halves',renderedDisplays=0;
const board=document.querySelector('#desktop-board'),picker=document.querySelector('#app-picker');
const icons={notes:'≡',browser:'◉',code:'⌘'};
const groups={halves:['left','right','top','bottom'],quarters:['topLeft','topRight','bottomLeft','bottomRight'],sixths:['cell1','cell2','cell3','cell4','cell5','cell6'],thirds:['firstThird','middleThird','lastThird','leftTwoThirds','rightTwoThirds']};
const bodies={
 code:'<span class="code-body window-body"><span class="comment">// A calmer desktop.</span>\n<span class="kw">import</span> AppKit\n\n<span class="kw">let</span> workspace = <span class="str">"focused"</span>\n<span class="kw">let</span> windows = [\n  <span class="str">"code"</span>,\n  <span class="str">"ideas"</span>,\n  <span class="str">"a little room"</span>\n]\n\nsnap(.left)\n<span class="comment">// Back to what matters.</span></span>',
 browser:'<span class="window-body"><span class="browser-address">lightsnap.local / welcome</span><span class="browser-heading">A little order.<br>A lot more focus.</span><span class="fake-line"></span><span class="fake-line short"></span><span class="browser-tile"></span><span class="fake-line"></span><span class="fake-line short"></span></span>',
 notes:'<span class="window-body"><span class="notes-heading">Room to think.</span><span class="notes-row done"><span></span> Clear the clutter</span><span class="notes-row done"><span></span> Find your focus</span><span class="notes-row"><span></span> Make something good</span><span class="fake-line"></span><span class="fake-line short"></span></span>'
};
const windowNodes=new Map();
for(const w of state.windows){
 const pick=document.createElement('button');pick.type='button';pick.dataset.window=w.id;pick.innerHTML=`<span class="app-icon ${w.id}" aria-hidden="true">${icons[w.id]}</span>${w.name}`;pick.addEventListener('click',()=>{state=selectWindow(state,w.id);render();});picker.append(pick);
 const win=document.createElement('button');win.type='button';win.className='mock-window';win.dataset.window=w.id;win.setAttribute('aria-label',`${w.name} 모의 창 선택`);win.innerHTML=`<span class="window-bar"><span class="window-dots" aria-hidden="true"><i></i><i></i><i></i></span>${w.name}<span aria-hidden="true"> · </span><span>${w.id==='code'?'main.swift':w.id==='notes'?'Today':'Welcome'}</span></span>${bodies[w.id]}`;
 win.addEventListener('click',()=>{state=selectWindow(state,w.id);render();board.focus({preventScroll:true});});windowNodes.set(w.id,win);
}
function renderLayouts(){
 const target=document.querySelector('#layout-buttons');target.className=`layout-buttons ${group}`;target.replaceChildren();
 for(const action of groups[group]){const [x,y,w,h]=layouts[action],b=document.createElement('button');b.type='button';b.dataset.action=action;b.innerHTML=`<span class="layout-icon" aria-hidden="true"><i style="left:${x*100}%;top:${y*100}%;width:${w*100}%;height:${h*100}%"></i></span><span>${titles[action]}</span>`;b.addEventListener('click',()=>run(action));target.append(b);}
 for(const tab of document.querySelectorAll('[data-group]'))tab.setAttribute('aria-pressed',String(tab.dataset.group===group));
}
function render(){
 const keepFocus=board.contains(document.activeElement);
 if(renderedDisplays!==state.displayCount){
  board.replaceChildren();board.classList.toggle('two-displays',state.displayCount===2);
  for(let i=0;i<state.displayCount;i++){
   const monitor=document.createElement('div');monitor.className=`monitor ${i===1?'secondary':''}`;monitor.innerHTML=`<div class="monitor-label"><span>${i===0?'MAIN DISPLAY':'SECOND DISPLAY'}</span><span>${i===0?'1512 × 982':'1920 × 1080'}</span></div><div class="screen"><div class="desktop-menubar" aria-hidden="true"><strong>✳</strong><span>LightSnap</span><span>File</span><span>Window</span><time>9:41</time></div><div class="screen-work" data-monitor="${i}"></div><div class="dock" aria-hidden="true"><span>⌘</span><span>≡</span><span>◉</span></div></div>`;board.append(monitor);
  }
  renderedDisplays=state.displayCount;
 }
 for(const w of state.windows){
  const win=windowNodes.get(w.id),container=board.querySelector(`[data-monitor="${w.monitor}"]`);
  if(win.parentElement!==container)container.append(win);
  const [x,y,width,height]=w.rect;
  Object.assign(win.style,{left:`${x*100}%`,top:`${y*100}%`,width:`${width*100}%`,height:`${height*100}%`,zIndex:String(w.z)});
  win.setAttribute('aria-pressed',String(w.id===state.active));
 }
 for(const container of board.querySelectorAll('[data-monitor]')){
  let empty=container.querySelector('.empty-screen');const hasWindows=!!container.querySelector('.mock-window');
  if(!hasWindows&&!empty){empty=document.createElement('div');empty.className='empty-screen';empty.innerHTML='<span><b>↗</b>다음 모니터로 이동해 보세요</span>';container.append(empty);}
  else if(hasWindows&&empty)empty.remove();
 }
 for(const button of picker.querySelectorAll('button'))button.setAttribute('aria-pressed',String(button.dataset.window===state.active));
 document.querySelector('#cycle-toggle').checked=state.cycling;
 const displayToggle=document.querySelector('#display-toggle');displayToggle.setAttribute('aria-pressed',String(state.displayCount===2));displayToggle.innerHTML=`모니터 ${state.displayCount}개 <span aria-hidden="true">${state.displayCount===1?'＋':'−'}</span>`;
 document.querySelector('#status').textContent=state.message;
 document.querySelector('#active-badge').textContent=`ACTIVE: ${state.windows.find(w=>w.id===state.active).name.toUpperCase()}`;
 if(keepFocus)board.focus({preventScroll:true});
}
function run(action){state=applyAction(state,action);render();}
for(const button of document.querySelectorAll('[data-group]'))button.addEventListener('click',()=>{group=button.dataset.group;renderLayouts();});
for(const button of document.querySelectorAll('.utility-buttons [data-action],.monitor-move'))button.addEventListener('click',()=>run(button.dataset.action));
document.querySelector('#cycle-toggle').addEventListener('change',e=>{state=setCycling(state,e.target.checked);render();});
document.querySelector('#display-toggle').addEventListener('click',()=>{state=setDisplays(state,state.displayCount===1?2:1);render();});
document.querySelector('#reset').addEventListener('click',()=>{state=createState();group='halves';renderLayouts();render();});
board.addEventListener('click',e=>{if(!e.target.closest('.mock-window'))board.focus({preventScroll:true});});
board.addEventListener('keydown',e=>{
 if(e.target!==board||e.metaKey||e.altKey||e.ctrlKey||e.shiftKey||e.repeat)return;
 const action={ArrowLeft:'left',ArrowRight:'right',ArrowUp:'top',ArrowDown:'bottom',Enter:'maximize',Backspace:'restore','1':'cell1','2':'cell2','3':'cell3','4':'cell4','5':'cell5','6':'cell6'}[e.key];
 if(action){e.preventDefault();run(action);}
});
renderLayouts();render();
