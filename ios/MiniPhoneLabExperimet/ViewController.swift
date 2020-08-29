//
//  ViewController.swift
//  MiniPhoneLabExperimet
//
//  Created by Eyal Cidon on 8/25/20.
//  Copyright © 2020 Eyal Cidon. All rights reserved.
//

import UIKit
import AVFoundation


class ViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate, AVCapturePhotoCaptureDelegate {

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var captureImageView: UIImageView!
    var captureSession: AVCaptureSession!
    var stillImageOutput: AVCapturePhotoOutput!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private let SERVER_IP_PORT:String = "http://192.168.1.180:8080/"
    
    func setupLivePreview() {
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        
        videoPreviewLayer.videoGravity = .resizeAspect
        videoPreviewLayer.connection?.videoOrientation = .portrait
        previewView.layer.addSublayer(videoPreviewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { //[weak self] in
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.videoPreviewLayer.frame = self.previewView.bounds
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break
            case .notDetermined: // The user has not yet been asked for camera access.
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if !granted {
                        print("Camera access not granted")
                        return
                    }
                }
            case .denied:
                print("Camera access denied")
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if !granted {
                        print("Camera access not granted")
                        return
                    }
                }
                return
            case .restricted:
                print("Camera access restricted")
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if !granted {
                        print("Camera access not granted")
                        return
                    }
                }
                return
            @unknown default:
                return
        }
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
            else {
                print("Unable to access back camera!")
                return
        }
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            stillImageOutput = AVCapturePhotoOutput()
            
            if captureSession.canAddInput(input) && captureSession.canAddOutput(stillImageOutput) {
                captureSession.addInput(input)
                captureSession.addOutput(stillImageOutput)
                setupLivePreview()
            }
        }
        catch let error  {
            print("Error Unable to initialize back camera:  \(error.localizedDescription)")
        }
    }

    var fileList: Array<String>?
    @IBAction func startExperiment(_ sender: Any) {
        self.fileList = getFileList()
        run()
    }
        
    
    func getFileList() -> Array<String> {
        let url = URL(string: "\(self.SERVER_IP_PORT)list")
        guard let requestUrl = url else { fatalError() }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var fileList:Array<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error took place \(error)")
                return
            }
            if let response = response as? HTTPURLResponse {
                print("Response HTTP Status code: \(response.statusCode)")
            }
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                print("Response data string:\n \(dataString)")
                let decoder = JSONDecoder()
                fileList = try! decoder.decode([String].self, from: data)
                semaphore.signal()
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .distantFuture)
        return fileList
    }
    
    var index:Int = 0

    func run() {
        self.index = 0
        takeScreenPhoto()
    }
    
    var file:String = ""
    func takeScreenPhoto() {
        let semaphore = DispatchSemaphore(value: 0)
        // request server to display image
        self.file = fileList![self.index]
        print("Requesting File:  \(file)\n")
        let url = URL(string: "\(self.SERVER_IP_PORT)\(file)")
        guard let requestUrl = url else { fatalError() }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error took place \(error)")
                return
            }
            if let response = response as? HTTPURLResponse {
                print("Response HTTP Status code: \(response.statusCode)")
                semaphore.signal()
            }
        }
        task.resume()
         _ = semaphore.wait(timeout: .distantFuture)
        
        guard let availableRawFormat = self.stillImageOutput.availableRawPhotoPixelFormatTypes.first else { return }
        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: availableRawFormat, processedFormat: [AVVideoCodecKey : AVVideoCodecType.hevc])
        self.stillImageOutput.capturePhoto(with: photoSettings, delegate: self)
        
    }
    
    var rawImageFileData: Data?
    var compressedFileData: Data?
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if photo.isRawPhoto {
            self.rawImageFileData = photo.fileDataRepresentation()!
        } else {
            self.compressedFileData = photo.fileDataRepresentation()!
            let image = UIImage(data: self.compressedFileData!)
            captureImageView.image = image
        }
    }
        
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        // upload raw (DNG) image
        let newFile = self.file.replacingOccurrences(of: "jpg", with: "dng")
        print("Posting File:  \(newFile)\n")
        let fileUrl = URL(string: "\(self.SERVER_IP_PORT)\(newFile)")
        guard let postUrl = fileUrl else { fatalError() }
        var post = URLRequest(url: postUrl)
        post.httpMethod = "POST"
        guard let rawData = self.rawImageFileData else { return }
        post.httpBody = rawData
        post.setValue("\(rawData.count)", forHTTPHeaderField: "Content-Length")
        let postTask = URLSession.shared.dataTask(with: post) { (_, postResponse, postError) in
            if let postError = postError {
                print("Post error took place \(postError)")
                return
            }
            if let postResponse = postResponse as? HTTPURLResponse {
                print("Post response HTTP Status code: \(postResponse.statusCode)")
                semaphore.signal()
            }
        }
        postTask.resume()
        _ = semaphore.wait(timeout: .distantFuture)

        // upload compressed (HEIC) image
        let newCompFile = self.file.replacingOccurrences(of: "jpg", with: "heic")
        print("Posting File:  \(newCompFile)\n")
        let compFileUrl = URL(string: "\(self.SERVER_IP_PORT)\(newCompFile)")
        guard let postCompUrl = compFileUrl else { fatalError() }
        var postComp = URLRequest(url: postCompUrl)
        postComp.httpMethod = "POST"
        guard let compData = self.compressedFileData else { return }
        postComp.httpBody = compData
        postComp.setValue("\(compData.count)", forHTTPHeaderField: "Content-Length")
        let postCompTask = URLSession.shared.dataTask(with: postComp) { (_, postResponse, postError) in
            if let postError = postError {
                print("Post error took place \(postError)")
                return
            }
            if let postResponse = postResponse as? HTTPURLResponse {
                print("Post response HTTP Status code: \(postResponse.statusCode)")
                semaphore.signal()
            }
        }
        postCompTask.resume()
        _ = semaphore.wait(timeout: .distantFuture)

        self.index += 1
        if self.index < self.fileList!.count {
            takeScreenPhoto()
        } else {
            return
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.captureSession.stopRunning()
    }
}

