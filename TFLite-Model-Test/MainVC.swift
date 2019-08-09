//
//  ViewController.swift
//  TFLite-Model-Test
//
//  Created by Leo Neat on 7/29/19.
//  Copyright © 2019 Leo Neat. All rights reserved.
//

import UIKit


class MainVC: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {
    
    var selectedModel = 0
    
    var modelArray = [ModelData]() // Holds all of the possable tensorflow models to be tested
    var confArray = [Float]()
    var selectedConf = 0.0
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
   
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if (pickerView.tag == 1){
            return modelArray.count
        }
        else{
            return confArray.count
        }
        
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if(pickerView.tag == 1)
        {
            return modelArray[row].name
        }
        else
        {
            return String(confArray[row])
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if(pickerView.tag == 1)
        {
            selectedModel = row
        }
        else
        {
            selectedConf = Double(confArray[row])
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if(segue.identifier == "MainToVideoSegue"){
            print("Setting model in videoVC")
            let videoVC = segue.destination as! VideoScreenVC
            modelArray[selectedModel].minConf = selectedConf
            videoVC.currentModel = modelArray[selectedModel]
        }
    }
    
    @IBOutlet weak var confPickerView: UIPickerView!
    
    @IBOutlet weak var pickerView: UIPickerView!

    
    override func viewDidLoad() {

        super.viewDidLoad()
        // Do any additional setup after loading the view.
        /*
         ****************************************
         WHERE TO ADD NEW MODELS AND THERE CONFIG
         ****************************************
         */
        
        modelArray.append(ModelData(name: "Blurry Text: Total Text", modelPath: "text_detector_blur.tflite", labelPath: "text-labels.txt", modelDim: 400, minConf:  0.50 ))
        modelArray.append(ModelData(name: "Exit Sign Detector", modelPath: "exit_sign_detector.tflite", labelPath: "exit-labels.txt", modelDim: 300, minConf:  0.70 ))
        modelArray.append(ModelData(name: "300 Inception Exit Sign Detector", modelPath: "exit_inception_48k_detector.tflite", labelPath: "exit-labels.txt", modelDim: 300, minConf:  0.50 ))
        for i in stride(from: 0, to: 1, by: 0.01)
        {
            confArray.append(Float(i))
        }
    }
}

