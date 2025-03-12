#!/bin/bash
# fs-monitor.sh - Dashboard for monitoring application file access on macOS
# Usage: sudo ./fs-monitor.sh [project_path] [app_name]

# Configuration
APP_NAME="${2:-Cursor}"       # Default to Cursor, override with second parameter
PROJECT_PATH="${1:-$HOME}"    # Default to home, override with first parameter
REFRESH_INTERVAL=2            # Seconds between refreshes
SHOW_SUMMARY=true             # Default to summary view (vs raw logs)
LOG_DIR="$PROJECT_PATH/.fs-monitor-logs"

# Paths to monitor specifically (these will be highlighted in the summary)
MONITORED_PATHS=(
  "$PROJECT_PATH"
  "$HOME/Library/Application Support/$APP_NAME"
  "/Applications/$APP_NAME.app"
  "/System"
  "/usr/lib"
  "/tmp"
)

# Check for sudo access
if [ "$EUID" -ne 0 ]; then
  echo "This script requires sudo permissions."
  echo "Please run: sudo $0 $PROJECT_PATH $APP_NAME"
  exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"

# Set up log files
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FS_USAGE_LOG="$LOG_DIR/fs-usage-$TIMESTAMP.log"
OPENSNOOP_LOG="$LOG_DIR/opensnoop-$TIMESTAMP.log"
SANDBOX_LOG="$LOG_DIR/sandbox-$TIMESTAMP.log"
CRASH_LOG="$LOG_DIR/crash-$TIMESTAMP.log"

# Initialize log files
> "$FS_USAGE_LOG"
> "$OPENSNOOP_LOG"
> "$SANDBOX_LOG"
> "$CRASH_LOG"
> "${FS_USAGE_LOG}.summary"
> "${OPENSNOOP_LOG}.summary"

# Function to clean up on exit
function cleanup {
  # Kill background processes
  kill $PID_FS_USAGE $PID_OPENSNOOP $PID_SANDBOX $PID_CRASH $PID_SUMMARY 2>/dev/null
  # Remove temporary files
  rm -f "${FS_USAGE_LOG}.summary" "${OPENSNOOP_LOG}.summary" 2>/dev/null
  # Restore terminal
  tput rmcup
  tput cnorm  # Restore cursor
  echo "Monitor stopped. Logs saved to $LOG_DIR"
  exit 0
}

# Trap signals for clean exit
trap cleanup EXIT INT TERM

# Function to add timestamp-based color fading
function color_by_age() {
  local line="$1"
  local current_time=$(date +%s)
  
  # Extract timestamp from line format [HH:MM:SS]
  if [[ $line =~ \[([0-9]{2}):([0-9]{2}):([0-9]{2})\] ]]; then
    local h=${BASH_REMATCH[1]}
    local m=${BASH_REMATCH[2]}
    local s=${BASH_REMATCH[3]}
    
    # Calculate seconds since timestamp (simplified)
    local now_h=$(date +%H)
    local now_m=$(date +%M)
    local now_s=$(date +%S)
    
    # Handle midnight crossing
    if (( 10#$now_h < 10#$h )); then
      now_h=$((now_h + 24))
    fi
    
    local timestamp_seconds=$((10#$h * 3600 + 10#$m * 60 + 10#$s))
    local now_seconds=$((10#$now_h * 3600 + 10#$now_m * 60 + 10#$now_s))
    local age=$((now_seconds - timestamp_seconds))
    
    # Color based on age - newer entries are brighter
    if (( age < 5 )); then
      echo -e "\033[1;97m$line\033[0m"  # Bright white for very recent
    elif (( age < 30 )); then
      echo -e "\033[0;97m$line\033[0m"   # White for recent
    elif (( age < 60 )); then
      echo -e "\033[0;37m$line\033[0m"   # Light gray
    else
      echo -e "\033[0;90m$line\033[0m"   # Dark gray for older
    fi
  else
    # No timestamp, just output the line
    echo "$line"
  fi
}

# Function to process logs and generate summaries
function generate_summary {
  local log_file="$1"
  local summary_file="$2"
  
  # Clear summary file
  > "$summary_file"
  
  # Create access count by path prefix
  echo "# PATH ACCESS COUNTS (LAST 5 MINUTES)" > "$summary_file"
  
  # Get top accessed paths
  grep -a -o "/[^ ]*" "$log_file" | sort | uniq -c | sort -nr | head -10 >> "$summary_file"
  
  # Add counts for specific monitored paths
  echo "" >> "$summary_file"
  echo "# MONITORED PATHS ACCESS" >> "$summary_file"
  
  for path in "${MONITORED_PATHS[@]}"; do
    # Count accesses to this path
    local count=$(grep -a "$path" "$log_file" | grep -a -v "No such file" | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      echo "$count : $path" >> "$summary_file"
    fi
  done
  
  # Add recent denied operations
  echo "" >> "$summary_file"
  echo "# RECENT DENIED OPERATIONS" >> "$summary_file"
  grep -a "Operation not permitted\|Permission denied\|denied\|Sandbox blocked" "$log_file" | \
    tail -5 >> "$summary_file"
}

# Function to trim long paths for display
function trim_path {
  local path="$1"
  local max_length="$2"
  
  if [ ${#path} -gt $max_length ]; then
    # Keep the first part and last part, insert ... in the middle
    local first_part=$(echo "$path" | cut -c 1-$(($max_length/2-3)))
    local last_part=$(echo "$path" | rev | cut -c 1-$(($max_length/2-3)) | rev)
    echo "${first_part}...${last_part}"
  else
    echo "$path"
  fi
}

# Clear screen and switch to alternate screen
tput smcup
clear

echo "FS Monitor v5"
echo "------------"
echo "Starting monitors... This may take a few seconds."
echo "Monitoring application: $APP_NAME"
echo "Logs will be saved to: $LOG_DIR"
echo

# Start fs_usage monitor in background
{
  # Run fs_usage and filter for the app
  fs_usage -f filesystem | grep -i "$APP_NAME" | while read -r line; do
    timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] $line" >> "$FS_USAGE_LOG"
  done
} &
PID_FS_USAGE=$!

# Start opensnoop monitor in background
{
  # Run opensnoop and filter for the app
  opensnoop -n "$APP_NAME" | while read -r line; do
    timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] $line" >> "$OPENSNOOP_LOG"
  done
} &
PID_OPENSNOOP=$!

# Start sandbox violation monitor in background
{
  # Monitor sandbox violations
  while true; do
    log show --style compact --predicate 'subsystem == "com.apple.sandbox" AND (process CONTAINS "'$APP_NAME'" OR eventMessage CONTAINS "'$APP_NAME'")' --last 10s 2>/dev/null | while read -r line; do
      timestamp=$(date '+%H:%M:%S')
      echo "[$timestamp] $line" >> "$SANDBOX_LOG"
    done
    sleep 5
  done
} &
PID_SANDBOX=$!

# Start crash/abort monitor in background
{
  # Monitor for crashes and aborts
  while true; do
    # Check for new crash reports
    find "$HOME/Library/Logs/DiagnosticReports" -name "*$APP_NAME*" -type f -ctime -1 -exec ls -lt {} \; 2>/dev/null | while read -r line; do
      timestamp=$(date '+%H:%M:%S')
      echo "[$timestamp] $line" >> "$CRASH_LOG"
    done
    
    # Check for abort messages
    log show --style compact --predicate 'eventMessage CONTAINS "Abort trap: 6" AND (process CONTAINS "'$APP_NAME'" OR eventMessage CONTAINS "'$APP_NAME'")' --last 10s 2>/dev/null | while read -r line; do
      timestamp=$(date '+%H:%M:%S')
      echo "[$timestamp] $line" >> "$CRASH_LOG"
    done
    sleep 5
  done
} &
PID_CRASH=$!

# Background process to periodically generate summaries
{
  while true; do
    generate_summary "$FS_USAGE_LOG" "${FS_USAGE_LOG}.summary"
    generate_summary "$OPENSNOOP_LOG" "${OPENSNOOP_LOG}.summary"
    sleep 30  # Update summaries every 30 seconds
  done
} &
PID_SUMMARY=$!

# Calculate start time for uptime display
START_TIME=$(date +%s)

# Main display loop
while true; do
  # Get terminal size
  TERM_ROWS=$(tput lines)
  TERM_COLS=$(tput cols)
  
  # Calculate available panel height
  HEADER_LINES=7
  FOOTER_LINES=2
  PANEL_SPACING=4  # Space between panels (title, separator, blank lines)
  PANELS=4
  
  # Calculate panel height based on terminal size
  PANEL_HEIGHT=$(( (TERM_ROWS - HEADER_LINES - FOOTER_LINES - (PANEL_SPACING * PANELS)) / PANELS ))
  if (( PANEL_HEIGHT < 3 )); then
    PANEL_HEIGHT=3  # Minimum panel height
  fi
  
  # Calculate run time
  CURRENT_TIME=$(date +%s)
  RUN_TIME=$((CURRENT_TIME - START_TIME))
  HOURS=$((RUN_TIME / 3600))
  MINUTES=$(( (RUN_TIME % 3600) / 60 ))
  SECONDS=$((RUN_TIME % 60))
  
  # Clear screen for refresh
  tput clear
  
  # Display header with dynamic width
  printf "=%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  printf "%-20s %-${TERM_COLS}s\n" "$APP_NAME MONITOR" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf "%-20s %-${TERM_COLS}s\n" "PROJECT:" "$(trim_path "$PROJECT_PATH" $((TERM_COLS-21)))"
  printf "%-20s %-${TERM_COLS}s\n" "RUNTIME:" "$(printf "%02d:%02d:%02d" $HOURS $MINUTES $SECONDS)"
  printf "%-20s %-${TERM_COLS}s\n" "VIEW MODE:" "$(if $SHOW_SUMMARY; then echo "Summary"; else echo "Raw Logs"; fi) (Press 't' to toggle)"
  printf "=%.0s" $(seq 1 $TERM_COLS)
  printf "\n\n"
  
  # Display fs_usage panel
  printf "FILE SYSTEM ACCESS\n"
  printf -- "-%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  if ! $SHOW_SUMMARY; then
    # Show raw logs with color fading
    if [ -f "$FS_USAGE_LOG" ]; then
      tail -n $PANEL_HEIGHT "$FS_USAGE_LOG" 2>/dev/null | while read -r line; do
        trimmed_line=$(echo "$line" | cut -c 1-$TERM_COLS)
        color_by_age "$trimmed_line"
      done
    fi
  else
    # Show summary
    if [ -f "${FS_USAGE_LOG}.summary" ]; then
      head -n $PANEL_HEIGHT "${FS_USAGE_LOG}.summary"
    fi
  fi
  printf "\n\n"
  
  # Display opensnoop panel
  printf "FILE OPEN OPERATIONS\n"
  printf -- "-%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  if ! $SHOW_SUMMARY; then
    # Show raw logs with color fading
    if [ -f "$OPENSNOOP_LOG" ]; then
      tail -n $PANEL_HEIGHT "$OPENSNOOP_LOG" 2>/dev/null | while read -r line; do
        trimmed_line=$(echo "$line" | cut -c 1-$TERM_COLS)
        color_by_age "$trimmed_line"
      done
    fi
  else
    # Show summary
    if [ -f "${OPENSNOOP_LOG}.summary" ]; then
      head -n $PANEL_HEIGHT "${OPENSNOOP_LOG}.summary"
    fi
  fi
  printf "\n\n"
  
  # Display sandbox violations panel
  printf "SANDBOX VIOLATIONS\n"
  printf -- "-%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  if [ -f "$SANDBOX_LOG" ]; then
    tail -n $PANEL_HEIGHT "$SANDBOX_LOG" 2>/dev/null | while read -r line; do
      trimmed_line=$(echo "$line" | cut -c 1-$TERM_COLS)
      color_by_age "$trimmed_line"
    done
  else
    echo "No sandbox violations detected"
  fi
  printf "\n\n"
  
  # Display crash panel
  printf "CRASH & ABORT EVENTS\n"
  printf -- "-%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  if [ -f "$CRASH_LOG" ] && [ -s "$CRASH_LOG" ]; then
    tail -n $PANEL_HEIGHT "$CRASH_LOG" 2>/dev/null | while read -r line; do
      trimmed_line=$(echo "$line" | cut -c 1-$TERM_COLS)
      color_by_age "$trimmed_line"
    done
  else
    echo "No crashes detected"
  fi
  printf "\n"
  
  # Display footer with help text
  printf "=%.0s" $(seq 1 $TERM_COLS)
  printf "\n"
  printf "Logs: %s | q: Quit | t: Toggle View | r: Refresh Now\n" "$LOG_DIR"
  
  # Hide cursor for cleaner display
  tput civis
  
  # Sleep before refresh, but allow for responsive controls
  for (( i=0; i<$REFRESH_INTERVAL*10; i++ )); do
    sleep 0.1
    # Check if user pressed a key
    if read -t 0.01 -n 1 key 2>/dev/null; then
      if [[ $key = "q" ]]; then
        cleanup
      elif [[ $key = "t" ]]; then
        SHOW_SUMMARY=$(! $SHOW_SUMMARY)
        break  # Refresh immediately
      elif [[ $key = "r" ]]; then
        break  # Refresh immediately
      fi
    fi
  done
done
