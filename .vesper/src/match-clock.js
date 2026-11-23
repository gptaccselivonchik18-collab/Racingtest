const paceModes = [
    {name:'Instant', minutes:1, analysisMs:850},
    {name:'Medium', minutes:3, analysisMs:2400},
    {name:'Hard', minutes:10, analysisMs:6500}
];
const paceIndex = value => Number.isInteger(value) && paceModes[value] ? value : 1;
const paceMilliseconds = index => paceModes[paceIndex(index)].minutes * 60000;

class MatchClock {
    constructor(preset, state){
        this.preset=paceIndex(preset);
        const duration=paceMilliseconds(this.preset);
        this.remaining={w:duration,b:duration};
        this.history=[{...this.remaining}];
        this.flagged=null;
        this.running=null;
        if(state){
            this.remaining={...state.remaining};
            this.history=state.history.map(item=>({...item}));
            this.flagged=state.flagged;
        }
    }
    static restore(state,ply){
        const validTime=entry=>['w','b'].every(side=>Number.isFinite(entry?.[side])&&entry[side]>=0);
        if(!state||!validTime(state.remaining)||!Array.isArray(state.history)||
           state.history.length!==ply+1||!state.history.every(validTime))return null;
        return new MatchClock(state.preset,state);
    }
    read(now=performance.now()){
        const values={...this.remaining};
        if(this.running)values[this.running]=Math.max(0,values[this.running]-Math.max(0,now-this.since));
        return values;
    }
    resume(side,now=performance.now()){
        if(this.running===side||this.flagged)return;
        this.pause(now);
        this.running=side;
        this.since=now;
    }
    pause(now=performance.now()){
        this.remaining=this.read(now);
        this.running=null;
    }
    played(now=performance.now()){
        this.pause(now);
        this.history.push({...this.remaining});
    }
    rewind(ply){
        this.running=null;
        this.flagged=null;
        this.history=this.history.slice(0,ply+1);
        this.remaining={...this.history[ply]};
    }
    export(){
        return {preset:this.preset,remaining:this.read(),history:this.history,flagged:this.flagged};
    }
}

function clockText(ms){
    const seconds=Math.ceil(ms/1000);
    const whole=Math.floor(seconds/60)+':'+String(seconds%60).padStart(2,'0');
    if(ms>=10000||ms<=0) return whole;
    return '0:'+String(Math.floor(ms/1000)).padStart(2,'0')+'.'+Math.floor(ms%1000/100);
}

function engineTime(values,side,limit=Infinity){
    const remaining=Math.floor(values[side]);
    if(remaining<=0)return null;
    // Keep time for the browser to deliver bestmove and update the board.
    const reserve=Math.min(180,Math.max(30,Math.floor(remaining*0.12)));
    return {w:Math.max(1,Math.floor(values.w)),b:Math.max(1,Math.floor(values.b)),
            cap:Math.max(1,Math.min(limit,remaining-reserve))};
}

function paceSlider(id,index,legend='Темп партии'){
    const labels=paceModes.map((mode,i)=>'<button type="button" data-pace="'+i+'" aria-pressed="'+
        (i===index)+'"><strong>'+mode.name+'</strong><small>'+mode.minutes+' мин</small></button>').join('');
    return '<fieldset id="'+id+'" class="pace"><legend>'+legend+'</legend>'+
        '<div class="pace-options">'+labels+'</div>'+
        '<input type="range" min="0" max="2" value="'+index+
        '" aria-label="'+legend+'" aria-valuetext="'+paceModes[index].name+' '+paceModes[index].minutes+
        ' мин" style="--pace-fill:'+index*50+'%"></fieldset>';
}

function connectPaceSlider(id,onChange){
    const group=document.getElementById(id);
    const range=group.querySelector('input');
    const buttons=[...group.querySelectorAll('button')];
    function sync(index){
        range.value=index;
        range.style.setProperty('--pace-fill',index*50+'%');
        range.setAttribute('aria-valuetext',paceModes[index].name+' '+paceModes[index].minutes+' мин');
        buttons.forEach((button,i)=>button.setAttribute('aria-pressed',String(i===index)));
        onChange(index);
    }
    range.oninput=()=>sync(Number(range.value));
    buttons.forEach((button,i)=>{button.onclick=()=>sync(i);});
}

if(typeof module!=='undefined')module.exports={MatchClock,paceModes,engineTime,clockText};
