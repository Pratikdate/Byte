from flask import Flask, request, send_file
import io
import soundfile as sf
import torch
from kokoro import KPipeline
import logging

app = Flask(__name__)
# Initialize the Kokoro pipeline for American English
pipeline = KPipeline(lang_code='a')

# Bot-like voice options:
# 'am_puck' - High-energy, boyish, cute mascot (Best for a pet!)
# 'af_alloy' - Friendly, androgynous/female AI assistant
# 'af_sky' - Classic clear female AI
# 'af_bella' - Very sweet, soft human female
default_voice = 'am_puck'

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
    # Run the server on port 8000 (which AudioManager.swift expects)
    print("Starting Kokoro TTS Server on port 8000...")
    app.run(host='0.0.0.0', port=8000)
