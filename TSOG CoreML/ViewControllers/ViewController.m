//
//  ViewController.m
//  TSOG CoreML
//
//  Created by Van Nguyen on 7/25/17.
//  Copyright © 2017 TheSchoolOfGames. All rights reserved.
//

#import "ViewController.h"
#import "Inceptionv3.h"
#import "Resnet50.h"
#import "CommonTools.h"

@import AVFoundation;
@import CoreML;
@import Vision;


@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    AVCaptureSession *session;

    dispatch_queue_t captureQueue;

    AVCaptureVideoPreviewLayer *previewLayer;
    CAGradientLayer *gradientLayer;
    NSArray *visionRequests;
    CGFloat recognitionThreshold;
    
    __weak IBOutlet UILabel *lbResult;
    __weak IBOutlet UIView *previewView;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self setupCamera];
    
    [self setupVisionAndCoreML];
    
    // Setup notification for device orientation change
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [notificationCenter addObserver:self
                           selector:@selector(deviceOrientationDidChange:)
                               name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Update preview layer and gradient layer size
    previewLayer.frame = previewView.bounds;
    gradientLayer.frame = previewView.bounds;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    AVCaptureVideoOrientation newOrientation;
    if (deviceOrientation == UIDeviceOrientationPortrait){
        newOrientation = AVCaptureVideoOrientationPortrait;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeLeft){
        newOrientation = AVCaptureVideoOrientationLandscapeRight;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight){
        newOrientation = AVCaptureVideoOrientationLandscapeLeft;
    } else {
        return;
    }
    
    AVCaptureConnection *previewLayerConnection = previewLayer.connection;
    if ([previewLayerConnection isVideoOrientationSupported])
    {
        [previewLayerConnection setVideoOrientation:newOrientation];
    }
}

#pragma mark - Init part
- (void)setupCamera {
    // Init session
    session = [[AVCaptureSession alloc] init];
    
    // Init Input device
    AVCaptureDevice *inputDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    if (!inputDevice) {
        NSLog(@"No video camera available");
        return;
    }
    
    // Create capture queue
    captureQueue = dispatch_queue_create( "captureQueue", DISPATCH_QUEUE_SERIAL );
    
    // add the preview layer
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [previewView.layer addSublayer:previewLayer];
    
    // add a slight gradient overlay so we can read the results easily
    gradientLayer = [[CAGradientLayer alloc] init];
    gradientLayer.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.7].CGColor];
    gradientLayer.locations = @[@(0.85), @(1.0)];
    [previewView.layer addSublayer:gradientLayer];
    
    // create the capture input and the video output
    NSError *error;
    AVCaptureDeviceInput *cameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputDevice error:&error];
    if (error) {
        [CommonTools showAlertInViewController:self withTitle:@"ERROR" message:@"Cannot connect to the camera"];
        NSLog(@"--->ERROR: %@", error);
        return;
    }
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoOutput setSampleBufferDelegate:self queue:captureQueue];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    videoOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    session.sessionPreset = AVCaptureSessionPresetHigh;
    
    // wire up the session
    [session addInput:cameraInput];
    [session addOutput:videoOutput];
    
    // make sure we are in portrait mode
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([connection isVideoOrientationSupported])
    {
        [self deviceOrientationDidChange:nil];
    }
    
    // Start the session
    [session startRunning];
}

- (void)setupVisionAndCoreML {
    NSError *error;
    VNCoreMLModel *inceptionv3Model = [VNCoreMLModel modelForMLModel:[[[Inceptionv3 alloc] init] model] error:&error];
    if (error) {
        [CommonTools showAlertInViewController:self withTitle:@"ERROR" message:@"Cannot access to MLModel"];
        NSLog(@"--->ERROR: %@", error);
        return;
    }
    
    VNCoreMLRequest *classificationRequest = [[VNCoreMLRequest alloc] initWithModel:inceptionv3Model completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        if (error) {
            NSLog(@"--->ERROR: %@", error);
            return;
        }
        
        if (!request.results) {
            NSLog(@"--->ERROR: No Results");
            return;
        }
        
        NSMutableArray *listObjects = [NSMutableArray array];
        for (VNClassificationObservation *observation in request.results) {
            if (observation.confidence > 0.3) {  // threshold
                [listObjects addObject:observation];
            }
        }
        
        NSString *resultText = @"";
        for (VNClassificationObservation *observation in listObjects) {
            NSLog(@"-------DETECT object:%@ threshold:%f", observation.identifier, observation.confidence);
            resultText = [NSString stringWithFormat:@"%@ %@(%f)", resultText, observation.identifier, observation.confidence];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            lbResult.text = resultText;
        });
    }];
    
    classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;
    visionRequests = @[classificationRequest];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    NSDictionary *requestOptions = [NSDictionary dictionaryWithObjectsAndKeys:CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil), VNImageOptionCameraIntrinsics, nil];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUpMirrored options:requestOptions];
    NSError *error;
    [imageRequestHandler performRequests:visionRequests error:&error];
    if (error) {
        [CommonTools showAlertInViewController:self withTitle:@"ERROR" message:@"imageRequestHandler error"];
        NSLog(@"--->ERROR: %@", error);
        return;
    }
}

@end
