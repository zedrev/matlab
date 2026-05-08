% PLUTO接收端GUI - 简化稳定版
% 在电脑B上运行

function pluto_chat_rx_only(varargin)
    p = inputParser;
    addParameter(p, 'ip', '192.168.2.1');
    addParameter(p, 'Fc', 2.45e9);
    addParameter(p, 'Fs', 40e6);
    parse(p, varargin{:});
    
    ip = p.Results.ip;
    Fc = p.Results.Fc;
    Fs = p.Results.Fs;
    
    addpath('../../library/matlab');
    addpath('../BPSK/transmitter');
    addpath('../BPSK/receiver');
    
    % 创建简单窗口
    hFig = figure('Name', 'PLUTO接收端', 'Position', [100,100,500,400]);
    
    uicontrol('Parent', hFig, 'Style', 'text', ...
        'String', 'PLUTO接收端 - 点击连接开始', ...
        'FontSize', 14, 'Position', [100,350,300,30]);
    
    statusText = uicontrol('Parent', hFig, 'Style', 'text', ...
        'String', '状态: 未连接', ...
        'FontSize', 11, 'Position', [20,300,460,25]);
    
    msgList = uicontrol('Parent', hFig, 'Style', 'listbox', ...
        'Position', [20,50,460,240], 'FontSize', 10, 'String', {});
    
    connectBtn = uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
        'String', '连接PLUTO', ...
        'Position', [200,10,100,30], 'Callback', @connect);
    
    global sdr config;
    sdr = [];
    rx_count = 0;
    
    function addMsg(txt)
        list = get(msgList, 'String');
        if isempty(list) || ~iscell(list)
            list = {};
        end
        list = [list; {txt}];
        if length(list) > 100
            list = list(end-99:end);
        end
        set(msgList, 'String', list, 'Value', length(list));
    end
    
    function connect(~,~)
        try
            set(statusText, 'String', '连接中...');
            drawnow;
            
            sdr = iio_sys_obj_matlab;
            sdr.ip_address = ip;
            sdr.dev_name = 'ad9361';
            sdr.in_ch_no = 2;
            sdr.out_ch_no = 2;
            sdr.in_ch_size = 80000;
            sdr.out_ch_size = 160000;
            sdr = sdr.setupImpl();
            
            config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));
            config{sdr.getInChannel('TX_LO_FREQ')} = Fc;
            config{sdr.getInChannel('RX_LO_FREQ')} = Fc;
            config{sdr.getInChannel('RX_SAMPLING_FREQ')} = Fs;
            config{sdr.getInChannel('TX_SAMPLING_FREQ')} = Fs;
            config{sdr.getInChannel('RX_RF_BANDWIDTH')} = 20e6;
            config{sdr.getInChannel('TX_RF_BANDWIDTH')} = 20e6;
            
            % 设置增益
            rx_gain_idx = sdr.getInChannel('RX1_GAIN');
            if rx_gain_idx > 0
                config{rx_gain_idx} = 40;
            end
            rx_mode_idx = sdr.getInChannel('RX1_GAIN_MODE');
            if rx_mode_idx > 0
                config{rx_mode_idx} = 'manual';
            end
            
            set(statusText, 'String', '状态: 已连接，正在接收...');
            addMsg('已连接，开始接收...');
            
            % 禁用按钮
            set(connectBtn, 'String', '已连接', 'Enable', 'off');
            
            % 开始接收循环
            tx_zeros = zeros(1, 80000);
            
            while isvalid(hFig)
                try
                    config{1} = tx_zeros;
                    config{2} = tx_zeros;
                    output = stepImpl(sdr, config);
                    rx_signal = double(output{1}) + 1i*double(output{2});
                    
                    % 尝试解码
                    [msg, success] = improved_rx(rx_signal);
                    
                    if success && ~isempty(msg)
                        rx_count = rx_count + 1;
                        timeStr = datestr(now, 'HH:MM:SS');
                        addMsg(['[' timeStr '] ' msg]);
                        set(statusText, 'String', sprintf('状态: 已连接 | 收到 %d 条消息', rx_count));
                    end
                    
                    pause(0.1);
                    
                catch
                    pause(0.5);
                end
            end
            
        catch ME
            set(statusText, 'String', ['连接失败: ' ME.message]);
            addMsg(['错误: ' ME.message]);
        end
    end
    
    function [text, success] = improved_rx(rxdata)
        text = '';
        success = false;
        
        rx_signal = rxdata;
        
        try
            % 1. 匹配滤波
            fir = rcosdesign(1, 128, 4);
            rx_sig_filter = upfirdn(rx_signal, fir, 1);
            
            % 2. 归一化
            c1 = max([abs(real(rx_sig_filter)), abs(imag(rx_sig_filter))]);
            rx_sig_norm = rx_sig_filter / c1;
            
            % 3. 定时恢复
            [~, rx_sig_down] = rx_timing_recovery(rx_sig_norm);
            
            % 4. 帧同步
            local_sync = tx_modulate(tx_gen_m_seq([1 0 0 0 0 0 1]), 'BPSK');
            [rx_frame, ~, ~, ~] = rx_package_search(rx_sig_down, local_sync, 703);
            
            if isempty(rx_frame) || length(rx_frame) < 100
                return;
            end
            
            % 5. 频偏同步
            coarse_sync_seq = rx_frame(1:8);
            [deltaf1, out_signal1] = rx_freq_sync(coarse_sync_seq, 4, rx_frame);
            
            fine_sync_seq_1 = out_signal1(1:120);
            [deltaf2, out_signal2] = rx_freq_sync(fine_sync_seq_1, 2, out_signal1);
            
            fine_sync_seq_2 = out_signal2(1:120);
            [deltaf3, out_signal3] = rx_freq_sync(fine_sync_seq_2, 2, out_signal2);
            
            % 6. 相位同步
            [out_signal4, ~] = rx_phase_sync(out_signal3, local_sync);
            
            % 7. 相位跟踪
            rx_no_syn_seq = out_signal4(127+1:end);
            [out_signal6, ~] = rx_phase_track(rx_no_syn_seq);
            
            % 8. 删导频
            out_signal7 = rx_delete_pilot(out_signal6);
            
            % 9. 均衡
            out_signal8 = rx_time_equalize(out_signal7);
            
            % 10. 解调
            [soft_bits_out, ~] = rx_bpsk_demod(out_signal8);
            
            % 11. 解扰
            Si = [1 1 0 1 1 0 0];
            m = 0;
            for i = 1:length(soft_bits_out)
                [c, Si] = descramble(soft_bits_out(i), Si);
                m = m + 1;
                y(m) = c;
            end
            soft_bits_out = y;
            
            % 12. CRC校验
            if length(soft_bits_out) < 32
                return;
            end
            
            ret = crc32(soft_bits_out(1:end-32)');
            crc_bits_32 = soft_bits_out(end-31:end);
            crc_outputs = sum(xor(ret, crc_bits_32), 2);
            
            if crc_outputs ~= 0
                return;
            end
            
            % 13. 比特转文本
            msg = soft_bits_out(1:end-32)';
            w = [128 64 32 16 8 4 2 1];
            Ny = length(msg) / 8;
            y = zeros(1, Ny);
            for i = 0:Ny-1
                y(i+1) = w * msg(8*i + (1:8));
            end
            
            text = char(y);
            success = true;
            
        catch
            % 解码失败
        end
    end
    
    hFig.CloseRequestFcn = @(~,~) cleanup();
    
    function cleanup()
        try
            if ~isempty(sdr)
                sdr.releaseImpl();
            end
        end
        delete(hFig);
    end
    
    addMsg('点击"连接PLUTO"开始接收');
end
