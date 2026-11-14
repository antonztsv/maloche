#!/bin/zsh
# Builds and starts the dev app, records its activation log with step markers to build/activation-log.txt.
set -euo pipefail
cd "${0:A:h}/.."

LOG="build/activation-log.txt"
APP="build/maloche Dev.app"

scripts/build-app.sh >/dev/null
pkill -f "maloche Dev.app/Contents/MacOS/Maloche" || true
sleep 1
: > "$LOG"
log stream --level debug --style compact --predicate 'subsystem == "io.github.antonztsv.maloche.dev"' >> "$LOG" &
STREAM=$!
trap 'kill $STREAM 2>/dev/null; echo "Log: $PWD/$LOG"' EXIT
sleep 1
open "$APP" --args -DebugCheckInInterval 90

step() {
  print -r -- "$1"
  read -r "?Enter, wenn erledigt. "
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') ==== Schritt erledigt: $1" >> "$LOG"
}

step "1. Falls maloche nicht trackt: Symbol klicken, im Dashboard einschalten. Dann auf die Timer-Abfrage warten (bis 90 s) und aufs Symbol klicken."
step "2. In Einstellungen \"Im Dock anzeigen\" aus. Symbol klicken, im Dashboard ⌘, drücken. Dann aufs Symbol klicken, damit das Dashboard aufgeht, und hineinklicken."
step "3. Symbol klicken, im Dashboard \"Aktivitäten verwalten\" öffnen. Dann aufs Symbol klicken und ins Dashboard klicken."
step "4. Einstellungen und Aktivitätenfenster offen lassen. \"Im Dock anzeigen\" einschalten, kurz warten, wieder ausschalten."
