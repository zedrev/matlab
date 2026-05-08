function msg_bits = str_to_bits(msgStr)

% Convert string to ASCII values
ascii_vals = double(msgStr);

% Convert ASCII to binary without using de2bi
msgBin = [];
for k = 1:length(ascii_vals)
    % Convert to 8-bit binary (left-msb)
    val = ascii_vals(k);
    bits = zeros(1, 8);
    for b = 8:-1:1
        bits(9-b) = bitget(val, b);
    end
    msgBin = [msgBin; bits];
end

len = size(msgBin,1).*size(msgBin,2);
msg_bits = reshape(double(msgBin).',len,1).';

end

