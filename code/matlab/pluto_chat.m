% PLUTOФ—�Г�©ХғҳЕ¤�Е®¤ - QQИёҶФ��Г•ҲИ�Ӯ
% Д�¤Е�°Г”ӢХ„‘ЕҚ„Х©ҚХӯҲД�қД��О�ҲД�қД��Х®�Г�®Д��Е�‘Е°„(TX)О�ҲД�қД��Х®�Г�®Д��ФҶӣФ”¶(RX)
% 
% Д�©Г”�Ф–№ФЁ•:
%   TXГ«�: pluto_chat('mode', 'tx', 'ip', '192.168.2.1')
%   RXГ«�: pluto_chat('mode', 'rx', 'ip', '192.168.2.1')

function pluto_chat(varargin)
    % И»�Х®¤Е�‚Ф•°
    p = inputParser;
    addParameter(p, 'mode', 'rx');  % 'tx' Е�‘Е°„ Ф�– 'rx' ФҶӣФ”¶
    addParameter(p, 'ip', '192.168.2.1');
    addParameter(p, 'Fs', 40e6);
    addParameter(p, 'Fc', 2e9);
    parse(p, varargin{:});
    
    mode = p.Results.mode;
    ip = p.Results.ip;
    Fs = p.Results.Fs;
    Fc = p.Results.Fc;
    
    % Ф·»Еҳ�Е�“Х·�Е�„
    addpath('../../library/matlab');
    
    %% ========== Е�›Е»�GUIГ•ҲИ�Ӯ ==========
    figWidth = 600;
    figHeight = 500;
    
    hFig = figure('Name', ['PLUTOФ—�Г�©ХғҳЕ¤�Е®¤ - ' upper(mode)], ...
                  'NumberTitle', 'off', ...
                  'Position', [100, 100, figWidth, figHeight], ...
                  'MenuBar', 'none', ...
                  'Resize', 'off', ...
                  'WindowStyle', 'modal');
    
    % Х®�Г�®ХҒҲФ™�Х‰²
    bgColor = [0.95, 0.95, 0.95];
    hFig.Color = bgColor;
    
    %% Ф�‡ИӮ�Ф��
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'PLUTOФ—�Г�©ХғҳЕ¤�Е®¤', ...
              'FontSize', 16, 'FontWeight', 'bold', ...
              'Position', [150, figHeight-50, 300, 35], ...
              'BackgroundColor', [0.2, 0.4, 0.6], ...
              'ForegroundColor', 'white');
    
    %% Ф�ӯЕ��ФҲ‡Г¤�
    if strcmp(mode, 'tx')
        modeColor = [0.2, 0.6, 0.2];
        modeStr = 'ЦқҚЕ�‘Е°„Ф�ӯЕ�� TXЦқ‘';
    else
        modeColor = [0.6, 0.3, 0.2];
        modeStr = 'ЦқҚФҶӣФ”¶Ф�ӯЕ�� RXЦқ‘';
    end
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', modeStr, ...
              'FontSize', 12, ...
              'Position', [200, figHeight-85, 200, 25], ...
              'BackgroundColor', modeColor, ...
              'ForegroundColor', 'white');
    
    %% Х©�ФҶӣГҳ¶Фқғ
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Гҳ¶Фқғ: Ф��Х©�ФҶӣ', ...
              'FontSize', 10, ...
              'Position', [20, figHeight-115, 200, 20], ...
              'HorizontalAlignment', 'left');
    
    %% ХғҳЕ¤�Ф¶�Фғ�Ф��Г¤�ЕҲ�Е��
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Ф¶�Фғ�Х®°Е�•:', ...
              'FontSize', 10, ...
              'Position', [20, figHeight-150, 100, 20], ...
              'HorizontalAlignment', 'left');
    
    hMsgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
              'Position', [20, 120, figWidth-40, figHeight-280], ...
              'FontSize', 10, ...
              'String', {}, ...
              'Value', 0, ...
              'Max', 100, ...
              'Min', 0);
    
    %% Х�“Е…ӣФӯ†
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'Х�“Е…ӣФ¶�Фғ�:', ...
              'FontSize', 10, ...
              'Position', [20, 95, 100, 20], ...
              'HorizontalAlignment', 'left');
    
    hInput = uicontrol('Parent', hFig, 'Style', 'edit', ...
              'Position', [20, 65, figWidth-140, 30], ...
              'FontSize', 11, ...
              'HorizontalAlignment', 'left', ...
              'Enable', 'off');
    
    %% Е�‘ИқғФҲ‰И’®
    hSendBtn = uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', 'Е�‘Иқғ', ...
              'Position', [figWidth-110, 65, 80, 30], ...
              'FontSize', 11, ...
              'Enable', 'off', ...
              'Callback', @sendMessage);
    
    %% Х©�ФҶӣФҲ‰И’®
    hConnectBtn = uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', 'Х©�ФҶӣPLUTO', ...
              'Position', [figWidth-120, figHeight-115, 100, 25], ...
              'FontSize', 10, ...
              'Callback', @connectPLUTO);
    
    %% Ф¶�Фғ�Ф��Г¤�Е‡�Ф•°
    function addMessage(msg, type)
        % type: 'send', 'recv', 'system'
        timeStr = datestr(now, 'HH:MM:SS');
        
        switch type
            case 'send'
                fullMsg = ['[Е�‘Иқғ ' timeStr '] ' msg];
            case 'recv'
                fullMsg = ['[ФҶӣФ”¶ ' timeStr '] ' msg];
            case 'system'
                fullMsg = ['[ГЁ»Г»� ' timeStr '] ' msg];
        end
        
        currentList = get(hMsgList, 'String');
        if isempty(currentList) || (iscell(currentList) && isempty(currentList{1}))
            newList = {fullMsg};
        else
            newList = [currentList; {fullMsg}];
        end
        set(hMsgList, 'String', newList);
        
        % Х‡�Еҳ�Ф»�Еҳ�Е�°Е�•ИҒ�
        n = length(newList);
        set(hMsgList, 'Value', n);
    end
    
    %% Х©�ФҶӣPLUTO
    function connectPLUTO(~, ~)
        set(statusText, 'String', 'Гҳ¶Фқғ: Ф­ёЕ��Х©�ФҶӣ...');
        drawnow;
        
        try
            % Е�›Е»�SDRЕ�№Х±ӯ
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = 40000;
            sdr = sdr.setupImpl();
            
            % И…ҷГ�®Е°„ИӮ‘Е�‚Ф•°
            config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            if strcmp(mode, 'tx')
                config{sdr.getInChannel('TX_LO_FREQ')} = Fc;
                config{sdr.getInChannel('TX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('TX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('TX1_GAIN')} = 30;
            else
                config{sdr.getInChannel('RX_LO_FREQ')} = Fc;
                config{sdr.getInChannel('RX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('RX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('RX1_GAIN_MODE')} = 'manual';
                config{sdr.getInChannel('RX1_GAIN')} = 40;
            end
            
            % Д©�Е­�Е�°Е�”Г”�Ф•°Фҷ®
            setappdata(hFig, 'sdr', sdr);
            setappdata(hFig, 'config', config);
            setappdata(hFig, 'Fs', Fs);
            setappdata(hFig, 'Fc', Fc);
            
            % Ф›�Ф–°Г•ҲИ�Ӯ
            set(statusText, 'String', ['Гҳ¶Фқғ: Е·²Х©�ФҶӣ (' ip ')']);
            set(hConnectBtn, 'String', 'Ф–­Е�қХ©�ФҶӣ', 'Callback', @disconnectPLUTO);
            set(hInput, 'Enable', 'on');
            set(hSendBtn, 'Enable', 'on');
            
            addMessage(['Е·²Х©�ФҶӣЕ�°PLUTO (' ip ')'], 'system');
            
            % Е¦‚Ф��Ф��RXФ�ӯЕ��О�ҲЕҚ�Еҳ�ФҶӣФ”¶Г�©Г�‹
            if strcmp(mode, 'rx')
                setappdata(hFig, 'running', true);
                timerObj = timer('TimerFcn', @receiveLoop, 'Period', 0.5, 'ExecutionMode', 'fixedRate');
                start(timerObj);
                setappdata(hFig, 'timer', timerObj);
                addMessage('Е�қЕ§‹Г›‘ЕҚ¬ФҶӣФ”¶Д©ӯЕ�·...', 'system');
            end
            
        catch ME
            set(statusText, 'String', 'Гҳ¶Фқғ: Х©�ФҶӣЕ¤±Х�ӣ');
            addMessage(['Х©�ФҶӣЕ¤±Х�ӣ: ' ME.message], 'system');
            errordlg(['Х©�ФҶӣPLUTOЕ¤±Х�ӣ: ' ME.message], 'И”™Х��');
        end
    end
    
    %% Ф–­Е�қХ©�ФҶӣ
    function disconnectPLUTO(~, ~)
        try
            sdr = getappdata(hFig, 'sdr');
            if ~isempty(sdr)
                sdr.releaseImpl();
            end
            
            timerObj = getappdata(hFig, 'timer');
            if ~isempty(timerObj) && isvalid(timerObj)
                stop(timerObj);
                delete(timerObj);
            end
            
            setappdata(hFig, 'running', false);
        catch
        end
        
        set(statusText, 'String', 'Гҳ¶Фқғ: Ф��Х©�ФҶӣ');
        set(hConnectBtn, 'String', 'Х©�ФҶӣPLUTO', 'Callback', @connectPLUTO);
        set(hInput, 'Enable', 'off');
        set(hSendBtn, 'Enable', 'off');
        addMessage('Е·²Ф–­Е�қPLUTOХ©�ФҶӣ', 'system');
    end
    
    %% Е�‘ИқғФ¶�Фғ�
    function sendMessage(~, ~)
        msg = get(hInput, 'String');
        if isempty(strtrim(msg))
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            Fs_local = getappdata(hFig, 'Fs');
            Fc_local = getappdata(hFig, 'Fc');
            
            % Ф��Г¤�Х‡�Е·±Е�‘ИқғГ�„Ф¶�Фғ�
            addMessage(msg, 'send');
            set(hInput, 'String', '');
            
            % Ф–‡Ф�¬Х�¬Д©ӯЕ�·
            tx_signal = textToSignal(msg, Fs_local, Fc_local);
            
            % Е�‘Иқғ
            config{1} = real(tx_signal);
            config{2} = imag(tx_signal);
            stepImpl(sdr, config);
            
        catch ME
            addMessage(['Е�‘ИқғЕ¤±Х�ӣ: ' ME.message], 'system');
        end
    end
    
    %% ФҶӣФ”¶Е��ГҶ�
    function receiveLoop(~, ~)
        if ~getappdata(hFig, 'running')
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            
            % ФҶӣФ”¶Д©ӯЕ�·
            sdr.out_ch_size = 40000;
            output = stepImpl(sdr, config);
            rx_signal = double(output{1}) + 1i*double(output{2});
            
            % Д©ӯЕ�·Х�¬Ф–‡Ф�¬
            msg = signalToText(rx_signal, getappdata(hFig, 'Fs'), getappdata(hFig, 'Fc'));
            
            if ~isempty(msg) && ~strcmpi(msg, '[Ф—�Д©ӯЕ�·]')
                addMessage(msg, 'recv');
            end
            
        catch
            % Е©�Г•ӣФҶӣФ”¶И”™Х��
        end
    end
    
    %% Ф–‡Ф�¬Х�¬Д©ӯЕ�·
    function signal = textToSignal(text, Fs, Fc)
        samples_per_symbol = 16;
        carrier_freq = 100e3;  % И�ЁИӮ‘Х��ФЁӮ
        
        % Ф–‡Ф�¬Х�¬ASCII
        bytes = double(text);
        bits = dec2bin(bytes) - 48;
        bits = bits'; bits = bits(:);
        
        % И‡ҷЕ¤ҷЕ�‘Иқғ3Ф¬ӯ
        bits_full = [bits; bits; bits];
        
        % Еӯ«Е……Е�°Г¬¦Е�·Х�№Г•Ҳ
        total_symbols = ceil(length(bits_full) / 2);
        bits_padded = zeros(total_symbols * 2, 1);
        bits_padded(1:length(bits_full)) = bits_full;
        
        % QPSKХ°ҒЕ�¶
        symbols = zeros(total_symbols, 1);
        for i = 1:total_symbols
            b1 = bits_padded(2*i-1);
            b2 = bits_padded(2*i);
            if b1 == 0 && b2 == 0
                symbols(i) = 1 + 1j;
            elseif b1 == 0 && b2 == 1
                symbols(i) = -1 + 1j;
            elseif b1 == 1 && b2 == 0
                symbols(i) = 1 - 1j;
            else
                symbols(i) = -1 - 1j;
            end
        end
        
        % Д�ҳИ‡‡Ф�·Е№¶Еҳ�Г�—
        signal_up = zeros(1, total_symbols * samples_per_symbol);
        for i = 1:total_symbols
            signal_up((i-1)*samples_per_symbol + (1:samples_per_symbol)) = real(symbols(i));
        end
        
        % Еҳ�Г�—
        win = hanning(samples_per_symbol * 2)';
        for i = 1:total_symbols
            idx = (i-1)*samples_per_symbol;
            if idx > 0
                signal_up(idx + (1:min(samples_per_symbol, length(signal_up)-idx))) = ...
                    signal_up(idx + (1:min(samples_per_symbol, length(signal_up)-idx))) .* win(1:min(samples_per_symbol, length(signal_up)-idx));
            end
        end
        
        % Х��ФЁӮХ°ҒЕ�¶
        t = (0:length(signal_up)-1) / Fs;
        signal = signal_up .* exp(1j * 2 * pi * carrier_freq * t);
        
        % Е�’Д�қЕҲ–
        signal = signal / max(abs(signal)) * 0.8;
    end
    
    %% Д©ӯЕ�·Х�¬Ф–‡Ф�¬
    function text = signalToText(signal, Fs, Fc)
        persistent last_text buffer
        
        if isempty(buffer)
            buffer = [];
        end
        if isempty(last_text)
            last_text = '';
        end
        
        carrier_freq = 100e3;
        samples_per_symbol = 16;
        
        % Д�‹Е��ИӮ‘
        t = (0:length(signal)-1) / Fs;
        baseband = signal .* exp(-1j * 2 * pi * carrier_freq * t);
        
        % Е�–Е®�ИҒ�О��Г®қЕҲ–Е¤„ГҚ†О�‰
        baseband = real(baseband);
        
        % ФёқФӢ‹Д©ӯЕ�·ХҒ�И‡�
        energy = sum(abs(baseband).^2) / length(baseband);
        if energy < 0.001
            text = '[Ф—�Д©ӯЕ�·]';
            return;
        end
        
        % Г®қЕҷ•Е�¤Е†Ё
        bits_received = baseband(1:16:end) > 0;
        
        % Ф��3Д��Е­—Хҳ‚Е�–Г›�ЕҚҲ
        bits_full = bits_received(1:min(length(bits_received), 3*20));
        
        % Е°�Х�•Х§ёГ�ғ
        try
            % Е�†Ф�Қ3Г»„О�ҲЕ�–Г¬¬Д�қГ»„
            n_bytes = floor(length(bits_full) / 24);
            bits_single = bits_full(1:n_bytes * 8);
            
            if length(bits_single) >= 8
                bytes = bi2de(reshape(bits_single(1:floor(length(bits_single)/8)*8), 8, [])');
                bytes = bytes(bytes > 31 & bytes < 127);
                if ~isempty(bytes)
                    text = char(bytes)';
                else
                    text = last_text;
                end
            else
                text = last_text;
            end
        catch
            text = last_text;
        end
        
        last_text = text;
        buffer = [buffer text];
        
        % Х©”Е›�Ф–°Ф¶�Фғ�О��ЕҶ»И‡ҷО�‰
        if length(buffer) > 40
            text = buffer(end-39:end);
            buffer = [];
        end
    end
    
    %% Е…ЁИ—­Е›�Х°Ғ
    hFig.CloseRequestFcn = @(~,~) cleanupAndClose();
    
    function cleanupAndClose()
        try
            disconnectPLUTO();
        catch
        end
        delete(hFig);
    end
    
    addMessage('Ф¬ӮХ©ҶД�©Г”�PLUTOФ—�Г�©ХғҳЕ¤�Е®¤', 'system');
    addMessage(['Е�“Е‰ҷФ�ӯЕ��: ' upper(mode)], 'system');
    addMessage('Г‚№Е‡»"Х©�ФҶӣPLUTO"Е�қЕ§‹', 'system');
end
