export const layouts = {
  left: [0,0,.5,1], right: [.5,0,.5,1], top: [0,0,1,.5], bottom: [0,.5,1,.5],
  topLeft: [0,0,.5,.5], topRight: [.5,0,.5,.5], bottomLeft: [0,.5,.5,.5], bottomRight: [.5,.5,.5,.5],
  firstThird: [0,0,1/3,1], middleThird: [1/3,0,1/3,1], lastThird: [2/3,0,1/3,1],
  leftTwoThirds: [0,0,2/3,1], rightTwoThirds: [1/3,0,2/3,1],
  cell1: [0,0,1/3,.5], cell2: [1/3,0,1/3,.5], cell3: [2/3,0,1/3,.5],
  cell4: [0,.5,1/3,.5], cell5: [1/3,.5,1/3,.5], cell6: [2/3,.5,1/3,.5], maximize: [0,0,1,1]
};
export const titles = {left:'왼쪽 ½',right:'오른쪽 ½',top:'위쪽 ½',bottom:'아래쪽 ½',topLeft:'왼쪽 위',topRight:'오른쪽 위',bottomLeft:'왼쪽 아래',bottomRight:'오른쪽 아래',firstThird:'왼쪽 ⅓',middleThird:'가운데 ⅓',lastThird:'오른쪽 ⅓',leftTwoThirds:'왼쪽 ⅔',rightTwoThirds:'오른쪽 ⅔',cell1:'위 1',cell2:'위 2',cell3:'위 3',cell4:'아래 1',cell5:'아래 2',cell6:'아래 3',maximize:'최대화',restore:'원래 배치 복원',nextDisplay:'다음 모니터'};
export function createState(){return {active:'code',displayCount:1,cycling:true,last:null,message:'배치 버튼을 눌러 Code 창부터 정리해 보세요.',windows:[
  {id:'notes',name:'Notes',monitor:0,rect:[.08,.08,.53,.69],original:null,z:1},
  {id:'browser',name:'Browser',monitor:0,rect:[.4,.24,.53,.68],original:null,z:2},
  {id:'code',name:'Code',monitor:0,rect:[.16,.16,.59,.73],original:null,z:3}
]};}
const copy = value => structuredClone(value);
export function selectWindow(state,id){const s=copy(state);const w=s.windows.find(w=>w.id===id);if(!w)return s;s.active=id;w.z=Math.max(...s.windows.map(w=>w.z))+1;s.message=`${w.name} 선택됨 · 배치할 영역을 선택하세요.`;return s;}
export function setDisplays(state,count){if(count!==1&&count!==2)return state;const s=copy(state);s.displayCount=count;s.last=null;for(const w of s.windows)if(w.monitor>=count)w.monitor=0;s.message=count===2?'모니터 2개 · 다음 모니터 버튼으로 선택한 창을 옮겨 보세요.':'모니터 1개 · 모든 창이 기본 화면에 있습니다.';return s;}
export function setCycling(state,enabled){const s=copy(state);s.cycling=!!enabled;s.last=null;s.message=enabled?'좌우 반복: ½ → ⅔ → ⅓ 순환':'좌우 단축키가 항상 ½ 크기로 배치합니다.';return s;}
export function applyAction(state,action){
 const s=copy(state),w=s.windows.find(w=>w.id===s.active);if(!w)return s;
 if(action==='nextDisplay'){
  s.last=null;if(s.displayCount<2){s.message='먼저 모니터를 2개로 바꿔 주세요.';return s;}
  w.original??={rect:[...w.rect],monitor:w.monitor};w.monitor=(w.monitor+1)%s.displayCount;s.message=`${w.name} → ${w.monitor===0?'기본':'보조'} 모니터 · 상대 크기 유지`;return s;
 }
 if(action==='restore'){
  s.last=null;if(!w.original){s.message='이 창의 저장된 원래 배치가 없습니다.';return s;}
  w.rect=[...w.original.rect];w.monitor=Math.min(w.original.monitor,s.displayCount-1);w.original=null;s.message=`${w.name} · 최초 배치로 복원`;return s;
 }
 if(!layouts[action])return s;
 let actual=action,index=0;
 if(s.cycling&&(action==='left'||action==='right')){
  const previous=s.last;
  if(previous?.id===w.id&&previous.action===action&&previous.monitor===w.monitor&&previous.rect.every((v,i)=>Math.abs(v-w.rect[i])<1e-6))index=(previous.index+1)%3;
  actual=(action==='left'?['left','leftTwoThirds','firstThird']:['right','rightTwoThirds','lastThird'])[index];
 }
 w.original??={rect:[...w.rect],monitor:w.monitor};w.rect=[...layouts[actual]];w.z=Math.max(...s.windows.map(w=>w.z))+1;
 s.last=s.cycling&&(action==='left'||action==='right')?{id:w.id,action,index,monitor:w.monitor,rect:[...w.rect]}:null;
 s.message=`${w.name} · ${titles[actual]} 배치 완료`;return s;
}
