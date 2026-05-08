function pluto_chat_reliable()
% PLUTO Chat - Pure Baseband (NO extra audio carrier!)
% Direct I/Q transmission: simpler and more reliable
%
% Usage:
%   pluto_chat_reliable

    % Add paths
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));

    % Parameters
    ip = '192.168.2.1';
    Fc = 915e6;           % RF carrier 915 MHz
    Fs = 1e6;             % Sampling rate 1 MHz (lower = more reliable)
    buf_size = 10000;     % Buffer size per frame
    
    % Create figure
    hFig = figure('Name','PLUTO Chat','NumberTitle','off',...
                  'Position',[100 100 600 500],'Color','w');
    
    logList = uicontrol(hFig,'Style','listbox','Position',[20 80 560 380],...
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

    function onConnect(~,~)
        try
            statusText.String = 'Connecting...';
            drawnow;

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
            
            chSet(sdr, cfg, 'TX_LO_FREQ', Fc);
            chSet(sdr, cfg, 'TX_SAMPLING_FREQ', Fs);
            chSet(sdr, cfg, 'TX_RF_BANDWIDTH', 1e6);
            chSet(sdr, cfg, 'RX_LO_FREQ', Fc);
            chSet(sdr, cfg, 'RX_SAMPLING_FREQ', Fs);
            chSet(sdr, cfg, 'RX_RF_BANDWIDTH', 1e6);
            chSet(sdr, cfg, 'RX1_GAIN_MODE', 'manual');
            chSet(sdr, cfg, 'RX_GAIN_MODE', 'manual');
            chSet(sdr, cfg, 'RX1_GAIN', 50);
            chSet(sdr, cfg, 'RX_GAIN', 50);

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
        statusText.String = 'Disconnected';
        connectBtn.String = 'Connect';
        connectBtn.Callback = @onConnect;
    end

    function addLog(msg, type)
        ts = datestr(now,'HH:MM:ss');
        pfx = '[TX]';
        if strcmp(type,'recv'), pfx='[RX]'; elseif strcmp(type,'ack'), pfx='[ACK]'; elseif strcmp(type,'sys'), pfx='[SYS]'; end
        old = get(logList,'String');
        if ~iscell(old) || isempty(old), old={}; end
        old{end+1}=[pfx ' ' ts '] ' msg];
        set(logList,'String',old);
        c=getappdata(hFig,'txcount')+1; setappdata(hFig,'txcount',c);
    end

    function onSend(~,~)
        msg=strtrim(get(inputBox,'String'));
        if isempty(msg), return; end
        set(inputBox,'String','');
        
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            if isempty(sdr), addLog('Not connected!','sys'); return; end
            
            [iData,qData] = makeSignal(msg);
            iData=iData(:)'; qData=qData(:)';
            
            cfg{1}=iData; cfg{2}=qData;
            stepImpl(sdr,cfg);
            
            addLog(msg,'send');
            statusText.String=['Sent: "' msg '" ...'];
            
        catch ME
            addLog(['Send Err:' ME.message(1:20)],'sys');
        end
    end

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
            
            if e > 100
                [msg,ok]=tryDecode(rx,e);
                if ok && ~isempty(msg)
                    rc=rc+1; setappdata(hFig,'rxcount',rc);
                    addLog(msg,'recv');
                    statusText.String=sprintf('RX:%d OK! | E:%.0f',rc,e);
                end
            end
            
        catch ME
            statusText.String=['ERR:' ME.message(1:25)];
        end
    end

    %% ========== Signal Generation (Pure Baseband) ==========
    function [iOut,qOut] = makeSignal(textMsg)
        % Convert text to bytes then to bits
        txtBytes = uint8(textMsg)';
        allBits = [];
        for b = double(txtBytes)
            db = de2bi(b,8,'left-msb')';
            allBits = [allBits, db(:)'];
        end
        
        % Sync pattern: strong alternating signal for detection
        syncLen = 200;
        syncBits = repmat([1 0], 1, syncLen);
        
        % Combine: sync + data + some padding
        frameBits = [syncBits, allBits];
        nBits = length(frameBits);
        
        % BPSK mapping: 0->+1, 1->-1
        bpskSym = 1 - 2*frameBits;
        
        % Simple up-sample by factor of sps (no filter needed at low rate)
        sps = 10;  % samples per symbol
        upSig = zeros(1, nBits*sps);
        upSig(1:sps:end) = bpskSym;
        
        % Pad or truncate to buffer size
        if length(upSig) < buf_size
            upSig = [upSig, zeros(1, buf_size-length(upSig))];
        else
            upSig = upSig(1:buf_size);
        end
        
        % Output as I/Q (real only on I channel, Q=0 for BPSK)
        iOut = upSig * 16000;   % Scale for PLUTO (14-bit DAC)
        qOut = zeros(size(iOut));
    end

    %% ========== Simple Decoder ==========
    function [msg, success] = tryDecode(sig, energy)
        msg = '';
        success = false;
        
        try
            r = real(sig);  % Use I channel only
            
            % Normalize
            r = r / (max(abs(r))+eps);
            
            % Find sync pattern [1,-1,1,-1,...]
            syncPattern = repmat([1,-1], 1, 100);
            corr = abs(conv(fliplr(syncPattern), r));
            [val, pos] = max(corr);
            
            if val < 80  % Correlation too weak
                return;
            end
            
            % Position after sync
            dataStart = pos + 100;
            if dataStart < 10 || dataStart+80 > length(r)
                return;
            end
            
            % Extract bits (down-sample: every 10th sample)
            sps = 10;
            dataSamples = r(dataStart:min(length(r),dataStart+sps*300));
            
            if length(dataSamples) < 80
                return;
            end
            
            % Sample one per symbol period
            bitIdx = 1:sps:length(dataSamples)-sps+1;
            rawBits = dataSamples(bitIdx);
            
            % Threshold decision
            decodedBits = rawBits > 0;
            
            % Group into bytes
            nBytes = floor(length(decodedBits)/8);
            if nBytes < 1
                return;
            end
            
            byteBits = decodedBits(1:nBytes*8);
            byteBits = reshape(byteBits, 8, [])';
            outBytes = uint8(bi2de(byteBits));
            
            % Keep only printable ASCII
            valid = outBytes >= 32 & outBytes <= 126;
            if sum(valid) < 1
                return;
            end
            
            msg = char(outBytes(valid));
            success = true;
            
        catch
        end
    end

    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        onDisconnect(); delete(hFig);
    end

end
