from faster_whisper import WhisperModel
from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)

# Two models: while the user is still talking, Byte shows live partial text, which needs
# to come back in well under a second (tiny.en). The final transcript, the one Byte acts
# on, uses the more accurate small model. int8 + greedy decoding (beam_size=1) is several
# times faster on a Mac CPU than the defaults, with little accuracy loss for short commands.
MODELS = {
    "final": WhisperModel("small", device="cpu", compute_type="int8"),
    "partial": WhisperModel("tiny.en", device="cpu", compute_type="int8"),
}

NAME_HINT = "Hey Byte. Byte is my desktop pet."

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

@app.route('/transcribe', methods=['POST'])
def transcribe():
    # ?final=0 marks a live partial; anything else is the final transcript.
    is_final = request.args.get("final", "1") != "0"
    try:
        audio = np.frombuffer(request.get_data(), dtype=np.float32)
        print(f"Received {'final' if is_final else 'partial'} audio: {len(audio) / 16000:.1f}s")

        if audio.size == 0:
            return jsonify({"text": "", "is_final": is_final})

        model = MODELS["final" if is_final else "partial"]
        # VAD skips silence, so trailing quiet after the user stops talking costs nothing.
        # The hint teaches Whisper the pet's name; otherwise "Hey Byte" comes out "Hey Bite/Mike".
        segments, _ = model.transcribe(audio, language="en", beam_size=1, vad_filter=True,
                                       initial_prompt=NAME_HINT)
        text = " ".join([s.text for s in segments]).strip()
        print(f"Transcribed text: '{text}'")
        return jsonify({"text": text, "is_final": is_final})
    except Exception as e:
        print(f"Whisper transcription error: {e}")
        return jsonify({"error": str(e), "text": "", "is_final": is_final}), 500

if __name__ == '__main__':
    app.run(host='localhost', port=9000, threaded=True)
