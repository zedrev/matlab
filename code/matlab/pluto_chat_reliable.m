function pluto_chat_reliable()
% PLUTO Reliable Chat - with ACK and retransmission
% Protocol: [PREAMBLE 64] [SYNC 128] [LENGTH 16] [CRC32] [DATA]
%
% Usage:
%   pluto_chat_reliable
%

    % Add paths
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));

    % Parameters
    ip = '192.168.2.1';
    Fc = 915e6;           % RF carrier - 915 MHz best for short range!
    Fs = 40e6;            % Sampling rate
    audio_fc = 200000;    % Audio carrier for modulation
    buf_size = 80000;     % Buffer size
    
    % Frame structure
    PREAMBLE_LEN = 64;
    SYNC_LEN = 128;
    LEN_FIELD = 16;
    CRC_BITS = 32;
    
    % Create figure
    hFig = figure('Name','PLUTO Chat (Reliable)','NumberTitle','off',...
                  'Position',[100 100 600 500],'Color','w');
    
    % UI components
    logList = uicontrol(hFig,'Style','listbox','Position',[20 80 560 380],...
                         'FontSize',11,'BackgroundColor',[0.95 0.95 0.95]);
    inputBox = uicontrol(hFig,'Style','edit','Position',[20 40 480 30],...
                          'FontSize',12,'HorizontalAlignment','left');
    sendBtn = uicontrol(hFig,'Style','pushbutton','Position',[510 40 70 30],...
                         'String','Send','FontSize',12,'Callback',@onSend);
    connectBtn = uicontrol(hFig,'Style','pushbutton','Position',[20 10 100 28],...
                            'String','Connect','Callback',@onConnect);
    statusText = uicontrol(hFig,'Style','text','Position',[140 10 460 28],...
                            'String','Disconnected','FontSize',10,'HorizontalAlignment','left');
    
    % State
    setappdata(hFig,'running',false);
    txcount = 0;
    rxcount = 0;
    
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
            
            cfg = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            idx = sdr.getInChannel('TX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx = sdr.getInChannel('TX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx = sdr.getInChannel('TX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx = sdr.getInChannel('RX_LO_FREQ'); if idx>=1, cfg{idx}=Fc; end
            idx = sdr.getInChannel('RX_SAMPLING_FREQ'); if idx>=1, cfg{idx}=Fs; end
            idx = sdr.getInChannel('RX_RF_BANDWIDTH'); if idx>=1, cfg{idx}=20e6; end
            idx = sdr.getInChannel('RX1_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx = sdr.getInChannel('RX_GAIN_MODE'); if idx>=1, cfg{idx}='manual'; end
            idx = sdr.getInChannel('RX1_GAIN'); if idx>=1, cfg{idx}=50; end
            idx = sdr.getInChannel('RX_GAIN'); if idx>=1, cfg{idx}=50; end
            
            stepImpl(sdr, cfg);
            
            setappdata(hFig,'sdr',sdr);
            setappdata(hFig,'cfg',cfg);
            setappdata(hFig,'running',true);
            
            statusText.String = sprintf('Connected | RF: %.3f GHz | Fs: %.1f MHz', Fc/1e9, Fs/1e6);
            connectBtn.String = 'Disconnect';
            connectBtn.Callback = @(~,~) onDisconnect();
            
            tObj = timer('ExecutionMode','fixedRate','Period',1.0,...
                        'TimerFcn',@recvLoop);
            setappdata(hFig,'timer',tObj);
            start(tObj);
            
        catch ME
            statusText.String = ['Error: ' ME.message];
        end
    end

    function onDisconnect(~,~)
        setappdata(hFig,'running',false);
        tObj = getappdata(hFig,'timer');
        if ~isempty(tObj) && isvalid(tObj)
            stop(tObj);
            delete(tObj);
        end
        statusText.String = 'Disconnected';
        connectBtn.String = 'Connect';
        connectBtn.Callback = @onConnect;
    end

    function addLog(msg, type)
        ts = datestr(now,'HH:MM:ss');
        prefix = '[TX]';
        if strcmp(type,'recv')
            prefix = '[RX]';
        elseif strcmp(type,'ack')
            prefix = '[ACK]';
        elseif strcmp(type,'sys')
            prefix = '[SYS]';
        end
        oldStr = get(logList,'String');
        if isempty(oldStr), oldStr = {}; end
        oldStr(end+1,:) = {[prefix ' ' ts '] ' msg]};
        set(logList,'String',oldStr);
        listboxAutoScroll(logList);
        txcount = txcount + 1;
    end

    function onSend(~,~)
        msg = strtrim(get(inputBox,'String'));
        if isempty(msg)
            return;
        end
        
        set(inputBox,'String','');
        
        try
            sdr = getappdata(hFig,'sdr');
            cfg = getappdata(hFig,'cfg');
            
            if isempty(sdr)
                addLog('Not connected!','sys');
                return;
            end
            
            txdata = makeFrame(msg);
            
            cfg{1} = real(txdata);
            cfg{2} = imag(txdata);
            stepImpl(sdr, cfg);
            
            addLog(msg, 'send');
            statusText.String = sprintf('Sent: "%s" | Waiting ACK...', msg(1:min(20,end)));
            
            % Start ACK timeout timer
            ackTimer = timer('StartDelay', 1.5, ...
                           'TimerFcn', @(~,~) retrySend(msg));
            start(ackTimer);
            setappdata(hFig,'ackTimer', ackTimer);
            setappdata(hFig,'pendingMsg', msg);
            
        catch ME
            addLog(['Err:' ME.message],'sys');
        end
    end

    function retrySend(msg)
        if ~getappdata(hFig,'running')
            return;
        end
        
        addLog(['Retry: ' msg], 'sys');
        
        try
            sdr = getappdata(hFig,'sdr');
            cfg = getappdata(hFig,'cfg');
            txdata = makeFrame(msg);
            cfg{1} = real(txdata);
            cfg{2} = imag(txdata);
            stepImpl(sdr, cfg);
            
            ackTimer = timer('StartDelay', 1.5, ...
                           'TimerFcn', @(~,~) retrySend(msg));
            start(ackTimer);
            setappdata(hFig,'ackTimer', ackTimer);
        catch
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
            
            if length(out) < 2
                statusText.String = 'No data';
                return;
            end
            
            len1 = min(buf_size, length(out{1}));
            len2 = min(buf_size, length(out{2}));
            rxlen = min(len1, len2);
            
            if rxlen < 1
                statusText.String = 'Empty RX';
                return;
            end
            
            rx = double(out{1}(1:rxlen)) + 1i*double(out{2}(1:rxlen));
            e = sum(abs(rx).^2)/length(rx);
            
            statusText.String = sprintf('E:%.4f | TX:%d RX:%d', e, txcount, rxcount);
            
            if e > 0.01
                [msg, ok, isAck] = decodeFrame(rx);
                
                if ok && isAck
                    % Received ACK - stop retry
                    ackT = getappdata(hFig,'ackTimer');
                    if ~isempty(ackT) && isvalid(ackT)
                        stop(ackT);
                        delete(ackT);
                    end
                    addLog('ACK received!', 'ack');
                    statusText.String = sprintf('ACK OK! | E:%.4f', e);
                    
                elseif ok && ~isempty(msg)
                    rxcount = rxcount + 1;
                    addLog(msg, 'recv');
                    statusText.String = sprintf('RX:%d DECODED! | E:%.4f', rxcount, e);
                    
                    % Send ACK back
                    sendAck();
                else
                    if e > 0.05
                        statusText.String = sprintf('Signal but no decode | E:%.4f', e);
                    end
                end
            end
            
        catch ME
            statusText.String = ['ERR:' ME.message(1:25)];
        end
    end

    function sendAck()
        try
            sdr = getappdata(hFig,'sdr');
            cfg = getappdata(hFig,'cfg');
            txdata = makeFrame('<ACK>');
            cfg{1} = real(txdata);
            cfg{2} = imag(txdata);
            stepImpl(sdr, cfg);
        catch
        end
    end

    %% ========== Frame Building ==========
    function txdata = makeFrame(msgStr)
        target_len = buf_size;
        
        % Convert text to bits
        msgBytes = uint8(msgStr)';
        nBytes = length(msgBytes);
        
        % Build bit stream: preamble + sync + length + crc + data
        % Preamble: alternating pattern for AGC
        preamble = repmat([1 -1], 1, PREAMBLE_LEN/2);
        
        % Sync: longer pattern for correlation
        sync = repmat([1 -1 1 -1], 1, SYNC_LEN/4);
        
        % Length field (16 bits)
        lenBits = dec2bin(nBytes, 16) - '0';
        
        % Data bits
        dataBits = [];
        for b = msgBytes
            db = dec2bin(b, 8) - '0';
            dataBits = [dataBits, db];
        end
        
        % Simple CRC (XOR of all bytes)
        crcVal = mod(sum(double(msgBytes)), 256);
        crcBits = dec2bin(crcVal, 8) - '0';
        
        % Combine all
        frameBits = [preamble, sync, lenBits, crcBits, dataBits];
        
        % BPSK modulation: 0 -> +1, 1 -> -1
        symbols = 1 - 2*frameBits;
        
        % SRRC filter
        sps = 4;
        firLen = 32;
        fir = rcosdesign(0.5, firLen, sps);
        
        sigUp = zeros(1, length(symbols)*sps);
        sigUp(1:sps:end) = symbols;
        sigFilt = conv(sigUp, fir, 'same');
        
        % Carrier modulation
        t = (0:length(sigFilt)-1)/Fs;
        baseband = sigFilt .* exp(1j*2*pi*audio_fc*t);
        
        % Normalize and pad
        baseband = baseband / max(abs(baseband)+eps) * 0.8;
        
        % Pad or truncate to target_len
        if length(baseband) < target_len
            basepad = [baseband, zeros(1, target_len-length(baseband))];
        else
            basepad = baseband(1:target_len);
        end
        
        txdata = basepad(:)';
    end

    %% ========== Frame Decoding ==========
    function [text, success, isAck] = decodeFrame(rxSignal)
        text = '';
        success = false;
        isAck = false;
        
        try
            % Down-convert
            t = (0:length(rxSignal)-1)/Fs;
            baseband = rxSignal .* exp(-1j*2*pi*audio_fc*t);
            bbReal = real(baseband);
            
            % Matched filter
            sps = 4;
            fir = rcosdesign(0.5, 32, sps);
            filtered = conv(bbReal, fir, 'same');
            
            % Down-sample
            downSampled = filtered(1:sps:end);
            
            % Correlate to find sync pattern
            syncPattern = repmat([1 -1 1 -1], 1, SYNC_LEN/4);
            preamblePattern = repmat([1 -1], 1, PREAMBLE_LEN/2);
            fullHeader = [preamblePattern, syncPattern];
            
            corr = abs(conv(fliplr(fullHeader), downSampled(1:min(3000,end))));
            [~, maxIdx] = max(corr);
            startIdx = maxIdx - length(fullHeader) + 1;
            
            if startIdx < 10 || startIdx > length(downSampled) - 200
                return;
            end
            
            % Extract frame fields after header
            hdrEnd = startIdx + PREAMBLE_LEN + SYNC_LEN - 1;
            dataStart = hdrEnd + 1;
            
            if dataStart + LEN_FIELD + 8 > length(downSampled)
                return;
            end
            
            % Read length field
            lenBits = downSampled(dataStart:dataStart+LEN_FIELD-1) < 0;
            nDataBits = bi2de(lenBits') * 8;
            nDataBits = min(nDataBits, 200); % Limit max message size
            
            % Read CRC
            crcStart = dataStart + LEN_FIELD;
            crcRx = downSampled(crcStart:crcStart+7) < 0;
            
            % Read data
            dataStart2 = crcStart + 8;
            if dataStart2 + nDataBits > length(downSampled)
                nDataBits = length(downSampled) - dataStart2;
            end
            if nDataBits < 8
                return;
            end
            
            dataBits = downSampled(dataStart2:dataStart2+nDataBits-1) < 0;
            
            % Convert bits to bytes
            nFullBytes = floor(length(dataBits)/8);
            data8 = dataBits(1:nFullBytes*8);
            data8 = reshape(data8, 8, [])';
            bytes = uint8(bi2de(data8));
            
            % Filter printable ASCII
            validIdx = bytes >= 32 & bytes <= 126;
            bytes = bytes(validIdx);
            
            if isempty(bytes)
                return;
            end
            
            decoded = char(bytes);
            
            % Check for ACK message
            if strcmp(decoded, '<ACK>')
                isAck = true;
                success = true;
                return;
            end
            
            % Verify CRC
            crcCalc = mod(sum(double(bytes)), 256);
            crcReceived = bi2de(crcRx');
            if crcCalc == crcReceived
                text = decoded;
                success = true;
            end
            
        catch
        end
    end

    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        onDisconnect();
        delete(hFig);
    end

end
