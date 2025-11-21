# Research Findings - Mac Catalyst AVAudioEngine Input Tap

## Key Insights from Research

### 1. Hardware Format Must Match
**Finding**: The format used for connections and taps must match the hardware's native format. Using arbitrary formats (like 44100 Hz, mono) can cause conversion errors.

**Recommendation**: 
- Access input node format AFTER engine is started
- Use `inputNode.inputFormat(forBus: 0)` or `inputNode.outputFormat(forBus: 0)` after starting
- Use this hardware format for all connections and taps

### 2. Tap Installation Timing
**Finding**: Multiple sources suggest installing taps AFTER the engine is started, not before.

**Current Approach**: We install tap before starting
**Recommended**: Install tap after `audioEngine.start()`

### 3. Audio Session Configuration
**Finding**: Audio session must be configured with proper options for Mac Catalyst.

**Current**: Using `.playAndRecord` with `.defaultToSpeaker`
**Consider**: May need `.allowBluetooth` or other options

### 4. Mixer Node May Not Be Necessary
**Finding**: For input-only scenarios (just tapping, not playing), we might not need to connect to the mixer at all.

**Current Approach**: Connecting input → mixer → output
**Alternative**: Just use the tap without any connections (but engine needs at least one connection for prepare())

### 5. Format Query After Start
**Finding**: The hardware format can only be reliably queried after the engine is started.

**Key Pattern from Research**:
```swift
// 1. Configure audio session
// 2. Connect nodes (with placeholder format if needed)
// 3. Prepare engine
// 4. Start engine
// 5. Query hardware format
// 6. Reconnect with hardware format (if needed)
// 7. Install tap with hardware format
```

## Potential Solutions to Try

### Solution A: Query Format After Start, Reconnect
1. Connect with placeholder format
2. Start engine
3. Query actual hardware format
4. Disconnect and reconnect with hardware format
5. Install tap with hardware format

### Solution B: Use Format Converter Node
Instead of direct connection, use `AVAudioConverter` to handle format differences between input and mixer.

### Solution C: Different Topology
- Don't connect input to mixer
- Connect a dummy node or use a different topology
- Just use the tap (but this might not work if engine requires connections)

### Solution D: Use AVAudioInputNode Directly
Research if there's a way to use `AVAudioInputNode` without going through the mixer.

## Critical Code Pattern from Research

```swift
// 1. Audio session
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
try session.setActive(true)

// 2. Get input node early
let inputNode = audioEngine.inputNode

// 3. Connect with format (may need placeholder)
let format = inputNode.outputFormat(forBus: 0) // After start!
audioEngine.connect(inputNode, to: mixer, format: format)

// 4. Prepare and start
audioEngine.prepare()
try audioEngine.start()

// 5. Install tap AFTER start
inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
    // Process
}
```

## Questions to Investigate

1. Can we avoid the mixer entirely for input-only scenarios?
2. Is there a way to initialize mixer input bus format explicitly?
3. Should we use `AVAudioConverter` for format conversion?
4. Are there Mac Catalyst-specific audio session requirements?
5. Can we use a different node topology that doesn't require the mixer?

## Next Steps

1. Try querying hardware format AFTER engine start
2. Try installing tap AFTER engine start
3. Try reconnecting with hardware format after start
4. Research if mixer is actually required for taps
5. Look for Apple sample code or WWDC sessions on Mac Catalyst audio

