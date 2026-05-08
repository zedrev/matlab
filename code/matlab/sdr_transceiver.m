classdef sdr_transceiver < handle
    properties
        % SDR对象
        tx_dev;  % 发射端SDR
        rx_dev;  % 接收端SDR
        
        % 配置
        tx_ip = '192.168.2.1';   % 发射端IP
        rx_ip = '192.168.2.2';   % 接收端IP (第二个SDR)
        sampling_rate = 40e6;    % 采样率
        carrier_freq = 2e9;      % 载波频率
    end
    
    methods
        function obj = sdr_transceiver()
            disp('初始化双SDR收发系统...');
            addpath('../../library/matlab');
        end
        
        function init_tx(obj)
            disp(['连接发射端SDR: ' obj.tx_ip]);
            obj.tx_dev = iio_sys_obj_matlab;
            obj.tx_dev.ip_address = obj.tx_ip;
            obj.tx_dev.dev_name = 'ad9361';
            obj.tx_dev.in_ch_no = 2;  % I/Q两路
            obj.tx_dev.out_ch_no = 0; % 只发送不接收
            obj.tx_dev = obj.tx_dev.setupImpl();
            disp('发射端SDR已连接');
        end
        
        function init_rx(obj)
            disp(['连接接收端SDR: ' obj.rx_ip]);
            obj.rx_dev = iio_sys_obj_matlab;
            obj.rx_dev.ip_address = obj.rx_ip;
            obj.rx_dev.dev_name = 'ad9361';
            obj.rx_dev.in_ch_no = 0;  % 不发送
            obj.rx_dev.out_ch_no = 2; % 只接收
            obj.rx_dev = obj.rx_dev.setupImpl();
            disp('接收端SDR已连接');
        end
        
        function init_all(obj)
            obj.init_tx();
            obj.init_rx();
        end
        
        function transmit(obj, signal)
            % 将信号发送到TX SDR
            if abs(max(real(signal))) > 1 || abs(max(imag(signal))) > 1
                signal = signal / max(max(abs(real(signal))), max(abs(imag(signal))));
            end
            
            input{1} = real(signal);
            input{2} = imag(signal);
            
            output = stepImpl(obj.tx_dev, input);
            disp('信号已发送');
        end
        
        function rx_data = receive(obj, num_samples)
            % 从RX SDR接收数据
            obj.rx_dev.out_ch_size = num_samples;
            
            input = cell(1, obj.rx_dev.in_ch_no + length(obj.rx_dev.iio_dev_cfg.cfg_ch));
            output = stepImpl(obj.rx_dev, input);
            
            rx_data = double(output{1}) + 1i*double(output{2});
            disp(['接收完成，共 ' num2str(length(rx_data)) ' 个采样点']);
        end
        
        function tx_rx_loop(obj, signal, num_samples)
            % 发送并接收 (收发同时)
            if abs(max(real(signal))) > 1 || abs(max(imag(signal))) > 1
                signal = signal / max(max(abs(real(signal))), max(abs(imag(signal))));
            end
            
            input_tx{1} = real(signal);
            input_tx{2} = imag(signal);
            input_rx = cell(1, obj.rx_dev.in_ch_no + length(obj.rx_dev.iio_dev_cfg.cfg_ch));
            
            % 发送
            stepImpl(obj.tx_dev, input_tx);
            
            % 接收
            output = stepImpl(obj.rx_dev, input_rx);
            rx_data = double(output{1}) + 1i*double(output{2});
            
            disp('收发完成');
        end
        
        function release(obj)
            if ~isempty(obj.tx_dev)
                obj.tx_dev.releaseImpl();
            end
            if ~isempty(obj.rx_dev)
                obj.rx_dev.releaseImpl();
            end
            disp('资源已释放');
        end
    end
end
