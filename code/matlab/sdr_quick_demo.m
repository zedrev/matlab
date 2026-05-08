% 双SDR快速使用示例
% 使用前确保两个SDR的IP地址正确配置

clear; close all; clc;
addpath('../../library/matlab');
j = 1i;

%% ========== 1. 连接两个SDR ==========
fprintf('连接发射端SDR (192.168.2.10 - PLUTO #1)...\n');
tx_dev = iio_sys_obj_matlab;
tx_dev.ip_address = '192.168.2.10';
tx_dev.dev_name = 'ad9361';
tx_dev.in_ch_no = 2;
tx_dev.out_ch_no = 0;
tx_dev = tx_dev.setupImpl();

fprintf('连接接收端SDR (192.168.2.1 - PLUTO #2)...\n');
rx_dev = iio_sys_obj_matlab;
rx_dev.ip_address = '192.168.2.1';
rx_dev.dev_name = 'ad9361';
rx_dev.in_ch_no = 0;
rx_dev.out_ch_no = 2;
rx_dev = rx_dev.setupImpl();

fprintf('✓ 双SDR连接成功！\n\n');

%% ========== 2. 配置参数 ==========
Fs = 40e6;           % 采样率 40 MHz
Fc = 2e9;            % 载波频率 2 GHz
signal_len = 40000;  % 信号长度

%% ========== 3. 生成测试信号 ==========
% 示例1: 单音信号
t = (0:signal_len-1) / Fs;
tx_signal = exp(j * 2 * pi * 1e6 * t);  % 1 MHz 正弦波

% 示例2: BPSK调制
% bits = randi([0 1], 1, 1000);
% tx_signal = 2*bits - 1;

% 示例3: 线性调频信号
% t = (0:signal_len-1) / Fs;
% tx_signal = exp(j * pi * 1e12 * t.^2);  % Chirp信号

%% ========== 4. 发送信号 ==========
fprintf('发送信号...\n');
tx_signal_norm = tx_signal / max(abs(tx_signal));  % 归一化
input{1} = real(tx_signal_norm);
input{2} = imag(tx_signal_norm);
stepImpl(tx_dev, input);
fprintf('✓ 信号已发送\n');

%% ========== 5. 接收信号 ==========
fprintf('接收信号...\n');
rx_dev.out_ch_size = signal_len;
input_rx = cell(1, 0);  % 无配置参数
output = stepImpl(rx_dev, input_rx);
rx_signal = double(output{1}) + j * double(output{2});
fprintf('✓ 信号已接收 (长度: %d)\n', length(rx_signal));

%% ========== 6. 分析结果 ==========
figure;
subplot(2,2,1); plot(real(tx_signal)); title('TX I路'); xlabel('采样点');
subplot(2,2,2); plot(imag(tx_signal)); title('TX Q路'); xlabel('采样点');
subplot(2,2,3); plot(real(rx_signal)); title('RX I路'); xlabel('采样点');
subplot(2,2,4); plot(imag(rx_signal)); title('RX Q路'); xlabel('采样点');

%% ========== 7. 清理 ==========
fprintf('\n释放SDR资源...\n');
tx_dev.releaseImpl();
rx_dev.releaseImpl();
fprintf('✓ 完成！\n');
