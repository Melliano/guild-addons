"""Run the Lua test suite with lupa (pip install lupa) when no lua5.1 binary is around."""
import os, sys
import lupa.lua51 as lua51

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
L = lua51.LuaRuntime()
L.execute("os.exit = function(code) error('exit:' .. tostring(code), 0) end")
try:
    L.execute(open("tests/sync_test.lua").read())
except lua51.LuaError as e:
    msg = str(e)
    if msg.startswith("exit:"):
        sys.exit(int(msg[5:].split()[0]))
    raise
