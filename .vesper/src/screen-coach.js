function openScreenCoach(){
    if (busy) { invalidate(); render(); }
    matchClock?.pause();
    runner.cancel();
    let preset=cfg.preset;
    openDlg('Доска с экрана',
        paceSlider('screen-pace',preset)+
        field('screen-side','Мой цвет',[['w','Белые'],['b','Чёрные']],'w')+
        '<p class="help">Начните со стартовой позиции в теме Chess The Musical. Можно включить захват или загрузить скриншоты по порядку.</p>'+
        '<div class="actions"><button type="button" class="primary" id="screen-start">Захват экрана</button>'+
        '<button type="button" class="soft" id="screen-stop" hidden>Стоп</button></div>'+
        '<label class="field" style="margin-top:.8rem">Скриншоты партии<input id="screen-files" type="file" accept="image/*" multiple></label>'+
        '<button type="button" class="soft" id="screen-notify" hidden>Разрешить уведомления</button>'+
        '<video id="screen-video" muted playsinline aria-label="Предпросмотр захвата" hidden style="width:72px;height:auto;margin-top:.8rem"></video>'+
        '<p id="screen-status" class="help" role="status">Ожидаю доску.</p>'+
        '<p id="screen-time" class="help" hidden></p>'+
        '<p id="screen-result" role="status"></p><p id="screen-history" class="help"></p>');
    const dialog=$('dialog'), side=$('screen-side'), status=$('screen-status');
    const startButton=$('screen-start'), stopButton=$('screen-stop'), files=$('screen-files');
    const notify=$('screen-notify'), video=$('screen-video');
    const resultText=$('screen-result'), history=$('screen-history'), time=$('screen-time');
    const canvas=document.createElement('canvas');
    const context=canvas.getContext('2d',{willReadFrequently:true});
    const engine=new LocalEngine();
    let tracker=chessComVision.track(Chess), stream=null, timer, generation=0, imageMode=false;
    let previousTop, candidate='', position='', pendingFen='', lastAskedFen='';
    let valid=false, notificationRegistration, estimatedClock;
    connectPaceSlider('screen-pace',index=>{
        preset=index;
        lastAskedFen=pendingFen='';
        engine.cancel();
        analyzeCurrent();
    });

    function paintEstimate(){
        time.hidden=!estimatedClock;
        if(!estimatedClock)return;
        const values=estimatedClock.read();
        time.textContent='Оценка без добавления · белые '+clockText(values.w)+' · чёрные '+clockText(values.b);
    }
    function currentBudget(){
        const duration=paceMilliseconds(preset), color=side.value;
        const values=estimatedClock?.read()??{w:duration,b:duration};
        // The external clock is estimated. Leave time to read the hint and play the move.
        values[color]=Math.max(0,values[color]-300);
        const cap=Math.min(paceModes[preset].screenCap,Math.max(40,Math.floor(values[color]*0.07)));
        return engineTime(values,color,cap);
    }

    function recognize(input,width,height){
        const scale=Math.min(1,630/width);
        canvas.width=Math.round(width*scale);
        canvas.height=Math.round(height*scale);
        context.drawImage(input,0,0,canvas.width,canvas.height);
        return chessComVision.readFrame(context.getImageData(0,0,canvas.width,canvas.height),
                                        chessComProfile, previousTop);
    }
    function notification(move,fen){
        if(!notificationRegistration||!document.hidden) return;
        notificationRegistration.showNotification('Vesper Gambit · твой ход',{
            body:move,tag:'vesper-screen-move',data:{fen}
        }).catch(()=>{});
    }
    function clearNotifications(){
        if(typeof notificationRegistration?.getNotifications==='function'){
            notificationRegistration.getNotifications({tag:'vesper-screen-move'})
                .then(items=>items.forEach(item=>item.close())).catch(()=>{});
        }
    }
    function invalidateFrame(){
        if(valid) clearNotifications();
        valid=false;
        candidate='';
    }
    function analyzeCurrent(){
        if(!valid||tracker.game.turn()!==side.value||tracker.game.isGameOver())return;
        const fen=tracker.game.fen();
        if(fen===pendingFen||fen===lastAskedFen) return;
        if(!currentBudget()){
            status.textContent='По оценке, времени на подсказку уже нет.';
            return;
        }
        pendingFen=fen;
        const line=tracker.game.history({verbose:true}).map(move=>move.lan).join(' ');
        engine.run({kind:kind(),hash:Math.min(cfg.hash,64),threads:cfg.threads,pv:1,
            timeControl:currentBudget,
            position:'position startpos'+(line?' moves '+line:''),
            progress:(d,t)=>{if(pendingFen===fen)status.textContent='Движок · '+Math.floor(100*d/t)+'%';},
            status:message=>{if(pendingFen===fen)status.textContent=message;},
            info:()=>{},
            fail:message=>{
                if(pendingFen!==fen)return;
                pendingFen='';
                lastAskedFen=fen;
                status.textContent='Движок: '+message;
            },
            done:uci=>{
                if(pendingFen!==fen)return;
                pendingFen='';
                if(!valid||tracker.game.fen()!==fen)return;
                const move=tracker.game.moves({verbose:true}).find(item=>item.lan===uci);
                if(!move)return;
                lastAskedFen=fen;
                const suggestion=move.san+' · '+move.from+' → '+move.to+
                    (move.promotion?' · '+names[move.promotion]:'');
                resultText.textContent='Последняя подсказка: '+suggestion;
                status.textContent='Доска распознана · твой ход.';
                notification(suggestion,fen);
            }
        });
    }
    function process(hit,stable,runAnalysis){
        if(!hit){
            invalidateFrame();
            status.textContent='Доска не найдена. Проверьте тему и видимость всех клеток.';
            return false;
        }
        previousTop=hit.top;
        const key=hit.labels.join('');
        if(!stable&&key!==candidate&&key!==position){
            invalidateFrame();
            candidate=key;
            return false;
        }
        candidate=key;
        const update=tracker.update(hit.labels);
        if(!update){
            invalidateFrame();
            status.textContent=tracker.flipped===null
                ?'Нужна стартовая позиция или позиция сразу после первого хода белых.'
                :'Ход не подтверждён. Вернитесь к последней распознанной позиции.';
            return false;
        }
        if(key!==position){
            const moves=tracker.game.history();
            history.textContent=moves.length?'Ходы: '+moves.join(' '):'Стартовая позиция';
            position=key;
            pendingFen='';
            resultText.textContent='';
            clearNotifications();
        }
        valid=true;
        if(stream){
            if(!estimatedClock)estimatedClock=new MatchClock(preset);
            if(tracker.game.isGameOver())estimatedClock.pause();
            else estimatedClock.resume(tracker.game.turn());
            paintEstimate();
        }
        status.textContent=tracker.game.isGameOver()?'Партия завершена.'
            :tracker.game.turn()===side.value?'Доска распознана · твой ход.':'Доска распознана · ход соперника.';
        if(runAnalysis) analyzeCurrent();
        return true;
    }
    function stop(reset){
        generation++;
        clearInterval(timer);
        estimatedClock?.pause();
        $('screen-pace').disabled=false;
        if(stream) for(const track of stream.getTracks()) track.stop();
        stream=null;
        video.srcObject=null;
        video.hidden=true;
        stopButton.hidden=true;
        startButton.disabled=false;
        files.disabled=false;
        imageMode=false;
        pendingFen='';
        engine.cancel();
        invalidateFrame();
        if(reset){
            estimatedClock=null;
            tracker=chessComVision.track(Chess);
            previousTop=undefined;
            position='';
            lastAskedFen='';
            history.textContent=resultText.textContent='';
        }
        paintEstimate();
    }

    startButton.hidden=typeof navigator.mediaDevices?.getDisplayMedia!=='function';
    startButton.onclick=async()=>{
        stop(true);
        startButton.disabled=true;
        files.disabled=true;
        $('screen-pace').disabled=true;
        const id=generation;
        try{
            const chosen=await navigator.mediaDevices.getDisplayMedia({video:true,audio:false});
            if(id!==generation){for(const track of chosen.getTracks())track.stop();return;}
            stream=chosen;
            const track=stream.getVideoTracks()[0];
            track.addEventListener('ended',()=>{
                if(id===generation){stop(false);status.textContent='Захват экрана остановлен.';}
            },{once:true});
            video.srcObject=stream;
            video.hidden=false;
            await video.play();
            if(id!==generation)return;
            stopButton.hidden=false;
            status.textContent='Откройте шахматы. Захват остановится, если браузер завершит трансляцию.';
            let lastTime=-1;
            timer=setInterval(()=>{
                paintEstimate();
                if(video.readyState<2||!video.videoWidth||video.currentTime===lastTime)return;
                lastTime=video.currentTime;
                try{process(recognize(video,video.videoWidth,video.videoHeight),false,true);}
                catch{status.textContent='Кадр захвата недоступен. Можно загрузить скриншоты.';}
            },160);
        }catch(error){
            if(id!==generation)return;
            stop(false);
            status.textContent=error.name==='NotAllowedError'?'Доступ к экрану не предоставлен.'
                :'Захват экрана недоступен. Можно загрузить скриншоты.';
        }
    };
    stopButton.onclick=()=>{stop(false);status.textContent='Захват остановлен.';};
    files.onchange=async()=>{
        const selected=Array.from(files.files);
        files.value='';
        if(!selected.length||imageMode)return;
        imageMode=true;
        files.disabled=true;
        startButton.disabled=true;
        const id=generation;
        try{
            for(const file of selected.sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true}))){
                const url=URL.createObjectURL(file);
                try{
                    const image=new Image();
                    image.src=url;
                    await image.decode();
                    if(id!==generation)return;
                    if(!process(recognize(image,image.naturalWidth,image.naturalHeight),true,false))break;
                }finally{URL.revokeObjectURL(url);}
            }
            if(id===generation)analyzeCurrent();
        }catch{if(id===generation){invalidateFrame();status.textContent='Не удалось открыть скриншот.';}}
        finally{if(id===generation){files.disabled=false;startButton.disabled=false;imageMode=false;}}
    };
    side.onchange=()=>{
        pendingFen='';
        lastAskedFen='';
        engine.cancel();
        resultText.textContent='';
        clearNotifications();
        analyzeCurrent();
    };
    notify.hidden=typeof Notification==='undefined'||!navigator.serviceWorker;
    notify.onclick=async()=>{
        try{
            if(await Notification.requestPermission()!=='granted') throw Error();
            const registration=await navigator.serviceWorker.getRegistration();
            if(!registration?.active||typeof registration.showNotification!=='function')throw Error();
            notificationRegistration=registration;
            notify.hidden=true;
        }catch{status.textContent='Уведомления недоступны. Подсказки будут здесь.';}
    };
    if(!notify.hidden&&Notification.permission==='granted'){
        navigator.serviceWorker.getRegistration().then(registration=>{
            if(registration?.active&&typeof registration.showNotification==='function'){
                notificationRegistration=registration;
                notify.hidden=true;
            }
        }).catch(()=>{});
    }
    if(startButton.hidden) status.textContent='Для захвата откройте страницу в Safari на iOS 27. Скриншоты можно загрузить здесь.';
    dialog.addEventListener('close',()=>{clearNotifications();stop(false);scheduleMove();},{once:true});
}
$('screen-coach').onclick=openScreenCoach;
