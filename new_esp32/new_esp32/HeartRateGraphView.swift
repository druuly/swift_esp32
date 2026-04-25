import SwiftUI
import Charts

struct HeartRateGraphView: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(spacing: 16) {
            if bleManager.bpmHistory.isEmpty {
                emptyState
            } else {
                currentBPM
                graph
                stats
            }
        }
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No Heart Rate Data")
                .font(.headline)
            Text("Connect to ESP32 and place finger on sensor to start recording")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var currentBPM: some View {
        VStack(spacing: 4) {
            Text("\(bleManager.bpm)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.red)
            Text("BPM")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var graph: some View {
        Chart {
            ForEach(Array(bleManager.bpmHistory.enumerated()), id: \.offset) { index, entry in
                LineMark(
                    x: .value("Time", entry.0),
                    y: .value("BPM", entry.1)
                )
                .foregroundStyle(.red.gradient)
                .interpolationMethod(.catmullRom)
            }
            
            if let avg = bleManager.bpmHistory.map({ $0.1 }).reduce(0, +) as Int?,
               !bleManager.bpmHistory.isEmpty {
                let average = Double(avg) / Double(bleManager.bpmHistory.count)
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
        .chartYScale(domain: 40...200)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.second())
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 20)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)")
                    }
                }
            }
        }
        .frame(height: 600)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var stats: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Min")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(bleManager.bpmHistory.map { $0.1 }.min() ?? 0)")
                    .font(.title3.monospacedDigit())
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 4) {
                Text("Avg")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(bleManager.avgBpm)")
                    .font(.title3.monospacedDigit())
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 4) {
                Text("Max")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(bleManager.bpmHistory.map { $0.1 }.max() ?? 0)")
                    .font(.title3.monospacedDigit())
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 4) {
                Text("Samples")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(bleManager.bpmHistory.count)")
                    .font(.title3.monospacedDigit())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    HeartRateGraphView(bleManager: BLEManager())
}
