% PLUTO接收端脚本 - 在电脑B上运行
% PLUTO #2 (192.168.2.1)

clear; close all; clc;
addpath('../../library/matlab');
j = 1i;

%% ========== 1. 连接SDR ==========
fprintf('连接接收端SDR (192.168.2.1)...\n');
sdr = iio_sys_obj_matlab;
sdr.ip_address = '192.168.2.1';
sdr.dev_name = 'ad9361';
sdr.in_ch_no = 2;   % 保留TX功能
sdr.out_ch_no = 2;  % 接收通道
sdr.out_ch_size = 40000;
sdr = sdr.setupImpl();

fprintf('✓ 接收端SDR已连接！\n\n');

%% ========== 2. 配置参数 ==========
Fs = 40e6;           % 采样率 40 MHz
Fc = 2e9;            % 载波频率 2 GHz
signal_len = 40000;  % 信号长度

%% ========== 3. 设置射频参数 ==========
config = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));

config{sdr.getInChannel('RX_LO_FREQ')} = Fc;
config{sdr.getInChannel('RX_SAMPLING_FREQ')} = Fs;
config{sdr.getInChannel('RX_RF_BANDWIDTH')} = 20e6;

% 尝试不同版本的RX增益通道名
rx_gain_mode_channels = {'RX1_GAIN_MODE', 'RX_GAIN_MODE'};
rx_gain_channels = {'RX1_GAIN', 'RX_GAIN', 'RX_HAD_GAIN'};

for idx = 1:length(rx_gain_mode_channels)
    ch = rx_gain_mode_channels{idx};
    ch_idx = sdr.getInChannel(ch);
    if ch_idx > 0
        config{ch_idx} = 'manual';
        fprintf('已设置 %s = manual\n', ch);
        break;
    end
end

for idx = 1:length(rx_gain_channels)
    ch = rx_gain_channels{idx};
    ch_idx = sdr.getInChannel(ch);
    if ch_idx > 0
        config{ch_idx} = 40;  % 接收增益 0-71 dB
        fprintf('已设置 %s = 40 dB\n', ch);
        break;
    end
end

fprintf('载波频率: %.2f GHz\n', Fc/1e9);
fprintf('采样率: %.1f MHz\n', Fs/1e6);

%% ========== 4. 循环接收信号 ==========
fprintf('\n开始接收信号...\n');
fprintf('按 Ctrl+C 停止\n\n');

% 创建图形窗口
figure('Name', 'SDR接收信号', 'NumberTitle', 'off');

i = 1;
while true
    % 接收
    output = stepImpl(sdr, config);
    rx_signal = double(output{1}) + j * double(output{2});
    
    % 显示
    fprintf('接收第 %d 帧 (长度: %d)\n', i, length(rx_signal));
    
    % 绘制波形
    subplot(2,2,1); plot(real(rx_signal)); title('I路'); ylim([-1 1]);
    subplot(2,2,2); plot(imag(rx_signal)); title('Q路'); ylim([-1 1]);
    subplot(2,2,3); plot(abs(rx_signal)); title('幅度'); grid on;
    subplot(2,2,4); histogram(real(rx_signal), 50); title('I路直方图');
    drawnow;
    
    % 存储最新数据到工作区
    assignin('base', 'rx_data', rx_signal);
    
    i = i + 1;
end

%% ========== 清理 ==========
sdr.releaseImpl();
fprintf('✓ 接收端已关闭\n');
