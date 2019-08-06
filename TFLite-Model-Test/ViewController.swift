//
//  ViewController.swift
//  TFLite-Model-Test
//
//  Created by Leo Neat on 7/29/19.
//  Copyright © 2019 Leo Neat. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {
    
    var modelHandler = TFLiteModelGroupHandler() // Holds all of the possable tensorflow models to be tested
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return modelHandler.getNumModels()
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        do{
            return try modelHandler.getModelNames()[row]
        }catch EmptyList.runtimeError(let errorMessage){
            print(errorMessage)
        } catch{
            print("Unknown error")
        }
        return ""
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
       
        do {
            print("Setting active model")
           try modelHandler.setActiveModel(modelName: modelHandler.getModelNames()[row])
        }catch ModelNotFound.runtimeError(let errorMessage){
            print(errorMessage)
        }catch{
            print("Unknown Error")
        }
    }
    

    @IBOutlet weak var pickerView: UIPickerView!
    override func viewDidLoad() {

        /*
            ****************************************
            WHERE TO ADD NEW MODELS AND THERE CONFIG
            ****************************************
        */
        modelHandler.addModel(name: "Blurry Text: Total Text", inputDim: 400, labelsPath: "text-labels.txt", modelPath: "text_detector_blur.tflite", minConfidence: 0.50)
        modelHandler.addModel(name: "Exit Sign Detector", inputDim: 300, labelsPath: "exit-labels.txt", modelPath: "exit_sign_detector.tflite", minConfidence: 0.70)
        do{
            try modelHandler.setActiveModel(modelName: "Blurry Text: Total Text")
        }catch
        {
            print("Error initalizing active model")
        }
        
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
}

