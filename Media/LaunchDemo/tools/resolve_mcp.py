"""Call the installed Resolve MCP over stdio, including in an existing Codex turn."""
import asyncio
import base64
import json
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

INSTALL = Path('/Users/gabrielgarrett/Library/Application Support/davinci-resolve-mcp')
API = '/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting'


async def main():
    env = dict(os.environ)
    env.update({
        'RESOLVE_SCRIPT_API': API,
        'RESOLVE_SCRIPT_LIB': '/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so',
        'PYTHONPATH': API + '/Modules',
        'DAVINCI_RESOLVE_MCP_UPDATE_CHECK': '0',
    })
    server = StdioServerParameters(command=str(INSTALL / 'venv/bin/python'),
                                   args=[str(INSTALL / 'src/server.py')], env=env)
    async with stdio_client(server) as (read, write):
        async with ClientSession(read, write) as client:
            init = await client.initialize()
            if sys.argv[1] == 'catalog':
                result = await client.list_tools()
                print(json.dumps({'instructions': init.instructions,
                                  'tools': [t.model_dump() for t in result.tools]}, indent=2))
            elif sys.argv[1] == 'batch':
                requests = json.loads(Path(sys.argv[2]).read_text())
                for request in requests:
                    result = await client.call_tool(request['tool'], request['arguments'])
                    data = result.structuredContent
                    if not data:
                        data = [c.model_dump() for c in result.content]
                    print(json.dumps({'tool': request['tool'], 'result': data}), flush=True)
                    if result.isError:
                        raise RuntimeError('MCP batch stopped after tool error')
            else:
                params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
                result = await client.call_tool(sys.argv[1], params)
                for i, content in enumerate(result.content):
                    if content.type == 'image':
                        ext = 'png' if content.mimeType == 'image/png' else 'jpg'
                        image_path = Path(__file__).resolve().parent.parent / 'review' / f'mcp-frame-{i}.{ext}'
                        image_path.write_bytes(base64.b64decode(content.data))
                        print(json.dumps({'image_path': str(image_path)}))
                print(json.dumps(result.structuredContent or
                                 [c.model_dump() for c in result.content if c.type != 'image'], indent=2))


if __name__ == '__main__':
    asyncio.run(main())
