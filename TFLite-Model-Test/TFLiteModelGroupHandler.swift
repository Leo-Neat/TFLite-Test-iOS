//
//  TFLiteModelHandler.swift
//  TFLite-Model-Test
//
//  Created by Leo Neat on 7/29/19.
//  Copyright © 2019 Leo Neat. All rights reserved.
//

import Foundation

// Error for when user trys to operate on an empty list
enum EmptyList: Error {
    case runtimeError(String)
}

// Error for when user trys to operate on an empty list
enum ModelNotFound: Error {
    case runtimeError(String)
}

class TFLiteModelGroupHandler
{
    
    // The values that are used in defaults as the key value pair
    static let NAME_TAG = "name"
    static let PATH_TAG = "path"
    static let DIMS_TAG = "dims"
    static let CONF_TAG = "confidence"
    static let LABELS_TAG = "labels"
   
    
    fileprivate var modelNames = [String]() // The name the model is refered to as
    fileprivate var modelInputDimentions = [Int]()  // The dimentions of the downsampled model
    fileprivate var modelPaths = [String]() // The Paths of the TF Lite files
    fileprivate var modelMinConfs = [Double]()  // The minimum accaptable model confdience scrores
    fileprivate var modelLabelsPath = [String]() // The path to the models label files
    fileprivate var currentModel = 0    // The index of the current model that will be used for detection
    fileprivate var listIsEmpty = true      // Determines if there is one model loaded or not
    fileprivate let EMPTY_MODEL_LIST_ERROR = "Can not operate on a handler with no models added."
    fileprivate let MODEL_NOT_FOUND_ERROR = "Error selected model was not found."
    fileprivate var numModels = 0

    init() {
    }
    
    // Saves the active model in user defaults to be loaded later
    func saveActiveModel() -> Void{
        UserDefaults.standard.set(modelNames[currentModel], forKey: TFLiteModelGroupHandler.NAME_TAG)
        UserDefaults.standard.set(modelInputDimentions[currentModel], forKey: TFLiteModelGroupHandler.DIMS_TAG)
        UserDefaults.standard.set(modelPaths[currentModel], forKey: TFLiteModelGroupHandler.PATH_TAG)
        UserDefaults.standard.set(modelMinConfs[currentModel], forKey: TFLiteModelGroupHandler.CONF_TAG)
        UserDefaults.standard.set(modelLabelsPath[currentModel], forKey: TFLiteModelGroupHandler.LABELS_TAG)
    }
    
    // Adds a model to the model list with the parameters that had been passed in
    func addModel(name: String, inputDim: Int, labelsPath: String ,modelPath: String, minConfidence: Double) -> Void {
        if(listIsEmpty){
            listIsEmpty = false
        }
        modelNames.append(name)
        modelInputDimentions.append(inputDim)
        modelPaths.append(modelPath)
        modelMinConfs.append(minConfidence)
        modelLabelsPath.append(labelsPath)
        numModels += 1
    }
    
    // Returns the total number of models in the list
    func getNumModels() -> Int {
        return numModels
    }
    
    // Returns true of there are no elements in the arrays
    func isEmpty() -> Bool {
        return  listIsEmpty
    }
    
    // Get a list of the names currently used by the handler
    func getModelNames() throws -> [String] {
        if(!isEmpty())
        {
            return modelNames
        }
        throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    
    // Gets the name of the active model
    func getCurrentModelName() throws -> String {
        if(!isEmpty()){
            return modelNames[currentModel]
        }
         throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    // Gets the label of the active model
    func getCurrentModelLabel() throws -> String {
        if(!isEmpty()){
            return modelLabelsPath[currentModel]
        }
        throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    
    // Gets the dimentions of the active model
    func getCurrentModelDim() throws -> Int {
        if(!isEmpty())
        {
            return modelInputDimentions[currentModel]
            
        }
       throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    // Gets the minimum accepted confidence of the active model
    func  getCurrentModelConf() throws -> Double {
        if(!isEmpty())
        {
            return modelMinConfs[currentModel]
        }
        throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    // gets the active models relitive modelPath
    func getCurrentModelPath() throws -> String {
        if(!isEmpty())
        {
            return modelPaths[currentModel]
        }
        throw EmptyList.runtimeError(EMPTY_MODEL_LIST_ERROR)
    }
    
    // Sets the active model to the one with the same name as passed in.
    // If active model does not exist an error is thrown
    func setActiveModel(modelName: String) throws -> Void {
        var counter = 0
        for mNameLoop in self.modelNames
        {
            if mNameLoop == modelName
            {
                self.currentModel = counter
                saveActiveModel()
                return
            }
            counter += 1
        }
        throw ModelNotFound.runtimeError(MODEL_NOT_FOUND_ERROR)
        
    }
}
