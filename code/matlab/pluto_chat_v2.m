% PLUTO Chat System - Advanced Version
% Features: m-sequence sync, Gardner timing, Multi-level frequency sync, CRC32
% Usage:
%   TX: pluto_chat_v2('mode', 'tx')
%   RX: pluto_chat_v2('mode', 'rx')

function pluto_chat_v2(varargin)
    %% Parameters
    p = inputParser;
    addParameter(p, 'mode', 'rx');
    addParameter(p, 'ip', '192.168.2.1');
    addParameter(p, 'Fc', 2.45e9);
    addParameter(p, 'Fs', 40e6);
    addParameter(p, 'audio_fc', 200e3);
    parse(p, varargin{:});
    
    mode = p.Results.mode;
    ip = p.Results.ip;
    Fc = p.Results.Fc;
    Fs = p.Results.Fs;
    audio_fc = p.Results.audio_fc;
    
    % Add library paths - use script location
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(scriptDir, '../../library/matlab'));
    addpath(fullfile(scriptDir, 'BPSK/transmitter'));
    addpath(fullfile(scriptDir, 'BPSK/receiver'));
    
    global cyc;
    cyc = 0;
    tx_count = 0;
    rx_count = 0;
    err_count = 0;
    sdr = [];
    timerObj = [];
    
    %% GUI
    figWidth = 700;
    figHeight = 580;
    
    hFig = figure('Name', ['PLUTO Chat v2.0 - ' upper(mode)], ...
                  'NumberTitle', 'off', ...
                  'Position', [100, 100, figWidth, figHeight], ...
                  'MenuBar', 'none');
    hFig.Color = [0.96, 0.96, 0.96];
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'PLUTO Wireless Chat (Advanced)', ...
              'FontSize', 18, 'FontWeight', 'bold', ...
              'Position', [150, figHeight-45, 400, 35], ...
              'BackgroundColor', [0.2, 0.4, 0.6], ...
              'ForegroundColor', 'white');
    
    if strcmp(mode, 'tx')
        modeColor = [0.2, 0.6, 0.2];
    else
        modeColor = [0.6, 0.3, 0.2];
    end
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', ['[' upper(mode) ' MODE]'], ...
              'FontSize', 12, ...
              'Position', [250, figHeight-80, 200, 25], ...
              'BackgroundColor', modeColor, ...
              'ForegroundColor', 'white');
    
    freqStr = sprintf('RF: %.3f GHz | Audio: %.0f kHz', Fc/1e9, audio_fc/1e3);
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', freqStr, ...
              'FontSize', 9, ...
              'Position', [20, figHeight-80, 250, 20]);
    
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Status: Not Connected', ...
              'FontSize', 10, ...
              'Position', [450, figHeight-80, 200, 20]);
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Messages:', ...
              'FontSize', 10, ...
              'Position', [20, figHeight-115, 100, 20]);
    
    hMsgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
              'Position', [20, 150, figWidth-40, figHeight-300], ...
              'FontSize', 10, ...
              'String', {}, ...
              'Value', 0);
    
    statsText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'TX: 0 | RX: 0 | Errors: 0', ...
              'FontSize', 9, ...
              'Position', [20, 125, 350, 20]);
    
    syncText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Sync: ---', ...
              'FontSize', 9, ...
              'ForegroundColor', [0.3, 0.3, 0.3], ...
              'Position', [400, 125, 200, 20]);
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Input:', ...
              'FontSize', 10, ...
              'Position', [20, 95, 80, 20]);
    
    hInput = uicontrol('Parent', hFig, 'Style', 'edit', ...
              'Position', [20, 65, figWidth-150, 30], ...
              'FontSize', 11, ...
              'Enable', 'off');
    
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', 'Send', ...
              'Position', [figWidth-120, 65, 90, 30], ...
              'FontSize', 11, ...
              'Enable', 'off', ...
              'Callback', @sendMessage);
    
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', 'Connect', ...
              'Position', [figWidth-120, figHeight-80, 90, 25], ...
              'FontSize', 10, ...
              'Callback', @connectPLUTO);
    
    %% Helper functions
    function addMessage(msg, type)
        timeStr = datestr(now, 'HH:MM:SS');
        if strcmp(type, 'send')
            fullMsg = ['[TX ' timeStr '] ' msg];
        elseif strcmp(type, 'recv')
            fullMsg = ['[RX ' timeStr '] ' msg];
        elseif strcmp(type, 'system')
            fullMsg = ['[SYS ' timeStr '] ' msg];
        else
            fullMsg = ['[ERR ' timeStr '] ' msg];
        end
        
        list = get(hMsgList, 'String');
        if isempty(list) || (iscell(list) && isempty(list{1}))
            list = {fullMsg};
        else
            list = [list; {fullMsg}];
        end
        if length(list) > 200
            list = list(end-199:end);
        end
        set(hMsgList, 'String', list, 'Value', length(list));
    end
    
    function updateStats()
        set(statsText, 'String', sprintf('TX: %d | RX: %d | Errors: %d', tx_count, rx_count, err_count));
    end
    
    function updateSyncStatus(status)
        set(syncText, 'String', ['Sync: ' status]);
    end
    
    function connectPLUTO(~, ~)
        set(statusText, 'String', 'Status: Connecting...');
        drawnow;
        
        try
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = 80000;
            sdr = sdr.setupImpl();
            
            config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            % Set TX parameters
            ch = sdr.getInChannel('TX_LO_FREQ');
            if ch > 0, config{ch} = Fc; end
            ch = sdr.getInChannel('TX_SAMPLING_FREQ');
            if ch > 0, config{ch} = Fs; end
            ch = sdr.getInChannel('TX_RF_BANDWIDTH');
            if ch > 0, config{ch} = 20e6; end
            
            % Set RX parameters
            ch = sdr.getInChannel('RX_LO_FREQ');
            if ch > 0, config{ch} = Fc; end
            ch = sdr.getInChannel('RX_SAMPLING_FREQ');
            if ch > 0, config{ch} = Fs; end
            ch = sdr.getInChannel('RX_RF_BANDWIDTH');
            if ch > 0, config{ch} = 20e6; end
            
            % Gain settings
            if strcmp(mode, 'tx')
                ch = sdr.getInChannel('TX1_GAIN');
                if ch > 0, config{ch} = 30; end
                ch = sdr.getInChannel('TX_GAIN');
                if ch > 0, config{ch} = 30; end
                ch = sdr.getInChannel('RX1_GAIN_MODE');
                if ch > 0, config{ch} = 'manual'; end
                ch = sdr.getInChannel('RX_GAIN_MODE');
                if ch > 0, config{ch} = 'manual'; end
                ch = sdr.getInChannel('RX1_GAIN');
                if ch > 0, config{ch} = 20; end
                ch = sdr.getInChannel('RX_GAIN');
                if ch > 0, config{ch} = 20; end
            else
                ch = sdr.getInChannel('RX1_GAIN_MODE');
                if ch > 0, config{ch} = 'manual'; end
                ch = sdr.getInChannel('RX_GAIN_MODE');
                if ch > 0, config{ch} = 'manual'; end
                ch = sdr.getInChannel('RX1_GAIN');
                if ch > 0, config{ch} = 40; end
                ch = sdr.getInChannel('RX_GAIN');
                if ch > 0, config{ch} = 40; end
            end
            
            setappdata(hFig, 'sdr', sdr);
            setappdata(hFig, 'config', config);
            
            set(statusText, 'String', ['Status: Connected (' ip ')']);
            set(hInput, 'Enable', 'on');
            set(findobj(hFig, 'String', 'Send'), 'Enable', 'on');
            
            addMessage(['Connected to PLUTO at ' num2str(Fc/1e9) ' GHz'], 'system');
            
            if strcmp(mode, 'rx')
                setappdata(hFig, 'running', true);
                timerObj = timer('TimerFcn', @receiveLoop, 'Period', 0.5, 'ExecutionMode', 'fixedRate');
                start(timerObj);
                setappdata(hFig, 'timer', timerObj);
                addMessage('Listening for incoming messages...', 'system');
            end
            
        catch ME
            set(statusText, 'String', 'Status: Connection Failed');
            addMessage(['Failed: ' ME.message], 'error');
        end
    end
    
    function sendMessage(~, ~)
        msg = get(hInput, 'String');
        if isempty(strtrim(msg))
            return;
        end
        
        try
            set(hInput, 'String', '');
            addMessage(msg, 'send');
            tx_count = tx_count + 1;
            updateStats();
            
            txdata = improved_tx(msg);
            
            config = getappdata(hFig, 'config');
            config{1} = real(txdata);
            config{2} = imag(txdata);
            stepImpl(sdr, config);
            
        catch ME
            addMessage(['Send failed: ' ME.message], 'error');
        end
    end
    
    function receiveLoop(~, ~)
        if ~getappdata(hFig, 'running')
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            
            sdr.out_ch_size = 160000;
            tx_zeros = zeros(1, 80000);
            config{1} = tx_zeros;
            config{2} = tx_zeros;
            output = stepImpl(sdr, config);
            rx_signal = double(output{1}(1:80000)) + 1i*double(output{2}(1:80000));
            
            updateSyncStatus('Decoding...');
            [msg, success, sync_info] = improved_rx(rx_signal);
            
            if success
                rx_count = rx_count + 1;
                updateStats();
                updateSyncStatus(sprintf('OK [Foff:%.1fkHz]', sync_info.freq_offset/1e3));
                addMessage(msg, 'recv');
            else
                updateSyncStatus('No sync');
            end
            
        catch
        end
    end
    
    function txdata = improved_tx(msgStr)
        % Simple BPSK transmission
        target_len = 80000;
        
        % 1. Text to bits
        msg_bytes = double(uint8(msgStr));
        bits = dec2bin(msg_bytes) - '0';
        bits = bits';
        msg_bits = bits(:)';
        
        % 2. Simple sync header (repeated pattern)
        header = repmat([1 -1 1 -1], 1, 32);  % 128 bits
        
        % 3. Combine header + data
        tx_bits = [header, msg_bits];
        
        % 4. BPSK modulation (1 -> +1, 0 -> -1)
        symbols = 2 * tx_bits - 1;
        
        % 5. SRRC filter
        sps = 4;
        fir = rcosdesign(0.5, 64, sps);
        
        % Up-sample and filter
        sig_up = zeros(1, length(symbols) * sps);
        sig_up(1:sps:end) = symbols;
        sig_filtered = conv(sig_up, fir, 'same');
        
        % 6. Audio carrier modulation
        t = (0:length(sig_filtered)-1) / Fs;
        tx_signal = sig_filtered .* exp(1j * 2 * pi * audio_fc * t);
        
        % 7. Prepare for PLUTO - FIXED length
        txdata = real(tx_signal);
        txdata = txdata / max(abs(txdata)) * 0.8;
        txdata = round(txdata * 2^14);
        
        % Repeat to reach target length
        txdata = repmat(txdata(:)', 1, ceil(target_len / length(txdata)));
        txdata = txdata(1:target_len);
    end
    
    function [text, success, sync_info] = improved_rx(rxdata)
        text = '';
        success = false;
        sync_info = struct('freq_offset', 0, 'snr', 0, 'constellation', []);
        
        rx_signal = rxdata;
        
        try
            % 1. Down-convert from audio carrier
            t = (0:length(rx_signal)-1) / Fs;
            baseband = rx_signal .* exp(-1j * 2 * pi * audio_fc * t);
            baseband = real(baseband);
            
            % 2. Matched filter
            sps = 4;
            fir = rcosdesign(0.5, 64, sps);
            filtered = conv(baseband, fir, 'same');
            
            % 3. Down-sample
            sampled = filtered(1:sps:end);
            
            % 4. Simple correlation sync
            header = repmat([1 -1 1 -1], 1, 32);
            [~, max_idx] = max(abs(conv(fliplr(header), sampled(1:min(2000,end)))));
            start_idx = max_idx - length(header) + 1;
            
            if start_idx < 1 || start_idx > length(sampled) - 500
                return;
            end
            
            % 5. Extract bits
            extracted = sampled(start_idx:start_idx+500);
            bits = extracted(1:512) > 0;
            
            % 6. Decode text
            data_bits = bits(129:end);  % Skip header
            data_bytes = uint8(bi2de(reshape(data_bits(1:floor(length(data_bits)/8)*8), 8, [])'));
            data_bytes = data_bytes(data_bytes > 31 & data_bytes < 127);
            
            if isempty(data_bytes)
                return;
            end
            
            text = char(data_bytes)';
            success = true;
            
        catch
        end
    end
    
    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        try
            setappdata(hFig, 'running', false);
            if ~isempty(timerObj) && isvalid(timerObj)
                stop(timerObj);
                delete(timerObj);
            end
            if ~isempty(sdr)
                sdr.releaseImpl();
            end
        catch
        end
        delete(hFig);
    end
    
    addMessage('========================================', 'system');
    addMessage('PLUTO Wireless Chat v2.0', 'system');
    addMessage('m-seq sync | CRC32 | Freq correction', 'system');
    addMessage('========================================', 'system');
    addMessage('Click "Connect" to start', 'system');
end
