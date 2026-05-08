% PLUTO Chat - Reliable Version with ACK
% Features:
%   - Preamble + Sync Header + Length + Data + CRC
%   - ACK confirmation
%   - Auto retransmission (no ACK = resend)
%
% Usage: pluto_chat_reliable

function pluto_chat_reliable()
    ip = '192.168.2.1';
    Fc = 915e6;
    Fs = 40e6;
    audio_fc = 200e3;
    buf_size = 80000;
    
    % Frame structure
    PREAMBLE_LEN = 64;      % Preamble for AGC
    SYNC_LEN     = 128;      % Sync header  
    LEN_BITS     = 16;       % Length field (max payload bits)
    CRC_BITS     = 32;       % CRC-32
    MAX_PAYLOAD  = 512;     % Max text chars per frame
    
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));
    
    hFig = figure('Name','PLUTO Reliable Chat', 'Position',[100,100,500,480]);
    
    uicontrol('Parent',hFig,'Style','text','String','PLUTO Chat (Reliable)',...
        'FontSize',14,'FontWeight','bold','Position':[120,440,260,30]);
    
    statusText = uicontrol('Parent',hFig,'Style','text','Status: Not Connected',...
        'FontSize',10,'Position',[20,400,450,25]);
    
    msgList = uicontrol('Parent',hFig,'Style','listbox','Position',[20,200,460,180],'FontSize',10);
    
    hInput = uicontrol('Parent',hFig,'Style','edit','Position',[20,160,360,30],'FontSize',11,'Enable','off');
    
    uicontrol('Parent',hFig,'Style','pushbutton','String','Send',...
        'Position',[390,160,80,30],'FontSize',11,'Enable','off','Callback',@sendMsg);
    
    uicontrol('Parent',hFig,'Style','pushbutton','String','Connect',...
        'Position',[210,120,80,30],'FontSize',11,'Callback',@connect);
    
    statText = uicontrol('Parent',hFig,'Style','text','String','---',...
        'FontSize',9,'Position',[20,80,460,20]);
    
    sdr = [];
    txcount = 0;
    rxcount = 0;
    lastSent = '';
    ackReceived = false;
    sendTimer = [];
    
    function addLog(txt, type)
        t = datestr(now,'HH:MM:SS');
        if strcmp(type,'send'), prefix = 'TX';
        elseif strcmp(type,'recv'), prefix = 'RX';
        elseif strcmp(type,'ack'), prefix = 'ACK';
        else prefix = 'SYS'; end
        list = get(msgList,'String');
        if ~iscell(list), list = {}; end
        list = [list; {['[' prefix ' ' t '] ' txt]}];
        if length(list)>100, list=list(end-99:end); end
        set(msgList,'String',list,'Value',length(list));
    end
    
    %% ========== CONNECT ==========
    function connect(~,~)
        try
            set(statusText,'String','Connecting...'); drawnow;
            
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = buf_size;
            sdr = sdr.setupImpl();
            
            cfg = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            idx=sdr.getInChannel('TX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx=sdr.getInChannel('TX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx=sdr.getInChannel('TX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx=sdr.getInChannel('RX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx=sdr.getInChannel('RX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx=sdr.getInChannel('RX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx=sdr.getInChannel('RX1_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx=sdr.getInChannel('RX_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx=sdr.getInChannel('RX1_GAIN'); if idx>=1, cfg{idx}=40; end
            idx=sdr.getInChannel('RX_GAIN'); if idx>=1, cfg{idx}=40; end
            
            setappdata(hFig,'sdr',sdr);
            setappdata(hFig,'cfg',cfg);
            setappdata(hFig,'running',true);
            
            set(statusText,'String','Connected');
            set(hInput,'Enable','on');
            set(findobj(hFig,'String','Send'),'Enable','on');
            set(findobj(hFig,'String','Connect'),'String','Connected');
            addLog('Ready!','sys');
            
            % Start receive timer
            t=timer('TimerFcn',@recvLoop,'Period',0.5,'ExecutionMode','fixedRate');
            start(t); setappdata(hFig,'timer',t);
            
            % Start ACK check timer
            at=timer('TimerFn',@ackCheck,'Period',0.8,'ExecutionMode','fixedRate');
            start(at); setappdata(hFig,'ackTimer',at);
            
        catch ME
            set(statusText,'String',['Failed: ' ME.message]);
            addLog(ME.message,'sys');
        end
    end
    
    %% ========== SEND MESSAGE ==========
    function sendMsg(~,~)
        msg=get(hInput,'String');
        if isempty(strtrim(msg)), return; end
        
        set(hInput,'String','');
        addLog(msg,'send');
        txcount = txcount+1;
        
        try
            txdata = buildFrame(msg);
            cfg = getappdata(hFig,'cfg');
            cfg{1}=real(txdata); cfg{2}=imag(txdata);
            stepImpl(sdr,cfg);
            
            ackReceived = false;
            set(statText,'String',sprintf('TX:%d Sent!',txcount));
            
            % Auto-retransmit timer
            if ~isempty(sendTimer), delete(sendTimer); end
            sendTimer = timer('TimerFn',@retransmit,'Period',1.5,...
                'ExecutionMode','fixedRate','TasksToExecute',1);
            start(sendTimer); setappdata(hFig,'sendTimer',sendTimer);
            
        catch ME
            addLog(['TX Err:' ME.message],'sys');
        end
    end
    
    %% ========== RETRANSMIT ==========
    function retransmit(~,~)
        if ackReceived || isempty(lastSent)
            return; end
        
        try
            txdata = buildFrame(lastSent);
            cfg = getappdata(hFig,'cfg');
            cfg{1}=real(txdata); cfg{2}=imag(txdata);
            stepImpl(sdr,cfg);
            set(statText,'String',sprintf('TX:%d Retx!',txcount));
            
        catch ME
            statText.String=['RetxErr:' ME.message];
        end
    end
    
    %% ========== RECEIVE LOOP ==========
    function recvLoop(~,~)
        if ~getappdata(hFig,'running'), return; end
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            sdr.out_ch_size = buf_size*2;
            cfg{1}=zeros(1,buf_size); cfg{2}=zeros(1,buf_size);
            out=stepImpl(sdr,cfg);
            
            rx=zeros(1,buf_size);
            if length(out)>=2 && length(out{1})>=buf_size
                rx=double(out{1}(1:buf_size))+1i*double(out{2}(1:buf_size));
            end
            
            e=sum(abs(rx).^2)/length(rx);
            
            [msg,ok]=decodeFrame(rx);
            
            if ok
                rxcount=rxcount+1;
                addLog(msg,'recv');
                statText.String=sprintf('RX:%d DECODED E:%.4f',rxcount,e);
                
                % Send ACK
                sendAck();
                ackReceived=true;
                set(appdata(hFig,'lastAcked',msg);
            else
                statText.String=sprintf('E:%.4f | Decoding...',e);
            end
            
        catch ME
            statText.String='RxErr:' ME.message(1:25);
        end
    end
    
    %% ========== CHECK ACK ==========
    function ackCheck(~,~)
        if ~getappdata(hFig,'running'), return; end
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            sdr.out_ch_size=buf_size*2;
            cfg{1}=zeros(1,buf_size); cfg{2}=zeros(1,buf_size);
            out=stepImpl(sdr,cfg);
            rx=zeros(1,buf_size);
            if length(out)>=2 && length(out{1})>=buf_size
                rx=double(out{1}(1:buf_size))+1i*double(out{2}(1:buf_size));
            end
            
            e=sum(abs(rx).^2)/length(rx);
            
            [msg,ok]=decodeFrame(rx);
            if ok && strcmp(msg,lastSent)
                ackReceived=true;
                statText.String=sprintf('ACK OK! E:%.4f',e);
            elseif ok
                statText.String=sprintf('Other msg E:%.4f',e);
            else
                statText.String=sprintf('E:%.4f waiting...',e);
            end
        catch ME
            statText.String='AckErr';
        end
    end
    
    %% ========== SEND ACK ==========
    function sendAck()
        try
            sdr=getappdata(hFig,'sdr'); cfg=getappdata(hFig,'cfg');
            sdr.out_ch_size=buf_size*2;
            cfg{1}=zeros(1,buf_size); cfg{2}=zeros(1,buf_size);
            out=stepImpl(sdr,cfg);
        catch
        end
    end
    
    %% ========== BUILD FRAME ==========
    function txdata = buildFrame(textStr)
        % 1. Text to bytes to bits
        bytes=double(uint8(textStr));
        bits=dec2bin(bytes)-'0'; bits=bits'; bits=bits(:)';
        
        nBits=length(bits);
        if nBits>MAX_PAYLOAD*8
            textStr=textStr(1:MAX_PAYLOAD);
            bytes=double(uint8(textStr));
            bits=dec2bin(bytes)-'0'; bits=bits'; bits=bits(:)';
            nBits=length(bits);
        end
        
        % 2. Pad with CRC
        crc=CRC32_calc(bits');
        allBits=[bits; crc'];
        
        % 3. Build frame
        % [preamble][sync][length][CRC][data]
        pream=repmat([1;-1],1,PREAMBLE_LEN);
        sync=repmat([1;-1],1,SYNC_LEN/2);
        lenBits=dec2bin(nBits,LEN_BITS)-'0'; lenBits=lenBits';
        
        frameBits=[pream, sync, lenBits, allBits];
        
        % 4. BPSK modulate
        syms=2*frameBits-1;
        
        sps=4;
        fir=rcosdesign(0.5,64,sps);
        up=zeros(1,length(syms)*sps);
        up(1:sps:end)=syms;
        sig=conv(up,fir,'same');
        
        t=(0:length(sig)-1)/Fs;
        sig=sig.*exp(1j*2*pi*audio_fc*t);
        sig=real(sig);
        sig=sig/max(abs(sig))*0.8;
        sig=round(sig*2^14);
        
        txdata=repmat(sig(:)',1,ceil(buf_size/length(sig)));
        txdata=txdata(1:buf_size);
    end
    
    %% ========== DECODE FRAME ==========
    function [text,ok]=decodeFrame(rx)
        text='';
        ok=false;
        try
            t=(0:length(rx)-1)/Fs;
            bb=rx.*exp(-1j*2*pi*audio_fc*t);
            bb=real(bb);
            
            sps=4;
            fir=rcosdesign(0.5,64,sps);
            bb=conv(bb,fir,'same');
            samp=bb(1:sps:end);
            
            % Find sync header
            syncPat=[1 -1 1 -1];
            c=abs(conv(fliplr(syncPat),samp(1:min(3000,end))));
            [~,idx]=max(c);
            start=idx-length(syncPat)+1;
            
            if start<1 || start>length(samp)-500
                return; end
            
            % Extract frame fields
            bits=samp(start:start+PREAMBLE_LEN+SYNC_LEN)>0;
            
            % Get length
            lenBits=bits(PREAMBLEN+SYNC_LEN+1:PREAMBLEN+SYNC_LEN+LEN_BITS);
            nLen=bi2de(reshape(lenBits,8,[])');
            
            % Extract data+CRC
            dataStart=PREAMLEN+SYNC_LEN+LEN_BITS+1;
            dataEnd=min(dataStart+nLen*8-1,length(bits));
            dataBits=bits(dataStart:dataEnd);
            
            % CRC check
            rcvCrc=dataBits(end-CRC_BITS+1:end);
            calcCrc=CRC32_calc(dataBits(1:end-CRC_BITS))';
            
            if ~isequal(calcCrc',rcvCrc')
                return; end
            
            % Decode data
            dataBytes=dataBits(1:end-CRC_BITS);
            dataBytes=uint8(bi2de(reshape(dataBytes,8,[])'));
            valid=(dataBytes>31)&(dataBytes<127);
            dataBytes=dataBytes(valid);
            
            if isempty(dataBytes), return; end
            
            text=char(dataBytes)';
            ok=true;
        catch
        end
    end
    
    %% ========== CRC32 ==========
    function c=CRC32_calc(bits)
        hexVal=hex2dec('EDB88320');
        poly=zeros(1,32);
        for b=1:32, poly(b)=bitget(hexVal,b); end
        poly=[1 poly];
        bits=[bits; zeros(32,1)];
        for i=1:length(bits)+32
            rem=[rem;bits(i)];
            if rem(1)==1, rem=xor(rem,poly);end
            rem=rem(2:33);
        end
        c=1-rem;
    end
    
    %% ========== CLOSE ==========
    hFig.CloseRequestFcn=@(~,~)cleanup;
    function cleanup()
        try
            setappdata(hFig,'running',false);
            t=getappdata(hFig,'timer'); if ~isempty(t)&&isvalid(t), stop(t); delete(t); end
            at=getappdata(hFig,'ackTimer'); if ~isempty(at)&&isvalid(at), stop(at); delete(at); end
            st=getappdata(hFig,'sendTimer'); if ~isempty(st)&&isvalid(st), stop(st); delete(st); end
            if ~isempty(sdr), sdr.releaseImpl(); end
        end
        delete(hFig);
    end
    
    addLog('Click Connect to start','sys');
end
