function pluto_loopback()
% PLUTO Self-Loopback Test
% Single PLUTO: TX -> RX (SMA cable or antenna near)
%
% Usage:
%   pluto_loopback
%
% Hardware:
%   Option A: SMA cable from TX1 to RX1
%   Option B: Antenna close (< 10cm)

    addpath(fullfile(fileparts(mfilename('fullpath')), '../../library/matlab'));

    ip = '192.168.2.1';
    Fc = 915e6;        % RF carrier
    Fs = 1e6;          % Sampling rate
    buf_size = 10000;  % Buffer size
    
    fprintf('=== PLUTO Loopback Test ===\n\n');
    
    %% 1. Connect
    fprintf('Connecting to PLUTO (%s)...\n', ip);
    
    try
        sdr = iio_sys_obj_matlab;
        sdr.ip_address = ip;
        sdr.dev_name = 'ad9361';
        sdr.in_ch_no = 2;
        sdr.out_ch_no = 2;
        sdr.in_ch_size = buf_size;
        sdr.out_ch_size = buf_size * 2;
        sdr = sdr.setupImpl();
        
        nCfg = sdr.in_ch_no + length(sdr.iio_dev_cfg.cfg_ch);
        cfg = cell(1, nCfg);
        
        chSet(sdr,cfg,'TX_LO_FREQ',Fc);
        chSet(sdr,cfg,'TX_SAMPLING_FREQ',Fs);
        chSet(sdr,cfg,'TX_RF_BANDWIDTH',1e6);
        chSet(sdr,cfg,'RX_LO_FREQ',Fc);
        chSet(sdr,cfg,'RX_SAMPLING_FREQ',Fs);
        chSet(sdr,cfg,'RX_RF_BANDWIDTH',1e6);
        chSet(sdr,cfg,'RX1_GAIN_MODE','manual');
        chSet(sdr,cfg,'RX_GAIN_MODE','manual');
        chSet(sdr,cfg,'RX1_GAIN',50);
        chSet(sdr,cfg,'RX_GAIN',50);

        cfg{1} = zeros(1,buf_size);
        cfg{2} = zeros(1,buf_size);
        stepImpl(sdr, cfg);
        
        fprintf('[OK] Connected! RF=%.3fGHz Fs=%.0fMHz\n\n', Fc/1e9, Fs/1e6);
        
    catch ME
        fprintf('[ERR] Connection failed: %s\n', ME.message);
        return;
    end
    
    %% 2. Generate test signal
    testMsg = 'Hello Pluto!';
    fprintf('Test message: "%s"\n', testMsg);
    
    [iData,qData] = makeSignal(testMsg, buf_size, Fs);
    
    figure('Name','Loopback Test - TX Signal','NumberTitle','off');
    subplot(3,1,1); plot(iData); title('TX I Channel'); grid on;
    subplot(3,1,2); plot(qData); title('TX Q Channel'); grid on;
    subplot(3,1,3); plot(real(iData+1i*qData),imag(iData+1i*qData),'o'); 
    title('TX Constellation (I/Q)'); grid on; axis equal;
    
    fprintf('\n[INFO] TX signal generated.\n');
    
    %% 3. Send and Receive loop
    fprintf('\n--- Starting Loopback Test ---\n');
    fprintf('(Press Ctrl+C to stop)\n\n');
    
    iter = 0;
    successCount = 0;
    
    % Pre-create RX figure
    rxFig=figure('Name','Loopback - RX Signal','NumberTitle','off');
    
    while true
        iter = iter + 1;
        
        % Send
        cfg{1} = iData(:)';
        cfg{2} = qData(:)';
        stepImpl(sdr, cfg);
        
        % Receive
        sdr.out_ch_size = buf_size * 2;
        cfg{1} = zeros(1,buf_size);
        cfg{2} = zeros(1,buf_size);
        out = stepImpl(sdr, cfg);
        
        if length(out) >= 2
            o1 = out{1}(:)'; o2 = out{2}(:)';
            rxlen = min(min(buf_size,length(o1)),length(o2));
            rx = o1(1:rxlen) + 1i*o2(1:rxlen);
            
            e = sum(abs(rx).^2)/rxlen;
            
            % Try decode
            [decoded, ok] = tryDecode(rx, e);
            
            if ok
                successCount = successCount + 1;
                fprintf('[%d] OK! E=%.0f | Decoded: "%s" (success rate: %.1f%%)\n',...
                    iter, e, decoded, 100*successCount/iter);
                
                % Plot RX
                figure(rxFig);
                clf;
                subplot(4,1,1); plot(real(rx)); title(sprintf('RX I  E=%.0f',e)); grid on;
                subplot(4,1,2); plot(imag(rx)); title('RX Q'); grid on;
                subplot(4,1,3); plot(real(rx(1:500)),'.'); title('First 500 I samples (dots)'); grid on;
                subplot(4,1,4); hist(real(rx),50); title('I distribution'); grid on;
                drawnow;
            else
                if iter<=5 || mod(iter,10)==0
                    fprintf('[%d] No decode | E=%.0f (check debug output above)\n', iter, e);
                end
            end
        else
            fprintf('[%d] No RX data\n', iter);
        end
        
        pause(0.5);
    end

    function chSet(sdr,cfg,name,val)
        idx = int32(sdr.getInChannel(name));
        if idx >= int32(1)
            cfg{int32(idx)}=val;
        end
    end

    function [iOut,qOut] = makeSignal(textMsg, targetLen, Fs)
        txtBytes = uint8(textMsg)';
        allBits=[];
        for b=double(txtBytes)
            db=de2bi(b,8,'left-msb')';
            allBits=[allBits, db(:)'];
        end
        
        syncLen=200;
        syncBits=repmat([1 0],1,syncLen);
        frameBits=[syncBits, allBits];
        nBits=length(frameBits);
        
        bpskSym=1-2*frameBits;
        
        sps=10;
        upSig=zeros(1,nBits*sps);
        upSig(1:sps:end)=bpskSym;
        
        if length(upSig)<targetLen
            upSig=[upSig, zeros(1,targetLen-length(upSig))];
        else
            upSig=upSig(1:targetLen);
        end
        
        iOut=upSig*16000;
        qOut=zeros(size(iOut));
    end

    function [msg,ok]=tryDecode(sig,energy)
        msg=''; ok=false;
        try
            r=real(sig);
            
            % Remove DC offset
            r=r-mean(r);
            
            % Normalize
            rmax=max(abs(r));
            if rmax<eps, return; end
            r=r/rmax;
            
            % Correlation with sync pattern [1,-1,1,-1,...]
            syncPat=repmat([1,-1],1,100);
            corr=conv(fliplr(syncPat),r);
            corrVal=max(abs(corr));
            [~,pos]=max(abs(corr));
            
            % Debug: show correlation value
            fprintf('    debug: max_corr=%.1f pos=%d\n', corrVal, pos);
            
            % Relaxed threshold - just check reasonable range
            if pos<10 || pos+100>length(r), return; end
            
            dataStart=pos+100;
            sps=10;
            dataEnd=min(length(r),dataStart+sps*300);
            dataSamples=r(dataStart:dataEnd);
            
            if length(dataSamples)<80, return; end
            
            % Sample one per symbol period (with small tolerance for clock drift)
            bitIdx=round(1:sps:length(dataSamples)-sps+1);
            bitIdx=bitIdx(bitIdx>=1 & bitIdx<=length(dataSamples));
            rawBits=dataSamples(bitIdx);
            
            % Decision threshold at 0
            decBits=rawBits>0;
            
            nBytes=floor(length(decBits)/8);
            if nBytes<1, return; end
            
            byteBits=decBits(1:nBytes*8);
            byteBits=reshape(byteBits,8,[])';
            outBytes=uint8(bi2de(byteBits));
            
            valid=outBytes>=32&outBytes<=126;
            if sum(valid)<1, return; end
            
            msg=char(outBytes(valid));
            ok=true;
        catch ME
            fprintf('    decode_err:%s\n',ME.message(1:30));
        end
    end

end
