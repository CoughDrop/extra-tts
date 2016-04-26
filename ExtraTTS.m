#import "ExtraTTS.h"
#import <Cordova/CDV.h>
#import "acattsioslicense.h"
#import "AcapelaLicense.h"
#import "AcapelaSpeech.h"
#import "ZipFileDownloader.h"

@interface ExtraTTS()
@property AcapelaSpeech *speech;
@property AcapelaLicense *licence;
@property NSURL *voicesFolderURL;
@property BOOL isReady;
@property ZipFileDownloader *zipFileDownloader;
@property CDVInvokedUrlCommand *speakTextCommand;
@property NSMutableDictionary *speakTextParams;
@property BOOL debug;
@end

@implementation ExtraTTS

- (void)pluginInitialize
{
    self.debug = false;
    if (self.debug) NSLog(@"ExtraTTS:init");
    
    // initialize the app, called only once. on Android I set the license here
    // call success when done, error if there were any problems
    
    self.isReady = false;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentsURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    self.voicesFolderURL = [documentsURL URLByAppendingPathComponent:@"coughdrop_voices"];
    if (self.voicesFolderURL) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.voicesFolderURL.path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:self.voicesFolderURL.path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        // mark the voices folder as not backed up
        [self addSkipBackupAttributeToItemAtURL:self.voicesFolderURL];
//        NSURL *backupUrl =[documentsURL URLByAppendingPathComponent:@"Backups"];
//        [self addSkipBackupAttributeToItemAtURL:backupUrl];
        [AcapelaSpeech setVoicesDirectoryArray:@[self.voicesFolderURL.path]];
    } else {
        self.isReady = false;
        return;
    }
    self.zipFileDownloader = [ZipFileDownloader new];
    
    // Setup Acapela license and load voices if any are downloaded
    self.licence = [[AcapelaLicense alloc] initLicense:[acattsioslicense license]
                                                  user:(unsigned int)[acattsioslicense userid]
                                                passwd:(unsigned int)[acattsioslicense password]];
    [self initializeAndLoadVoices];
    
    if (!self.licence) {
        self.isReady = false;
    } else {
        self.isReady = true;
    }
}

// https://developer.apple.com/library/ios/qa/qa1719/_index.html
- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL
{
    assert([[NSFileManager defaultManager] fileExistsAtPath: [URL path]]);
    
    NSError *error = nil;
    BOOL success = [URL setResourceValue:[NSNumber numberWithBool: YES]
                                  forKey: NSURLIsExcludedFromBackupKey error: &error];
    if(!success){
        NSLog(@"Error excluding %@ from backup %@", [URL lastPathComponent], error);
    }
    
    return success;
}

- (void)hashCheck:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:hashCheck");
    
    // just testing with reading in values from a hash object and returning a hash result
    NSDictionary* options = nil;
    NSMutableDictionary* result = [[NSMutableDictionary alloc]init];
    NSString* val = nil;
    CDVPluginResult* pluginResult = nil;
    
    if ([command.arguments count] > 0) {
        options = [command argumentAtIndex:0];
        val = [options objectForKey:@"val"];
        [result setObject:val forKey:@"result"];
        [result setObject:@"set" forKey:@"hash"];
        [result setObject:[NSNumber numberWithBool:YES] forKey:@"set"];
    }
    if(val != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"val not found"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)status:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:status");
    // return success({ready: true}) or error({ready:false}) depending on whether init has been called
    
    if (self.isReady) {
        [self sendOKWithCommand:command parameters:@{ @"ready" : @YES }];
    } else {
        [self sendErrorWithCommand:command parameters:@{ @"ready" : @NO }];
    }
}

- (void)getAvailableVoices:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:getAvailableVoices");
    // retrieve a list of voices found in the storage path on device using the library
    // result should be a json array of json objects with the following attributes:
    // {
    //    language: <voice.language>,
    //    locale: <voice.locale>,
    //    active: true,
    //    name: <voice_id>,
    //    voice_id: "acap:<voice_id>"
    // }
    // if any voices are retrieved, take the first 1 or 2 results and initialize/load them for speaking
    
    if (!self.isReady) {
        [self sendErrorWithCommand:command message:@"not ready"];
        return;
    }
    
    NSArray *voices = [self availableVoices];
    NSMutableArray *results = [NSMutableArray new];
    for (NSString *voice in voices) {
        NSDictionary *attributes = [AcapelaSpeech attributesForVoice:voice];
        [results addObject:@{
                             @"language" : attributes[AcapelaVoiceLanguage],
                             @"locale" : attributes[AcapelaVoiceLocaleIdentifier],
                             @"active" : @YES,
                             @"name" : voice,
                             @"voice_id" : [NSString stringWithFormat:@"acap:%@", voice]
                             }];
    }
    
    [self initializeAndLoadVoices];
    
    [self sendOKWithCommand:command array:results];
}

- (void)downloadVoice:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:downloadVoice");
    // receives a single argument which is a json object and downloads the object.voice_url attribute
    // and unzips its contents (a folder) into the storage path on device.
    // calls success multiple times, using:
    // [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    // except on the final completion callback. Success calls should pass a json object with the following attributes:
    // {
    //   percent: <0.0 - 1.0 percent finished>,
    //   done: <true only when completed, and setKeepCallback is not set>
    // }
    // for progress percent on Android I go from 0.0 to 0.75 while downloading (if you can't get the content length,
    // most of the files are around 50Mb), then from 0.75 to 1.0 for the unzipping process.
    // call error on any problems, preferably with a helpful error message. once this is completed, expect an immediate
    // follow-up call to getAvailableVoices
    
    if (!self.isReady) {
        [self sendErrorWithCommand:command message:@"not ready"];
        return;
    }
    if (self.zipFileDownloader.isDownloading) {
        [self sendErrorWithCommand:command message:@"already downloading a voice"];
        return;
    }
    
    NSDictionary *JSONArgument = [command argumentAtIndex:0];
    NSString *voiceURLPath = JSONArgument[@"voice_url"];
    if (voiceURLPath) {
        NSURL *voiceURL = [NSURL URLWithString:voiceURLPath];
        if (voiceURL) {
            __weak __typeof(self) weakSelf = self;
            [self.zipFileDownloader downloadfileAtURL:voiceURL
                                        andUnZipToURL:self.voicesFolderURL
                                        progressBlock:^(double progress, BOOL isCompleted) {
                                            NSDictionary *params = @{ @"percent" : @(progress),
                                                                      @"done" : @(isCompleted) };
                                            
                                            if (weakSelf.debug) NSLog(@"percent: %.2lf", progress);
                                            
                                            if (isCompleted) {
                                                [AcapelaSpeech refreshVoiceList];
                                                [weakSelf sendOKWithCommand:command parameters:params];
                                            } else {
                                                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
                                                pluginResult.keepCallback = @YES;
                                                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                                            }
                                        }
                                           errorBlock:^(NSString *errorMessage) {
                                               [weakSelf sendErrorWithCommand:command message:errorMessage];
                                           }];
            
            
            return;
        }
    }
    
    // send error if there we weren't able to get a url to download
    [self sendErrorWithCommand:command message:@"invalid download URL"];
}

- (void)deleteVoice:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:deleteVoice");
    // receives a single argument which is a json object and recursively deletes all files in the folder specified
    // by object.voice_dir. calls success on completion, error on any problems, prefereably with a helpful error message.
    // expect an immediate follow-up call to getAvailableVoices afterward.
    
    if (!self.isReady) {
        [self sendErrorWithCommand:command message:@"not ready"];
        return;
    }
    
    NSDictionary *JSONArgument = [command argumentAtIndex:0];
    NSString *voiceDir = JSONArgument[@"voice_dir"];
    NSString *voicePath = [[self.voicesFolderURL URLByAppendingPathComponent:voiceDir] path];
    
    // return success if there is no directory
    if (![[NSFileManager defaultManager] fileExistsAtPath:voicePath isDirectory:nil]) {
        [self sendOKWithCommand:command message:nil];
        return;
    }
    
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:voicePath error:&error];
    if (success) {
        [AcapelaSpeech refreshVoiceList];
        [self sendOKWithCommand:command message:nil];
    } else {
        [self sendErrorWithCommand:command message:error.localizedDescription];
    }
}

- (void)speakText:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:speakText");
    // receives a single argument which is a json object and uses it to generate text. the object looks like this:
    // {
    //   text: <text to speak>,
    //   voice_id: <voice_id to speak with>,
    //   pitch: <pitch value, not sure this is settable on ios>,
    //          on Android, the conversion is: int pitch = (int) Math.min(Math.max(pitchPercent * 100, 70), 130);
    //   rate: <rate value as a double, with 1.0 being the default>
    //          on Android, the conversion is: int rate = (int) Math.min(Math.max(ratePercent * 120, 50), 400);
    //   volume: <volume value as a double, with 1.0 being the default>
    //          Android doesn't support this, so I'm not sure what a good conversion would be..
    // }
    // if there is an error speaking text, error should be called. otherwise success should be called, but not until
    // the text has finished being spoken. I believe you'll be listening with a delegate to catch that event.
    // when speaking, make sure to add the vce=speaker=voice_id voice switch option to the beginning of the text.
    // on success, pass the following data:
    // {
    //   text: <unmodified spoken text>,
    //   voice_id: <voice_id>,
    //   pitch: <pitch>,
    //   rate: <rate>
    //   volume: <volume>
    //   modified_text: <modified text, including vce=speaker=voice_id switch option>,
    //   modified_rate: <computed rate value from 50 - 700>,
    //   modified_pitch: nil,
    //   modified_volume: <computed volume value from 15 - 200>
    // }
    
    if (!self.isReady) {
        [self sendErrorWithCommand:command message:@"not ready"];
        return;
    }
    if (self.speakTextCommand) {
        [self sendErrorWithCommand:command message:@"already speaking text"];
        return;
    }
    
    NSDictionary *JSONArgument = [command argumentAtIndex:0];
    
    float ratePercent = 1.0;
    NSNumber *rateNumber = JSONArgument[@"rate"];
    if (rateNumber) {
        ratePercent = rateNumber.floatValue;
    }
    // words to speak per minute (50 to 700). We max it out at 400
    float rate = MIN(MAX(ratePercent * 120, 50), 400);
    [self.speech setRate:rate];
    
    float pitchPercent = 1.0;
    NSNumber *pitchNumber = JSONArgument[@"pitch"];
    if (pitchNumber) {
        pitchPercent = pitchNumber.floatValue;
    }
    // Shaping value from 70 to 140. We max out at 130
    float pitch = MIN(MAX(pitchPercent * 100, 70), 130);
    [self.speech setVoiceShaping:pitch];
    
    float volumePercent = 1.0;
    NSNumber *volumeNumber = JSONArgument[@"volume"];
    if (volumeNumber) {
        volumePercent = volumeNumber.floatValue;
    }
    // From 15 to 200
    float volume = MIN(MAX(ratePercent * 190, 15), 200);
    [self.speech setVolume:volume];
    
    NSString *voiceId = JSONArgument[@"voice_id"];
    NSString *text = JSONArgument[@"text"];
    if (text) {
        if (voiceId) {
            NSString *prefix = @"acap:";
            if ([voiceId hasPrefix:prefix]) {
                voiceId = [voiceId stringByReplacingCharactersInRange:NSMakeRange(0, prefix.length) withString:@""];
            }
            NSString *modifiedText = [NSString stringWithFormat:@"\\vce=speaker=%@\\%@", voiceId, text];
            
            self.speakTextCommand = command;
            self.speakTextParams = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                   @"text" : text,
                                                                                   @"voice_id" : voiceId,
                                                                                   @"pitch" : @(pitchPercent),
                                                                                   @"rate" : @(ratePercent),
                                                                                   @"volume" : @(volumePercent),
                                                                                   @"modified_text" : modifiedText,
                                                                                   @"modified_rate" : @(rate),
                                                                                   @"modified_pitch" : @(pitch),
                                                                                   @"modified_volume" : @(volume)
                                                                                   }];
            
            [self.speech startSpeakingString:modifiedText];
            
            return;
        }
    }
    
    [self sendErrorWithCommand:command message:@"not enough information sent to speak text"];
}

- (void)stopSpeakingText:(CDVInvokedUrlCommand*)command
{
    if (self.debug) NSLog(@"ExtraTTS:stopSpeakingText");
    // stops the currently-speaking text, if any. keep in mind that if a text is stopped, its success callback from
    // speakText must be triggered, with an additional attribute set on the result object, object.interrupted = true.
    
    if (!self.isReady) {
        [self sendErrorWithCommand:command message:@"not ready"];
        return;
    }
    
    if (self.speakTextCommand && self.speakTextParams) {
        [self.speakTextParams setObject:@YES forKey:@"interrupted"];
        [self sendOKWithCommand:self.speakTextCommand parameters:self.speakTextParams];
        self.speakTextCommand = nil;
        self.speakTextParams = nil;
    }
    [self.speech stopSpeaking];
    [self sendOKWithCommand:command message:nil];
}

#pragma mark - AcapelaSpeechDelegate

- (void)speechSynthesizer:(AcapelaSpeech *)sender didFinishSpeaking:(BOOL)finishedSpeaking
{
    if (self.speakTextCommand && self.speakTextParams) {
        [self sendOKWithCommand:self.speakTextCommand parameters:self.speakTextParams];
        self.speakTextCommand = nil;
        self.speakTextParams = nil;
    }
}

- (void)speechSynthesizer:(AcapelaSpeech *)sender didFinishSpeaking:(BOOL)finishedSpeaking textIndex:(int)index
{
    
}

- (void)speechSynthesizer:(AcapelaSpeech *)sender willSpeakWord:(NSRange)characterRange ofString:(NSString *)string
{
    
}

- (void)speechSynthesizer:(AcapelaSpeech *)sender willSpeakViseme:(short)visemeCode
{
    
}

- (void)speechSynthesizer:(AcapelaSpeech *)sender didEncounterSyncMessage:(NSString *)errorMessage
{
    if (self.speakTextCommand) {
        [self sendErrorWithCommand:self.speakTextCommand message:errorMessage];
    }
}

#pragma mark - Acapela Helpers

- (NSArray *)availableVoices
{
    // If there is a file in the voice directory that isn't recognized,
    // [AcapelaSpeech availableVoices] returns a voice with the name "name"
    // and should be ignored since it causes errors. I keep seeing a file
    // called "__MACOSX" that causes this error
    
    NSArray *acapelaVoices = [AcapelaSpeech availableVoices];
    NSMutableArray *voices = [NSMutableArray new];
    for (NSString *voice in acapelaVoices) {
        if (![voice isEqualToString:@"name"]) {
            [voices addObject:voice];
        }
    }
    return voices;
}

- (void)initializeAndLoadVoices
{
    NSArray *voices = [self availableVoices];
    NSArray *voicesToAdd = [voices subarrayWithRange:NSMakeRange(0, MIN(voices.count, 2))];
    if (voicesToAdd.count > 0) {
        NSString *voicesString = [voices componentsJoinedByString:@","];
        if (self.speech) {
            [self.speech setVoice:voicesString];
        } else {
            self.speech = [[AcapelaSpeech alloc] initWithVoice:voicesString license:self.licence];
        }
        [self.speech setDelegate:self];
    }
}

#pragma mark - Cordova Helpers

- (void)sendOKWithCommand:(CDVInvokedUrlCommand *)command message:(NSString *)message
{
    [self sendResultWithStatus:CDVCommandStatus_OK command:command message:message];
}

- (void)sendOKWithCommand:(CDVInvokedUrlCommand *)command parameters:(NSDictionary *)parameters
{
    [self sendResultWithStatus:CDVCommandStatus_OK command:command parameters:parameters];
}

- (void)sendOKWithCommand:(CDVInvokedUrlCommand *)command array:(NSArray *)array
{
    [self sendResultWithStatus:CDVCommandStatus_OK command:command array:array];
}

- (void)sendErrorWithCommand:(CDVInvokedUrlCommand *)command message:(NSString *)message
{
    [self sendResultWithStatus:CDVCommandStatus_ERROR command:command message:message];
}

- (void)sendErrorWithCommand:(CDVInvokedUrlCommand *)command parameters:(NSDictionary *)parameters
{
    [self sendResultWithStatus:CDVCommandStatus_ERROR command:command parameters:parameters];
}

- (void)sendResultWithStatus:(CDVCommandStatus)status command:(CDVInvokedUrlCommand *)command message:(NSString *)message
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:status messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)sendResultWithStatus:(CDVCommandStatus)status command:(CDVInvokedUrlCommand *)command parameters:(NSDictionary *)parameters
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:status messageAsDictionary:parameters];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)sendResultWithStatus:(CDVCommandStatus)status command:(CDVInvokedUrlCommand *)command array:(NSArray *)array
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:status messageAsArray:array];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end