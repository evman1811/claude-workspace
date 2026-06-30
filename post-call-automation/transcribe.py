"""Step 1 - turn a call into text.

You can hand this three things, in order of preference:
  1. existing_transcript - text you already have (no API call needed)
  2. audio_path          - a local recording file (mp3/wav/m4a); Whisper transcribes it
  3. recording_url       - a link to a recording; we download then transcribe it
"""
import os
import tempfile

import requests
from openai import OpenAI

import config


def transcribe(recording_url=None, existing_transcript=None, audio_path=None):
    # 1) Best case: you already have the transcript text.
    if existing_transcript:
        return existing_transcript.strip()

    # 2) A local audio file you provide.
    if audio_path:
        return _whisper(audio_path)

    # 3) A remote recording URL - download to a temp file, then transcribe.
    if recording_url:
        resp = requests.get(recording_url, timeout=120)
        resp.raise_for_status()
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as f:
            f.write(resp.content)
            tmp = f.name
        try:
            return _whisper(tmp)
        finally:
            os.remove(tmp)

    raise ValueError("Provide existing_transcript, audio_path, or recording_url.")


def _whisper(audio_path):
    client = OpenAI(api_key=config.OPENAI_API_KEY)
    with open(audio_path, "rb") as audio_file:
        result = client.audio.transcriptions.create(model="whisper-1", file=audio_file)
    return result.text.strip()
