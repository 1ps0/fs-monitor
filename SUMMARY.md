# Cursor Monitor: Development & Extension Guide

## Overview

Cursor Monitor is a terminal-based dashboard tool for macOS that provides real-time visibility into how the Cursor code editor (or other applications) interacts with the file system. The tool helps developers understand and control file access patterns, detect sandbox violations, and monitor for crashes.

## Evolution & Design Criteria

The tool evolved through several iterations, focusing on these key criteria:

1. **Visibility**: Provide real-time insight into file system interactions
2. **Sandboxing**: Monitor for access beyond permitted boundaries
3. **Consolidation**: Combine multiple monitoring approaches into a single view
4. **Summarization**: Aggregate raw data into meaningful metrics
5. **Usability**: Create a clean, responsive interface with meaningful visualizations

## Key Components

The current implementation combines four core monitoring approaches:

1. **File System Calls** (via `fs_usage`): Low-level file system operations
2. **File Open Tracking** (via `opensnoop`): File open events
3. **Sandbox Violation Detection**: Via macOS unified logging system
4. **Crash/Abort Monitoring**: Application crash and abort trap events

## Latest Changes

The most recent improvements focus on noise reduction and meaningful data presentation:

1. **Toggle View Modes**:
   - Summary view (default): Shows consolidated metrics and important patterns
   - Raw logs view: Shows detailed event stream with timestamps

2. **Path-Based Metrics**:
   - Configurable paths of interest
   - Count and categorize access by path
   - Highlight unusual access patterns outside monitored paths

3. **Visual Clarity**:
   - Color-coded aging system where entries fade over time
   - Path trimming for long filenames
   - Categorized violations with distinctive coloring
   - Dynamic panel sizing based on terminal dimensions

4. **Improved Log Management**:
   - Project-specific log directory (.fs-monitor-logs)
   - Session-based log files with timestamps
   - Separation of raw logs and summary statistics

## Extending the Script

### Generalization by Target Application

To make the script more general-purpose for monitoring different applications:

1. **Target App Configuration**:
   ```bash
   # Add to configuration section
   TARGET_APP="${2:-Cursor}"  # Default to Cursor, allow override via second parameter
   ```

2. **Application Profile Templates**:
   ```bash
   # Add application profiles with common paths
   declare -A APP_PROFILES
   APP_PROFILES[Cursor]="/Applications/Cursor.app,$HOME/Library/Application Support/Cursor"
   APP_PROFILES[VSCode]="/Applications/Visual Studio Code.app,$HOME/Library/Application Support/Code"
   ```

3. **Process Detection**:
   - Add functionality to auto-detect processes with similar names
   - Create a process group monitoring approach for multi-process applications

### Improved Visualization

1. **File Operation Categories**:
   - Categorize operations (read, write, create, delete) with distinct visual indicators
   - Add operation-type summary statistics

2. **Access Heat Maps**:
   - Create visual heat maps of directory trees with access frequency
   - Implement simplified ASCII-based visualization for terminal

   ```
   /project
   ├── src/ [████████] 73%
   │   ├── components/ [██████] 54% 
   │   └── utils/ [█] 12%
   └── node_modules/ [█] 8%
   ```

3. **Virtual Boundary Visualization**:
   ```
   # Example boundary visualization
   INSIDE SANDBOX → node_modules/lodash (473 accesses)
   INSIDE SANDBOX → src/components (142 accesses)
   ----------- BOUNDARY -----------
   VIOLATION → /Users/home/.ssh (3 attempts)
   VIOLATION → /etc/hosts (1 attempt)
   ```

4. **Real-Time Differential Analysis**:
   - Compare current session with previous sessions
   - Highlight new access patterns or changes in frequency

5. **Time-Series Data**:
   - Implement simple ASCII charts for access frequency over time
   - Track access patterns across monitoring sessions

### Additional Monitoring Dimensions

1. **Network Access Monitoring**:
   - Add monitoring for outbound connections using `nettop`
   - Correlate network activity with file access

2. **Process Relationship Mapping**:
   - Track child processes and their file access patterns
   - Create a process tree visualization with file access attribution

3. **Memory Usage Correlation**:
   - Monitor memory usage spikes in relation to file operations
   - Identify potential memory leaks related to file handling

4. **Performance Impact Measurement**:
   - Add metrics for application performance during file operations
   - Identify performance bottlenecks related to file access patterns

## Implementation Next Steps

1. **Configuration File Support**:
   - Move settings to an external configuration file
   - Allow for customizable profiles without script modification

2. **Enhanced Filtering**:
   - Add support for inclusion/exclusion patterns
   - Create saved filter profiles for different monitoring scenarios

3. **Persistent Database**:
   - Implement a simple SQLite database for historical analysis
   - Allow querying of patterns across multiple sessions

4. **Integration Options**:
   - Add export capabilities for integration with other tools
   - Create hooks for triggering actions on specific events (e.g., alerts)

5. **Visual Reporting**:
   - Generate HTML/PDF reports with visualizations
   - Create executive summaries of file access behaviors

By implementing these extensions, the Cursor Monitor tool can evolve from a specific monitoring solution into a comprehensive file system behavior analysis platform suitable for development, security auditing, and performance optimization.
