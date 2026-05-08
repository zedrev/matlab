% PLUTO多用户聊天室 - 教室场景
% 
% 使用方法:
%   TX端: pluto_multi_chat('mode', 'tx', 'group', 1)
%   RX端: pluto_multi_chat('mode', 'rx', 'group', 1)
%   group: 1-10 (每组使用不同频率)

function pluto_multi_chat(varargin)
    %% ========== 默认参数 ==========
    p = inputParser;
    addParameter(p, 'mode', 'rx');       % 'tx' 或 'rx'
    addParameter(p, 'group', 1);         % 用户组号 1-10
    addParameter(p, 'ip', '192.168.2.1');
    parse(p, varargin{:});
    
    mode = p.Results.mode;
    group = p.Results.group;
    ip = p.Results.ip;
    
    % 多用户频率表 (避免串扰)
    % 每个组使用不同载波频率，间隔5MHz
    base_freq = 2.4e9;  % 2.4 GHz
    freq_step = 5e6;    % 5 MHz 间隔
    carrier_freq = base_freq + (group - 1) * freq_step;
    
    Fs = 40e6;
    
    % 添加库路径
    addpath('../../library/matlab');
    
    %% ========== 创建GUI ==========
    figWidth = 650;
    figHeight = 550;
    
    hFig = figure('Name', ['PLUTO多用户聊天室 - 第' num2str(group) '组 (' upper(mode) ')'], ...
                  'NumberTitle', 'off', ...
                  'Position', [100, 100, figWidth, figHeight], ...
                  'MenuBar', 'none', ...
                  'Resize', 'off');
    
    bgColor = [0.96, 0.96, 0.96];
    hFig.Color = bgColor;
    
    %% 标题栏
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', ['第 ' num2str(group) ' 组聊天室'], ...
              'FontSize', 18, 'FontWeight', 'bold', ...
              'Position', [150, figHeight-45, 350, 35], ...
              'BackgroundColor', [0.2, 0.4, 0.6], ...
              'ForegroundColor', 'white');
    
    %% 频率信息
    freqStr = sprintf('载波频率: %.3f GHz', carrier_freq/1e9);
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', freqStr, ...
              'FontSize', 10, ...
              'Position', [20, figHeight-80, 200, 20], ...
              'HorizontalAlignment', 'left');
    
    %% 连接状态
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '状态: 未连接', ...
              'FontSize', 10, ...
              'Position', [450, figHeight-80, 180, 20]);
    
    %% 消息显示区域
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '消息记录:', ...
              'FontSize', 10, ...
              'Position', [20, figHeight-115, 100, 20]);
    
    hMsgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
              'Position', [20, 130, figWidth-40, figHeight-280], ...
              'FontSize', 10, ...
              'String', {}, ...
              'Value', 0);
    
    %% 消息统计
    statsText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '发送: 0 | 接收: 0 | 错误: 0', ...
              'FontSize', 9, ...
              'Position', [20, 105, 300, 20]);
    
    %% 输入框
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '输入消息:', ...
              'FontSize', 10, ...
              'Position', [20, 80, 100, 20]);
    
    hInput = uicontrol('Parent', hFig, 'Style', 'edit', ...
              'Position', [20, 50, figWidth-140, 30], ...
              'FontSize', 11, ...
              'Enable', 'off');
    
    %% 发送按钮
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', '发送', ...
              'Position', [figWidth-110, 50, 80, 30], ...
              'FontSize', 11, ...
              'Enable', 'off', ...
              'Callback', @sendMessage);
    
    %% 连接按钮
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', '连接PLUTO', ...
              'Position', [figWidth-120, figHeight-80, 100, 25], ...
              'FontSize', 10, ...
              'Callback', @connectPLUTO);
    
    %% 组号选择 (TX模式下显示)
    if strcmp(mode, 'tx')
        uicontrol('Parent', hFig, 'Style', 'text', ...
                  'String', ['第 ' num2str(group) ' 组'], ...
                  'FontSize', 12, 'FontWeight', 'bold', ...
                  'ForegroundColor', 'blue', ...
                  'Position', [250, figHeight-80, 100, 25]);
    end
    
    %% 统计变量
    tx_count = 0;
    rx_count = 0;
    err_count = 0;
    
    %% 添加消息
    function addMessage(msg, type, showGroup)
        if nargin < 3
            showGroup = false;
        end
        
        timeStr = datestr(now, 'HH:MM:SS');
        
        switch type
            case 'send'
                if showGroup
                    fullMsg = ['[组' num2str(group) ' ' timeStr ' 我] ' msg];
                else
                    fullMsg = ['[发送 ' timeStr '] ' msg];
                end
            case 'recv'
                fullMsg = ['[组' num2str(group) ' ' timeStr '] ' msg];
            case 'system'
                fullMsg = ['[系统 ' timeStr '] ' msg];
            case 'error'
                fullMsg = ['[错误 ' timeStr '] ' msg];
        end
        
        currentList = get(hMsgList, 'String');
        if isempty(currentList) || (iscell(currentList) && isempty(currentList{1}))
            newList = {fullMsg};
        else
            newList = [currentList; {fullMsg}];
        end
        
        % 限制显示数量
        if length(newList) > 200
            newList = newList(end-199:end);
        end
        
        set(hMsgList, 'String', newList);
        set(hMsgList, 'Value', length(newList));
    end
    
    %% 更新统计
    function updateStats()
        set(statsText, 'String', ...
            sprintf('发送: %d | 接收: %d | 错误: %d', tx_count, rx_count, err_count));
    end
    
    %% 连接PLUTO
    function connectPLUTO(~, ~)
        set(statusText, 'String', '状态: 正在连接...');
        drawnow;
        
        try
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = 50000;
            sdr = sdr.setupImpl();
            
            % 配置射频参数
            config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            
            if strcmp(mode, 'tx')
                config{sdr.getInChannel('TX_LO_FREQ')} = carrier_freq;
                config{sdr.getInChannel('TX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('TX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('TX1_GAIN')} = 30;
                config{sdr.getInChannel('RX_LO_FREQ')} = carrier_freq;
                config{sdr.getInChannel('RX1_GAIN_MODE')} = 'manual';
                config{sdr.getInChannel('RX1_GAIN')} = 20;
            else
                config{sdr.getInChannel('RX_LO_FREQ')} = carrier_freq;
                config{sdr.getInChannel('RX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('RX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('RX1_GAIN_MODE')} = 'manual';
                config{sdr.getInChannel('RX1_GAIN')} = 40;
                config{sdr.getInChannel('TX_LO_FREQ')} = carrier_freq;
            end
            
            setappdata(hFig, 'sdr', sdr);
            setappdata(hFig, 'config', config);
            setappdata(hFig, 'group', group);
            setappdata(hFig, 'Fs', Fs);
            setappdata(hFig, 'carrier_freq', carrier_freq);
            
            set(statusText, 'String', sprintf('状态: 已连接 %.3f GHz', carrier_freq/1e9));
            set(hInput, 'Enable', 'on');
            
            addMessage(sprintf('已连接PLUTO，载波频率 %.3f GHz', carrier_freq/1e9), 'system');
            
            if strcmp(mode, 'rx')
                setappdata(hFig, 'running', true);
                timerObj = timer('TimerFcn', @receiveLoop, 'Period', 0.3, 'ExecutionMode', 'fixedRate');
                start(timerObj);
                setappdata(hFig, 'timer', timerObj);
                addMessage('开始监听...', 'system');
            end
            
        catch ME
            set(statusText, 'String', '状态: 连接失败');
            addMessage(['连接失败: ' ME.message], 'system');
        end
    end
    
    %% 发送消息
    function sendMessage(~, ~)
        msg = get(hInput, 'String');
        if isempty(strtrim(msg))
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            group_local = getappdata(hFig, 'group');
            Fs_local = getappdata(hFig, 'Fs');
            freq = getappdata(hFig, 'carrier_freq');
            
            % 显示发送的消息
            addMessage(msg, 'send', true);
            set(hInput, 'String', '');
            tx_count = tx_count + 1;
            updateStats();
            
            % 生成信号 (带组号标识)
            tx_signal = generate_tx_signal(msg, group_local, Fs_local, freq);
            
            % 发送
            config{1} = real(tx_signal);
            config{2} = imag(tx_signal);
            stepImpl(sdr, config);
            
        catch ME
            err_count = err_count + 1;
            updateStats();
            addMessage(['发送失败: ' ME.message], 'error');
        end
    end
    
    %% 接收循环
    function receiveLoop(~, ~)
        if ~getappdata(hFig, 'running')
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            my_group = getappdata(hFig, 'group');
            Fs_local = getappdata(hFig, 'Fs');
            freq = getappdata(hFig, 'carrier_freq');
            
            sdr.out_ch_size = 50000;
            output = stepImpl(sdr, config);
            rx_signal = double(output{1}) + 1i*double(output{2});
            
            % 尝试解码
            [msg, detected_group] = decode_rx_signal(rx_signal, Fs_local, freq);
            
            if ~isempty(msg)
                % 检查是否是本组的信号
                if detected_group == my_group
                    rx_count = rx_count + 1;
                    updateStats();
                    addMessage(msg, 'recv', true);
                end
            end
            
        catch
            % 忽略接收错误
        end
    end
    
    %% 生成发送信号
    function signal = generate_tx_signal(text, group_id, Fs, Fc)
        samples_per_symbol = 16;
        symbol_rate = Fs / samples_per_symbol;
        
        % 1. 添加组号前缀 (1字节)
        group_byte = group_id + 64;  % 1->'A', 2->'B', ...
        
        % 2. 添加帧头标识 (特殊字符)
        header = '#STX#';  % 帧开始标记
        
        % 3. 组合消息: [组号][帧头][文本][帧尾]
        full_msg = [group_byte, double(header), double(text), '#ETX#'];
        
        % 4. 转比特
        bits = reshape(dec2bin(full_msg)', 1, []);
        bits = bits - '0';
        
        % 5. CRC16校验
        crc = calc_crc16(bits);
        bits_full = [bits, crc];
        
        % 6. 填充到帧边界
        frame_bits = 256;  % 固定帧长
        bits_padded = zeros(1, frame_bits);
        bits_padded(1:min(length(bits_full), frame_bits)) = bits_full(1:min(length(bits_full), frame_bits));
        
        % 7. BPSK调制
        symbols = 2 * bits_padded - 1;  % 0->-1, 1->+1
        
        % 8. 上采样 + SRRC滤波
        sps = samples_per_symbol;
        fir = rcosdesign(0.5, 64, sps);
        
        signal_up = zeros(1, length(symbols) * sps);
        signal_up(1:sps:end) = symbols;
        signal_up = conv(signal_up, fir, 'same');
        
        % 9. 载波调制
        t = (0:length(signal_up)-1) / Fs;
        signal = signal_up .* exp(1j * 2 * pi * 100e3 * t);
        
        % 10. 归一化
        signal = signal / max(abs(signal)) * 0.8;
    end
    
    %% 解码接收信号
    function [text, group_id] = decode_rx_signal(signal, Fs, Fc)
        text = '';
        group_id = 0;
        
        samples_per_symbol = 16;
        
        % 1. 下变频到基带
        t = (0:length(signal)-1) / Fs;
        baseband = signal .* exp(-1j * 2 * pi * 100e3 * t);
        baseband = real(baseband);  % 简化处理
        
        % 2. 匹配滤波
        fir = rcosdesign(0.5, 64, samples_per_symbol);
        filtered = conv(baseband, fir, 'same');
        
        % 3. 采样
        sampled = filtered(1:samples_per_symbol:end);
        
        % 4. 判决
        bits = sampled > 0;
        
        % 5. 检测帧头
        header_bits = double('#STX#')';
        header_bits = reshape(dec2bin(header_bits)', 1, []);
        header_bits = header_bits - '0';
        
        % 简单相关检测
        corr = abs(conv(double(bits)-0.5, fliplr(double(header_bits)-0.5), 'same'));
        [~, max_idx] = max(corr);
        
        if max_idx < length(header_bits) || max_idx > length(bits) - 270
            return;  % 没找到有效帧
        end
        
        % 6. 提取数据
        start_idx = max_idx + length(header_bits);
        data_bits = bits(start_idx : min(start_idx + 263, length(bits)));
        
        if length(data_bits) < 264
            return;
        end
        
        % 7. 分离数据和CRC
        msg_bits = data_bits(1:256);
        rx_crc = data_bits(257:272);
        
        % 8. CRC校验
        calc_crc = calc_crc16(msg_bits);
        if sum(xor(calc_crc, rx_crc)) ~= 0
            return;  % CRC错误
        end
        
        % 9. 提取组号和文本
        group_id = msg_bits(1:8);
        group_id = bi2de(group_id);
        
        text_bits = msg_bits(9:9+55);  % 最多56比特文本
        bytes = bi2de(reshape(text_bits(1:floor(length(text_bits)/8)*8), 8, [])');
        text = char(bytes(bytes > 31 & bytes < 127))';
    end
    
    %% CRC16计算
    function crc = calc_crc16(bits)
        crc_reg = ones(1, 16);  % 初始化为全1
        
        for i = 1:length(bits)
            bit = bits(i);
            temp = crc_reg(1);
            crc_reg = circshift(crc_reg, -1);
            crc_reg(16) = 0;
            
            if xor(bit, temp) == 1
                crc_reg = xor(crc_reg, [1 0 0 0 1 0 0 0 0 0 1 0 1 0 0 1]);  % CRC-CCITT
            end
        end
        
        crc = 1 - crc_reg;  % 取反
    end
    
    %% 关闭回调
    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        try
            timerObj = getappdata(hFig, 'timer');
            if ~isempty(timerObj) && isvalid(timerObj)
                stop(timerObj);
                delete(timerObj);
            end
            sdr = getappdata(hFig, 'sdr');
            if ~isempty(sdr)
                sdr.releaseImpl();
            end
        catch
        end
        delete(hFig);
    end
    
    %% 初始化消息
    addMessage('=========================================', 'system');
    addMessage(sprintf('PLUTO多用户聊天室 - 第 %d 组', group), 'system');
    addMessage(sprintf('载波频率: %.3f GHz', carrier_freq/1e9), 'system');
    addMessage('=========================================', 'system');
    addMessage('点击"连接PLUTO"开始', 'system');
    
    if strcmp(mode, 'rx')
        addMessage('接收模式：会自动过滤其他组的信号', 'system');
    end
end
