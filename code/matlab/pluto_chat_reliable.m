function pluto_chat_reliable()
% PLUTO Reliable Chat - Dual device with ACK
% Pure baseband, long sync header, DC removal, normalized correlation
%
% Usage:
%   Both sides run:  pluto_chat_reliable

    addpath(fullfile(fileparts(mfilename('fullpath')), '../../library/matlab'));

    % Parameters
    ip = '192.168.2.1';
    Fc = 915e6;
    Fs = 1e6;
    buf_size = 10000;
    
    % Frame structure
    SYNC_LEN = 500;       % Long sync for reliable detection
    SPS = 10;             % Samples per symbol
    
    % Create figure
    hFig = figure('Name','PLUTO Chat','NumberTitle','off',...
                  'Position',[100 100 600 520],'Color','w');
    
    logList = uicontrol(hFig,'Style','listbox','Position',[20 80 560 400],...
                         'FontSize',11,'BackgroundColor',[0.95 0.95 0.95]);
    inputBox = uicontrol(hFig,'Style','edit','Position',[20 40 480 30],...
                          'FontSize',12);
    sendBtn = uicontrol(hFig,'Style','pushbutton','Position',[510 40 70 30],...
                         'String','Send','FontSize',12,'Callback',@onSend);
    connectBtn = uicontrol(hFig,'Style','pushbutton','Position',[20 10 100 28],...
                            'String','Connect','Callback',@onConnect);
    statusText = uicontrol(hFig,'Style','text','Position',[140 10 460 28],...
                            'String','Disconnected','FontSize',10);

    setappdata(hFig,'running',false);
    setappdata(hFig,'txcount',0);
    setappdata(hFig,'rxcount',0);

    %% ========== Connect ==========
    function onConnect(~,~)
        try
            statusText.String = 'Connecting...'; drawnow;

            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = buf_size;
            sdr.out_ch_size = buf_size * 2;
            sdr = sdr.setupImpl();

            nCfg = sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch);
            cfg = cell(1, nCfg);
            
            chSet(sdr,cfg,'TX_LO_FREQ',Fc);
            chSet(sdr,cfg,'TX_SAMPLING_FREQ',Fs);
            chSet(sdr,cfg,'TX_RF_BANDWIDTH',1e6);
            chSet(sdr,cfg,'RX_LO_FREQ',Fc);
            chSet(sdr,cfg,'RX_SAMPLING_FREQ',Fs);
            chSet(sdr,cfg,'RX_RF_BANDWIDTH',1e6);
            chSet(sdr,cfg,'RX1_GAIN_MODE','manual');
            chSet(sdr,cfg,'RX_GAIN_MODE','manual');
            chSet(sdr,cfg,'RX1_GAIN',50);
            chSet(sdr,cfg,'RX_GAIN',50);

            cfg{1} = zeros(1,buf_size);
            cfg{2} = zeros(1,buf_size);
            stepImpl(sdr, cfg);

            setappdata(hFig,'sdr',sdr);
            setappdata(hFig,'cfg',cfg);
            setappdata(hFig,'running',true);

            statusText.String = sprintf('Connected | RF:%.3fGHz Fs:%.0fMHz', Fc/1e9, Fs/1e6);
            connectBtn.String = 'Disconnect';
            connectBtn.Callback = @(~,~) onDisconnect();
            
            tObj = timer('ExecutionMode','fixedRate','Period',1.5,...
                        'TimerFcn',@recvLoop);
            setappdata(hFig,'timer',tObj);
            start(tObj);
            
        catch ME
            statusText.String = ['Err:' ME.message(1:min(40,end))];
        end
    end

    function chSet(sdr, cfg, name, val)
        idx = int32(sdr.getInChannel(name));
        if idx >= int32(1)
            cfg{int32(idx)} = val;
        end
    end

    function onDisconnect(~,~)
        setappdata(hFig,'running',false);
        tObj = getappdata(hFig,'timer');
        if ~isempty(tObj) && isvalid(tObj), stop(tObj); delete(tObj); end
        
        ackT = getappdata(hFig,'ackTimer');
        if ~isempty(ackT) && isvalid(ackT), stop(ackT); delete(ackT); end
        
        statusText.String = 'Disconnected';
        connectBtn.String = 'Connect';
        connectBtn.Callback = @onConnect;
    end

    function addLog(msg, type)
        ts = datestr(now,'HH:MM:ss');
        pfx='[TX]';
        if strcmp(type,'recv'), pfx='[RX]'; 
        elseif strcmp(type,'ack'), pfx='[ACK]'; 
        elseif strcmp(type,'sys'), pfx='[SYS]'; 
        elseif strcmp(type,'retry'), pfx='[RET]';
        end
        old=get(logList,'String');
        if ~iscell(old)||isempty(old), old={}; end
        old{end+1}=[pfx ' ' ts '] ' msg];
        set(logList,'String',old);
        c=getappdata(hFig,'txcount')+1; 
        setappdata(hFig,'txcount',c);
    end

    %% ========== Send with ACK retry ==========
    function onSend(~,~)
        msg=strtrim(get(inputBox,'String'));
        if isempty(msg), return; end
        set(inputBox,'String','');
        
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            if isempty(sdr), addLog('Not connected!','sys'); return; end
            
            [iD,qD]=encodeFrame(msg);
            iD=iD(:)'; qD=qD(:)';
            
            cfg{1}=iD; cfg{2}=qD;
            stepImpl(sdr,cfg);
            
            addLog(msg,'send');
            statusText.String=['Sent: "' msg '" - waiting ACK...'];
            
            % Start ACK timeout
            startAckTimer(msg);
            
        catch ME
            addLog(['Err:' ME.message(1:20)],'sys');
        end
    end

    function startAckTimer(msg)
        % Cancel previous
        oldT = getappdata(hFig,'ackTimer');
        if ~isempty(oldT) && isvalid(oldT), stop(oldT); delete(oldT); end
        
        newT = timer('StartDelay', 2.0, ...
                      'TimerFcn', {@onAckTimeout, msg});
        start(newT);
        setappdata(hFig,'ackTimer', newT);
        setappdata(hFig,'pendingMsg', msg);
    end

    function onAckTimeout(~,~,msg)
        if ~getappdata(hFig,'running'), return; end
        
        addLog(msg,'retry');
        
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            [iD,qD]=encodeFrame(msg);
            iD=iD(:)'; qD=qD(:)';
            cfg{1}=iD; cfg{2}=qD;
            stepImpl(sdr,cfg);
            
            % Retry again
            startAckTimer(msg);
        catch
        end
    end

    function stopAckRetry()
        ackT = getappdata(hFig,'ackTimer');
        if ~isempty(ackT) && isvalid(ackT)
            stop(ackT); delete(ackT);
            setappdata(hFig,'ackTimer', []);
        end
    end

    %% ========== Receive Loop ==========
    function recvLoop(~,~)
        if ~getappdata(hFig,'running'), return; end
        
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            sdr.out_ch_size=buf_size*2;
            cfg{1}=zeros(1,buf_size);
            cfg{2}=zeros(1,buf_size);
            out=stepImpl(sdr,cfg);
            
            if length(out)<2, return; end
            
            o1=out{1}(:)'; o2=out{2}(:)';
            rxlen=min(min(buf_size,length(o1)),length(o2));
            rx=o1(1:rxlen)+1i*o2(1:rxlen);
            e=sum(abs(rx).^2)/rxlen;
            
            tc=getappdata(hFig,'txcount'); rc=getappdata(hFig,'rxcount');
            statusText.String=sprintf('E:%.0f | TX:%d RX:%d', e, tc, rc);
            
            if e > 500  % Signal threshold
                [decodedMsg, ok, isAck] = decode(rx);
                
                if ok && isAck
                    % Received ACK - stop retrying
                    stopAckRetry();
                    rc=rc+1; setappdata(hFig,'rxcount',rc);
                    addLog('ACK received','ack');
                    statusText.String=sprintf('ACK OK | E:%.0f RX:%d', e, rc);
                    
                elseif ok && ~isempty(decodedMsg)
                    rc=rc+1; setappdata(hFig,'rxcount',rc);
                    addLog(decodedMsg,'recv');
                    statusText.String=sprintf('RX:%d "%s" E:%.0f', rc, decodedMsg, e);
                    
                    % Send ACK back
                    sendAck();
                end
            end
            
        catch ME
            statusText.String=['ERR:' ME.message(1:25)];
        end
    end

    function sendAck()
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            [iD,qD]=encodeFrame('<ACK>');
            iD=iD(:)'; qD=qD(:)';
            cfg{1}=iD; cfg{2}=qD;
            stepImpl(sdr,cfg);
        catch
        end
    end

    %% ========== Encode: Text -> I/Q signal ==========
    function [iOut,qOut] = encodeFrame(textMsg)
        % Convert text to bits
        txtBytes = uint8(textMsg)';
        allBits=[];
        for b=double(txtBytes)
            db=de2bi(b,8,'left-msb')';
            allBits=[allBits, db(:)'];
        end
        
        % Long sync pattern [1,-1,1,-1,...]
        syncBits=repmat([1 0], 1, SYNC_LEN);
        
        % Full frame
        frameBits=[syncBits, allBits];
        nBits=length(frameBits);
        
        % BPSK: 0->+1, 1->-1
        bpskSym=1-2*frameBits;
        
        % Up-sample by SPS
        upSig=zeros(1,nBits*SPS);
        upSig(1:SPS:end)=bpskSym;
        
        % Pad to buffer size
        if length(upSig)<buf_size
            upSig=[upSig, zeros(1,buf_size-length(upSig))];
        else
            upSig=upSig(1:buf_size);
        end
        
        % Output (real only for BPSK)
        iOut=upSig*16000;
        qOut=zeros(size(iOut));
    end

    %% ========== Decode: Signal -> Text (same logic as loopback) ==========
    function [textOut,success,isAckFlag] = decode(sig)
        textOut=''; success=false; isAckFlag=false;
        
        try
            r=real(sig);
            
            % Remove DC offset
            r=r-mean(r);
            
            % Normalize to [-1,1]
            rmax=max(abs(r));
            if rmax<eps, return; end
            r=r/rmax;
            
            % Correlation with sync pattern [1,-1,1,-1,...]
            syncPat=repmat([1,-1], 1, SYNC_LEN);
            corr=conv(fliplr(syncPat), r);
            corrAbs=abs(corr);
            maxCorr=max(corrAbs);
            [~,pos]=max(corrAbs);
            
            % Debug output
            fprintf('[RX debug] max_corr=%.2f pos=%d\n', maxCorr, pos);
            
            % Check range only (no threshold - let it try)
            if pos<SYNC_LEN || pos+SYNC_LEN+SPS*50>length(r)
                return;
            end
            
            % Data starts after sync
            dataStart=pos+SYNC_LEN;
            dataEnd=min(length(r), dataStart+SPS*400);
            dataSamples=r(dataStart:dataEnd);
            
            nDataSamples=length(dataSamples);
            if nDataSamples<SPS*8, return; end
            
            % Bit sampling at SPS rate (with rounding for clock tolerance)
            bitIdxs=round(1:SPS:nDataSamples-SPS+1);
            bitIdxs=bitIdxs(bitIdxs>=1 & bitIdxs<=nDataSamples);
            rawBits=dataSamples(bitIdxs);
            
            % Hard decision at 0
            decBits=rawBits>0;
            
            % Bits to bytes
            nBytes=floor(length(decBits)/8);
            if nBytes<1, return; end
            
            byteBits=decBits(1:nBytes*8);
            byteBits=reshape(byteBits,8,[])';
            outBytes=uint8(bi2de(byteBits));
            
            % Keep printable ASCII
            valid=outBytes>=32 & outBytes<=126;
            if sum(valid)<1, return; end
            
            textOut=char(outBytes(valid));
            success=true;
            
            % Check for ACK message
            if strcmp('<ACK>', textOut)
                isAckFlag=true;
            else
                isAckFlag=false;
            end
            
        catch ME
            fprintf('[RX decode err] %s\n', ME.message(1:30));
        end
    end

    hFig.CloseRequestFcn = @(~,~) cleanup();

    function cleanup()
        onDisconnect(); delete(hFig);
    end

end
