function ret = crc32(bits)
% CRC-32 polynomial: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + 
%                    x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1
% Hex representation: 0xEDB88320 (reversed)
% Convert hex to binary without de2bi
hex_val = hex2dec('EDB88320');
poly_bits = zeros(1, 32);
for b = 1:32
    poly_bits(b) = bitget(hex_val, b);
end
poly = [1 poly_bits]';

bits = bits(:);

% Flip first 32 bits
bits(1:32) = 1 - bits(1:32);
% Add 32 zeros at the back
bits = [bits; zeros(32,1)];

% Initialize remainder to 0
rem = zeros(32,1);
% Main compution loop for the CRC32
for i = 1:length(bits)
    rem = [rem; bits(i)]; %#ok<AGROW>
    if rem(1) == 1
        rem = xor(rem,poly);%mod(rem + poly, 2);
    end
    rem = rem(2:33);
end

% Flip the remainder before returning it
ret = 1 - rem;
end
