import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
import uvicorn
import json
import httpx

app = FastAPI()

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

manager = ConnectionManager()

async def ollama_stream(websocket: WebSocket, prefix: str):
    """
    Streams response from local Ollama instance in real-time.
    """
    url = "http://localhost:11434/api/generate"
    payload = {
        "model": "llama3.2:latest",
        "prompt": f"Respond conversationally and concisely to the following input: {prefix}",
        "stream": True
    }
    
    try:
        async with httpx.AsyncClient() as client:
            async with client.stream("POST", url, json=payload, timeout=None) as response:
                async for line in response.aiter_lines():
                    if line:
                        data = json.loads(line)
                        if "response" in data:
                            token = data["response"]
                            await websocket.send_text(json.dumps({"type": "token", "content": token}))
                        if data.get("done"):
                            await websocket.send_text(json.dumps({"type": "done"}))
                            break
    except asyncio.CancelledError:
        # Crucial part: task cancelled by new keystroke
        pass
    except Exception as e:
        print(f"Error during stream: {e}")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    
    current_task = None
    
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "input":
                user_text = message.get("text", "")
                
                # If there's an active generation, cancel it instantly!
                if current_task and not current_task.done():
                    current_task.cancel()
                
                # If the user cleared the text box, just clear the prediction
                if not user_text.strip():
                    await websocket.send_text(json.dumps({"type": "clear"}))
                    continue
                
                # Tell the client we are starting a new stream
                await websocket.send_text(json.dumps({"type": "clear"}))
                
                # Start a new LLM generation task based on the current input
                current_task = asyncio.create_task(ollama_stream(websocket, user_text))
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        if current_task and not current_task.done():
            current_task.cancel()

# Serve the index.html directly from root for convenience
@app.get("/")
async def get():
    with open("index.html", "r") as f:
        html_content = f.read()
    return HTMLResponse(content=html_content)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
