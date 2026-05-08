% PLUTO聊天系统 - 改进版 (集成可靠同步算法)
% 
% 功能:
%   - m序列帧同步
%   - Gardner定时恢复
%   - 多级频偏同步  
%   - 导频相位跟踪
%   - CRC32校验
%
% 使用方法:
%   TX端: pluto_chat_v2('mode', 'tx')
%   RX端: pluto_chat_v2('mode', 'rx')

function pluto_chat_v2(varargin)
    %% ========== 参数配置 ==========
    p = inputParser;
    addParameter(p, 'mode', 'rx');
    addParameter(p, 'ip', '192.168.2.1');
    addParameter(p, 'Fc', 2.45e9);      % 载波频率
    addParameter(p, 'Fs', 40e6);       % 采样率
    addParameter(p, 'audio_fc', 200e3); % 音频载波
    parse(p, varargin{:});
    
    mode = p.Results.mode;
    ip = p.Results.ip;
    Fc = p.Results.Fc;
    Fs = p.Results.Fs;
    audio_fc = p.Results.audio_fc;
    
    % 添加库路径
    addpath('../../library/matlab');
    addpath('../BPSK/transmitter');
    addpath('../BPSK/receiver');
    
    %% ========== 全局变量 ==========
    global cyc;
    cyc = 0;
    tx_count = 0;
    rx_count = 0;
    err_count = 0;
    sdr = [];
    timerObj = [];
    
    %% ========== 创建GUI ==========
    figWidth = 700;
    figHeight = 580;
    
    hFig = figure('Name', ['PLUTO聊天 v2.0 - ' upper(mode)], ...
                  'NumberTitle', 'off', ...
                  'Position', [100, 100, figWidth, figHeight], ...
                  'MenuBar', 'none');
    hFig.Color = [0.96, 0.96, 0.96];
    
    % 标题
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', 'PLUTO无线聊天室 (改进版)', ...
              'FontSize', 18, 'FontWeight', 'bold', ...
              'Position', [150, figHeight-45, 400, 35], ...
              'BackgroundColor', [0.2, 0.4, 0.6], ...
              'ForegroundColor', 'white');
    
    % 模式标签
    if strcmp(mode, 'tx')
        modeColor = [0.2, 0.6, 0.2];
    else
        modeColor = [0.6, 0.3, 0.2];
    end
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', ['【' upper(mode) '模式】'], ...
              'FontSize', 12, ...
              'Position', [250, figHeight-80, 200, 25], ...
              'BackgroundColor', modeColor, ...
              'ForegroundColor', 'white');
    
    % 频率信息
    freqStr = sprintf('射频: %.3f GHz | 音频: %.0f kHz', Fc/1e9, audio_fc/1e3);
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', freqStr, ...
              'FontSize', 9, ...
              'Position', [20, figHeight-80, 250, 20]);
    
    % 状态
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '状态: 未连接', ...
              'FontSize', 10, ...
              'Position', [450, figHeight-80, 200, 20]);
    
    % 消息列表
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '消息记录:', ...
              'FontSize', 10, ...
              'Position', [20, figHeight-115, 100, 20]);
    
    hMsgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
              'Position', [20, 150, figWidth-40, figHeight-300], ...
              'FontSize', 10, ...
              'String', {}, ...
              'Value', 0);
    
    % 统计
    statsText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '发送: 0 | 接收: 0 | CRC错误: 0', ...
              'FontSize', 9, ...
              'Position', [20, 125, 350, 20]);
    
    % 同步状态
    syncText = uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '同步状态: ---', ...
              'FontSize', 9, ...
              'ForegroundColor', [0.3, 0.3, 0.3], ...
              'Position', [400, 125, 200, 20]);
    
    % 输入框
    uicontrol('Parent', hFig, 'Style', 'text', ...
              'String', '输入消息:', ...
              'FontSize', 10, ...
              'Position', [20, 95, 80, 20]);
    
    hInput = uicontrol('Parent', hFig, 'Style', 'edit', ...
              'Position', [20, 65, figWidth-150, 30], ...
              'FontSize', 11, ...
              'Enable', 'off');
    
    % 发送按钮
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', '发送', ...
              'Position', [figWidth-120, 65, 90, 30], ...
              'FontSize', 11, ...
              'Enable', 'off', ...
              'Callback', @sendMessage);
    
    % 连接按钮
    uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
              'String', '连接PLUTO', ...
              'Position', [figWidth-120, figHeight-80, 90, 25], ...
              'FontSize', 10, ...
              'Callback', @connectPLUTO);
    
    % 波形显示区
    hAx = axes('Parent', hFig, ...
                'Position', [0.05, 0.02, 0.25, 0.12]);
    title(hAx, 'TX波形');
    xlabel(hAx, '采样点');
    hTxPlot = plot(hAx, zeros(100,1));
    
    hAx2 = axes('Parent', hFig, ...
                 'Position', [0.35, 0.02, 0.25, 0.12]);
    title(hAx2, 'RX波形');
    xlabel(hAx2, '采样点');
    hRxPlot = plot(hAx2, zeros(100,1));
    
    hAx3 = axes('Parent', hFig, ...
                 'Position', [0.65, 0.02, 0.30, 0.12]);
    title(hAx3, '星座图');
    xlabel(hAx3, 'I');
    ylabel(hAx3, 'Q');
    hScatter = scatter(hAx3, 0, 0, 10, 'filled');
    axis(hAx3, [-1.5 1.5 -1.5 1.5]);
    grid(hAx3, 'on');
    
    %% ========== 辅助函数 ==========
    
    function addMessage(msg, type)
        timeStr = datestr(now, 'HH:MM:SS');
        switch type
            case 'send'
                fullMsg = ['[发送 ' timeStr '] ' msg];
            case 'recv'
                fullMsg = ['[接收 ' timeStr '] ' msg];
            case 'system'
                fullMsg = ['[系统 ' timeStr '] ' msg];
            case 'error'
                fullMsg = ['[错误 ' timeStr '] ' msg];
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
        set(statsText, 'String', ...
            sprintf('发送: %d | 接收: %d | CRC错误: %d', tx_count, rx_count, err_count));
    end
    
    function updateSyncStatus(status)
        set(syncText, 'String', ['同步状态: ' status]);
    end
    
    %% ========== 连接PLUTO ==========
    function connectPLUTO(~, ~)
        set(statusText, 'String', '状态: 连接中...');
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
            
            if strcmp(mode, 'tx')
                config{sdr.getInChannel('TX_LO_FREQ')} = Fc;
                config{sdr.getInChannel('TX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('TX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('TX1_GAIN')} = 30;
                config{sdr.getInChannel('RX_LO_FREQ')} = Fc;
                config{sdr.getInChannel('RX1_GAIN_MODE')} = 'manual';
                config{sdr.getInChannel('RX1_GAIN')} = 20;
            else
                config{sdr.getInChannel('RX_LO_FREQ')} = Fc;
                config{sdr.getInChannel('RX_SAMPLING_FREQ')} = Fs;
                config{sdr.getInChannel('RX_RF_BANDWIDTH')} = 20e6;
                config{sdr.getInChannel('RX1_GAIN_MODE')} = 'manual';
                config{sdr.getInChannel('RX1_GAIN')} = 40;
                config{sdr.getInChannel('TX_LO_FREQ')} = Fc;
            end
            
            setappdata(hFig, 'sdr', sdr);
            setappdata(hFig, 'config', config);
            
            set(statusText, 'String', ['状态: 已连接 (' ip ')']);
            set(hInput, 'Enable', 'on');
            set(findobj(hFig, 'String', '发送'), 'Enable', 'on');
            
            addMessage(['已连接到PLUTO，载波频率 ' num2str(Fc/1e9) ' GHz'], 'system');
            
            if strcmp(mode, 'rx')
                setappdata(hFig, 'running', true);
                timerObj = timer('TimerFcn', @receiveLoop, 'Period', 0.5, 'ExecutionMode', 'fixedRate');
                start(timerObj);
                setappdata(hFig, 'timer', timerObj);
                addMessage('开始监听接收信号...', 'system');
            end
            
        catch ME
            set(statusText, 'String', '状态: 连接失败');
            addMessage(['连接失败: ' ME.message], 'system');
        end
    end
    
    %% ========== 发送消息 ==========
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
            
            % 生成发送信号
            txdata = improved_tx(msg);
            
            % 更新波形显示
            set(hTxPlot, 'YData', real(txdata(1:min(100,end))));
            
            % 发送
            config = getappdata(hFig, 'config');
            config{1} = real(txdata);
            config{2} = imag(txdata);
            stepImpl(sdr, config);
            
        catch ME
            addMessage(['发送失败: ' ME.message], 'error');
        end
    end
    
    %% ========== 接收循环 ==========
    function receiveLoop(~, ~)
        if ~getappdata(hFig, 'running')
            return;
        end
        
        try
            sdr = getappdata(hFig, 'sdr');
            config = getappdata(hFig, 'config');
            
            sdr.out_ch_size = 80000;
            output = stepImpl(sdr, config);
            rx_signal = double(output{1}) + 1i*double(output{2});
            
            % 更新RX波形
            set(hRxPlot, 'YData', real(rx_signal(1:min(100,end))));
            
            % 尝试解码
            updateSyncStatus('解调中...');
            [msg, success, sync_info] = improved_rx(rx_signal);
            
            if success
                rx_count = rx_count + 1;
                updateStats();
                updateSyncStatus(sprintf('OK [频偏:%.1fkHz]', sync_info.freq_offset/1e3));
                addMessage(msg, 'recv');
                
                % 更新星座图
                if ~isempty(sync_info.constellation)
                    const = sync_info.constellation(1:50:end);
                    set(hScatter, 'XData', real(const), 'YData', imag(const));
                end
            else
                if sync_info.snr < 5
                    updateSyncStatus('信号太弱');
                else
                    updateSyncStatus('未同步/CRC错误');
                end
            end
            
        catch
        end
    end
    
    %% ========== 改进版发送 (带同步头) ==========
    function txdata = improved_tx(msgStr)
        % 1. 生成m序列同步头
        m_seq = tx_gen_m_seq([1 0 0 0 0 0 1]);  % 7位m序列
        sync_symbols = tx_modulate(m_seq, 'BPSK');
        
        % 2. 消息转比特
        msg_bits = str_to_bits(msgStr);
        
        % 3. CRC32校验
        crc_bits = crc32(msg_bits)';
        tx_bits = [msg_bits; crc_bits];
        
        % 4. 扰码
        scramble_int = [1,1,0,1,1,0,0];
        sym_bits = scramble(scramble_int, tx_bits);
        
        % 5. BPSK调制
        mod_symbols = tx_modulate(sym_bits, 'BPSK');
        
        % 6. 插入导频
        data_symbols = insert_pilot(mod_symbols);
        
        % 7. 组合帧
        trans_symbols = [sync_symbols data_symbols];
        
        % 8. SRRC成型滤波
        fir = rcosdesign(1, 128, 4);
        tx_frame = upfirdn(trans_symbols, fir, 4);
        tx_frame = [tx_frame, zeros(1, 2000)];
        
        % 9. 载波调制 (audio_fc)
        t = (0:length(tx_frame)-1) / Fs;
        tx_signal = tx_frame .* exp(1j * 2 * pi * audio_fc * t);
        
        % 10. 归一化并复制
        txdata = real(tx_signal);
        txdata = round(txdata * 2^14);
        txdata = repmat(txdata(:)', 8, 1);
        
        % 转换为复数格式
        txdata = txdata(1:min(80000,end))';
    end
    
    %% ========== 改进版接收 (完整同步链) ==========
    function [text, success, sync_info] = improved_rx(rxdata)
        text = '';
        success = false;
        sync_info = struct('freq_offset', 0, 'snr', 0, 'constellation', []);
        
        rx_signal = rxdata;
        
        % 1. 匹配滤波
        fir = rcosdesign(1, 128, 4);
        rx_sig_filter = upfirdn(rx_signal, fir, 1);
        
        % 2. 归一化
        c1 = max([abs(real(rx_sig_filter)), abs(imag(rx_sig_filter))]);
        rx_sig_norm = rx_sig_filter / c1;
        
        % 3. 定时恢复 (Gardner算法)
        [time_error, rx_sig_down] = rx_timing_recovery(rx_sig_norm);
        
        % 4. 帧同步
        local_sync = tx_modulate(tx_gen_m_seq([1 0 0 0 0 0 1]), 'BPSK');
        [rx_frame, ~, ~, ~] = rx_package_search(rx_sig_down, local_sync, 703);
        
        if isempty(rx_frame) || length(rx_frame) < 100
            return;
        end
        
        % 5. 粗频偏同步
        coarse_sync_seq = rx_frame(1:8);
        [deltaf1, out_signal1] = rx_freq_sync(coarse_sync_seq, 4, rx_frame);
        
        % 6. 细频偏同步 (两级)
        fine_sync_seq_1 = out_signal1(1:120);
        [deltaf2, out_signal2] = rx_freq_sync(fine_sync_seq_1, 2, out_signal1);
        
        fine_sync_seq_2 = out_signal2(1:120);
        [deltaf3, out_signal3] = rx_freq_sync(fine_sync_seq_2, 2, out_signal2);
        
        deltaf = deltaf1 + deltaf2 + deltaf3;
        sync_info.freq_offset = deltaf;
        
        % 7. 相位同步
        [out_signal4, ang] = rx_phase_sync(out_signal3, local_sync);
        
        % 8. 相位跟踪
        rx_no_syn_seq = out_signal4(127+1:end);
        [out_signal6, phase_curve] = rx_phase_track(rx_no_syn_seq);
        
        % 9. 删导频
        out_signal7 = rx_delete_pilot(out_signal6);
        
        % 10. 均衡
        out_signal8 = rx_time_equalize(out_signal7);
        
        % 保存星座图
        sync_info.constellation = out_signal8;
        
        % 11. 解调
        [soft_bits_out, ~] = rx_bpsk_demod(out_signal8);
        
        % 12. 解扰
        Si = [1 1 0 1 1 0 0];
        m = 0;
        for i = 1:length(soft_bits_out)
            [c, Si] = descramble(soft_bits_out(i), Si);
            m = m + 1;
            y(m) = c;
        end
        soft_bits_out = y;
        
        % 13. CRC32校验
        if length(soft_bits_out) < 32
            return;
        end
        
        ret = crc32(soft_bits_out(1:end-32)');
        crc_bits_32 = soft_bits_out(end-31:end);
        crc_outputs = sum(xor(ret, crc_bits_32), 2);
        
        if crc_outputs ~= 0
            return;  % CRC错误
        end
        
        % 14. 比特转文本
        msg = soft_bits_out(1:end-32)';
        w = [128 64 32 16 8 4 2 1];
        Nbits = numel(msg);
        Ny = Nbits / 8;
        y = zeros(1, Ny);
        for i = 0:Ny-1
            y(i+1) = w * msg(8*i + (1:8));
        end
        
        text = char(y);
        success = true;
    end
    
    %% ========== 关闭回调 ==========
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
    
    %% ========== 初始化 ==========
    addMessage('========================================', 'system');
    addMessage('PLUTO无线聊天室 v2.0 (改进版)', 'system');
    addMessage('功能: m序列同步 | CRC32校验 | 频偏纠正', 'system');
    addMessage('========================================', 'system');
    addMessage('点击"连接PLUTO"开始', 'system');
end
