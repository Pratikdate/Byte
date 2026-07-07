from faster_whisper import WhisperModel
from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)
model = WhisperModel("small")

@app.route('/transcribe', methods=['POST'])
def transcribe():
    audio = np.frombuffer(request.data, dtype=np.float32)
    print(f"Received audio buffer of size: {len(audio)}")
    segments, _ = model.transcribe(audio, language="en")
    text = " ".join([s.text for s in segments])
    print(f"Transcribed text: '{text}'")
    return jsonify({"text": text, "is_final": True})

if __name__ == '__main__':
    app.run(host='localhost', port=9000)
