def compute_crc8_atm(datagram: bytes, initial_value: int = 0) -> int:
    crc = initial_value
    # Iterate bytes in data
    for byte in datagram:
        # Iterate bits in byte
        for _ in range(8):
            if (crc >> 7) ^ (byte & 0x01):
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
            # Shift to next bit
            byte = byte >> 1
    return crc


dg = bytes([0x05, 0x00, 0x6C, 0xCA])
print(hex(compute_crc8_atm(dg[0:3])))
