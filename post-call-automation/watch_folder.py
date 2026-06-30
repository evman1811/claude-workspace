"""Central 'always-on' mode - watch a shared folder and process any call that
lands in it, automatically. Run this on ONE machine for the whole team.

Reps (or your phone system) drop a transcript (.txt) or a recording
(.mp3/.wav/.m4a) into the shared folder set by INCOMING_DIR. This scores it,
fills Salesforce, and updates the weekly sheet. Handled files move to the
'processed' subfolder; anything that errors moves to 'failed'.

Run it (and leave it running):   python watch_folder.py
On Windows, just double-click     run_watcher.bat
"""
import os
import time
import shutil
import traceback

import config
from process_call import process_call

AUDIO_EXTS = {".mp3", ".wav", ".m4a", ".mp4", ".mpeg", ".mpga", ".webm"}
TEXT_EXTS = {".txt"}
POLL_SECONDS = 10


def _process_file(path):
    ext = os.path.splitext(path)[1].lower()
    call = {
        "recording_url": None, "transcript": None, "audio_path": None,
        "caller_name": "", "caller_email": "", "caller_phone": "",
    }
    if ext in TEXT_EXTS:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            call["transcript"] = f.read()
    elif ext in AUDIO_EXTS:
        call["audio_path"] = path
    else:
        return None
    return process_call(call)


def _is_stable(path, wait=2):
    """Make sure a file has finished copying before we touch it."""
    try:
        s1 = os.path.getsize(path)
        time.sleep(wait)
        return s1 == os.path.getsize(path)
    except OSError:
        return False


def main():
    incoming = config.INCOMING_DIR
    processed = os.path.join(incoming, "processed")
    failed = os.path.join(incoming, "failed")
    for d in (incoming, processed, failed):
        os.makedirs(d, exist_ok=True)

    print(f"Watching: {os.path.abspath(incoming)}")
    print("Drop .txt transcripts or audio files here. Press Ctrl+C to stop.\n")

    while True:
        for name in sorted(os.listdir(incoming)):
            src = os.path.join(incoming, name)
            if os.path.isdir(src):
                continue
            ext = os.path.splitext(name)[1].lower()
            if ext not in TEXT_EXTS and ext not in AUDIO_EXTS:
                continue
            if not _is_stable(src):
                continue
            print(f"--> Processing {name}")
            try:
                result = _process_file(src)
                tag = f"  [{result.get('score')}/100 {result.get('rating')}]" if result else ""
                shutil.move(src, os.path.join(processed, name))
                print(f"    Done{tag}\n")
            except Exception:
                traceback.print_exc()
                try:
                    shutil.move(src, os.path.join(failed, name))
                except OSError:
                    pass
                print("    Moved to 'failed'\n")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
