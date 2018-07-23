# aad.py
# Parse az ad app create output
# 23 Jul 2018  JMA
import os, sys
import json

ad_out = sys.stdin.read()

if len(ad_out) > 0 :
    ad_json = json.loads(ad_out)
    print("appId: ", ad_json["appId"], file=sys.stderr)
    print(ad_json["appId"])
else:
    print("No json generated", file=sys.stderr)


