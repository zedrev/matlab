% PLUTO发送端脚本 - 在电脑A上运行
% PLUTO #1 (192.168.2.1)

clear; close all; clc;
addpath('../../library/matlab');
j = 1i;

%% ========== 1. 连接SDR ==========
fprintf('连接发射端SDR (192.168.2.1)...\n');
sdr = iio_sys_obj_matlab;
sdr.ip_address = '192.168.2.1';
sdr.dev_name = 'ad9361';
sdr.in_ch_no = 2;   % 发射通道
sdr.out_ch_no = 2;  % 保留RX功能
sdr.in_ch_size = 40000;
sdr = sdr.setupImpl();

fprintf('✓ 发射端SDR已连接！\n\n');

%% ========== 2. 配置参数 ==========
Fs = 40e6;           % 采样率 40 MHz
Fc = 2e9;            % 载波频率 2 GHz
signal_len = 40000;  % 信号长度

%% ========== 3. 设置射频参数 ==========
input = cell(1, sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch));

input{sdr.getInChannel('TX_LO_FREQ')} = Fc;
input{sdr.getInChannel('TX_SAMPLING_FREQ')} = Fs;
input{sdr.getInChannel('TX_RF_BANDWIDTH')} = 20e6;
input{sdr.getInChannel('TX1_GAIN')} = 0;  % 发射增益 0-71 dB

fprintf('载波频率: %.2f GHz\n', Fc/1e9);
fprintf('采样率: %.1f MHz\n', Fs/1e6);

%% ========== 4. 循环发送信号 ==========
fprintf('\n开始发送信号...\n');
fprintf('按 Ctrl+C 停止\n\n');

i = 1;
while true
    % 生成测试信号 (单音)
    t = (0:signal_len-1) / Fs;
    tx_signal = exp(j * 2 * pi * 1e6 * t);  % 1 MHz 正弦波
    
    % 归一化
    tx_signal = tx_signal / max(abs(tx_signal));
    
    % 发送
    input{1} = real(tx_signal);
    input{2} = imag(tx_signal);
    output = stepImpl(sdr, input);
    
    fprintf('发送第 %d 帧...\n', i);
    i = i + 1;
    pause(0.1);
end

%% ========== 清理 ==========
sdr.releaseImpl();
fprintf('✓ 发射端已关闭\n');
