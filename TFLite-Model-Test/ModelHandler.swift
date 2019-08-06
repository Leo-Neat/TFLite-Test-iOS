//
//  ModelHandler.swift
//  TFLite-Model-Test
//
//  Created by Leo Neat on 7/30/19.
//  Copyright © 2019 Leo Neat. All rights reserved.
//

import Foundation
import CoreImage
import TensorFlowLite
import UIKit
import Accelerate

// Error for when user trys to operate on an empty list
enum LabelFileNotFound: Error {
    case runtimeError(String)
}

// Error for when user trys to operate on an empty list
enum ModelFileNotFound: Error {
    case runtimeError(String)
}

class ModelHandler{
    
    /// Information about a model file or labels file.
    typealias FileInfo = (name: String, extension: String)
    
    var modelDim: Int           // The dimention of the image passed in
    var minConf: Double         // The minimum accepted confidence of the model
    
    /// The current thread count used by the TensorFlow Lite Interpreter.
    let threadCount: Int
    
    let resultCount = 3
    let threadCountLimit = 10
    
    let batchSize = 1
    let inputChannels = 3
    
    fileprivate var isProcessing  = false
    fileprivate let lock = NSLock()
    
    /// List of labels from the given labels file.
    private var labels: [String] = []
    
    /// A result from invoking the `Interpreter`.
    struct Result {
        let inferenceTime: Double
        let inferences: [Inference]
    }
    
    /// Stores one formatted inference.
    struct Inference {
        let confidence: Float
        let className: String
        let rect: CGRect
        let displayColor: UIColor
    }
    
    private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
    private let rgbPixelChannels = 3
    private let colorStrideValue = 10
    private let colors = [
        UIColor.red,
        UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
        UIColor.green,
        UIColor.orange,
        UIColor.blue,
        UIColor.purple,
        UIColor.magenta,
        UIColor.yellow,
        UIColor.cyan,
        UIColor.brown
    ]
    
    /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
    private var interpreter: Interpreter
    
    /// Information about the alpha component in RGBA data.
    private let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
    
    
    // Create a tflite model with the passed in parameters
    init?(modelName: String, modelDim: Int, labelsPath: String, modelPath: String, minConf: Double) throws {
        
        
        
        print("Trying to load model with name: ", modelName)
        print("Path: ", modelPath)
        print("Labels: ", labelsPath)
        self.modelDim = modelDim
        self.minConf = minConf
        threadCount = 4
        
        let (existsModel, modelIOSPath) = ModelHandler.fileExistsCheck(filePath: modelPath)
        if !(existsModel){
            throw ModelFileNotFound.runtimeError("Model file does not exist")
        }
        
        let (existsLabels, _) = ModelHandler.fileExistsCheck(filePath: labelsPath)
        if !(existsLabels){
            throw LabelFileNotFound.runtimeError("Label file does not exist")
        }

        
        // Specify the options for the `Interpreter`.
        var options = InterpreterOptions()
        options.threadCount = threadCount
        do {
            // Create the `Interpreter`.
            interpreter = try Interpreter(modelPath: modelIOSPath, options: options)
            // Allocate memory for the model's input `Tensor`s.
            try interpreter.allocateTensors()
        } catch let error {
            print("Failed to create the interpreter with error: \(error.localizedDescription)")
            return nil
        }
        
        // Load the classes listed in the labels file.
        let labelsFI: FileInfo = (name: labelsPath.fileName(), extension: labelsPath.fileExtension())
        loadLabels(fileInfo: labelsFI)
        
        print("Successfully loaded model with name: ", modelName)
    }

    
    private func setIsProcessing(toSet: Bool){
        lock.lock()
        isProcessing = toSet
        lock.unlock()
    }
    
    func  getIsProcessing() -> Bool {
        lock.lock()
        let res = isProcessing
        lock.unlock()
        return res
    }
    
    /// Loads the labels from the labels file and stores them in the `labels` property.
    private func loadLabels(fileInfo: FileInfo) {
        let filename = fileInfo.name
        let fileExtension = fileInfo.extension
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            fatalError("Labels file not found in bundle. Please add a labels file with name " +
                "\(filename).\(fileExtension) and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            labels = contents.components(separatedBy: .newlines)
        } catch {
            fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a " +
                "valid labels file and try again.")
        }
    }

    // Checks if a file can be accessed by the iOS device
    static func fileExistsCheck(filePath: String) -> (Bool, String) {
        let name = filePath.fileName()
        let ext = filePath.fileExtension()
        let stringPath = Bundle.main.path(forResource: name, ofType: ext)!
        let url = URL(string: stringPath)
        if FileManager.default.fileExists(atPath: url!.path) {
           return (true, stringPath)
        } else {
            return (false, stringPath)
        }
    }
    
    /// This class handles all data preprocessing and makes calls to run inference on a given frame
    /// through the `Interpeter`. It then formats the inferences obtained and returns the top N
    /// results for a successful inference.
    func runModel(onFrame pixelBuffer: CVPixelBuffer) -> Result? {
        setIsProcessing(toSet: true)
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
            sourcePixelFormat == kCVPixelFormatType_32BGRA ||
            sourcePixelFormat == kCVPixelFormatType_32RGBA)
        
        
        let imageChannels = 4
        assert(imageChannels >= inputChannels)
        
        // Crops the image to the biggest square in the center and scales it down to model dimensions.
        let scaledSize = CGSize(width: modelDim, height: modelDim)
        guard let scaledPixelBuffer = pixelBuffer.resized(to: scaledSize) else {
            return nil
        }
        
        let interval: TimeInterval
        let outputBoundingBox: Tensor
        let outputClasses: Tensor
        let outputScores: Tensor
        let outputCount: Tensor
        do {
            let inputTensor = try interpreter.input(at: 0)
            
            // Remove the alpha component from the image buffer to get the RGB data.
            guard let rgbData = rgbDataFromBuffer(
                scaledPixelBuffer,
                byteCount: batchSize * modelDim * modelDim * inputChannels,
                isModelQuantized: inputTensor.dataType == .uInt8
                ) else {
                    print("Failed to convert the image buffer to RGB data.")
                    return nil
            }
            
            // Copy the RGB data to the input `Tensor`.
            try interpreter.copy(rgbData, toInputAt: 0)
            
            // Run inference by invoking the `Interpreter`.
            let startDate = Date()
            try interpreter.invoke()
            interval = Date().timeIntervalSince(startDate) * 1000
            
            outputBoundingBox = try interpreter.output(at: 0)
            outputClasses = try interpreter.output(at: 1)
            outputScores = try interpreter.output(at: 2)
            outputCount = try interpreter.output(at: 3)
        } catch let error {
            print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
            setIsProcessing(toSet: false)
            return nil
        }
        
        if(Int(([Float](unsafeData: outputCount.data) ?? [0])[0]) != 0)
        {
            // Formats the results
            let resultArray = formatResults(
                boundingBox: [Float](unsafeData: outputBoundingBox.data) ?? [],
                outputClasses: [Float](unsafeData: outputClasses.data) ?? [],
                outputScores: [Float](unsafeData: outputScores.data) ?? [],
                outputCount: Int(([Float](unsafeData: outputCount.data) ?? [0])[0]),
                width: CGFloat(imageWidth),
                height: CGFloat(imageHeight)
            )
            
            // Returns the inference time and inferences
            let result = Result(inferenceTime: interval, inferences: resultArray)
            setIsProcessing(toSet: false)
            return result
        }
        else
        {
            setIsProcessing(toSet: false)
            // No prediction was made
                return nil
        }
    }
    
    /// Filters out all the results with confidence score < threshold and returns the top N results
    /// sorted in descending order.
    func formatResults(boundingBox: [Float], outputClasses: [Float], outputScores: [Float], outputCount: Int, width: CGFloat, height: CGFloat) -> [Inference]{
        var resultsArray: [Inference] = []
        for i in 0...outputCount - 1 {
            
            let score = outputScores[i]
            
            // Filters results with confidence < threshold.
            guard score >= Float(self.minConf) else {
                continue
            }
            
            // Gets the output class names for detected classes from labels list.
            let outputClassIndex = Int(outputClasses[i])
            let outputClass = labels[outputClassIndex + 1]
            
            var rect: CGRect = CGRect.zero
            
            // Translates the detected bounding box to CGRect.
            rect.origin.y = CGFloat(boundingBox[4*i+2])
            rect.origin.x = CGFloat(boundingBox[4*i+1])
            rect.size.height = abs(CGFloat(boundingBox[4*i]) - CGFloat(boundingBox[4*i+2]))
            rect.size.width = abs(CGFloat(boundingBox[4*i+3]) - CGFloat(boundingBox[4*i+1]))

            
            // The detected corners are for model dimensions. So we scale the rect with respect to the
            // actual image dimensions.            
            // Gets the color assigned for the class
            let colorToAssign = UIColor.green
            let inference = Inference(confidence: score,
                                      className: outputClass,
                                      rect: rect,
                                      displayColor: colorToAssign)
            resultsArray.append(inference)
        }
        
        // Sort results in descending order of confidence.
        resultsArray.sort { (first, second) -> Bool in
            return first.confidence  > second.confidence
        }
        
        return resultsArray
    }
    
    
    /// Returns the RGB data representation of the given image buffer with the specified `byteCount`.
    ///
    /// - Parameters
    ///   - buffer: The BGRA pixel buffer to convert to RGB data.
    ///   - byteCount: The expected byte count for the RGB data calculated using the values that the
    ///       model was trained on: `batchSize * imageWidth * imageHeight * componentsCount`.
    ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than
    ///       floating point values).
    /// - Returns: The RGB data representation of the image buffer or `nil` if the buffer could not be
    ///     converted.
    private func rgbDataFromBuffer(
        _ buffer: CVPixelBuffer,
        byteCount: Int,
        isModelQuantized: Bool
        ) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let mutableRawPointer = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        assert(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)
        let count = CVPixelBufferGetDataSize(buffer)
        let bufferData = Data(bytesNoCopy: mutableRawPointer, count: count, deallocator: .none)
        var rgbBytes = [UInt8](repeating: 0, count: byteCount)
        var pixelIndex = 0
        for component in bufferData.enumerated() {
            let bgraComponent = component.offset % bgraPixel.channels;
            let isAlphaComponent = bgraComponent == bgraPixel.alphaComponent;
            guard !isAlphaComponent else {
                pixelIndex += 1
                continue
            }
            // Swizzle BGR -> RGB.
            let rgbIndex = pixelIndex * rgbPixelChannels + (bgraPixel.lastBgrComponent - bgraComponent)
            rgbBytes[rgbIndex] = component.element
        }
        if isModelQuantized { return Data(_: rgbBytes) }
        return Data(copyingBufferOf: rgbBytes.map { Float($0) / 255.0 })
    }
}

extension String {
    
    func fileName() -> String {
        return NSURL(fileURLWithPath: self).deletingPathExtension?.lastPathComponent ?? ""
    }
    
    func fileExtension() -> String {
        return NSURL(fileURLWithPath: self).pathExtension ?? ""
    }
}

// MARK: - Extensions
extension Data {
    /// Creates a new buffer by copying the buffer pointer of the given array.
    ///
    /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
    ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
    ///     data from the resulting buffer has undefined behavior.
    /// - Parameter array: An array with elements of type `T`.
    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
}

extension Array {
    /// Creates a new array from the bytes of the given unsafe data.
    ///
    /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
    ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
    ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
    /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
    ///     `MemoryLayout<Element>.stride`.
    /// - Parameter unsafeData: The data containing the bytes to turn into an array.
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
        #if swift(>=5.0)
        self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
        #else
        self = unsafeData.withUnsafeBytes {
            .init(UnsafeBufferPointer<Element>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
        #endif  // swift(>=5.0)
    }
}

extension CVPixelBuffer {
    /// Returns thumbnail by cropping pixel buffer to biggest square and scaling the cropped image
    /// to model dimensions.
    func resized(to size: CGSize ) -> CVPixelBuffer? {
        
        let imageWidth = CVPixelBufferGetWidth(self)
        let imageHeight = CVPixelBufferGetHeight(self)
        
        let pixelBufferType = CVPixelBufferGetPixelFormatType(self)
        
        assert(pixelBufferType == kCVPixelFormatType_32BGRA)
        
        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
        let imageChannels = 4
        
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        
        // Finds the biggest square in the pixel buffer and advances rows based on it.
        guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }
        
        // Gets vImage Buffer from input image
        var inputVImageBuffer = vImage_Buffer(data: inputBaseAddress, height: UInt(imageHeight), width: UInt(imageWidth), rowBytes: inputImageRowBytes)
        
        let scaledImageRowBytes = Int(size.width) * imageChannels
        guard  let scaledImageBytes = malloc(Int(size.height) * scaledImageRowBytes) else {
            return nil
        }
        
        // Allocates a vImage buffer for scaled image.
        var scaledVImageBuffer = vImage_Buffer(data: scaledImageBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: scaledImageRowBytes)
        
        // Performs the scale operation on input image buffer and stores it in scaled image buffer.
        let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &scaledVImageBuffer, nil, vImage_Flags(0))
        
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        
        guard scaleError == kvImageNoError else {
            return nil
        }
        
        let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in
            
            if let pointer = pointer {
                free(UnsafeMutableRawPointer(mutating: pointer))
            }
        }
        
        var scaledPixelBuffer: CVPixelBuffer?
        
        // Converts the scaled vImage buffer to CVPixelBuffer
        let conversionStatus = CVPixelBufferCreateWithBytes(nil, Int(size.width), Int(size.height), pixelBufferType, scaledImageBytes, scaledImageRowBytes, releaseCallBack, nil, nil, &scaledPixelBuffer)
        
        guard conversionStatus == kCVReturnSuccess else {
            
            free(scaledImageBytes)
            return nil
        }
        
        return scaledPixelBuffer
    }
    
}
