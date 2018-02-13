//
//  ViewController.swift
//  BareMetalCalibrationTest
//
//  Created by Gregg Jaskiewicz on 13/02/2018.
//  Copyright © 2018 Gregg Jaskiewicz. All rights reserved.
//

import UIKit
import AVFoundation


class Synthesizer {

    // The maximum number of audio buffers in flight. Setting to two allows one
    // buffer to be played while the next is being written.
    private var kInFlightAudioBuffers: Int = 2

    // The number of audio samples per buffer. A lower value reduces latency for
    // changes but requires more processing but increases the risk of being unable
    // to fill the buffers in time. A setting of 1024 represents about 23ms of
    // samples.
    private let kSamplesPerBuffer: AVAudioFrameCount = 1024

    // The audio engine manages the sound system.
    private let audioEngine: AVAudioEngine

    // The player node schedules the playback of the audio buffers.
    private let playerNode: AVAudioPlayerNode

    // Use standard non-interleaved PCM audio.
    private let audioFormat: AVAudioFormat?

    // A circular queue of audio buffers.
    private var audioBuffers: [AVAudioPCMBuffer] = []

    // The index of the next buffer to fill.
    private var bufferIndex: Int = 0

    // The dispatch queue to render audio samples.
    private let audioQueue: DispatchQueue

    // A semaphore to gate the number of buffers processed.
    private let audioSemaphore: DispatchSemaphore

    public func stop() {
        NotificationCenter.default.removeObserver(self)
        self.audioEngine.stop()
    }

    deinit {
        self.stop()
        NotificationCenter.default.removeObserver(self)
//        print("FM Synch is gone")
    }

    public init() {
        // init the semaphore
        self.audioSemaphore = DispatchSemaphore(value: kInFlightAudioBuffers)
        self.audioEngine = AVAudioEngine()

        // The player node schedules the playback of the audio buffers.
        self.playerNode = AVAudioPlayerNode()

        // Use standard non-interleaved PCM audio.
        self.audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
        self.audioQueue = DispatchQueue(label: "FMSynthesizerQueue", attributes: [])

        // Create a pool of audio buffers.
        if let audioFormat = self.audioFormat, let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: UInt32(kSamplesPerBuffer)) {
            self.audioBuffers = [AVAudioPCMBuffer](repeating: buffer, count: 1)
            // Attach and connect the player node.
            self.audioEngine.attach(playerNode)
            self.audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        }

        do {
            try self.audioEngine.start()
        } catch {
            print("AudioEngine didn't start")
        }
    }

    func play(_ carrierFrequency: Float32, modulatorFrequency: Float32, modulatorAmplitude: Float32) {
        let unitVelocity = Float32(2.0 * Double.pi / (audioFormat?.sampleRate)!)
        let carrierVelocity = carrierFrequency * unitVelocity
        let modulatorVelocity = modulatorFrequency * unitVelocity

        NotificationCenter.default.addObserver(self, selector: #selector(Synthesizer.audioEngineConfigurationChange(_:)),
                                               name: NSNotification.Name.AVAudioEngineConfigurationChange, object: audioEngine)

        self.playerNode.play()

        self.audioQueue.async { [weak self] in
            var sampleTime: Float32 = 0
            guard let semaphore = self?.audioSemaphore else {
                return
            }

            while (self?.playerNode.isPlaying) ?? false {
                guard let strongSelf = self else {
                    break
                }
                // Wait for a buffer to become available.
                _ = semaphore.wait(timeout: DispatchTime.distantFuture)
//                _ = semaphore.wait(wallTimeout: DispatchWallTime.now() + .seconds(1) )

                // Fill the buffer with new samples.
                let audioBuffer = strongSelf.audioBuffers[strongSelf.bufferIndex]
                let leftChannel = audioBuffer.floatChannelData?[0]
                let rightChannel = audioBuffer.floatChannelData?[1]
                for sampleIndex in 0 ..< Int(strongSelf.kSamplesPerBuffer) {
                    let sample = sin(carrierVelocity * sampleTime + modulatorAmplitude * sin(modulatorVelocity * sampleTime))
                    leftChannel?[sampleIndex] = sample
                    rightChannel?[sampleIndex] = sample
                    sampleTime = sampleTime + 1.0
                }
                audioBuffer.frameLength = strongSelf.kSamplesPerBuffer

                // Schedule the buffer for playback and release it for reuse after
                // playback has finished.
                self?.playerNode.scheduleBuffer(audioBuffer) {
                    semaphore.signal()
                }

                strongSelf.bufferIndex = (strongSelf.bufferIndex + 1) % strongSelf.audioBuffers.count
            }
//            print("play loop left")
            semaphore.signal()
        }

        self.playerNode.pan = ((Float32(arc4random_uniform(1024))-512.0)/512.0)
//        self.playerNode.pan = -1.0
    }

    @objc  func audioEngineConfigurationChange(_ notification: Notification) -> Void {
        NSLog("Audio engine configuration change: \(notification)")
    }

}

class ViewController: UIViewController {

    private var synth: [Synthesizer] = []

    @IBAction func buttonPressed() {

        DispatchQueue.global().async {

            for _ in 1...15 {
                let synth = Synthesizer()
                synth.play( Float32(arc4random_uniform(1024)), modulatorFrequency: 679.0, modulatorAmplitude: 0.8)
                usleep(200000)
                self.synth.append(synth)
            }
            sleep(1)

            self.synth.forEach({ (synth) in
                synth.stop()
            })

            self.synth = []
        }
    }

}

