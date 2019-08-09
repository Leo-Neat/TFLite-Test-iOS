//
//  VideoScreenVC.swift
//  TFLite-Model-Test
//
//  Created by Leo Neat on 7/29/19.
//  Copyright © 2019 Leo Neat. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import CoreGraphics
import CoreMotion
import AudioToolbox


class VideoScreenVC: UIViewController{

    
    
    
    let photoOutput = AVCapturePhotoOutput()
    let captureSession = AVCaptureSession()
    var previewLayer:CALayer!
    var captureDevice:AVCaptureDevice!
    var isInterupted = false
    let semaphore = DispatchSemaphore(value: 1)
    var modelHandler:ModelHandler?
    var textLayer = CATextLayer() // A layer to draw the content of the detected text onto
    var timer = Timer() // Timer for the UI clearing
    var bbLayer = CAShapeLayer()
    var currentModel: ModelData?
    
    func clearLayer()
    {
        if (bbLayer.sublayers != nil){
            for layer in bbLayer.sublayers!{
                layer.removeFromSuperlayer()
            }
        }
    }
    
    func addBB(rect: CGRect, text: String, origImageWidth: Int, origImageHeight: Int){

        let rect = rect.applying(CGAffineTransform(scaleX: self.previewLayer.frame.width, y: self.previewLayer.frame.height))
        
        let bb = CAShapeLayer()
        bb.fillColor = UIColor.clear.cgColor
        bb.lineWidth = 2
        bb.strokeColor = UIColor.green.cgColor
        
        let myFrame = CGRect(x: rect.minX, y: rect.minY ,
                             width: (rect.maxX - rect.minX) ,
                             height: (rect.maxY - rect.minY))
        let rectPath = UIBezierPath(rect: myFrame)
        bb.path = rectPath.cgPath
        textLayer = CATextLayer()
        textLayer.string = text
        textLayer.fontSize = 20
        textLayer.frame = myFrame
        textLayer.foregroundColor = UIColor.black.cgColor
        bbLayer.addSublayer(bb)
        bbLayer.addSublayer(textLayer)
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        prepareCamera()
        semaphore.wait()
        isInterupted = false
        semaphore.signal()
        loadActiveModel()
    }
    
    // Loads the current configuration to the model to be tested and used
    func loadActiveModel() -> Void
    {
        
        do{
            try self.modelHandler = ModelHandler(currentModel: currentModel!, prevWidth: Float(self.previewLayer.frame.width), prevHeight: Float(self.previewLayer.frame.height))
        }catch(ModelFileNotFound.runtimeError( _))
        {
            print("Error, model file passed in does not exist")
            self.dismiss(animated: true, completion: nil)
        }catch(LabelFileNotFound.runtimeError( _))
        {
            print("Error, label file passed does not exist")
            self.dismiss(animated: true, completion: nil)
        }catch{
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        semaphore.wait()
        isInterupted = true
        semaphore.signal()
    }
    
    
    func prepareCamera() {
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        
        let avaliableDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back).devices
        
        captureDevice = avaliableDevices.first
        beginSession()
    }
    
    func beginSession(){
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(captureDeviceInput)
        }catch{
            print(error.localizedDescription)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer = previewLayer
        self.view.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.layer.frame
        captureSession.startRunning()
        if captureSession.canAddOutput(photoOutput){
            captureSession.addOutput(photoOutput)
        }
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]
        dataOutput.connection(with: .video)?.videoOrientation = AVCaptureVideoOrientation.portrait
        let cameraWorker1 = DispatchQueue(label: "cameraQ")
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(self, queue: cameraWorker1)
        if captureSession.canAddOutput(dataOutput){
            captureSession.addOutput(dataOutput)
        }
        captureSession.commitConfiguration()
    }
}

extension VideoScreenVC: AVCaptureVideoDataOutputSampleBufferDelegate{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = AVCaptureVideoOrientation.portrait
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        if(!(modelHandler?.getIsProcessing())!)
        {
            let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
            let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
            
            // Set up bounding box layer for display
            bbLayer.frame = previewLayer.frame
            bbLayer.removeFromSuperlayer()
            clearLayer()
            let results = modelHandler?.runModel(onFrame: pixelBuffer)
            
            if (results != nil)
            {
               
                var numFound = 0
                for result in (results!.inferences)
                {
                    
                    addBB(rect: result.rect, text: result.className, origImageWidth: imageWidth, origImageHeight: imageHeight)
                    
                    if(numFound > 10)
                    {
                        break
                    }
                    numFound += 1
                }
                
            
            }
            
        }
        DispatchQueue.main.async {
            self.textLayer.display()
            self.previewLayer.addSublayer(self.bbLayer)
        }
    }
    
    
    
    func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage
    {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let  imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!);
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!);
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!);
        let height = CVPixelBufferGetHeight(imageBuffer!);
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        
        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext.init(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context?.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        // Create an image object from the Quartz image
        let image = UIImage.init(cgImage: quartzImage!);
        
        return (image);
    }
}

import UIKit

extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0,
                                 y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -origin.y, y: -origin.x,
                            width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return rotatedImage ?? self
        }
        return self
    }
}
