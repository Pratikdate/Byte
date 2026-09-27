from flask import Flask, request, send_file, jsonify
import io
import soundfile as sf
import torch
from kokoro import KPipeline
import logging

app = Flask(__name__)
# Initialize the Kokoro pipeline for American English
pipeline = KPipeline(lang_code='a')

# Optionally map emotions to different voices if you want, but for now we use a default
default_voice = 'am_onyx'

@app.route('/health', methods=['GET'])
def health():
    # "service" lets Byte tell its own voice server apart from any other app on the port.
    return jsonify({"status": "ok", "service": "byte-kokoro-tts"}), 200

@app.route('/synthesize', methods=['POST'])
def synthesize():
    data = request.json
    text = data.get('text', '')
    speed = data.get('speed', 1.2)
    
    if not text:
        return "No text provided", 400

    print(f"Synthesizing: '{text}' at speed {speed}")

    try:
        # Generate the audio
        generator = pipeline(text, voice=default_voice, speed=speed)
        
        audio_chunks = []
        sample_rate = 24000
        for i, (gs, ps, audio) in enumerate(generator):
            if audio is not None:
                audio_chunks.append(audio)
            
        if not audio_chunks:
            return "Failed to generate audio", 500
            
        import numpy as np
        full_audio = np.concatenate(audio_chunks)
        
        # Apply a sci-fi robotic ring modulation effect
        t = np.arange(len(full_audio)) / sample_rate
        # 40 Hz gives a nice fast robotic vibration
        modulator = np.sin(2 * np.pi * 40 * t)
        # Mix original and modulated signal
        full_audio = full_audio * (0.7 + 0.3 * modulator)
            
        # Write to a bytes buffer
        buf = io.BytesIO()
        sf.write(buf, full_audio, sample_rate, format='WAV')
        buf.seek(0)
        
        return send_file(buf, mimetype='audio/wav')
        
    except Exception as e:
        print(f"TTS Error: {e}")
        return str(e), 500

if __name__ == '__main__':
    # 8880, not 8000: 8000 is the default for most dev servers (uvicorn, Django, ...), and
    # when one of those held it, Byte's voice silently broke. Override with BYTE_TTS_PORT.
    import os
    port = int(os.getenv("BYTE_TTS_PORT", "8880"))
    print(f"Starting Kokoro TTS Server on port {port}...")
    app.run(host='127.0.0.1', port=port)
