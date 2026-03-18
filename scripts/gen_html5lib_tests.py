#!/usr/bin/env python3

"""Generate test cases for ekdy using the test cases developed for html5lib.
Expected text output for ekdy is obtained from the chromium browser.

Tets cases are read from stdin in html5lib-tests format.
Outputs are written to stdout in the following format, for each case:

#data
[html]
#text
[inner text of chromium]
"""

import argparse
import sys
import websocket
import subprocess
import json
import tempfile
import urllib.request
import time
from typing import TextIO, Optional

ws_msg_id = 1

def ws_wait_reload(ws: websocket.WebSocket):
    while True:
        resp = json.loads(ws.recv())
        if resp.get("method") == "Page.loadEventFired":
            break

def read_test_html(stream: TextIO) -> Optional[str]:
    html_lines = []
    in_data = False
    for line in stream:
        line = line.rstrip()
        if in_data and (line == "#errors" or line == "#document"):
            return "\n".join(html_lines)

        if line == "#data":
            assert(not in_data)
            in_data = True
        elif in_data:
            html_lines.append(line)

    return None

def ws_response(ws: websocket.WebSocket, req_id: int) -> dict:
    while True:
        resp = json.loads(ws.recv())
        if "id" in resp and resp["id"] == req_id:
            return resp["result"]

def send_ws_message(ws: websocket.WebSocket, msg: dict) -> int:
    global ws_msg_id
    curr_id = ws_msg_id
    msg_w_id = {"id": curr_id} | msg
    ws.send(json.dumps(msg_w_id))
    ws_msg_id += 1
    return curr_id

def create_ws(port: int) -> websocket.WebSocket:
    targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
    ws_url = None
    for target in targets:
        if "type" not in target:
            continue

        if target["type"] == "page":
            ws_url = target["webSocketDebuggerUrl"]
            break

    if ws_url is None:
        raise Exception("Could not find websocket uri")

    return websocket.create_connection(ws_url)

def run_headless(port: int) -> subprocess.Popen:
    chromium_proc = subprocess.Popen(
        [
            "chromium",
            "--headless",
            f"--remote-debugging-port={port}",
            "--remote-allow-origins=*",
            "about:blank",
        ]
    )
    if (ret_code := chromium_proc.poll()) is not None:
        raise Exception(f"chromium exited with: {ret_code}")

    return chromium_proc

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--port", type=int, default=7469)
    args = parser.parse_args()
    chromium_proc = run_headless(args.port)
    time.sleep(5)
    try:
        ws = create_ws(args.port)
        send_ws_message(ws, {"method": "Page.enable"})
        send_ws_message(ws, {
                "method": "Emulation.setScriptExecutionDisabled",
                "params": {"value": True},
        })
        with tempfile.NamedTemporaryFile("w", suffix=".html") as temp_html:
            nav_id = send_ws_message(
                ws,
                {"method": "Page.navigate", "params": {"url": f"file://{temp_html.name}"}},
            )
            nav_res = ws_response(ws, nav_id)
            if "errorText" in nav_res:
                raise Exception(f"Navigation failed: {nav_res}")
            ws_wait_reload(ws)
            while True:
                html_code = read_test_html(sys.stdin)
                if html_code is None:
                    break

                temp_html.seek(0)
                temp_html.truncate()
                temp_html.write(html_code)
                temp_html.flush()
                send_ws_message(ws, {"method": "Page.reload", "params": {"ignoreCache": True}})
                ws_wait_reload(ws)
                text_id = send_ws_message(
                    ws,
                    {
                        "method": "Runtime.evaluate",
                        "params": {"expression": "document.body.innerText", "returnByValue": True},
                    }
                )
                text_resp = ws_response(ws, text_id)
                print("#data")
                print(html_code)
                print("#text")
                val = text_resp["result"]["value"]
                # When there is absolutely no text, chromium just inserts a new line?
                if val == "\n":
                    val = ""
                print(val)
            ws.close()

    finally:
        chromium_proc.kill()

if __name__ == "__main__":
    sys.exit(main())
