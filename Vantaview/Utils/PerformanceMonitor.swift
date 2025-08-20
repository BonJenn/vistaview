//
//  PerformanceMonitor.swift
//  Vistaview
//
//  Created by AI Assistant for Performance Optimization
//

import Foundation
import AppKit
import OSLog
import SwiftUI

/// Performance monitoring utility to track CPU usage, memory usage, and frame rates
@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var frameRate: Double = 0.0
    @Published var energyImpact: EnergyImpact = .low
    
    private var timer: Timer?
    private var lastUpdateTime: CFTimeInterval = 0
    private var frameCount = 0
    private let logger = Logger(subsystem: "com.vistaview.performance", category: "monitor")
    
    // PERFORMANCE: Reduce timer frequency from 2 seconds to 5 seconds to save CPU
    private let updateInterval: TimeInterval = 5.0
    
    // PERFORMANCE: Add CPU measurement tracking
    private var lastCPUTime: Double = 0
    private var lastSystemTime: Double = 0
    
    enum EnergyImpact: String, CaseIterable {
        case low = "Low"
        case medium = "Medium" 
        case high = "High"
        case veryHigh = "Very High"
        
        var color: NSColor {
            switch self {
            case .low: return .systemGreen
            case .medium: return .systemYellow
            case .high: return .systemOrange
            case .veryHigh: return .systemRed
            }
        }
    }
    
    init() {
        startMonitoring()
    }
    
    deinit {
        // Timer cleanup will happen automatically when the object is deallocated
        // We can't call MainActor methods from deinit, so just let ARC handle cleanup
    }
    
    func startMonitoring() {
        guard timer == nil else { return }
        
        lastUpdateTime = CACurrentMediaTime()
        
        // PERFORMANCE: Increased timer interval from 2.0 to 5.0 seconds
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        
        logger.info("Performance monitoring started with \(self.updateInterval, privacy: .public)s interval")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        logger.info("Performance monitoring stopped")
    }
    
    private func updateMetrics() {
        updateCPUUsage()
        updateMemoryUsage()
        updateFrameRate()
        updateEnergyImpact()
        
        // PERFORMANCE: Reduced logging frequency - every 2 minutes instead of 1 minute
        if frameCount % 24 == 0 { // Every 2 minutes at 5 second intervals
            logger.info("Performance: CPU: \(self.cpuUsage, privacy: .public)%, Memory: \(self.memoryUsage, privacy: .public)MB, FPS: \(self.frameRate, privacy: .public), Energy: \(self.energyImpact.rawValue, privacy: .public)")
        }
        
        frameCount += 1
    }
    
    // PERFORMANCE: More accurate CPU usage measurement
    private func updateCPUUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            // PERFORMANCE: Improved CPU usage calculation using task_info
            var task_info_data = task_thread_times_info()
            var task_info_count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size / MemoryLayout<natural_t>.size)
            
            let task_kerr = withUnsafeMutablePointer(to: &task_info_data) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &task_info_count)
                }
            }
            
            if task_kerr == KERN_SUCCESS {
                let currentTime = CFAbsoluteTimeGetCurrent()
                let totalTime = Double(task_info_data.user_time.seconds + task_info_data.system_time.seconds) +
                               Double(task_info_data.user_time.microseconds + task_info_data.system_time.microseconds) / 1_000_000.0
                
                if lastCPUTime > 0 && lastSystemTime > 0 {
                    let cpuDelta = totalTime - lastCPUTime
                    let timeDelta = currentTime - lastSystemTime
                    
                    if timeDelta > 0 {
                        cpuUsage = min(100.0, max(0.0, (cpuDelta / timeDelta) * 100.0))
                    }
                }
                
                lastCPUTime = totalTime
                lastSystemTime = currentTime
            } else {
                // Fallback to simple estimation
                cpuUsage = min(100.0, Double(info.resident_size) / (1024 * 1024 * 10)) // Rough estimation
            }
        }
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            memoryUsage = Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }
    }
    
    private func updateFrameRate() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastUpdateTime
        
        if deltaTime > 0 {
            // PERFORMANCE: Calculate average frame rate over the monitoring interval
            frameRate = Double(frameCount) / deltaTime
        }
        
        lastUpdateTime = currentTime
    }
    
    private func updateEnergyImpact() {
        // PERFORMANCE: More accurate energy impact calculation
        let cpuFactor = cpuUsage / 100.0
        let memoryFactor = min(memoryUsage / 1000.0, 1.0) // Normalize to 1GB
        let frameRateFactor = min(frameRate / 60.0, 1.0)
        
        // Weighted combination: CPU has highest impact, then memory, then frame rate
        let combinedFactor = (cpuFactor * 0.6) + (memoryFactor * 0.25) + (frameRateFactor * 0.15)
        
        switch combinedFactor {
        case 0.0..<0.2:
            energyImpact = .low
        case 0.2..<0.4:
            energyImpact = .medium
        case 0.4..<0.7:
            energyImpact = .high
        default:
            energyImpact = .veryHigh
        }
    }
    
    /// Get a performance summary for logging
    func getPerformanceSummary() -> String {
        return """
        Performance Summary:
        - CPU Usage: \(String(format: "%.1f", cpuUsage))%
        - Memory Usage: \(String(format: "%.1f", memoryUsage)) MB
        - Frame Rate: \(String(format: "%.1f", frameRate)) FPS
        - Energy Impact: \(energyImpact.rawValue)
        """
    }
    
    /// Reset performance counters
    func resetCounters() {
        frameCount = 0
        lastUpdateTime = CACurrentMediaTime()
        lastCPUTime = 0
        lastSystemTime = 0
        logger.info("Performance counters reset")
    }
}

/// Performance overlay view to show real-time metrics
struct PerformanceOverlay: View {
    @StateObject private var monitor = PerformanceMonitor()
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(monitor.energyImpact.color).gradient)
                        .frame(width: 8, height: 8)
                    
                    Text("Performance")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    metricRow("CPU", String(format: "%.1f%%", monitor.cpuUsage), monitor.cpuUsage > 50 ? .orange : .primary)
                    metricRow("Memory", String(format: "%.0f MB", monitor.memoryUsage), monitor.memoryUsage > 500 ? .orange : .primary)
                    metricRow("FPS", String(format: "%.0f", monitor.frameRate), monitor.frameRate < 30 ? .orange : .primary)
                    metricRow("Energy", monitor.energyImpact.rawValue, Color(monitor.energyImpact.color))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
        }
        .padding(8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    private func metricRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            Text(value)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundColor(color)
        }
    }
}