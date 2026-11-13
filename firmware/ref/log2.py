import json

log = {
    "slide": [
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1004},
            {"value": 0, "pos": 4992},
            {"value": 1, "pos": 5029},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 999},
            {"value": 0, "pos": 4998},
            {"value": 1, "pos": 5028},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 990},
            {"value": 0, "pos": 4995},
            {"value": 1, "pos": 5029},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1004},
        ],
    ],
    "blank": [
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1143},
            {"value": 0, "pos": 2720},
            {"value": 1, "pos": 3298},
            {"value": 0, "pos": 4955},
            {"value": 1, "pos": 5025},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1184},
            {"value": 0, "pos": 2616},
            {"value": 1, "pos": 3385},
            {"value": 0, "pos": 3981},
            {"value": 1, "pos": 3996},
            {"value": 0, "pos": 4869},
            {"value": 1, "pos": 5025},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1137},
            {"value": 0, "pos": 1174},
            {"value": 1, "pos": 1243},
            {"value": 0, "pos": 1275},
            {"value": 1, "pos": 5025},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1053},
            {"value": 0, "pos": 2695},
            {"value": 1, "pos": 3311},
            {"value": 0, "pos": 4948},
            {"value": 1, "pos": 5024},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1343},
            {"value": 0, "pos": 1383},
            {"value": 1, "pos": 1399},
            {"value": 0, "pos": 1444},
            {"value": 1, "pos": 1539},
            {"value": 0, "pos": 2652},
            {"value": 1, "pos": 3380},
            {"value": 0, "pos": 4017},
            {"value": 1, "pos": 4030},
            {"value": 0, "pos": 4075},
            {"value": 1, "pos": 4395},
            {"value": 0, "pos": 4403},
            {"value": 1, "pos": 4691},
            {"value": 0, "pos": 4843},
            {"value": 1, "pos": 5025},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1042},
            {"value": 0, "pos": 2689},
            {"value": 1, "pos": 3264},
            {"value": 0, "pos": 4957},
            {"value": 1, "pos": 5024},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 2092},
            {"value": 0, "pos": 2101},
            {"value": 1, "pos": 5026},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1140},
            {"value": 0, "pos": 2676},
            {"value": 1, "pos": 3332},
            {"value": 0, "pos": 4934},
            {"value": 1, "pos": 5026},
        ],
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 1077},
            {"value": 0, "pos": 2709},
            {"value": 1, "pos": 3292},
            {"value": 0, "pos": 4971},
            {"value": 1, "pos": 5025},
        ],
    ],
    "empty": [
        [
            {"value": 0, "pos": 0},
            {"value": 1, "pos": 5025},
        ],
    ],
}

event = 1
id = 1
for kind, events in log.items():
    for ev in events:
        for row in ev:
            rec = {"id": id, "event": event, "kind": kind, **row}
            print(json.dumps(rec))
            id += 1
        event += 1
