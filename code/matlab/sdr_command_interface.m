% 双SDR命令行交互界面
% 使用方法：在MATLAB命令窗口中运行后，按提示输入命令

function sdr_command_interface()
    clc;
    disp('========================================');
    disp('   双AD9361 SDR 命令行交互界面');
    disp('========================================');
    disp('提示: 输入help查看可用命令');
    disp('');
    
    % 初始化SDR
    sdr = sdr_transceiver();
    
    try
        % 自动连接两个SDR
        disp('正在连接SDR设备...');
        addpath('../../library/matlab');
        
        % 发射端SDR (PLUTO #1)
        tx_dev = iio_sys_obj_matlab;
        tx_dev.ip_address = '192.168.2.1';
        tx_dev.dev_name = 'ad9361';
        tx_dev.in_ch_no = 2;
        tx_dev.out_ch_no = 0;
        tx_dev = tx_dev.setupImpl();
        
        % 接收端SDR (PLUTO #2)
        rx_dev = iio_sys_obj_matlab;
        rx_dev.ip_address = '192.168.2.10';
        rx_dev.dev_name = 'ad9361';
        rx_dev.in_ch_no = 0;
        rx_dev.out_ch_no = 2;
        rx_dev = rx_dev.setupImpl();
        
        disp('✓ 双SDR连接成功！');
        disp('');
        
        % 命令循环
        while true
            try
                cmd = input('SDR>> ', 's');
                cmd = strtrim(cmd);
                
                if isempty(cmd)
                    continue;
                end
                
                % 解析命令
                parts = strsplit(cmd, ' ');
                main_cmd = lower(parts{1});
                
                switch main_cmd
                    case 'help'
                        disp_help();
                        
                    case 'tx'
                        % 发送信号
                        if length(parts) < 2
                            disp('用法: tx <信号表达式>');
                            disp('示例: tx sin(2*pi*1e6*t)'); 
                            disp('      tx exp(j*2*pi*1e6*t)');
                            continue;
                        end
                        signal_expr = cmd(3:end);
                        send_signal(tx_dev, signal_expr);
                        
                    case 'txfile'
                        % 发送文件中的信号
                        if length(parts) < 2
                            disp('用法: txfile <文件名>');
                            continue;
                        end
                        send_signal_file(tx_dev, parts{2});
                        
                    case 'rx'
                        % 接收信号
                        n = 4096;
                        if length(parts) >= 2
                            n = str2double(parts{2});
                        end
                        rx_data = receive_signal(rx_dev, n);
                        assignin('base', 'rx_data', rx_data);
                        disp(['信号已保存到变量: rx_data (长度: ' num2str(length(rx_data)) ')']);
                        
                    case 'txrx'
                        % 发送并接收
                        if length(parts) < 2
                            disp('用法: txrx <信号表达式>');
                            continue;
                        end
                        signal_expr = cmd(5:end);
                        [tx_sig, rx_sig] = send_receive(tx_dev, rx_dev, signal_expr);
                        assignin('base', 'tx_signal', tx_sig);
                        assignin('base', 'rx_signal', rx_sig);
                        disp('发送和接收信号已保存到: tx_signal, rx_signal');
                        
                    case 'bpsk'
                        % 发送BPSK调制信号
                        send_bpsk(tx_dev);
                        
                    case 'tone'
                        % 发送单音信号
                        freq = 1e6;
                        if length(parts) >= 2
                            freq = str2double(parts{2});
                        end
                        send_tone(tx_dev, freq);
                        
                    case 'config'
                        % 配置参数
                        config_devices(tx_dev, rx_dev, parts{2:end});
                        
                    case 'quit'
                        break;
                        
                    otherwise
                        disp(['未知命令: ' main_cmd]);
                        disp('输入 help 查看可用命令');
                end
                
            catch ME
                disp(['错误: ' ME.message]);
            end
        end
        
    catch ME
        disp(['初始化错误: ' ME.message]);
    end
    
    % 释放资源
    if exist('tx_dev', 'var')
        tx_dev.releaseImpl();
    end
    if exist('rx_dev', 'var')
        rx_dev.releaseImpl();
    end
    disp('SDR已断开连接');
end

function disp_help()
    disp('');
    disp('可用命令:');
    disp('  help      - 显示此帮助信息');
    disp('  tx <expr> - 发送信号 (如: tx exp(j*2*pi*1e6*t))');
    disp('  txfile <f>- 从文件加载信号并发送');
    disp('  rx [N]    - 接收N个采样点 (默认4096)');
    disp('  txrx <expr>- 发送信号并同时接收');
    disp('  bpsk      - 发送BPSK调制信号');
    disp('  tone [f]  - 发送单音信号 (默认1MHz)');
    disp('  config    - 配置SDR参数');
    disp('  quit      - 退出程序');
    disp('');
    disp('示例:');
    disp('  tx exp(j*2*pi*1e6*(0:0.1e-6:1e-3))');
    disp('  rx 8192');
    disp('  txrx sin(2*pi*5e6*t)');
    disp('');
end

function send_signal(tx_dev, signal_expr)
    try
        t = 0:1/40e6:1e-3;  % 默认1ms信号
        signal = eval(signal_expr);
        signal = signal(:).';
        
        % 归一化
        if max(abs(signal)) > 1
            signal = signal / max(abs(signal));
        end
        
        % 转换为IQ格式
        input{1} = real(signal);
        input{2} = imag(signal);
        
        stepImpl(tx_dev, input);
        disp('✓ 信号已发送');
    catch ME
        disp(['信号解析错误: ' ME.message]);
    end
end

function send_signal_file(tx_dev, filename)
    try
        load(filename);
        if exist('txdata', 'var')
            signal = txdata;
        else
            error('文件中未找到txdata变量');
        end
        
        input{1} = real(signal);
        input{2} = imag(signal);
        stepImpl(tx_dev, input);
        disp(['✓ 文件 ' filename ' 已发送']);
    catch ME
        disp(['文件加载错误: ' ME.message]);
    end
end

function rx_data = receive_signal(rx_dev, num_samples)
    rx_dev.out_ch_size = num_samples;
    input = cell(1, rx_dev.in_ch_no);
    output = stepImpl(rx_dev, input);
    rx_data = double(output{1}) + 1i*double(output{2});
end

function [tx_sig, rx_sig] = send_receive(tx_dev, rx_dev, signal_expr)
    t = 0:1/40e6:1e-3;
    tx_sig = eval(signal_expr);
    tx_sig = tx_sig(:).';
    
    if max(abs(tx_sig)) > 1
        tx_sig = tx_sig / max(abs(tx_sig));
    end
    
    % 发送
    input_tx{1} = real(tx_sig);
    input_tx{2} = imag(tx_sig);
    stepImpl(tx_dev, input_tx);
    
    % 接收
    rx_dev.out_ch_size = length(tx_sig);
    input_rx = cell(1, rx_dev.in_ch_no);
    output = stepImpl(rx_dev, input_rx);
    rx_sig = double(output{1}) + 1i*double(output{2});
end

function send_bpsk(tx_dev)
    bits = randi([0 1], 1, 1000);
    symbols = 2*bits - 1;
    
    input{1} = real(symbols);
    input{2} = imag(symbols);
    stepImpl(tx_dev, input);
    disp('✓ BPSK信号已发送');
end

function send_tone(tx_dev, freq)
    t = 0:1/40e6:1e-3;
    signal = exp(1i*2*pi*freq*t);
    
    input{1} = real(signal);
    input{2} = imag(signal);
    stepImpl(tx_dev, input);
    disp(['✓ ' num2str(freq/1e6) ' MHz 单音信号已发送']);
end

function config_devices(tx_dev, rx_dev, params)
    % 配置SDR参数
    % 格式: config rx_lo 2.4e9 tx_lo 2.4e9
    disp('参数配置功能开发中...');
end
