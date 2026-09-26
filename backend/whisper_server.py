from faster_whisper import WhisperModel
from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)
model = WhisperModel("small")

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

@app.route('/transcribe', methods=['POST'])
def transcribe():
    try:
        audio = np.frombuffer(request.data, dtype=np.float32)
        print(f"Received audio buffer of size: {len(audio)}")

        if audio.size == 0:
            return jsonify({"text": "", "is_final": True})

        segments, _ = model.transcribe(audio, language="en")
        text = " ".join([s.text for s in segments])
        print(f"Transcribed text: '{text}'")
        return jsonify({"text": text, "is_final": True})
    except Exception as e:
        print(f"Whisper transcription error: {e}")
        return jsonify({"error": str(e), "text": "", "is_final": True}), 500

if __name__ == '__main__':
    app.run(host='localhost', port=9000)
