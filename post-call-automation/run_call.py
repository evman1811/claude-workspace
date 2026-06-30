"""Run ONE call through the system by hand - no phone connection needed.

You bring the call as EITHER:
  --transcript call.txt   a text transcript you already have
  --audio call.mp3        an audio recording (Whisper turns it into text)

Examples:
  python run_call.py --transcript call.txt --name "Maria Lopez" --email maria@acme.com
  python run_call.py --audio call.mp3 --name "Maria Lopez" --phone "+1 555 0142"

Anything you don't pass on the command line, Claude tries to pull from the call.
"""
import argparse
import sys

from process_call import process_call


def main():
    parser = argparse.ArgumentParser(description="Score one sales call and save it.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--transcript", help="Path to a .txt transcript of the call")
    source.add_argument("--audio", help="Path to an audio file (mp3/wav/m4a) of the call")
    parser.add_argument("--name", default="", help="Prospect name (optional)")
    parser.add_argument("--email", default="", help="Prospect email (optional)")
    parser.add_argument("--phone", default="", help="Prospect phone (optional)")
    args = parser.parse_args()

    transcript_text = None
    if args.transcript:
        try:
            with open(args.transcript, "r", encoding="utf-8") as f:
                transcript_text = f.read()
        except OSError as e:
            sys.exit(f"Could not read transcript file: {e}")

    call = {
        "transcript": transcript_text,
        "audio_path": args.audio,
        "recording_url": None,
        "caller_name": args.name,
        "caller_email": args.email,
        "caller_phone": args.phone,
    }

    result = process_call(call)

    print("\n=== Lead ===")
    print(f"Name:    {result.get('contact_name')}  ({result.get('company')})")
    hot = "   *** HOT ***" if result.get("is_hot") else ""
    print(f"Score:   {result.get('score')}/100  ->  {result.get('rating')}{hot}")
    print(f"Summary: {result.get('summary')}")
    if result.get("next_steps"):
        print("Next:    " + " | ".join(result["next_steps"]))


if __name__ == "__main__":
    main()
