classdef pluto_chat_modem < handle
    % 文本到信号的调制解调器
    
    properties
        % 调制参数
        samples_per_symbol = 16;  % 每个符号的采样点数
        carrier_freq = 1e6;        % 载波频率 1 MHz
        Fs = 40e6;                 % 采样率 40 MHz
        frame_size = 1000;         % 每帧发送的符号数
    end
    
    methods
        function textToSignal(obj, text)
            % 将文本转换为发送信号
            % text: 字符数组或字符串
        end
        
        function signal = textToSignal(obj, text)
            % 1. 文本转比特
            bits = obj.textToBits(text);
            
            % 2. 填充到帧大小
            total_symbols = obj.frame_size;
            bits_padded = obj.padBits(bits, total_symbols);
            
            % 3. QPSK调制
            symbols = obj.bitsToQPSK(bits_padded);
            
            % 4. 成型滤波 (根升余弦)
            % 简化为矩形脉冲
            
            % 5. 载波调制
            t = (0:length(symbols)*obj.samples_per_symbol-1) / obj.Fs;
            tx_signal = real(symbols(:) * ones(1, obj.samples_per_symbol) .') .* ...
                        exp(1j * 2 * pi * obj.carrier_freq * t);
        end
        
        function bits = signalToText(obj, signal)
            % 从接收信号提取文本
        end
        
        function text = decodeSignal(obj, signal)
            % 1. 载波解调
            t = (0:length(signal)-1) / obj.Fs;
            baseband = signal .* exp(-1j * 2 * pi * obj.carrier_freq * t);
            
            % 2. 匹配滤波
            % 简化处理
            
            % 3. QPSK解调
            % 采样判决
            
            % 4. 比特到文本
            % text = obj.bitsToText(bits);
            text = '[解码中...]';
        end
    end
    
    methods (Access = private)
        function bits = textToBits(obj, text)
            % 文本转比特
            if isstring(text)
                text = char(text);
            end
            bits = double(dec2bin(text)) - 48;
            bits = bits.'; % 转置为行向量
        end
        
        function text = bitsToText(obj, bits)
            % 比特转文本
            bytes = bi2de(reshape(bits, 8, [])');
            text = char(bytes);
        end
        
        function symbols = bitsToQPSK(obj, bits)
            % 比特到QPSK符号 (格雷码映射)
            % 00 -> 1+1j, 01 -> -1+1j, 10 -> 1-1j, 11 -> -1-1j
            
            % 将比特每2个一组
            bit_pairs = reshape(bits, 2, [])';
            
            % 格雷码映射
            symbols = zeros(length(bit_pairs), 1);
            for i = 1:length(bit_pairs)
                if bit_pairs(i,1) == 0 && bit_pairs(i,2) == 0
                    symbols(i) = 1 + 1j;
                elseif bit_pairs(i,1) == 0 && bit_pairs(i,2) == 1
                    symbols(i) = -1 + 1j;
                elseif bit_pairs(i,1) == 1 && bit_pairs(i,2) == 0
                    symbols(i) = 1 - 1j;
                else
                    symbols(i) = -1 - 1j;
                end
            end
            symbols = symbols / sqrt(2); % 归一化
        end
        
        function bits_padded = padBits(obj, bits, total_symbols)
            % 填充比特以匹配帧大小 (QPSK每符号2比特)
            total_bits = total_symbols * 2;
            bits_padded = zeros(total_bits, 1);
            bits_padded(1:min(length(bits), total_bits)) = ...
                bits(1:min(length(bits), total_bits));
        end
    end
end
