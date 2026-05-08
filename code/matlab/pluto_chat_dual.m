% PLUTO Chat - Simple Bidirectional Version
% Usage: pluto_chat_dual

function pluto_chat_dual()
    ip = '192.168.2.1';
    Fc = 915e6;      % 915 MHz - best for short range!
    Fs = 40e6;       % Sampling rate
    audio_fc = 200e3;
    buf_size = 80000;
    
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));
    
    hFig = figure('Name', 'PLUTO Chat', 'Position', [100,100,450,450]);
    
    uicontrol('Parent',hFig,'Style','text','String','PLUTO Bidirectional Chat',...
        'FontSize',14,'FontWeight','bold','Position',[100,410,250,30]);
    
    statusText = uicontrol('Parent',hFig,'Style','text','String','Not Connected',...
        'FontSize',10,'Position',[20,370,400,25]);
    
    msgList = uicontrol('Parent',hFig,'Style','listbox','Position',[20,180,410,180],'FontSize',10);
    
    hInput = uicontrol('Parent',hFig,'Style','edit','Position',[20,140,330,30],'FontSize',11,'Enable','off');
    
    uicontrol('Parent',hFig,'Style','pushbutton','String','Send',...
        'Position',[360,140,70,30],'FontSize',11,'Enable','off','Callback',@sendMsg);
    
    uicontrol('Parent',hFig,'Style','pushbutton','String','Connect',...
        'Position',[175,100,100,30],'FontSize',11,'Callback',@connect);
    
    debugText = uicontrol('Parent',hFig,'Style','text','String','---',...
        'FontSize',9,'Position',[20,60,400,20]);
    
    sdr = [];
    txcount = 0;
    rxcount = 0;
    
    function addLog(txt, type)
        t = datestr(now,'HH:MM:SS');
        if strcmp(type,'send'), prefix = 'TX';
        elseif strcmp(type,'recv'), prefix = 'RX';
        else prefix = 'SYS'; end
        list = get(msgList,'String');
        if ~iscell(list), list = {}; end
        list = [list; {['[' prefix ' ' t '] ' txt]}];
        if length(list)>100, list=list(end-99:end); end
        set(msgList,'String',list,'Value',length(list));
    end
    
    function connect(~,~)
        try
            set(statusText,'String','Connecting...');
            drawnow;
            
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = buf_size;
            sdr = sdr.setupImpl();
            
            cfg = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            % Set channels - direct calls (no nested functions)
            idx = sdr.getInChannel('TX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx = sdr.getInChannel('TX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx = sdr.getInChannel('TX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx = sdr.getInChannel('RX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx = sdr.getInChannel('RX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx = sdr.getInChannel('RX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx = sdr.getInChannel('RX1_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx = sdr.getInChannel('RX_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx = sdr.getInChannel('RX1_GAIN'); if idx>=1, cfg{idx}=40; end
            idx = sdr.getInChannel('RX_GAIN'); if idx>=1, cfg{idx}=40; end
            
            setappdata(hFig,'sdr',sdr);
            setappdata(hFig,'cfg',cfg);
            setappdata(hFig,'running',true);
            
            set(statusText,'String','Connected');
            set(hInput,'Enable','on');
            set(findobj(hFig,'String','Send'),'Enable','on');
            set(findobj(hFig,'String','Connect'),'String','Connected');
            addLog('Ready!','sys');
            
            t = timer('TimerFcn',@recvLoop,'Period',0.5,'ExecutionMode','fixedRate');
            start(t);
            setappdata(hFig,'timer',t);
            
        catch ME
            set(statusText,'String',['Failed: ' ME.message]);
            addLog(ME.message,'sys');
        end
    end
    
    function sendMsg(~,~)
        msg = get(hInput,'String');
        if isempty(strtrim(msg)), return; end
        set(hInput,'String','');
        addLog(msg,'send');
        txcount = txcount+1;
        
        try
            txdata = makeSignal(msg);
            cfg = getappdata(hFig,'cfg');
            cfg{1} = real(txdata);
            cfg{2} = imag(txdata);
            stepImpl(sdr, cfg);
            set(debugText,'String',sprintf('TX: %d',txcount));
        catch ME
            addLog(['TX Error: ' ME.message],'sys');
        end
    end
    
    function recvLoop(~,~)
        if ~getappdata(hFig,'running'), return; end
        try
            sdr = getappdata(hFig,'sdr');
            cfg = getappdata(hFig,'cfg');
            sdr.out_ch_size = buf_size * 2;
            cfg{1} = zeros(1,buf_size);
            cfg{2} = zeros(1,buf_size);
            out = stepImpl(sdr, cfg);
            
            if length(out) >= 2
                rx = double(out{1}(1:buf_size)) + 1i*double(out{2}(1:buf_size));
                e = sum(abs(rx).^2)/length(rx);
                set(debugText,'String',sprintf('TX:%d RX:%d E:%.4f',txcount,rxcount,e));
                
                [msg,ok] = decode(rx);
                if ok
                    rxcount = rxcount+1;
                    addLog(msg,'recv');
                    set(debugText,'String',sprintf('TX:%d RX:%d GOT IT!',txcount,rxcount));
                end
            end
        catch ME
            set(debugText,'String',ME.message(1:30));
        end
    end
    
    function txdata = makeSignal(msgStr)
        bytes = double(uint8(msgStr));
        bits = dec2bin(bytes) - '0';
        bits = bits'; bits = bits(:)';
        header = repmat([1 -1 1 -1],1,32);
        txbits = [header bits];
        syms = 2*txbits - 1;
        
        sps = 4;
        fir = rcosdesign(0.5,64,sps);
        up = zeros(1,length(syms)*sps);
        up(1:sps:end) = syms;
        sig = conv(up,fir,'same');
        
        t = (0:length(sig)-1)/Fs;
        sig = sig .* exp(1j*2*pi*audio_fc*t);
        sig = real(sig);
        sig = sig/max(abs(sig))*0.8;
        sig = round(sig*2^14);
        
        % Repeat to fill buffer
        txdata = repmat(sig(:)', 1, ceil(buf_size/length(sig)));
        txdata = txdata(1:buf_size);
    end
    
    function [text,ok] = decode(rx)
        text = '';
        ok = false;
        try
            t = (0:length(rx)-1)/Fs;
            bb = rx .* exp(-1j*2*pi*audio_fc*t);
            bb = real(bb);
            
            sps = 4;
            fir = rcosdesign(0.5,64,sps);
            bb = conv(bb,fir,'same');
            samp = bb(1:sps:end);
            
            header = repmat([1 -1 1 -1],1,32);
            c = abs(conv(fliplr(header),samp(1:min(3000,end))));
            [~,idx] = max(c);
            start = idx - length(header) + 1;
            if start<1 || start>length(samp)-500, return; end
            
            bits = samp(start:start+500) > 0;
            data = bits(129:129+min(length(bits)-128,400));
            if length(data)<8, return; end
            
            bytes = uint8(bi2de(reshape(data(1:floor(length(data)/8)*8),8,[])')));
            bytes = bytes(bytes>31 & bytes<127);
            if isempty(bytes), return; end
            
            text = char(bytes)';
            ok = true;
        catch
        end
    end
    
    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        try
            setappdata(hFig,'running',false);
            t = getappdata(hFig,'timer');
            if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            if ~isempty(sdr), sdr.releaseImpl(); end
        end
        delete(hFig);
    end
    
    addLog('Click Connect to start','sys');
end
