#!/bin/bash

# Configuration
OLLAMA_PORT=11434
WHISPER_PORT=9000
TTS_PORT=8000

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🐾 Desktop Pet Launcher 🐾${NC}\n"

# Variables to track what we started so we can kill them later
STARTED_OLLAMA=0
STARTED_WHISPER=0
STARTED_TTS=0

# Clean up function
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    if [ $STARTED_WHISPER -eq 1 ]; then
        echo "Killing Whisper server..."
        kill $WHISPER_PID 2>/dev/null
    fi
    if [ $STARTED_TTS -eq 1 ]; then
        echo "Killing TTS server..."
        kill $TTS_PID 2>/dev/null
    fi
    if [ $STARTED_OLLAMA -eq 1 ]; then
        echo "Killing Ollama server..."
        kill $OLLAMA_PID 2>/dev/null
    fi
    echo -e "${GREEN}Done!${NC}"
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM

# Determine python executable
PYTHON_EXE="python3"
if [ -f ".venv/bin/python" ]; then
    PYTHON_EXE=".venv/bin/python"
fi

# 1. Start Ollama if needed
if lsof -Pi :$OLLAMA_PORT -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✓ Ollama is already running.${NC}"
else
    echo -e "${YELLOW}Starting Ollama server...${NC}"
    ollama serve >/dev/null 2>&1 &
    OLLAMA_PID=$!
    STARTED_OLLAMA=1
    sleep 2 # wait for it to bind
fi

# 2. Start Whisper Server if needed
if lsof -Pi :$WHISPER_PORT -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✓ Whisper server is already running.${NC}"
else
    echo -e "${YELLOW}Starting Whisper server...${NC}"
    $PYTHON_EXE backend/whisper_server.py >/dev/null 2>&1 &
    WHISPER_PID=$!
    STARTED_WHISPER=1
    sleep 2 # wait for it to bind
fi

# 3. Start TTS Server if needed
if lsof -Pi :$TTS_PORT -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✓ TTS server is already running.${NC}"
else
    echo -e "${YELLOW}Starting TTS server...${NC}"
    $PYTHON_EXE backend/tts_server.py >/dev/null 2>&1 &
    TTS_PID=$!
    STARTED_TTS=1
    sleep 2 # wait for it to bind
fi

# 3. Build the Xcode project
echo -e "\n${YELLOW}Building Desktop Pet...${NC}"
if xcodebuild -project DesktopPet.xcodeproj build >/dev/null 2>&1 ; then
    echo -e "${GREEN}✓ Build succeeded.${NC}"
else
    echo -e "${RED}✗ Build failed! Please check Xcode for errors.${NC}"
    cleanup
fi

# 4. Launch the App
echo -e "\n${GREEN}🚀 Launching Desktop Pet!${NC}"
echo -e "${YELLOW}(Press Ctrl+C in this terminal to shut down servers and exit)${NC}"

# Open the built app
open build/Release/DesktopPet.app

# Wait forever so the trap can catch Ctrl+C to clean up servers
while true; do
    sleep 1
done
