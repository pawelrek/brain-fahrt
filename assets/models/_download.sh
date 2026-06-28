#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
LOG="_download.log"; : > "$LOG"
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

dl(){ # url outfile
  say "START $2"
  if curl -L --fail --retry 6 --retry-delay 3 -C - -# -o "$2" "$1" 2>>"$LOG"; then
    say "DONE  $2 ($(du -h "$2" | cut -f1))"
  else
    say "FAIL  $2 (curl exit $?)"
  fi
}

# parallel downloads
dl "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx" "silero_vad.onnx" &
dl "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2" "kws.tar.bz2" &
dl "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2" "whisper.tar.bz2" &
# Multilingual Whisper small (int8) — bundled STT default; more robust to
# accented / non-native English than small.en. Extracts to sherpa-onnx-whisper-small/.
dl "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2" "whisper-ml.tar.bz2" &
dl "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf" "qwen2.5-1.5b-instruct-q4_k_m.gguf" &
wait

# extract tarballs
for t in kws.tar.bz2 whisper.tar.bz2 whisper-ml.tar.bz2; do
  if [ -s "$t" ]; then
    say "EXTRACT $t"
    if tar xf "$t" 2>>"$LOG"; then rm -f "$t"; say "EXTRACTED+rm $t"; else say "EXTRACT-FAIL $t"; fi
  else
    say "SKIP extract (missing/empty) $t"
  fi
done

say "ALL DONE"
say "---- final tree ----"
{ find . -maxdepth 2 -not -name '_download.*' -not -name '.' | sort; echo; du -sh ./* 2>/dev/null; } | tee -a "$LOG"
