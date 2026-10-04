#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.recognitionLanguages = @[@"zh-Hans", @"en-US"];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithURL:[NSURL fileURLWithPath:@(argv[1])] options:@{}];
        NSError *error = nil;
        if (![handler performRequests:@[request] error:&error]) return 1;
        for (VNRecognizedTextObservation *observation in request.results) {
            NSString *text = [observation topCandidates:1].firstObject.string;
            if (text.length) puts(text.UTF8String);
        }
    }
    return 0;
}
