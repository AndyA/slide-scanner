import json
from collections import deque
from time import sleep
from typing import Any

import serial


def read_resonse(ser: serial.Serial) -> Any:
    buf = bytearray()
    while True:
        byte = ser.read()
        if byte == b"\n":
            break
        buf.append(ord(byte))
    return json.loads(buf)


ser = serial.Serial("/dev/tty.usbmodemfeeder1", 115200)

pipeline = deque()

# ser.write(b"calibrate\n")
while True:
    ser.write(b"advance\n")
    res = read_resonse(ser)["result"]
    print(res)
    if res == "AdvanceEmpty":
        break
    pipeline.append(res)
    if len(pipeline) == 2:
        loaded = pipeline.popleft()
        if loaded == "AdvanceSlide":
            print("Scanning slide...")
            sleep(5)
            print("Scanned")
