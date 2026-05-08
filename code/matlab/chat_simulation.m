% PLUTO聊天仿真模式 - 不需要硬件
% 纯MATLAB仿真测试通信流程

function chat_simulation()
    clc;
    
    %% ========== 仿真参数 ==========
    Fs = 40e6;           % 采样率 40 MHz
    Fc = 100e3;          % 载波频率 100 kHz (音频范围，方便观察)
    samples_per_symbol = 16;
    snr_db = 20;         % 信噪比 (dB)
    
    fprintf('=== PLUTO聊天仿真模式 ===\n\n');
    
    %% ========== 测试用例 ==========
    test_messages = {
        'Hello!',
        '你好，世界！',
        'This is a test message.',
        'ABCabc123!@#',
        '长消息测试：这是一段比较长的文本，用于测试数据包的完整性传输功能。'
    };
    
    %% ========== 逐条测试 ==========
    for i = 1:length(test_messages)
        original_text = test_messages{i};
        fprintf('--- 测试 %d/%d ---\n', i, length(test_messages));
        fprintf('原始文本: %s\n', original_text);
        
        %% 发送端：文本 -> 信号
        fprintf('发送端: 文本 → QPSK调制 → 载波调制...\n');
        tx_signal = text_to_signal(original_text, Fs, Fc, samples_per_symbol);
        fprintf('  生成信号长度: %d 采样点\n', length(tx_signal));
        
        %% 模拟信道 (加噪声)
        fprintf('信道: 添加高斯噪声 (SNR=%ddB)...\n', snr_db);
        rx_signal = add_awgn_noise(tx_signal, snr_db);
        
        %% 接收端：信号 -> 文本
        fprintf('接收端: 下变频 → QPSK解调 → 文本...\n');
        received_text = signal_to_text(rx_signal, Fs, Fc, samples_per_symbol);
        fprintf('解码文本: %s\n', received_text);
        
        %% 验证结果
        if strcmp(original_text, received_text)
            fprintf('✓ 传输正确!\n\n');
        else
            fprintf('✗ 传输有误 (可能是长消息截断)\n\n');
        end
    end
    
    %% ========== 交互式仿真 ==========
    fprintf('=== 交互模式 ===\n');
    fprintf('输入你的消息（直接回车退出）：\n\n');
    
    while true
        text = input('TX> ', 's');
        if isempty(text)
            fprintf('仿真结束。\n');
            break;
        end
        
        % 发送
        tx_signal = text_to_signal(text, Fs, Fc, samples_per_symbol);
        rx_signal = add_awgn_noise(tx_signal, snr_db);
        received = signal_to_text(rx_signal, Fs, Fc, samples_per_symbol);
        
        fprintf('RX> %s\n\n', received);
    end
end

%% ========== 文本转信号 ==========
function signal = text_to_signal(text, Fs, Fc, sps)
    % 1. 文本转ASCII比特
    bytes = double(text);
    bits = dec2bin(bytes) - 48;
    bits = bits'; bits = bits(:);
    
    % 2. 填充到符号边界
    n_symbols = ceil(length(bits) / 2);
    bits_padded = zeros(n_symbols * 2, 1);
    bits_padded(1:length(bits)) = bits;
    
    % 3. QPSK调制 (格雷码)
    symbols = zeros(n_symbols, 1);
    for i = 1:n_symbols
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
    symbols = symbols / sqrt(2);  % 归一化
    
    % 4. 上采样
    signal_up = zeros(1, n_symbols * sps);
    for i = 1:n_symbols
        signal_up((i-1)*sps + 1) = real(symbols(i));
    end
    
    % 5. 升余弦滤波
    alpha = 0.5;
    span = 10;
    t = (-span*sps/2 : span*sps/2) / sps;
    rrc = (sin(pi*(1-alpha)*t) + 4*alpha*t.*cos(pi*(1+alpha)*t)) ./ ...
          (pi*t.*(1-(4*alpha*t).^2));
    rrc(isnan(rrc)) = 1 - alpha + 2*alpha/pi;
    rrc = rrc / sqrt(sum(rrc.^2));
    
    % 卷积滤波
    signal_up = conv(signal_up, rrc, 'same');
    
    % 6. 载波调制
    t = (0:length(signal_up)-1) / Fs;
    signal = signal_up .* exp(1j * 2 * pi * Fc * t);
    
    % 归一化
    signal = signal / max(abs(signal)) * 0.8;
end

%% ========== 信号转文本 ==========
function text = signal_to_text(signal, Fs, Fc, sps)
    % 1. 下变频
    t = (0:length(signal)-1) / Fs;
    baseband = signal .* exp(-1j * 2 * pi * Fc * t);
    
    % 2. 匹配滤波 (降余弦)
    alpha = 0.5;
    span = 10;
    t_filt = (-span*sps/2 : span*sps/2) / sps;
    rrc = (sin(pi*(1-alpha)*t_filt) + 4*alpha*t_filt.*cos(pi*(1+alpha)*t_filt)) ./ ...
          (pi*t_filt.*(1-(4*alpha*t_filt).^2));
    rrc(isnan(rrc)) = 1 - alpha + 2*alpha/pi;
    rrc = rrc / sqrt(sum(rrc.^2));
    
    baseband = conv(baseband, rrc, 'same');
    
    % 3. 采样判决
    samples = baseband(1:sps:end);
    symbols_est = samples > 0;
    
    % 4. QPSK解调
    bits = zeros(length(symbols_est) * 2, 1);
    for i = 1:length(symbols_est)
        real_bit = real(samples(i)) > 0;
        imag_bit = imag(samples(i)) > 0;
        bits(2*i-1) = real_bit;
        bits(2*i) = imag_bit;
    end
    
    % 5. 比特转文本
    try
        n_bytes = floor(length(bits) / 8);
        bytes = zeros(n_bytes, 1);
        for i = 1:n_bytes
            byte_bits = bits((i-1)*8 + (1:8));
            bytes(i) = sum(byte_bits .* 2.^(7:-1:0));
        end
        % 只保留可打印字符
        valid = bytes >= 32 & bytes <= 126;
        text = char(bytes(valid)');
        if isempty(text)
            text = '[无法解码]';
        end
    catch
        text = '[解码错误]';
    end
end

%% ========== 添加高斯噪声 ==========
function noisy = add_awgn_noise(signal, snr_db)
    % 计算信号功率
    signal_power = mean(abs(signal).^2);
    
    % 计算噪声功率
    snr_linear = 10^(snr_db/10);
    noise_power = signal_power / snr_linear;
    
    % 生成噪声
    noise = sqrt(noise_power/2) * (randn(size(signal)) + 1j*randn(size(signal)));
    
    % 添加噪声
    noisy = signal + noise;
end
