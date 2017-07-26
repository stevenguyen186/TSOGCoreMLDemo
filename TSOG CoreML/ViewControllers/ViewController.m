//
//  ViewController.m
//  TSOG CoreML
//
//  Created by Van Nguyen on 7/25/17.
//  Copyright © 2017 TheSchoolOfGames. All rights reserved.
//

#import "ViewController.h"
#import "Inceptionv3.h"
#import "CommonTools.h"
#import "Constants.h"
#import "IdentifiedObjectListViewController.h"
#import "SessionManager.h"

@import AVFoundation;
@import CoreML;
@import Vision;

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    AVCaptureSession *session;

    dispatch_queue_t captureQueue;

    AVCaptureVideoPreviewLayer *previewLayer;
    CAGradientLayer *gradientLayer;
    NSArray *visionRequests;

    __weak IBOutlet UILabel *lbResult;
    __weak IBOutlet UIView *previewView;
    __weak IBOutlet UILabel *animatedText;
    
    BOOL foundingObj;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // Setup Camera
    [self setupCamera];
    
    // Setup CoreML and Vision
    [self setupVisionAndCoreML];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Setup observer
    [self setupObserver];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self deviceOrientationDidChange:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Remove observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - Button Handler
- (IBAction)btnGotoListClicked:(id)sender {
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    IdentifiedObjectListViewController *iOLVC = [sb instantiateViewControllerWithIdentifier:@"IdentifiedObjectListViewController"];
    [self.navigationController pushViewController:iOLVC animated:YES];
}

#pragma mark - Update preview layer when orientation changed
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
        // Do nothing
        return;
    }
    
    AVCaptureConnection *previewLayerConnection = previewLayer.connection;
    if ([previewLayerConnection isVideoOrientationSupported])
    {
        [previewLayerConnection setVideoOrientation:newOrientation];
    }
}

#pragma mark - Setup Camera
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

#pragma mark - Setup Camera
- (void)setupVisionAndCoreML {
    // Read MLModel
    NSError *error;
    VNCoreMLModel *inceptionv3Model = [VNCoreMLModel modelForMLModel:[[[Inceptionv3 alloc] init] model] error:&error];
    if (error) {
        [CommonTools showAlertInViewController:self withTitle:@"ERROR" message:@"Cannot access to MLModel"];
        NSLog(@"--->ERROR: %@", error);
        return;
    }
    
    // Create request to classify object
    VNCoreMLRequest *classificationRequest = [[VNCoreMLRequest alloc] initWithModel:inceptionv3Model completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        // Handle the response
        
        // Check found object
        if (foundingObj) {
            return;
        }
        
        // Check error
        if (error) {
            NSLog(@"--->ERROR: %@", error);
            return;
        }
        
        if (!request.results) {
            NSLog(@"--->ERROR: No Results");
            return;
        }
        
        // Just get first object
        VNClassificationObservation *firstObj = [request.results firstObject];
        if (firstObj.confidence > kRecognitionThreshold) {
            // Found object
            [self handleFoundObject:firstObj];
        }
    }];
    
    classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;
    visionRequests = @[classificationRequest];
}

#pragma mark - Setup Observer
- (void)setupObserver {
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                           selector:@selector(deviceOrientationDidChange:)
                               name:UIDeviceOrientationDidChangeNotification object:nil];
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

#pragma mark - Handle found object
- (void)handleFoundObject:(VNClassificationObservation *)obj {
    // Found object
    foundingObj = YES;
    
    // analyze string
    NSString *fullName = obj.identifier;
    NSArray *nameArray = [fullName componentsSeparatedByString:@", "];
    
    if (nameArray.count == 0) {
        return;
    }
    // just get first name
    NSString *identifiedObj = [CommonTools capitalizeFirstLetterOnlyOfString:nameArray[0]];
    
    if ([[SessionManager sharedInstance] addIdentifiedObject:identifiedObj]) {
        // Show text on screen
        dispatch_async(dispatch_get_main_queue(), ^{
            lbResult.text = identifiedObj;
            [self showAnimatedString:identifiedObj];
        });
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            foundingObj = NO;
        });
    } else {
        foundingObj = NO;
    }
}

- (void)showAnimatedString:(NSString *)animatedString {
    CGSize windowSize = [UIScreen mainScreen].bounds.size;
    
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    
    UIView *backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowSize.width, windowSize.height)];
    CGRect oldFrame = animatedText.frame;
    UILabel *animatedLabel = [[UILabel alloc] initWithFrame:oldFrame];
    animatedLabel.text = animatedString;
    animatedLabel.textColor = [UIColor whiteColor];
    [animatedLabel setFont:[UIFont boldSystemFontOfSize:30.0]];
    [animatedLabel setMinimumScaleFactor:0.2];
    animatedLabel.textAlignment = NSTextAlignmentCenter;
    [backgroundView addSubview:animatedLabel];
    [window addSubview:backgroundView];
    
    // animation
    backgroundView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    CGFloat minWidth = 50.0;
    CGFloat maxWidth = 300.0;
    animatedLabel.frame = CGRectMake((windowSize.width - minWidth)/2, (windowSize.height - 80.0)/2, minWidth, 80.0);
    [UIView animateWithDuration:0.3 animations:^{
        backgroundView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        animatedLabel.frame = CGRectMake((windowSize.width - maxWidth)/2, (windowSize.height - 80.0)/2, maxWidth, 80.0);
    } completion:^(BOOL finished) {
        if (finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [backgroundView removeFromSuperview];
            });
        }
    }];
}

@end
