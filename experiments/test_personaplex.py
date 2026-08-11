#!/usr/bin/env python3
"""
Test Suite for NVIDIA PersonaPlex-7B-v1 Integration
Reference: https://huggingface.co/nvidia/personaplex-7b-v1

This script verifies:
1. HuggingFace authentication and gated model status check.
2. Persona text and voice prompt conditioning logic.
3. Audio generation and WAV byte stream synthesis.
4. FastAPI server endpoints (/health, /prompt, /synthesize_speech).
5. WebSocket full-duplex framing protocol.
"""

import sys
import os
import io
import json
import unittest
import numpy as np
from pathlib import Path

# Ensure root workspace and backend are in path
workspace_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(workspace_dir))
sys.path.insert(0, str(workspace_dir / "backend"))

from fastapi.testclient import TestClient
from backend.personaplex_server import app, model_mgr, MODEL_ID

class TestPersonaPlex7B(unittest.TestCase):

    def setUp(self):
        self.client = TestClient(app)
        # Ensure test runs in deterministic mock mode unless HF_TOKEN is explicitly set
        model_mgr.load_model(force_mock=not bool(os.getenv("HF_TOKEN")))

    def test_01_model_id_and_gated_status(self):
        """Verify model ID matches huggingface.co/nvidia/personaplex-7b-v1"""
        self.assertEqual(MODEL_ID, "nvidia/personaplex-7b-v1")
        self.assertTrue(hasattr(model_mgr, "check_hf_auth"))
        auth_status = model_mgr.check_hf_auth()
        print(f"HuggingFace Auth Status for {MODEL_ID}: {auth_status}")

    def test_02_health_endpoint(self):
        """Verify GET /health endpoint structure"""
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "ok")
        self.assertEqual(data["model_id"], MODEL_ID)
        self.assertIn("is_loaded", data)
        self.assertIn("device", data)
        self.assertIn("hf_authenticated", data)
        print(f"Health response: {data}")

    def test_03_prompt_conditioning(self):
        """Verify POST /prompt updates persona text and voice prompts"""
        new_text_prompt = "You are Byte, an energetic sci-fi companion robot."
        new_voice_prompt = "robotic_beam"
        
        response = self.client.post("/prompt", json={
            "text_prompt": new_text_prompt,
            "voice_prompt": new_voice_prompt
        })
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "updated")
        self.assertEqual(data["text_prompt"], new_text_prompt)
        self.assertEqual(data["voice_prompt"], new_voice_prompt)

    def test_04_synthesize_speech_audio_generation(self):
        """Verify POST /synthesize_speech generates valid WAV audio stream"""
        response = self.client.post("/synthesize_speech", json={
            "text": "Hello, I am testing PersonaPlex 7B!",
            "speed": 1.0
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "audio/wav")
        audio_bytes = response.content
        self.assertGreater(len(audio_bytes), 100)
        
        # Header check for RIFF WAV
        self.assertTrue(audio_bytes.startswith(b"RIFF"))
        print(f"Synthesized speech WAV size: {len(audio_bytes)} bytes")

    def test_05_websocket_full_duplex_framing(self):
        """Verify /ws/duplex WebSocket handshake and framing protocol"""
        with self.client.websocket_connect("/ws/duplex") as websocket:
            handshake = websocket.receive_json()
            self.assertEqual(handshake["type"], "handshake")
            self.assertEqual(handshake["model"], MODEL_ID)

            # Send test text input message
            websocket.send_json({"type": "text_input", "text": "Are you ready?"})
            
            resp_text = websocket.receive_json()
            self.assertEqual(resp_text["type"], "response_text")
            self.assertIn("Byte", resp_text["content"])

            resp_audio = websocket.receive_json()
            self.assertEqual(resp_audio["type"], "audio_frame")
            self.assertTrue(resp_audio["is_final"])

    def test_06_direct_voice_to_voice_binary_streaming(self):
        """Verify direct end-to-end voice-to-voice streaming without intermediate systems"""
        with self.client.websocket_connect("/ws/duplex") as websocket:
            handshake = websocket.receive_json()
            self.assertEqual(handshake["type"], "handshake")

            # Send raw audio PCM bytes directly (simulating microphone audio stream)
            dummy_pcm_in = (0.1 * np.sin(np.linspace(0, 1, 1920))).astype(np.float32).tobytes()
            websocket.send_bytes(dummy_pcm_in)

            # Receive raw output audio PCM bytes directly (simulating speaker audio stream)
            response_pcm_out = websocket.receive_bytes()
            self.assertGreater(len(response_pcm_out), 0)
            print(f"Direct Voice-to-Voice: Received {len(response_pcm_out)} bytes output audio stream.")

if __name__ == "__main__":
    print("=" * 60)
    print("Running Test Suite for nvidia/personaplex-7b-v1...")
    print("=" * 60)
    unittest.main()
