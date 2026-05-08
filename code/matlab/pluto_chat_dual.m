% PLUTO Chat - Bidirectional Version
% Both parties use the same mode, can send and receive
% Usage: pluto_chat_dual

function pluto_chat_dual()
    % Parameters
    ip = '192.168.2.1';
    Fc = 2.45e9;
    Fs = 40e6;
    audio_fc = 200e3;
    target_len = 80000;
    
    % Add paths
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));
    
    % Create GUI
    hFig = figure('Name', 'PLUTO Chat - Bidirectional', ...
                  'Position', [100, 100, 500, 500], ...
                  'MenuBar', 'none');
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
        'String', 'PLUTO Bidirectional Chat', ...
        'FontSize', 16, 'FontWeight', 'bold', ...
        'Position', [100, 460, 300, 30]);
    
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
        'String', 'Status: Not Connected', ...
        'FontSize', 10, 'Position', [20, 420, 460, 25]);
    
    msgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
        'Position', [20, 180, 460, 230], 'FontSize', 10, 'String', {});
    
    hInput = uicontrol('Parent', hFig, 'Style', 'edit', ...
        'Position', [20, 140, 380, 30], 'FontSize', 11, 'Enable', 'off');
    
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
        'String', 'Send', ...
        'Position', [410, 140, 70, 30], ...
        'FontSize', 11, 'Enable', 'off', 'Callback', @sendMsg);
    
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
        'String', 'Connect', ...
        'Position', [200, 70, 100, 30], ...
        'FontSize', 11, 'Callback', @connectPLUTO);
    
    syncText = uicontrol('Parent', hFig, 'Style', 'text', ...
        'String', 'Sync: ---', ...
        'FontSize', 9, 'Position', [20, 50, 200, 20]);
    
    rx_count = 0;
    tx_count = 0;
    sdr = [];
    
    function addMsg(txt, type)
        list = get(msgList, 'String');
        if isempty(list) || ~iscell(list), list = {}; end
        timeStr = datestr(now, 'HH:MM:SS');
        if strcmp(type, 'send')
            fullMsg = ['[TX ' timeStr '] ' txt];
        elseif strcmp(type, 'recv')
            fullMsg = ['[RX ' timeStr '] ' txt];
        else
            fullMsg = ['[SYS ' timeStr '] ' txt];
        end
        list = [list; {fullMsg}];
        if length(list) > 100, list = list(end-99:end); end
        set(msgList, 'String', list, 'Value', length(list));
    end
    
    function connectPLUTO(~,~)
        try
            set(statusText, 'String', 'Connecting...');
            drawnow;
            
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = target_len;
            sdr = sdr.setupImpl();
            
            config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            % TX settings
            ch = sdr.getInChannel('TX_LO_FREQ'); if ch>0, config{ch}=Fc; end
            ch = sdr.getInChannel('TX_SAMPLING_FREQ'); if ch>0, config{ch}=Fs; end
            ch = sdr.getInChannel('TX_RF_BANDWIDTH'); if ch>0, config{ch}=20e6; end
            
            % RX settings
            ch = sdr.getInChannel('RX_LO_FREQ'); if ch>0, config{ch}=Fc; end
            ch = sdr.getInChannel('RX_SAMPLING_FREQ'); if ch>0, config{ch}=Fs; end
            ch = sdr.getInChannel('RX_RF_BANDWIDTH'); if ch>0, config{ch}=20e6; end
            
            % Gains
            ch = sdr.getInChannel('RX1_GAIN_MODE'); if ch>0, config{ch}='manual'; end
            ch = sdr.getInChannel('RX_GAIN_MODE'); if ch>0, config{ch}='manual'; end
            ch = sdr.getInChannel('RX1_GAIN'); if ch>0, config{ch}=40; end
            ch = sdr.getInChannel('RX_GAIN'); if ch>0, config{ch}=40; end
            
            setappdata(hFig, 'sdr', sdr);
            setappdata(hFig, 'config', config);
            setappdata(hFig, 'running', true);
            
            set(statusText, 'String', 'Status: Connected');
            set(hInput, 'Enable', 'on');
            set(findobj(hFig, 'String', 'Send'), 'Enable', 'on');
            set(findobj(hFig, 'String', 'Connect'), 'String', 'Connected');
            
            addMsg('Connected! Start chatting.', 'system');
            
            % Start receive timer
            timerObj = timer('TimerFcn', @receiveLoop, 'Period', 0.5, 'ExecutionMode', 'fixedRate');
            start(timerObj);
            setappdata(hFig, 'timer', timerObj);
            
        catch ME
            set(statusText, 'String', ['Failed: ' ME.message]);
            addMsg(['Error: ' ME.message], 'system');
        end
    end
    
    function sendMsg(~,~)
        msg = get(hInput, 'String');
        if isempty(strtrim(msg)), return; end
        
        try
            set(hInput, 'String', '');
            addMsg(msg, 'send');
            tx_count = tx_count + 1;
            
            txdata = generate_tx(msg);
            
            config = getappdata(hFig, 'config');
            config{1} = real(txdata);
            config{2} = imag(txdata);
            stepImpl(sdr, config);
            
        catch ME
            addMsg(['Send failed: ' ME.message], 'system');
        end
    end
    
    function receiveLoop(~,~)
        if ~getappdata(hFig, 'running'), return; end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            
            sdr.out_ch_size = target_len * 2;
            config{1} = zeros(1, target_len);
            config{2} = zeros(1, target_len);
            output = stepImpl(sdr, config);
            
            % Safe access to output
            if length(output) < 2
                set(syncText, 'String', 'No RX data');
                return;
            end
            
            rx_len = min(length(output{1}), length(output{2}), target_len);
            rx_signal = double(output{1}(1:rx_len)) + 1i*double(output{2}(1:rx_len));
            
            % Calculate signal energy
            energy = sum(abs(rx_signal).^2) / length(rx_signal);
            set(syncText, 'String', sprintf('Energy: %.2f', energy));
            
            [msg, success] = decode_rx(rx_signal);
            
            if success && ~isempty(msg)
                rx_count = rx_count + 1;
                addMsg(msg, 'recv');
                set(syncText, 'String', sprintf('RX: %d | MSG!', rx_count));
            end
            
        catch ME
            set(syncText, 'String', ['Err: ' ME.message(1:min(20,end))]);
        end
    end
    
    function txdata = generate_tx(msgStr)
        % Text to bits
        % Text to bits
        msg_bytes = double(uint8(msgStr));
        bits = dec2bin(msg_bytes) - '0';
        bits = bits'; bits = bits(:)';
        
        % Sync header
        header = repmat([1 -1 1 -1], 1, 32);
        tx_bits = [header, bits];
        
        % BPSK
        symbols = 2 * tx_bits - 1;
        
        % SRRC filter
        sps = 4;
        fir = rcosdesign(0.5, 64, sps);
        sig_up = zeros(1, length(symbols) * sps);
        sig_up(1:sps:end) = symbols;
        sig_filtered = conv(sig_up, fir, 'same');
        
        % Audio carrier
        t = (0:length(sig_filtered)-1) / Fs;
        tx_signal = sig_filtered .* exp(1j * 2 * pi * audio_fc * t);
        
        % Fix length
        txdata = real(tx_signal);
        txdata = txdata / max(abs(txdata)) * 0.8;
        txdata = round(txdata * 2^14);
        txdata = repmat(txdata(:)', 1, ceil(target_len / length(txdata)));
        txdata = txdata(1:target_len);
    end
    
    function [text, success] = decode_rx(rxdata)
        text = '';
        success = false;
        
        try
            % Down-convert
            t = (0:length(rxdata)-1) / Fs;
            baseband = rxdata .* exp(-1j * 2 * pi * audio_fc * t);
            baseband = real(baseband);
            
            % Matched filter
            sps = 4;
            fir = rcosdesign(0.5, 64, sps);
            filtered = conv(baseband, fir, 'same');
            
            % Down-sample
            sampled = filtered(1:sps:end);
            
            % Sync detection
            header = repmat([1 -1 1 -1], 1, 32);
            corr = abs(conv(fliplr(header), sampled(1:min(3000,end))));
            [~, max_idx] = max(corr);
            
            start_idx = max_idx - length(header) + 1;
            if start_idx < 1 || start_idx > length(sampled) - 500
                return;
            end
            
            % Extract bits
            extracted = sampled(start_idx:start_idx+500);
            bits = extracted(1:512) > 0;
            
            % Decode
            data_bits = bits(129:end);
            data_bytes = uint8(bi2de(reshape(data_bits(1:floor(length(data_bits)/8)*8), 8, [])'));
            data_bytes = data_bytes(data_bytes > 31 & data_bytes < 127);
            
            if isempty(data_bytes), return; end
            
            text = char(data_bytes)';
            success = true;
            
        catch
        end
    end
    
    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        try
            setappdata(hFig, 'running', false);
            t = getappdata(hFig, 'timer');
            if ~isempty(t) && isvalid(t), stop(t); delete(t); end
            if ~isempty(sdr), sdr.releaseImpl(); end
        end
        delete(hFig);
    end
    
    addMsg('Click "Connect" to start', 'system');
end
